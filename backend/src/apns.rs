use std::io::Cursor;

use a2::{ClientConfig, ErrorBody, ErrorReason, NotificationBuilder, NotificationOptions};
use anyhow::Context;
use base64::{prelude::BASE64_STANDARD_NO_PAD, Engine};

#[derive(Debug, Clone)]
pub struct ApnsClient {
    client: a2::Client,
    topic: String,
}

#[derive(Debug, thiserror::Error)]
pub enum ApnsError {
    #[error("Failed to send push notification: {:?}", 0)]
    SendFailed(ErrorBody),
    #[error("Failed to connect to APNS: {0}")]
    ConnectionFailed(#[from] a2::Error),
}

impl ApnsError {
    pub fn a2_reason(&self) -> Option<&ErrorReason> {
        match self {
            Self::SendFailed(err) => Some(&err.reason),
            Self::ConnectionFailed(a2::Error::ResponseError(resp)) => {
                resp.error.as_ref().map(|e| &e.reason)
            }
            _ => None,
        }
    }
}

impl ApnsClient {
    pub fn new(
        key_id: String,
        team_id: String,
        bundle_id: String,
        private_key: String,
    ) -> Result<Self, anyhow::Error> {
        let pkey_bytes = BASE64_STANDARD_NO_PAD
            .decode(private_key)
            .context("Failed to decode private key")?;
        let client = a2::Client::token(
            Cursor::new(pkey_bytes),
            key_id,
            team_id,
            ClientConfig::default(),
        )
        .context("Failed to create APNS client")?;
        Ok(Self {
            client,
            topic: bundle_id,
        })
    }

    pub async fn send_push_notification(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
    ) -> Result<(), ApnsError> {
        let opt = NotificationOptions {
            apns_id: None,
            apns_expiration: None,
            apns_collapse_id: None,
            apns_priority: Some(a2::Priority::Normal),
            apns_topic: Some(&self.topic),
            apns_push_type: None,
        };
        let notification_payload = a2::DefaultNotificationBuilder::new()
            .set_category("DEVELOPER_RESPONSE")
            .set_sound("default")
            .set_title(title)
            .set_body(body)
            .build(device_token, opt);

        let result = self.client.send(notification_payload).await?;
        if let Some(err) = result.error {
            tracing::error!("Failed to send foreground push notification: {:?}", err);

            Err(ApnsError::SendFailed(err))
        } else {
            tracing::info!("Push notification sent successfully!");
            Ok(())
        }
    }

    pub async fn send_background_push_notification(
        &self,
        device_token: &str,
        message: &str,
    ) -> Result<(), ApnsError> {
        let opt = NotificationOptions {
            apns_id: None,
            apns_expiration: None,
            apns_collapse_id: None,
            apns_priority: Some(a2::Priority::High),
            apns_topic: Some(&self.topic),
            apns_push_type: Some(a2::PushType::Background),
        };
        let notification_payload = a2::DefaultNotificationBuilder::new()
            .set_content_available()
            .set_body(message)
            .build(device_token, opt);

        let result = self.client.send(notification_payload).await?;
        if let Some(err) = result.error {
            tracing::error!("Failed to send background push notification: {:?}", err);
            Err(ApnsError::SendFailed(err))
        } else {
            tracing::info!("Background push notification sent successfully!");
            Ok(())
        }
    }
}
