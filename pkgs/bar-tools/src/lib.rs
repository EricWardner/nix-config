//! Shared pieces of the bar tools: a minimal PulseAudio-protocol client, the
//! waybar output helper, and small system utilities.

use std::time::Duration;

use rustix::event::{PollFd, Timespec};

pub mod pa;
pub mod waybar;

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
