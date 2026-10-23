//! pttd: push-to-talk. While armed (see [`bar_tools::ptt`] and `micctl
//! ptt`), every microphone stays muted except while Right Alt is held.
//! Arming mutes them all, disarming unmutes them all, and a microphone that
//! appears while armed is muted at once. pttd acts on those changes only: it
//! doesn't fight a mic unmuted by hand (e.g. in pavucontrol) while armed;
//! that lasts until the next key release.
//!
//! Usage: pttd [KEYBOARD]. The key is read straight from that evdev device
//! (default: keyd's virtual keyboard, so real keyboards coming and going
//! never matter), and mutes go to the audio server in one write. Anything
//! that could hide a key release (dropped events, the keyboard vanishing,
//! startup) counts as the key being up: pttd fails muted.

use std::convert::Infallible;
use std::os::fd::OwnedFd;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use bar_tools::inotify::{self, WatchFlags};
use bar_tools::pa::{self, Conn, Frame};
use bar_tools::ptt;
use pulseaudio::protocol::{
    Command, SubscriptionEventFacility, SubscriptionEventType, SubscriptionMask,
};
use rustix::event::{PollFd, PollFlags};
use rustix::fs::{Mode, OFlags};
use rustix::io::Errno;

const DEFAULT_KEYBOARD: &str = "/dev/input/by-id/keyd-virtual-keyboard-event-kbd";
const RECONNECT: Duration = Duration::from_secs(2);
/// A hotplugged device can add several sources at once: wait for this much
/// quiet (at most `SETTLE_MAX`) before reloading the list.
const SETTLE: Duration = Duration::from_millis(15);
const SETTLE_MAX: Duration = Duration::from_millis(100);
/// A source list that fails to decode is retried this often.
const RETRY: Duration = Duration::from_secs(1);

/// `struct input_event` on 64-bit Linux: a timeval, then type, code, value.
const EVENT_SIZE: usize = 24;
const EV_SYN: u16 = 0;
const EV_KEY: u16 = 1;
const SYN_DROPPED: u16 = 3;
const KEY_RIGHTALT: u16 = 100;
const KEY_REPEAT: i32 = 2;

struct Ptt {
    armed_file: PathBuf,
    keyboard_path: PathBuf,
    keyboard: Option<OwnedFd>,
    /// Watches the armed flag's directory and the keyboard's directory.
    notify: OwnedFd,
    armed: bool,
    talking: bool,
}

impl Ptt {
    fn open_keyboard(&mut self) {
        if self.keyboard.is_some() {
            return;
        }
        let flags = OFlags::RDONLY | OFlags::NONBLOCK | OFlags::CLOEXEC;
        match rustix::fs::open(&self.keyboard_path, flags, Mode::empty()) {
            Ok(fd) => {
                bar_tools::warn!("pttd: reading {}", self.keyboard_path.display());
                self.keyboard = Some(fd);
            }
            Err(Errno::NOENT) => {} // inotify says when it appears
            Err(e) => bar_tools::warn!("pttd: {}: {e}", self.keyboard_path.display()),
        }
    }

    /// Apply the queued key events to `talking`. On losing the keyboard,
    /// treat the key as released and look for the device again.
    fn read_keys(&mut self) {
        let Some(fd) = &self.keyboard else { return };
        let mut buf = [0u8; EVENT_SIZE * 64];
        let gone = loop {
            match rustix::io::read(fd, &mut buf) {
                Ok(0) => break true,
                Ok(n) => {
                    for event in buf[..n].as_chunks::<EVENT_SIZE>().0 {
                        let kind = u16::from_ne_bytes([event[16], event[17]]);
                        let code = u16::from_ne_bytes([event[18], event[19]]);
                        let value =
                            i32::from_ne_bytes([event[20], event[21], event[22], event[23]]);
                        match (kind, code) {
                            (EV_KEY, KEY_RIGHTALT) if value != KEY_REPEAT => {
                                self.talking = value != 0;
                            }
                            // the kernel dropped events, maybe the release
                            (EV_SYN, SYN_DROPPED) => self.talking = false,
                            _ => {}
                        }
                    }
                }
                Err(Errno::AGAIN) => break false,
                Err(Errno::INTR) => {}
                Err(_) => break true, // ENODEV: the device went away
            }
        };
        if gone {
            bar_tools::warn!("pttd: lost {}", self.keyboard_path.display());
            self.keyboard = None;
            self.talking = false;
            self.open_keyboard(); // its replacement may already be there
        }
    }
}

fn main() {
    let keyboard_path = std::env::args_os()
        .nth(1)
        .map_or_else(|| PathBuf::from(DEFAULT_KEYBOARD), PathBuf::from);
    let mut ptt = match setup(keyboard_path) {
        Ok(ptt) => ptt,
        Err(e) => {
            bar_tools::warn!("pttd: {e}");
            std::process::exit(1);
        }
    };
    ptt.open_keyboard();
    loop {
        let Err(err) = run(&mut ptt);
        bar_tools::warn!("pttd: {err}; reconnecting");
        std::thread::sleep(RECONNECT);
    }
}

fn setup(keyboard_path: PathBuf) -> std::io::Result<Ptt> {
    let dir = ptt::dir().ok_or_else(|| std::io::Error::other("XDG_RUNTIME_DIR unset"))?;
    std::fs::create_dir_all(&dir)?;
    let notify = inotify::watch(
        &dir,
        WatchFlags::CREATE | WatchFlags::DELETE | WatchFlags::MOVED_TO | WatchFlags::MOVED_FROM,
    )?;
    let keyboard_dir = keyboard_path.parent().unwrap_or(Path::new("/"));
    inotify::add(
        &notify,
        keyboard_dir,
        WatchFlags::CREATE | WatchFlags::MOVED_TO,
    )?;
    let armed_file = dir.join(ptt::ARMED);
    Ok(Ptt {
        armed: armed_file.exists(),
        armed_file,
        keyboard_path,
        keyboard: None,
        notify,
        talking: false,
    })
}

fn run(ptt: &mut Ptt) -> Result<Infallible, pa::Error> {
    let mut conn = Conn::connect("pttd")?;
    conn.request_ack(&Command::Subscribe(SubscriptionMask::SOURCE))?;

    // On (re)connect, reassert push-to-talk once the list loads: the server
    // may have restarted, and the flag may have changed while we were away.
    let was_armed = ptt.armed;
    ptt.armed = ptt.armed_file.exists();
    let mut reassert = ptt.armed || was_armed;

    let mut sources: Vec<u32> = Vec::new();
    // The full list loads now, whenever sources come or go, and again after
    // a decode error.
    let mut reload_at = Some(Instant::now());
    let mut failing = false;
    loop {
        if reload_at.is_some_and(|t| Instant::now() >= t) {
            conn.drain_burst(SETTLE, SETTLE_MAX)?;
            match conn.capture_sources() {
                Ok(list) => {
                    let fresh: Vec<u32> = (list.iter().map(|s| s.index))
                        .filter(|i| !sources.contains(i))
                        .collect();
                    sources = list.iter().map(|s| s.index).collect();
                    // sources that came or went during the query: look again
                    reload_at = conn.missed_events().then(Instant::now);
                    failing = false;
                    if std::mem::take(&mut reassert) {
                        set_all(&mut conn, &sources, ptt.armed && !ptt.talking)?;
                    } else if ptt.armed && !ptt.talking {
                        set_all(&mut conn, &fresh, true)?; // new mics start muted
                    }
                }
                Err(pa::Error::Decode(e)) => {
                    if !std::mem::replace(&mut failing, true) {
                        bar_tools::warn!("pttd: {e}; retrying every {RETRY:?}");
                    }
                    reload_at = Some(Instant::now() + RETRY);
                }
                Err(e) => return Err(e),
            }
        }

        let timeout = reload_at.map(|t| t.saturating_duration_since(Instant::now()));
        let (audio_ready, notify_ready, keys_ready) = {
            // third slot unused (and never polled) without a keyboard
            let mut fds = [
                PollFd::new(&conn, PollFlags::IN),
                PollFd::new(&ptt.notify, PollFlags::IN),
                PollFd::new(&ptt.notify, PollFlags::empty()),
            ];
            let mut n = 2;
            if let Some(fd) = &ptt.keyboard {
                fds[2] = PollFd::new(fd, PollFlags::IN);
                n = 3;
            }
            bar_tools::poll(&mut fds[..n], timeout)?;
            let ready = |i: usize| fds[..n].get(i).is_some_and(|f| !f.revents().is_empty());
            (ready(0), ready(1), ready(2))
        };

        if keys_ready {
            let was = ptt.talking;
            ptt.read_keys();
            if ptt.armed && ptt.talking != was {
                set_all(&mut conn, &sources, !ptt.talking)?;
            }
        }
        if notify_ready {
            inotify::drain(&ptt.notify);
            ptt.open_keyboard();
            let armed = ptt.armed_file.exists();
            if armed != ptt.armed {
                ptt.armed = armed;
                // arming mutes (unless the key is held); disarming unmutes
                set_all(&mut conn, &sources, armed && !ptt.talking)?;
            }
        }
        if audio_ready {
            match conn.read_frame()? {
                Frame::Event(event)
                    if event.event_facility == SubscriptionEventFacility::Source
                        && event.event_type != SubscriptionEventType::Changed =>
                {
                    reload_at.get_or_insert_with(Instant::now);
                }
                Frame::Error { seq, error } => {
                    bar_tools::warn!("pttd: request {seq} failed: {error:?}");
                }
                _ => {} // mute acks, and Changed events: pttd only acts on its own triggers
            }
        }
    }
}

/// Set every microphone's mute in one write. The acks are read by the main
/// loop, which logs any failures.
fn set_all(conn: &mut Conn, sources: &[u32], mute: bool) -> Result<(), pa::Error> {
    for &index in sources {
        conn.queue_source_mute(index, mute)?;
    }
    conn.flush()
}
