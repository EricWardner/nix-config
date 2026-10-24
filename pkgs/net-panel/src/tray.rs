//! The tray icon: a StatusNotifierItem in waybar's tray. Clicking it toggles
//! the panel (there is no menu, so waybar never draws one). The icon names
//! files in IconThemePath, which waybar loads at the exact pixel size and,
//! being `-symbolic`, recolours to the bar's text colour.
//!
//! The same session-bus connection serves `io.github.netpanel`, whose Toggle
//! method `net-panel toggle` calls (for keybinds).

use async_channel::Sender;
use futures_util::StreamExt as _;
use zbus::Connection;
use zbus::object_server::SignalEmitter;

use crate::Event;

const ITEM_PATH: &str = "/StatusNotifierItem";
const WATCHER: &str = "org.kde.StatusNotifierWatcher";
pub const CONTROL_NAME: &str = "io.github.netpanel";
pub const CONTROL_PATH: &str = "/io/github/netpanel";
pub const CONTROL_IFACE: &str = "io.github.netpanel.Control";

/// (icon name, icon pixmaps, title, description)
type ToolTip = (String, Vec<(i32, i32, Vec<u8>)>, String, String);

struct Item {
    icon: String,
    theme_path: String,
    title: String,
    body: String,
    tx: Sender<Event>,
}

#[zbus::interface(name = "org.kde.StatusNotifierItem")]
impl Item {
    #[zbus(property)]
    fn category(&self) -> String {
        "Hardware".into()
    }

    #[zbus(property)]
    fn id(&self) -> String {
        "net-panel".into()
    }

    #[zbus(property)]
    fn title(&self) -> String {
        "Network".into()
    }

    #[zbus(property)]
    fn status(&self) -> String {
        "Active".into()
    }

    #[zbus(property)]
    fn icon_name(&self) -> String {
        self.icon.clone()
    }

    #[zbus(property)]
    fn icon_theme_path(&self) -> String {
        self.theme_path.clone()
    }

    #[zbus(property)]
    fn item_is_menu(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn window_id(&self) -> i32 {
        0
    }

    #[zbus(property)]
    fn tool_tip(&self) -> ToolTip {
        (
            String::new(),
            Vec::new(),
            self.title.clone(),
            self.body.clone(),
        )
    }

    async fn activate(&self, x: i32, y: i32) {
        let _ = self.tx.send(Event::Toggle(Some((x, y)))).await;
    }

    async fn context_menu(&self, x: i32, y: i32) {
        let _ = self.tx.send(Event::Toggle(Some((x, y)))).await;
    }

    async fn secondary_activate(&self, _x: i32, _y: i32) {}

    async fn scroll(&self, _delta: i32, _orientation: String) {}

    #[zbus(signal)]
    async fn new_icon(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn new_tool_tip(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
}

struct Control {
    tx: Sender<Event>,
}

#[zbus::interface(name = "io.github.netpanel.Control")]
impl Control {
    async fn toggle(&self) {
        let _ = self.tx.send(Event::Toggle(None)).await;
    }
}

#[derive(Clone)]
pub struct Tray {
    conn: Connection,
}

impl Tray {
    pub async fn start(tx: Sender<Event>, theme_path: String, icon: String) -> zbus::Result<Self> {
        let name = format!("org.kde.StatusNotifierItem-{}-1", std::process::id());
        let item = Item {
            icon,
            theme_path,
            title: "Network".into(),
            body: String::new(),
            tx: tx.clone(),
        };
        let conn = zbus::connection::Builder::session()?
            .name(name.as_str())?
            .name(CONTROL_NAME)?
            .serve_at(ITEM_PATH, item)?
            .serve_at(CONTROL_PATH, Control { tx })?
            .build()
            .await?;
        let tray = Self { conn: conn.clone() };
        gtk::glib::spawn_future_local(keep_registered(conn, name));
        Ok(tray)
    }

    pub fn connection(&self) -> &Connection {
        &self.conn
    }

    pub async fn set(&self, icon: &str, title: &str, body: &str) -> zbus::Result<()> {
        let item = self
            .conn
            .object_server()
            .interface::<_, Item>(ITEM_PATH)
            .await?;
        let (icon_changed, tip_changed) = {
            let mut item = item.get_mut().await;
            let icon_changed = item.icon != icon;
            let tip_changed = item.title != title || item.body != body;
            item.icon = icon.to_owned();
            item.title = title.to_owned();
            item.body = body.to_owned();
            (icon_changed, tip_changed)
        };
        if icon_changed {
            Item::new_icon(item.signal_emitter()).await?;
        }
        if tip_changed {
            Item::new_tool_tip(item.signal_emitter()).await?;
        }
        Ok(())
    }
}

/// Registers with the tray host now and whenever it comes back: waybar is
/// the watcher, and it restarts on every monitor hotplug.
async fn keep_registered(conn: Connection, name: String) {
    let register = || async {
        conn.call_method(
            Some(WATCHER),
            "/StatusNotifierWatcher",
            Some(WATCHER),
            "RegisterStatusNotifierItem",
            &(name.as_str(),),
        )
        .await
        .map(drop)
    };
    // No watcher yet is fine: it will announce itself below.
    let _ = register().await;
    let Ok(dbus) = zbus::fdo::DBusProxy::new(&conn).await else {
        return;
    };
    let Ok(mut owners) = dbus
        .receive_name_owner_changed_with_args(&[(0, WATCHER)])
        .await
    else {
        return;
    };
    while let Some(change) = owners.next().await {
        if change.args().is_ok_and(|a| a.new_owner().is_some())
            && let Err(e) = register().await
        {
            eprintln!("net-panel: can't register with the tray: {e}");
        }
    }
}

/// `net-panel toggle`: asks the running panel to open or close.
pub fn send_toggle() -> Result<(), zbus::Error> {
    let conn = zbus::blocking::Connection::session()?;
    conn.call_method(
        Some(CONTROL_NAME),
        CONTROL_PATH,
        Some(CONTROL_IFACE),
        "Toggle",
        &(),
    )?;
    Ok(())
}
