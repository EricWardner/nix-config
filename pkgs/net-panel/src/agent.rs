//! A NetworkManager secret agent, so password prompts (a key that was
//! wrong while joining, a saved network whose key changed) come to the panel
//! instead of nm-applet's dialogs. NetworkManager calls GetSecrets on this
//! object; the request goes to the panel and the call waits for its answer.

use std::collections::HashMap;

use async_channel::Sender;
use futures_util::StreamExt as _;
use zbus::Connection;
use zbus::zvariant::{OwnedObjectPath, Value};

use crate::Event;
use crate::nm::{self, Secret, SettingsMap};

/// NMSecretAgentGetSecretsFlags.
const ALLOW_INTERACTION: u32 = 0x1;
const REQUEST_NEW: u32 = 0x2;
const AGENT_PATH: &str = "/org/freedesktop/NetworkManager/SecretAgent";

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org.freedesktop.NetworkManager.SecretAgent")]
pub enum AgentError {
    #[zbus(error)]
    ZBus(zbus::Error),
    UserCanceled(String),
    AgentCanceled(String),
    NoSecrets(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Kind {
    Key { wep: bool },
    Login { identity: String },
}

/// A prompt for the panel to show; `reply` carries the answer back, and
/// dropping it cancels the request.
pub struct SecretRequest {
    pub connection_path: String,
    pub setting: String,
    pub ssid: String,
    pub kind: Kind,
    /// The previous secret failed.
    pub retry: bool,
    pub reply: Sender<Option<Secret>>,
}

pub enum AgentEvent {
    Request(SecretRequest),
    Cancel {
        connection_path: String,
        setting: String,
    },
}

struct Agent {
    tx: Sender<Event>,
}

fn secrets(setting: &str, kind: &Kind, secret: Secret) -> SettingsMap {
    let mut values = HashMap::new();
    match (kind, secret) {
        (Kind::Key { wep: true }, Secret::Key(key)) => {
            values.insert("wep-key0".to_owned(), nm::owned(Value::from(key)));
        }
        (Kind::Key { wep: false }, Secret::Key(key)) => {
            values.insert("psk".to_owned(), nm::owned(Value::from(key)));
        }
        (
            Kind::Login { .. },
            Secret::Login {
                identity, password, ..
            },
        ) => {
            values.insert("identity".to_owned(), nm::owned(Value::from(identity)));
            values.insert("password".to_owned(), nm::owned(Value::from(password)));
        }
        _ => {}
    }
    HashMap::from([(setting.to_owned(), values)])
}

#[zbus::interface(name = "org.freedesktop.NetworkManager.SecretAgent")]
impl Agent {
    async fn get_secrets(
        &self,
        connection: SettingsMap,
        connection_path: OwnedObjectPath,
        setting_name: String,
        _hints: Vec<String>,
        flags: u32,
    ) -> Result<SettingsMap, AgentError> {
        if flags & ALLOW_INTERACTION == 0 {
            return Err(AgentError::NoSecrets(
                "the panel only has secrets the user types".into(),
            ));
        }
        let kind = match setting_name.as_str() {
            "802-11-wireless-security" => Kind::Key {
                wep: nm::request_key_mgmt(&connection) == "none",
            },
            "802-1x" => Kind::Login {
                identity: nm::request_identity(&connection),
            },
            other => {
                return Err(AgentError::NoSecrets(format!(
                    "{other} secrets aren't supported"
                )));
            }
        };
        let (reply, answer) = async_channel::bounded(1);
        let request = SecretRequest {
            connection_path: connection_path.to_string(),
            setting: setting_name.clone(),
            ssid: nm::request_ssid(&connection),
            kind: kind.clone(),
            retry: flags & REQUEST_NEW != 0,
            reply,
        };
        if self
            .tx
            .send(Event::Agent(AgentEvent::Request(request)))
            .await
            .is_err()
        {
            return Err(AgentError::AgentCanceled("the panel isn't running".into()));
        }
        match answer.recv().await {
            Ok(Some(secret)) => Ok(secrets(&setting_name, &kind, secret)),
            Ok(None) => Err(AgentError::UserCanceled("cancelled".into())),
            Err(_) => Err(AgentError::AgentCanceled("the prompt was closed".into())),
        }
    }

    async fn cancel_get_secrets(&self, connection_path: OwnedObjectPath, setting_name: String) {
        let cancel = AgentEvent::Cancel {
            connection_path: connection_path.to_string(),
            setting: setting_name,
        };
        let _ = self.tx.send(Event::Agent(cancel)).await;
    }

    // Secrets the user types are saved by NetworkManager itself (system-owned),
    // so there is nothing for the agent to store or delete.
    async fn save_secrets(&self, _connection: SettingsMap, _connection_path: OwnedObjectPath) {}

    async fn delete_secrets(&self, _connection: SettingsMap, _connection_path: OwnedObjectPath) {}
}

/// Serves the agent and keeps it registered, including after NetworkManager
/// restarts (agents are per NetworkManager process).
pub async fn run(conn: Connection, tx: Sender<Event>) {
    if let Err(e) = conn.object_server().at(AGENT_PATH, Agent { tx }).await {
        eprintln!("net-panel: can't serve the secret agent: {e}");
        return;
    }
    register(&conn).await;
    let Ok(dbus) = zbus::fdo::DBusProxy::new(&conn).await else {
        return;
    };
    let Ok(mut owners) = dbus
        .receive_name_owner_changed_with_args(&[(0, nm::NM)])
        .await
    else {
        return;
    };
    while let Some(change) = owners.next().await {
        if change.args().is_ok_and(|a| a.new_owner().is_some()) {
            register(&conn).await;
        }
    }
}

/// Registers, retrying for a few seconds: on a restart the previous process's
/// registration (same ID) lingers until NetworkManager sees it gone.
async fn register(conn: &Connection) {
    for attempt in 1..=10 {
        match nm::register_agent(conn).await {
            Ok(()) => return,
            Err(e) if attempt == 10 => eprintln!("net-panel: can't register the secret agent: {e}"),
            Err(_) => gtk::glib::timeout_future(std::time::Duration::from_secs(1)).await,
        }
    }
}
