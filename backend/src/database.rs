use std::{path::PathBuf, str::FromStr, time::Duration};

use crate::{UserId, utils::i64_to_string};
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

    /// Atomically (a) flips rows that have exhausted their attempts to
    /// `failed_at_ms = now` and returns them so the caller can notify Discord, and
    /// (b) leases up to `n` eligible rows by setting `leased_at_ms = now` and incrementing
    /// `attempts`. Returns `(newly_failed, leased)`.
    ///
    /// A row is eligible for lease once it is not held by a live lease *and* its
    /// retry backoff has elapsed; see `release_lease_with_error`.
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
              -- `leased_at_ms IS NOT NULL` used to be required here, but a
              -- worker reporting failure clears it. An exhausted row therefore
              -- matched neither this query (lease was NULL) nor the lease query
              -- below (attempts >= 3) and sat unfailed forever, so its Discord
              -- notification never fired. Match a cleared lease too; the
              -- IS NOT NULL case still covers workers that died holding one.
              AND (leased_at_ms IS NULL OR leased_at_ms < ?)
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
                  AND (retry_after_ms IS NULL OR retry_after_ms <= ?)
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
            now_ms,
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

    /// Records a freshly symbolicated crash against its thread.
    ///
    /// Upserts, so a thread keeps one row describing its most recent crash.
    /// The review columns are untouched, so a thread reviewed before this crash
    /// becomes unreviewed again.
    pub async fn record_crash_for_review(
        &self,
        thread_id: i64,
        latest_crash_message_id: Option<i64>,
        facts: &crate::crash_rules::CrashFacts,
    ) -> Result<CrashReview, anyhow::Error> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        let app_version = facts.app_version.as_deref();
        let installed_version = facts.installed_version.as_deref();
        let device_type = facts.device_type.as_deref();
        let os_version = facts.os_version.as_deref();
        let termination_code = facts.termination_code.as_deref();
        sqlx::query_as!(
            CrashReview,
            r#"
            INSERT INTO crash_reviews (
                thread_id, latest_crash_message_id, latest_crash_at_ms,
                app_version, installed_version, device_type, os_version,
                exception_type, signal, termination_code
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(thread_id) DO UPDATE SET
                latest_crash_message_id = excluded.latest_crash_message_id,
                latest_crash_at_ms = excluded.latest_crash_at_ms,
                app_version = excluded.app_version,
                installed_version = excluded.installed_version,
                device_type = excluded.device_type,
                os_version = excluded.os_version,
                exception_type = excluded.exception_type,
                signal = excluded.signal,
                termination_code = excluded.termination_code
            RETURNING thread_id,
                latest_crash_message_id,
                latest_crash_at_ms,
                app_version,
                installed_version,
                device_type,
                os_version,
                exception_type,
                signal,
                termination_code,
                reviewed_at_ms,
                reviewed_by,
                reviewed_message_id,
                matched_rule_id,
                review_note
            "#,
            thread_id,
            latest_crash_message_id,
            now_ms,
            app_version,
            installed_version,
            device_type,
            os_version,
            facts.exception_type,
            facts.signal,
            termination_code,
        )
        .fetch_one(&self.writer_pool)
        .await
        .context("Error recording crash for review")
    }

    /// Marks a thread reviewed as of now.
    ///
    /// `reviewed_by` is free-form: `auto:<rule id>` for the rules engine, or
    /// whatever a human caller supplies.
    /// Records which rule matched a crash without reviewing it.
    ///
    /// Used when a rule matches a crash from a build that already carries its
    /// fix: the diagnosis is worth keeping on the row, but `reviewed_at_ms`
    /// stays null so the thread remains in the unreviewed queue.
    pub async fn note_rule_match(
        &self,
        thread_id: i64,
        matched_rule_id: &str,
        review_note: &str,
    ) -> Result<(), anyhow::Error> {
        sqlx::query!(
            r#"
            UPDATE crash_reviews
            SET matched_rule_id = ?, review_note = ?
            WHERE thread_id = ?
            "#,
            matched_rule_id,
            review_note,
            thread_id,
        )
        .execute(&self.writer_pool)
        .await
        .context("Error recording rule match")?;
        Ok(())
    }

    pub async fn mark_thread_reviewed(
        &self,
        thread_id: i64,
        reviewed_by: Option<&str>,
        reviewed_message_id: Option<i64>,
        matched_rule_id: Option<&str>,
        review_note: Option<&str>,
    ) -> Result<Option<CrashReview>, anyhow::Error> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        sqlx::query_as!(
            CrashReview,
            r#"
            UPDATE crash_reviews
            SET reviewed_at_ms = ?,
                reviewed_by = ?,
                reviewed_message_id = COALESCE(?, reviewed_message_id),
                matched_rule_id = COALESCE(?, matched_rule_id),
                review_note = COALESCE(?, review_note)
            WHERE thread_id = ?
            RETURNING thread_id,
                latest_crash_message_id,
                latest_crash_at_ms,
                app_version,
                installed_version,
                device_type,
                os_version,
                exception_type,
                signal,
                termination_code,
                reviewed_at_ms,
                reviewed_by,
                reviewed_message_id,
                matched_rule_id,
                review_note
            "#,
            now_ms,
            reviewed_by,
            reviewed_message_id,
            matched_rule_id,
            review_note,
            thread_id,
        )
        .fetch_optional(&self.writer_pool)
        .await
        .context("Error marking thread reviewed")
    }

    /// Clears review state so a thread shows up as needing attention again.
    pub async fn mark_thread_unreviewed(
        &self,
        thread_id: i64,
    ) -> Result<Option<CrashReview>, anyhow::Error> {
        sqlx::query_as!(
            CrashReview,
            r#"
            UPDATE crash_reviews
            SET reviewed_at_ms = NULL,
                reviewed_by = NULL,
                reviewed_message_id = NULL,
                matched_rule_id = NULL,
                review_note = NULL
            WHERE thread_id = ?
            RETURNING thread_id,
                latest_crash_message_id,
                latest_crash_at_ms,
                app_version,
                installed_version,
                device_type,
                os_version,
                exception_type,
                signal,
                termination_code,
                reviewed_at_ms,
                reviewed_by,
                reviewed_message_id,
                matched_rule_id,
                review_note
            "#,
            thread_id,
        )
        .fetch_optional(&self.writer_pool)
        .await
        .context("Error marking thread unreviewed")
    }

    /// Lists tracked crash threads, newest crash first.
    ///
    /// `only_unreviewed` applies the same predicate as
    /// [`CrashReview::is_unreviewed`]. `before_ms` pages backwards through
    /// `latest_crash_at_ms`; pass the last row's value to get the next page.
    ///
    /// `app_version` finds the crashes a build produced; `installed_version`
    /// finds the reporters a build is installed on. They combine with AND.
    pub async fn list_crash_reviews(
        &self,
        only_unreviewed: bool,
        app_version: Option<&str>,
        installed_version: Option<&str>,
        before_ms: Option<i64>,
        limit: i64,
    ) -> Result<Vec<CrashReview>, anyhow::Error> {
        sqlx::query_as!(
            CrashReview,
            r#"
            SELECT thread_id,
                latest_crash_message_id,
                latest_crash_at_ms,
                app_version,
                installed_version,
                device_type,
                os_version,
                exception_type,
                signal,
                termination_code,
                reviewed_at_ms,
                reviewed_by,
                reviewed_message_id,
                matched_rule_id,
                review_note
            FROM crash_reviews
            WHERE (?1 = 0 OR reviewed_at_ms IS NULL OR reviewed_at_ms < latest_crash_at_ms)
              AND (?2 IS NULL OR app_version = ?2)
              AND (?3 IS NULL OR installed_version = ?3)
              AND (?4 IS NULL OR latest_crash_at_ms < ?4)
            ORDER BY latest_crash_at_ms DESC
            LIMIT ?5
            "#,
            only_unreviewed,
            app_version,
            installed_version,
            before_ms,
            limit,
        )
        .fetch_all(&self.reader_pool)
        .await
        .context("Error listing crash reviews")
    }

    pub async fn get_crash_review(
        &self,
        thread_id: i64,
    ) -> Result<Option<CrashReview>, anyhow::Error> {
        sqlx::query_as!(
            CrashReview,
            r#"
            SELECT thread_id,
                latest_crash_message_id,
                latest_crash_at_ms,
                app_version,
                installed_version,
                device_type,
                os_version,
                exception_type,
                signal,
                termination_code,
                reviewed_at_ms,
                reviewed_by,
                reviewed_message_id,
                matched_rule_id,
                review_note
            FROM crash_reviews
            WHERE thread_id = ?
            "#,
            thread_id,
        )
        .fetch_optional(&self.reader_pool)
        .await
        .context("Error getting crash review")
    }

    /// Records every crash in one symbolicated report. Idempotent on
    /// `(message_id, crash_index)`; returns how many rows were new.
    pub async fn insert_crash_records(
        &self,
        thread_id: i64,
        message_id: i64,
        received_at_ms: i64,
        crashes: &[crate::crash_records::ParsedCrash],
    ) -> Result<u64, anyhow::Error> {
        let mut tx = self.writer_pool.begin().await?;
        let mut inserted = 0;
        for crash in crashes {
            let facts = &crash.facts;
            let app_version = facts.app_version.as_deref();
            let installed_version = facts.installed_version.as_deref();
            let device_type = facts.device_type.as_deref();
            let os_version = facts.os_version.as_deref();
            let termination_code = facts.termination_code.as_deref();
            let window_begin = crash.window_begin.as_deref();
            let window_end = crash.window_end.as_deref();
            let crash_day = crash.crash_day.as_deref();
            let user_id = crash.user_id.as_deref();
            let app_build_version = crash.app_build_version.as_deref();
            inserted += sqlx::query!(
                r#"
                INSERT OR IGNORE INTO crash_records (
                    thread_id, message_id, crash_index, received_at_ms,
                    window_begin, window_end, crash_day, user_id,
                    app_version, app_build_version, installed_version,
                    device_type, os_version, exception_type, signal,
                    termination_code, matched_rule_id, dev_build
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                "#,
                thread_id,
                message_id,
                crash.crash_index,
                received_at_ms,
                window_begin,
                window_end,
                crash_day,
                user_id,
                app_version,
                app_build_version,
                installed_version,
                device_type,
                os_version,
                facts.exception_type,
                facts.signal,
                termination_code,
                crash.matched_rule_id,
                crash.dev_build,
            )
            .execute(&mut *tx)
            .await
            .context("Error inserting crash record")?
            .rows_affected();
        }
        tx.commit().await?;
        Ok(inserted)
    }

    /// Crash records newest first. `before_id` pages on the previous page's
    /// last `id`.
    pub async fn list_crash_records(
        &self,
        filter: &CrashRecordFilter,
        before_id: Option<i64>,
        limit: i64,
    ) -> Result<Vec<CrashRecord>, anyhow::Error> {
        sqlx::query_as!(
            CrashRecord,
            r#"
            SELECT id,
                thread_id,
                message_id,
                crash_index,
                received_at_ms,
                window_begin,
                window_end,
                COALESCE(crash_day, date(received_at_ms / 1000, 'unixepoch')) AS "crash_day!: String",
                user_id,
                app_version,
                app_build_version,
                installed_version,
                device_type,
                os_version,
                exception_type,
                signal,
                termination_code,
                matched_rule_id,
                dev_build AS "dev_build: bool"
            FROM crash_records
            WHERE (?1 OR dev_build = 0)
              AND (?2 IS NULL OR app_version = ?2)
              AND (?3 IS NULL OR thread_id = ?3)
              AND (?4 IS NULL OR COALESCE(crash_day, date(received_at_ms / 1000, 'unixepoch')) >= ?4)
              AND (?5 IS NULL OR id < ?5)
            ORDER BY id DESC
            LIMIT ?6
            "#,
            filter.include_dev,
            filter.app_version,
            filter.thread_id,
            filter.since_day,
            before_id,
            limit,
        )
        .fetch_all(&self.reader_pool)
        .await
        .context("Error listing crash records")
    }

    /// Crashes per device-local day, oldest first. A report with no payload
    /// window falls back to the UTC day it was posted.
    pub async fn crash_counts_by_day(
        &self,
        filter: &CrashRecordFilter,
    ) -> Result<Vec<DailyCrashCount>, anyhow::Error> {
        sqlx::query_as!(
            DailyCrashCount,
            r#"
            SELECT COALESCE(crash_day, date(received_at_ms / 1000, 'unixepoch')) AS "day!: String",
                COUNT(*) AS "crashes!: i64",
                COUNT(DISTINCT thread_id) AS "devices!: i64"
            FROM crash_records
            WHERE (?1 OR dev_build = 0)
              AND (?2 IS NULL OR app_version = ?2)
              AND (?3 IS NULL OR thread_id = ?3)
              AND (?4 IS NULL OR COALESCE(crash_day, date(received_at_ms / 1000, 'unixepoch')) >= ?4)
            GROUP BY 1
            ORDER BY 1
            "#,
            filter.include_dev,
            filter.app_version,
            filter.thread_id,
            filter.since_day,
        )
        .fetch_all(&self.reader_pool)
        .await
        .context("Error counting crashes by day")
    }

    /// Records a worker-reported failure on the given lease. Clears `leased_at_ms`
    /// so the row is re-leasable, but keeps the incremented `attempts` from the
    /// lease call, which is what caps retries via the `attempts < 3` filter.
    ///
    /// Also stamps `retry_after_ms`, without which the drain loop would burn
    /// every attempt within the same second.
    pub async fn release_lease_with_error(
        &self,
        id: &str,
        error: &str,
    ) -> Result<Option<PendingSymbolication>, anyhow::Error> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        let base_ms = RETRY_BACKOFF_BASE.as_millis() as i64;
        // Doubles per attempt, derived from the row's own counter. `attempts`
        // includes the failure just recorded, so the first waits one base
        // interval. Capped at 2^7.
        let row = sqlx::query_as!(
            PendingSymbolication,
            r#"
            UPDATE pending_symbolications
            SET leased_at_ms = NULL,
                retry_after_ms = ? + ? * (1 << MIN(MAX(attempts - 1, 0), 7)),
                last_error = ?
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
            now_ms,
            base_ms,
            error,
            id,
        )
        .fetch_optional(&self.writer_pool)
        .await
        .context("Error releasing pending_symbolication lease")?;
        Ok(row)
    }
}

impl DatabaseClient {
    /// Returns exhausted symbolications to the queue with a fresh attempt budget.
    ///
    /// Covers rows marked `failed_at_ms` and rows that ran out of attempts.
    /// `error_contains` narrows the reset to a single failure mode.
    ///
    /// Rows whose payload has been reaped fail again on their next lease with
    /// "payload missing on disk".
    /// Payloads of permanently-failed symbolications old enough to reap.
    ///
    /// Returns `(id, payload_path)` for rows that failed before `cutoff_ms`
    /// whose file remains. The caller deletes them and reports back via
    /// `mark_payload_reaped`, so a failed delete retries on the next sweep.
    pub async fn expired_failed_payloads(
        &self,
        cutoff_ms: i64,
    ) -> Result<Vec<(String, String)>, anyhow::Error> {
        let rows = sqlx::query!(
            r#"
            SELECT id as "id!: String", payload_path as "payload_path!: String"
            FROM pending_symbolications
            WHERE failed_at_ms IS NOT NULL
              AND failed_at_ms < ?
              AND payload_reaped_at_ms IS NULL
            ORDER BY failed_at_ms
            "#,
            cutoff_ms,
        )
        .fetch_all(&self.reader_pool)
        .await
        .context("Error listing expired failed symbolication payloads")?;
        Ok(rows
            .into_iter()
            .map(|row| (row.id, row.payload_path))
            .collect())
    }

    /// Record that a failed symbolication's payload file has been removed.
    pub async fn mark_payload_reaped(&self, id: &str) -> Result<(), anyhow::Error> {
        let now_ms = chrono::Utc::now().timestamp_millis();
        sqlx::query!(
            "UPDATE pending_symbolications SET payload_reaped_at_ms = ? WHERE id = ?",
            now_ms,
            id,
        )
        .execute(&self.writer_pool)
        .await
        .context("Error marking symbolication payload as reaped")?;
        Ok(())
    }

    /// Ids that `requeue_failed_symbolications` would reset, without resetting
    /// them. Same predicate, so a dry run cannot disagree with the real thing.
    pub async fn failed_symbolication_ids(
        &self,
        error_contains: Option<&str>,
    ) -> Result<Vec<String>, anyhow::Error> {
        let pattern = error_contains.map(|needle| format!("%{needle}%"));
        let ids = sqlx::query_scalar!(
            r#"
            SELECT id as "id!: String"
            FROM pending_symbolications
            WHERE completed_at_ms IS NULL
              AND (failed_at_ms IS NOT NULL OR attempts >= 3)
              AND payload_reaped_at_ms IS NULL
              AND (? IS NULL OR last_error LIKE ?)
            ORDER BY received_at_ms
            "#,
            pattern,
            pattern,
        )
        .fetch_all(&self.reader_pool)
        .await
        .context("Error listing failed pending_symbolications")?;
        Ok(ids)
    }

    pub async fn requeue_failed_symbolications(
        &self,
        error_contains: Option<&str>,
    ) -> Result<Vec<PendingSymbolication>, anyhow::Error> {
        let pattern = error_contains.map(|needle| format!("%{needle}%"));
        let rows = sqlx::query_as!(
            PendingSymbolication,
            r#"
            UPDATE pending_symbolications
            SET failed_at_ms = NULL,
                leased_at_ms = NULL,
                retry_after_ms = NULL,
                attempts = 0
            WHERE completed_at_ms IS NULL
              AND (failed_at_ms IS NOT NULL OR attempts >= 3)
              AND payload_reaped_at_ms IS NULL
              AND (? IS NULL OR last_error LIKE ?)
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
            pattern,
            pattern,
        )
        .fetch_all(&self.writer_pool)
        .await
        .context("Error requeueing failed pending_symbolications")?;
        Ok(rows)
    }
}

// ---------------------------------------------------------------------------
// App Attest credentials and the sessions they mint
// ---------------------------------------------------------------------------

/// A Secure Enclave key that passed attestation, and the anti-replay state for
/// the assertions it signs.
#[derive(Debug, Clone)]
pub struct AttestKey {
    pub key_id: String,
    pub public_key: Vec<u8>,
    /// Install id bound at registration. It never moves to another id, so an
    /// attested key can only ever act as the conversation it first claimed.
    pub user_id: String,
    pub bundle_id: String,
    pub environment: String,
    pub sign_count: i64,
    pub replay_window: i64,
    pub revoked_at_ms: Option<i64>,
}

#[derive(Debug, Clone)]
pub struct AppSession {
    pub session_id: String,
    /// Null for the unattested fallback issued to devices with no Secure Enclave.
    pub key_id: Option<String>,
    pub user_id: String,
    pub attested: bool,
    pub bundle_id: Option<String>,
    pub expires_at_ms: i64,
}

impl DatabaseClient {
    pub async fn issue_challenge(
        &self,
        challenge: &str,
        issued_at_ms: i64,
        expires_at_ms: i64,
    ) -> Result<(), anyhow::Error> {
        sqlx::query!(
            "INSERT INTO attest_challenges (challenge, issued_at_ms, expires_at_ms)
             VALUES (?, ?, ?)",
            challenge,
            issued_at_ms,
            expires_at_ms,
        )
        .execute(&self.writer_pool)
        .await
        .context("Error issuing attestation challenge")?;
        Ok(())
    }

    /// Spends a challenge, reporting whether this caller is the one that got it.
    ///
    /// The guard lives in the `UPDATE` rather than in a read followed by a
    /// write, so two clients racing on the same challenge cannot both win.
    pub async fn consume_challenge(
        &self,
        challenge: &str,
        now_ms: i64,
    ) -> Result<bool, anyhow::Error> {
        let result = sqlx::query!(
            "UPDATE attest_challenges SET consumed_at_ms = ?
             WHERE challenge = ? AND consumed_at_ms IS NULL AND expires_at_ms > ?",
            now_ms,
            challenge,
            now_ms,
        )
        .execute(&self.writer_pool)
        .await
        .context("Error consuming attestation challenge")?;
        Ok(result.rows_affected() == 1)
    }

    /// Stores a freshly attested key, or leaves an existing one untouched.
    ///
    /// A repeat registration is a client retry: Apple only ever attests a key
    /// once. The conflict branch therefore refreshes nothing that would let a
    /// second call move the key to another install id or rewind its replay
    /// state. It returns the `user_id` actually on file so the caller can tell
    /// the client which conversation it owns.
    pub async fn register_attest_key(
        &self,
        key: &AttestKey,
        receipt: &[u8],
        now_ms: i64,
    ) -> Result<String, anyhow::Error> {
        sqlx::query!(
            "INSERT INTO attest_keys (
                 key_id, public_key, user_id, bundle_id, environment, receipt,
                 sign_count, replay_window, created_at_ms, last_seen_at_ms
             )
             VALUES (?, ?, ?, ?, ?, ?, 0, 0, ?, ?)
             ON CONFLICT (key_id) DO UPDATE SET last_seen_at_ms = excluded.last_seen_at_ms",
            key.key_id,
            key.public_key,
            key.user_id,
            key.bundle_id,
            key.environment,
            receipt,
            now_ms,
            now_ms,
        )
        .execute(&self.writer_pool)
        .await
        .context("Error registering attestation key")?;

        let stored = sqlx::query_scalar!(
            r#"SELECT user_id as "user_id!: String" FROM attest_keys WHERE key_id = ?"#,
            key.key_id
        )
        .fetch_one(&self.writer_pool)
        .await
        .context("Error reading back registered attestation key")?;
        Ok(stored)
    }

    pub async fn get_attest_key(&self, key_id: &str) -> Result<Option<AttestKey>, anyhow::Error> {
        let key = sqlx::query_as!(
            AttestKey,
            r#"SELECT
                   key_id as "key_id!: String",
                   public_key as "public_key!: Vec<u8>",
                   user_id as "user_id!: String",
                   bundle_id as "bundle_id!: String",
                   environment as "environment!: String",
                   sign_count as "sign_count!",
                   replay_window as "replay_window!",
                   revoked_at_ms
               FROM attest_keys WHERE key_id = ?"#,
            key_id
        )
        .fetch_optional(&self.reader_pool)
        .await
        .context("Error loading attestation key")?;
        Ok(key)
    }

    /// Folds an accepted assertion counter into the stored replay window.
    ///
    /// The write is conditional on the window still holding the values the
    /// caller verified against, so two concurrent assertions cannot both commit
    /// from the same starting state and lose one of the two counters.
    pub async fn record_assertion(
        &self,
        key_id: &str,
        previous: (i64, i64),
        next: (i64, i64),
        now_ms: i64,
    ) -> Result<bool, anyhow::Error> {
        let (previous_count, previous_window) = previous;
        let (next_count, next_window) = next;
        let result = sqlx::query!(
            "UPDATE attest_keys
             SET sign_count = ?, replay_window = ?, last_seen_at_ms = ?
             WHERE key_id = ? AND sign_count = ? AND replay_window = ?",
            next_count,
            next_window,
            now_ms,
            key_id,
            previous_count,
            previous_window,
        )
        .execute(&self.writer_pool)
        .await
        .context("Error recording assertion counter")?;
        Ok(result.rows_affected() == 1)
    }

    pub async fn create_session(
        &self,
        token_hash: &[u8],
        session: &AppSession,
        issued_at_ms: i64,
    ) -> Result<(), anyhow::Error> {
        sqlx::query!(
            "INSERT INTO app_sessions (
                 token_hash, session_id, key_id, user_id, attested, bundle_id,
                 issued_at_ms, expires_at_ms
             )
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            token_hash,
            session.session_id,
            session.key_id,
            session.user_id,
            session.attested,
            session.bundle_id,
            issued_at_ms,
            session.expires_at_ms,
        )
        .execute(&self.writer_pool)
        .await
        .context("Error creating app session")?;
        Ok(())
    }

    pub async fn get_session(
        &self,
        token_hash: &[u8],
        now_ms: i64,
    ) -> Result<Option<AppSession>, anyhow::Error> {
        let session = sqlx::query_as!(
            AppSession,
            r#"SELECT
                   session_id as "session_id!: String",
                   key_id,
                   user_id as "user_id!: String",
                   attested as "attested!: bool",
                   bundle_id,
                   expires_at_ms as "expires_at_ms!"
               FROM app_sessions
               WHERE token_hash = ? AND expires_at_ms > ?"#,
            token_hash,
            now_ms,
        )
        .fetch_optional(&self.reader_pool)
        .await
        .context("Error loading app session")?;
        Ok(session)
    }

    /// Drops every session minted for a key, so revoking a credential takes
    /// effect before the sessions it already issued expire.
    pub async fn revoke_sessions_for_key(&self, key_id: &str) -> Result<u64, anyhow::Error> {
        let result = sqlx::query!("DELETE FROM app_sessions WHERE key_id = ?", key_id)
            .execute(&self.writer_pool)
            .await
            .context("Error revoking sessions for attestation key")?;
        Ok(result.rows_affected())
    }

    /// Binds a receipt to the install that first presented it, and reports the
    /// install actually on file.
    ///
    /// A receipt is a static file, so the same one can be presented from
    /// anywhere. Keeping the first binding means a copied receipt reaches the
    /// conversation it was copied from rather than opening a new one.
    pub async fn bind_receipt(
        &self,
        fingerprint: &[u8],
        user_id: &str,
        bundle_id: &str,
        app_version: &str,
        now_ms: i64,
    ) -> Result<String, anyhow::Error> {
        sqlx::query!(
            "INSERT INTO receipt_bindings (
                 fingerprint, user_id, bundle_id, app_version,
                 first_seen_at_ms, last_seen_at_ms
             )
             VALUES (?, ?, ?, ?, ?, ?)
             ON CONFLICT (fingerprint) DO UPDATE SET
                 last_seen_at_ms = excluded.last_seen_at_ms,
                 app_version = excluded.app_version",
            fingerprint,
            user_id,
            bundle_id,
            app_version,
            now_ms,
            now_ms,
        )
        .execute(&self.writer_pool)
        .await
        .context("Error binding App Store receipt")?;

        let stored = sqlx::query_scalar!(
            r#"SELECT user_id as "user_id!: String" FROM receipt_bindings WHERE fingerprint = ?"#,
            fingerprint
        )
        .fetch_one(&self.writer_pool)
        .await
        .context("Error reading back the receipt binding")?;
        Ok(stored)
    }

    /// Clears expired sessions and challenges. Both tables are write-once per
    /// app launch, so without a sweep they grow with every install forever.
    pub async fn reap_expired_attest_state(
        &self,
        now_ms: i64,
    ) -> Result<(u64, u64), anyhow::Error> {
        let sessions = sqlx::query!("DELETE FROM app_sessions WHERE expires_at_ms <= ?", now_ms)
            .execute(&self.writer_pool)
            .await
            .context("Error reaping expired app sessions")?
            .rows_affected();
        let challenges = sqlx::query!(
            "DELETE FROM attest_challenges WHERE expires_at_ms <= ?",
            now_ms
        )
        .execute(&self.writer_pool)
        .await
        .context("Error reaping expired attestation challenges")?
        .rows_affected();
        Ok((sessions, challenges))
    }
}

/// Wait after a payload's first failure before it may be leased again; doubles
/// with each subsequent attempt.
///
/// Minutes rather than seconds: rate-limited downloads and fetch blips recover
/// on that scale, and retrying within the same second just burns attempts.
const RETRY_BACKOFF_BASE: Duration = Duration::from_secs(5 * 60);

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

/// Review state for the crashes in one Discord thread.
///
/// See `migrations/20260811000000_crash_reviews.up.sql` for the unreviewed
/// predicate; [`CrashReview::is_unreviewed`] mirrors it in Rust.
///
/// These queries were runtime-checked until
/// `20260811120000_users_device_id_text`, because the untyped `users.device_id`
/// column segfaulted rustc during macro expansion.
#[derive(Debug, Clone, serde::Serialize)]
pub struct CrashReview {
    #[serde(serialize_with = "i64_to_string")]
    pub thread_id: i64,
    #[serde(serialize_with = "crate::utils::i64_to_string_optional")]
    pub latest_crash_message_id: Option<i64>,
    pub latest_crash_at_ms: i64,
    /// The crash's own MetricKit `appVersion`: the build that died.
    pub app_version: Option<String>,
    /// The release the device was running when it uploaded the payload, which
    /// after an App Store update is newer than `app_version`.
    pub installed_version: Option<String>,
    pub device_type: Option<String>,
    pub os_version: Option<String>,
    pub exception_type: Option<i64>,
    pub signal: Option<i64>,
    pub termination_code: Option<String>,
    pub reviewed_at_ms: Option<i64>,
    pub reviewed_by: Option<String>,
    #[serde(serialize_with = "crate::utils::i64_to_string_optional")]
    pub reviewed_message_id: Option<i64>,
    pub matched_rule_id: Option<String>,
    pub review_note: Option<String>,
}

impl CrashReview {
    /// A thread needs attention when it was never reviewed, or when a newer
    /// crash landed after the last review.
    pub fn is_unreviewed(&self) -> bool {
        match self.reviewed_at_ms {
            None => true,
            Some(reviewed_at) => reviewed_at < self.latest_crash_at_ms,
        }
    }
}

/// One crash out of a symbolicated report. See
/// `migrations/20260928120000_crash_records.up.sql`.
#[derive(Debug, Clone, serde::Serialize)]
pub struct CrashRecord {
    pub id: i64,
    #[serde(serialize_with = "i64_to_string")]
    pub thread_id: i64,
    #[serde(serialize_with = "i64_to_string")]
    pub message_id: i64,
    pub crash_index: i64,
    pub received_at_ms: i64,
    /// Device-local wall-clock time, no offset.
    pub window_begin: Option<String>,
    pub window_end: Option<String>,
    pub crash_day: String,
    pub user_id: Option<String>,
    pub app_version: Option<String>,
    pub app_build_version: Option<String>,
    pub installed_version: Option<String>,
    pub device_type: Option<String>,
    pub os_version: Option<String>,
    pub exception_type: Option<i64>,
    pub signal: Option<i64>,
    pub termination_code: Option<String>,
    pub matched_rule_id: Option<String>,
    pub dev_build: bool,
}

#[derive(Debug, Clone, Default)]
pub struct CrashRecordFilter {
    /// Keep simulator and debug builds, which are excluded by default.
    pub include_dev: bool,
    pub app_version: Option<String>,
    pub thread_id: Option<i64>,
    /// Inclusive `YYYY-MM-DD`.
    pub since_day: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct DailyCrashCount {
    pub day: String,
    pub crashes: i64,
    /// Distinct reporting threads, one per user.
    pub devices: i64,
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crash_rules::CrashFacts;

    /// The `crash_reviews` queries are compile-time checked, so column names and
    /// bind types are verified by the macros. These tests cover what that cannot:
    /// the upsert's conflict behaviour, the unreviewed predicate, and paging.
    async fn test_client() -> (DatabaseClient, tempfile::TempDir) {
        let dir = tempfile::tempdir().expect("tempdir");
        let db_path = dir.path().join("test.db");
        let opts = SqliteConnectOptions::from_str(db_path.to_str().unwrap())
            .expect("parse opts")
            .create_if_missing(true);
        let writer_pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect_with(opts.clone())
            .await
            .expect("writer pool");
        let reader_pool = SqlitePoolOptions::new()
            .max_connections(2)
            .connect_with(opts)
            .await
            .expect("reader pool");
        sqlx::migrate!("./migrations")
            .run(&writer_pool)
            .await
            .expect("migrations");
        (
            DatabaseClient {
                reader_pool,
                writer_pool,
            },
            dir,
        )
    }

    /// Both stamp at millisecond resolution and `is_unreviewed` compares with a
    /// strict `<`, so tests needing a strict ordering must let the clock tick.
    async fn tick() {
        tokio::time::sleep(Duration::from_millis(2)).await;
    }

    /// A crash from a device that has not updated since: both versions agree,
    /// which is the common case.
    fn facts(version: &str) -> CrashFacts {
        facts_on(version, version)
    }

    /// A crash from `crashed_on`, reported by a device now running `installed`.
    fn facts_on(crashed_on: &str, installed: &str) -> CrashFacts {
        CrashFacts {
            app_version: Some(crashed_on.to_string()),
            installed_version: Some(installed.to_string()),
            device_type: Some("iPhone14,7".to_string()),
            os_version: Some("iPhone OS 26.6 (23G71)".to_string()),
            exception_type: Some(10),
            signal: Some(9),
            termination_code: Some("0xdead10cc".to_string()),
            // Only the columns above are persisted; the rest exist for matching.
            ..Default::default()
        }
    }

    fn parsed(index: i64, day: Option<&str>, dev_build: bool) -> crate::crash_records::ParsedCrash {
        crate::crash_records::ParsedCrash {
            crash_index: index,
            window_begin: day.map(|d| format!("{d} 10:00:00")),
            window_end: day.map(|d| format!("{d} 10:00:00")),
            crash_day: day.map(str::to_string),
            user_id: Some("abc-def-ghi".to_string()),
            app_build_version: None,
            facts: facts("1.58"),
            matched_rule_id: None,
            dev_build,
        }
    }

    #[tokio::test]
    async fn crash_records_are_idempotent_and_counted_by_day() {
        let (db, _dir) = test_client().await;
        // 2026-09-24T14:16:10.544Z.
        let received = 1_790_259_370_544;
        let report_a = [
            parsed(1, Some("2026-09-20"), false),
            parsed(2, Some("2026-09-20"), false),
            parsed(3, Some("2026-09-21"), true),
        ];
        assert_eq!(
            db.insert_crash_records(1, 10, received, &report_a)
                .await
                .unwrap(),
            3
        );
        assert_eq!(
            db.insert_crash_records(1, 10, received, &report_a)
                .await
                .unwrap(),
            0
        );
        // The same payload re-posted after a requeue.
        assert_eq!(
            db.insert_crash_records(1, 11, received, &report_a[..1])
                .await
                .unwrap(),
            0
        );
        db.insert_crash_records(2, 20, received, &[parsed(1, None, false)])
            .await
            .unwrap();

        let days = db
            .crash_counts_by_day(&CrashRecordFilter::default())
            .await
            .unwrap();
        let days: Vec<(&str, i64, i64)> = days
            .iter()
            .map(|d| (d.day.as_str(), d.crashes, d.devices))
            .collect();
        assert_eq!(days, [("2026-09-20", 2, 1), ("2026-09-24", 1, 1)]);

        let with_dev = CrashRecordFilter {
            include_dev: true,
            since_day: Some("2026-09-21".to_string()),
            ..Default::default()
        };
        let days = db.crash_counts_by_day(&with_dev).await.unwrap();
        assert_eq!(days.len(), 2);
        assert_eq!(days[0].day, "2026-09-21");

        let page = db
            .list_crash_records(&CrashRecordFilter::default(), None, 2)
            .await
            .unwrap();
        assert_eq!(page.len(), 2);
        assert_eq!(page[0].thread_id, 2);
        let rest = db
            .list_crash_records(&CrashRecordFilter::default(), Some(page[1].id), 2)
            .await
            .unwrap();
        assert_eq!(rest.len(), 1);
        assert_eq!(rest[0].crash_index, 1);
    }

    #[tokio::test]
    async fn records_and_reviews_a_crash() {
        let (db, _dir) = test_client().await;

        let recorded = db
            .record_crash_for_review(42, Some(1001), &facts("1.50"))
            .await
            .expect("record");
        assert_eq!(recorded.thread_id, 42);
        assert_eq!(recorded.app_version.as_deref(), Some("1.50"));
        assert_eq!(recorded.exception_type, Some(10));
        assert!(recorded.is_unreviewed());

        let unreviewed = db
            .list_crash_reviews(true, None, None, None, 50)
            .await
            .expect("list");
        assert_eq!(unreviewed.len(), 1);

        let reviewed = db
            .mark_thread_reviewed(
                42,
                Some("auto:test-rule"),
                Some(2002),
                Some("test-rule"),
                None,
            )
            .await
            .expect("review")
            .expect("row exists");
        assert!(!reviewed.is_unreviewed());
        assert_eq!(reviewed.reviewed_by.as_deref(), Some("auto:test-rule"));
        assert_eq!(reviewed.reviewed_message_id, Some(2002));

        assert!(
            db.list_crash_reviews(true, None, None, None, 50)
                .await
                .expect("list")
                .is_empty()
        );
        assert_eq!(
            db.list_crash_reviews(false, None, None, None, 50)
                .await
                .expect("list all")
                .len(),
            1
        );
    }

    #[tokio::test]
    async fn a_newer_crash_reopens_a_reviewed_thread() {
        let (db, _dir) = test_client().await;
        db.record_crash_for_review(7, Some(1), &facts("1.49"))
            .await
            .expect("record");
        db.mark_thread_reviewed(7, Some("someone"), None, None, None)
            .await
            .expect("review");
        tick().await;

        // Same thread, newer crash: the review is now stale and the thread
        // should surface again rather than staying silently closed.
        let reopened = db
            .record_crash_for_review(7, Some(2), &facts("1.50"))
            .await
            .expect("record again");
        assert!(reopened.is_unreviewed(), "{reopened:?}");
        assert_eq!(reopened.app_version.as_deref(), Some("1.50"));
        assert_eq!(reopened.latest_crash_message_id, Some(2));

        let unreviewed = db
            .list_crash_reviews(true, None, None, None, 50)
            .await
            .expect("list");
        assert_eq!(unreviewed.len(), 1);
    }

    #[tokio::test]
    async fn filters_by_version_and_pages_backwards() {
        let (db, _dir) = test_client().await;
        // Thread 3 crashed on 1.50 and has since updated to 1.51, so it answers
        // one version filter and not the other.
        for (thread_id, crashed_on, installed) in [
            (1, "1.49", "1.49"),
            (2, "1.50", "1.50"),
            (3, "1.50", "1.51"),
        ] {
            db.record_crash_for_review(thread_id, None, &facts_on(crashed_on, installed))
                .await
                .expect("record");
        }

        let only_150 = db
            .list_crash_reviews(false, Some("1.50"), None, None, 50)
            .await
            .expect("list");
        assert_eq!(only_150.len(), 2);
        assert!(
            only_150
                .iter()
                .all(|c| c.app_version.as_deref() == Some("1.50"))
        );

        // The installed filter asks the other question: who is *running* 1.50,
        // regardless of which build produced their crash.
        let running_150 = db
            .list_crash_reviews(false, None, Some("1.50"), None, 50)
            .await
            .expect("list");
        assert_eq!(running_150.len(), 1);
        assert_eq!(running_150[0].thread_id, 2);

        // Thread 3 is the one the two filters disagree about.
        let updated_away = db
            .list_crash_reviews(false, Some("1.50"), Some("1.51"), None, 50)
            .await
            .expect("list");
        assert_eq!(updated_away.len(), 1);
        assert_eq!(updated_away[0].thread_id, 3);

        // Both filters AND together, so a mismatched pair matches nothing.
        assert!(
            db.list_crash_reviews(false, Some("1.49"), Some("1.51"), None, 50)
                .await
                .expect("list")
                .is_empty()
        );

        // Newest first, and `before_ms` excludes everything at or after it.
        let all = db
            .list_crash_reviews(false, None, None, None, 50)
            .await
            .expect("list");
        assert_eq!(all.len(), 3);
        let cursor = all[0].latest_crash_at_ms;
        let next_page = db
            .list_crash_reviews(false, None, None, Some(cursor), 50)
            .await
            .expect("page");
        assert!(next_page.iter().all(|c| c.latest_crash_at_ms < cursor));
    }

    #[tokio::test]
    async fn unreview_clears_state_and_missing_threads_report_none() {
        let (db, _dir) = test_client().await;
        db.record_crash_for_review(9, None, &facts("1.50"))
            .await
            .expect("record");
        db.mark_thread_reviewed(9, Some("someone"), Some(5), Some("rule"), Some("note"))
            .await
            .expect("review");

        let cleared = db
            .mark_thread_unreviewed(9)
            .await
            .expect("unreview")
            .expect("row");
        assert!(cleared.is_unreviewed());
        assert_eq!(cleared.reviewed_by, None);
        assert_eq!(cleared.matched_rule_id, None);

        assert!(db.get_crash_review(9).await.expect("get").is_some());
        assert!(db.get_crash_review(12345).await.expect("get").is_none());
        assert!(
            db.mark_thread_reviewed(12345, None, None, None, None)
                .await
                .expect("review missing")
                .is_none()
        );
    }

    fn pending(id: &str) -> PendingSymbolication {
        PendingSymbolication {
            id: id.to_string(),
            device_id: "device".to_string(),
            thread_id: 7,
            payload_path: "/tmp/payload.json".to_string(),
            diagnostics_json: "{}".to_string(),
            installation_info_json: "{}".to_string(),
            binary_uuids_json: "[]".to_string(),
            payload_index: 0,
            received_at_ms: 1,
            leased_at_ms: None,
            completed_at_ms: None,
            failed_at_ms: None,
            attempts: 0,
            last_error: None,
        }
    }

    /// Drive a payload through `attempts` worth of lease-then-fail, the way the
    /// worker does. Returns the rows the lease marked newly failed each round.
    async fn fail_n_times(
        db: &DatabaseClient,
        id: &str,
        times: usize,
    ) -> Vec<PendingSymbolication> {
        let mut newly_failed = Vec::new();
        for _ in 0..times {
            let (failed, leased) = db
                .lease_pending_symbolications(10, Duration::from_secs(15 * 60))
                .await
                .expect("lease");
            newly_failed.extend(failed);
            if leased.iter().any(|row| row.id == id) {
                db.release_lease_with_error(id, "recursion limit exceeded")
                    .await
                    .expect("release");
            }
        }
        newly_failed
    }

    #[tokio::test]
    async fn a_failed_payload_waits_before_it_can_be_leased_again() {
        let (db, _dir) = test_client().await;
        db.insert_pending_symbolication(&pending("a"))
            .await
            .expect("insert");

        let (_, leased) = db
            .lease_pending_symbolications(10, Duration::from_secs(15 * 60))
            .await
            .expect("lease");
        assert_eq!(leased.len(), 1);

        db.release_lease_with_error("a", "boom")
            .await
            .expect("release");

        // Previously the release cleared the lease outright, so the very next
        // poll handed the same payload straight back and all three attempts
        // burned inside the same second.
        let (_, released) = db
            .lease_pending_symbolications(10, Duration::from_secs(15 * 60))
            .await
            .expect("lease again");
        assert!(
            released.is_empty(),
            "a just-failed payload must not be immediately re-leasable"
        );
    }

    #[tokio::test]
    async fn an_exhausted_payload_is_marked_failed_rather_than_stranded() {
        let (db, _dir) = test_client().await;
        db.insert_pending_symbolication(&pending("a"))
            .await
            .expect("insert");

        // Burn the attempt budget. The backoff means only the first lease
        // actually hands the row over, which is the point of the previous test;
        // clear it by hand between rounds so this one can reach exhaustion.
        for _ in 0..3 {
            sqlx::query!("UPDATE pending_symbolications SET retry_after_ms = NULL")
                .execute(&db.writer_pool)
                .await
                .expect("clear backoff");
            fail_n_times(&db, "a", 1).await;
        }

        // Out of attempts with the lease cleared, which matched neither the
        // dead-letter nor the lease predicate.
        sqlx::query!("UPDATE pending_symbolications SET retry_after_ms = NULL")
            .execute(&db.writer_pool)
            .await
            .expect("clear backoff");
        let (newly_failed, leased) = db
            .lease_pending_symbolications(10, Duration::from_secs(15 * 60))
            .await
            .expect("lease");

        assert!(leased.is_empty(), "an exhausted payload must not be leased");
        assert_eq!(
            newly_failed.len(),
            1,
            "an exhausted payload must be reported as failed"
        );
        assert_eq!(newly_failed[0].id, "a");
    }

    #[tokio::test]
    async fn reaping_only_takes_payloads_past_the_retention_window() {
        let (db, _dir) = test_client().await;
        for id in ["old", "recent"] {
            db.insert_pending_symbolication(&pending(id))
                .await
                .expect("insert");
        }

        // `old` failed well before the cutoff, `recent` just now.
        sqlx::query!("UPDATE pending_symbolications SET failed_at_ms = 1000 WHERE id = 'old'")
            .execute(&db.writer_pool)
            .await
            .expect("age old");
        sqlx::query!("UPDATE pending_symbolications SET failed_at_ms = 9000 WHERE id = 'recent'")
            .execute(&db.writer_pool)
            .await
            .expect("age recent");

        let expired = db.expired_failed_payloads(5000).await.expect("expired");
        assert_eq!(
            expired
                .iter()
                .map(|(id, _)| id.as_str())
                .collect::<Vec<_>>(),
            vec!["old"],
            "a payload inside the retention window must be kept"
        );

        // Once reaped it is not offered again, and it can no longer be
        // requeued - there is nothing left on disk to symbolicate.
        db.mark_payload_reaped("old").await.expect("mark");
        assert!(
            db.expired_failed_payloads(5000)
                .await
                .expect("expired")
                .is_empty()
        );
        assert!(
            db.failed_symbolication_ids(None)
                .await
                .expect("ids")
                .iter()
                .all(|id| id != "old")
        );
    }

    #[tokio::test]
    async fn requeue_returns_exhausted_payloads_matching_an_error() {
        let (db, _dir) = test_client().await;
        for id in ["deep", "other"] {
            db.insert_pending_symbolication(&pending(id))
                .await
                .expect("insert");
        }

        sqlx::query!(
            "UPDATE pending_symbolications
             SET attempts = 3, failed_at_ms = 99, last_error = 'recursion limit exceeded'
             WHERE id = 'deep'"
        )
        .execute(&db.writer_pool)
        .await
        .expect("fail deep");
        sqlx::query!(
            "UPDATE pending_symbolications
             SET attempts = 3, failed_at_ms = 99, last_error = 'payload missing on disk'
             WHERE id = 'other'"
        )
        .execute(&db.writer_pool)
        .await
        .expect("fail other");

        let candidates = db
            .failed_symbolication_ids(Some("recursion limit"))
            .await
            .expect("dry run");
        assert_eq!(candidates, vec!["deep".to_string()]);

        let requeued = db
            .requeue_failed_symbolications(Some("recursion limit"))
            .await
            .expect("requeue");
        assert_eq!(requeued.len(), 1);
        assert_eq!(requeued[0].id, "deep");

        // The requeued payload is leasable again; the unrelated failure is not.
        let (_, leased) = db
            .lease_pending_symbolications(10, Duration::from_secs(15 * 60))
            .await
            .expect("lease");
        let leased_ids: Vec<&str> = leased.iter().map(|row| row.id.as_str()).collect();
        assert_eq!(leased_ids, vec!["deep"]);

        // And an unfiltered dry run still sees the one left behind.
        assert_eq!(
            db.failed_symbolication_ids(None).await.expect("dry run"),
            vec!["other".to_string()]
        );
    }

    // -----------------------------------------------------------------------
    // App Attest storage
    // -----------------------------------------------------------------------

    fn attest_key(key_id: &str, user_id: &str) -> AttestKey {
        AttestKey {
            key_id: key_id.to_string(),
            public_key: vec![0x04; 65],
            user_id: user_id.to_string(),
            bundle_id: "com.msdrigg.roam".to_string(),
            environment: "production".to_string(),
            sign_count: 0,
            replay_window: 0,
            revoked_at_ms: None,
        }
    }

    fn session_for(key_id: Option<&str>, user_id: &str, expires_at_ms: i64) -> AppSession {
        AppSession {
            session_id: format!("sid-{user_id}"),
            key_id: key_id.map(str::to_string),
            user_id: user_id.to_string(),
            attested: key_id.is_some(),
            bundle_id: Some("com.msdrigg.roam".to_string()),
            expires_at_ms,
        }
    }

    #[tokio::test]
    async fn an_attested_key_round_trips() {
        let (db, _dir) = test_client().await;
        let key = attest_key("aa11", "aaa-bbb-ccc");
        db.register_attest_key(&key, b"receipt", 1_000)
            .await
            .expect("register");

        let stored = db
            .get_attest_key("aa11")
            .await
            .expect("read")
            .expect("present");
        assert_eq!(stored.user_id, "aaa-bbb-ccc");
        assert_eq!(stored.public_key, vec![0x04; 65]);
        assert_eq!(stored.bundle_id, "com.msdrigg.roam");
        assert_eq!(stored.sign_count, 0);
        assert!(stored.revoked_at_ms.is_none());
    }

    #[tokio::test]
    async fn a_key_keeps_the_install_id_it_first_claimed() {
        let (db, _dir) = test_client().await;
        db.register_attest_key(&attest_key("aa11", "original-id"), b"r", 1_000)
            .await
            .expect("first registration");

        // A second registration for the same key must not move it to another
        // conversation.
        let bound = db
            .register_attest_key(&attest_key("aa11", "someone-elses-id"), b"r", 2_000)
            .await
            .expect("second registration");

        assert_eq!(bound, "original-id");
        let stored = db.get_attest_key("aa11").await.unwrap().unwrap();
        assert_eq!(stored.user_id, "original-id");
    }

    #[tokio::test]
    async fn a_challenge_may_only_be_spent_once() {
        let (db, _dir) = test_client().await;
        db.issue_challenge("chal", 1_000, 9_000)
            .await
            .expect("issue");

        assert!(db.consume_challenge("chal", 2_000).await.expect("first"));
        assert!(
            !db.consume_challenge("chal", 2_001).await.expect("second"),
            "a spent challenge cannot be replayed"
        );
    }

    #[tokio::test]
    async fn an_expired_challenge_cannot_be_spent() {
        let (db, _dir) = test_client().await;
        db.issue_challenge("chal", 1_000, 5_000)
            .await
            .expect("issue");
        assert!(!db.consume_challenge("chal", 5_001).await.expect("expired"));
    }

    #[tokio::test]
    async fn an_unknown_challenge_is_refused() {
        let (db, _dir) = test_client().await;
        assert!(
            !db.consume_challenge("never-issued", 1)
                .await
                .expect("query")
        );
    }

    #[tokio::test]
    async fn a_session_is_readable_by_token_hash_until_it_expires() {
        let (db, _dir) = test_client().await;
        db.register_attest_key(&attest_key("aa11", "user"), b"r", 1_000)
            .await
            .unwrap();
        let session = session_for(Some("aa11"), "user", 10_000);
        db.create_session(b"hash-a", &session, 1_000)
            .await
            .expect("create");

        let found = db.get_session(b"hash-a", 9_999).await.expect("read");
        assert_eq!(found.expect("present").user_id, "user");

        assert!(
            db.get_session(b"hash-a", 10_000)
                .await
                .expect("read")
                .is_none(),
            "expiry is exclusive of the boundary"
        );
        assert!(
            db.get_session(b"wrong-hash", 1)
                .await
                .expect("read")
                .is_none()
        );
    }

    #[tokio::test]
    async fn revoking_a_key_drops_the_sessions_it_minted() {
        let (db, _dir) = test_client().await;
        db.register_attest_key(&attest_key("aa11", "user"), b"r", 1_000)
            .await
            .unwrap();
        db.create_session(b"hash-a", &session_for(Some("aa11"), "user", 99_000), 1_000)
            .await
            .unwrap();
        let mut other = session_for(None, "other", 99_000);
        other.session_id = "sid-other".to_string();
        db.create_session(b"hash-b", &other, 1_000).await.unwrap();

        assert_eq!(db.revoke_sessions_for_key("aa11").await.expect("revoke"), 1);
        assert!(db.get_session(b"hash-a", 2_000).await.unwrap().is_none());
        assert!(
            db.get_session(b"hash-b", 2_000).await.unwrap().is_some(),
            "an unrelated session survives"
        );
    }

    #[tokio::test]
    async fn recording_an_assertion_is_a_compare_and_set() {
        let (db, _dir) = test_client().await;
        db.register_attest_key(&attest_key("aa11", "user"), b"r", 1_000)
            .await
            .unwrap();

        assert!(
            db.record_assertion("aa11", (0, 0), (5, 1), 2_000)
                .await
                .expect("first"),
            "the state matched what the caller verified against"
        );

        assert!(
            !db.record_assertion("aa11", (0, 0), (6, 1), 3_000)
                .await
                .expect("stale"),
            "a caller working from stale state must not overwrite a newer counter"
        );

        let stored = db.get_attest_key("aa11").await.unwrap().unwrap();
        assert_eq!(stored.sign_count, 5);
        assert_eq!(stored.replay_window, 1);
    }

    #[tokio::test]
    async fn the_reaper_clears_only_expired_rows() {
        let (db, _dir) = test_client().await;
        db.issue_challenge("old", 0, 1_000).await.unwrap();
        db.issue_challenge("fresh", 0, 90_000).await.unwrap();
        db.create_session(b"old", &session_for(None, "a", 1_000), 0)
            .await
            .unwrap();
        let mut fresh = session_for(None, "b", 90_000);
        fresh.session_id = "sid-fresh".to_string();
        db.create_session(b"fresh", &fresh, 0).await.unwrap();

        let (sessions, challenges) = db.reap_expired_attest_state(50_000).await.expect("reap");
        assert_eq!((sessions, challenges), (1, 1));

        assert!(db.get_session(b"fresh", 60_000).await.unwrap().is_some());
        assert!(db.consume_challenge("fresh", 60_000).await.unwrap());
    }
}
