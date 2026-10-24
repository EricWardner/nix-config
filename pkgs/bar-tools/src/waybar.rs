//! Output for waybar `custom` modules with `return-type = "json"`: one JSON
//! object per line on stdout, read by waybar as a long-running `exec`.

use std::io::Write;

#[derive(Default)]
pub struct Emitter {
    last: String,
}

/// Pango markup for a number shown beside an icon: a size smaller (14px
/// against the bar's 16px) so the icon leads, lifted ~0.75px (`rise` is in
/// 1/1024 px) so it centres on the icon instead of sitting on the 16px
/// baseline. `text` must be plain text such as "45%". Matches `num` in the
/// waybar module.
pub fn number(text: &str) -> String {
    format!("<span size='87.5%' rise='768'>{text}</span>")
}

impl Emitter {
    /// Print one module update, skipping it if nothing changed. Exits the
    /// process once stdout is gone: waybar closed the module, so there is
    /// no one left to report to.
    pub fn emit(&mut self, text: &str, tooltip: &str, class: &str) {
        self.write(text, true, tooltip, class, None);
    }

    /// Like [`Emitter::emit`], but `text` is Pango markup the caller has
    /// already made safe (the tooltip is still escaped).
    pub fn emit_markup(&mut self, text: &str, tooltip: &str, class: &str) {
        self.write(text, false, tooltip, class, None);
    }

    /// Like [`Emitter::emit_markup`], plus `alt` (plain text) and
    /// `percentage`, which the module's `format-alt` shows as `{alt}` and
    /// `{percentage}` once a left-click toggles it, like the built-in cpu
    /// module's.
    pub fn emit_level(
        &mut self,
        text: &str,
        tooltip: &str,
        class: &str,
        alt: &str,
        percentage: u32,
    ) {
        self.write(text, false, tooltip, class, Some((alt, percentage)));
    }

    fn write(
        &mut self,
        text: &str,
        escape_text: bool,
        tooltip: &str,
        class: &str,
        level: Option<(&str, u32)>,
    ) {
        let mut line = String::with_capacity(96);
        line.push_str("{\"text\":\"");
        escape_into(&mut line, text, escape_text);
        line.push_str("\",\"tooltip\":\"");
        escape_into(&mut line, tooltip, true);
        line.push_str("\",\"class\":\"");
        escape_into(&mut line, class, false);
        line.push('"');
        if let Some((alt, percentage)) = level {
            line.push_str(",\"alt\":\"");
            escape_into(&mut line, alt, true);
            line.push_str(&format!("\",\"percentage\":{percentage}"));
        }
        line.push_str("}\n");
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
