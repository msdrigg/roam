use std::sync::{Arc, Mutex};

use crate::utils::{serialize_anyhow, serialize_reqwest, serialize_status_code};
use chrono::{DateTime, Utc};
use reqwest::{Response, StatusCode};
use serde::{Deserialize, Serialize};
use tokio::sync::AcquireError;
use types::{IdResponse, ThreadResponse};

pub use types::{
    DiscordAuthor, DiscordFile, DiscordFileUpload, DiscordMessage, MessageAttachment, Thread,
};

#[derive(Debug, Deserialize)]
struct CurrentApplicationResponse {
    id: String,
}

#[derive(Debug, Clone)]
pub struct DiscordClient {
    token: String,
    channel_id: i64,
    guild_id: i64,
    retry_at: Arc<Mutex<Option<DateTime<Utc>>>>,
    client: reqwest::Client,
    semaphore: Arc<tokio::sync::Semaphore>,
}

pub struct DiscordMessageOptions {
    pub nonce: Option<String>,
    pub notify: bool,
}

impl Default for DiscordMessageOptions {
    fn default() -> Self {
        Self {
            nonce: Default::default(),
            notify: true,
        }
    }
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
    InvalidInputResponse(#[serde(serialize_with = "serialize_reqwest")] reqwest::Error),
    #[error("Invalid input: {0}")]
    InvalidInput(String),
}

impl DiscordClient {
    const DISCORD_API_BASE_URL: &str = "https://discord.com/api/v10";
    const DEFAULT_AUTO_ARCHIVE_DURATION: i64 = 10080;
    const DISCORD_CONCURRENT_REQUESTS: usize = 3;
    const DISCORD_NONCE_MAX_LENGTH: usize = 25;

    fn get_flags(options: Option<&DiscordMessageOptions>) -> u32 {
        let notify = options.map(|o| o.notify).unwrap_or(true);
        let mut flags: u32 = 0;

        // Set SUPPRESS_NOTIFICATIONS flag (1 << 12) if notify is false
        if !notify {
            flags |= 1 << 12;
        }

        flags
    }

    fn normalize_nonce(nonce: &str) -> String {
        if nonce.len() <= Self::DISCORD_NONCE_MAX_LENGTH {
            return nonce.to_string();
        }

        let compact: String = nonce
            .chars()
            .filter(|c| c.is_ascii_alphanumeric())
            .take(Self::DISCORD_NONCE_MAX_LENGTH)
            .collect();

        if compact.is_empty() {
            "0".to_string()
        } else {
            compact
        }
    }

    fn normalize_options(options: Option<&DiscordMessageOptions>) -> Option<DiscordMessageOptions> {
        options.map(|options| DiscordMessageOptions {
            nonce: options.nonce.as_deref().map(Self::normalize_nonce),
            notify: options.notify,
        })
    }

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
        message: &str,
    ) -> Result<reqwest::Response, DiscordError> {
        let status = response.status();
        if status == reqwest::StatusCode::TOO_MANY_REQUESTS {
            tracing::info!(?message, "Discord rate limited");
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
            tracing::info!(?message, ?status, ?error_data, "Discord errored");
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
            semaphore: Arc::new(tokio::sync::Semaphore::new(
                Self::DISCORD_CONCURRENT_REQUESTS,
            )),
            client: reqwest::Client::new(),
        }
    }

    pub async fn register_guild_translate_command(&self) -> Result<(), DiscordError> {
        let _permit = self.acquire().await.expect("Semaphore should never close");
        self.error_on_locked()?;

        let application_url = format!("{}/oauth2/applications/@me", Self::DISCORD_API_BASE_URL);
        let response = self
            .client
            .get(&application_url)
            .header("Authorization", format!("Bot {}", self.token))
            .send()
            .await
            .map_err(|e| DiscordError::ConnectionError(e.into()))?;
        self.update_rate_limit(response.headers());

        let status = response.status();
        let response = self
            .except_error_response(response, "getting current application")
            .await?;
        let application: CurrentApplicationResponse =
            response.json().await.map_err(|e| DiscordError::ApiError {
                message: format!("Failed to parse current application: {e}"),
                status,
            })?;

        let command_url = format!(
            "{}/applications/{}/guilds/{}/commands",
            Self::DISCORD_API_BASE_URL,
            application.id,
            self.guild_id
        );
        let body = serde_json::json!({
            "name": "translate",
            "type": 1,
            "description": "Translate a support reply to the user's language",
            "options": [{
                "type": 3,
                "name": "text",
                "description": "Support message to translate",
                "required": true
            }]
        });

        let response = self
            .client
            .post(&command_url)
            .header("Authorization", format!("Bot {}", self.token))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| DiscordError::ConnectionError(e.into()))?;
        self.update_rate_limit(response.headers());
        self.except_error_response(response, "registering translate command")
            .await?;
        tracing::info!(
            guild_id = self.guild_id,
            "Registered AI responder /translate guild command"
        );

        Ok(())
    }

    pub async fn get_messages_in_thread(
        &self,
        thread_id: i64,
        last_message_id: Option<i64>,
    ) -> Result<Vec<DiscordMessage>, DiscordError> {
        self.get_messages_in_thread_with_limit(thread_id, last_message_id, None)
            .await
    }

    pub async fn get_recent_messages_in_thread(
        &self,
        thread_id: i64,
        limit: u8,
    ) -> Result<Vec<DiscordMessage>, DiscordError> {
        self.get_messages_in_thread_with_limit(thread_id, None, Some(limit))
            .await
    }

    async fn get_messages_in_thread_with_limit(
        &self,
        thread_id: i64,
        last_message_id: Option<i64>,
        limit: Option<u8>,
    ) -> Result<Vec<DiscordMessage>, DiscordError> {
        let _permit = self.acquire().await.expect("Semaphore should never close");
        self.error_on_locked()?;

        let mut url = format!(
            "{}/channels/{}/messages",
            Self::DISCORD_API_BASE_URL,
            thread_id
        );

        let mut query = Vec::new();
        if let Some(last_id) = last_message_id {
            query.push(format!("after={last_id}"));
        }
        if let Some(limit) = limit {
            query.push(format!("limit={}", limit.clamp(1, 100)));
        }
        if !query.is_empty() {
            url = format!("{url}?{}", query.join("&"));
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
        let response = self
            .except_error_response(response, "Getting messages")
            .await?;

        let messages: Vec<DiscordMessage> =
            response.json().await.map_err(|e| DiscordError::ApiError {
                message: format!("Failed to parse messages: {e}"),
                status,
            })?;

        Ok(messages)
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

        let response = self
            .except_error_response(response, "getting active threads")
            .await?;

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

    async fn _send_message_no_attachments(
        &self,
        thread_id: i64,
        content: &str,
        options: Option<&DiscordMessageOptions>,
    ) -> Result<reqwest::Response, DiscordError> {
        let nonce = options.and_then(|o| o.nonce.as_deref());
        let _permit = self.acquire().await.expect("Semaphore should never close");
        self.error_on_locked()?;
        let url = format!(
            "{}/channels/{}/messages",
            Self::DISCORD_API_BASE_URL,
            thread_id
        );
        tracing::info!("Sending message \"{}\" to thread {}", content, thread_id);
        let body = serde_json::json!({
            "content": content,
            "nonce": nonce,
            "enforce_nonce": true,
            "flags": Self::get_flags(options)
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
        Ok(response)
    }

    async fn _send_message_multipart(
        &self,
        thread_id: i64,
        content: Option<&str>,
        attachments: &[&DiscordFileUpload],
        options: Option<&DiscordMessageOptions>,
    ) -> Result<reqwest::Response, DiscordError> {
        let nonce = options.and_then(|o| o.nonce.as_deref());
        let _permit = self.acquire().await.expect("Semaphore should never close");
        self.error_on_locked()?;
        let url = format!(
            "{}/channels/{}/messages",
            Self::DISCORD_API_BASE_URL,
            thread_id
        );
        tracing::info!(
            "Sending attachments {:?} to thread: {}",
            attachments,
            thread_id
        );

        let mut form = reqwest::multipart::Form::new();

        let content = content.unwrap_or_default();
        if !content.is_empty() {
            form = form.text("content", content.to_string());
        }
        if let Some(nonce) = nonce {
            form = form.text("nonce", nonce.to_string());
        }

        for (n, attachment) in attachments.iter().enumerate() {
            form = form.part(
                format!("files[{n}]"),
                reqwest::multipart::Part::bytes(attachment.data.clone())
                    .file_name(attachment.filename.clone())
                    .mime_str(&attachment.content_type)
                    .map_err(DiscordError::InvalidInputResponse)?,
            );
        }

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bot {}", self.token))
            .multipart(form)
            .send()
            .await
            .map_err(|e| DiscordError::ConnectionError(e.into()))?;

        Ok(response)
    }

    pub async fn send_typing(&self, thread_id: i64) -> Result<(), DiscordError> {
        let _permit = self.acquire().await.expect("Semaphore should never close");
        self.error_on_locked()?;

        let url = format!(
            "{}/channels/{}/typing",
            Self::DISCORD_API_BASE_URL,
            thread_id
        );
        tracing::info!("Sending typing indicator to thread {}", thread_id);

        let response = self
            .client
            .post(&url)
            .header("Authorization", format!("Bot {}", self.token))
            .header("Content-Type", "application/json")
            .send()
            .await
            .map_err(|e| DiscordError::ConnectionError(e.into()))?;

        self.update_rate_limit(response.headers());

        let _ = self
            .except_error_response(response, "sending typing indicator")
            .await?;

        Ok(())
    }

    pub async fn join_thread(&self, thread_id: i64) -> Result<(), DiscordError> {
        let _permit = self.acquire().await.expect("Semaphore should never close");
        self.error_on_locked()?;

        let url = format!(
            "{}/channels/{}/thread-members/@me",
            Self::DISCORD_API_BASE_URL,
            thread_id
        );
        tracing::info!("Joining thread {}", thread_id);

        let response = self
            .client
            .put(&url)
            .header("Authorization", format!("Bot {}", self.token))
            .send()
            .await
            .map_err(|e| DiscordError::ConnectionError(e.into()))?;

        self.update_rate_limit(response.headers());

        let _ = self
            .except_error_response(response, "joining thread")
            .await?;

        Ok(())
    }

    pub async fn update_thread_name(&self, thread_id: i64, name: &str) -> Result<(), DiscordError> {
        let _permit = self.acquire().await.expect("Semaphore should never close");
        self.error_on_locked()?;

        let url = format!("{}/channels/{}", Self::DISCORD_API_BASE_URL, thread_id);
        tracing::info!(thread_id, name, "Updating Discord thread name");
        let body = serde_json::json!({ "name": name });

        let response = self
            .client
            .patch(&url)
            .header("Authorization", format!("Bot {}", self.token))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| DiscordError::ConnectionError(e.into()))?;

        self.update_rate_limit(response.headers());

        let _ = self
            .except_error_response(response, "updating thread name")
            .await?;

        Ok(())
    }

    pub async fn send_message(
        &self,
        thread_id: i64,
        content: &str,
        attachment: Option<DiscordFileUpload>,
        options: Option<&DiscordMessageOptions>,
    ) -> Result<DiscordMessage, DiscordError> {
        let normalized_options = Self::normalize_options(options);
        let options = normalized_options.as_ref();

        if let Some(nonce) = options.and_then(|o| o.nonce.as_deref()) {
            if nonce.len() > 25 {
                return Err(DiscordError::InvalidInput(
                    "Nonce must be at most 25 characters".to_string(),
                ));
            }
        }

        let handle_response = |response: Response| async {
            self.update_rate_limit(response.headers());

            let response = self
                .except_error_response(response, "sending message")
                .await?;

            let result: DiscordMessage = response
                .json()
                .await
                .map_err(|e| DiscordError::ResponseError(e.into()))?;

            tracing::info!("Sending message succeeded");
            Ok(result)
        };

        let result = if let Some(attachment) = attachment {
            for paired_message in attachment.paired_messages.iter() {
                let response = self
                    ._send_message_no_attachments(thread_id, paired_message, None)
                    .await?;
                handle_response(response).await?;
            }

            // Split off first attachment
            let response = self
                ._send_message_multipart(thread_id, Some(content), &[&attachment], options)
                .await?;

            handle_response(response).await?
        } else {
            let response = self
                ._send_message_no_attachments(thread_id, content, options)
                .await?;
            handle_response(response).await?
        };

        tracing::info!("Sending message succeeded");

        Ok(result)
    }

    pub async fn send_message_multiple_attachments(
        &self,
        thread_id: i64,
        content: &str,
        attachments: Vec<DiscordFileUpload>,
        options: Option<&DiscordMessageOptions>,
    ) -> Result<(), DiscordError> {
        let normalized_options = Self::normalize_options(options);
        let options = normalized_options.as_ref();
        let nonce = options.and_then(|o| o.nonce.as_deref());
        if let Some(nonce) = nonce {
            if nonce.len() > 25 {
                return Err(DiscordError::InvalidInput(
                    "Nonce must be at most 25 characters".to_string(),
                ));
            }
        }

        let handle_response = |response: Response| async {
            self.update_rate_limit(response.headers());

            let response = self
                .except_error_response(response, "sending message")
                .await?;

            let _response_data: IdResponse = response
                .json()
                .await
                .map_err(|e| DiscordError::ResponseError(e.into()))?;

            tracing::info!("Sending message succeeded");
            Ok(())
        };

        if let Some((first, rest)) = attachments.split_first() {
            for attachment in attachments.iter() {
                for paired_message in attachment.paired_messages.iter() {
                    let response = self
                        ._send_message_no_attachments(thread_id, paired_message, None)
                        .await?;
                    handle_response(response).await?;
                }
            }

            // Split off first attachment
            let response = self
                ._send_message_multipart(thread_id, Some(content), &[first], options)
                .await?;

            handle_response(response).await?;
            for attachment in rest {
                let response = self
                    ._send_message_multipart(thread_id, None, &[attachment], options)
                    .await?;
                handle_response(response).await?;
            }
        } else {
            let response = self
                ._send_message_no_attachments(thread_id, content, options)
                .await?;
            handle_response(response).await?;
        }

        tracing::info!("Sending message succeeded");
        Ok(())
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
        tracing::info!(
            "Creating thread in channel {} with message {}",
            self.channel_id,
            message
        );

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

        let response = self
            .except_error_response(response, "creating thread")
            .await?;

        let response_data: IdResponse = response
            .json()
            .await
            .map_err(|e| DiscordError::ResponseError(e.into()))?;
        Ok(response_data.id)
    }
}

mod types {
    use crate::utils::{
        base64_data_de, base64_data_ser, i64_to_string, string_to_i64, string_to_i64_optional,
    };
    use regex::Regex;
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Clone, Deserialize, Serialize)]
    pub struct DiscordMessage {
        #[serde(deserialize_with = "string_to_i64", serialize_with = "i64_to_string")]
        pub id: i64,
        pub nonce: Option<String>,
        pub content: String,
        pub author: DiscordAuthor,
        #[serde(rename = "type")]
        pub message_type: u8,
        pub attachments: Vec<MessageAttachment>,
    }

    #[derive(Debug, Clone, Deserialize, Serialize)]
    pub struct MessageAttachment {
        #[serde(deserialize_with = "string_to_i64", serialize_with = "i64_to_string")]
        pub id: i64,
        pub filename: String,
        pub content_type: Option<String>,
        pub url: String,
    }

    impl DiscordMessage {
        const ALLOWED_MESSAGE_TYPES: [u8; 4] = [0, 19, 20, 21];

        pub fn new(
            id: i64,
            content: String,
            author_id: i64,
            message_type: u8,
            attachments: Vec<MessageAttachment>,
            nonce: Option<String>,
        ) -> Self {
            Self {
                id,
                content,
                nonce,
                author: DiscordAuthor { id: author_id },
                message_type,
                attachments,
            }
        }

        pub fn author_id(&self) -> i64 {
            self.author.id
        }

        pub fn is_hidden(&self) -> bool {
            !Self::ALLOWED_MESSAGE_TYPES.contains(&self.message_type)
                || (self.content.is_empty() && self.attachments.is_empty())
                || self.content.starts_with("!HiddenMessage")
                || self.content.starts_with(":ninja:")
                || self.is_translate_command()
        }

        pub fn suppress_notification(&self) -> bool {
            self.content.starts_with(":cold:")
        }

        fn is_translate_command(&self) -> bool {
            let content = self.content.trim_start();
            if content.starts_with(":translate:")
                || content == "/translate"
                || content.starts_with("/translate ")
            {
                return true;
            }

            Regex::new(r"^<@!?\d+>\s*(:translate:|/translate)(\s|$)")
                .unwrap()
                .is_match(content)
        }

        pub fn normalize(mut self) -> DiscordMessage {
            let re = Regex::new(r":[a-zA-Z_]+:").unwrap();
            self.content = re
                .replace_all(&self.content, |caps: &regex::Captures| {
                    caps[0].replace('_', "-")
                })
                .trim_start_matches(":cold:")
                .trim()
                .to_string();

            self
        }
    }

    #[derive(Debug, Clone, Deserialize, Serialize)]
    pub struct DiscordAuthor {
        #[serde(deserialize_with = "string_to_i64", serialize_with = "i64_to_string")]
        pub id: i64,
    }

    #[derive(Deserialize)]
    pub struct DiscordFileUpload {
        pub filename: String,
        pub content_type: String,
        #[serde(
            deserialize_with = "base64_data_de",
            serialize_with = "base64_data_ser"
        )]
        pub data: Vec<u8>,
        #[serde(default)]
        pub paired_messages: Vec<String>,
    }

    impl std::fmt::Debug for DiscordFileUpload {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            f.debug_struct("DiscordFileUpload")
                .field("filename", &self.filename)
                .field("content_type", &self.content_type)
                .field("data", &format!("{} bytes", self.data.len()))
                .field("paired_messages", &self.paired_messages)
                .finish()
        }
    }

    #[derive(Deserialize, Serialize)]
    pub struct DiscordFile {
        #[serde(
            deserialize_with = "string_to_i64",
            serialize_with = "i64_to_string",
            default
        )]
        pub id: i64,
        pub filename: String,
        pub content_type: String,
        #[serde(
            deserialize_with = "base64_data_de",
            serialize_with = "base64_data_ser"
        )]
        pub data: Vec<u8>,
    }

    impl std::fmt::Debug for DiscordFile {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            f.debug_struct("DiscordFile")
                .field("name", &self.filename)
                .field("id", &self.id)
                .field("content_type", &self.content_type)
                .field("data", &self.data.len())
                .finish()
        }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_nonce_to_discord_limit() {
        assert_eq!(
            DiscordClient::normalize_nonce("550E8400-E29B-41D4-A716-446655440000"),
            "550E8400E29B41D4A71644665"
        );
        assert_eq!(DiscordClient::normalize_nonce("short-nonce"), "short-nonce");
        assert_eq!(
            DiscordClient::normalize_nonce("--------------------------"),
            "0"
        );
    }

    #[test]
    fn test_discord_message_normalization() {
        let message = DiscordMessage {
            id: 1,
            content: ":cold: Hello :ninja: World! :smile:".to_string(),
            nonce: None,
            author: DiscordAuthor { id: 2 },
            message_type: 0,
            attachments: vec![],
        };
        let normalized = message.normalize();
        assert_eq!(normalized.content, "Hello :ninja: World! :smile:");
        assert!(!normalized.suppress_notification());
        assert!(!normalized.is_hidden());
        assert_eq!(normalized.author_id(), 2);
        assert_eq!(normalized.message_type, 0);

        // Now test command underscore to hyphen transformation
        let message_with_command = DiscordMessage {
            id: 2,
            content: ":cold: This is a test :word_with_underscores: message".to_string(),
            nonce: None,
            author: DiscordAuthor { id: 3 },
            message_type: 0,
            attachments: vec![],
        };
        let normalized = message_with_command.normalize();
        assert_eq!(
            normalized.content,
            "This is a test :word-with-underscores: message",
        );
        assert!(!normalized.suppress_notification());
        assert!(!normalized.is_hidden());
        assert_eq!(normalized.author_id(), 3);
        assert_eq!(normalized.message_type, 0);
    }

    #[test]
    fn translate_commands_are_hidden() {
        let messages = [
            DiscordMessage {
                id: 1,
                content: ":translate: Please try again".to_string(),
                nonce: None,
                author: DiscordAuthor { id: 2 },
                message_type: 0,
                attachments: vec![],
            },
            DiscordMessage {
                id: 2,
                content: "<@123> :translate: Please try again".to_string(),
                nonce: None,
                author: DiscordAuthor { id: 2 },
                message_type: 0,
                attachments: vec![],
            },
            DiscordMessage {
                id: 3,
                content: "/translate Please try again".to_string(),
                nonce: None,
                author: DiscordAuthor { id: 2 },
                message_type: 0,
                attachments: vec![],
            },
        ];

        assert!(messages.iter().all(DiscordMessage::is_hidden));
    }
}
