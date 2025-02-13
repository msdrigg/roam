use std::sync::Arc;

use ahash::AHashMap;
use chrono::{DateTime, Utc};
use serde::Serialize;

use crate::UserId;

#[derive(Clone, Default, Serialize)]
pub struct UserPresenceInfo {
    #[serde(serialize_with = "serialize_option_datetime")]
    last_support_typing: Option<DateTime<Utc>>,
    #[serde(serialize_with = "serialize_option_datetime")]
    last_self_typing: Option<DateTime<Utc>>,
}

fn serialize_option_datetime<S>(
    date: &Option<DateTime<Utc>>,
    serializer: S,
) -> Result<S::Ok, S::Error>
where
    S: serde::Serializer,
{
    match date {
        Some(date) => date
            .to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
            .serialize(serializer),
        None => serializer.serialize_none(),
    }
}

#[derive(Clone, Default)]
pub struct PresenceClient {
    internal: Arc<tokio::sync::Mutex<AHashMap<UserId, UserPresenceInfo>>>,
}

impl PresenceClient {
    pub async fn notify_support_typing(&self, user_id: UserId) {
        let mut internal = self.internal.lock().await;
        let user_presence_info = internal.entry(user_id).or_default();

        user_presence_info.last_support_typing = Some(Utc::now());
    }

    pub async fn notify_self_typing(&self, user_id: UserId) -> Result<(), anyhow::Error> {
        let mut internal = self.internal.lock().await;
        let user_presence_info = internal.entry(user_id).or_default();
        if user_presence_info.last_self_typing > Some(Utc::now() - chrono::Duration::seconds(1)) {
            return Err(anyhow::anyhow!("User is already typing"));
        }

        user_presence_info.last_self_typing = Some(Utc::now());
        Ok(())
    }

    pub async fn get_user_presence_info(&self, user_id: &UserId) -> UserPresenceInfo {
        let internal = self.internal.lock().await;
        internal.get(user_id).cloned().unwrap_or_default()
    }
}
