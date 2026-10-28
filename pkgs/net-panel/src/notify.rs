//! Connection notifications through org.freedesktop.Notifications, each
//! replacing the last so a flaky link doesn't stack them up.

use std::cell::Cell;
use std::collections::HashMap;

use zbus::Connection;
use zbus::zvariant::Value;

#[derive(Default)]
pub struct Notifier {
    last: Cell<u32>,
}

impl Notifier {
    pub async fn send(&self, conn: &Connection, icon: &str, summary: &str, body: &str) {
        let hints: HashMap<&str, Value> = HashMap::from([("category", Value::from("network"))]);
        let reply = conn
            .call_method(
                Some("org.freedesktop.Notifications"),
                "/org/freedesktop/Notifications",
                Some("org.freedesktop.Notifications"),
                "Notify",
                &(
                    "Network",
                    self.last.get(),
                    icon,
                    summary,
                    body,
                    Vec::<&str>::new(),
                    hints,
                    4000i32,
                ),
            )
            .await;
        if let Ok(id) = reply.and_then(|r| r.body().deserialize::<u32>()) {
            self.last.set(id);
        }
    }
}
