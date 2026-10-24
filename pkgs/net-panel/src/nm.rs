//! NetworkManager over D-Bus. State comes from one GetManagedObjects call
//! (every device, access point, active connection and IP config, ~10 ms)
//! plus each saved connection's settings, cached until NetworkManager says
//! they changed. Any signal NetworkManager sends triggers a refresh, coalesced
//! so a scan's burst of property changes costs one rebuild.

use std::collections::HashMap;
use std::time::Duration;

use async_channel::Sender;
use futures_util::{FutureExt as _, StreamExt as _};
use gtk::glib;
use zbus::message::Type as MessageType;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value};
use zbus::{Connection, MatchRule, MessageStream};

use crate::model::{
    AccessPoint, Connectivity, Current, NetState, Primary, Saved, Security, Snapshot, Vpn,
    WifiDevice, Wired, group_networks,
};

pub const NM: &str = "org.freedesktop.NetworkManager";
const NM_PATH: &str = "/org/freedesktop/NetworkManager";
const SETTINGS_PATH: &str = "/org/freedesktop/NetworkManager/Settings";
const IFACE_DEVICE: &str = "org.freedesktop.NetworkManager.Device";
const IFACE_WIRELESS: &str = "org.freedesktop.NetworkManager.Device.Wireless";
const IFACE_WIRED: &str = "org.freedesktop.NetworkManager.Device.Wired";
const IFACE_AP: &str = "org.freedesktop.NetworkManager.AccessPoint";
const IFACE_ACTIVE: &str = "org.freedesktop.NetworkManager.Connection.Active";
const IFACE_IP4: &str = "org.freedesktop.NetworkManager.IP4Config";
const IFACE_IP6: &str = "org.freedesktop.NetworkManager.IP6Config";
const IFACE_SETTINGS: &str = "org.freedesktop.NetworkManager.Settings";
const IFACE_CONNECTION: &str = "org.freedesktop.NetworkManager.Settings.Connection";

const DEVICE_ETHERNET: u32 = 1;
const DEVICE_WIFI: u32 = 2;
/// The connection id the hotspot form creates and reuses.
pub const HOTSPOT_ID: &str = "Hotspot";

type Props = HashMap<String, OwnedValue>;
type Objects = HashMap<OwnedObjectPath, HashMap<String, Props>>;
/// a{sa{sv}}: a connection's settings, or secrets, by setting name.
pub type SettingsMap = HashMap<String, HashMap<String, OwnedValue>>;
/// The same, for building settings to send.
pub type NewSettings = HashMap<&'static str, HashMap<&'static str, Value<'static>>>;

fn value<'a>(props: &'a Props, key: &str) -> Option<&'a Value<'static>> {
    props.get(key).map(|v| &**v)
}

fn as_u32(v: Option<&Value>) -> u32 {
    match v {
        Some(Value::U32(x)) => *x,
        Some(Value::U8(x)) => u32::from(*x),
        _ => 0,
    }
}

fn as_i64(v: Option<&Value>) -> i64 {
    match v {
        Some(Value::I64(x)) => *x,
        Some(Value::I32(x)) => i64::from(*x),
        _ => 0,
    }
}

fn as_u64(v: Option<&Value>) -> u64 {
    match v {
        Some(Value::U64(x)) => *x,
        _ => 0,
    }
}

fn as_bool(v: Option<&Value>, default: bool) -> bool {
    match v {
        Some(Value::Bool(b)) => *b,
        _ => default,
    }
}

fn as_string(v: Option<&Value>) -> String {
    match v {
        Some(Value::Str(s)) => s.as_str().to_owned(),
        Some(Value::ObjectPath(p)) => p.as_str().to_owned(),
        _ => String::new(),
    }
}

/// An object path, or None for NetworkManager's "/" placeholder.
fn as_path(v: Option<&Value>) -> Option<String> {
    Some(as_string(v)).filter(|p| !p.is_empty() && p != "/")
}

fn as_paths(v: Option<&Value>) -> Vec<String> {
    match v {
        Some(Value::Array(items)) => items.iter().filter_map(|i| as_path(Some(i))).collect(),
        _ => Vec::new(),
    }
}

fn as_bytes(v: Option<&Value>) -> Vec<u8> {
    match v {
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(|i| match i {
                Value::U8(b) => Some(*b),
                _ => None,
            })
            .collect(),
        _ => Vec::new(),
    }
}

/// The `key` string of each a{sv} in an aa{sv} (IP AddressData and
/// NameserverData).
fn dict_strings(v: Option<&Value>, key: &str) -> Vec<String> {
    let Some(Value::Array(items)) = v else {
        return Vec::new();
    };
    items
        .iter()
        .filter_map(|item| {
            let Value::Dict(dict) = item else { return None };
            let found: Option<Value> = dict.get(&key).ok().flatten();
            found.map(|v| as_string(Some(&v)))
        })
        .filter(|s| !s.is_empty())
        .collect()
}

struct Index<'a> {
    objects: HashMap<&'a str, &'a HashMap<String, Props>>,
}

impl<'a> Index<'a> {
    fn new(objects: &'a Objects) -> Self {
        Self {
            objects: objects
                .iter()
                .map(|(path, ifaces)| (path.as_str(), ifaces))
                .collect(),
        }
    }

    fn props(&self, path: &str, iface: &str) -> Option<&'a Props> {
        self.objects.get(path)?.get(iface)
    }
}

fn setting<'a>(settings: &'a SettingsMap, section: &str, key: &str) -> Option<&'a Value<'static>> {
    settings.get(section).and_then(|s| value(s, key))
}

fn parse_saved(path: &str, settings: &SettingsMap) -> Saved {
    Saved {
        path: path.to_owned(),
        id: as_string(setting(settings, "connection", "id")),
        kind: as_string(setting(settings, "connection", "type")),
        ssid: as_bytes(setting(settings, "802-11-wireless", "ssid")),
        mode: as_string(setting(settings, "802-11-wireless", "mode")),
        timestamp: as_u64(setting(settings, "connection", "timestamp")),
    }
}

fn ip4_details(
    index: &Index,
    path: Option<String>,
) -> (Option<String>, Option<String>, Vec<String>) {
    let Some(props) = path.and_then(|p| index.props(&p, IFACE_IP4)) else {
        return (None, None, Vec::new());
    };
    let address = dict_strings(value(props, "AddressData"), "address")
        .into_iter()
        .next();
    let gateway = Some(as_string(value(props, "Gateway"))).filter(|g| !g.is_empty());
    let dns = dict_strings(value(props, "NameserverData"), "address");
    (address, gateway, dns)
}

fn ip6_address(index: &Index, path: Option<String>) -> Option<String> {
    let props = index.props(&path?, IFACE_IP6)?;
    dict_strings(value(props, "AddressData"), "address")
        .into_iter()
        .find(|a| !a.to_lowercase().starts_with("fe80"))
}

fn active_state(state: u32) -> Option<NetState> {
    match state {
        1 => Some(NetState::Activating),
        2 => Some(NetState::Active),
        _ => None,
    }
}

fn snapshot(objects: &Objects, saved: &[Saved]) -> Snapshot {
    let index = Index::new(objects);
    let Some(nm) = index.props(NM_PATH, NM) else {
        return Snapshot::default();
    };
    let mut snap = Snapshot {
        networking: as_bool(value(nm, "NetworkingEnabled"), true),
        wifi_enabled: as_bool(value(nm, "WirelessEnabled"), true),
        wifi_hardware: as_bool(value(nm, "WirelessHardwareEnabled"), true),
        connectivity: Connectivity::from_nm(as_u32(value(nm, "Connectivity"))),
        primary: match as_string(value(nm, "PrimaryConnectionType")).as_str() {
            "" => Primary::None,
            "802-11-wireless" => Primary::Wifi,
            "802-3-ethernet" => Primary::Wired,
            _ => Primary::Other,
        },
        hotspot_saved: saved
            .iter()
            .find(|s| s.kind == "802-11-wireless" && s.mode == "ap" && s.id == HOTSPOT_ID)
            .map(|s| s.path.clone()),
        ..Snapshot::default()
    };

    let saved_by_path: HashMap<&str, &Saved> = saved.iter().map(|s| (s.path.as_str(), s)).collect();
    let mut aps = Vec::new();
    let mut active_wifi: Option<(Vec<u8>, NetState)> = None;

    for device_path in as_paths(value(nm, "Devices")) {
        let Some(device) = index.props(&device_path, IFACE_DEVICE) else {
            continue;
        };
        if !as_bool(value(device, "Managed"), true) {
            continue;
        }
        let interface = as_string(value(device, "Interface"));
        let state = as_u32(value(device, "State"));
        let active = as_path(value(device, "ActiveConnection"));
        let active_props = active.as_deref().and_then(|a| index.props(a, IFACE_ACTIVE));
        match as_u32(value(device, "DeviceType")) {
            DEVICE_WIFI if snap.wifi.is_none() => {
                let Some(wireless) = index.props(&device_path, IFACE_WIRELESS) else {
                    continue;
                };
                snap.wifi = Some(WifiDevice {
                    path: device_path.clone(),
                    interface,
                    state,
                    last_scan: as_i64(value(wireless, "LastScan")),
                    hw_address: as_string(value(wireless, "HwAddress")),
                });
                for ap_path in as_paths(value(wireless, "AccessPoints")) {
                    let Some(ap) = index.props(&ap_path, IFACE_AP) else {
                        continue;
                    };
                    aps.push(AccessPoint {
                        security: Security::from_flags(
                            as_u32(value(ap, "Flags")),
                            as_u32(value(ap, "WpaFlags")),
                            as_u32(value(ap, "RsnFlags")),
                        ),
                        path: ap_path,
                        ssid: as_bytes(value(ap, "Ssid")),
                        bssid: as_string(value(ap, "HwAddress")),
                        strength: as_u32(value(ap, "Strength")).min(100) as u8,
                        frequency: as_u32(value(ap, "Frequency")),
                    });
                }
                let (Some(active_path), Some(active_props)) = (active, active_props) else {
                    continue;
                };
                let Some(conn_state) = active_state(as_u32(value(active_props, "State"))) else {
                    continue;
                };
                let settings_path = as_path(value(active_props, "Connection")).unwrap_or_default();
                let saved = saved_by_path.get(settings_path.as_str());
                let ap = as_path(value(active_props, "SpecificObject"))
                    .and_then(|p| aps.iter().find(|a| a.path == p));
                let ssid_bytes = saved
                    .map(|s| s.ssid.clone())
                    .filter(|s| !s.is_empty())
                    .or_else(|| ap.map(|a| a.ssid.clone()))
                    .unwrap_or_default();
                let hotspot = saved.is_some_and(|s| s.mode == "ap");
                let (ip4, gateway, dns) = ip4_details(&index, as_path(value(device, "Ip4Config")));
                if !hotspot {
                    active_wifi = Some((ssid_bytes.clone(), conn_state));
                }
                snap.current = Some(Current {
                    ssid: if ssid_bytes.is_empty() {
                        as_string(value(active_props, "Id"))
                    } else {
                        crate::model::display_ssid(&ssid_bytes)
                    },
                    ssid_bytes,
                    hotspot,
                    state: conn_state,
                    strength: ap.map_or(0, |a| a.strength),
                    frequency: ap.map_or(0, |a| a.frequency),
                    security: ap.map(|a| a.security),
                    bitrate: as_u32(value(wireless, "Bitrate")),
                    ip4,
                    gateway,
                    dns,
                    ip6: ip6_address(&index, as_path(value(device, "Ip6Config"))),
                    active_path,
                    settings_path,
                });
            }
            DEVICE_ETHERNET => {
                let wired = index.props(&device_path, IFACE_WIRED);
                let (ip4, _, _) = ip4_details(&index, as_path(value(device, "Ip4Config")));
                snap.wired.push(Wired {
                    path: device_path.clone(),
                    interface,
                    state,
                    carrier: wired.is_some_and(|w| as_bool(value(w, "Carrier"), false)),
                    speed: wired.map_or(0, |w| as_u32(value(w, "Speed"))),
                    active_id: active_props.map(|a| as_string(value(a, "Id"))),
                    ip4,
                });
            }
            _ => {}
        }
    }

    let active_by_settings: HashMap<String, (String, u32)> =
        as_paths(value(nm, "ActiveConnections"))
            .into_iter()
            .filter_map(|path| {
                let props = index.props(&path, IFACE_ACTIVE)?;
                let settings = as_path(value(props, "Connection"))?;
                Some((settings, (path, as_u32(value(props, "State")))))
            })
            .collect();
    snap.vpns = saved
        .iter()
        .filter(|s| s.is_vpn())
        .map(|s| {
            let active = active_by_settings.get(&s.path);
            Vpn {
                settings_path: s.path.clone(),
                id: s.id.clone(),
                active_path: active.map(|(p, _)| p.clone()),
                state: active
                    .and_then(|(_, state)| active_state(*state))
                    .unwrap_or_default(),
            }
        })
        .collect();
    snap.vpns.sort_by_key(|v| v.id.to_lowercase());

    let active = active_wifi
        .as_ref()
        .map(|(ssid, state)| (ssid.as_slice(), *state));
    snap.networks = group_networks(&aps, saved, active);
    snap
}

async fn call<B>(
    conn: &Connection,
    path: &str,
    iface: &str,
    method: &str,
    body: &B,
) -> zbus::Result<zbus::Message>
where
    B: serde::ser::Serialize + zbus::zvariant::DynamicType,
{
    conn.call_method(Some(NM), path, Some(iface), method, body)
        .await
}

fn object_path(path: &str) -> zbus::Result<ObjectPath<'_>> {
    Ok(ObjectPath::try_from(path)?)
}

async fn managed_objects(conn: &Connection) -> zbus::Result<Objects> {
    let reply = conn
        .call_method(
            Some(NM),
            "/org/freedesktop",
            Some("org.freedesktop.DBus.ObjectManager"),
            "GetManagedObjects",
            &(),
        )
        .await?;
    reply.body().deserialize()
}

async fn saved_connections(conn: &Connection) -> zbus::Result<Vec<Saved>> {
    let reply = call(conn, SETTINGS_PATH, IFACE_SETTINGS, "ListConnections", &()).await?;
    let paths: Vec<OwnedObjectPath> = reply.body().deserialize()?;
    let mut saved = Vec::with_capacity(paths.len());
    for path in paths {
        // A connection deleted between the two calls just drops out.
        if let Ok(reply) = call(conn, path.as_str(), IFACE_CONNECTION, "GetSettings", &()).await
            && let Ok(settings) = reply.body().deserialize::<SettingsMap>()
        {
            saved.push(parse_saved(path.as_str(), &settings));
        }
    }
    Ok(saved)
}

/// Sends a fresh snapshot whenever NetworkManager's state changes.
pub async fn watch(conn: Connection, tx: Sender<crate::Event>) {
    let rule = MatchRule::builder()
        .msg_type(MessageType::Signal)
        .sender(NM)
        .expect("valid bus name")
        .build();
    let mut stream = match MessageStream::for_match_rule(rule, &conn, None).await {
        Ok(stream) => stream,
        Err(e) => {
            eprintln!("net-panel: can't watch NetworkManager: {e}");
            return;
        }
    };
    let mut saved: Option<Vec<Saved>> = None;
    let mut last: Option<Snapshot> = None;
    loop {
        if saved.is_none() {
            saved = saved_connections(&conn).await.ok();
        }
        match managed_objects(&conn).await {
            Ok(objects) => {
                let snap = snapshot(&objects, saved.as_deref().unwrap_or_default());
                if last.as_ref() != Some(&snap) {
                    last = Some(snap.clone());
                    if tx
                        .send(crate::Event::Snapshot(Box::new(snap)))
                        .await
                        .is_err()
                    {
                        return;
                    }
                }
            }
            Err(e) => eprintln!("net-panel: reading NetworkManager state: {e}"),
        }

        // Wait for a change, then let the rest of its burst arrive.
        let Some(first) = stream.next().await else {
            return;
        };
        let mut settings_changed = touches_settings(first.ok().as_ref());
        glib::timeout_future(Duration::from_millis(120)).await;
        while let Some(Some(msg)) = stream.next().now_or_never() {
            settings_changed |= touches_settings(msg.ok().as_ref());
        }
        if settings_changed {
            saved = None;
        }
    }
}

fn touches_settings(msg: Option<&zbus::Message>) -> bool {
    let Some(msg) = msg else { return true };
    let header = msg.header();
    let iface = header.interface().map(|i| i.as_str()).unwrap_or_default();
    let member = header.member().map(|m| m.as_str()).unwrap_or_default();
    iface == IFACE_SETTINGS
        || iface == IFACE_CONNECTION
        || (iface == "org.freedesktop.DBus.Properties"
            && header
                .path()
                .is_some_and(|p| p.as_str().starts_with(SETTINGS_PATH)))
        || member == "NameOwnerChanged"
}

pub async fn request_scan(conn: &Connection, device: &str) -> zbus::Result<()> {
    let options: HashMap<&str, Value> = HashMap::new();
    call(conn, device, IFACE_WIRELESS, "RequestScan", &(options,))
        .await
        .map(drop)
}

pub async fn set_wifi_enabled(conn: &Connection, enabled: bool) -> zbus::Result<()> {
    conn.call_method(
        Some(NM),
        NM_PATH,
        Some("org.freedesktop.DBus.Properties"),
        "Set",
        &(NM, "WirelessEnabled", Value::from(enabled)),
    )
    .await
    .map(drop)
}

pub async fn set_networking(conn: &Connection, enabled: bool) -> zbus::Result<()> {
    call(conn, NM_PATH, NM, "Enable", &(enabled,))
        .await
        .map(drop)
}

/// Activates a saved connection; "/" lets NetworkManager pick the device and
/// access point.
pub async fn activate(conn: &Connection, settings: &str, device: &str) -> zbus::Result<String> {
    let body = (
        object_path(settings)?,
        object_path(device)?,
        object_path("/")?,
    );
    let reply = call(conn, NM_PATH, NM, "ActivateConnection", &body).await?;
    Ok(reply.body().deserialize::<OwnedObjectPath>()?.to_string())
}

/// Saves `settings` as a new connection and activates it on `device`,
/// returning (settings path, active connection path).
pub async fn add_and_activate(
    conn: &Connection,
    settings: NewSettings,
    device: &str,
    access_point: Option<&str>,
) -> zbus::Result<(String, String)> {
    let body = (
        settings,
        object_path(device)?,
        object_path(access_point.unwrap_or("/"))?,
    );
    let reply = call(conn, NM_PATH, NM, "AddAndActivateConnection", &body).await?;
    let (path, active): (OwnedObjectPath, OwnedObjectPath) = reply.body().deserialize()?;
    Ok((path.to_string(), active.to_string()))
}

pub async fn deactivate(conn: &Connection, active: &str) -> zbus::Result<()> {
    call(
        conn,
        NM_PATH,
        NM,
        "DeactivateConnection",
        &(object_path(active)?,),
    )
    .await
    .map(drop)
}

/// Disconnects a device and keeps it from auto-connecting until asked.
pub async fn disconnect(conn: &Connection, device: &str) -> zbus::Result<()> {
    call(conn, device, IFACE_DEVICE, "Disconnect", &())
        .await
        .map(drop)
}

pub async fn delete(conn: &Connection, settings: &str) -> zbus::Result<()> {
    call(conn, settings, IFACE_CONNECTION, "Delete", &())
        .await
        .map(drop)
}

/// The saved Wi-Fi key of a connection (PSK, or WEP key 0).
pub async fn wifi_key(conn: &Connection, settings: &str) -> zbus::Result<Option<String>> {
    let reply = call(
        conn,
        settings,
        IFACE_CONNECTION,
        "GetSecrets",
        &("802-11-wireless-security",),
    )
    .await?;
    let secrets: SettingsMap = reply.body().deserialize()?;
    let security = secrets.get("802-11-wireless-security");
    Ok(["psk", "wep-key0"]
        .iter()
        .map(|key| as_string(security.and_then(|s| value(s, key))))
        .find(|k| !k.is_empty()))
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Eap {
    Peap,
    Ttls,
}

/// What the user typed to join a network.
#[derive(Clone, Debug)]
pub enum Secret {
    None,
    Key(String),
    Login {
        eap: Eap,
        identity: String,
        password: String,
    },
}

fn section(entries: Vec<(&'static str, Value<'static>)>) -> HashMap<&'static str, Value<'static>> {
    entries.into_iter().collect()
}

/// Settings for joining `ssid`; NetworkManager fills in the rest from the
/// access point (or, for a hidden network, from what's given here).
pub fn wifi_settings(
    ssid: &[u8],
    security: Security,
    secret: &Secret,
    hidden: bool,
) -> NewSettings {
    let mut settings = NewSettings::new();
    settings.insert(
        "connection",
        section(vec![
            ("type", Value::from("802-11-wireless")),
            ("id", Value::from(crate::model::display_ssid(ssid))),
        ]),
    );
    let mut wireless = section(vec![
        ("ssid", Value::from(ssid.to_vec())),
        ("mode", Value::from("infrastructure")),
    ]);
    if hidden {
        wireless.insert("hidden", Value::from(true));
    }
    settings.insert("802-11-wireless", wireless);
    match (security, secret) {
        (Security::Wep, Secret::Key(key)) => {
            settings.insert(
                "802-11-wireless-security",
                section(vec![
                    ("key-mgmt", Value::from("none")),
                    ("wep-key0", Value::from(key.clone())),
                    ("wep-key-type", Value::from(1u32)),
                ]),
            );
        }
        (Security::Wpa3, Secret::Key(key)) => {
            settings.insert(
                "802-11-wireless-security",
                section(vec![
                    ("key-mgmt", Value::from("sae")),
                    ("psk", Value::from(key.clone())),
                ]),
            );
        }
        (Security::Wpa2 | Security::Wpa2Wpa3, Secret::Key(key)) => {
            settings.insert(
                "802-11-wireless-security",
                section(vec![
                    ("key-mgmt", Value::from("wpa-psk")),
                    ("psk", Value::from(key.clone())),
                ]),
            );
        }
        (Security::EnhancedOpen, _) => {
            settings.insert(
                "802-11-wireless-security",
                section(vec![("key-mgmt", Value::from("owe"))]),
            );
        }
        (
            Security::Enterprise,
            Secret::Login {
                eap,
                identity,
                password,
            },
        ) => {
            settings.insert(
                "802-11-wireless-security",
                section(vec![("key-mgmt", Value::from("wpa-eap"))]),
            );
            let (method, phase2) = match eap {
                Eap::Peap => ("peap", "mschapv2"),
                Eap::Ttls => ("ttls", "pap"),
            };
            settings.insert(
                "802-1x",
                section(vec![
                    ("eap", Value::from(vec![method])),
                    ("identity", Value::from(identity.clone())),
                    ("password", Value::from(password.clone())),
                    ("phase2-auth", Value::from(phase2)),
                ]),
            );
        }
        _ => {}
    }
    settings
}

/// A shared (NAT) access point on 2.4 GHz, which every client can join.
pub fn hotspot_settings(name: &str, password: &str) -> NewSettings {
    let mut settings = NewSettings::new();
    settings.insert(
        "connection",
        section(vec![
            ("id", Value::from(HOTSPOT_ID)),
            ("type", Value::from("802-11-wireless")),
            ("autoconnect", Value::from(false)),
        ]),
    );
    settings.insert(
        "802-11-wireless",
        section(vec![
            ("ssid", Value::from(name.as_bytes().to_vec())),
            ("mode", Value::from("ap")),
            ("band", Value::from("bg")),
        ]),
    );
    settings.insert(
        "802-11-wireless-security",
        section(vec![
            ("key-mgmt", Value::from("wpa-psk")),
            ("psk", Value::from(password.to_owned())),
            ("proto", Value::from(vec!["rsn"])),
            ("pairwise", Value::from(vec!["ccmp"])),
            ("group", Value::from(vec!["ccmp"])),
        ]),
    );
    settings.insert("ipv4", section(vec![("method", Value::from("shared"))]));
    settings.insert("ipv6", section(vec![("method", Value::from("ignore"))]));
    settings
}

/// The panel's secret agent registers under this name.
pub const AGENT_ID: &str = "io.github.net-panel";

pub async fn register_agent(conn: &Connection) -> zbus::Result<()> {
    call(
        conn,
        "/org/freedesktop/NetworkManager/AgentManager",
        "org.freedesktop.NetworkManager.AgentManager",
        "RegisterWithCapabilities",
        &(AGENT_ID, 0u32),
    )
    .await
    .map(drop)
}

/// Returns the SSID and setting a GetSecrets request is about.
pub fn request_ssid(settings: &SettingsMap) -> String {
    let wireless = settings.get("802-11-wireless");
    let ssid = as_bytes(wireless.and_then(|w| value(w, "ssid")));
    if ssid.is_empty() {
        as_string(settings.get("connection").and_then(|c| value(c, "id")))
    } else {
        crate::model::display_ssid(&ssid)
    }
}

pub fn request_identity(settings: &SettingsMap) -> String {
    as_string(settings.get("802-1x").and_then(|s| value(s, "identity")))
}

pub fn request_key_mgmt(settings: &SettingsMap) -> String {
    as_string(
        settings
            .get("802-11-wireless-security")
            .and_then(|s| value(s, "key-mgmt")),
    )
}

pub fn owned(value: Value<'static>) -> OwnedValue {
    value.try_into().expect("plain values convert")
}
