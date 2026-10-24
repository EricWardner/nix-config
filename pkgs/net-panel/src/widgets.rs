//! Small drawn widgets: the signal glyph, the padlock, a chevron and the QR
//! code. They paint in the widget's CSS `color`, so classes restyle them.

use std::cell::{Cell, RefCell};
use std::rc::Rc;

use gtk::prelude::*;
use gtk::{cairo, gdk};

use crate::icons;

fn rgba(color: gdk::RGBA) -> (f64, f64, f64, f64) {
    (
        f64::from(color.red()),
        f64::from(color.green()),
        f64::from(color.blue()),
        f64::from(color.alpha()),
    )
}

#[derive(Clone)]
pub struct SignalIcon {
    pub area: gtk::DrawingArea,
    level: Rc<Cell<u8>>,
}

impl SignalIcon {
    pub fn new(size: i32, level: u8) -> Self {
        let area = gtk::DrawingArea::builder()
            .content_width(size)
            .content_height(size)
            .valign(gtk::Align::Center)
            .build();
        area.add_css_class("signal");
        let level = Rc::new(Cell::new(level));
        let shown = level.clone();
        area.set_draw_func(move |area, cr, w, h| {
            icons::draw_wifi(cr, f64::from(w.min(h)), shown.get(), rgba(area.color()));
        });
        Self { area, level }
    }

    pub fn set_level(&self, level: u8) {
        if self.level.replace(level) != level {
            self.area.queue_draw();
        }
    }
}

pub fn lock_icon() -> gtk::DrawingArea {
    let area = gtk::DrawingArea::builder()
        .content_width(12)
        .content_height(12)
        .valign(gtk::Align::Center)
        .build();
    area.add_css_class("lock");
    area.set_draw_func(|area, cr, w, h| {
        icons::draw_lock(cr, f64::from(w.min(h)), rgba(area.color()))
    });
    area
}

/// A chevron that points down, or up once its section is open.
#[derive(Clone)]
pub struct Chevron {
    pub area: gtk::DrawingArea,
    up: Rc<Cell<bool>>,
}

impl Chevron {
    pub fn new(size: i32) -> Self {
        let area = gtk::DrawingArea::builder()
            .content_width(size)
            .content_height(size)
            .halign(gtk::Align::Center)
            .valign(gtk::Align::Center)
            .build();
        let up: Rc<Cell<bool>> = Rc::default();
        let shown = up.clone();
        area.set_draw_func(move |area, cr, w, h| {
            let (w, h) = (f64::from(w), f64::from(h));
            let (r, g, b, a) = rgba(area.color());
            cr.set_source_rgba(r, g, b, a);
            cr.set_line_width(w * 0.15);
            cr.set_line_cap(cairo::LineCap::Round);
            cr.set_line_join(cairo::LineJoin::Round);
            let (tip, ends) = if shown.get() {
                (h * 0.32, h * 0.66)
            } else {
                (h * 0.68, h * 0.34)
            };
            cr.move_to(w * 0.22, ends);
            cr.line_to(w * 0.5, tip);
            cr.line_to(w * 0.78, ends);
            cr.stroke().ok();
        });
        Self { area, up }
    }

    pub fn set_up(&self, up: bool) {
        if self.up.replace(up) != up {
            self.area.queue_draw();
        }
    }
}

/// A QR code of `text`, drawn on a light tile so phones can read it.
#[derive(Clone)]
pub struct Qr {
    pub area: gtk::DrawingArea,
    code: Rc<RefCell<Option<qrcode::QrCode>>>,
}

impl Qr {
    pub fn new(size: i32) -> Self {
        let area = gtk::DrawingArea::builder()
            .content_width(size)
            .content_height(size)
            .halign(gtk::Align::Center)
            .build();
        area.add_css_class("qr");
        let code: Rc<RefCell<Option<qrcode::QrCode>>> = Rc::default();
        let shown = code.clone();
        area.set_draw_func(move |_, cr, w, h| {
            let Some(code) = shown.borrow().as_ref().map(|c| (c.width(), c.to_colors())) else {
                return;
            };
            let (modules, colors) = code;
            let side = f64::from(w.min(h));
            // A quiet zone of two modules on every side.
            let cell = side / (modules as f64 + 4.0);
            cr.set_source_rgb(1.0, 1.0, 1.0);
            rounded(cr, 0.0, 0.0, side, side, cell * 1.5);
            cr.fill().ok();
            cr.set_source_rgb(0.08, 0.09, 0.11);
            for (i, color) in colors.iter().enumerate() {
                if *color == qrcode::Color::Dark {
                    let (x, y) = ((i % modules) as f64 + 2.0, (i / modules) as f64 + 2.0);
                    cr.rectangle(x * cell, y * cell, cell + 0.4, cell + 0.4);
                }
            }
            cr.fill().ok();
        });
        Self { area, code }
    }

    pub fn set_text(&self, text: Option<&str>) {
        *self.code.borrow_mut() = text.and_then(|t| qrcode::QrCode::new(t.as_bytes()).ok());
        self.area.queue_draw();
    }
}

fn rounded(cr: &cairo::Context, x: f64, y: f64, w: f64, h: f64, r: f64) {
    use std::f64::consts::PI;
    cr.new_sub_path();
    cr.arc(x + w - r, y + r, r, -PI / 2.0, 0.0);
    cr.arc(x + w - r, y + h - r, r, 0.0, PI / 2.0);
    cr.arc(x + r, y + h - r, r, PI / 2.0, PI);
    cr.arc(x + r, y + r, r, PI, 1.5 * PI);
    cr.close_path();
}

/// The Wi-Fi QR payload phones read to join (the ZXing "WIFI:" format).
pub fn wifi_qr_payload(ssid: &str, key: &str, kind: &str) -> String {
    let escape = |s: &str| {
        s.chars()
            .flat_map(|c| {
                if matches!(c, '\\' | ';' | ',' | ':' | '"') {
                    vec!['\\', c]
                } else {
                    vec![c]
                }
            })
            .collect::<String>()
    };
    format!("WIFI:T:{kind};S:{};P:{};;", escape(ssid), escape(key))
}

#[cfg(test)]
mod tests {
    use super::wifi_qr_payload;

    #[test]
    fn escapes_wifi_payload() {
        assert_eq!(
            wifi_qr_payload("Home", "hunter22", "WPA"),
            "WIFI:T:WPA;S:Home;P:hunter22;;"
        );
        assert_eq!(
            wifi_qr_payload("a;b", "c:d\\", "WPA"),
            r"WIFI:T:WPA;S:a\;b;P:c\:d\\;;"
        );
    }
}
