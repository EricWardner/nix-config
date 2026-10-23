//! Shared pieces of the bar tools: a minimal PulseAudio-protocol client, the
//! waybar output helper, and small system utilities.

use std::time::Duration;

use rustix::event::{PollFd, Timespec};

pub mod pa;
pub mod waybar;

/// Push-to-talk's one piece of shared state: it is armed while the file
/// `$XDG_RUNTIME_DIR/ptt/armed` exists. pttd mutes and unmutes the mics as
/// it appears and disappears; mic-watch shows it. The directory holds
/// nothing else, so an inotify watch on it fires only for this file.
pub mod ptt {
    use std::path::PathBuf;

    pub const ARMED: &str = "armed";

    pub fn dir() -> Option<PathBuf> {
        std::env::var_os("XDG_RUNTIME_DIR").map(|d| PathBuf::from(d).join("ptt"))
    }
}

/// inotify for "something changed in this directory": the tools never parse
/// events, any event just means "look again".
pub mod inotify {
    use std::os::fd::OwnedFd;
    use std::path::Path;

    pub use rustix::fs::inotify::WatchFlags;
    use rustix::fs::inotify::{CreateFlags, add_watch, init};

    /// A non-blocking inotify fd watching the directory `dir`.
    pub fn watch(dir: &Path, flags: WatchFlags) -> rustix::io::Result<OwnedFd> {
        let fd = init(CreateFlags::NONBLOCK | CreateFlags::CLOEXEC)?;
        add_watch(&fd, dir, flags | WatchFlags::ONLYDIR)?;
        Ok(fd)
    }

    /// Discard the queued events.
    pub fn drain(fd: &OwnedFd) {
        let mut buf = [0u8; 4096];
        while matches!(rustix::io::read(fd, &mut buf), Ok(n) if n > 0) {}
    }
}

/// Log a line to stderr (the journal under systemd), ignoring failures: with
/// `panic = "abort"`, `eprintln!` on a broken stderr would kill the process.
#[macro_export]
macro_rules! warn {
    ($($arg:tt)*) => {{
        use std::io::Write as _;
        let _ = writeln!(std::io::stderr(), $($arg)*);
    }};
}

/// `poll(2)`, retried on EINTR. `None` waits forever. Returns how many fds
/// are ready (0 on timeout).
pub fn poll(fds: &mut [PollFd<'_>], timeout: Option<Duration>) -> rustix::io::Result<usize> {
    // a duration too large for a timespec is as good as forever
    let timeout = timeout.and_then(|d| Timespec::try_from(d).ok());
    loop {
        match rustix::event::poll(fds, timeout.as_ref()) {
            Err(rustix::io::Errno::INTR) => continue,
            result => return result,
        }
    }
}
