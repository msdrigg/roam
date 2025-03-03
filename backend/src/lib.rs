use std::sync::Arc;

use anyhow::Context;
use apns::ApnsClient;
use database::{DatabaseClient, DeviceInfo, User, UserUpdate};
use discord::{DiscordClient, DiscordMessage};
use presence::{PresenceClient, UserPresenceInfo};
use server::ApiError;

pub mod apns;
pub mod cli;
pub mod database;
pub mod discord;
pub mod gateway;
pub mod logging;
pub mod presence;
pub mod server;
pub mod tasks;
mod utils;

pub type UserId = String;

#[derive(Clone)]
pub struct AppContext {
    db_client: DatabaseClient,
    presence_info: PresenceClient,
    discord_client: DiscordClient,
    apns_client: ApnsClient,
    user_create_lock: Arc<tokio::sync::Mutex<()>>,
    discord_token: String,
    discord_bot_id: i64,
    backend_url: String,
    apns_disabled: bool,
    backend_api_key: String,
    port: u16,
}

impl AppContext {
    pub async fn new(cli: cli::RoamCli) -> anyhow::Result<Self> {
        let db_client = DatabaseClient::new(&cli)
            .await
            .context("Error creating database client")?;

        let discord_client = DiscordClient::new(
            cli.discord_token.clone(),
            cli.discord_help_channel,
            cli.discord_guild_id,
        );
        let apns_client = ApnsClient::new(
            cli.apns_key_id,
            cli.apns_team_id,
            cli.apns_bundle_id,
            cli.apns_private_key,
        )
        .context("Error creating APNS client")?;

        Ok(Self {
            db_client,
            discord_client,
            apns_client,
            discord_bot_id: cli.discord_bot_id,
            discord_token: cli.discord_token,
            backend_url: cli.backend_url,
            backend_api_key: cli.backend_api_key,
            user_create_lock: Arc::new(tokio::sync::Mutex::new(())),
            presence_info: Default::default(),
            port: cli.port,
            apns_disabled: cli.apns_disabled,
        })
    }

    pub fn db_client(&self) -> &DatabaseClient {
        &self.db_client
    }

    pub fn discord_client(&self) -> &DiscordClient {
        &self.discord_client
    }

    pub fn apns_client(&self) -> &ApnsClient {
        &self.apns_client
    }

    pub fn discord_token(&self) -> &str {
        &self.discord_token
    }

    pub fn discord_bot_id(&self) -> i64 {
        self.discord_bot_id
    }

    pub fn backend_url(&self) -> &str {
        &self.backend_url
    }

    pub fn backend_api_key(&self) -> &str {
        &self.backend_api_key
    }

    async fn presence_info(&self, device_id: &UserId) -> UserPresenceInfo {
        self.presence_info.get_user_presence_info(device_id).await
    }
}

impl AppContext {
    async fn send_pushes(&self) -> anyhow::Result<()> {
        if self.apns_disabled {
            return Ok(());
        }
        tracing::info!("Sending pushes");
        let last_alerted_message = self
            .db_client
            .get_last_alerted_message()
            .await?
            .context("Error getting last alerted message")?;
        let threads = self
            .discord_client
            .get_active_threads_updated_since(Some(last_alerted_message))
            .await
            .context("Error getting active threads")?;

        let max_alerted_message = threads
            .iter()
            .map(|thread| thread.last_message_id)
            .max()
            .unwrap_or(last_alerted_message)
            .max(last_alerted_message);

        self.db_client
            .set_last_alerted_message(max_alerted_message)
            .await
            .context("Error setting last alerted message")?;

        tracing::info!(
            "Found {} active threads since {}. Last Message Ids: {:?}",
            threads.len(),
            last_alerted_message,
            threads
                .iter()
                .map(|thread| &thread.last_message_id)
                .collect::<Vec<_>>()
        );

        for thread in threads {
            let user = self
                .db_client
                .get_user_with_thread(thread.id)
                .await
                .context("Error getting user")?;
            let Some(user) = user else {
                tracing::warn!("No user found for thread {}", thread.id);
                continue;
            };
            let messages = self
                .discord_client
                .get_messages_in_thread(thread.id, Some(last_alerted_message))
                .await
                .context("Error getting messages in thread for user")?;

            tracing::info!(
                "Found {} notifiable messages in thread {} since {}. Last Message Ids: {:?}",
                messages.len(),
                thread.id,
                last_alerted_message,
                messages
                    .iter()
                    .map(|message| &message.id)
                    .collect::<Vec<_>>()
            );

            let Some(apns_token) = user.apns_token.as_ref() else {
                tracing::info!("No APNS token found for user {}", user.device_id);
                continue;
            };

            self.apns_client
                .send_background_push_notification(apns_token, "CHECK_MESSAGES")
                .await?;

            for message in messages.into_iter().filter(|message| !message.is_hidden()) {
                if let Err(err) = self.notify_user(&user, message).await {
                    tracing::warn!("Error sending apple alerts: {:?}", err);
                }
            }
        }

        Ok(())
    }

    async fn notify_self_typing(&self, user: &User) -> anyhow::Result<()> {
        self.presence_info
            .notify_self_typing(user.device_id.clone())
            .await?;
        Ok(())
    }

    async fn notify_support_typing(&self, user: &User) -> anyhow::Result<()> {
        self.presence_info
            .notify_support_typing(user.device_id.clone())
            .await;
        if let Some(apns_token) = user.apns_token.as_ref() {
            if let Err(err) = self
                .apns_client
                .send_background_push_notification(apns_token, "TYPING_ALERT")
                .await
            {
                self.handle_apns_error(&err, user).await?;
                return Err(err.into());
            }
        } else {
            tracing::info!("No APNS token found for user {}", user.device_id);
        }
        Ok(())
    }

    async fn notify_user(&self, user: &User, message: DiscordMessage) -> anyhow::Result<()> {
        if self.apns_disabled {
            return Ok(());
        }
        let apns_token = user
            .apns_token
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("No APNS token found for user {}", user.device_id))?;
        if message.author.id == self.discord_bot_id
            || message.suppress_notification()
            || message.is_hidden()
        {
            tracing::info!(
                "Skipping foreground push notification for message: {}",
                message.content,
            );
            return Ok(());
        } else {
            tracing::info!(
                "Sending foreground push notification for message: {} to {}",
                message.content,
                apns_token
            );
        }

        tracing::info!(
            "Sending foreground push notification for message: {} to {}",
            message.content,
            apns_token
        );

        if let Err(err) = self
            .apns_client
            .send_push_notification(
                apns_token,
                "Message from roam",
                &message.normalize().content,
            )
            .await
        {
            tracing::error!("Error sending push notification: {:?}", err);
            self.handle_apns_error(&err, user).await?;
        } else {
            tracing::info!("Push notification sent successfully");
        }
        Ok(())
    }
    async fn handle_apns_error(&self, err: &apns::ApnsError, user: &User) -> anyhow::Result<()> {
        if matches!(
            err.a2_reason(),
            Some(
                a2::ErrorReason::Unregistered
                    | a2::ErrorReason::BadDeviceToken
                    | a2::ErrorReason::DeviceTokenNotForTopic
            )
        ) {
            self.db_client.clear_user_apns(&user.device_id).await?;
        }
        Ok(())
    }

    async fn refresh_user(
        &self,
        mut user: database::User,
        apns_token: Option<&String>,
        installation_info: &Option<DeviceInfo>,
    ) -> Result<database::User, ApiError> {
        let old_apns_token = user.apns_token.clone();
        let old_installation_info = user.device_info.clone().map(|it| it.0);
        if (apns_token.is_some() && apns_token != old_apns_token.as_ref())
            || (installation_info != &old_installation_info && installation_info.is_some())
        {
            user = self
                .db_client()
                .update_user(
                    &user.device_id,
                    &UserUpdate {
                        apns_token: apns_token.cloned(),
                        device_info: installation_info.clone(),
                        ..Default::default()
                    },
                )
                .await
                .map_err(ApiError::DatabaseError)?;

            self.send_device_info(&user).await?;
        }

        Ok(user)
    }

    async fn send_device_info(&self, user: &User) -> Result<(), ApiError> {
        let Some(device_info) = &user.device_info.as_ref() else {
            return Ok(());
        };

        tracing::info!("Updating device info for user {}", user.device_id);

        let DeviceInfo {
            user_id,
            build_version,
            os_platform,
            os_version,
            user_locale,
        } = &device_info.0;
        // let message = `:ninja:\n\n### Device info\n\n- **User ID**: ${userId}\n- **Build version**: ${buildVersion}\n- **OS platform**: ${osPlatform}\n- **OS version**: ${osVersion}\n- **User Locale**: ${userLocale}`;
        let message = format!(
            ":ninja:\n\n### Device info\n\n- **User ID**: {}\n- **Build version**: {}\n- **OS platform**: {}\n- **OS version**: {}\n- **User Locale**: {}\n- **APNS Token**: {}",
            user_id.as_deref().unwrap_or("--"),
            build_version.as_deref().unwrap_or("--"),
            os_platform.as_deref().unwrap_or("--"),
            os_version.as_deref().unwrap_or("--"),
            user_locale.as_deref().unwrap_or("--"),
            user.apns_token.as_deref().unwrap_or("--"),
        );
        self.discord_client()
            .send_message_multiple_attachments(user.thread_id, &message, vec![], None)
            .await
            .map_err(ApiError::DiscordError)?;
        Ok(())
    }

    async fn get_or_create_user(
        &self,
        device_id: &UserId,
        seed: &UserUpdate,
    ) -> Result<User, ApiError> {
        // We need to serialize all of these requests so they need to be done with the writer queue
        let _guard = self.user_create_lock.lock().await;
        if let Some(user) = self
            .db_client()
            .get_user_with_id(device_id)
            .await
            .map_err(ApiError::DatabaseError)?
        {
            return Ok(user);
        }

        let thread_id = self
            .discord_client()
            .create_thread(&format!("New message from {device_id}"), ":ninja:", None)
            .await
            .map_err(ApiError::DiscordError)?;

        let user = User {
            device_id: device_id.to_string(),
            thread_id,
            apns_token: seed.apns_token.clone(),
            device_info: seed.device_info.clone().map(sqlx::types::Json),
        };

        self.send_device_info(&user).await?;

        self.db_client()
            .create_user(&user)
            .await
            .map_err(ApiError::DatabaseError)?;

        Ok(user)
    }
}
