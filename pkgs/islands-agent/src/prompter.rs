//! gnome-keyring's prompter, in place of gcr's dialog (D-Bus starts that
//! only while nothing owns the name).

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use serde_json::json;
use zbus::object_server::ResponseDispatchNotifier;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};
use zbus::{Connection, fdo, message::Header};

use crate::Shell;
use crate::exchange::Exchange;

pub const NAME: &str = "org.gnome.keyring.SystemPrompter";
pub const PATH: &str = "/org/gnome/keyring/Prompter";
const CALLBACK: &str = "org.gnome.keyring.internal.Prompter.Callback";

#[derive(Clone)]
struct Caller {
    name: String,
    path: String,
}

impl Caller {
    fn new(header: &Header<'_>, callback: &OwnedObjectPath) -> Self {
        Self {
            name: header.sender().map(ToString::to_string).unwrap_or_default(),
            path: callback.to_string(),
        }
    }

    fn key(&self) -> String {
        format!("keyring {} {}", self.name, self.path)
    }

    /// `reply` is "" before the first answer
    async fn ready(
        &self,
        conn: &Connection,
        reply: &str,
        changed: HashMap<&str, Value<'_>>,
        exchange: String,
    ) {
        let body = (reply, changed, exchange);
        let result = conn
            .call_method(
                Some(self.name.as_str()),
                self.path.as_str(),
                Some(CALLBACK),
                "PromptReady",
                &body,
            )
            .await;
        if let Err(e) = result {
            eprintln!("keyring prompt: PromptReady failed: {e}");
        }
    }

    /// Unanswered when the asker stopped the prompt itself, as it usually
    /// does: its callback object is gone by then
    async fn done(&self, conn: &Connection) {
        let _ = conn
            .call_method(
                Some(self.name.as_str()),
                self.path.as_str(),
                Some(CALLBACK),
                "PromptDone",
                &(),
            )
            .await;
    }
}

struct Prompt {
    exchange: Exchange,
    // Each PerformPrompt brings only the properties that changed
    properties: HashMap<String, OwnedValue>,
}

impl Prompt {
    fn text(&self, name: &str) -> &str {
        self.properties
            .get(name)
            .and_then(|v| <&str>::try_from(&**v).ok())
            .unwrap_or_default()
    }

    fn flag(&self, name: &str) -> bool {
        self.properties
            .get(name)
            .and_then(|v| bool::try_from(&**v).ok())
            .unwrap_or_default()
    }
}

pub struct Prompter {
    shell: Shell,
    prompts: Arc<Mutex<HashMap<String, Prompt>>>,
}

impl Prompter {
    pub fn new(shell: Shell) -> Self {
        Self {
            shell,
            prompts: Arc::default(),
        }
    }
}

/// Runs `work` once the reply has gone out: the asker only takes
/// PromptReady once it has BeginPrompting's reply
fn after_reply(
    conn: &Connection,
    sent: impl Future<Output = ()> + Send + 'static,
    work: impl Future<Output = ()> + Send + 'static,
) {
    conn.executor()
        .spawn(
            async move {
                sent.await;
                work.await;
            },
            "keyring prompt",
        )
        .detach();
}

#[zbus::interface(name = "org.gnome.keyring.internal.Prompter")]
impl Prompter {
    async fn begin_prompting(
        &self,
        callback: OwnedObjectPath,
        #[zbus(header)] header: Header<'_>,
        #[zbus(connection)] conn: &Connection,
    ) -> fdo::Result<ResponseDispatchNotifier<()>> {
        let caller = Caller::new(&header, &callback);
        let prompt = Prompt {
            exchange: Exchange::new(),
            properties: HashMap::new(),
        };
        let ours = prompt.exchange.send(None);
        {
            let mut prompts = self.prompts.lock().unwrap();
            if prompts.contains_key(&caller.key()) {
                return Err(fdo::Error::Failed(
                    "already prompting for this callback".into(),
                ));
            }
            prompts.insert(caller.key(), prompt);
        }
        let (reply, sent) = ResponseDispatchNotifier::new(());
        let conn2 = conn.clone();
        after_reply(conn, sent, async move {
            caller.ready(&conn2, "", HashMap::new(), ours).await;
        });
        Ok(reply)
    }

    async fn perform_prompt(
        &self,
        callback: OwnedObjectPath,
        r#type: String,
        properties: HashMap<String, OwnedValue>,
        exchange: String,
        #[zbus(header)] header: Header<'_>,
        #[zbus(connection)] conn: &Connection,
    ) -> fdo::Result<ResponseDispatchNotifier<()>> {
        let caller = Caller::new(&header, &callback);
        let confirm = match r#type.as_str() {
            "confirm" => true,
            "password" => false,
            other => return Err(fdo::Error::InvalidArgs(format!("no {other} prompts"))),
        };
        let question = {
            let mut prompts = self.prompts.lock().unwrap();
            let prompt = prompts
                .get_mut(&caller.key())
                .ok_or_else(|| fdo::Error::Failed("not prompting for this callback".into()))?;
            prompt.properties.extend(properties);
            if !prompt.exchange.receive(&exchange) {
                return Err(fdo::Error::InvalidArgs("invalid secret exchange".into()));
            }
            json!({
                "kind": "keyring",
                "confirm": confirm,
                "title": prompt.text("title"),
                "message": prompt.text("message"),
                "description": prompt.text("description"),
                "warning": prompt.text("warning"),
                "new": prompt.flag("password-new"),
                "choice": prompt.text("choice-label"),
                "chosen": prompt.flag("choice-chosen"),
                "continue": prompt.text("continue-label"),
                "cancel": prompt.text("cancel-label"),
            })
        };
        // Asked before the reply, so a StopPrompting right after it finds
        // the question to withdraw
        let answer = self.shell.ask(&caller.key(), question);
        let (reply, sent) = ResponseDispatchNotifier::new(());
        let (prompts, conn2) = (self.prompts.clone(), conn.clone());
        after_reply(conn, sent, async move {
            let answer = answer.await;
            let chosen = answer
                .as_ref()
                .map(|a| a["chosen"].as_bool().unwrap_or_default());
            let secret = answer
                .as_ref()
                .filter(|_| !confirm)
                .map(|a| a["secret"].as_str().unwrap_or_default().to_owned());
            // gcr wraps each value in a second variant, and unwraps it so
            let mut changed = HashMap::<&str, Value<'_>>::new();
            if let Some(chosen) = chosen {
                changed.insert("choice-chosen", Value::new(Value::from(chosen)));
            }
            // 0 is no password at all, which gnome-keyring checks before
            // keeping a keyring unencrypted
            if let Some(secret) = &secret {
                let strength = i32::from(!secret.is_empty());
                changed.insert("password-strength", Value::new(Value::from(strength)));
            }
            // Gone if the asker stopped while the question was up
            let Some(ours) = prompts.lock().unwrap().get_mut(&caller.key()).map(|p| {
                // For a retry after a wrong password: gnome-keyring doesn't
                // send the choice again
                if let Some(chosen) = chosen {
                    p.properties.insert("choice-chosen".into(), chosen.into());
                }
                p.exchange.send(secret.as_deref())
            }) else {
                return;
            };
            let reply = if answer.is_some() { "yes" } else { "no" };
            caller.ready(&conn2, reply, changed, ours).await;
        });
        Ok(reply)
    }

    async fn stop_prompting(
        &self,
        callback: OwnedObjectPath,
        #[zbus(header)] header: Header<'_>,
        #[zbus(connection)] conn: &Connection,
    ) -> ResponseDispatchNotifier<()> {
        let caller = Caller::new(&header, &callback);
        self.prompts.lock().unwrap().remove(&caller.key());
        self.shell.cancel(&caller.key());
        let (reply, sent) = ResponseDispatchNotifier::new(());
        let conn2 = conn.clone();
        after_reply(conn, sent, async move {
            caller.done(&conn2).await;
        });
        reply
    }
}
