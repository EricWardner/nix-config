//! Output for waybar `custom` modules with `return-type = "json"`: one JSON
//! object per line on stdout, read by waybar as a long-running `exec`.

use std::io::Write;

#[derive(Default)]
pub struct Emitter {
    last: String,
}

/// Pango markup for an icon that leads a number, plus the gap before the
/// number. The icon is drawn from Symbols Nerd Font, whose glyph boxes fit
/// their ink, so every icon sits the same distance from its number; the
/// bar's default (patched SF Pro) gives every icon an equal, wider box. It
/// centres glyphs ~0.75px lower than the patched font, so `rise` (1/1024
/// px) lifts them level, tuned for the bar's 16px font. The gap is a space
/// plus a thin space. Matches `numberIcon` in the waybar module.
pub fn number_icon(icon: &str) -> String {
    format!("<span font_family='Symbols Nerd Font' rise='768'>{icon}</span> &#x2009;")
}

impl Emitter {
    /// Print one module update, skipping it if nothing changed. Exits the
    /// process once stdout is gone: waybar closed the module, so there is
    /// no one left to report to.
    pub fn emit(&mut self, text: &str, tooltip: &str, class: &str) {
        self.write(text, true, tooltip, class);
    }

    /// Like [`Emitter::emit`], but `text` is Pango markup the caller has
    /// already made safe (the tooltip is still escaped).
    pub fn emit_markup(&mut self, text: &str, tooltip: &str, class: &str) {
        self.write(text, false, tooltip, class);
    }

    fn write(&mut self, text: &str, escape_text: bool, tooltip: &str, class: &str) {
        let mut line = String::with_capacity(96);
        line.push_str("{\"text\":\"");
        escape_into(&mut line, text, escape_text);
        line.push_str("\",\"tooltip\":\"");
        escape_into(&mut line, tooltip, true);
        line.push_str("\",\"class\":\"");
        escape_into(&mut line, class, false);
        line.push_str("\"}\n");
        if line == self.last {
            return;
        }

        let mut out = std::io::stdout().lock();
        if out
            .write_all(line.as_bytes())
            .and_then(|()| out.flush())
            .is_err()
        {
            std::process::exit(0);
        }
        self.last = line;
    }
}

/// JSON-escape `s` into `out`. With `markup`, also escape the characters
/// Pango treats as markup, since waybar renders text and tooltips with it.
fn escape_into(out: &mut String, s: &str, markup: bool) {
    for c in s.chars() {
        match c {
            '&' if markup => out.push_str("&amp;"),
            '<' if markup => out.push_str("&lt;"),
            '>' if markup => out.push_str("&gt;"),
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            c if c.is_control() => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
}
