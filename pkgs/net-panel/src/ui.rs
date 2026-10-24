//! The panel: a layer-shell window that drops from the bar under the tray
//! icon, with the current network on a card, saved and other networks below
//! it, and the less-used actions in the footer. It closes when it loses
//! focus or on Escape.
//!
//! While it is open the network rows keep their places (only signals and
//! labels update) so nothing moves under the pointer; the lists re-sort the
//! next time it opens, or when a network changes list.

use std::cell::{Cell, RefCell};
use std::collections::{HashMap, HashSet};
use std::rc::{Rc, Weak};
use std::time::{Duration, Instant};

use gtk::prelude::*;
use gtk::{gdk, gio, glib, pango};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use zbus::Connection;

use crate::agent::{AgentEvent, Kind, SecretRequest};
use crate::model::{
    self, Connectivity, NetState, Network, NetworkKey, Security, Snapshot, TrayIcon,
};
use crate::nm::{self, Eap, Secret};
use crate::notify::Notifier;
use crate::rfkill::Rfkill;
use crate::tray::Tray;
use crate::widgets::{self, Qr, SignalIcon};
use crate::{Event, Options};

const PANEL_WIDTH: i32 = 344;
/// The panel's side margin in style.css (room for its shadow).
const SIDE_MARGIN: i32 = 14;
/// How long a scan may run before the spinner stops anyway.
const SCAN_TIMEOUT: Duration = Duration::from_secs(10);
/// Panel-initiated changes don't also raise notifications for this long.
const QUIET: Duration = Duration::from_secs(20);
/// "Other networks" rows shown before "Show more" (all of them when searching).
const OTHER_LIMIT: i32 = 8;

fn label(text: &str, classes: &[&str]) -> gtk::Label {
    // Wrapped and ellipsized labels ask for their whole text as natural width;
    // capping it keeps the panel at its set width.
    let label = gtk::Label::builder()
        .label(text)
        .xalign(0.0)
        .max_width_chars(30)
        .build();
    for class in classes {
        label.add_css_class(class);
    }
    label
}

fn button(text: &str, classes: &[&str]) -> gtk::Button {
    let button = gtk::Button::with_label(text);
    for class in classes {
        button.add_css_class(class);
    }
    button
}

fn icon_button(icon: &str, tooltip: &str) -> gtk::Button {
    let button = gtk::Button::from_icon_name(icon);
    button.add_css_class("icon");
    button.set_tooltip_text(Some(tooltip));
    button.update_property(&[gtk::accessible::Property::Label(tooltip)]);
    button
}

fn bx(orientation: gtk::Orientation, spacing: i32) -> gtk::Box {
    gtk::Box::new(orientation, spacing)
}

fn vbox(spacing: i32) -> gtk::Box {
    bx(gtk::Orientation::Vertical, spacing)
}

fn hbox(spacing: i32) -> gtk::Box {
    bx(gtk::Orientation::Horizontal, spacing)
}

/// A switch whose programmatic updates don't fire its handler.
struct Toggle {
    switch: gtk::Switch,
    handler: RefCell<Option<glib::SignalHandlerId>>,
}

impl Toggle {
    fn new(label_text: &str) -> (Self, gtk::Label) {
        let switch = gtk::Switch::builder().valign(gtk::Align::Center).build();
        switch.update_property(&[gtk::accessible::Property::Label(label_text)]);
        (
            Self {
                switch,
                handler: RefCell::default(),
            },
            label(label_text, &[]),
        )
    }

    fn on_toggle(&self, f: impl Fn(bool) + 'static) {
        let id = self.switch.connect_active_notify(move |s| f(s.is_active()));
        *self.handler.borrow_mut() = Some(id);
    }

    fn set(&self, on: bool) {
        if self.switch.is_active() == on {
            return;
        }
        let handler = self.handler.borrow();
        if let Some(h) = handler.as_ref() {
            self.switch.block_signal(h);
        }
        self.switch.set_active(on);
        if let Some(h) = handler.as_ref() {
            self.switch.unblock_signal(h);
        }
    }
}

/// A network row's join form, built the first time the row opens: crowded
/// places list hundreds of networks, and most are never joined.
struct JoinForm {
    revealer: gtk::Revealer,
    identity_label: gtk::Label,
    identity: gtk::Entry,
    password: gtk::PasswordEntry,
    error: gtk::Label,
}

/// A row of a network list, with its join form folded under it.
struct NetRow {
    ui: Weak<Ui>,
    row: gtk::ListBoxRow,
    body: gtk::Box,
    icon: SignalIcon,
    name: gtk::Label,
    note: gtk::Label,
    lock: gtk::DrawingArea,
    form: RefCell<Option<JoinForm>>,
    network: RefCell<Network>,
    /// Which list it sits in: Some(true) for known networks.
    placed: Cell<Option<bool>>,
    failed: Cell<bool>,
}

impl NetRow {
    fn new(ui: &Rc<Ui>, network: &Network) -> Rc<Self> {
        let icon = SignalIcon::new(18, model::signal_level(network.strength));
        let name = label(&network.ssid, &[]);
        name.set_hexpand(true);
        name.set_ellipsize(pango::EllipsizeMode::End);
        let note = label("", &["dim", "small"]);
        note.set_visible(false);
        let text = vbox(1);
        text.set_valign(gtk::Align::Center);
        text.append(&name);
        text.append(&note);
        let lock = widgets::lock_icon();
        let line = hbox(10);
        line.add_css_class("net-line");
        line.append(&icon.area);
        line.append(&text);
        line.append(&lock);
        let body = vbox(0);
        body.append(&line);
        let row = gtk::ListBoxRow::builder()
            .child(&body)
            .activatable(true)
            .build();
        let this = Rc::new(Self {
            ui: Rc::downgrade(ui),
            row,
            body,
            icon,
            name,
            note,
            lock,
            form: RefCell::default(),
            network: RefCell::new(network.clone()),
            placed: Cell::new(None),
            failed: Cell::new(false),
        });
        this.update(network);
        this
    }

    fn build_form(self: &Rc<Self>) -> JoinForm {
        let identity_label = label("Username", &["dim", "small"]);
        let identity = gtk::Entry::new();
        let password = gtk::PasswordEntry::builder().show_peek_icon(true).build();
        password.update_property(&[gtk::accessible::Property::Label("Password")]);
        let error = label("", &["error"]);
        error.set_wrap(true);
        error.set_visible(false);
        let cancel = button("Cancel", &["pill"]);
        let join = button("Join", &["pill", "accent"]);
        let buttons = hbox(6);
        buttons.set_halign(gtk::Align::End);
        buttons.set_margin_top(2);
        buttons.append(&cancel);
        buttons.append(&join);
        let form = vbox(6);
        form.add_css_class("form");
        form.append(&identity_label);
        form.append(&identity);
        form.append(&label("Password", &["dim", "small"]));
        form.append(&password);
        form.append(&error);
        form.append(&buttons);
        let revealer = gtk::Revealer::builder()
            .transition_type(gtk::RevealerTransitionType::SlideDown)
            .transition_duration(160)
            .child(&form)
            .build();
        self.body.append(&revealer);

        let weak = Rc::downgrade(self);
        cancel.connect_clicked(move |_| {
            if let Some(row) = weak.upgrade() {
                row.collapse();
            }
        });
        let weak = Rc::downgrade(self);
        let submit = Rc::new(move || {
            if let Some(row) = weak.upgrade()
                && let Some(ui) = row.ui.upgrade()
            {
                ui.join_row(&row);
            }
        });
        let on_click = submit.clone();
        join.connect_clicked(move |_| on_click());
        password.connect_activate(move |_| submit());
        let to_password = password.clone();
        identity.connect_activate(move |_| {
            to_password.grab_focus();
        });
        let login = self.network.borrow().security == Security::Enterprise;
        identity_label.set_visible(login);
        identity.set_visible(login);
        JoinForm {
            revealer,
            identity_label,
            identity,
            password,
            error,
        }
    }

    fn update(&self, network: &Network) {
        self.icon.set_level(model::signal_level(network.strength));
        self.name.set_text(&network.ssid);
        self.row.set_widget_name(&network.ssid.to_lowercase());
        self.lock.set_visible(network.security.secured());
        let mut notes = Vec::new();
        if !network.security.secured() {
            notes.push(network.security.label().to_owned());
        }
        if network.bands.len() > 1 {
            notes.push(model::bands_label(&network.bands));
        } else if network.ap_count > 1 {
            notes.push(format!("{} access points", network.ap_count));
        }
        if !self.failed.get() {
            self.note.remove_css_class("error");
            self.note.add_css_class("dim");
            self.note.set_text(&notes.join(" · "));
            self.note.set_visible(!notes.is_empty());
        }
        if let Some(form) = self.form.borrow().as_ref() {
            let login = network.security == Security::Enterprise;
            form.identity_label.set_visible(login);
            form.identity.set_visible(login);
        }
        let secured = if network.security.secured() {
            ", secured"
        } else {
            ""
        };
        self.row
            .update_property(&[gtk::accessible::Property::Label(&format!(
                "{}, {} signal{secured}",
                network.ssid,
                model::signal_label(network.strength),
            ))]);
        *self.network.borrow_mut() = network.clone();
    }

    fn expanded(&self) -> bool {
        self.form
            .borrow()
            .as_ref()
            .is_some_and(|f| f.revealer.reveals_child())
    }

    fn expand(self: &Rc<Self>) {
        if self.form.borrow().is_none() {
            let form = self.build_form();
            *self.form.borrow_mut() = Some(form);
        }
        let form = self.form.borrow();
        let Some(form) = form.as_ref() else { return };
        self.row.add_css_class("expanded");
        form.revealer.set_reveal_child(true);
        if WidgetExt::is_visible(&form.identity) && form.identity.text().is_empty() {
            form.identity.grab_focus();
        } else {
            form.password.grab_focus();
        }
    }

    fn collapse(&self) {
        self.row.remove_css_class("expanded");
        if let Some(form) = self.form.borrow().as_ref() {
            form.revealer.set_reveal_child(false);
            form.password.set_text("");
            form.error.set_visible(false);
            form.password.remove_css_class("warn");
        }
    }

    fn show_error(self: &Rc<Self>, message: &str) {
        if !self.expanded() {
            self.expand();
        }
        if let Some(form) = self.form.borrow().as_ref() {
            form.error.set_text(message);
            form.error.set_visible(true);
            form.password.add_css_class("warn");
        }
    }

    /// A failed attempt, noted on the folded row until it's tried again.
    fn mark_failed(&self, message: &str) {
        self.failed.set(true);
        self.note.remove_css_class("dim");
        self.note.add_css_class("error");
        self.note.set_text(message);
        self.note.set_visible(true);
    }

    fn clear_failed(&self) {
        if self.failed.replace(false) {
            let network = self.network.borrow().clone();
            self.update(&network);
        }
    }

    /// What the form holds, or why it can't be sent.
    fn secret(&self) -> Result<Secret, &'static str> {
        let security = self.network.borrow().security;
        let form = self.form.borrow();
        let (identity, password) = form
            .as_ref()
            .map(|f| (f.identity.text().to_string(), f.password.text().to_string()))
            .unwrap_or_default();
        secret_for(security, &identity, &password)
    }
}

fn secret_for(security: Security, identity: &str, password: &str) -> Result<Secret, &'static str> {
    match security {
        Security::Open | Security::EnhancedOpen => Ok(Secret::None),
        Security::Enterprise => {
            if identity.is_empty() || password.is_empty() {
                Err("Enter your username and password.")
            } else {
                Ok(Secret::Login {
                    eap: Eap::Peap,
                    identity: identity.to_owned(),
                    password: password.to_owned(),
                })
            }
        }
        Security::Wep => {
            if password.is_empty() {
                Err("Enter the network's key.")
            } else {
                Ok(Secret::Key(password.to_owned()))
            }
        }
        _ if password.len() < 8 => Err("Wi-Fi passwords are at least 8 characters."),
        _ if password.len() > 64 => Err("Wi-Fi passwords are at most 63 characters."),
        _ => Ok(Secret::Key(password.to_owned())),
    }
}

/// NetworkManager's D-Bus errors, shortened for a one-line message.
fn friendly(error: &zbus::Error) -> String {
    let text = error.to_string();
    if text.contains("psk") || text.contains("wep-key") {
        "That password isn't valid for this network.".into()
    } else if text.contains("NotAuthorized") || text.contains("PermissionDenied") {
        "Not allowed to change this network.".into()
    } else {
        format!(
            "Couldn't connect: {}",
            text.rsplit(": ").next().unwrap_or(&text)
        )
    }
}

/// The current network's card, and its details.
struct Card {
    root: gtk::Box,
    icon: SignalIcon,
    title: gtk::Label,
    subtitle: gtk::Label,
    expander: gtk::Button,
    details: gtk::Revealer,
    values: Vec<gtk::Label>,
    ip6_key: gtk::Label,
    ip6: gtk::Label,
    portal: gtk::Button,
    disconnect: gtk::Button,
    share: gtk::Button,
    forget: gtk::Button,
    forget_armed: Cell<bool>,
    shared: gtk::Revealer,
    key: gtk::Label,
    qr: Qr,
    chevron: widgets::Chevron,
}

const DETAIL_KEYS: [&str; 6] = ["Signal", "Speed", "Channel", "IPv4", "Gateway", "DNS"];

impl Card {
    fn new() -> Self {
        let icon = SignalIcon::new(18, 4);
        let badge = gtk::Box::builder()
            .halign(gtk::Align::Center)
            .valign(gtk::Align::Center)
            .build();
        badge.add_css_class("badge");
        icon.area.set_halign(gtk::Align::Center);
        icon.area.set_hexpand(true);
        badge.append(&icon.area);
        let title = label("", &["name"]);
        title.set_ellipsize(pango::EllipsizeMode::End);
        let subtitle = label("", &["dim"]);
        subtitle.set_ellipsize(pango::EllipsizeMode::End);
        let text = vbox(2);
        text.set_hexpand(true);
        text.set_valign(gtk::Align::Center);
        text.append(&title);
        text.append(&subtitle);
        let chevron = widgets::Chevron::new(14);
        let expander = gtk::Button::builder()
            .child(&chevron.area)
            .tooltip_text("Show details")
            .build();
        expander.add_css_class("icon");
        expander.update_property(&[gtk::accessible::Property::Label("Show details")]);
        expander.set_valign(gtk::Align::Center);
        let head = hbox(10);
        head.append(&badge);
        head.append(&text);
        head.append(&expander);

        let grid = gtk::Grid::builder()
            .column_spacing(10)
            .row_spacing(8)
            .column_homogeneous(true)
            .build();
        grid.set_margin_start(4);
        grid.set_margin_end(4);
        let mut values = Vec::new();
        for (i, key) in DETAIL_KEYS.iter().enumerate() {
            let cell = vbox(2);
            cell.append(&label(key, &["dim", "small"]));
            let value = label("", &[]);
            value.set_ellipsize(pango::EllipsizeMode::End);
            value.set_selectable(true);
            value.add_css_class("small");
            cell.append(&value);
            grid.attach(&cell, (i % 3) as i32, (i / 3) as i32, 1, 1);
            values.push(value);
        }
        let ip6_key = label("IPv6", &["dim", "small"]);
        let ip6 = label("", &["small"]);
        ip6.set_selectable(true);
        ip6.set_ellipsize(pango::EllipsizeMode::Middle);
        let ip6_cell = vbox(2);
        ip6_cell.append(&ip6_key);
        ip6_cell.append(&ip6);
        grid.attach(&ip6_cell, 0, 2, 3, 1);

        let portal = button("Open sign-in page", &["pill", "accent"]);
        let disconnect = button("Disconnect", &["pill"]);
        let share = button("Share password", &["pill"]);
        let forget = button("Forget", &["pill"]);
        for b in [&disconnect, &share, &forget] {
            b.set_hexpand(true);
        }
        let actions = hbox(6);
        actions.append(&disconnect);
        actions.append(&share);
        actions.append(&forget);

        let key = label("", &["key"]);
        key.set_selectable(true);
        key.set_halign(gtk::Align::Center);
        let qr = Qr::new(148);
        let copy = button("Copy password", &["pill"]);
        copy.set_halign(gtk::Align::Center);
        let copied_key = key.clone();
        copy.connect_clicked(move |b| {
            b.clipboard().set_text(&copied_key.text());
            b.set_label("Copied");
            let b = b.clone();
            glib::timeout_add_local_once(Duration::from_secs(2), move || {
                b.set_label("Copy password")
            });
        });
        let share_box = vbox(8);
        share_box.set_margin_top(4);
        share_box.append(&qr.area);
        share_box.append(&key);
        share_box.append(&copy);
        let shared = gtk::Revealer::builder()
            .transition_type(gtk::RevealerTransitionType::SlideDown)
            .child(&share_box)
            .build();

        let details_box = vbox(10);
        details_box.set_margin_top(10);
        details_box.append(&grid);
        details_box.append(&actions);
        details_box.append(&shared);
        let details = gtk::Revealer::builder()
            .transition_type(gtk::RevealerTransitionType::SlideDown)
            .transition_duration(180)
            .child(&details_box)
            .build();

        let root = vbox(0);
        root.add_css_class("current");
        root.append(&head);
        portal.set_margin_top(10);
        root.append(&portal);
        root.append(&details);
        Self {
            root,
            icon,
            title,
            subtitle,
            expander,
            details,
            values,
            ip6_key,
            ip6,
            portal,
            disconnect,
            share,
            forget,
            forget_armed: Cell::new(false),
            shared,
            key,
            qr,
            chevron,
        }
    }

    fn set_expanded(&self, expanded: bool) {
        self.details.set_reveal_child(expanded);
        self.chevron.set_up(expanded);
        let tip = if expanded {
            "Hide details"
        } else {
            "Show details"
        };
        self.expander.set_tooltip_text(Some(tip));
        self.expander
            .update_property(&[gtk::accessible::Property::Label(tip)]);
        if !expanded {
            self.hide_shared();
            self.disarm_forget();
        }
    }

    fn hide_shared(&self) {
        self.shared.set_reveal_child(false);
        self.share.set_label("Share password");
        self.key.set_text("");
        self.qr.set_text(None);
    }

    fn disarm_forget(&self) {
        self.forget_armed.set(false);
        self.forget.set_label("Forget");
        self.forget.remove_css_class("danger");
    }

    fn update(&self, current: &model::Current, connectivity: Connectivity) {
        self.title.set_text(&if current.hotspot {
            format!("Hotspot: {}", current.ssid)
        } else {
            current.ssid.clone()
        });
        let band = model::Band::from_frequency(current.frequency);
        let mut parts: Vec<String> = Vec::new();
        match current.state {
            NetState::Active if current.hotspot => parts.push("Sharing this connection".into()),
            NetState::Active => parts.push("Connected".into()),
            _ => parts.push("Connecting…".into()),
        }
        if let Some(band) = band {
            parts.push(band.label().into());
        }
        if let Some(security) = current.security.filter(|_| !current.hotspot) {
            parts.push(security.label().into());
        }
        if current.state == NetState::Active {
            match connectivity {
                Connectivity::Portal => parts.push("Sign-in required".into()),
                Connectivity::Limited | Connectivity::None => parts.push("No internet".into()),
                _ => {}
            }
        }
        self.subtitle.set_text(&parts.join(" · "));
        self.icon
            .set_level(if current.hotspot || current.strength == 0 {
                4
            } else {
                model::signal_level(current.strength)
            });
        self.portal
            .set_visible(current.state == NetState::Active && connectivity == Connectivity::Portal);

        let channel = model::channel(current.frequency)
            .map(|c| {
                format!(
                    "{c}{}",
                    band.map(|b| format!(" · {}", b.label().trim_end_matches(" GHz")))
                        .unwrap_or_default()
                )
            })
            .unwrap_or_else(|| "—".into());
        let or_dash = |v: Option<&String>| v.cloned().unwrap_or_else(|| "—".into());
        let signal = if current.strength > 0 {
            format!("{}%", current.strength)
        } else {
            "—".into()
        };
        let speed = if current.bitrate > 0 {
            model::speed_label(current.bitrate)
        } else {
            "—".into()
        };
        let values = [
            signal,
            speed,
            channel,
            or_dash(current.ip4.as_ref()),
            or_dash(current.gateway.as_ref()),
            or_dash(current.dns.first()),
        ];
        for (label, value) in self.values.iter().zip(values) {
            label.set_text(&value);
        }
        self.ip6
            .set_text(current.ip6.as_deref().unwrap_or_default());
        self.ip6_key.set_visible(current.ip6.is_some());
        self.ip6.set_visible(current.ip6.is_some());
        self.disconnect.set_label(if current.hotspot {
            "Stop hotspot"
        } else {
            "Disconnect"
        });
        self.share
            .set_visible(current.security.is_none_or(|s| s.secured()));
        self.forget.set_visible(!current.hotspot);
    }
}

/// A password prompt from NetworkManager (the secret agent) for a network
/// being joined or re-joined.
struct Prompt {
    root: gtk::Box,
    title: gtk::Label,
    message: gtk::Label,
    identity_label: gtk::Label,
    identity: gtk::Entry,
    password: gtk::PasswordEntry,
    error: gtk::Label,
    cancel: gtk::Button,
    join: gtk::Button,
    request: RefCell<Option<SecretRequest>>,
}

impl Prompt {
    fn new() -> Self {
        let title = label("", &["name"]);
        let message = label("", &["dim"]);
        message.set_wrap(true);
        let identity_label = label("Username", &["dim", "small"]);
        let identity = gtk::Entry::new();
        let password = gtk::PasswordEntry::builder().show_peek_icon(true).build();
        password.update_property(&[gtk::accessible::Property::Label("Password")]);
        let error = label("", &["error"]);
        error.set_visible(false);
        let cancel = button("Cancel", &["pill"]);
        let join = button("Join", &["pill", "accent"]);
        let buttons = hbox(6);
        buttons.set_halign(gtk::Align::End);
        buttons.append(&cancel);
        buttons.append(&join);
        let root = vbox(6);
        root.add_css_class("prompt");
        root.append(&title);
        root.append(&message);
        root.append(&identity_label);
        root.append(&identity);
        root.append(&label("Password", &["dim", "small"]));
        root.append(&password);
        root.append(&error);
        root.append(&buttons);
        root.set_visible(false);
        Self {
            root,
            title,
            message,
            identity_label,
            identity,
            password,
            error,
            cancel,
            join,
            request: RefCell::default(),
        }
    }

    fn show(&self, request: SecretRequest) {
        self.title.set_text(&request.ssid);
        let (message, login) = match (&request.kind, request.retry) {
            (Kind::Login { identity }, retry) => {
                self.identity.set_text(identity);
                (
                    if retry {
                        "That login didn't work. Try again."
                    } else {
                        "Sign in to join this network."
                    },
                    true,
                )
            }
            (Kind::Key { .. }, true) => ("That password didn't work. Try again.", false),
            (Kind::Key { .. }, false) => ("This network needs its password.", false),
        };
        self.message.set_text(message);
        self.identity_label.set_visible(login);
        self.identity.set_visible(login);
        self.password.set_text("");
        self.error.set_visible(false);
        self.root.set_visible(true);
        if login && self.identity.text().is_empty() {
            self.identity.grab_focus();
        } else {
            self.password.grab_focus();
        }
        // A newer request replaces (and so cancels) an older one.
        *self.request.borrow_mut() = Some(request);
    }

    fn answer(&self, secret: Option<Secret>) {
        if let Some(request) = self.request.borrow_mut().take() {
            let _ = request.reply.try_send(secret);
        }
        self.root.set_visible(false);
        self.password.set_text("");
    }

    fn submit(&self) {
        let login = self
            .request
            .borrow()
            .as_ref()
            .is_some_and(|r| matches!(r.kind, Kind::Login { .. }));
        let wep = self
            .request
            .borrow()
            .as_ref()
            .is_some_and(|r| r.kind == Kind::Key { wep: true });
        let security = if login {
            Security::Enterprise
        } else if wep {
            Security::Wep
        } else {
            Security::Wpa2
        };
        match secret_for(security, &self.identity.text(), &self.password.text()) {
            Ok(secret) => self.answer(Some(secret)),
            Err(message) => {
                self.error.set_text(message);
                self.error.set_visible(true);
            }
        }
    }

    fn active(&self) -> bool {
        self.request.borrow().is_some()
    }
}

/// The "connect to hidden network" form.
struct HiddenForm {
    revealer: gtk::Revealer,
    name: gtk::Entry,
    kinds: Vec<(gtk::ToggleButton, Security)>,
    identity: gtk::Entry,
    password: gtk::PasswordEntry,
    error: gtk::Label,
    join: gtk::Button,
}

impl HiddenForm {
    fn new() -> Rc<Self> {
        let name = gtk::Entry::builder()
            .placeholder_text("Network name")
            .build();
        name.update_property(&[gtk::accessible::Property::Label("Network name")]);
        let segmented = hbox(0);
        segmented.add_css_class("segmented");
        segmented.set_homogeneous(false);
        let mut kinds = Vec::new();
        let mut first: Option<gtk::ToggleButton> = None;
        for (text, security) in [
            ("Open", Security::Open),
            ("WPA2", Security::Wpa2),
            ("WPA3", Security::Wpa3),
            ("Enterprise", Security::Enterprise),
        ] {
            let toggle = gtk::ToggleButton::with_label(text);
            if let Some(first) = &first {
                toggle.set_group(Some(first));
            } else {
                first = Some(toggle.clone());
            }
            segmented.append(&toggle);
            kinds.push((toggle, security));
        }
        let identity = gtk::Entry::builder().placeholder_text("Username").build();
        identity.update_property(&[gtk::accessible::Property::Label("Username")]);
        let password = gtk::PasswordEntry::builder()
            .show_peek_icon(true)
            .placeholder_text("Password")
            .build();
        password.update_property(&[gtk::accessible::Property::Label("Password")]);
        let error = label("", &["error"]);
        error.set_visible(false);
        error.set_wrap(true);
        let cancel = button("Cancel", &["pill"]);
        let join = button("Join", &["pill", "accent"]);
        let buttons = hbox(6);
        buttons.set_halign(gtk::Align::End);
        buttons.append(&cancel);
        buttons.append(&join);
        let form = vbox(6);
        form.add_css_class("form");
        form.set_margin_top(4);
        form.append(&name);
        form.append(&segmented);
        form.append(&identity);
        form.append(&password);
        form.append(&error);
        form.append(&buttons);
        let revealer = gtk::Revealer::builder()
            .transition_type(gtk::RevealerTransitionType::SlideDown)
            .child(&form)
            .build();
        let this = Rc::new(Self {
            revealer,
            name,
            kinds,
            identity,
            password,
            error,
            join,
        });
        this.kinds[1].0.set_active(true);
        for (toggle, _) in &this.kinds {
            let weak = Rc::downgrade(&this);
            toggle.connect_toggled(move |_| {
                if let Some(form) = weak.upgrade() {
                    form.sync();
                }
            });
        }
        let weak = Rc::downgrade(&this);
        cancel.connect_clicked(move |_| {
            if let Some(form) = weak.upgrade() {
                form.close();
            }
        });
        this.sync();
        this
    }

    fn security(&self) -> Security {
        self.kinds
            .iter()
            .find(|(t, _)| t.is_active())
            .map_or(Security::Wpa2, |(_, s)| *s)
    }

    fn sync(&self) {
        let security = self.security();
        self.identity.set_visible(security == Security::Enterprise);
        self.password.set_visible(security != Security::Open);
    }

    fn open(&self) {
        self.revealer.set_reveal_child(true);
        self.name.grab_focus();
    }

    fn close(&self) {
        self.revealer.set_reveal_child(false);
        self.name.set_text("");
        self.password.set_text("");
        self.identity.set_text("");
        self.error.set_visible(false);
    }

    fn show_error(&self, message: &str) {
        self.error.set_text(message);
        self.error.set_visible(true);
    }
}

/// The "create hotspot" form.
struct HotspotForm {
    revealer: gtk::Revealer,
    name: gtk::Entry,
    password: gtk::PasswordEntry,
    error: gtk::Label,
    start: gtk::Button,
}

impl HotspotForm {
    fn new() -> Rc<Self> {
        let name = gtk::Entry::builder()
            .placeholder_text("Hotspot name")
            .build();
        name.update_property(&[gtk::accessible::Property::Label("Hotspot name")]);
        let password = gtk::PasswordEntry::builder()
            .show_peek_icon(true)
            .placeholder_text("Password")
            .build();
        password.update_property(&[gtk::accessible::Property::Label("Password")]);
        let note = label(
            "Other devices share this computer's connection. Wi-Fi disconnects while it runs.",
            &["dim", "small"],
        );
        note.set_wrap(true);
        let error = label("", &["error"]);
        error.set_visible(false);
        error.set_wrap(true);
        let cancel = button("Cancel", &["pill"]);
        let start = button("Start", &["pill", "accent"]);
        let buttons = hbox(6);
        buttons.set_halign(gtk::Align::End);
        buttons.append(&cancel);
        buttons.append(&start);
        let form = vbox(6);
        form.add_css_class("form");
        form.set_margin_top(4);
        form.append(&name);
        form.append(&password);
        form.append(&note);
        form.append(&error);
        form.append(&buttons);
        let revealer = gtk::Revealer::builder()
            .transition_type(gtk::RevealerTransitionType::SlideDown)
            .child(&form)
            .build();
        let this = Rc::new(Self {
            revealer,
            name,
            password,
            error,
            start,
        });
        let weak = Rc::downgrade(&this);
        cancel.connect_clicked(move |_| {
            if let Some(form) = weak.upgrade() {
                form.close();
            }
        });
        this
    }

    fn open(&self) {
        if self.name.text().is_empty() {
            self.name
                .set_text(&format!("{} hotspot", glib::host_name()));
        }
        if self.password.text().is_empty() {
            self.password.set_text(&random_password());
        }
        self.revealer.set_reveal_child(true);
        self.start.grab_focus();
    }

    fn close(&self) {
        self.revealer.set_reveal_child(false);
        self.error.set_visible(false);
    }
}

/// Ten characters without look-alikes, for reading off to someone.
fn random_password() -> String {
    const ALPHABET: &[u8] = b"abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789";
    let mut bytes = [0u8; 10];
    if let Ok(mut f) = std::fs::File::open("/dev/urandom") {
        use std::io::Read as _;
        let _ = f.read_exact(&mut bytes);
    }
    bytes
        .iter()
        .map(|b| ALPHABET[usize::from(*b) % ALPHABET.len()] as char)
        .collect()
}

struct Pending {
    ssid: Vec<u8>,
    /// A connection this attempt created; deleted if it never comes up.
    created: Option<String>,
    seen: bool,
    started: Instant,
}

pub struct Ui {
    opts: Options,
    window: gtk::Window,
    panel: gtk::Box,
    wifi: Toggle,
    notice: gtk::Box,
    notice_label: gtk::Label,
    notice_action: gtk::Button,
    search_revealer: gtk::Revealer,
    search: gtk::SearchEntry,
    card: Card,
    prompt: Prompt,
    lists: gtk::ScrolledWindow,
    known_box: gtk::Box,
    known_list: gtk::ListBox,
    other_list: gtk::ListBox,
    other_empty: gtk::Label,
    scan_state: gtk::Stack,
    wired_box: gtk::Box,
    wired_list: gtk::ListBox,
    vpn_box: gtk::Box,
    vpn_list: gtk::ListBox,
    hidden: Rc<HiddenForm>,
    hotspot: Rc<HotspotForm>,
    hotspot_button: gtk::Button,
    airplane_toggle: Toggle,
    rows: RefCell<HashMap<NetworkKey, Rc<NetRow>>>,
    /// Whether "Other networks" lists everything, not just the strongest.
    show_all: Rc<Cell<bool>>,
    show_more: gtk::Button,
    rendered_extras: RefCell<(Vec<model::Wired>, Vec<model::Vpn>)>,
    snapshot: RefCell<Snapshot>,
    started: Cell<bool>,
    airplane: Cell<bool>,
    system: RefCell<Option<Connection>>,
    tray: RefCell<Option<Tray>>,
    rfkill: RefCell<Option<Rc<Rfkill>>>,
    notifier: Notifier,
    pending: RefCell<Option<Pending>>,
    scan: Cell<Option<(Instant, i64)>>,
    quiet_until: Cell<Option<Instant>>,
    was_active: Cell<bool>,
    icon_dir: String,
    phase: Cell<u8>,
    animating: Cell<bool>,
}

impl Ui {
    fn new(app: &gtk::Application, opts: Options, icon_dir: String) -> Rc<Self> {
        let window = gtk::Window::builder()
            .application(app)
            .title("Network")
            .build();
        window.add_css_class("net-panel");
        window.init_layer_shell();
        window.set_layer(Layer::Top);
        window.set_namespace(Some("net-panel"));
        window.set_keyboard_mode(KeyboardMode::OnDemand);
        // The window covers the monitor below the bar, clear but for the
        // panel: a click anywhere else closes it, and the pointer passing
        // over windows can't move focus (Hyprland's follow_mouse) and close
        // it mid-reach. The bar stays clear, so the tray icon still toggles.
        for edge in [Edge::Top, Edge::Right, Edge::Bottom, Edge::Left] {
            window.set_anchor(edge, true);
        }
        window.set_exclusive_zone(0);

        let (wifi, _) = Toggle::new("Wi-Fi");
        let header = hbox(8);
        let title = label("Wi-Fi", &["title"]);
        title.set_hexpand(true);
        header.append(&title);
        header.append(&wifi.switch);
        header.set_margin_start(4);
        header.set_margin_end(4);

        let search = gtk::SearchEntry::builder()
            .placeholder_text("Search networks")
            .build();
        let search_revealer = gtk::Revealer::builder().child(&search).build();

        let notice_label = label("", &["dim"]);
        notice_label.set_hexpand(true);
        notice_label.set_wrap(true);
        let notice_action = button("", &["pill"]);
        let notice = hbox(8);
        notice.set_margin_start(4);
        notice.append(&notice_label);
        notice.append(&notice_action);
        notice.set_visible(false);

        let card = Card::new();
        let prompt = Prompt::new();

        let section = |title: &str| {
            let box_ = vbox(2);
            let heading = hbox(4);
            let label = label(title, &["section-title"]);
            label.set_hexpand(true);
            label.set_margin_start(6);
            heading.append(&label);
            heading.set_margin_bottom(4);
            box_.append(&heading);
            let list = gtk::ListBox::builder()
                .selection_mode(gtk::SelectionMode::None)
                .build();
            box_.append(&list);
            (box_, heading, list)
        };
        let (known_box, _, known_list) = section("Known networks");
        let (other_box, other_heading, other_list) = section("Other networks");
        // The refresh button, or three breathing dots (style.css) while a
        // scan runs.
        let rescan = icon_button("view-refresh-symbolic", "Scan again");
        let dots = hbox(3);
        dots.add_css_class("scan-dots");
        dots.set_halign(gtk::Align::Center);
        dots.set_valign(gtk::Align::Center);
        dots.update_property(&[gtk::accessible::Property::Label("Scanning")]);
        for _ in 0..3 {
            let dot = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            dot.add_css_class("dot");
            dots.append(&dot);
        }
        let scan_state = gtk::Stack::builder()
            .transition_type(gtk::StackTransitionType::Crossfade)
            .transition_duration(150)
            .build();
        scan_state.add_named(&rescan, Some("idle"));
        scan_state.add_named(&dots, Some("scanning"));
        other_heading.append(&scan_state);
        let other_empty = label("No other networks in range", &["dim"]);
        other_empty.set_margin_start(6);
        other_empty.set_visible(false);
        other_box.append(&other_empty);
        let show_more = button("", &["footer-item", "show-more"]);
        if let Some(child) = show_more.child().and_downcast::<gtk::Label>() {
            child.set_xalign(0.0);
        }
        show_more.set_visible(false);
        other_box.append(&show_more);
        let (wired_box, _, wired_list) = section("Wired");
        let (vpn_box, _, vpn_list) = section("VPN");

        let lists_box = vbox(12);
        lists_box.append(&known_box);
        lists_box.append(&other_box);
        let lists = gtk::ScrolledWindow::builder()
            .hscrollbar_policy(gtk::PolicyType::Never)
            .propagate_natural_height(true)
            .max_content_height(400)
            .child(&lists_box)
            .build();

        let hidden = HiddenForm::new();
        let hotspot = HotspotForm::new();
        let hidden_button = button("Connect to hidden network…", &["footer-item"]);
        let hotspot_button = button("Create hotspot…", &["footer-item"]);
        let settings_button = button("Network settings…", &["footer-item"]);
        for b in [&hidden_button, &hotspot_button, &settings_button] {
            if let Some(child) = b.child().and_downcast::<gtk::Label>() {
                child.set_xalign(0.0);
            }
        }
        let (airplane_toggle, airplane_label) = Toggle::new("Airplane mode");
        let toggle_row = |label: &gtk::Label, toggle: &Toggle| {
            let row = hbox(8);
            row.set_margin_start(8);
            row.set_margin_end(4);
            row.set_size_request(-1, 34);
            label.set_hexpand(true);
            label.add_css_class("footer-label");
            row.append(label);
            row.append(&toggle.switch);
            row
        };
        let footer = vbox(0);
        footer.append(&hidden_button);
        footer.append(&hidden.revealer);
        footer.append(&hotspot_button);
        footer.append(&hotspot.revealer);
        footer.append(&toggle_row(&airplane_label, &airplane_toggle));
        footer.append(&settings_button);

        let panel = vbox(12);
        panel.add_css_class("panel");
        panel.set_size_request(PANEL_WIDTH, -1);
        panel.set_halign(gtk::Align::End);
        panel.set_valign(gtk::Align::Start);
        panel.append(&search_revealer);
        panel.append(&header);
        panel.append(&notice);
        panel.append(&prompt.root);
        panel.append(&card.root);
        panel.append(&lists);
        panel.append(&wired_box);
        panel.append(&vpn_box);
        panel.append(&gtk::Separator::new(gtk::Orientation::Horizontal));
        panel.append(&footer);
        window.set_child(Some(&panel));

        let ui = Rc::new(Self {
            opts,
            window,
            panel,
            wifi,
            notice,
            notice_label,
            notice_action,
            search_revealer,
            search,
            card,
            prompt,
            lists,
            known_box,
            known_list,

            other_list,
            other_empty,
            scan_state,
            wired_box,
            wired_list,
            vpn_box,
            vpn_list,
            hidden,
            hotspot,
            hotspot_button,
            airplane_toggle,
            rows: RefCell::default(),
            show_all: Rc::default(),
            show_more,
            rendered_extras: RefCell::default(),
            snapshot: RefCell::default(),
            started: Cell::new(false),
            airplane: Cell::new(false),
            system: RefCell::default(),
            tray: RefCell::default(),
            rfkill: RefCell::default(),
            notifier: Notifier::default(),
            pending: RefCell::default(),
            scan: Cell::new(None),
            quiet_until: Cell::new(None),
            was_active: Cell::new(false),
            icon_dir,
            phase: Cell::new(1),
            animating: Cell::new(false),
        });
        ui.connect(&rescan, &hidden_button, &settings_button);
        ui
    }

    fn connect(
        self: &Rc<Self>,
        rescan: &gtk::Button,
        hidden_button: &gtk::Button,
        settings_button: &gtk::Button,
    ) {
        let weak = Rc::downgrade(self);
        let with = move |f: fn(&Rc<Ui>)| {
            let weak = weak.clone();
            move || {
                if let Some(ui) = weak.upgrade() {
                    f(&ui);
                }
            }
        };

        let wifi = Rc::downgrade(self);
        self.wifi.on_toggle(move |on| {
            if let Some(ui) = wifi.upgrade() {
                ui.run(move |conn| async move { nm::set_wifi_enabled(&conn, on).await });
            }
        });
        let weak = Rc::downgrade(self);
        self.airplane_toggle.on_toggle(move |on| {
            if let Some(ui) = weak.upgrade() {
                ui.set_airplane(on);
            }
        });

        let f = with(Ui::rescan);
        rescan.connect_clicked(move |_| f());
        let f = with(|ui| {
            ui.hotspot.close();
            ui.hidden.open();
        });
        hidden_button.connect_clicked(move |_| f());
        let f = with(Ui::hotspot_clicked);
        self.hotspot_button.connect_clicked(move |_| f());
        let f = with(Ui::launch_editor);
        settings_button.connect_clicked(move |_| f());
        let f = with(Ui::join_hidden);
        self.hidden.join.connect_clicked(move |_| f());
        let f = with(Ui::join_hidden);
        self.hidden.password.connect_activate(move |_| f());
        let f = with(Ui::start_hotspot);
        self.hotspot.start.connect_clicked(move |_| f());
        let f = with(Ui::notice_clicked);
        self.notice_action.connect_clicked(move |_| f());

        let f = with(|ui| {
            let expanded = !ui.card.details.reveals_child();
            ui.card.set_expanded(expanded);
        });
        self.card.expander.connect_clicked(move |_| f());
        let f = with(Ui::disconnect_current);
        self.card.disconnect.connect_clicked(move |_| f());
        let f = with(Ui::share_clicked);
        self.card.share.connect_clicked(move |_| f());
        let f = with(Ui::forget_clicked);
        self.card.forget.connect_clicked(move |_| f());
        self.card.portal.connect_clicked(|_| {
            // Any plain-HTTP page gets redirected to the portal's login.
            let _ = gio::AppInfo::launch_default_for_uri(
                "http://neverssl.com",
                None::<&gio::AppLaunchContext>,
            );
        });

        let f = with(|ui| ui.prompt.submit());
        self.prompt.join.connect_clicked(move |_| f());
        let f = with(|ui| ui.prompt.submit());
        self.prompt.password.connect_activate(move |_| f());
        let f = with(|ui| ui.prompt.answer(None));
        self.prompt.cancel.connect_clicked(move |_| f());

        for (list, limited) in [(&self.known_list, false), (&self.other_list, true)] {
            let weak = Rc::downgrade(self);
            list.connect_row_activated(move |_, row| {
                if let Some(ui) = weak.upgrade() {
                    ui.row_activated(row);
                }
            });
            // Typing searches every network; otherwise "Other networks" shows
            // only its strongest few until "Show more".
            let (search, show_all) = (self.search.clone(), self.show_all.clone());
            list.set_filter_func(move |row| {
                let query = search.text().to_lowercase();
                if !query.is_empty() {
                    return row.widget_name().contains(query.as_str());
                }
                !limited
                    || show_all.get()
                    || row.index() < OTHER_LIMIT
                    || row.has_css_class("expanded")
            });
        }
        let f = with(|ui| {
            ui.show_all.set(true);
            ui.other_list.invalidate_filter();
            ui.update_show_more();
        });
        self.show_more.connect_clicked(move |_| f());

        self.search.set_key_capture_widget(Some(&self.window));
        let weak = Rc::downgrade(self);
        self.search.connect_search_changed(move |entry| {
            if let Some(ui) = weak.upgrade() {
                ui.search_revealer
                    .set_reveal_child(!entry.text().is_empty());
                ui.known_list.invalidate_filter();
                ui.other_list.invalidate_filter();
                ui.update_show_more();
            }
        });
        let weak = Rc::downgrade(self);
        self.search.connect_stop_search(move |entry| {
            entry.set_text("");
            if let Some(ui) = weak.upgrade() {
                ui.hide();
            }
        });

        let keys = gtk::EventControllerKey::new();
        let weak = Rc::downgrade(self);
        keys.connect_key_pressed(move |_, key, _, _| {
            let Some(ui) = weak.upgrade() else {
                return glib::Propagation::Proceed;
            };
            if key != gdk::Key::Escape {
                return glib::Propagation::Proceed;
            }
            if !ui.search.text().is_empty() {
                ui.search.set_text("");
            } else if !ui.collapse_forms() {
                ui.hide();
            }
            glib::Propagation::Stop
        });
        self.window.add_controller(keys);

        // A click on the clear part of the window, outside the panel, closes it.
        let outside = gtk::GestureClick::new();
        outside.set_button(0);
        let weak = Rc::downgrade(self);
        outside.connect_pressed(move |gesture, _, x, y| {
            let Some(ui) = weak.upgrade() else { return };
            let inside = ui
                .panel
                .compute_bounds(&ui.window)
                .is_some_and(|b| b.contains_point(&gtk::graphene::Point::new(x as f32, y as f32)));
            if !inside {
                gesture.set_state(gtk::EventSequenceState::Claimed);
                ui.hide();
            }
        });
        self.window.add_controller(outside);

        // Close when focus goes elsewhere, say a keybind switching windows
        // (Hyprland focuses the panel when it maps).
        let weak = Rc::downgrade(self);
        self.window.connect_is_active_notify(move |window| {
            let Some(ui) = weak.upgrade() else { return };
            if window.is_active() {
                ui.was_active.set(true);
            } else if ui.was_active.get() && window.is_visible() {
                let weak = Rc::downgrade(&ui);
                glib::timeout_add_local_once(Duration::from_millis(120), move || {
                    if let Some(ui) = weak.upgrade()
                        && !ui.window.is_active()
                        && ui.window.is_visible()
                    {
                        ui.hide();
                    }
                });
            }
        });
    }

    fn conn(&self) -> Option<Connection> {
        self.system.borrow().clone()
    }

    fn wifi_device(&self) -> Option<String> {
        self.snapshot.borrow().wifi.as_ref().map(|w| w.path.clone())
    }

    /// Runs a NetworkManager call, showing a failure in the notice line.
    fn run<F, Fut>(self: &Rc<Self>, f: F)
    where
        F: FnOnce(Connection) -> Fut + 'static,
        Fut: std::future::Future<Output = zbus::Result<()>> + 'static,
    {
        let Some(conn) = self.conn() else { return };
        let ui = self.clone();
        glib::spawn_future_local(async move {
            if let Err(e) = f(conn).await {
                ui.show_notice(&friendly(&e), None);
            }
        });
    }

    fn quiet(&self) {
        self.quiet_until.set(Some(Instant::now() + QUIET));
    }

    fn is_quiet(&self) -> bool {
        self.window.is_visible() || self.quiet_until.get().is_some_and(|t| Instant::now() < t)
    }

    pub fn handle(self: &Rc<Self>, event: Event) {
        match event {
            Event::Snapshot(snapshot) => self.apply(*snapshot),
            Event::Toggle(at) => {
                if self.window.is_visible() {
                    self.hide();
                } else {
                    self.show(at);
                }
            }
            Event::Agent(AgentEvent::Request(request)) => {
                self.prompt.show(request);
                self.card.root.set_visible(false);
                if !self.window.is_visible() {
                    self.show(None);
                }
            }
            Event::Agent(AgentEvent::Cancel {
                connection_path,
                setting,
            }) => {
                let matches =
                    self.prompt.request.borrow().as_ref().is_some_and(|r| {
                        r.connection_path == connection_path && r.setting == setting
                    });
                if matches {
                    // Dropping the request answers NetworkManager's GetSecrets.
                    self.prompt.request.borrow_mut().take();
                    self.prompt.root.set_visible(false);
                    self.render();
                }
            }
            Event::Airplane(on) => {
                self.airplane.set(on);
                self.render();
                self.update_tray();
            }
        }
    }

    fn apply(self: &Rc<Self>, snapshot: Snapshot) {
        let previous = self.snapshot.replace(snapshot);
        if self.started.replace(true) {
            self.notify_changes(&previous);
        }
        self.resolve_pending();
        self.render();
        self.update_tray();
    }

    fn resolve_pending(self: &Rc<Self>) {
        let snapshot = self.snapshot.borrow().clone();
        let failed = {
            let mut pending = self.pending.borrow_mut();
            let Some(p) = pending.as_mut() else { return };
            let state = snapshot
                .current
                .as_ref()
                .filter(|c| c.ssid_bytes == p.ssid)
                .map(|c| c.state);
            match state {
                Some(NetState::Active) => {
                    *pending = None;
                    None
                }
                Some(_) => {
                    p.seen = true;
                    None
                }
                None if p.seen || p.started.elapsed() > Duration::from_secs(30) => pending.take(),
                None => None,
            }
        };
        let Some(failed) = failed else { return };
        if let (Some(created), Some(conn)) = (failed.created, self.conn()) {
            // It never came up, so don't leave a connection with a bad key behind.
            glib::spawn_future_local(async move {
                let _ = nm::delete(&conn, &created).await;
            });
        }
        if let Some(row) = self.row_for_ssid(&failed.ssid) {
            row.mark_failed("Couldn't connect");
        }
    }

    /// The row an attempt by SSID belongs to (pending joins know no more).
    fn row_for_ssid(&self, ssid: &[u8]) -> Option<Rc<NetRow>> {
        self.rows
            .borrow()
            .values()
            .find(|r| r.network.borrow().ssid_bytes == ssid)
            .cloned()
    }

    fn update_show_more(&self) {
        let others = self
            .rows
            .borrow()
            .values()
            .filter(|r| r.placed.get() == Some(false))
            .count();
        let hidden = others.saturating_sub(OTHER_LIMIT as usize);
        let show = hidden > 0 && !self.show_all.get() && self.search.text().is_empty();
        self.show_more.set_visible(show);
        if show {
            self.show_more.set_label(&format!(
                "Show {hidden} more network{}",
                if hidden == 1 { "" } else { "s" }
            ));
        }
    }

    fn render(self: &Rc<Self>) {
        let snapshot = self.snapshot.borrow().clone();
        let airplane = self.airplane.get();
        let wifi_usable = snapshot.networking
            && snapshot.wifi_enabled
            && snapshot.wifi_hardware
            && !airplane
            && snapshot.wifi.is_some();

        self.wifi
            .set(snapshot.wifi_enabled && snapshot.wifi_hardware && !airplane);
        self.wifi.switch.set_sensitive(
            snapshot.networking && snapshot.wifi_hardware && !airplane && snapshot.wifi.is_some(),
        );
        self.airplane_toggle.set(airplane);
        self.airplane_toggle
            .switch
            .set_sensitive(self.rfkill.borrow().is_some());

        let notice = if airplane {
            Some(("Airplane mode is on.", Some("Turn off")))
        } else if !snapshot.networking {
            Some(("Networking is off.", Some("Turn on")))
        } else if snapshot.wifi.is_none() {
            Some(("No Wi-Fi adapter.", None))
        } else if !snapshot.wifi_hardware {
            Some(("Wi-Fi is off (hardware switch).", None))
        } else if !snapshot.wifi_enabled {
            Some(("Wi-Fi is off.", None))
        } else {
            None
        };
        match notice {
            Some((text, action)) => self.show_notice(text, action),
            None if self
                .notice_action
                .label()
                .is_some_and(|l| l == "Turn off" || l == "Turn on")
                || self.notice_label.text().ends_with(" off.")
                || self.notice_label.text() == "No Wi-Fi adapter." =>
            {
                self.notice.set_visible(false)
            }
            None => {}
        }

        match snapshot.current.as_ref() {
            Some(current) => {
                self.card.update(current, snapshot.connectivity);
                self.card.root.set_visible(!self.prompt.active());
            }
            None => {
                self.card.root.set_visible(false);
                self.card.set_expanded(false);
            }
        }

        self.lists.set_visible(wifi_usable);
        self.sync_rows(&snapshot);
        self.render_extras(&snapshot);
        let hotspot_on = snapshot.current.as_ref().is_some_and(|c| c.hotspot);
        self.hotspot_button.set_label(if hotspot_on {
            "Stop hotspot"
        } else {
            "Create hotspot…"
        });
        self.hotspot_button
            .set_sensitive(snapshot.wifi.is_some() && !airplane);

        if let Some((asked, last_scan)) = self.scan.get() {
            let done = snapshot
                .wifi
                .as_ref()
                .is_some_and(|w| w.last_scan != last_scan)
                || asked.elapsed() > SCAN_TIMEOUT;
            if done {
                self.scan.set(None);
            }
        }
        let scanning = self.scan.get().is_some();
        self.scan_state
            .set_visible_child_name(if scanning { "scanning" } else { "idle" });
        let others = self
            .rows
            .borrow()
            .values()
            .filter(|r| r.placed.get() == Some(false))
            .count();
        self.other_empty.set_visible(others == 0 && !scanning);
        self.other_list.set_visible(others > 0);
        self.update_show_more();
    }

    fn show_notice(&self, text: &str, action: Option<&str>) {
        self.notice_label.set_text(text);
        self.notice_action.set_visible(action.is_some());
        if let Some(action) = action {
            self.notice_action.set_label(action);
        }
        self.notice.set_visible(true);
    }

    fn notice_clicked(self: &Rc<Self>) {
        if self.airplane.get() {
            self.set_airplane(false);
        } else if !self.snapshot.borrow().networking {
            self.run(|conn| async move { nm::set_networking(&conn, true).await });
        }
    }

    /// Updates rows in place, and re-sorts them only while the panel is hidden
    /// or when a network moves between lists.
    fn sync_rows(self: &Rc<Self>, snapshot: &Snapshot) {
        let networks: Vec<&Network> = snapshot
            .networks
            .iter()
            .filter(|n| !snapshot.current.as_ref().is_some_and(|c| c.is(n)))
            .collect();
        let mut rows = self.rows.borrow_mut();
        let mut relayout = !self.window.is_visible();
        let mut seen = HashSet::new();
        for network in &networks {
            let key = network.key();
            match rows.get(&key) {
                Some(row) => {
                    row.update(network);
                    relayout |= row.placed.get() != Some(network.saved.is_some());
                }
                None => {
                    rows.insert(key.clone(), NetRow::new(self, network));
                    relayout = true;
                }
            }
            seen.insert(key);
        }
        let before = rows.len();
        rows.retain(|key, row| seen.contains(key) || row.expanded());
        relayout |= rows.len() != before;
        if !relayout {
            return;
        }
        self.known_list.remove_all();
        self.other_list.remove_all();
        // Network order from the snapshot, then any expanded leftovers.
        let mut order: Vec<NetworkKey> = networks.iter().map(|n| n.key()).collect();
        order.extend(rows.keys().filter(|k| !seen.contains(*k)).cloned());
        for key in order {
            let Some(row) = rows.get(&key) else { continue };
            let known = row.network.borrow().saved.is_some();
            if known {
                self.known_list.append(&row.row);
            } else {
                self.other_list.append(&row.row);
            }
            row.placed.set(Some(known));
        }
        let known = rows
            .values()
            .filter(|r| r.placed.get() == Some(true))
            .count();
        self.known_box.set_visible(known > 0);
    }

    fn render_extras(self: &Rc<Self>, snapshot: &Snapshot) {
        let extras = (snapshot.wired.clone(), snapshot.vpns.clone());
        self.wired_box.set_visible(!snapshot.wired.is_empty());
        self.vpn_box.set_visible(!snapshot.vpns.is_empty());
        if *self.rendered_extras.borrow() == extras {
            return;
        }
        self.wired_list.remove_all();
        for wired in &snapshot.wired {
            let status = match wired.state {
                100 => format!(
                    "Connected{}{}",
                    if wired.speed > 0 {
                        format!(" · {}", model::speed_label(wired.speed * 1000))
                    } else {
                        String::new()
                    },
                    wired
                        .ip4
                        .as_ref()
                        .map(|ip| format!(" · {ip}"))
                        .unwrap_or_default()
                ),
                40..=90 => "Connecting…".into(),
                _ if !wired.carrier => "Cable unplugged".into(),
                _ => "Disconnected".into(),
            };
            let name = wired
                .active_id
                .clone()
                .filter(|_| wired.state == 100)
                .unwrap_or_else(|| wired.interface.clone());
            let device = wired.path.clone();
            let on = wired.state >= 40 && wired.state <= 100;
            self.wired_list.append(&self.switch_row(
                &name,
                &status,
                on,
                wired.carrier,
                move |ui, on| {
                    let device = device.clone();
                    ui.run(move |conn| async move {
                        if on {
                            nm::activate(&conn, "/", &device).await.map(drop)
                        } else {
                            nm::disconnect(&conn, &device).await
                        }
                    });
                },
            ));
        }
        self.wired_box.set_visible(!snapshot.wired.is_empty());

        self.vpn_list.remove_all();
        for vpn in &snapshot.vpns {
            let status = match vpn.state {
                NetState::Active => "Connected",
                NetState::Activating => "Connecting…",
                NetState::Idle => "Off",
            };
            let (settings, active) = (vpn.settings_path.clone(), vpn.active_path.clone());
            self.vpn_list.append(&self.switch_row(
                &vpn.id,
                status,
                vpn.state != NetState::Idle,
                true,
                move |ui, on| {
                    let (settings, active) = (settings.clone(), active.clone());
                    ui.quiet();
                    ui.run(move |conn| async move {
                        match (on, active) {
                            (true, _) => nm::activate(&conn, &settings, "/").await.map(drop),
                            (false, Some(active)) => nm::deactivate(&conn, &active).await,
                            (false, None) => Ok(()),
                        }
                    });
                },
            ));
        }
        self.vpn_box.set_visible(!snapshot.vpns.is_empty());
        *self.rendered_extras.borrow_mut() = extras;
    }

    fn switch_row(
        self: &Rc<Self>,
        name: &str,
        status: &str,
        on: bool,
        sensitive: bool,
        f: impl Fn(&Rc<Ui>, bool) + 'static,
    ) -> gtk::ListBoxRow {
        let text = vbox(1);
        text.set_hexpand(true);
        text.set_valign(gtk::Align::Center);
        let title = label(name, &[]);
        title.set_ellipsize(pango::EllipsizeMode::End);
        text.append(&title);
        text.append(&label(status, &["dim", "small"]));
        let (toggle, _) = Toggle::new(name);
        toggle.set(on);
        toggle.switch.set_sensitive(sensitive);
        let weak = Rc::downgrade(self);
        toggle.on_toggle(move |on| {
            if let Some(ui) = weak.upgrade() {
                f(&ui, on);
            }
        });
        let line = hbox(10);
        line.add_css_class("net-line");
        line.append(&text);
        line.append(&toggle.switch);
        // The Toggle only guards programmatic updates; this row is rebuilt
        // rather than updated, so it can go.
        drop(toggle);
        gtk::ListBoxRow::builder()
            .child(&line)
            .activatable(false)
            .build()
    }

    fn row_activated(self: &Rc<Self>, row: &gtk::ListBoxRow) {
        let Some(net_row) = self.rows.borrow().values().find(|r| r.row == *row).cloned() else {
            return;
        };
        if net_row.expanded() {
            return;
        }
        net_row.clear_failed();
        let network = net_row.network.borrow().clone();
        if let Some(saved) = network.saved.clone() {
            self.collapse_forms();
            self.connect_saved(&network, saved);
        } else if !network.security.secured() {
            self.collapse_forms();
            self.connect_new(&network, Secret::None, &net_row);
        } else {
            self.collapse_forms();
            net_row.expand();
        }
    }

    /// Folds every open form; true if there was one.
    fn collapse_forms(&self) -> bool {
        let mut any = false;
        for row in self.rows.borrow().values() {
            if row.expanded() {
                row.collapse();
                any = true;
            }
        }
        if self.hidden.revealer.reveals_child() {
            self.hidden.close();
            any = true;
        }
        if self.hotspot.revealer.reveals_child() {
            self.hotspot.close();
            any = true;
        }
        if self.card.details.reveals_child() {
            self.card.set_expanded(false);
            any = true;
        }
        any
    }

    fn start_pending(&self, ssid: &[u8]) {
        self.quiet();
        *self.pending.borrow_mut() = Some(Pending {
            ssid: ssid.to_vec(),
            created: None,
            seen: false,
            started: Instant::now(),
        });
    }

    fn connect_saved(self: &Rc<Self>, network: &Network, saved: String) {
        let (Some(conn), Some(device)) = (self.conn(), self.wifi_device()) else {
            return;
        };
        self.start_pending(&network.ssid_bytes);
        let ui = self.clone();
        let ssid = network.ssid_bytes.clone();
        glib::spawn_future_local(async move {
            if let Err(e) = nm::activate(&conn, &saved, &device).await {
                ui.pending.borrow_mut().take();
                if let Some(row) = ui.row_for_ssid(&ssid) {
                    row.mark_failed(&friendly(&e));
                }
            }
        });
    }

    fn connect_new(self: &Rc<Self>, network: &Network, secret: Secret, row: &Rc<NetRow>) {
        let (Some(conn), Some(device)) = (self.conn(), self.wifi_device()) else {
            return;
        };
        let settings = nm::wifi_settings(&network.ssid_bytes, network.security, &secret, false);
        self.start_pending(&network.ssid_bytes);
        let (ui, row, ap) = (self.clone(), row.clone(), network.best_ap.clone());
        glib::spawn_future_local(async move {
            match nm::add_and_activate(&conn, settings, &device, Some(&ap)).await {
                Ok((created, _)) => {
                    if let Some(p) = ui.pending.borrow_mut().as_mut() {
                        p.created = Some(created);
                    }
                    row.collapse();
                }
                Err(e) => {
                    ui.pending.borrow_mut().take();
                    row.expand();
                    row.show_error(&friendly(&e));
                }
            }
        });
    }

    fn join_row(self: &Rc<Self>, row: &Rc<NetRow>) {
        match row.secret() {
            Ok(secret) => {
                let network = row.network.borrow().clone();
                self.connect_new(&network, secret, row);
            }
            Err(message) => row.show_error(message),
        }
    }

    fn join_hidden(self: &Rc<Self>) {
        let name = self.hidden.name.text().to_string();
        if name.is_empty() {
            self.hidden.show_error("Enter the network's name.");
            return;
        }
        let security = self.hidden.security();
        let secret = match secret_for(
            security,
            &self.hidden.identity.text(),
            &self.hidden.password.text(),
        ) {
            Ok(secret) => secret,
            Err(message) => {
                self.hidden.show_error(message);
                return;
            }
        };
        let (Some(conn), Some(device)) = (self.conn(), self.wifi_device()) else {
            return;
        };
        let settings = nm::wifi_settings(name.as_bytes(), security, &secret, true);
        self.start_pending(name.as_bytes());
        let ui = self.clone();
        glib::spawn_future_local(async move {
            match nm::add_and_activate(&conn, settings, &device, None).await {
                Ok((created, _)) => {
                    if let Some(p) = ui.pending.borrow_mut().as_mut() {
                        p.created = Some(created);
                    }
                    ui.hidden.close();
                }
                Err(e) => {
                    ui.pending.borrow_mut().take();
                    ui.hidden.show_error(&friendly(&e));
                }
            }
        });
    }

    fn hotspot_clicked(self: &Rc<Self>) {
        let active = self
            .snapshot
            .borrow()
            .current
            .as_ref()
            .filter(|c| c.hotspot)
            .map(|c| c.active_path.clone());
        match active {
            Some(active) => {
                self.run(move |conn| async move { nm::deactivate(&conn, &active).await })
            }
            None => {
                self.hidden.close();
                self.hotspot.open();
            }
        }
    }

    fn start_hotspot(self: &Rc<Self>) {
        let name = self.hotspot.name.text().to_string();
        let password = self.hotspot.password.text().to_string();
        if name.is_empty() || !(8..=63).contains(&password.len()) {
            self.hotspot
                .error
                .set_text("Give it a name and a password of 8 to 63 characters.");
            self.hotspot.error.set_visible(true);
            return;
        }
        let (Some(conn), Some(device)) = (self.conn(), self.wifi_device()) else {
            return;
        };
        let old = self.snapshot.borrow().hotspot_saved.clone();
        self.quiet();
        let ui = self.clone();
        glib::spawn_future_local(async move {
            // Replace the last hotspot so its name and password are the new ones.
            if let Some(old) = old {
                let _ = nm::delete(&conn, &old).await;
            }
            match nm::add_and_activate(&conn, nm::hotspot_settings(&name, &password), &device, None)
                .await
            {
                Ok(_) => ui.hotspot.close(),
                Err(e) => {
                    ui.hotspot.error.set_text(&friendly(&e));
                    ui.hotspot.error.set_visible(true);
                }
            }
        });
    }

    fn disconnect_current(self: &Rc<Self>) {
        let snapshot = self.snapshot.borrow().clone();
        let Some(current) = snapshot.current else {
            return;
        };
        self.quiet();
        if current.hotspot {
            self.run(move |conn| async move { nm::deactivate(&conn, &current.active_path).await });
        } else if let Some(device) = snapshot.wifi.map(|w| w.path) {
            self.run(move |conn| async move { nm::disconnect(&conn, &device).await });
        }
    }

    fn share_clicked(self: &Rc<Self>) {
        if self.card.shared.reveals_child() {
            self.card.hide_shared();
            return;
        }
        let Some(current) = self.snapshot.borrow().current.clone() else {
            return;
        };
        let Some(conn) = self.conn() else { return };
        let ui = self.clone();
        glib::spawn_future_local(async move {
            match nm::wifi_key(&conn, &current.settings_path).await {
                Ok(Some(key)) => {
                    let kind = match current.security {
                        Some(Security::Wep) => "WEP",
                        Some(Security::Wpa3) => "SAE",
                        _ => "WPA",
                    };
                    ui.card.key.set_text(&key);
                    ui.card
                        .qr
                        .set_text(Some(&widgets::wifi_qr_payload(&current.ssid, &key, kind)));
                    ui.card.shared.set_reveal_child(true);
                    ui.card.share.set_label("Hide password");
                }
                Ok(None) => ui.show_notice("This network has no saved password.", None),
                Err(e) => ui.show_notice(&friendly(&e), None),
            }
        });
    }

    fn forget_clicked(self: &Rc<Self>) {
        if !self.card.forget_armed.get() {
            self.card.forget_armed.set(true);
            self.card.forget.set_label("Forget?");
            self.card.forget.add_css_class("danger");
            let weak = Rc::downgrade(self);
            glib::timeout_add_local_once(Duration::from_secs(4), move || {
                if let Some(ui) = weak.upgrade() {
                    ui.card.disarm_forget();
                }
            });
            return;
        }
        self.card.disarm_forget();
        let Some(settings) = self
            .snapshot
            .borrow()
            .current
            .as_ref()
            .map(|c| c.settings_path.clone())
        else {
            return;
        };
        self.quiet();
        self.run(move |conn| async move { nm::delete(&conn, &settings).await });
    }

    fn set_airplane(self: &Rc<Self>, on: bool) {
        let Some(rfkill) = self.rfkill.borrow().clone() else {
            return;
        };
        self.quiet();
        if let Err(e) = rfkill.set_airplane(on) {
            self.show_notice(&format!("Couldn't change airplane mode: {e}"), None);
        }
    }

    fn rescan(self: &Rc<Self>) {
        let snapshot = self.snapshot.borrow().clone();
        let Some(wifi) = snapshot.wifi.filter(|_| snapshot.wifi_enabled) else {
            return;
        };
        self.scan.set(Some((Instant::now(), wifi.last_scan)));
        self.render();
        // NetworkManager refuses scans too close together; the spinner
        // simply runs until the next scan result or the timeout.
        if let Some(conn) = self.conn() {
            glib::spawn_future_local(async move {
                let _ = nm::request_scan(&conn, &wifi.path).await;
            });
        }
        let weak = Rc::downgrade(self);
        glib::timeout_add_local_once(SCAN_TIMEOUT, move || {
            if let Some(ui) = weak.upgrade() {
                ui.render();
            }
        });
    }

    fn launch_editor(self: &Rc<Self>) {
        self.hide();
        let args = [
            self.opts.systemd_run.as_str(),
            "--user",
            "--scope",
            "--collect",
            "--quiet",
            "--",
            self.opts.editor.as_str(),
        ];
        let args: Vec<&std::ffi::OsStr> = args.iter().map(std::ffi::OsStr::new).collect();
        if let Err(e) = gio::Subprocess::newv(&args, gio::SubprocessFlags::NONE) {
            eprintln!("net-panel: can't start {}: {e}", self.opts.editor);
        }
    }

    fn show(self: &Rc<Self>, at: Option<(i32, i32)>) {
        self.place(at);
        self.was_active.set(false);
        // Re-sort while still hidden.
        let snapshot = self.snapshot.borrow().clone();
        self.sync_rows(&snapshot);
        self.window.set_visible(true);
        self.window.present();
        self.rescan();
    }

    fn hide(self: &Rc<Self>) {
        // A prompt nobody can see would keep NetworkManager waiting.
        if self.prompt.active() {
            self.prompt.answer(None);
        }
        self.collapse_forms();
        self.search.set_text("");
        self.card.hide_shared();
        self.show_all.set(false);
        self.other_list.invalidate_filter();
        self.window.set_visible(false);
        self.notice.set_visible(false);
        self.render();
    }

    /// Opens on the monitor that was clicked, centred under the click where
    /// it fits; without a click, wherever the compositor puts it.
    fn place(&self, at: Option<(i32, i32)>) {
        let monitors = gdk::Display::default().map(|d| d.monitors());
        let found = at.zip(monitors).and_then(|((x, y), monitors)| {
            (0..monitors.n_items())
                .filter_map(|i| monitors.item(i).and_downcast::<gdk::Monitor>())
                .find(|m| {
                    let g = m.geometry();
                    x >= g.x() && x < g.x() + g.width() && y >= g.y() && y < g.y() + g.height()
                })
        });
        match (found, at) {
            (Some(monitor), Some((x, _))) => {
                let g = monitor.geometry();
                let full = PANEL_WIDTH + 2 * SIDE_MARGIN;
                let right = g.x() + g.width() - x - full / 2;
                self.window.set_monitor(Some(&monitor));
                self.panel
                    .set_margin_end(right.clamp(0, (g.width() - full).max(0)));
            }
            _ => {
                self.window.set_monitor(None);
                self.panel.set_margin_end(0);
            }
        }
    }

    fn update_tray(self: &Rc<Self>) {
        let Some(tray) = self.tray.borrow().clone() else {
            return;
        };
        let snapshot = self.snapshot.borrow().clone();
        let icon = TrayIcon::from_snapshot(&snapshot, self.airplane.get());
        if icon == TrayIcon::Connecting && !self.animating.replace(true) {
            let weak = Rc::downgrade(self);
            glib::timeout_add_local(Duration::from_millis(450), move || {
                let Some(ui) = weak.upgrade() else {
                    return glib::ControlFlow::Break;
                };
                let still = TrayIcon::from_snapshot(&ui.snapshot.borrow(), ui.airplane.get())
                    == TrayIcon::Connecting;
                if !still {
                    ui.animating.set(false);
                    return glib::ControlFlow::Break;
                }
                ui.phase.set(ui.phase.get() % 3 + 1);
                ui.update_tray();
                glib::ControlFlow::Continue
            });
        }
        let name = icon.name(self.phase.get());
        let (title, body) = model::tooltip(&snapshot, self.airplane.get());
        glib::spawn_future_local(async move {
            if let Err(e) = tray.set(&name, &title, &body).await {
                eprintln!("net-panel: updating the tray icon: {e}");
            }
        });
    }

    fn notify_changes(self: &Rc<Self>, previous: &Snapshot) {
        if self.is_quiet() {
            return;
        }
        let snapshot = self.snapshot.borrow().clone();
        let up = |s: &Snapshot| {
            s.current
                .as_ref()
                .filter(|c| c.state == NetState::Active)
                .map(|c| c.ssid.clone())
        };
        let mut messages: Vec<(String, String)> = Vec::new();
        match (up(previous), up(&snapshot)) {
            (before, Some(now)) if before.as_ref() != Some(&now) => {
                let body = snapshot
                    .current
                    .as_ref()
                    .map(|c| {
                        let band =
                            model::Band::from_frequency(c.frequency).map(|b| b.label().to_owned());
                        [band, c.security.map(|s| s.label().to_owned())]
                            .into_iter()
                            .flatten()
                            .collect::<Vec<_>>()
                            .join(" · ")
                    })
                    .unwrap_or_default();
                messages.push((format!("Connected to {now}"), body));
            }
            (Some(before), None)
                if snapshot.networking && snapshot.wifi_enabled && !self.airplane.get() =>
            {
                messages.push((format!("Disconnected from {before}"), String::new()));
            }
            _ => {}
        }
        for vpn in &snapshot.vpns {
            let was = previous
                .vpns
                .iter()
                .find(|v| v.settings_path == vpn.settings_path)
                .map(|v| v.state);
            match (was, vpn.state) {
                (Some(NetState::Activating | NetState::Idle) | None, NetState::Active) => {
                    messages.push((format!("VPN connected: {}", vpn.id), String::new()));
                }
                (Some(NetState::Active), NetState::Idle) => {
                    messages.push((format!("VPN disconnected: {}", vpn.id), String::new()));
                }
                _ => {}
            }
        }
        let Some(tray) = self.tray.borrow().clone() else {
            return;
        };
        let icon = format!(
            "{}/{}.svg",
            self.icon_dir,
            TrayIcon::from_snapshot(&snapshot, self.airplane.get()).name(1)
        );
        let ui = self.clone();
        glib::spawn_future_local(async move {
            for (summary, body) in messages {
                ui.notifier
                    .send(tray.connection(), &icon, &summary, &body)
                    .await;
            }
        });
    }
}

fn load_css(opts: &Options) {
    let Some(display) = gdk::Display::default() else {
        return;
    };
    let base = gtk::CssProvider::new();
    base.load_from_string(include_str!("style.css"));
    gtk::style_context_add_provider_for_display(
        &display,
        &base,
        gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
    if let Some(path) = &opts.css {
        let theme = gtk::CssProvider::new();
        theme.load_from_path(path);
        gtk::style_context_add_provider_for_display(
            &display,
            &theme,
            gtk::STYLE_PROVIDER_PRIORITY_APPLICATION + 1,
        );
    }
}

/// Builds the panel and starts the D-Bus side: the tray icon and control
/// interface on the session bus, NetworkManager and the agent on the system bus.
pub fn start(app: &gtk::Application, opts: Options) {
    // The panel lives for the session, window or not.
    std::mem::forget(app.hold());
    load_css(&opts);

    let runtime = glib::user_runtime_dir().join("net-panel").join("icons");
    let icon_dir = match crate::icons::write_tray_icons(&runtime, &opts.icon_color) {
        Ok(dir) => dir.to_string_lossy().into_owned(),
        Err(e) => {
            eprintln!(
                "net-panel: writing tray icons to {}: {e}",
                runtime.display()
            );
            runtime.to_string_lossy().into_owned()
        }
    };

    let (tx, rx) = async_channel::unbounded::<Event>();
    let ui = Ui::new(app, opts, icon_dir.clone());

    match Rfkill::watch(tx.clone()) {
        Ok(rfkill) => *ui.rfkill.borrow_mut() = Some(rfkill),
        Err(e) => eprintln!("net-panel: airplane mode unavailable (/dev/rfkill): {e}"),
    }

    let (tray_ui, tray_tx) = (ui.clone(), tx.clone());
    glib::spawn_future_local(async move {
        let first = TrayIcon::Disconnected.name(1);
        match Tray::start(tray_tx, icon_dir, first).await {
            Ok(tray) => {
                *tray_ui.tray.borrow_mut() = Some(tray);
                tray_ui.update_tray();
            }
            Err(e) => eprintln!("net-panel: can't publish the tray icon: {e}"),
        }
    });

    let system_ui = ui.clone();
    glib::spawn_future_local(async move {
        let conn = match Connection::system().await {
            Ok(conn) => conn,
            Err(e) => {
                eprintln!("net-panel: can't reach the system bus: {e}");
                return;
            }
        };
        *system_ui.system.borrow_mut() = Some(conn.clone());
        glib::spawn_future_local(crate::agent::run(conn.clone(), tx.clone()));
        nm::watch(conn, tx).await;
    });

    glib::spawn_future_local(async move {
        while let Ok(event) = rx.recv().await {
            ui.handle(event);
        }
    });
}
