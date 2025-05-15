use std::{path::PathBuf, str::FromStr};

use crate::{utils::i64_to_string, UserId};
use anyhow::Context;
use sqlx::{
    sqlite::{SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions},
    types::Json,
};
use tokio::fs::create_dir_all;

use crate::cli::RoamCli;

#[derive(Debug, Clone)]
pub struct DatabaseClient {
    pub reader_pool: sqlx::SqlitePool,
    pub writer_pool: sqlx::SqlitePool,
}

impl DatabaseClient {
    pub async fn new(cli: &RoamCli) -> Result<Self, anyhow::Error> {
        // Create data directory if not exists
        create_dir_all(&cli.data_dir)
            .await
            .context("Failed to create data directory")?;

        let db_path = PathBuf::from(cli.data_dir.clone())
            .join("cloud-backend.db")
            .to_string_lossy()
            .to_string();

        let connection_opts = SqliteConnectOptions::from_str(&db_path)
            .context("Error parsing database url")?
            .create_if_missing(true)
            .journal_mode(SqliteJournalMode::Wal);

        tracing::info!("Connecting to database");
        // Get self
        let reader_pool = SqlitePoolOptions::new()
            .max_connections(10)
            .min_connections(10)
            .connect_with(connection_opts.clone())
            .await
            .context("Error creating SqlitePool reader")?;
        let writer_pool = SqlitePoolOptions::new()
            .max_connections(1)
            .min_connections(1)
            .connect_with(connection_opts)
            .await
            .context("Error creating SqlitePool writer")?;

        // Run migrations on database
        sqlx::migrate!("./migrations")
            .run(&writer_pool)
            .await
            .context("Error running migrations, can't start")?;
        Ok(Self {
            reader_pool,
            writer_pool,
        })
    }

    pub async fn get_user_with_id(
        &self,
        device_id: &UserId,
    ) -> Result<Option<User>, anyhow::Error> {
        let user = sqlx::query_as!(
            User,
            r#"
            SELECT thread_id as "thread_id!", device_id as "device_id!: String", apns_token,
            device_info_json as "device_info?: Json<DeviceInfo>" 
            FROM users WHERE device_id = ?
            "#,
            device_id
        )
        .fetch_optional(&self.reader_pool)
        .await
        .context("Error fetching user")?;
        Ok(user)
    }

    pub async fn get_user_with_thread(
        &self,
        thread_id: i64,
    ) -> Result<Option<User>, anyhow::Error> {
        let user = sqlx::query_as!(
            User,
            r#"
            SELECT thread_id as "thread_id!", device_id as "device_id!: String", apns_token,
            device_info_json as "device_info?: Json<DeviceInfo>" 
            FROM users WHERE thread_id = ?
            "#,
            thread_id
        )
        .fetch_optional(&self.reader_pool)
        .await
        .context("Error fetching user")?;
        Ok(user)
    }

    pub async fn clear_user_apns(&self, device_id: &UserId) -> Result<(), anyhow::Error> {
        tracing::info!("Clearing APNS token for user {}", device_id);
        sqlx::query_scalar!(
            r#"
            UPDATE users
            SET apns_token = NULL
            WHERE device_id = ?
            returning device_id as "device_id!: String"
            "#,
            device_id
        )
        .fetch_one(&self.writer_pool)
        .await
        .context("Error updating user")?;
        Ok(())
    }

    pub async fn update_user(
        &self,
        device_id: &UserId,
        user: &UserUpdate,
    ) -> Result<User, anyhow::Error> {
        let device_info_json = user
            .device_info
            .as_ref()
            .map(|device_info| Json(device_info.clone()));
        let user = sqlx::query_as!(
            User,
            r#"
            UPDATE users
            SET
                thread_id = COALESCE(?, thread_id),
                apns_token = COALESCE(?, apns_token),
                device_info_json = COALESCE(?, device_info_json)
            WHERE device_id = ?
            RETURNING
                device_id as "device_id!: String",
                thread_id as "thread_id!",
                apns_token, device_info_json as "device_info?: Json<DeviceInfo>"
            "#,
            user.thread_id,
            user.apns_token,
            device_info_json,
            device_id
        )
        .fetch_one(&self.writer_pool)
        .await
        .context("Error updating user")?;
        Ok(user)
    }

    pub async fn get_parameter(&self, key: &str) -> Result<Option<String>, anyhow::Error> {
        let value = sqlx::query_scalar!(
            r#"
            SELECT value  FROM parameters WHERE key = ?
            "#,
            key
        )
        .fetch_optional(&self.reader_pool)
        .await
        .context("Error fetching user")?;
        Ok(value)
    }

    pub async fn set_parameter(&self, key: &str, value: &str) -> Result<(), anyhow::Error> {
        sqlx::query!(
            r#"
                INSERT INTO parameters (key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
            "#,
            key,
            value
        )
        .execute(&self.writer_pool)
        .await
        .context("Error setting parameter")?;
        Ok(())
    }

    pub async fn get_last_alerted_message(&self) -> Result<Option<i64>, anyhow::Error> {
        let param = self.get_parameter("last_alerted_message").await?;

        if let Some(param) = param {
            Ok(Some(param.parse()?))
        } else {
            Ok(None)
        }
    }

    pub async fn set_last_alerted_message(&self, message_id: i64) -> Result<(), anyhow::Error> {
        return self
            .set_parameter("last_alerted_message", &message_id.to_string())
            .await;
    }

    pub async fn create_user(&self, user: &User) -> Result<User, anyhow::Error> {
        sqlx::query_as!(
            User,
            r#"
            INSERT INTO users (device_id, thread_id, apns_token, device_info_json)
            VALUES (?, ?, ?, ?)
            RETURNING device_id as "device_id!: String", thread_id as "thread_id!", apns_token,
            device_info_json as "device_info?: Json<DeviceInfo>"
            "#,
            user.device_id,
            user.thread_id,
            user.apns_token,
            user.device_info
        )
        .fetch_one(&self.writer_pool)
        .await
        .context("Error creating user")
    }
}

#[derive(Debug, serde::Serialize)]
pub struct User {
    pub device_id: UserId,
    #[serde(serialize_with = "i64_to_string")]
    pub thread_id: i64,
    pub apns_token: Option<String>,
    pub device_info: Option<Json<DeviceInfo>>,
}

#[derive(Default)]
pub struct UserUpdate {
    pub apns_token: Option<String>,
    pub thread_id: Option<i64>,
    pub device_info: Option<DeviceInfo>,
}

#[derive(Debug, Clone, serde::Deserialize, serde::Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DeviceInfo {
    pub user_id: Option<String>,
    pub build_version: Option<String>,
    pub release_version: Option<String>,
    pub os_platform: Option<String>,
    pub os_version: Option<String>,
    pub user_locale: Option<String>,
}
