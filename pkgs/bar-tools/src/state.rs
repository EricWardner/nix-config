//! The watchers' output, read by the islands shell (shell/Watcher.qml): their
//! state as one JSON object per line on stdout, `{"class":"…"}`, whenever it
//! changes.

use std::io::Write;

#[derive(Default)]
pub struct Emitter {
    last: String,
}

impl Emitter {
    /// Prints the state, unless it's unchanged. `class` is one of the
    /// watcher's fixed names, so it needs no escaping. Exits once stdout is
    /// gone: the shell stopped reading, so there's no one left to tell.
    pub fn emit(&mut self, class: &str) {
        if class == self.last {
            return;
        }
        let mut out = std::io::stdout().lock();
        if writeln!(out, "{{\"class\":\"{class}\"}}")
            .and_then(|()| out.flush())
            .is_err()
        {
            std::process::exit(0);
        }
        self.last = class.to_owned();
    }
}
