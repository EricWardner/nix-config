//! waybar's two screen-recording modules, from screen-record's state file
//! (see [`bar_tools::record`]), whenever it changes:
//!
//! - `record-watch button`, `custom/record` beside the webcam: record.circle
//!   to start, stop.circle while selecting, counting down or recording.
//! - `record-watch status`, `custom/recording` after the clock: hidden when
//!   idle, otherwise the active state, with a timer while recording.
//!
//! Changes arrive through inotify. The status module also ticks once a
//! second while recording (the timer), and sleeps otherwise.

use std::fs;
use std::os::fd::OwnedFd;
use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use bar_tools::inotify::{self, WatchFlags};
use bar_tools::record;
use bar_tools::sf;
use bar_tools::waybar::{self, Emitter};
use rustix::event::{PollFd, PollFlags};

/// With no inotify, how often to reread the state file.
const POLL: Duration = Duration::from_secs(1);

enum State {
    Idle,
    Selecting,
    Countdown(u8),
    /// Started at this Unix time, in milliseconds.
    Recording(u64),
    Done,
}

fn main() {
    let button = match std::env::args().nth(1).as_deref() {
        Some("button") => true,
        Some("status") => false,
        _ => {
            bar_tools::warn!("usage: record-watch button|status");
            std::process::exit(2);
        }
    };
    let Some(dir) = record::dir() else {
        bar_tools::warn!("record-watch: XDG_RUNTIME_DIR is not set");
        std::process::exit(1);
    };
    let _ = fs::create_dir_all(&dir);
    let events = inotify::watch(
        &dir,
        WatchFlags::CREATE | WatchFlags::MOVED_TO | WatchFlags::CLOSE_WRITE | WatchFlags::DELETE,
    )
    .inspect_err(|e| bar_tools::warn!("record-watch: can't watch {}: {e}", dir.display()))
    .ok();

    let mut out = Emitter::default();
    loop {
        let state = read(&dir);
        let timeout = if button {
            render_button(&mut out, &state);
            None
        } else {
            render_status(&mut out, &state)
        };
        wait(events.as_ref(), timeout);
    }
}

fn read(dir: &Path) -> State {
    let Ok(line) = fs::read_to_string(dir.join(record::STATE)) else {
        return State::Idle;
    };
    let mut words = line.split_whitespace();
    let state = words.next();
    let arg = words.next();
    match state {
        Some("selecting") => State::Selecting,
        Some("countdown") => State::Countdown(arg.and_then(|a| a.parse().ok()).unwrap_or(3)),
        Some("recording") => {
            State::Recording(arg.and_then(|a| a.parse().ok()).unwrap_or_else(now_ms))
        }
        Some("done") => State::Done,
        _ => State::Idle,
    }
}

fn render_button(out: &mut Emitter, state: &State) {
    let (text, tooltip, class) = match state {
        State::Selecting | State::Countdown(_) => (sf::STOP_CIRCLE, "Cancel recording", "active"),
        State::Recording(_) => (sf::STOP_CIRCLE, "Stop recording", "active"),
        _ => (sf::RECORD_CIRCLE, "Record an area (Super+R)", "idle"),
    };
    out.emit(text, tooltip, class);
}

/// Returns how long until the next redraw is due, if one is.
fn render_status(out: &mut Emitter, state: &State) -> Option<Duration> {
    let label = |icon: &str, text: &str| format!("{icon} {}", waybar::number(text));
    match state {
        State::Idle => {
            out.emit("", "", "idle");
            None
        }
        State::Selecting => {
            let text = label(sf::CIRCLE_DASHED, "Select");
            out.emit_markup(
                &text,
                "Select an area to record (click to cancel)",
                "selecting",
            );
            None
        }
        State::Countdown(n) => {
            let icon = match n {
                1 => sf::ONE_CIRCLE_FILL,
                2 => sf::TWO_CIRCLE_FILL,
                _ => sf::THREE_CIRCLE_FILL,
            };
            out.emit(icon, "Recording soon (click to cancel)", "countdown");
            None
        }
        State::Recording(start) => {
            let elapsed = now_ms().saturating_sub(*start);
            let secs = elapsed / 1000;
            // tabular digits, so the timer keeps its width as it counts
            let text = format!(
                "{} <span size='87.5%' rise='768' font_features='tnum'>{}:{:02}</span>",
                sf::CIRCLE_FILL,
                secs / 60,
                secs % 60
            );
            out.emit_markup(&text, "Recording (click to stop)", "recording");
            // wake on the next whole second of the recording
            Some(Duration::from_millis(1000 - elapsed % 1000))
        }
        State::Done => {
            let text = label(sf::CHECKMARK_CIRCLE_FILL, "Saved");
            out.emit_markup(&text, "Recording saved (click to preview)", "done");
            None
        }
    }
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| u64::try_from(d.as_millis()).unwrap_or(u64::MAX))
}

/// Sleep until the state directory changes or `timeout` passes. Without
/// inotify, reread every `POLL` instead.
fn wait(events: Option<&OwnedFd>, timeout: Option<Duration>) {
    let Some(fd) = events else {
        std::thread::sleep(timeout.map_or(POLL, |t| t.min(POLL)));
        return;
    };
    let mut fds = [PollFd::new(fd, PollFlags::IN)];
    match bar_tools::poll(&mut fds, timeout) {
        Ok(0) => {}
        Ok(_) => inotify::drain(fd),
        Err(e) => {
            bar_tools::warn!("record-watch: poll: {e}");
            std::thread::sleep(POLL);
        }
    }
}
