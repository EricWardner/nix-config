//! net-panel: a Wi-Fi and network panel for the waybar tray, in place of
//! nm-applet. One resident process holds the tray icon, the panel window and
//! NetworkManager's secret agent; `net-panel toggle` opens or closes it.

mod agent;
mod icons;
mod model;
mod nm;
mod notify;
mod rfkill;
mod tray;
mod ui;
mod widgets;

use std::path::PathBuf;

use gtk::prelude::*;
use gtk::{gio, glib};

/// Everything the panel reacts to, from any thread.
pub enum Event {
    Snapshot(Box<model::Snapshot>),
    /// A tray click (with its screen position) or `net-panel toggle`.
    Toggle(Option<(i32, i32)>),
    Agent(agent::AgentEvent),
    Airplane(bool),
}

#[derive(Clone, Debug)]
pub struct Options {
    /// A stylesheet loaded over the built-in one (theme colours, font).
    pub css: Option<PathBuf>,
    /// The tray icons' colour, for consumers that don't recolour symbolic
    /// icons (notifications).
    pub icon_color: String,
    pub editor: String,
    pub systemd_run: String,
}

const USAGE: &str =
    "usage: net-panel [--css FILE] [--icon-color RRGGBB] [--editor CMD] [--systemd-run PATH]
       net-panel toggle";

fn parse(args: impl Iterator<Item = String>) -> Result<Options, String> {
    let mut opts = Options {
        css: None,
        icon_color: "eeffff".into(),
        editor: "nm-connection-editor".into(),
        systemd_run: "systemd-run".into(),
    };
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        let mut value = || {
            args.next()
                .ok_or_else(|| format!("{arg} needs a value\n{USAGE}"))
        };
        match arg.as_str() {
            "--css" => opts.css = Some(PathBuf::from(value()?)),
            "--icon-color" => opts.icon_color = value()?.trim_start_matches('#').to_owned(),
            "--editor" => opts.editor = value()?,
            "--systemd-run" => opts.systemd_run = value()?,
            "-h" | "--help" => return Err(USAGE.to_owned()),
            other => return Err(format!("unknown argument {other}\n{USAGE}")),
        }
    }
    Ok(opts)
}

fn main() -> glib::ExitCode {
    let mut args = std::env::args().skip(1).peekable();
    if args.peek().map(String::as_str) == Some("toggle") {
        return match tray::send_toggle() {
            Ok(()) => glib::ExitCode::SUCCESS,
            Err(e) => {
                eprintln!("net-panel: is the panel running? {e}");
                glib::ExitCode::FAILURE
            }
        };
    }
    let opts = match parse(args) {
        Ok(opts) => opts,
        Err(message) => {
            eprintln!("{message}");
            return glib::ExitCode::FAILURE;
        }
    };
    let app = gtk::Application::builder()
        .application_id("io.github.netpanel.Panel")
        .flags(gio::ApplicationFlags::NON_UNIQUE)
        .build();
    app.connect_activate(move |app| ui::start(app, opts.clone()));
    app.run_with_args::<&str>(&[])
}
