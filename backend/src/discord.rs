use std::sync::{Arc, Mutex};

use crate::utils::{serialize_anyhow, serialize_reqwest, serialize_status_code};
use chrono::{DateTime, Utc};
use reqwest::StatusCode;
use serde::Serialize;
use tokio::sync::AcquireError;
use types::{IdResponse, Thread, ThreadResponse};

pub use types::{DiscordFile, DiscordMessage};

#[derive(Debug, Clone)]
pub struct DiscordClient {
    token: String,
    channel_id: i64,
    guild_id: i64,
    retry_at: Arc<Mutex<Option<DateTime<Utc>>>>,
    client: reqwest::Client,
    semaphore: Arc<tokio::sync::Semaphore>,
}

#[derive(Debug, thiserror::Error, Serialize)]
pub enum DiscordError {
    #[error("Rate limited for {retry_after} seconds. {message}")]
    RateLimited { message: String, retry_after: f64 },
    #[error("Failed to connect to Discord: {0}")]
    ConnectionError(#[serde(serialize_with = "serialize_anyhow")] anyhow::Error),
    #[error("Failed to parse response from Discord: {0}")]
    ResponseError(#[serde(serialize_with = "serialize_anyhow")] anyhow::Error),
    #[error("API error: {message}, status: {status}")]
    ApiError {
        message: String,
        #[serde(serialize_with = "serialize_status_code")]
        status: StatusCode,
    },
    #[error("Invalid input: {0}")]
    InvalidInput(#[serde(serialize_with = "serialize_reqwest")] reqwest::Error),
}

impl DiscordClient {
    const DISCORD_API_BASE_URL: &str = "https://discord.com/api/v10";
    const DEFAULT_AUTO_ARCHIVE_DURATION: i64 = 10080;

    async fn acquire(&self) -> Result<tokio::sync::SemaphorePermit<'_>, AcquireError> {
        self.semaphore.acquire().await
    }

    fn retry_at(&self) -> Option<DateTime<Utc>> {
        *self.retry_at.lock().expect("Mutex shouldn't poison")
    }

    fn set_retry_at(&self, retry_at: DateTime<Utc>) {
        *self.retry_at.lock().expect("Mutex shouldn't poison") = Some(retry_at);
    }

    fn update_rate_limit(&self, headers: &reqwest::header::HeaderMap) {
        let remaining = headers
            .get("X-RateLimit-Remaining")
            .and_then(|remaining| remaining.to_str().ok())
            .and_then(|remaining| remaining.parse::<i64>().ok());
        let reset_after = headers
            .get("X-RateLimit-Reset-After")
            .and_then(|reset_after| reset_after.to_str().ok())
            .and_then(|reset_after| reset_after.parse::<f64>().ok())
            .unwrap_or(1.0);

        if remaining == Some(0) {
            tracing::warn!("Rate limit exceeded. Resetting in {} seconds.", reset_after);
            self.set_retry_at(
                Utc::now() + chrono::Duration::milliseconds((reset_after * 1000.0) as i64),
            );
        }
    }

    async fn except_error_response(
        &self,
        response: reqwest::Response,
    ) -> Result<reqwest::Response, DiscordError> {
        let status = response.status();
        if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
            let header_retry_after = response
                .headers()
                .get("Retry-After")
                .and_then(|h| h.to_str().ok())
                .and_then(|s| s.parse::<f64>().ok());

            let response_text = response.text().await.unwrap_or("Unknown error".to_string());

            let mut retry_after = header_retry_after.unwrap_or(5.0);
            let mut message = response_text.clone();

            if let Ok(parsed_data) = serde_json::from_str::<serde_json::Value>(&response_text) {
                if let Some(body_retry_after) = parsed_data["retry_after"].as_f64() {
                    retry_after = body_retry_after;
                }

                if let Some(body_message) = parsed_data["message"].as_str() {
                    message = body_message.to_string();
                }
            }

            self.set_retry_at(
                chrono::Utc::now() + chrono::Duration::milliseconds((retry_after * 1000.0) as i64),
            );
            return Err(DiscordError::RateLimited {
                message,
                retry_after,
            });
        } else if !status.is_success() {
            let error_data: serde_json::Value = response
                .json()
                .await
                .unwrap_or_else(|_| serde_json::json!({}));
            return Err(DiscordError::ApiError {
                status,
                message: error_data["message"]
                    .as_str()
                    .unwrap_or("Unknown error")
                    .to_string(),
            });
        }
        Ok(response)
    }

    fn error_on_locked(&self) -> Result<(), DiscordError> {
        let retry_at = self.retry_at();
        let now = chrono::Utc::now();
        if retry_at > Some(now) {
            tracing::warn!("Rate limited until: {}", retry_at.unwrap());
            Err(DiscordError::RateLimited {
                message: format!("Rate limited until: {}", retry_at.unwrap()),
                retry_after: (retry_at.unwrap() - now).num_seconds() as f64,
            })
        } else {
            Ok(())
        }
    }

    pub fn new(token: String, channel_id: i64, guild_id: i64) -> Self {
        Self {
            token,
            channel_id,
            guild_id,
            retry_at: Arc::new(Mutex::new(None)),
            semaphore: Arc::new(tokio::sync::Semaphore::new(5)),
            client: reqwest::Client::new(),
        }
    }

    pub async fn get_messages_in_thread(
        &self,
        thread_id: i64,
        last_message_id: Option<i64>,
    ) -> Result<Vec<DiscordMessage>, DiscordError> {
        let _permit = self.acquire().await.expect("Semaphore should never close");
        self.error_on_locked()?;

        let mut url = format!(
            "{}/channels/{}/messages",
            Self::DISCORD_API_BASE_URL,
            thread_id
        );

        if let Some(last_id) = last_message_id {
            url = format!("{}?after={}", url, last_id);
        }

        tracing::info!("Fetching messages in thread: {}", thread_id);

        let response = self
            .client
            .get(&url)
            .header("Authorization", format!("Bot {}", self.token))
            .send()
            .await
            .map_err(|e| DiscordError::ConnectionError(e.into()))?;

        self.update_rate_limit(response.headers());

        let status = response.status();
        let response = self.except_error_response(response).await?;

        let messages: Vec<DiscordMessage> =
            response.json().await.map_err(|e| DiscordError::ApiError {
                message: format!("Failed to parse messages: {}", e),
                status,
            })?;

        Ok(messages)
    }

    pub async fn send_attachment(
        &self,
        thread_id: i64,
        attachment: DiscordFile,
    ) -> Result<i64, DiscordError> {
        let _permit = self.acquire().await.expect("Semaphore should never close");
        self.error_on_locked()?;
        let url = format!(
            "{}/channels/{}/messages",
            Self::DISCORD_API_BASE_URL,
            thread_id
        );
        tracing::info!("Sending attachment to thread: {}", thread_id);

        let form = reqwest::multipart::Form::new().part(
            "files[0]",
            reqwest::multipart::Part::bytes(attachment.data)
                .file_name(attachment.name.clone())
                .mime_str(&attachment.content_type)
                .map_err(DiscordError::InvalidInput)?,
        );

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bot {}", self.token))
            .multipart(form)
            .send()
            .await
            .map_err(|e| DiscordError::ConnectionError(e.into()))?;

        self.update_rate_limit(response.headers());

        let response = self.except_error_response(response).await?;

        let response_data: IdResponse = response
            .json()
            .await
            .map_err(|e| DiscordError::ResponseError(e.into()))?;
        Ok(response_data.id)
    }

    pub async fn get_active_threads_updated_since(
        &self,
        latest_message_id: Option<i64>,
    ) -> Result<Vec<Thread>, DiscordError> {
        let _permit = self.acquire().await.expect("Semaphore should never close");
        self.error_on_locked()?;
        let url = format!(
            "{}/guilds/{}/threads/active",
            Self::DISCORD_API_BASE_URL,
            self.guild_id
        );
        tracing::info!(
            "Fetching active threads for guild-channel {}-{}",
            self.guild_id,
            self.channel_id
        );

        let response = self
            .client
            .get(&url)
            .header("Authorization", format!("Bot {}", self.token))
            .send()
            .await
            .map_err(|e| DiscordError::ConnectionError(e.into()))?;

        self.update_rate_limit(response.headers());

        let response = self.except_error_response(response).await?;

        let data: ThreadResponse = response
            .json()
            .await
            .map_err(|e| DiscordError::ResponseError(e.into()))?;

        let threads = data
            .threads
            .into_iter()
            .filter(|thread| {
                thread.parent_id == Some(self.channel_id)
                    && Some(thread.last_message_id) > latest_message_id
            })
            .collect();

        Ok(threads)
    }

    pub async fn send_message(&self, thread_id: i64, content: &str) -> Result<i64, DiscordError> {
        let _permit = self.acquire().await.expect("Semaphore should never close");
        self.error_on_locked()?;
        let url = format!(
            "{}/channels/{}/messages",
            Self::DISCORD_API_BASE_URL,
            thread_id
        );
        tracing::info!("Sending messages to thread: {}", thread_id);
        let body = serde_json::json!({
            "content": content,
        });

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bot {}", self.token))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| DiscordError::ConnectionError(e.into()))?;

        self.update_rate_limit(response.headers());

        let response = self.except_error_response(response).await?;

        let response_data: IdResponse = response
            .json()
            .await
            .map_err(|e| DiscordError::ResponseError(e.into()))?;
        Ok(response_data.id)
    }

    pub async fn create_thread(
        &self,
        title: &str,
        message: &str,
        auto_archive_duration: Option<i64>,
    ) -> Result<i64, DiscordError> {
        let _permit = self.acquire().await.expect("Semaphore should never close");
        self.error_on_locked()?;

        let url = format!(
            "{}/channels/{}/threads",
            Self::DISCORD_API_BASE_URL,
            self.channel_id
        );
        tracing::info!("Creating thread in channel: {}", self.channel_id);

        let body = serde_json::json!({
            "name": title,
            "auto_archive_duration": auto_archive_duration.unwrap_or(Self::DEFAULT_AUTO_ARCHIVE_DURATION),
            "message": {
                "content": message,
            }
        });

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bot {}", self.token))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| DiscordError::ConnectionError(e.into()))?;

        self.update_rate_limit(response.headers());

        let response = self.except_error_response(response).await?;

        let response_data: IdResponse = response
            .json()
            .await
            .map_err(|e| DiscordError::ResponseError(e.into()))?;
        Ok(response_data.id)
    }
}

mod types {
    use crate::utils::{i64_to_string, string_to_i64, string_to_i64_optional};
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Clone, Deserialize, Serialize)]
    pub struct DiscordMessage {
        #[serde(deserialize_with = "string_to_i64", serialize_with = "i64_to_string")]
        pub id: i64,
        pub content: String,
        pub author: DiscordAuthor,
        #[serde(rename = "type")]
        pub message_type: u16,
    }

    impl DiscordMessage {
        const ALLOWED_MESSAGE_TYPES: [u16; 4] = [0, 19, 20, 21];

        pub fn author_id(&self) -> i64 {
            self.author.id
        }

        pub fn is_hidden(&self) -> bool {
            !Self::ALLOWED_MESSAGE_TYPES.contains(&self.message_type)
                || self.content.is_empty()
                || self.content.starts_with("!HiddenMessage")
                || self.content.starts_with(":ninja:")
        }

        pub fn suppress_notification(&self) -> bool {
            self.content.starts_with(":cold:")
        }
        pub fn normalize(mut self) -> DiscordMessage {
            self.content = self.content.trim_start_matches(":cold:").to_string();

            self
        }
    }

    #[derive(Debug, Clone, Deserialize, Serialize)]
    pub struct DiscordAuthor {
        #[serde(deserialize_with = "string_to_i64", serialize_with = "i64_to_string")]
        pub id: i64,
        pub username: String,
        pub discriminator: String,
    }

    pub struct DiscordFile {
        pub name: String,
        pub content_type: String,
        pub data: Vec<u8>,
    }

    #[derive(Debug, Clone, Deserialize)]
    pub struct Thread {
        #[serde(deserialize_with = "string_to_i64")]
        pub id: i64,
        #[serde(default, deserialize_with = "string_to_i64_optional")]
        pub parent_id: Option<i64>,
        pub name: String,
        #[serde(deserialize_with = "string_to_i64")]
        pub last_message_id: i64,
    }

    #[derive(Debug, Clone, Deserialize, Serialize)]
    pub struct ApiError {
        pub code: u16,
        pub message: String,
    }
    #[derive(Deserialize)]
    pub struct IdResponse {
        #[serde(deserialize_with = "string_to_i64")]
        pub id: i64,
    }

    #[derive(Deserialize)]
    pub struct ThreadResponse {
        pub threads: Vec<Thread>,
    }
}
