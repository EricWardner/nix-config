//! islands-agent: NetworkManager's secret agent, BlueZ's pairing agent and
//! gnome-keyring's prompter for the islands shell, which asks their
//! questions in its centre island.
//!
//! The shell runs it as a child process, and they talk in JSON lines. Each
//! question goes out on stdout (`{"id":1,"kind":"wifi","ssid":…}`), and its
//! answer comes back on stdin (`{"id":1,"value":…}`, with `null` for
//! cancel). A question the asker gave up on goes out as
//! `{"id":1,"kind":"cancel"}`. It exits when stdin closes, so it never
//! outlives the shell, and the agents go with it.

mod exchange;
mod prompter;

use std::collections::HashMap;
use std::io::{BufRead as _, Write as _};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures_util::StreamExt as _;
use serde_json::{Value as Json, json};
use zbus::Connection;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};

const NM: &str = "org.freedesktop.NetworkManager";
const BLUEZ: &str = "org.bluez";
const SECRETS_PATH: &str = "/org/freedesktop/NetworkManager/SecretAgent";
const PAIRING_PATH: &str = "/io/github/islands/PairingAgent";
const AGENT_ID: &str = "io.github.islands.agent";

/// a{sa{sv}}: a connection's settings, or secrets, by setting name
type SettingsMap = HashMap<String, HashMap<String, OwnedValue>>;

/// A question's way back to its asker, and the key the asker cancels it by
type Waiting = (async_channel::Sender<Json>, String);

/// The questions waiting on the shell, by id
#[derive(Clone, Default)]
struct Shell {
    next: Arc<AtomicU64>,
    waiting: Arc<Mutex<HashMap<u64, Waiting>>>,
}

impl Shell {
    fn send(&self, key: &str, mut question: Json) -> (u64, async_channel::Receiver<Json>) {
        let id = self.next.fetch_add(1, Ordering::Relaxed) + 1;
        let (tx, rx) = async_channel::bounded(1);
        self.waiting
            .lock()
            .unwrap()
            .insert(id, (tx, key.to_owned()));
        question["id"] = json!(id);
        emit(&question);
        (id, rx)
    }

    /// Asks the shell, and waits: None if it was cancelled, by either side
    async fn ask(&self, key: &str, question: Json) -> Option<Json> {
        let (id, rx) = self.send(key, question);
        let answer = rx.recv().await.ok();
        self.waiting.lock().unwrap().remove(&id);
        answer.filter(|value| !value.is_null())
    }

    /// Shows something without waiting for an answer (a passkey to type on
    /// a keyboard); the shell drops it once pairing is done
    fn show(&self, key: &str, question: Json) {
        drop(self.send(key, question));
    }

    fn answer(&self, id: u64, value: Json) {
        if let Some((tx, _)) = self.waiting.lock().unwrap().remove(&id) {
            let _ = tx.try_send(value);
        }
    }

    /// Withdraws the questions asked under `key`
    fn cancel(&self, key: &str) {
        let mut waiting = self.waiting.lock().unwrap();
        let ids: Vec<u64> = waiting
            .iter()
            .filter(|(_, (_, k))| k == key)
            .map(|(id, _)| *id)
            .collect();
        for id in ids {
            waiting.remove(&id);
            emit(&json!({ "id": id, "kind": "cancel" }));
        }
    }
}

fn emit(message: &Json) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{message}");
    let _ = out.flush();
}

fn owned(value: Value<'_>) -> OwnedValue {
    OwnedValue::try_from(value).expect("a string holds no file descriptors")
}

/// A string from a connection's settings, or ""
fn setting(map: &SettingsMap, section: &str, key: &str) -> String {
    map.get(section)
        .and_then(|s| s.get(key))
        .and_then(|v| <&str>::try_from(&**v).ok())
        .unwrap_or_default()
        .to_owned()
}

/// The network's name, from its SSID's bytes, or the connection's name
fn ssid(map: &SettingsMap) -> String {
    let bytes: Vec<u8> = match map
        .get("802-11-wireless")
        .and_then(|w| w.get("ssid"))
        .map(|v| &**v)
    {
        Some(Value::Array(array)) => array.iter().filter_map(|b| u8::try_from(b).ok()).collect(),
        _ => Vec::new(),
    };
    if bytes.is_empty() {
        setting(map, "connection", "id")
    } else {
        String::from_utf8_lossy(&bytes).into_owned()
    }
}

/// NMSecretAgentGetSecretsFlags
const ALLOW_INTERACTION: u32 = 0x1;
const REQUEST_NEW: u32 = 0x2;

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.freedesktop.NetworkManager.SecretAgent")]
enum SecretError {
    #[zbus(error)]
    ZBus(zbus::Error),
    UserCanceled(String),
    NoSecrets(String),
}

/// NetworkManager asks this for a password it doesn't have: joining a
/// network that wasn't given one, or a saved one whose password changed
struct Secrets {
    shell: Shell,
}

#[zbus::interface(name = "org.freedesktop.NetworkManager.SecretAgent")]
impl Secrets {
    async fn get_secrets(
        &self,
        connection: SettingsMap,
        connection_path: OwnedObjectPath,
        setting_name: String,
        _hints: Vec<String>,
        flags: u32,
    ) -> Result<SettingsMap, SecretError> {
        if flags & ALLOW_INTERACTION == 0 {
            return Err(SecretError::NoSecrets("only secrets someone types".into()));
        }
        let (login, wep) = match setting_name.as_str() {
            "802-11-wireless-security" => (
                false,
                setting(&connection, "802-11-wireless-security", "key-mgmt") == "none",
            ),
            "802-1x" => (true, false),
            other => {
                return Err(SecretError::NoSecrets(format!(
                    "{other} secrets aren't supported"
                )));
            }
        };
        let question = json!({
            "kind": "wifi",
            "ssid": ssid(&connection),
            "retry": flags & REQUEST_NEW != 0,
            "login": login,
            "identity": setting(&connection, "802-1x", "identity"),
        });
        let key = format!("{} {setting_name}", connection_path.as_str());
        let answer = self
            .shell
            .ask(&key, question)
            .await
            .ok_or_else(|| SecretError::UserCanceled("cancelled".into()))?;
        let text = |name: &str| answer[name].as_str().unwrap_or_default().to_owned();
        let mut values = HashMap::new();
        if login {
            values.insert("identity".to_owned(), owned(Value::from(text("identity"))));
            values.insert("password".to_owned(), owned(Value::from(text("secret"))));
        } else {
            let name = if wep { "wep-key0" } else { "psk" };
            values.insert(name.to_owned(), owned(Value::from(text("secret"))));
        }
        Ok(HashMap::from([(setting_name, values)]))
    }

    async fn cancel_get_secrets(&self, connection_path: OwnedObjectPath, setting_name: String) {
        self.shell
            .cancel(&format!("{} {setting_name}", connection_path.as_str()));
    }

    // NetworkManager keeps typed secrets itself, so there's nothing to store
    async fn save_secrets(&self, _connection: SettingsMap, _connection_path: OwnedObjectPath) {}

    async fn delete_secrets(&self, _connection: SettingsMap, _connection_path: OwnedObjectPath) {}
}

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.bluez.Error")]
enum PairingError {
    #[zbus(error)]
    ZBus(zbus::Error),
    Rejected(String),
    Canceled(String),
}

/// BlueZ asks this while pairing: to confirm a passkey, to show one to type
/// on a keyboard, or for a PIN
struct Pairing {
    shell: Shell,
    conn: Connection,
}

impl Pairing {
    async fn device(&self, path: &OwnedObjectPath, property: &str) -> Option<OwnedValue> {
        let reply = self
            .conn
            .call_method(
                Some(BLUEZ),
                path.as_str(),
                Some("org.freedesktop.DBus.Properties"),
                "Get",
                &("org.bluez.Device1", property),
            )
            .await
            .ok()?;
        reply.body().deserialize::<OwnedValue>().ok()
    }

    async fn name(&self, path: &OwnedObjectPath) -> String {
        let alias = self.device(path, "Alias").await;
        alias
            .as_ref()
            .and_then(|v| <&str>::try_from(&**v).ok())
            .map_or_else(|| path.as_str().to_owned(), str::to_owned)
    }

    async fn question(&self, path: &OwnedObjectPath, kind: &str) -> Json {
        json!({ "kind": kind, "device": self.name(path).await, "path": path.as_str() })
    }

    async fn ask(
        &self,
        path: &OwnedObjectPath,
        kind: &str,
        passkey: Option<String>,
    ) -> Option<Json> {
        let mut question = self.question(path, kind).await;
        if let Some(passkey) = passkey {
            question["passkey"] = json!(passkey);
        }
        self.shell.ask("bluetooth", question).await
    }

    async fn agreed(
        &self,
        path: &OwnedObjectPath,
        kind: &str,
        passkey: Option<String>,
    ) -> Result<(), PairingError> {
        match self.ask(path, kind, passkey).await {
            Some(Json::Bool(true)) => Ok(()),
            Some(_) => Err(PairingError::Rejected("declined".into())),
            None => Err(PairingError::Canceled("cancelled".into())),
        }
    }
}

#[zbus::interface(name = "org.bluez.Agent1")]
impl Pairing {
    fn release(&self) {}

    async fn request_pin_code(&self, device: OwnedObjectPath) -> Result<String, PairingError> {
        match self.ask(&device, "bt-pin", None).await {
            Some(Json::String(pin)) => Ok(pin),
            _ => Err(PairingError::Canceled("cancelled".into())),
        }
    }

    async fn request_passkey(&self, device: OwnedObjectPath) -> Result<u32, PairingError> {
        match self.ask(&device, "bt-passkey", None).await {
            Some(Json::String(passkey)) => passkey
                .trim()
                .parse()
                .map_err(|_| PairingError::Rejected("not a number".into())),
            _ => Err(PairingError::Canceled("cancelled".into())),
        }
    }

    async fn display_pin_code(&self, device: OwnedObjectPath, pincode: String) {
        let mut question = self.question(&device, "bt-display").await;
        question["passkey"] = json!(pincode);
        self.shell.show("bluetooth", question);
    }

    // Called again as each digit is typed; the first call shows it
    async fn display_passkey(&self, device: OwnedObjectPath, passkey: u32, entered: u16) {
        if entered == 0 {
            let mut question = self.question(&device, "bt-display").await;
            question["passkey"] = json!(format!("{passkey:06}"));
            self.shell.show("bluetooth", question);
        }
    }

    async fn request_confirmation(
        &self,
        device: OwnedObjectPath,
        passkey: u32,
    ) -> Result<(), PairingError> {
        self.agreed(&device, "bt-confirm", Some(format!("{passkey:06}")))
            .await
    }

    async fn request_authorization(&self, device: OwnedObjectPath) -> Result<(), PairingError> {
        self.agreed(&device, "bt-authorize", None).await
    }

    // A device connecting a service: fine for one that's paired, asked
    // about otherwise
    async fn authorize_service(
        &self,
        device: OwnedObjectPath,
        _uuid: String,
    ) -> Result<(), PairingError> {
        let paired = self.device(&device, "Paired").await;
        if paired.as_ref().and_then(|v| bool::try_from(&**v).ok()) == Some(true) {
            return Ok(());
        }
        self.agreed(&device, "bt-authorize", None).await
    }

    fn cancel(&self) {
        self.shell.cancel("bluetooth");
    }
}

/// Registers with NetworkManager or BlueZ, retrying for a few seconds: after
/// a restart, NetworkManager keeps the old process's registration (same id)
/// until it sees it gone
async fn register(conn: &Connection, service: &str) {
    for attempt in 1..=10 {
        let result = if service == NM {
            conn.call_method(
                Some(NM),
                "/org/freedesktop/NetworkManager/AgentManager",
                Some("org.freedesktop.NetworkManager.AgentManager"),
                "RegisterWithCapabilities",
                &(AGENT_ID, 0u32),
            )
            .await
            .map(drop)
        } else {
            let path = zbus::zvariant::ObjectPath::from_static_str_unchecked(PAIRING_PATH);
            let agents = Some("org.bluez.AgentManager1");
            match conn
                .call_method(
                    Some(BLUEZ),
                    "/org/bluez",
                    agents,
                    "RegisterAgent",
                    &(&path, "KeyboardDisplay"),
                )
                .await
            {
                Ok(_) => conn
                    .call_method(
                        Some(BLUEZ),
                        "/org/bluez",
                        agents,
                        "RequestDefaultAgent",
                        &(&path,),
                    )
                    .await
                    .map(drop),
                Err(e) => Err(e),
            }
        };
        match result {
            Ok(()) => {
                eprintln!("registered with {service}");
                return;
            }
            Err(e) if attempt == 10 => {
                eprintln!("can't register with {service}: {e}")
            }
            Err(_) => std::thread::sleep(Duration::from_secs(1)),
        }
    }
}

/// Registers now and again whenever the service restarts (agents belong to
/// its process)
async fn keep_registered(conn: &Connection, service: &'static str) {
    register(conn, service).await;
    let Ok(dbus) = zbus::fdo::DBusProxy::new(conn).await else {
        return;
    };
    let Ok(mut owners) = dbus
        .receive_name_owner_changed_with_args(&[(0, service)])
        .await
    else {
        return;
    };
    while let Some(change) = owners.next().await {
        if change.args().is_ok_and(|a| a.new_owner().is_some()) {
            register(conn, service).await;
        }
    }
}

/// Takes the keyring's prompts from gcr's dialog, or queues for them while
/// it's up
async fn prompt_for_keyring(shell: Shell) -> zbus::Result<Connection> {
    let session = Connection::session().await?;
    session
        .object_server()
        .at(prompter::PATH, prompter::Prompter::new(shell))
        .await?;
    let flags = zbus::fdo::RequestNameFlags::ReplaceExisting.into();
    match session
        .request_name_with_flags(prompter::NAME, flags)
        .await?
    {
        zbus::fdo::RequestNameReply::InQueue => eprintln!("queued for {}", prompter::NAME),
        _ => eprintln!("registered as {}", prompter::NAME),
    }
    Ok(session)
}

async fn run(shell: Shell) -> zbus::Result<()> {
    let _session = prompt_for_keyring(shell.clone()).await?;
    let conn = Connection::system().await?;
    conn.object_server()
        .at(
            SECRETS_PATH,
            Secrets {
                shell: shell.clone(),
            },
        )
        .await?;
    conn.object_server()
        .at(
            PAIRING_PATH,
            Pairing {
                shell,
                conn: conn.clone(),
            },
        )
        .await?;
    futures_util::future::join(keep_registered(&conn, NM), keep_registered(&conn, BLUEZ)).await;
    Ok(())
}

fn main() {
    let shell = Shell::default();
    let answers = shell.clone();
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines() {
            let Ok(line) = line else { break };
            if let Ok(message) = serde_json::from_str::<Json>(&line)
                && let Some(id) = message["id"].as_u64()
            {
                answers.answer(id, message["value"].clone());
            }
        }
        // The shell is gone
        std::process::exit(0);
    });
    if let Err(e) = zbus::block_on(run(shell)) {
        eprintln!("islands-agent: {e}");
        std::process::exit(1);
    }
}
