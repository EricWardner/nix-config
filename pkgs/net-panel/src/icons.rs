//! The Wi-Fi glyph, drawn two ways from one geometry: as filled SVG shapes
//! for the tray (waybar loads `*-symbolic` icons through GTK, which forces
//! `fill` on every path, so strokes would fill in) and with cairo for the
//! panel's own icons. 24×24 box: a dot and three concentric arcs.

use std::f64::consts::PI;
use std::fmt::Write as _;
use std::path::{Path, PathBuf};

use gtk::cairo;

/// Half the arc width (the stroke is 2.6 in the 24 box).
const HALF_WIDTH: f64 = 1.3;
const DOT: (f64, f64, f64) = (12.0, 19.0, 1.5);
const DIM: f64 = 0.3;

/// An arc whose chord ends sit at `y`, `half_chord` either side of centre.
struct Arc {
    y: f64,
    half_chord: f64,
    radius: f64,
}

/// Inner to outer.
const ARCS: [Arc; 3] = [
    Arc {
        y: 15.5,
        half_chord: 3.2,
        radius: 4.5,
    },
    Arc {
        y: 12.4,
        half_chord: 6.3,
        radius: 8.8,
    },
    Arc {
        y: 9.3,
        half_chord: 9.4,
        radius: 13.2,
    },
];

impl Arc {
    fn center_y(&self) -> f64 {
        self.y + (self.radius * self.radius - self.half_chord * self.half_chord).sqrt()
    }

    /// Start (left) and end (right) angles; y grows downward.
    fn angles(&self) -> (f64, f64) {
        let dy = self.y - self.center_y();
        (dy.atan2(-self.half_chord), dy.atan2(self.half_chord))
    }

    fn point(&self, radius: f64, angle: f64) -> (f64, f64) {
        (
            12.0 + radius * angle.cos(),
            self.center_y() + radius * angle.sin(),
        )
    }

    /// The arc as a filled band with round caps.
    fn band_path(&self) -> String {
        let (a0, a1) = self.angles();
        let (outer, inner) = (self.radius + HALF_WIDTH, self.radius - HALF_WIDTH);
        let p = |r, a| {
            let (x, y) = self.point(r, a);
            format!("{x:.3} {y:.3}")
        };
        format!(
            "M{} A{outer:.3} {outer:.3} 0 0 1 {} A{HALF_WIDTH} {HALF_WIDTH} 0 0 1 {} A{inner:.3} {inner:.3} 0 0 0 {} A{HALF_WIDTH} {HALF_WIDTH} 0 0 1 {}Z",
            p(outer, a0),
            p(outer, a1),
            p(inner, a1),
            p(inner, a0),
            p(outer, a0),
        )
    }
}

/// How many arcs are lit for a signal level: level 1 is the dot alone.
fn lit_arcs(level: u8) -> usize {
    usize::from(level.clamp(1, 4) - 1)
}

#[derive(Clone, Copy)]
enum Badge {
    None,
    Limited,
    Vpn,
}

impl Badge {
    /// The badge's shapes, and the area knocked out of the glyph under it.
    fn parts(self) -> Option<(&'static str, &'static str)> {
        match self {
            Self::None => None,
            Self::Limited => Some((
                concat!(
                    r#"<path fill-rule="evenodd" d="M18.5 13.6a4.9 4.9 0 1 1 0 9.8a4.9 4.9 0 1 1 0-9.8z"#,
                    r#"M17.75 15.6h1.5v4.1h-1.5z M18.5 20.5a.9 .9 0 1 1 0 1.8a.9 .9 0 1 1 0-1.8z"/>"#,
                ),
                "M18.5 12.2a6.3 6.3 0 1 1 0 12.6a6.3 6.3 0 1 1 0-12.6z",
            )),
            Self::Vpn => Some((
                concat!(
                    r#"<path d="M15.6 17.5h5.8a.9 .9 0 0 1 .9.9v3.9a.9 .9 0 0 1-.9.9h-5.8a.9 .9 0 0 1-.9-.9v-3.9a.9 .9 0 0 1 .9-.9z"/>"#,
                    r#"<path d="M16.1 17.6v-1.3a2.4 2.4 0 0 1 4.8 0v1.3h-1.3v-1.3a1.1 1.1 0 0 0-2.2 0v1.3z"/>"#,
                ),
                "M14.6 11.6h8.4a1.6 1.6 0 0 1 1.6 1.6v10.6h-11.6v-10.6a1.6 1.6 0 0 1 1.6-1.6z",
            )),
        }
    }
}

/// `glyph` with `hole` knocked out of it, then `overlay` drawn on top, so a
/// slash or badge reads on its own against the glyph under it.
fn knocked_out(glyph: &str, hole: Option<&str>, overlay: &str, color: &str) -> String {
    match hole {
        Some(hole) => svg(
            &format!(
                r#"<defs><clipPath id="k"><path clip-rule="evenodd" d="M-1 -1H25V25H-1Z {hole}"/></clipPath></defs><g clip-path="url(#k)">{glyph}</g>{overlay}"#
            ),
            color,
        ),
        None => svg(&format!("{glyph}{overlay}"), color),
    }
}

fn wifi_svg(lit: usize, all_dim: bool, slash: bool, badge: Badge, color: &str) -> String {
    let mut glyph = String::new();
    let alpha = |on: bool| if on && !all_dim { 1.0 } else { DIM };
    let _ = write!(
        glyph,
        r#"<circle cx="{}" cy="{}" r="{}" opacity="{}"/>"#,
        DOT.0,
        DOT.1,
        DOT.2,
        if all_dim { DIM } else { 1.0 }
    );
    for (i, arc) in ARCS.iter().enumerate() {
        let _ = write!(
            glyph,
            r#"<path d="{}" opacity="{}"/>"#,
            arc.band_path(),
            alpha(i < lit)
        );
    }
    if slash {
        let line = |half| capsule(3.6, 3.4, 20.4, 20.6, half);
        return knocked_out(
            &glyph,
            Some(&line(HALF_WIDTH + 1.4)),
            &format!(r#"<path d="{}"/>"#, line(HALF_WIDTH)),
            color,
        );
    }
    match badge.parts() {
        Some((overlay, hole)) => knocked_out(&glyph, Some(hole), overlay, color),
        None => knocked_out(&glyph, None, "", color),
    }
}

/// A line from (x1, y1) to (x2, y2) as a filled shape with round ends.
fn capsule(x1: f64, y1: f64, x2: f64, y2: f64, half: f64) -> String {
    let angle = (y2 - y1).atan2(x2 - x1);
    let (nx, ny) = (-angle.sin() * half, angle.cos() * half);
    format!(
        "M{:.3} {:.3}L{:.3} {:.3}A{half} {half} 0 0 1 {:.3} {:.3}L{:.3} {:.3}A{half} {half} 0 0 1 {:.3} {:.3}Z",
        x1 + nx,
        y1 + ny,
        x2 + nx,
        y2 + ny,
        x2 - nx,
        y2 - ny,
        x1 - nx,
        y1 - ny,
        x1 + nx,
        y1 + ny,
    )
}

fn wired_svg(badge: Badge, color: &str) -> String {
    let port = concat!(
        r#"<path fill-rule="evenodd" d="M6 4.5h12a2.5 2.5 0 0 1 2.5 2.5v7a2.5 2.5 0 0 1-2.5 2.5h-2.5v2.5a1 1 0 0 1-1 1h-5a1 1 0 0 1-1-1v-2.5H6a2.5 2.5 0 0 1-2.5-2.5V7A2.5 2.5 0 0 1 6 4.5z"#,
        r#"M6.3 6.6a.6 .6 0 0 0-.6.6v6.6a.6 .6 0 0 0 .6.6h11.4a.6 .6 0 0 0 .6-.6V7.2a.6 .6 0 0 0-.6-.6z"/>"#,
        r#"<path d="M8 8.4h1.4v3.4H8z M10.6 8.4H12v3.4h-1.4z M13.2 8.4h1.4v3.4h-1.4z M15.8 8.4h1.4v3.4h-1.4z"/>"#,
    );
    match badge.parts() {
        Some((overlay, hole)) => knocked_out(port, Some(hole), overlay, color),
        None => knocked_out(port, None, "", color),
    }
}

fn airplane_svg(color: &str) -> String {
    svg(
        r#"<path d="M12 2.5c.8 0 1.4.7 1.4 1.5v5.2l7.6 4.6v2l-7.6-2.4v4.4l2.2 1.7v1.5L12 20.3 8.4 21v-1.5l2.2-1.7v-4.4L3 15.8v-2l7.6-4.6V4c0-.8.6-1.5 1.4-1.5z"/>"#,
        color,
    )
}

fn svg(body: &str, color: &str) -> String {
    format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="#{color}">{body}</svg>"##
    )
}

/// Every icon the tray can name (see `TrayIcon::name`), as (stem, svg).
fn all_icons(color: &str) -> Vec<(String, String)> {
    let mut icons = vec![
        ("airplane".to_owned(), airplane_svg(color)),
        (
            "off".to_owned(),
            wifi_svg(3, true, true, Badge::None, color),
        ),
        (
            "disconnected".to_owned(),
            wifi_svg(3, true, false, Badge::None, color),
        ),
        ("wired".to_owned(), wired_svg(Badge::None, color)),
        ("wired-limited".to_owned(), wired_svg(Badge::Limited, color)),
        ("wired-vpn".to_owned(), wired_svg(Badge::Vpn, color)),
    ];
    for phase in 1..=3u8 {
        icons.push((
            format!("connecting-{phase}"),
            wifi_svg(lit_arcs(phase + 1), false, false, Badge::None, color),
        ));
    }
    for level in 1..=4u8 {
        let lit = lit_arcs(level);
        icons.push((
            format!("wifi-{level}"),
            wifi_svg(lit, false, false, Badge::None, color),
        ));
        icons.push((
            format!("wifi-{level}-limited"),
            wifi_svg(lit, false, false, Badge::Limited, color),
        ));
        icons.push((
            format!("wifi-{level}-vpn"),
            wifi_svg(lit, false, false, Badge::Vpn, color),
        ));
    }
    icons
}

/// Writes the tray icons into `dir` (the tray's IconThemePath) and returns it.
pub fn write_tray_icons(dir: &Path, color: &str) -> std::io::Result<PathBuf> {
    std::fs::create_dir_all(dir)?;
    for (stem, svg) in all_icons(color) {
        std::fs::write(dir.join(format!("net-panel-{stem}-symbolic.svg")), svg)?;
    }
    Ok(dir.to_path_buf())
}

/// Paints the Wi-Fi glyph into a `size`×`size` square at the origin.
/// `lit` arcs at full alpha, the rest dimmed; `alpha` scales everything.
pub fn draw_wifi(cr: &cairo::Context, size: f64, level: u8, rgba: (f64, f64, f64, f64)) {
    let lit = lit_arcs(level);
    let scale = size / 24.0;
    cr.save().ok();
    cr.scale(scale, scale);
    let (r, g, b, a) = rgba;
    cr.set_source_rgba(r, g, b, a);
    cr.arc(DOT.0, DOT.1, DOT.2, 0.0, 2.0 * PI);
    cr.fill().ok();
    cr.set_line_width(HALF_WIDTH * 2.0);
    cr.set_line_cap(cairo::LineCap::Round);
    for (i, arc) in ARCS.iter().enumerate() {
        let (a0, a1) = arc.angles();
        cr.set_source_rgba(r, g, b, if i < lit { a } else { a * DIM });
        cr.new_sub_path();
        cr.arc(12.0, arc.center_y(), arc.radius, a0, a1);
        cr.stroke().ok();
    }
    cr.restore().ok();
}

/// A small padlock in a `size`×`size` square.
pub fn draw_lock(cr: &cairo::Context, size: f64, rgba: (f64, f64, f64, f64)) {
    let scale = size / 24.0;
    cr.save().ok();
    cr.scale(scale, scale);
    cr.set_source_rgba(rgba.0, rgba.1, rgba.2, rgba.3);
    rounded_rect(cr, 5.0, 10.5, 14.0, 11.0, 2.5);
    cr.fill().ok();
    cr.set_line_width(2.6);
    cr.new_sub_path();
    cr.arc(12.0, 8.5, 4.0, PI, 2.0 * PI);
    cr.move_to(8.0, 8.5);
    cr.line_to(8.0, 11.0);
    cr.move_to(16.0, 8.5);
    cr.line_to(16.0, 11.0);
    cr.stroke().ok();
    cr.restore().ok();
}

fn rounded_rect(cr: &cairo::Context, x: f64, y: f64, w: f64, h: f64, r: f64) {
    cr.new_sub_path();
    cr.arc(x + w - r, y + r, r, -PI / 2.0, 0.0);
    cr.arc(x + w - r, y + h - r, r, 0.0, PI / 2.0);
    cr.arc(x + r, y + h - r, r, PI / 2.0, PI);
    cr.arc(x + r, y + r, r, PI, 1.5 * PI);
    cr.close_path();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Snapshot, TrayIcon};

    #[test]
    fn arcs_share_a_centre_with_the_dot() {
        for arc in &ARCS {
            assert!(
                (arc.center_y() - DOT.1).abs() < 0.6,
                "arc centre {} far from dot",
                arc.center_y()
            );
            let (a0, a1) = arc.angles();
            assert!(a0 < a1 && a1 < 0.0, "arcs open upward");
        }
    }

    #[test]
    fn every_tray_icon_name_has_a_file() {
        let stems: Vec<String> = all_icons("eeffff")
            .into_iter()
            .map(|(s, _)| format!("net-panel-{s}-symbolic"))
            .collect();
        let mut names = vec![
            TrayIcon::Airplane.name(1),
            TrayIcon::Off.name(1),
            TrayIcon::Disconnected.name(1),
            TrayIcon::from_snapshot(&Snapshot::default(), false).name(1),
        ];
        for phase in 1..=3 {
            names.push(TrayIcon::Connecting.name(phase));
        }
        for level in 1..=4 {
            for (limited, vpn) in [(false, false), (true, false), (false, true), (true, true)] {
                names.push(
                    TrayIcon::Wifi {
                        level,
                        limited,
                        vpn,
                    }
                    .name(1),
                );
                names.push(TrayIcon::Wired { limited, vpn }.name(1));
            }
        }
        for name in names {
            assert!(stems.contains(&name), "no icon for {name}");
        }
    }
}
