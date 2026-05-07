use std::{path::PathBuf, str::FromStr, time::Duration};

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
            device_info_json as "device_info?: Json<DeviceInfo>",
            ai_disabled as "ai_disabled!: bool"
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
            device_info_json as "device_info?: Json<DeviceInfo>",
            ai_disabled as "ai_disabled!: bool"
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
                apns_token, device_info_json as "device_info?: Json<DeviceInfo>",
                ai_disabled as "ai_disabled!: bool"
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

    pub async fn set_thread_ai_disabled(
        &self,
        thread_id: i64,
        ai_disabled: bool,
    ) -> Result<bool, anyhow::Error> {
        let result = sqlx::query!(
            r#"
            UPDATE users SET ai_disabled = ? WHERE thread_id = ?
            "#,
            ai_disabled,
            thread_id
        )
        .execute(&self.writer_pool)
        .await
        .context("Error updating thread ai_disabled flag")?;
        Ok(result.rows_affected() > 0)
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
            device_info_json as "device_info?: Json<DeviceInfo>",
            ai_disabled as "ai_disabled!: bool"
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

    pub async fn insert_pending_symbolication(
        &self,
        row: &PendingSymbolication,
    ) -> Result<(), anyhow::Error> {
        sqlx::query!(
            r#"
            INSERT INTO pending_symbolications (
                id, device_id, thread_id, payload_path, diagnostics_json,
                installation_info_json, binary_uuids_json, payload_index,
                received_at_ms, leased_at_ms, completed_at_ms, failed_at_ms,
                attempts, last_error
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            "#,
            row.id,
            row.device_id,
            row.thread_id,
            row.payload_path,
            row.diagnostics_json,
            row.installation_info_json,
            row.binary_uuids_json,
            row.payload_index,
            row.received_at_ms,
            row.leased_at_ms,
            row.completed_at_ms,
            row.failed_at_ms,
            row.attempts,
            row.last_error,
        )
        .execute(&self.writer_pool)
        .await
        .context("Error inserting pending_symbolication")?;
        Ok(())
    }

    /// Atomically (a) flips rows whose `attempts >= 3 AND leased_at_ms < now - lease_ttl`
    /// to `failed_at_ms = now` and returns them so the caller can notify Discord, and
    /// (b) leases up to `n` eligible rows by setting `leased_at_ms = now` and incrementing
    /// `attempts`. Returns `(newly_failed, leased)`.
    pub async fn lease_pending_symbolications(
        &self,
        n: i64,
        lease_ttl: Duration,
    ) -> Result<(Vec<PendingSymbolication>, Vec<PendingSymbolication>), anyhow::Error> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        let lease_cutoff_ms = now_ms - (lease_ttl.as_millis() as i64);

        let newly_failed = sqlx::query_as!(
            PendingSymbolication,
            r#"
            UPDATE pending_symbolications
            SET failed_at_ms = ?
            WHERE completed_at_ms IS NULL
              AND failed_at_ms IS NULL
              AND attempts >= 3
              AND leased_at_ms IS NOT NULL
              AND leased_at_ms < ?
            RETURNING
                id as "id!: String",
                device_id as "device_id!: String",
                thread_id as "thread_id!",
                payload_path as "payload_path!: String",
                diagnostics_json as "diagnostics_json!: String",
                installation_info_json as "installation_info_json!: String",
                binary_uuids_json as "binary_uuids_json!: String",
                payload_index as "payload_index!",
                received_at_ms as "received_at_ms!",
                leased_at_ms,
                completed_at_ms,
                failed_at_ms,
                attempts as "attempts!",
                last_error
            "#,
            now_ms,
            lease_cutoff_ms,
        )
        .fetch_all(&self.writer_pool)
        .await
        .context("Error marking exhausted leases as failed")?;

        let leased = sqlx::query_as!(
            PendingSymbolication,
            r#"
            UPDATE pending_symbolications
            SET leased_at_ms = ?, attempts = attempts + 1
            WHERE id IN (
                SELECT id FROM pending_symbolications
                WHERE completed_at_ms IS NULL
                  AND failed_at_ms IS NULL
                  AND attempts < 3
                  AND (leased_at_ms IS NULL OR leased_at_ms < ?)
                ORDER BY received_at_ms
                LIMIT ?
            )
            RETURNING
                id as "id!: String",
                device_id as "device_id!: String",
                thread_id as "thread_id!",
                payload_path as "payload_path!: String",
                diagnostics_json as "diagnostics_json!: String",
                installation_info_json as "installation_info_json!: String",
                binary_uuids_json as "binary_uuids_json!: String",
                payload_index as "payload_index!",
                received_at_ms as "received_at_ms!",
                leased_at_ms,
                completed_at_ms,
                failed_at_ms,
                attempts as "attempts!",
                last_error
            "#,
            now_ms,
            lease_cutoff_ms,
            n,
        )
        .fetch_all(&self.writer_pool)
        .await
        .context("Error leasing pending_symbolications")?;

        Ok((newly_failed, leased))
    }

    pub async fn complete_pending_symbolication(
        &self,
        id: &str,
    ) -> Result<Option<PendingSymbolication>, anyhow::Error> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        let row = sqlx::query_as!(
            PendingSymbolication,
            r#"
            UPDATE pending_symbolications
            SET completed_at_ms = ?, last_error = NULL
            WHERE id = ? AND completed_at_ms IS NULL
            RETURNING
                id as "id!: String",
                device_id as "device_id!: String",
                thread_id as "thread_id!",
                payload_path as "payload_path!: String",
                diagnostics_json as "diagnostics_json!: String",
                installation_info_json as "installation_info_json!: String",
                binary_uuids_json as "binary_uuids_json!: String",
                payload_index as "payload_index!",
                received_at_ms as "received_at_ms!",
                leased_at_ms,
                completed_at_ms,
                failed_at_ms,
                attempts as "attempts!",
                last_error
            "#,
            now_ms,
            id,
        )
        .fetch_optional(&self.writer_pool)
        .await
        .context("Error completing pending_symbolication")?;
        Ok(row)
    }

    /// Records a worker-reported failure on the given lease. Clears `leased_at_ms`
    /// so the row is re-leasable, but keeps the incremented `attempts` from the
    /// lease call, which is what caps retries via the `attempts < 3` filter.
    pub async fn release_lease_with_error(
        &self,
        id: &str,
        error: &str,
    ) -> Result<Option<PendingSymbolication>, anyhow::Error> {
        let row = sqlx::query_as!(
            PendingSymbolication,
            r#"
            UPDATE pending_symbolications
            SET leased_at_ms = NULL, last_error = ?
            WHERE id = ? AND completed_at_ms IS NULL AND failed_at_ms IS NULL
            RETURNING
                id as "id!: String",
                device_id as "device_id!: String",
                thread_id as "thread_id!",
                payload_path as "payload_path!: String",
                diagnostics_json as "diagnostics_json!: String",
                installation_info_json as "installation_info_json!: String",
                binary_uuids_json as "binary_uuids_json!: String",
                payload_index as "payload_index!",
                received_at_ms as "received_at_ms!",
                leased_at_ms,
                completed_at_ms,
                failed_at_ms,
                attempts as "attempts!",
                last_error
            "#,
            error,
            id,
        )
        .fetch_optional(&self.writer_pool)
        .await
        .context("Error releasing pending_symbolication lease")?;
        Ok(row)
    }
}

#[derive(Debug, serde::Serialize)]
pub struct User {
    pub device_id: UserId,
    #[serde(serialize_with = "i64_to_string")]
    pub thread_id: i64,
    pub apns_token: Option<String>,
    pub device_info: Option<Json<DeviceInfo>>,
    #[serde(skip_serializing)]
    pub ai_disabled: bool,
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

#[derive(Debug, Clone)]
pub struct PendingSymbolication {
    pub id: String,
    pub device_id: String,
    pub thread_id: i64,
    pub payload_path: String,
    pub diagnostics_json: String,
    pub installation_info_json: String,
    pub binary_uuids_json: String,
    pub payload_index: i64,
    pub received_at_ms: i64,
    pub leased_at_ms: Option<i64>,
    pub completed_at_ms: Option<i64>,
    pub failed_at_ms: Option<i64>,
    pub attempts: i64,
    pub last_error: Option<String>,
}
