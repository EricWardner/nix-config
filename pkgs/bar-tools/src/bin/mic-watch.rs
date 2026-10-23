//! waybar `custom/mic`: prints whether the microphones are live and whether
//! push-to-talk is armed, whenever either changes. "Muted" means every
//! capture source is muted: apps can pin their stream to a non-default
//! source, so the default's state alone can lie.

use std::convert::Infallible;
use std::os::fd::OwnedFd;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use bar_tools::inotify::{self, WatchFlags};
use bar_tools::pa::{self, Conn, Frame};
use bar_tools::ptt;
use bar_tools::waybar::Emitter;
use pulseaudio::protocol::{Command, SourceInfoList, SubscriptionMask};
use rustix::event::{PollFd, PollFlags};

/// An event burst ends after this much quiet, or after `SETTLE_MAX`. Arming
/// push-to-talk goes through the same wait, so pttd's mutes land before
/// the first render instead of a "talking" flicker.
const SETTLE: Duration = Duration::from_millis(15);
const SETTLE_MAX: Duration = Duration::from_millis(100);
/// A source list that fails to decode (the protocol crate rejects the state
/// of a device mid-hotplug) is retried this often.
const RETRY: Duration = Duration::from_secs(1);
const RECONNECT: Duration = Duration::from_secs(2);

#[derive(Clone, Copy)]
enum Mics {
    None,
    AllMuted,
    Live,
}

/// Push-to-talk's armed flag (see [`bar_tools::ptt`]), watched with inotify.
struct Armed {
    file: Option<PathBuf>,
    events: Option<OwnedFd>,
}

impl Armed {
    fn watch() -> Armed {
        let Some(dir) = ptt::dir() else {
            bar_tools::warn!("mic-watch: XDG_RUNTIME_DIR unset; push-to-talk state unknown");
            return Armed {
                file: None,
                events: None,
            };
        };
        let flags =
            WatchFlags::CREATE | WatchFlags::DELETE | WatchFlags::MOVED_TO | WatchFlags::MOVED_FROM;
        let events = std::fs::create_dir_all(&dir)
            .and_then(|()| inotify::watch(&dir, flags).map_err(std::io::Error::from))
            .inspect_err(|e| {
                bar_tools::warn!("mic-watch: can't watch {}: {e}", dir.display());
            })
            .ok();
        Armed {
            file: Some(dir.join(ptt::ARMED)),
            events,
        }
    }

    fn is_armed(&self) -> bool {
        self.file.as_ref().is_some_and(|f| f.exists())
    }
}

fn main() {
    let mut out = Emitter::default();
    let armed = Armed::watch();
    loop {
        let Err(err) = run(&mut out, &armed);
        bar_tools::warn!("mic-watch: {err}; reconnecting");
        out.emit("󰍭", "Audio server unavailable", "muted");
        std::thread::sleep(RECONNECT);
    }
}

fn run(out: &mut Emitter, armed: &Armed) -> Result<Infallible, pa::Error> {
    let mut conn = Conn::connect("mic-watch")?;
    conn.request_ack(&Command::Subscribe(SubscriptionMask::SOURCE))?;

    let mut mics: Option<Mics> = None;
    let mut retry_at: Option<Instant> = None;
    let mut dirty = true;
    loop {
        if dirty {
            conn.drain_burst(SETTLE, SETTLE_MAX)?;
            match query(&mut conn) {
                Ok(m) => {
                    mics = Some(m);
                    retry_at = None;
                }
                Err(pa::Error::Decode(e)) => {
                    if retry_at.is_none() {
                        bar_tools::warn!("mic-watch: {e}; retrying every {RETRY:?}");
                    }
                    retry_at = Some(Instant::now() + RETRY);
                }
                Err(e) => return Err(e),
            }
            dirty = conn.missed_events();
            if let Some(mics) = mics {
                render(out, mics, armed.is_armed());
            }
            if dirty {
                continue;
            }
        }

        let timeout = retry_at.map(|t| t.saturating_duration_since(Instant::now()));
        let (audio_ready, armed_changed) = {
            // second slot unused (and never polled) without an armed watch
            let mut fds = [
                PollFd::new(&conn, PollFlags::IN),
                PollFd::new(&conn, PollFlags::empty()),
            ];
            let mut n = 1;
            if let Some(fd) = &armed.events {
                fds[1] = PollFd::new(fd, PollFlags::IN);
                n = 2;
            }
            bar_tools::poll(&mut fds[..n], timeout)?;
            let ready = |i: usize| fds[..n].get(i).is_some_and(|f| !f.revents().is_empty());
            (ready(0), ready(1))
        };
        if let (true, Some(fd)) = (armed_changed, &armed.events) {
            inotify::drain(fd);
            dirty = true;
        }
        if audio_ready && matches!(conn.read_frame()?, Frame::Event(_)) {
            dirty = true;
        }
        if retry_at.is_some_and(|t| Instant::now() >= t) {
            dirty = true;
        }
    }
}

/// The capture sources' combined mute state; sink monitors don't count.
fn query(conn: &mut Conn) -> Result<Mics, pa::Error> {
    let sources: SourceInfoList = conn.request(&Command::GetSourceInfoList)?;
    let mut mics = sources
        .iter()
        .filter(|s| s.monitor_of_sink_index.is_none())
        .peekable();
    Ok(if mics.peek().is_none() {
        Mics::None
    } else if mics.all(|s| s.muted) {
        Mics::AllMuted
    } else {
        Mics::Live
    })
}

fn render(out: &mut Emitter, mics: Mics, armed: bool) {
    let (text, tooltip, class) = match (mics, armed) {
        (Mics::None, _) => ("󰍭", "No microphones", "muted"),
        (Mics::AllMuted, true) => (
            "󰍭",
            "Push-to-talk armed — hold Right Alt to talk",
            "ptt-muted",
        ),
        (Mics::Live, true) => ("󰍬", "Push-to-talk — talking", "ptt-active"),
        (Mics::AllMuted, false) => ("󰍭", "Mic muted (left-click for push-to-talk)", "muted"),
        (Mics::Live, false) => ("󰍬", "Mic live (left-click for push-to-talk)", "on"),
    };
    out.emit(text, tooltip, class);
}
