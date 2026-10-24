//! NetworkManager state as the panel and the tray icon see it. Pure data,
//! built by `nm` from one GetManagedObjects call plus the saved connections,
//! so the grouping, sorting and icon rules are unit-tested here.

// NM80211ApFlags and NM80211ApSecurityFlags (nm-dbus-interface.h).
const AP_FLAGS_PRIVACY: u32 = 0x1;
const KEY_MGMT_PSK: u32 = 0x100;
const KEY_MGMT_802_1X: u32 = 0x200;
const KEY_MGMT_SAE: u32 = 0x400;
const KEY_MGMT_OWE: u32 = 0x800;
const KEY_MGMT_OWE_TM: u32 = 0x1000;
const KEY_MGMT_EAP_SUITE_B_192: u32 = 0x2000;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Security {
    Open,
    EnhancedOpen,
    Wep,
    Wpa2,
    Wpa3,
    Wpa2Wpa3,
    Enterprise,
}

impl Security {
    pub fn from_flags(flags: u32, wpa: u32, rsn: u32) -> Self {
        let key_mgmt = wpa | rsn;
        if key_mgmt & (KEY_MGMT_802_1X | KEY_MGMT_EAP_SUITE_B_192) != 0 {
            Self::Enterprise
        } else if key_mgmt & KEY_MGMT_SAE != 0 && key_mgmt & KEY_MGMT_PSK != 0 {
            Self::Wpa2Wpa3
        } else if key_mgmt & KEY_MGMT_SAE != 0 {
            Self::Wpa3
        } else if key_mgmt & KEY_MGMT_PSK != 0 {
            Self::Wpa2
        } else if key_mgmt & (KEY_MGMT_OWE | KEY_MGMT_OWE_TM) != 0 {
            Self::EnhancedOpen
        } else if flags & AP_FLAGS_PRIVACY != 0 {
            Self::Wep
        } else {
            Self::Open
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Open => "Open",
            Self::EnhancedOpen => "Enhanced Open",
            Self::Wep => "WEP",
            Self::Wpa2 => "WPA2",
            Self::Wpa3 => "WPA3",
            Self::Wpa2Wpa3 => "WPA2/WPA3",
            Self::Enterprise => "Enterprise",
        }
    }

    /// Whether joining asks for something (a key, or a login).
    pub fn secured(self) -> bool {
        !matches!(self, Self::Open | Self::EnhancedOpen)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Band {
    G2,
    G5,
    G6,
}

impl Band {
    pub fn from_frequency(mhz: u32) -> Option<Self> {
        match mhz {
            2400..=2500 => Some(Self::G2),
            5150..=5925 => Some(Self::G5),
            5926..=7125 => Some(Self::G6),
            _ => None,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::G2 => "2.4 GHz",
            Self::G5 => "5 GHz",
            Self::G6 => "6 GHz",
        }
    }
}

pub fn channel(mhz: u32) -> Option<u32> {
    match mhz {
        2484 => Some(14),
        2412..=2472 => Some((mhz - 2407) / 5),
        5150..=5925 => Some((mhz - 5000) / 5),
        5926..=7125 => Some((mhz - 5950) / 5),
        _ => None,
    }
}

/// "2.4 GHz", or "2.4 and 5 GHz" for a network on several bands.
pub fn bands_label(bands: &[Band]) -> String {
    match bands {
        [] => String::new(),
        [one] => one.label().to_owned(),
        many => {
            let numbers: Vec<&str> = many
                .iter()
                .map(|b| b.label().trim_end_matches(" GHz"))
                .collect();
            let (last, rest) = numbers.split_last().expect("non-empty");
            format!("{} and {last} GHz", rest.join(", "))
        }
    }
}

/// The four signal levels the icons draw: 1 is just the dot.
pub fn signal_level(strength: u8) -> u8 {
    match strength {
        76.. => 4,
        51..=75 => 3,
        26..=50 => 2,
        _ => 1,
    }
}

pub fn signal_label(strength: u8) -> &'static str {
    match signal_level(strength) {
        4 => "Excellent",
        3 => "Good",
        2 => "Fair",
        _ => "Weak",
    }
}

pub fn display_ssid(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

#[derive(Clone, Debug, PartialEq)]
pub struct AccessPoint {
    pub path: String,
    pub ssid: Vec<u8>,
    pub bssid: String,
    pub strength: u8,
    pub frequency: u32,
    pub security: Security,
}

/// A saved NetworkManager connection (Settings.Connection) of any type.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct Saved {
    pub path: String,
    pub id: String,
    pub kind: String,
    pub ssid: Vec<u8>,
    pub mode: String,
    pub timestamp: u64,
}

impl Saved {
    pub fn is_wifi_client(&self) -> bool {
        self.kind == "802-11-wireless" && (self.mode.is_empty() || self.mode == "infrastructure")
    }

    pub fn is_vpn(&self) -> bool {
        self.kind == "vpn" || self.kind == "wireguard"
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum NetState {
    #[default]
    Idle,
    Activating,
    Active,
}

/// Every access point broadcasting one SSID, shown as one row.
#[derive(Clone, Debug, PartialEq)]
pub struct Network {
    pub ssid: String,
    pub ssid_bytes: Vec<u8>,
    pub strength: u8,
    pub best_ap: String,
    pub ap_count: usize,
    pub bands: Vec<Band>,
    pub security: Security,
    /// Settings path of the saved connection to reuse, if any.
    pub saved: Option<String>,
    pub state: NetState,
}

/// Groups access points by SSID, attaches saved connections and sorts:
/// the active network first, then saved ones, then the rest, each by signal.
/// Hidden networks (empty SSID) are dropped; they're joined by name.
pub fn group_networks(
    aps: &[AccessPoint],
    saved: &[Saved],
    active: Option<(&[u8], NetState)>,
) -> Vec<Network> {
    let mut networks: Vec<Network> = Vec::new();
    for ap in aps.iter().filter(|ap| !ap.ssid.is_empty()) {
        let band = Band::from_frequency(ap.frequency);
        match networks.iter_mut().find(|n| n.ssid_bytes == ap.ssid) {
            Some(network) => {
                network.ap_count += 1;
                if ap.strength > network.strength {
                    network.strength = ap.strength;
                    network.best_ap = ap.path.clone();
                    network.security = ap.security;
                }
                if let Some(band) = band
                    && !network.bands.contains(&band)
                {
                    network.bands.push(band);
                }
            }
            None => networks.push(Network {
                ssid: display_ssid(&ap.ssid),
                ssid_bytes: ap.ssid.clone(),
                strength: ap.strength,
                best_ap: ap.path.clone(),
                ap_count: 1,
                bands: band.into_iter().collect(),
                security: ap.security,
                saved: None,
                state: NetState::Idle,
            }),
        }
    }

    for network in &mut networks {
        network.bands.sort();
        network.saved = saved
            .iter()
            .filter(|s| s.is_wifi_client() && s.ssid == network.ssid_bytes)
            .max_by_key(|s| s.timestamp)
            .map(|s| s.path.clone());
        if let Some((ssid, state)) = active
            && ssid == network.ssid_bytes.as_slice()
        {
            network.state = state;
        }
    }

    networks.sort_by(|a, b| {
        let rank = |n: &Network| match (n.state, n.saved.is_some()) {
            (NetState::Active | NetState::Activating, _) => 0,
            (_, true) => 1,
            _ => 2,
        };
        rank(a)
            .cmp(&rank(b))
            .then(b.strength.cmp(&a.strength))
            .then_with(|| a.ssid.to_lowercase().cmp(&b.ssid.to_lowercase()))
    });
    networks
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct WifiDevice {
    pub path: String,
    pub interface: String,
    pub state: u32,
    pub last_scan: i64,
    pub hw_address: String,
}

/// The Wi-Fi connection that is up or coming up.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct Current {
    pub ssid: String,
    pub ssid_bytes: Vec<u8>,
    pub hotspot: bool,
    pub state: NetState,
    pub strength: u8,
    pub frequency: u32,
    pub security: Option<Security>,
    /// Link rate in kbit/s.
    pub bitrate: u32,
    pub ip4: Option<String>,
    pub gateway: Option<String>,
    pub dns: Vec<String>,
    pub ip6: Option<String>,
    pub active_path: String,
    pub settings_path: String,
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct Wired {
    pub path: String,
    pub interface: String,
    pub state: u32,
    pub carrier: bool,
    /// Link speed in Mb/s.
    pub speed: u32,
    pub active_id: Option<String>,
    pub ip4: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct Vpn {
    pub settings_path: String,
    pub id: String,
    pub active_path: Option<String>,
    pub state: NetState,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Primary {
    #[default]
    None,
    Wifi,
    Wired,
    Other,
}

/// NMConnectivityState.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]
pub enum Connectivity {
    #[default]
    Unknown,
    None,
    Portal,
    Limited,
    Full,
}

impl Connectivity {
    pub fn from_nm(value: u32) -> Self {
        match value {
            1 => Self::None,
            2 => Self::Portal,
            3 => Self::Limited,
            4 => Self::Full,
            _ => Self::Unknown,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct Snapshot {
    pub networking: bool,
    pub wifi_enabled: bool,
    pub wifi_hardware: bool,
    pub wifi: Option<WifiDevice>,
    pub networks: Vec<Network>,
    pub current: Option<Current>,
    pub wired: Vec<Wired>,
    pub vpns: Vec<Vpn>,
    pub primary: Primary,
    pub connectivity: Connectivity,
    /// Settings path of the connection the hotspot form reuses.
    pub hotspot_saved: Option<String>,
}

impl Snapshot {
    pub fn vpn_active(&self) -> bool {
        self.vpns.iter().any(|v| v.state == NetState::Active)
    }

    pub fn wired_up(&self) -> Option<&Wired> {
        self.wired.iter().find(|w| w.state == 100)
    }

    fn limited(&self) -> bool {
        matches!(
            self.connectivity,
            Connectivity::Portal | Connectivity::Limited
        )
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TrayIcon {
    Airplane,
    Off,
    Disconnected,
    Connecting,
    Wifi { level: u8, limited: bool, vpn: bool },
    Wired { limited: bool, vpn: bool },
}

impl TrayIcon {
    pub fn from_snapshot(snapshot: &Snapshot, airplane: bool) -> Self {
        let limited = snapshot.limited();
        let vpn = snapshot.vpn_active();
        let wifi_up = snapshot
            .current
            .as_ref()
            .filter(|c| c.state == NetState::Active);
        if airplane {
            Self::Airplane
        } else if !snapshot.networking {
            Self::Off
        } else if snapshot.primary == Primary::Wired
            || (wifi_up.is_none() && snapshot.wired_up().is_some())
        {
            Self::Wired { limited, vpn }
        } else if let Some(current) = wifi_up {
            let level = if current.hotspot {
                4
            } else {
                signal_level(current.strength)
            };
            Self::Wifi {
                level,
                limited,
                vpn,
            }
        } else if snapshot.current.is_some()
            || snapshot.wired.iter().any(|w| (40..100).contains(&w.state))
        {
            Self::Connecting
        } else if !snapshot.wifi_enabled || !snapshot.wifi_hardware {
            Self::Off
        } else {
            Self::Disconnected
        }
    }

    /// Icon file stem; `phase` (1-3) steps the connecting animation.
    pub fn name(self, phase: u8) -> String {
        let badge = |limited: bool, vpn: bool| match (limited, vpn) {
            (true, _) => "-limited",
            (false, true) => "-vpn",
            _ => "",
        };
        let stem = match self {
            Self::Airplane => "airplane".to_owned(),
            Self::Off => "off".to_owned(),
            Self::Disconnected => "disconnected".to_owned(),
            Self::Connecting => format!("connecting-{}", phase.clamp(1, 3)),
            Self::Wifi {
                level,
                limited,
                vpn,
            } => format!("wifi-{level}{}", badge(limited, vpn)),
            Self::Wired { limited, vpn } => format!("wired{}", badge(limited, vpn)),
        };
        format!("net-panel-{stem}-symbolic")
    }
}

/// Tooltip title and body for the tray icon.
pub fn tooltip(snapshot: &Snapshot, airplane: bool) -> (String, String) {
    let limited = match snapshot.connectivity {
        Connectivity::Portal => " · Sign-in required",
        Connectivity::Limited => " · No internet",
        _ => "",
    };
    let vpn: Vec<&str> = snapshot
        .vpns
        .iter()
        .filter(|v| v.state == NetState::Active)
        .map(|v| v.id.as_str())
        .collect();
    let vpn = if vpn.is_empty() {
        String::new()
    } else {
        format!("\nVPN: {}", vpn.join(", "))
    };
    if airplane {
        return ("Airplane mode".into(), String::new());
    }
    if !snapshot.networking {
        return ("Networking off".into(), String::new());
    }
    if let Some(wired) = snapshot.wired_up()
        && snapshot.primary != Primary::Wifi
    {
        let speed = if wired.speed > 0 {
            format!(" · {}", speed_label(wired.speed * 1000))
        } else {
            String::new()
        };
        return (
            format!("Wired{limited}"),
            format!("{}{speed}{vpn}", wired.interface),
        );
    }
    match &snapshot.current {
        Some(c) if c.state == NetState::Active && c.hotspot => {
            (format!("Hotspot: {}", c.ssid), vpn.trim().to_owned())
        }
        Some(c) if c.state == NetState::Active => {
            let band = Band::from_frequency(c.frequency)
                .map(|b| format!(" · {}", b.label()))
                .unwrap_or_default();
            (
                format!("{}{limited}", c.ssid),
                format!("Signal {}%{band}{vpn}", c.strength),
            )
        }
        Some(c) => (format!("Connecting to {}…", c.ssid), String::new()),
        None if !snapshot.wifi_enabled => ("Wi-Fi off".into(), String::new()),
        None => ("Not connected".into(), String::new()),
    }
}

/// "866 Mb/s" from a rate in kbit/s.
pub fn speed_label(kbit: u32) -> String {
    if kbit >= 1_000_000 {
        format!("{:.1} Gb/s", f64::from(kbit) / 1_000_000.0)
    } else {
        format!("{} Mb/s", kbit / 1000)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ap(path: &str, ssid: &str, strength: u8, frequency: u32, security: Security) -> AccessPoint {
        AccessPoint {
            path: path.into(),
            ssid: ssid.as_bytes().to_vec(),
            bssid: String::new(),
            strength,
            frequency,
            security,
        }
    }

    fn saved(path: &str, ssid: &str, timestamp: u64) -> Saved {
        Saved {
            path: path.into(),
            id: ssid.into(),
            kind: "802-11-wireless".into(),
            ssid: ssid.as_bytes().to_vec(),
            mode: "infrastructure".into(),
            timestamp,
        }
    }

    #[test]
    fn security_from_flags() {
        // RsnFlags 392 = PSK | PAIR_CCMP | GROUP_CCMP, from a live scan.
        assert_eq!(Security::from_flags(1, 0, 392), Security::Wpa2);
        assert_eq!(Security::from_flags(1, 0, 0x400 | 0x88), Security::Wpa3);
        assert_eq!(Security::from_flags(1, 0, 0x500 | 0x88), Security::Wpa2Wpa3);
        assert_eq!(
            Security::from_flags(1, 0, 0x200 | 0x88),
            Security::Enterprise
        );
        assert_eq!(Security::from_flags(0, 0, 0x800), Security::EnhancedOpen);
        assert_eq!(Security::from_flags(1, 0, 0), Security::Wep);
        assert_eq!(Security::from_flags(0, 0, 0), Security::Open);
        assert!(!Security::EnhancedOpen.secured());
        assert!(Security::Wep.secured());
    }

    #[test]
    fn bands_and_channels() {
        assert_eq!(Band::from_frequency(2437), Some(Band::G2));
        assert_eq!(Band::from_frequency(5240), Some(Band::G5));
        assert_eq!(Band::from_frequency(5955), Some(Band::G6));
        assert_eq!(channel(2412), Some(1));
        assert_eq!(channel(2484), Some(14));
        assert_eq!(channel(5240), Some(48));
        assert_eq!(channel(5955), Some(1));
        assert_eq!(bands_label(&[Band::G2]), "2.4 GHz");
        assert_eq!(bands_label(&[Band::G2, Band::G5]), "2.4 and 5 GHz");
        assert_eq!(
            bands_label(&[Band::G2, Band::G5, Band::G6]),
            "2.4, 5 and 6 GHz"
        );
    }

    #[test]
    fn signal_levels() {
        assert_eq!(signal_level(100), 4);
        assert_eq!(signal_level(76), 4);
        assert_eq!(signal_level(75), 3);
        assert_eq!(signal_level(51), 3);
        assert_eq!(signal_level(50), 2);
        assert_eq!(signal_level(26), 2);
        assert_eq!(signal_level(25), 1);
        assert_eq!(signal_level(0), 1);
    }

    #[test]
    fn groups_duplicate_ssids() {
        let aps = [
            ap("/a", "xfinitywifi", 30, 2437, Security::Open),
            ap("/b", "xfinitywifi", 55, 5180, Security::Open),
            ap("/c", "", 99, 5240, Security::Wpa2),
        ];
        let networks = group_networks(&aps, &[], None);
        assert_eq!(networks.len(), 1, "hidden SSID dropped, duplicates merged");
        let n = &networks[0];
        assert_eq!(n.ap_count, 2);
        assert_eq!(n.strength, 55);
        assert_eq!(n.best_ap, "/b");
        assert_eq!(n.bands, vec![Band::G2, Band::G5]);
    }

    #[test]
    fn sorts_active_then_saved_then_others() {
        let aps = [
            ap("/1", "Royal Jelly", 70, 2437, Security::Wpa2),
            ap("/2", "ChateauCherry", 60, 2437, Security::Wpa2),
            ap("/3", "Shermans Hotspot", 40, 5240, Security::Wpa2),
            ap("/4", "LML622", 45, 2437, Security::Wpa2),
            ap("/5", "aardvark", 70, 2437, Security::Open),
        ];
        let saved = [
            saved("/s1", "ChateauCherry", 1),
            saved("/s2", "LML622", 2),
            saved("/s3", "Shermans Hotspot", 3),
        ];
        let networks = group_networks(&aps, &saved, Some((b"Shermans Hotspot", NetState::Active)));
        let order: Vec<&str> = networks.iter().map(|n| n.ssid.as_str()).collect();
        assert_eq!(
            order,
            [
                "Shermans Hotspot",
                "ChateauCherry",
                "LML622",
                "aardvark",
                "Royal Jelly"
            ]
        );
        assert_eq!(networks[0].state, NetState::Active);
        assert_eq!(networks[1].saved.as_deref(), Some("/s1"));
        assert_eq!(networks[3].saved, None);
    }

    #[test]
    fn prefers_most_recent_saved_connection() {
        let aps = [ap("/1", "Home", 80, 2437, Security::Wpa2)];
        let saved = [saved("/old", "Home", 10), saved("/new", "Home", 20)];
        let networks = group_networks(&aps, &saved, None);
        assert_eq!(networks[0].saved.as_deref(), Some("/new"));
    }

    #[test]
    fn ignores_hotspot_profiles_as_known_networks() {
        let aps = [ap("/1", "Home", 80, 2437, Security::Wpa2)];
        let mut hotspot = saved("/hs", "Home", 5);
        hotspot.mode = "ap".into();
        let networks = group_networks(&aps, &[hotspot], None);
        assert_eq!(networks[0].saved, None);
    }

    fn connected(strength: u8) -> Snapshot {
        Snapshot {
            networking: true,
            wifi_enabled: true,
            wifi_hardware: true,
            primary: Primary::Wifi,
            connectivity: Connectivity::Full,
            current: Some(Current {
                ssid: "Home".into(),
                state: NetState::Active,
                strength,
                frequency: 5240,
                ..Current::default()
            }),
            ..Snapshot::default()
        }
    }

    #[test]
    fn tray_icon_states() {
        assert_eq!(
            TrayIcon::from_snapshot(&connected(80), false).name(1),
            "net-panel-wifi-4-symbolic"
        );
        assert_eq!(
            TrayIcon::from_snapshot(&connected(30), false).name(1),
            "net-panel-wifi-2-symbolic"
        );
        assert_eq!(
            TrayIcon::from_snapshot(&connected(80), true).name(1),
            "net-panel-airplane-symbolic"
        );

        let mut portal = connected(60);
        portal.connectivity = Connectivity::Portal;
        assert_eq!(
            TrayIcon::from_snapshot(&portal, false).name(1),
            "net-panel-wifi-3-limited-symbolic"
        );

        let mut vpn = connected(60);
        vpn.vpns.push(Vpn {
            state: NetState::Active,
            ..Vpn::default()
        });
        assert_eq!(
            TrayIcon::from_snapshot(&vpn, false).name(1),
            "net-panel-wifi-3-vpn-symbolic"
        );

        let mut connecting = connected(60);
        connecting.current.as_mut().unwrap().state = NetState::Activating;
        connecting.primary = Primary::None;
        assert_eq!(
            TrayIcon::from_snapshot(&connecting, false).name(2),
            "net-panel-connecting-2-symbolic"
        );

        let mut wired = connected(60);
        wired.primary = Primary::Wired;
        wired.wired.push(Wired {
            state: 100,
            ..Wired::default()
        });
        assert_eq!(
            TrayIcon::from_snapshot(&wired, false).name(1),
            "net-panel-wired-symbolic"
        );

        let mut off = connected(60);
        off.current = None;
        off.primary = Primary::None;
        off.wifi_enabled = false;
        assert_eq!(
            TrayIcon::from_snapshot(&off, false).name(1),
            "net-panel-off-symbolic"
        );
        off.wifi_enabled = true;
        assert_eq!(
            TrayIcon::from_snapshot(&off, false).name(1),
            "net-panel-disconnected-symbolic"
        );
    }

    #[test]
    fn speeds() {
        assert_eq!(speed_label(573_500), "573 Mb/s");
        assert_eq!(speed_label(1_200_000), "1.2 Gb/s");
    }
}
