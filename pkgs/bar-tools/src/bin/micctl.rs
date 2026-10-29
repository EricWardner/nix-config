//! micctl: microphone controls for the bar's clicks and keybinds.
//!
//!   micctl ptt    arm or disarm push-to-talk (pttd does the muting)
//!   micctl mute   mute every microphone, or unmute them all if all are
//!                 muted; does nothing while push-to-talk is armed, since
//!                 the mics are pttd's then (and unmuting would open them)

use std::process::ExitCode;

use bar_tools::pa::{self, Conn};
use bar_tools::ptt;

fn main() -> ExitCode {
    let result = match std::env::args().nth(1).as_deref() {
        Some("ptt") => toggle_ptt(),
        Some("mute") if ptt_armed() => {
            Err("push-to-talk is armed (`micctl ptt` disarms it); leaving the mics alone".into())
        }
        Some("mute") => toggle_mute().map_err(|e| e.to_string()),
        _ => Err("usage: micctl ptt|mute".to_owned()),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            bar_tools::warn!("micctl: {e}");
            ExitCode::FAILURE
        }
    }
}

fn ptt_armed() -> bool {
    ptt::dir().is_some_and(|d| d.join(ptt::ARMED).exists())
}

fn toggle_ptt() -> Result<(), String> {
    let dir = ptt::dir().ok_or("XDG_RUNTIME_DIR unset")?;
    let armed = dir.join(ptt::ARMED);
    match std::fs::remove_file(&armed) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => std::fs::create_dir_all(&dir)
            .and_then(|()| std::fs::File::create(&armed).map(drop))
            .map_err(|e| format!("{}: {e}", armed.display())),
        Err(e) => Err(format!("{}: {e}", armed.display())),
    }
}

fn toggle_mute() -> Result<(), pa::Error> {
    let mut conn = Conn::connect("micctl")?;
    let sources = conn.capture_sources()?;
    let mute = sources.iter().any(|s| !s.muted);
    let Some((last, rest)) = sources.split_last() else {
        return Ok(());
    };
    for s in rest {
        conn.queue_source_mute(s.index, mute)?;
    }
    // Replies arrive in order, so once the last one is in, all are applied.
    conn.request_ack(&pa::source_mute(last.index, mute))
}
