//! Request authentication for the app-facing API.
//!
//! Three kinds of caller reach these routes:
//!
//! - an **attested** session, minted after an App Attest registration and
//!   refreshed with an assertion, which is what current releases use;
//! - an **unattested** session, for the handful of devices with no Secure
//!   Enclave, held to a rate limit low enough to be useless for abuse;
//! - a **legacy** caller presenting the shared key that older releases ship,
//!   accepted until those releases age out.
//!
//! Mutating requests from an attested session must also carry a fresh Secure
//! Enclave assertion, so a session token lifted out of the app's memory cannot
//! send messages or upload on its own.

use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::Duration,
};

use axum::{
    body::Body,
    extract::{Request, State},
    http::{HeaderMap, Method},
    middleware::Next,
    response::Response,
};
use base64::{Engine, prelude::BASE64_STANDARD};
use rand::{TryRng, rngs::SysRng};
use sha2::{Digest, Sha256};

use crate::{
    AppContext,
    attest::{self, ReplayWindow},
    database::AppSession,
    server::{ApiError, UnauthorizedReason},
};

/// Client data an assertion signs. The client sends these exact bytes rather
/// than fields the server re-serialises, so neither side has to agree on a
/// canonical JSON encoding for the hash to match.
#[derive(Debug, serde::Deserialize)]
pub struct AssertionClientData {
    /// Session the assertion is bound to.
    pub s: String,
    /// HTTP method.
    pub m: String,
    /// Request path.
    pub p: String,
    /// Unix milliseconds.
    pub t: i64,
}

/// How far an assertion's timestamp may sit from the server clock.
const ASSERTION_SKEW: Duration = Duration::from_secs(120);

const HEADER_ASSERTION: &str = "x-roam-assertion";
const HEADER_CLIENT_DATA: &str = "x-roam-client-data";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CallerKind {
    Attested { key_id: String },
    Unattested,
    Legacy,
}

/// Who is making the request, resolved once by the middleware and read by
/// handlers through `Extension<Caller>`.
#[derive(Debug, Clone)]
pub struct Caller {
    pub kind: CallerKind,
    /// Install id this caller is bound to. A legacy caller has none, which is
    /// exactly the gap attestation closes.
    pub user_id: Option<String>,
}

impl Caller {
    /// Rejects a request that names someone else's conversation.
    ///
    /// A legacy caller carries no binding and keeps the old behaviour of
    /// addressing any install id, because the releases that send that key have
    /// no way to prove which install they are.
    pub fn authorize_user(&self, requested: &str) -> Result<(), ApiError> {
        match &self.user_id {
            None => Ok(()),
            Some(bound) if bound == requested => Ok(()),
            Some(bound) => {
                tracing::warn!(
                    bound_user_id = %bound,
                    requested_user_id = %requested,
                    "Session tried to address another install's conversation"
                );
                Err(ApiError::Unauthorized(
                    "Session is not bound to that user".to_string(),
                ))
            }
        }
    }

    pub fn is_attested(&self) -> bool {
        matches!(self.kind, CallerKind::Attested { .. })
    }
}

/// Fixed-window request counter, keyed by caller and bucket.
///
/// Fixed rather than sliding because the limits here are coarse (a handful of
/// requests an hour) and a caller who games a window boundary gains one extra
/// window's worth, which none of these buckets care about.
#[derive(Clone, Default)]
pub struct RateLimiter {
    buckets: Arc<Mutex<HashMap<String, Vec<i64>>>>,
}

impl RateLimiter {
    /// Records a hit and reports whether it is within `limit` for `window`.
    pub fn check(&self, key: &str, limit: u32, window: Duration, now_ms: i64) -> bool {
        let cutoff = now_ms - window.as_millis() as i64;
        let mut buckets = match self.buckets.lock() {
            Ok(guard) => guard,
            // A poisoned lock means a panic while holding it. Failing open on a
            // rate limiter is worse than failing closed.
            Err(poisoned) => poisoned.into_inner(),
        };

        // Bounded sweep so an abandoned key does not sit in the map forever.
        if buckets.len() > 4096 {
            buckets.retain(|_, hits| hits.iter().any(|hit| *hit > cutoff));
        }

        let hits = buckets.entry(key.to_string()).or_default();
        hits.retain(|hit| *hit > cutoff);
        if hits.len() as u32 >= limit {
            return false;
        }
        hits.push(now_ms);
        true
    }
}

/// Best-effort client address for rate limiting.
///
/// Fly terminates TLS and sets `Fly-Client-IP`; the forwarded header is a
/// fallback for local runs. Neither is trustworthy on its own, which is why
/// these buckets only ever gate the unattested paths.
pub fn client_ip(headers: &HeaderMap) -> String {
    headers
        .get("fly-client-ip")
        .or_else(|| headers.get("x-forwarded-for"))
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.split(',').next())
        .map(|value| value.trim().to_string())
        .unwrap_or_else(|| "unknown".to_string())
}

pub fn now_ms() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

/// 32 bytes of OS randomness, hex encoded.
pub fn random_token() -> String {
    let mut bytes = [0u8; 32];
    SysRng
        .try_fill_bytes(&mut bytes)
        .expect("OS random number generator is available");
    hex(&bytes)
}

pub fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn hash_token(token: &str) -> Vec<u8> {
    Sha256::digest(token.as_bytes()).to_vec()
}

/// Mints a session and returns the bearer token, which is never stored.
pub async fn mint_session(
    app_context: &AppContext,
    user_id: &str,
    key_id: Option<String>,
    bundle_id: Option<String>,
    attested: bool,
) -> Result<(String, AppSession), ApiError> {
    let token = random_token();
    let issued_at_ms = now_ms();
    let session = AppSession {
        session_id: random_token(),
        key_id,
        user_id: user_id.to_string(),
        attested,
        bundle_id,
        expires_at_ms: issued_at_ms + app_context.app_session_ttl().as_millis() as i64,
    };
    app_context
        .db_client()
        .create_session(&hash_token(&token), &session, issued_at_ms)
        .await
        .map_err(ApiError::DatabaseError)?;
    Ok((token, session))
}

fn header<'a>(headers: &'a HeaderMap, name: &str) -> Option<&'a str> {
    headers.get(name).and_then(|value| value.to_str().ok())
}

/// Routes that create something durable: a Discord post, a symbolication job, a
/// push registration.
///
/// Only these carry the assertion requirement and the rate limit. Classifying
/// by HTTP method instead would sweep in `/typing`, which the app posts every
/// five seconds while someone is composing, and polling, which it repeats every
/// ten to sixty seconds. Neither costs anything to replay, and putting a Secure
/// Enclave signature on a five-second timer is the assertion volume Apple warns
/// against.
fn requires_proof(path: &str) -> bool {
    matches!(
        path,
        "/v2/new-message" | "/new-message" | "/v2/upload-diagnostics" | "/new-apns"
    ) || path.starts_with("/upload-diagnostics/")
}

/// Hourly ceiling per class of route.
///
/// Every route is metered, but the ceilings differ by two orders of magnitude
/// because the traffic does: the app posts a typing notice every five seconds
/// (720/hour) and polls every ten to sixty (up to 360/hour), while a person
/// sends a handful of messages an hour. The wide ceilings are not spam control,
/// they are a backstop against a client stuck in a loop; the message budget is
/// the spam control.
///
/// Diagnostics sits high on purpose. Every shipped `MetricManager` deletes its
/// cached payload whatever the response says, so a 429 there loses a crash
/// report rather than deferring it. The ceiling has to sit far above any real
/// backlog, which the client already bounds at ten files and 31 days.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Budget {
    Messages,
    Diagnostics,
    Push,
    Typing,
    Reads,
}

const DIAGNOSTICS_HOURLY_LIMIT: u32 = 200;
const PUSH_HOURLY_LIMIT: u32 = 60;
const TYPING_HOURLY_LIMIT: u32 = 2_000;
const READ_HOURLY_LIMIT: u32 = 2_000;

/// Legacy callers are bucketed per address when the path does not name an
/// install, so the low-volume classes have to tolerate several subscribers
/// sharing one carrier NAT address.
const LEGACY_NAT_FACTOR: u32 = 5;

impl Budget {
    fn label(self) -> &'static str {
        match self {
            Self::Messages => "messages",
            Self::Diagnostics => "diagnostics",
            Self::Push => "push",
            Self::Typing => "typing",
            Self::Reads => "reads",
        }
    }

    fn refusal(self) -> &'static str {
        match self {
            Self::Messages => "Too many messages in the last hour",
            _ => "Too many requests in the last hour",
        }
    }
}

fn budget_for(path: &str) -> Budget {
    match path {
        "/v2/new-message" | "/new-message" => Budget::Messages,
        "/v2/upload-diagnostics" => Budget::Diagnostics,
        "/new-apns" => Budget::Push,
        p if p.starts_with("/upload-diagnostics/") => Budget::Diagnostics,
        p if p.starts_with("/typing/") => Budget::Typing,
        _ => Budget::Reads,
    }
}

/// The install id a path names.
///
/// The three highest-volume routes carry it, which lets a legacy caller be
/// bucketed per install rather than per address. Without that, one carrier NAT
/// address would put every subscriber behind it into a single typing bucket.
fn path_user_id(path: &str) -> Option<&str> {
    ["/typing/", "/updates/", "/messages/"]
        .iter()
        .find_map(|prefix| path.strip_prefix(prefix))
        .filter(|rest| !rest.is_empty() && !rest.contains('/'))
}

/// Applies the ceiling for `path` to `subject`.
fn enforce_budget(
    app_context: &AppContext,
    path: &str,
    subject: &str,
    legacy: bool,
    now: i64,
) -> Result<(), ApiError> {
    let budget = budget_for(path);
    let base = match budget {
        Budget::Messages if legacy => app_context.legacy_hourly_limit(),
        Budget::Messages => app_context.message_hourly_limit(),
        Budget::Diagnostics => DIAGNOSTICS_HOURLY_LIMIT,
        Budget::Push => PUSH_HOURLY_LIMIT,
        Budget::Typing => TYPING_HOURLY_LIMIT,
        Budget::Reads => READ_HOURLY_LIMIT,
    };
    // A legacy caller bucketed by address covers several people; one bucketed
    // by the install it names does not.
    let limit = if legacy && budget != Budget::Messages && path_user_id(path).is_none() {
        base.saturating_mul(LEGACY_NAT_FACTOR)
    } else {
        base
    };

    if app_context.rate_limiter().check(
        &format!("{}:{subject}", budget.label()),
        limit,
        Duration::from_secs(3600),
        now,
    ) {
        return Ok(());
    }

    tracing::warn!(%path, budget = budget.label(), limit, "Refused a request over its hourly ceiling");
    Err(ApiError::RateLimited(budget.refusal().to_string()))
}

/// Authenticates every app-facing route.
pub async fn app_auth(
    State(app_context): State<AppContext>,
    request: Request,
    next: Next,
) -> Result<Response, ApiError> {
    let headers = request.headers().clone();
    let method = request.method().clone();
    let path = request.uri().path().to_string();
    let now = now_ms();

    let bearer = header(&headers, "authorization")
        .and_then(|value| value.strip_prefix("Bearer "))
        .map(str::to_string);

    let caller = match bearer {
        Some(token) => {
            authenticate_session(&app_context, &token, &headers, &method, &path, now).await?
        }
        None => authenticate_legacy(&app_context, &headers, &path, now)?,
    };

    let mut request = request;
    request.extensions_mut().insert(caller);
    Ok(next.run(request).await)
}

async fn authenticate_session(
    app_context: &AppContext,
    token: &str,
    headers: &HeaderMap,
    method: &Method,
    path: &str,
    now: i64,
) -> Result<Caller, ApiError> {
    let session = app_context
        .db_client()
        .get_session(&hash_token(token), now)
        .await
        .map_err(ApiError::DatabaseError)?
        .ok_or_else(|| {
            ApiError::unauthorized(
                UnauthorizedReason::SessionInvalid,
                "Session is unknown or expired",
            )
        })?;

    if !session.attested {
        enforce_budget(
            app_context,
            path,
            &format!("unattested:{}", session.user_id),
            false,
            now,
        )?;
        // Only for durable routes: the unattested branch also serves polling
        // and typing, which would bury this at hundreds of lines an hour.
        if requires_proof(path) {
            tracing::info!(
                user_id = %session.user_id,
                %path,
                "Served a durable request from an unattested session"
            );
        }
        return Ok(Caller {
            kind: CallerKind::Unattested,
            user_id: Some(session.user_id),
        });
    }

    let key_id = session.key_id.clone().ok_or_else(|| {
        ApiError::unauthorized(
            UnauthorizedReason::SessionInvalid,
            "Attested session has no key",
        )
    })?;

    // Polling and typing are bearer-only, so the Secure Enclave stays off the
    // paths the app walks every few seconds. Anything durable proves the key.
    if requires_proof(path) {
        verify_request_assertion(app_context, &session, &key_id, headers, method, path, now)
            .await?;
        tracing::info!(
            %key_id,
            user_id = %session.user_id,
            %path,
            "Verified an App Attest assertion"
        );
    }

    Ok(Caller {
        kind: CallerKind::Attested { key_id },
        user_id: Some(session.user_id),
    })
}

async fn verify_request_assertion(
    app_context: &AppContext,
    session: &AppSession,
    key_id: &str,
    headers: &HeaderMap,
    method: &Method,
    path: &str,
    now: i64,
) -> Result<(), ApiError> {
    let assertion = header(headers, HEADER_ASSERTION).ok_or_else(|| {
        ApiError::unauthorized(
            UnauthorizedReason::AssertionMissing,
            format!("{HEADER_ASSERTION} is required on this request"),
        )
    })?;
    let client_data_b64 = header(headers, HEADER_CLIENT_DATA).ok_or_else(|| {
        ApiError::unauthorized(
            UnauthorizedReason::AssertionMissing,
            format!("{HEADER_CLIENT_DATA} is required on this request"),
        )
    })?;

    let assertion = BASE64_STANDARD.decode(assertion).map_err(|_| {
        ApiError::unauthorized(
            UnauthorizedReason::AssertionInvalid,
            "Assertion is not valid base64",
        )
    })?;
    let client_data = BASE64_STANDARD.decode(client_data_b64).map_err(|_| {
        ApiError::unauthorized(
            UnauthorizedReason::AssertionInvalid,
            "Client data is not valid base64",
        )
    })?;

    let key = app_context
        .db_client()
        .get_attest_key(key_id)
        .await
        .map_err(ApiError::DatabaseError)?
        .ok_or_else(|| {
            ApiError::unauthorized(UnauthorizedReason::KeyUnknown, "Attested key is unknown")
        })?;
    if key.revoked_at_ms.is_some() {
        return Err(ApiError::unauthorized(
            UnauthorizedReason::KeyRevoked,
            "Attested key was revoked",
        ));
    }

    let verified = attest::verify_assertion(
        &assertion,
        &key.public_key,
        &client_data,
        app_context.attest_policy(),
        &key.bundle_id,
    )
    .map_err(|err| {
        tracing::warn!(%key_id, ?err, "Rejected request assertion");
        ApiError::unauthorized(
            UnauthorizedReason::AssertionInvalid,
            "Assertion is not valid",
        )
    })?;

    // The signature proves the key signed these bytes; the fields prove it
    // signed *this* request rather than a different one from the same app.
    let parsed: AssertionClientData = serde_json::from_slice(&client_data).map_err(|_| {
        ApiError::unauthorized(
            UnauthorizedReason::AssertionInvalid,
            "Client data is not the expected shape",
        )
    })?;
    if parsed.s != session.session_id {
        return Err(ApiError::unauthorized(
            UnauthorizedReason::AssertionMismatch,
            "Assertion is bound to another session",
        ));
    }
    if parsed.m != method.as_str() || parsed.p != path {
        return Err(ApiError::unauthorized(
            UnauthorizedReason::AssertionMismatch,
            "Assertion does not cover this request",
        ));
    }
    if (now - parsed.t).abs() > ASSERTION_SKEW.as_millis() as i64 {
        return Err(ApiError::unauthorized(
            UnauthorizedReason::AssertionMismatch,
            "Assertion timestamp is outside the accepted skew",
        ));
    }

    commit_counter(
        app_context,
        key_id,
        key.sign_count,
        key.replay_window,
        verified.counter,
        now,
    )
    .await
}

/// Folds an accepted counter into the stored replay window.
///
/// The update is a compare-and-set against the state that was verified, so two
/// assertions committing at once cannot lose one of the two counters. A lost
/// race is retried against freshly read state rather than failing the request.
pub async fn commit_counter(
    app_context: &AppContext,
    key_id: &str,
    mut sign_count: i64,
    mut replay_window: i64,
    counter: u32,
    now: i64,
) -> Result<(), ApiError> {
    for _ in 0..4 {
        let mut window = ReplayWindow::from_storage(sign_count, replay_window);
        window.accept(counter).map_err(|err| {
            tracing::warn!(%key_id, counter, ?err, "Rejected replayed assertion counter");
            ApiError::unauthorized(
                UnauthorizedReason::AssertionReplayed,
                "Assertion counter was already used",
            )
        })?;

        let next = window.to_storage();
        let committed = app_context
            .db_client()
            .record_assertion(key_id, (sign_count, replay_window), next, now)
            .await
            .map_err(ApiError::DatabaseError)?;
        if committed {
            return Ok(());
        }

        let key = app_context
            .db_client()
            .get_attest_key(key_id)
            .await
            .map_err(ApiError::DatabaseError)?
            .ok_or_else(|| {
                ApiError::unauthorized(UnauthorizedReason::KeyUnknown, "Attested key is unknown")
            })?;
        sign_count = key.sign_count;
        replay_window = key.replay_window;
    }

    // Losing this race four times running says the row is contended, not that
    // the caller's key is bad -- so it must not read as "re-register".
    Err(ApiError::unauthorized(
        UnauthorizedReason::Transient,
        "Could not record the assertion counter",
    ))
}

fn authenticate_legacy(
    app_context: &AppContext,
    headers: &HeaderMap,
    path: &str,
    now: i64,
) -> Result<Caller, ApiError> {
    let Some(expected) = app_context.legacy_app_api_key() else {
        return Err(ApiError::Unauthorized(
            "This endpoint requires an attested session".to_string(),
        ));
    };
    let presented = header(headers, "x-api-key").unwrap_or_default();
    if presented.is_empty() || presented != expected {
        return Err(ApiError::Unauthorized("Unauthorized".to_string()));
    }

    // A release predating attestation cannot prove which install it is, so it
    // is bucketed by the install its path names where there is one, and by
    // address otherwise. The ceilings still have to clear real client traffic:
    // capping polling or typing would break the very installs this key exists
    // to keep working.
    let subject = match path_user_id(path) {
        Some(user_id) => format!("legacy-user:{user_id}"),
        None => format!("legacy-ip:{}", client_ip(headers)),
    };
    enforce_budget(app_context, path, &subject, true, now)?;

    Ok(Caller {
        kind: CallerKind::Legacy,
        user_id: None,
    })
}

/// Guards the crash and symbolication routes, which no app build ever calls.
pub async fn crash_auth(
    State(app_context): State<AppContext>,
    request: Request<Body>,
    next: Next,
) -> Result<Response, ApiError> {
    let presented = header(request.headers(), "x-api-key").unwrap_or_default();
    if presented.is_empty() || presented != app_context.crash_api_key() {
        return Err(ApiError::Unauthorized("Unauthorized".to_string()));
    }
    Ok(next.run(request).await)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_bound_session_may_only_address_its_own_user() {
        let caller = Caller {
            kind: CallerKind::Attested {
                key_id: "abc".into(),
            },
            user_id: Some("aaa-bbb-ccc".into()),
        };
        caller.authorize_user("aaa-bbb-ccc").expect("its own id");
        assert!(caller.authorize_user("xxx-yyy-zzz").is_err());
    }

    #[test]
    fn a_legacy_caller_keeps_the_old_unbound_behaviour() {
        let caller = Caller {
            kind: CallerKind::Legacy,
            user_id: None,
        };
        caller
            .authorize_user("anyone-at-all")
            .expect("older releases cannot prove which install they are");
    }

    #[test]
    fn the_rate_limiter_admits_exactly_the_limit() {
        let limiter = RateLimiter::default();
        let window = Duration::from_secs(3600);
        for i in 0..5 {
            assert!(
                limiter.check("k", 5, window, 1_000 + i),
                "hit {i} is within"
            );
        }
        assert!(!limiter.check("k", 5, window, 1_006));
    }

    #[test]
    fn the_rate_limiter_forgets_hits_older_than_the_window() {
        let limiter = RateLimiter::default();
        let window = Duration::from_secs(60);
        assert!(limiter.check("k", 1, window, 0));
        assert!(!limiter.check("k", 1, window, 30_000));
        assert!(
            limiter.check("k", 1, window, 61_000),
            "the first hit aged out"
        );
    }

    #[test]
    fn rate_limit_buckets_are_independent() {
        let limiter = RateLimiter::default();
        let window = Duration::from_secs(3600);
        assert!(limiter.check("a", 1, window, 0));
        assert!(!limiter.check("a", 1, window, 1));
        assert!(
            limiter.check("b", 1, window, 2),
            "a different key is untouched"
        );
    }

    /// The numbers here are measured from the app, not invented: `MessagingView`
    /// throttles typing to one post per 5s (720/hour) and polls every 10 to 60s
    /// (up to 360/hour). An earlier cut metered both and capped writes at 10 an
    /// hour, which silently broke every conversation in the field.
    #[test]
    fn an_hour_of_typing_and_polling_is_never_metered() {
        let limiter = RateLimiter::default();
        let window = Duration::from_secs(3600);

        for tick in 0..720i64 {
            let path = "/typing/aaa-bbb-ccc";
            assert!(!requires_proof(path));
            // Nothing consults the limiter for these, but prove that even if it
            // did the budget would not be the thing that broke them.
            assert!(limiter.check("typing", 2000, window, tick * 5_000));
        }
        for tick in 0..360i64 {
            assert!(!requires_proof("/updates/aaa-bbb-ccc"));
            assert!(limiter.check("polling", 2000, window, tick * 10_000));
        }
    }

    /// Every route now has a ceiling, but they are not the same ceiling. A 429
    /// on diagnostics is not a delay, it is data loss: `MetricManager` deletes
    /// the cached payload whatever the response says, and that code is already
    /// in the field where it cannot be fixed. So diagnostics is metered far
    /// above any real backlog, which the client itself bounds at ten files.
    #[test]
    fn every_route_lands_in_a_budget() {
        assert!(matches!(budget_for("/v2/new-message"), Budget::Messages));
        assert!(matches!(budget_for("/new-message"), Budget::Messages));
        assert!(matches!(
            budget_for("/v2/upload-diagnostics"),
            Budget::Diagnostics
        ));
        assert!(matches!(
            budget_for("/upload-diagnostics/aaa-bbb-ccc-2026"),
            Budget::Diagnostics
        ));
        assert!(matches!(budget_for("/new-apns"), Budget::Push));
        assert!(matches!(budget_for("/typing/aaa-bbb-ccc"), Budget::Typing));
        assert!(matches!(budget_for("/updates/aaa-bbb-ccc"), Budget::Reads));
        assert!(matches!(budget_for("/messages/aaa"), Budget::Reads));
    }

    #[test]
    fn the_high_volume_routes_clear_real_client_traffic() {
        // Measured from the app: typing is one post per 5s and polling is one
        // per 10s at its fastest.
        const { assert!(TYPING_HOURLY_LIMIT > 720, "an hour of composing must fit") };
        const { assert!(READ_HOURLY_LIMIT > 360, "an hour of polling must fit") };
        const {
            assert!(
                DIAGNOSTICS_HOURLY_LIMIT > 10,
                "the client caches at most ten payloads before pruning"
            )
        };
    }

    #[test]
    fn a_legacy_caller_is_bucketed_per_install_where_the_path_names_one() {
        // Otherwise one carrier NAT address puts every subscriber behind it
        // into a single typing bucket.
        assert_eq!(path_user_id("/typing/aaa-bbb-ccc"), Some("aaa-bbb-ccc"));
        assert_eq!(path_user_id("/updates/aaa-bbb-ccc"), Some("aaa-bbb-ccc"));
        assert_eq!(path_user_id("/messages/aaa-bbb-ccc"), Some("aaa-bbb-ccc"));
        assert_eq!(path_user_id("/v2/new-message"), None);
        assert_eq!(path_user_id("/typing/"), None);
        assert_eq!(path_user_id("/typing/a/b"), None);
    }

    #[test]
    fn a_busy_support_conversation_fits_in_every_budget() {
        let limiter = RateLimiter::default();
        let window = Duration::from_secs(3600);
        // Twenty messages plus a crash upload burst inside one hour.
        for i in 0..30i64 {
            assert!(
                limiter.check("attested:user", 60, window, i * 60_000),
                "message {i} should not be throttled"
            );
        }
    }

    #[test]
    fn the_client_ip_prefers_flys_header() {
        let mut headers = HeaderMap::new();
        headers.insert("x-forwarded-for", "10.0.0.1, 10.0.0.2".parse().unwrap());
        assert_eq!(client_ip(&headers), "10.0.0.1");
        headers.insert("fly-client-ip", "203.0.113.7".parse().unwrap());
        assert_eq!(client_ip(&headers), "203.0.113.7");
    }

    #[test]
    fn only_durable_writes_need_proof() {
        for path in [
            "/v2/new-message",
            "/new-message",
            "/v2/upload-diagnostics",
            "/new-apns",
            "/upload-diagnostics/aaa-bbb-ccc-2026",
        ] {
            assert!(requires_proof(path), "{path} creates something durable");
        }
    }

    #[test]
    fn polling_and_typing_are_exempt() {
        // The app polls every 10 to 60 seconds and posts a typing notice every
        // 5 seconds while composing. Metering either, or signing it, breaks an
        // ordinary conversation.
        for path in [
            "/updates/aaa-bbb-ccc",
            "/messages/aaa-bbb-ccc",
            "/typing/aaa-bbb-ccc",
        ] {
            assert!(!requires_proof(path), "{path} is sent on a timer");
        }
    }

    #[test]
    fn tokens_are_not_stored_in_the_clear() {
        let token = random_token();
        assert_eq!(token.len(), 64, "32 bytes hex encoded");
        assert_ne!(hash_token(&token), token.as_bytes());
        assert_eq!(hash_token(&token), hash_token(&token));
        assert_ne!(hash_token(&token), hash_token(&random_token()));
    }
}
