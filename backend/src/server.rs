use std::{path::PathBuf, time::Duration};

use crate::{
    database::{DeviceInfo, PendingSymbolication, User, UserUpdate},
    discord::{
        DiscordAuthor, DiscordFile, DiscordFileUpload, DiscordMessageOptions, SUPPORT_ONLY_PREFIX,
        support_only,
    },
    presence::UserPresenceInfo,
    symbolicate::{DsymUploadMetadata, RoamDebugInfo, scan_binary_uuids},
    utils::{i64_to_string, string_to_i64_optional},
};
use anyhow::Context;
use axum::{
    Extension, Json,
    body::{Body, to_bytes},
    extract::{DefaultBodyLimit, Multipart, Path, Query, State},
    http::{HeaderName, Request, StatusCode, header},
    response::{IntoResponse, Response},
    routing::post,
};
use axum::{Router, routing::get, serve::ListenerExt};
use base64::{Engine, prelude::BASE64_STANDARD};
#[cfg(test)]
use clap::Parser;
pub use error::{ApiError, UnauthorizedReason};
use futures::{StreamExt, stream};
use opentelemetry::trace::{SpanKind, TraceContextExt};
use serde::{Deserialize, Serialize};
use tokio::{io::AsyncWriteExt, net::TcpListener, task::JoinHandle};
use tokio_util::io::ReaderStream;
use tower_http::{
    catch_panic::CatchPanicLayer,
    cors::{AllowHeaders, AllowMethods, AllowOrigin, CorsLayer},
    request_id::{MakeRequestId, PropagateRequestIdLayer, RequestId, SetRequestIdLayer},
    trace::{DefaultOnFailure, DefaultOnRequest, DefaultOnResponse, TraceLayer},
};
use tracing::{Level, Span};
use tracing_opentelemetry::OpenTelemetrySpanExt;
use uuid::Uuid;

/// How long a leased payload stays out before another worker can re-claim it.
const LEASE_TTL: Duration = Duration::from_secs(15 * 60);

use crate::{AppContext, auth::Caller, discord::DiscordMessage};

const UPLOAD_LIMIT: usize = 10 * 1024 * 1024;

/// Ceiling for a streamed dSYM upload. Enforced while writing to disk rather than
/// by `DefaultBodyLimit`, which would buffer the body in memory.
const MAX_DSYM_UPLOAD_BYTES: u64 = 2 * 1024 * 1024 * 1024;

pub async fn start_server(
    app_context: AppContext,
) -> anyhow::Result<JoinHandle<anyhow::Result<()>>> {
    let port = app_context.port;
    let router = build_app(app_context);
    let router = router.clone();
    let future = async move {
        let tcp_listener = TcpListener::bind(format!("0.0.0.0:{port}"))
            .await
            .context(format!("Error binding to port {port}"))?
            .tap_io(|tcp_stream| {
                if let Err(err) = tcp_stream.set_nodelay(true) {
                    tracing::info!("failed to set TCP_NODELAY on incoming connection: {err:#}");
                }
            });

        let server = axum::serve(tcp_listener, router.into_make_service());
        server.await.context("error running HTTP server")?;
        anyhow::Result::Ok(())
    };

    tokio::task::Builder::new()
        .name("http-server")
        .spawn(future)
        .context("Error spawning http server")
}

fn build_app(app_context: AppContext) -> Router {
    let x_request_id: axum::http::HeaderName = HeaderName::from_static("x-request-id");

    let cors = CorsLayer::new()
        .allow_headers(AllowHeaders::mirror_request())
        .allow_methods(AllowMethods::mirror_request())
        .allow_origin(AllowOrigin::mirror_request());

    router(app_context.clone())
        .layer(
            TraceLayer::new_for_http()
                .make_span_with(|request: &Request<Body>| {
                    tracing::span!(
                        Level::DEBUG,
                        "request",
                        "otel.name" = %format!("{}: {}", request.method(), request.uri().path()),
                        "otel.kind" = ?SpanKind::Server,
                        method = %request.method(),
                        uri = %request.uri(),
                        version = ?request.version(),
                        headers = ?request.headers(),
                    )
                })
                .on_failure(DefaultOnFailure::default().level(Level::WARN))
                .on_request(DefaultOnRequest::new().level(Level::DEBUG))
                .on_response(
                    DefaultOnResponse::new()
                        .level(Level::DEBUG)
                        .include_headers(true),
                ),
        )
        .layer(SetRequestIdLayer::new(
            x_request_id.clone(),
            OpenTelemetryRequestId,
        ))
        .layer(cors)
        .layer(PropagateRequestIdLayer::new(x_request_id))
        .layer(CatchPanicLayer::new())
        .layer(DefaultBodyLimit::max(
            1024 * 1024 * 70, // 70 MB
        ))
}

// A `MakeRequestId` that increments an atomic counter
#[derive(Clone, Default)]
struct OpenTelemetryRequestId;

impl MakeRequestId for OpenTelemetryRequestId {
    fn make_request_id<B>(&mut self, _: &Request<B>) -> Option<RequestId> {
        let id: Uuid = get_current_trace_id();
        let request_id = id.as_simple().to_string().parse().unwrap();

        Some(RequestId::new(request_id))
    }
}

fn get_current_trace_id() -> Uuid {
    let trace_id = Span::current().context().span().span_context().trace_id();
    Uuid::from_bytes(trace_id.to_bytes())
}

/// The API is split into three zones by who is allowed to call them.
///
/// `public` is unauthenticated: health, and the attestation handshake a client
/// has to complete before it holds any credential. `crash` is the internal
/// tooling key, which no app build ever carries. `app` is everything the app
/// calls, behind an attested session or, for older releases, the legacy key.
fn router(app_context: AppContext) -> Router {
    let public = Router::new()
        .route("/health", get(|| async { "Healthy!" }))
        .route("/", get(|| async { "Hello, world!" }))
        .route("/v3/attest/challenge", post(attest_challenge))
        .route("/v3/attest/register", post(attest_register))
        .route("/v3/attest/session", post(attest_session))
        .route("/v3/attest/unattested", post(attest_unattested_session));

    let crash = Router::new()
        // Crash review tracking.
        .route("/v2/crashes", get(list_crashes))
        .route("/v2/crashes/rules", get(list_crash_rules))
        .route("/v2/crashes/{thread_id}", get(get_crash))
        .route(
            "/v2/crashes/{thread_id}/review",
            post(review_crash).delete(unreview_crash),
        )
        // Discord proxy. Lets the crash key read threads, messages and
        // attachments without ever handling a bot token.
        .route("/v2/discord/threads", get(list_discord_threads))
        .route(
            "/v2/discord/threads/{thread_id}/messages",
            get(list_discord_messages).post(post_discord_message),
        )
        .route(
            "/v2/discord/threads/{thread_id}/messages/{message_id}",
            get(get_discord_message),
        )
        .route(
            "/v2/discord/threads/{thread_id}/messages/{message_id}/attachments/{attachment_id}",
            get(stream_discord_attachment),
        )
        .route("/v2/symbolicate/lease", get(lease_pending_symbolications))
        .route("/v2/symbolicate/dsym/{uuid}", get(get_dsym_by_uuid))
        .route("/v2/symbolicate/result", post(submit_symbolication_result))
        .route("/v2/symbolicate/requeue", post(requeue_symbolications))
        // Streams to disk, so the global 70 MB body limit must not apply here.
        .route(
            "/v2/upload-roam-dsym",
            post(upload_roam_dsym).layer(DefaultBodyLimit::disable()),
        )
        .route("/user-info/{user_id}", get(get_user_info))
        .route("/thread-info/{thread_id}", get(get_thread_info))
        .layer(axum::middleware::from_fn_with_state(
            app_context.clone(),
            crate::auth::crash_auth,
        ));

    let app = Router::new()
        .route("/messages/{user_id}", get(get_user_messages))
        .route("/updates/{user_id}", get(get_user_state))
        .route("/new-message", post(new_message_old))
        .route("/v2/new-message", post(new_message))
        .route("/v2/upload-diagnostics", post(upload_metric_diagnostics))
        .route("/new-apns", post(new_apns))
        .route(
            "/upload-diagnostics/{diagnostic_key}",
            post(upload_diagnostics),
        )
        .route("/typing/{user_id}", post(update_user_typing))
        .layer(axum::middleware::from_fn_with_state(
            app_context.clone(),
            crate::auth::app_auth,
        ));

    public.merge(crash).merge(app).with_state(app_context)
}

// ---------------------------------------------------------------------------
// App Attest handshake
// ---------------------------------------------------------------------------

/// How long a challenge stays spendable.
const CHALLENGE_TTL: Duration = Duration::from_secs(5 * 60);

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ChallengeResponse {
    challenge: String,
    expires_at_ms: i64,
}

/// Hands out a single-use challenge.
///
/// Unauthenticated by necessity: a client that has never attested holds no
/// credential to present here, so the only control available is the rate limit.
async fn attest_challenge(
    State(app_context): State<AppContext>,
    headers: axum::http::HeaderMap,
) -> Result<Json<ChallengeResponse>, ApiError> {
    let now = crate::auth::now_ms();
    let ip = crate::auth::client_ip(&headers);
    if !app_context.rate_limiter().check(
        &format!("challenge:{ip}"),
        60,
        Duration::from_secs(3600),
        now,
    ) {
        return Err(ApiError::RateLimited("Too many challenges".to_string()));
    }

    let challenge = crate::auth::random_token();
    let expires_at_ms = now + CHALLENGE_TTL.as_millis() as i64;
    app_context
        .db_client()
        .issue_challenge(&challenge, now, expires_at_ms)
        .await
        .map_err(ApiError::DatabaseError)?;

    Ok(Json(ChallengeResponse {
        challenge,
        expires_at_ms,
    }))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RegisterRequest {
    /// The key identifier `DCAppAttestService.generateKey` returned, base64 as
    /// the framework hands it over.
    key_id: String,
    /// Base64 of the CBOR attestation object.
    attestation: String,
    challenge: String,
    /// Install id this device wants to own. Honoured only the first time a key
    /// registers; the response carries whatever the key is actually bound to.
    user_id: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SessionResponse {
    token: String,
    session_id: String,
    /// The install id the caller is bound to, which after a reinstall is the
    /// one already on file rather than the one the client just generated.
    user_id: String,
    expires_at_ms: i64,
    attested: bool,
}

async fn attest_register(
    State(app_context): State<AppContext>,
    headers: axum::http::HeaderMap,
    Json(request): Json<RegisterRequest>,
) -> Result<Json<SessionResponse>, ApiError> {
    let now = crate::auth::now_ms();
    let ip = crate::auth::client_ip(&headers);
    if !app_context.rate_limiter().check(
        &format!("register:{ip}"),
        20,
        Duration::from_secs(3600),
        now,
    ) {
        return Err(ApiError::RateLimited("Too many registrations".to_string()));
    }

    if !app_context
        .db_client()
        .consume_challenge(&request.challenge, now)
        .await
        .map_err(ApiError::DatabaseError)?
    {
        return Err(ApiError::unauthorized(
            UnauthorizedReason::ChallengeInvalid,
            "Challenge is unknown, spent, or expired",
        ));
    }

    let key_id = BASE64_STANDARD
        .decode(&request.key_id)
        .map_err(|_| ApiError::BadRequest("keyId is not valid base64".to_string()))?;
    let attestation = BASE64_STANDARD
        .decode(&request.attestation)
        .map_err(|_| ApiError::BadRequest("attestation is not valid base64".to_string()))?;

    let verified = crate::attest::verify_attestation(
        &attestation,
        &key_id,
        &request.challenge,
        app_context.attest_policy(),
        chrono::Utc::now(),
    )
    .map_err(|err| {
        tracing::warn!(?err, %ip, "Rejected App Attest registration");
        ApiError::unauthorized(
            UnauthorizedReason::AttestationInvalid,
            "Attestation is not valid",
        )
    })?;

    let key = crate::database::AttestKey {
        key_id: crate::auth::hex(&verified.key_id),
        public_key: verified.public_key,
        user_id: request.user_id.clone(),
        bundle_id: verified.bundle_id.clone(),
        environment: verified.environment.as_str().to_string(),
        sign_count: 0,
        replay_window: 0,
        revoked_at_ms: None,
    };
    let bound_user_id = app_context
        .db_client()
        .register_attest_key(&key, &verified.receipt, now)
        .await
        .map_err(ApiError::DatabaseError)?;

    if bound_user_id != request.user_id {
        tracing::info!(
            key_id = %key.key_id,
            bound_user_id = %bound_user_id,
            requested_user_id = %request.user_id,
            "Attested key kept its original install id"
        );
    }

    let (token, session) = crate::auth::mint_session(
        &app_context,
        &bound_user_id,
        Some(key.key_id.clone()),
        Some(verified.bundle_id),
        true,
    )
    .await?;

    tracing::info!(
        key_id = %key.key_id,
        user_id = %bound_user_id,
        environment = %verified.environment.as_str(),
        "Registered an attested key"
    );

    Ok(Json(SessionResponse {
        token,
        session_id: session.session_id,
        user_id: bound_user_id,
        expires_at_ms: session.expires_at_ms,
        attested: true,
    }))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RefreshRequest {
    key_id: String,
    /// Base64 of the CBOR assertion.
    assertion: String,
    /// Base64 of the exact client data bytes the assertion signed. On this
    /// route its `s` field carries the challenge rather than a session id,
    /// because the caller has no session yet.
    client_data: String,
}

/// Exchanges an assertion for a fresh session.
///
/// This is the only place a session comes from after the one-time registration,
/// so a client that loses its token proves possession of the Secure Enclave key
/// again rather than falling back to anything weaker.
async fn attest_session(
    State(app_context): State<AppContext>,
    Json(request): Json<RefreshRequest>,
) -> Result<Json<SessionResponse>, ApiError> {
    let now = crate::auth::now_ms();

    let assertion = BASE64_STANDARD
        .decode(&request.assertion)
        .map_err(|_| ApiError::BadRequest("assertion is not valid base64".to_string()))?;
    let client_data = BASE64_STANDARD
        .decode(&request.client_data)
        .map_err(|_| ApiError::BadRequest("clientData is not valid base64".to_string()))?;

    let key_id = crate::auth::hex(
        &BASE64_STANDARD
            .decode(&request.key_id)
            .map_err(|_| ApiError::BadRequest("keyId is not valid base64".to_string()))?,
    );

    let key = app_context
        .db_client()
        .get_attest_key(&key_id)
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

    let verified = crate::attest::verify_assertion(
        &assertion,
        &key.public_key,
        &client_data,
        app_context.attest_policy(),
        &key.bundle_id,
    )
    .map_err(|err| {
        tracing::warn!(%key_id, ?err, "Rejected session refresh assertion");
        ApiError::unauthorized(
            UnauthorizedReason::AssertionInvalid,
            "Assertion is not valid",
        )
    })?;

    let parsed: crate::auth::AssertionClientData = serde_json::from_slice(&client_data)
        .map_err(|_| ApiError::BadRequest("clientData is not the expected shape".to_string()))?;
    if parsed.p != "/v3/attest/session" || parsed.m != "POST" {
        return Err(ApiError::unauthorized(
            UnauthorizedReason::AssertionMismatch,
            "Assertion does not cover this request",
        ));
    }
    if !app_context
        .db_client()
        .consume_challenge(&parsed.s, now)
        .await
        .map_err(ApiError::DatabaseError)?
    {
        return Err(ApiError::unauthorized(
            UnauthorizedReason::ChallengeInvalid,
            "Challenge is unknown, spent, or expired",
        ));
    }

    crate::auth::commit_counter(
        &app_context,
        &key_id,
        key.sign_count,
        key.replay_window,
        verified.counter,
        now,
    )
    .await?;

    tracing::info!(
        %key_id,
        user_id = %key.user_id,
        counter = verified.counter,
        "Refreshed an attested session"
    );

    let (token, session) = crate::auth::mint_session(
        &app_context,
        &key.user_id,
        Some(key_id),
        Some(key.bundle_id),
        true,
    )
    .await?;

    Ok(Json(SessionResponse {
        token,
        session_id: session.session_id,
        user_id: key.user_id,
        expires_at_ms: session.expires_at_ms,
        attested: true,
    }))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct UnattestedRequest {
    user_id: String,
    challenge: String,
    /// Base64 of the Mac App Store receipt from `Bundle.main.appStoreReceiptURL`.
    /// Required: without it the caller is only asserting it cannot attest, and
    /// an assertion is not a credential.
    receipt: String,
    /// What the client reported about why it cannot attest, recorded so the
    /// size of this population can be watched rather than guessed at.
    #[serde(default)]
    reason: Option<String>,
}

/// Issues a session to a Mac that cannot attest, against its App Store receipt.
///
/// App Attest reached macOS only in macOS 27 and Roam deploys to macOS 15, so
/// every Mac below 27 authenticates here. The receipt is what makes that a
/// credential rather than a claim: an earlier cut took the client's word for
/// "I cannot attest", which any caller can say. Only macOS builds compile the
/// code that calls this, and only a genuine Apple-signed receipt gets past it.
///
/// What a receipt proves is narrower than an attestation. It is a static file,
/// so it establishes that a genuine App Store receipt for this bundle exists,
/// not that this request came from the Mac it was issued to. Binding one
/// receipt to one install is what caps a copied receipt to a single
/// conversation.
async fn attest_unattested_session(
    State(app_context): State<AppContext>,
    headers: axum::http::HeaderMap,
    Json(request): Json<UnattestedRequest>,
) -> Result<Json<SessionResponse>, ApiError> {
    if !app_context.app_attest_fallback_enabled() {
        return Err(ApiError::unauthorized(
            UnauthorizedReason::FallbackClosed,
            "This build must attest; the receipt fallback is closed",
        ));
    }

    let now = crate::auth::now_ms();
    let ip = crate::auth::client_ip(&headers);
    if !app_context.rate_limiter().check(
        &format!("unattested-session:{ip}"),
        3,
        Duration::from_secs(3600),
        now,
    ) {
        return Err(ApiError::RateLimited(
            "Too many unattested sessions".to_string(),
        ));
    }

    if !app_context
        .db_client()
        .consume_challenge(&request.challenge, now)
        .await
        .map_err(ApiError::DatabaseError)?
    {
        return Err(ApiError::unauthorized(
            UnauthorizedReason::ChallengeInvalid,
            "Challenge is unknown, spent, or expired",
        ));
    }

    let receipt_der = BASE64_STANDARD
        .decode(&request.receipt)
        .map_err(|_| ApiError::BadRequest("receipt is not valid base64".to_string()))?;
    let receipt = crate::attest::verify_receipt(
        &receipt_der,
        &app_context.attest_policy().bundle_ids,
        chrono::Utc::now(),
    )
    .map_err(|err| {
        tracing::warn!(?err, %ip, "Rejected an App Store receipt");
        ApiError::unauthorized(
            UnauthorizedReason::ReceiptInvalid,
            "App Store receipt is not valid",
        )
    })?;

    let bound_user_id = app_context
        .db_client()
        .bind_receipt(
            &receipt.fingerprint,
            &request.user_id,
            &receipt.bundle_id,
            &receipt.app_version,
            now,
        )
        .await
        .map_err(ApiError::DatabaseError)?;

    tracing::warn!(
        user_id = %bound_user_id,
        requested_user_id = %request.user_id,
        %ip,
        bundle_id = %receipt.bundle_id,
        app_version = %receipt.app_version,
        reason = request.reason.as_deref().unwrap_or("--"),
        "Issued an unattested session against an App Store receipt"
    );

    let (token, session) = crate::auth::mint_session(
        &app_context,
        &bound_user_id,
        None,
        Some(receipt.bundle_id),
        false,
    )
    .await?;

    Ok(Json(SessionResponse {
        token,
        session_id: session.session_id,
        user_id: bound_user_id,
        expires_at_ms: session.expires_at_ms,
        attested: false,
    }))
}

#[derive(serde::Deserialize)]
struct AfterQuery {
    #[serde(default, deserialize_with = "string_to_i64_optional")]
    after: Option<i64>,
}

#[derive(Serialize)]
struct UserState {
    messages: Vec<DiscordMessageDownload>,
    presence: UserPresenceInfo,
}

#[derive(Serialize)]
pub struct DiscordMessageDownload {
    #[serde(serialize_with = "i64_to_string")]
    pub id: i64,
    pub nonce: Option<String>,
    pub content: String,
    pub author: DiscordAuthor,
    #[serde(rename = "type")]
    pub message_type: u8,
    pub attachments: Vec<DiscordFile>,
    pub ai_message: bool,
    pub human_support_message: bool,
}
impl DiscordMessageDownload {
    async fn prepare(
        message: DiscordMessage,
        ai_bot_id: Option<i64>,
        human_support_user_id: Option<i64>,
    ) -> Result<Self, error::ApiError> {
        let translated_support = message.is_translated_support_message();
        let message = message.normalize();
        let ai_message = !translated_support && Some(message.author.id) == ai_bot_id;
        let human_support_message =
            translated_support || Some(message.author.id) == human_support_user_id;
        let attachments = stream::iter(message.attachments)
            .map(|attachment| async move {
                let url = attachment.url;
                let id = attachment.id;
                let data = match reqwest::get(&url).await {
                    Ok(response) => match response.bytes().await {
                        Ok(bytes) => bytes.to_vec(),
                        Err(e) => {
                            return Err(ApiError::BadRequest(format!(
                                "Error reading attachment: {e}"
                            )));
                        }
                    },
                    Err(e) => {
                        return Err(ApiError::BadRequest(format!(
                            "Error downloading attachment: {e}"
                        )));
                    }
                };

                Ok(DiscordFile {
                    id,
                    content_type: attachment
                        .content_type
                        .unwrap_or_else(|| "application/octet-stream".to_string()),
                    filename: attachment.filename,
                    data,
                })
            })
            .buffer_unordered(10) // Adjust concurrency level
            .collect::<Vec<Result<DiscordFile, ApiError>>>()
            .await;

        let attachments = attachments.into_iter().collect::<Result<Vec<_>, _>>()?;

        Ok(Self {
            id: message.id,
            nonce: message.nonce,
            content: message.content,
            author: message.author,
            message_type: message.message_type,
            attachments,
            ai_message,
            human_support_message,
        })
    }
}

async fn get_user_state(
    Path(device_id): Path<String>,
    Query(query): Query<AfterQuery>,
    Extension(caller): Extension<Caller>,
    State(app_context): State<AppContext>,
) -> Result<Json<UserState>, ApiError> {
    caller.authorize_user(&device_id)?;
    let user = app_context
        .get_or_create_user(&device_id, &UserUpdate::default())
        .await?;

    let messages = app_context
        .discord_client()
        .get_messages_in_thread(user.thread_id, query.after)
        .await?
        .into_iter()
        .filter(|m| !m.is_hidden());
    let ai_bot_id = app_context.ai_responder_discord_bot_id();
    let human_support_user_id = app_context.ai_responder_human_support_user_id();
    let messages = stream::iter(messages)
        .map(|m| async move {
            DiscordMessageDownload::prepare(m, ai_bot_id, human_support_user_id).await
        }) // Async mapping
        .buffer_unordered(10) // Adjust concurrency level as needed
        .collect::<Vec<_>>() // Collect into Vec
        .await;

    let messages = messages.into_iter().collect::<Result<Vec<_>, _>>()?;

    let presence = app_context.presence_info(&user.device_id).await;

    Ok(Json(UserState { messages, presence }))
}

async fn get_user_messages(
    Path(device_id): Path<String>,
    Query(query): Query<AfterQuery>,
    Extension(caller): Extension<Caller>,
    State(app_context): State<AppContext>,
) -> Result<Json<Vec<DiscordMessage>>, ApiError> {
    caller.authorize_user(&device_id)?;
    let user = app_context
        .get_or_create_user(&device_id, &UserUpdate::default())
        .await?;

    let messages = app_context
        .discord_client()
        .get_messages_in_thread(user.thread_id, query.after)
        .await?
        .into_iter()
        .filter(|m| !m.is_hidden())
        .map(|m| m.normalize())
        .collect();

    Ok(Json(messages))
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ApnsRequest {
    user_id: String,
    apns_token: String,
    installation_info: Option<DeviceInfo>,
}

async fn new_apns(
    State(app_context): State<AppContext>,
    Extension(caller): Extension<Caller>,
    Json(req): Json<ApnsRequest>,
) -> Result<String, ApiError> {
    let ApnsRequest {
        apns_token,
        user_id: device_id,
        installation_info,
    } = req;
    caller.authorize_user(&device_id)?;

    let user = app_context
        .get_or_create_user(
            &device_id,
            &UserUpdate {
                apns_token: Some(apns_token.clone()),
                device_info: installation_info.clone(),
                thread_id: None,
            },
        )
        .await?;

    app_context
        .refresh_user(user, Some(apns_token).as_ref(), &installation_info)
        .await?;

    Ok("OK".to_string())
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct MessageRequest {
    user_id: String,
    apns_token: Option<String>,
    content: Option<String>,
    attachments: Option<Vec<DiscordFileUpload>>,
    nonce: Option<String>,
    installation_info: Option<DeviceInfo>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct MessageRequestV2 {
    user_id: String,
    content: String,
    attachment: Option<DiscordFileUpload>,
    installation_info: Option<DeviceInfo>,
    nonce: Option<String>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct DiagnosticRequest {
    user_id: String,
    metrics_payloads: Vec<String>,
    diagnostics: RoamDebugInfo,
    installation_info: DeviceInfo,
}

async fn upload_metric_diagnostics(
    State(app_context): State<AppContext>,
    Extension(caller): Extension<Caller>,
    Json(diagnostic_request): Json<DiagnosticRequest>,
) -> Result<(), ApiError> {
    let DiagnosticRequest {
        user_id: device_id,
        installation_info,
        diagnostics,
        metrics_payloads,
    } = diagnostic_request;
    caller.authorize_user(&device_id)?;

    let user = app_context
        .get_or_create_user(
            &device_id,
            &UserUpdate {
                apns_token: None,
                device_info: Some(installation_info.clone()),
                thread_id: None,
            },
        )
        .await?;

    let user = app_context
        .refresh_user(user, None, &Some(installation_info.clone()))
        .await?;

    app_context
        .discord_client()
        .send_message(
            user.thread_id,
            &support_only("MK Diagnostics Payload Received"),
            Some(DiscordFileUpload {
                content_type: "application/json".to_string(),
                filename: "diagnostics.json".to_string(),
                data: serde_json::to_vec(&metrics_payloads).map_err(|e| {
                    ApiError::BadRequest(format!("Error serializing diagnostics: {e}"))
                })?,
                paired_messages: vec![],
            }),
            Some(&DiscordMessageOptions::default()),
        )
        .await?;

    app_context
        .discord_client()
        .send_message(
            user.thread_id,
            &support_only("MK Diagnostics Supporting Data"),
            Some(DiscordFileUpload {
                content_type: "application/json".to_string(),
                filename: "diagnostics.json".to_string(),
                data: serde_json::to_vec(&diagnostics).map_err(|e| {
                    ApiError::BadRequest(format!("Error serializing diagnostics: {e}"))
                })?,
                paired_messages: vec![],
            }),
            Some(&DiscordMessageOptions::default()),
        )
        .await?;

    let pending_dir = app_context.data_dir().join("pending-symbolication");
    tokio::fs::create_dir_all(&pending_dir)
        .await
        .map_err(|e| ApiError::SymbolicationError(anyhow::Error::from(e)))?;

    let total = metrics_payloads.len();
    let diagnostics_json = serde_json::to_string(&diagnostics)
        .map_err(|e| ApiError::BadRequest(format!("Error serializing diagnostics: {e}")))?;
    let installation_info_json = serde_json::to_string(&installation_info)
        .map_err(|e| ApiError::BadRequest(format!("Error serializing installation info: {e}")))?;

    for (idx, payload_json) in metrics_payloads.into_iter().enumerate() {
        // Scan for binary UUIDs rather than parsing the payload. Ingest only
        // needs the UUID list as a dSYM pre-fetch hint, and the parser reserves
        // a 256 MiB stack to survive deep `subFrames` nesting - a reservation
        // this 256 MB VM cannot map, so calling it here panicked *after* the
        // Discord posts and before the insert, silently dropping every crash
        // uploaded while it was deployed. `scan_binary_uuids` is a flat pass
        // over bytes already in memory and cannot fail; the worker still parses
        // the payload properly on a machine with room for it.
        let binary_uuids: Vec<String> = scan_binary_uuids(payload_json.as_bytes())
            .into_iter()
            .collect();
        let binary_uuids_json = serde_json::to_string(&binary_uuids).map_err(|e| {
            ApiError::SymbolicationError(anyhow::anyhow!("Error serializing binary UUIDs: {e}"))
        })?;

        let id = Uuid::new_v4().to_string();
        let payload_path = pending_dir.join(format!("{id}.json"));
        tokio::fs::write(&payload_path, payload_json.as_bytes())
            .await
            .map_err(|e| ApiError::SymbolicationError(anyhow::Error::from(e)))?;

        let row = PendingSymbolication {
            id,
            device_id: device_id.clone(),
            thread_id: user.thread_id,
            payload_path: payload_path.to_string_lossy().to_string(),
            diagnostics_json: diagnostics_json.clone(),
            installation_info_json: installation_info_json.clone(),
            binary_uuids_json,
            payload_index: idx as i64,
            received_at_ms: chrono::Utc::now().timestamp_millis(),
            leased_at_ms: None,
            completed_at_ms: None,
            failed_at_ms: None,
            attempts: 0,
            last_error: None,
        };
        app_context
            .db_client()
            .insert_pending_symbolication(&row)
            .await
            .map_err(ApiError::DatabaseError)?;
    }

    tracing::info!(
        user_id = %device_id,
        thread_id = user.thread_id,
        enqueued = total,
        "Enqueued MetricKit payloads for symbolication"
    );

    Ok(())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DsymUploadResponse {
    extracted_root: String,
    indexed_debug_ids: Vec<String>,
}

/// Deletes the temp upload on drop so an early return (bad request, extraction
/// failure, client hangup) can't leak a few hundred megabytes onto the volume.
struct TempUpload(PathBuf);

impl Drop for TempUpload {
    fn drop(&mut self) {
        if let Err(err) = std::fs::remove_file(&self.0)
            && err.kind() != std::io::ErrorKind::NotFound
        {
            tracing::warn!(path = %self.0.display(), %err, "Failed to remove temp dSYM upload");
        }
    }
}

/// Accepts a `multipart/form-data` upload with text fields `bundleIdentifier`,
/// `appVersion`, `buildVersion`, `platform` and a file field `dsymZip`.
///
/// The zip is streamed straight to the data volume rather than buffered: dSYM
/// archives are 100 MB+ and the previous base64-in-JSON body OOM-killed the
/// 256 MB machine (three copies of the payload live at once).
async fn upload_roam_dsym(
    State(app_context): State<AppContext>,
    mut multipart: Multipart,
) -> Result<Json<DsymUploadResponse>, ApiError> {
    let mut bundle_identifier = String::new();
    let mut app_version = String::new();
    let mut build_version = String::new();
    let mut platform = String::new();
    let mut upload: Option<TempUpload> = None;
    let mut bytes_written: u64 = 0;

    let temp_dir = app_context.data_dir().join("tmp");
    tokio::fs::create_dir_all(&temp_dir)
        .await
        .with_context(|| format!("creating temp upload directory {}", temp_dir.display()))
        .map_err(ApiError::SymbolicationError)?;

    while let Some(mut field) = multipart
        .next_field()
        .await
        .map_err(|err| ApiError::BadRequest(format!("reading multipart field: {err}")))?
    {
        let Some(name) = field.name().map(str::to_string) else {
            continue;
        };

        if name == "dsymZip" {
            let temp_path = temp_dir.join(format!("dsym-upload-{}.zip", Uuid::new_v4()));
            let temp_upload = TempUpload(temp_path.clone());
            let mut file = tokio::fs::File::create(&temp_path)
                .await
                .with_context(|| format!("creating temp dSYM upload {}", temp_path.display()))
                .map_err(ApiError::SymbolicationError)?;

            while let Some(chunk) = field
                .chunk()
                .await
                .map_err(|err| ApiError::BadRequest(format!("reading dsymZip field: {err}")))?
            {
                bytes_written += chunk.len() as u64;
                if bytes_written > MAX_DSYM_UPLOAD_BYTES {
                    return Err(ApiError::BadRequest(format!(
                        "dsymZip exceeds the {} MB upload limit",
                        MAX_DSYM_UPLOAD_BYTES / (1024 * 1024)
                    )));
                }
                file.write_all(&chunk)
                    .await
                    .with_context(|| format!("writing temp dSYM upload {}", temp_path.display()))
                    .map_err(ApiError::SymbolicationError)?;
            }

            file.flush()
                .await
                .with_context(|| format!("flushing temp dSYM upload {}", temp_path.display()))
                .map_err(ApiError::SymbolicationError)?;
            drop(file);
            upload = Some(temp_upload);
            continue;
        }

        let value = field
            .text()
            .await
            .map_err(|err| ApiError::BadRequest(format!("reading field {name}: {err}")))?;
        match name.as_str() {
            "bundleIdentifier" => bundle_identifier = value,
            "appVersion" => app_version = value,
            "buildVersion" => build_version = value,
            "platform" => platform = value,
            _ => tracing::warn!(field = %name, "Ignoring unknown dSYM upload field"),
        }
    }

    if bundle_identifier.trim().is_empty()
        || app_version.trim().is_empty()
        || build_version.trim().is_empty()
        || platform.trim().is_empty()
    {
        return Err(ApiError::BadRequest(
            "bundleIdentifier, appVersion, buildVersion, and platform are required".to_string(),
        ));
    }

    let Some(upload) = upload else {
        return Err(ApiError::BadRequest(
            "a dsymZip file part is required".to_string(),
        ));
    };

    let metadata = DsymUploadMetadata {
        bundle_identifier,
        app_version,
        build_version,
        platform,
    };
    tracing::info!(
        bytes = bytes_written,
        platform = %metadata.platform,
        build_version = %metadata.build_version,
        "Received dSYM upload; extracting"
    );
    let stored = app_context
        .store_dsym_zip(metadata, upload.0.clone())
        .await?;
    drop(upload);
    tracing::info!(
        path = %stored.extracted_root.display(),
        indexed_uuids = stored.indexed_debug_ids.len(),
        "Stored uploaded dSYM archive"
    );
    Ok(Json(DsymUploadResponse {
        extracted_root: stored.extracted_root.display().to_string(),
        indexed_debug_ids: stored.indexed_debug_ids,
    }))
}

#[derive(serde::Deserialize)]
struct LeaseQuery {
    #[serde(default = "default_lease_n")]
    n: i64,
}

fn default_lease_n() -> i64 {
    5
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MatchedDsym {
    pub uuid: String,
    pub breakpad_id: String,
    pub filename: String,
    pub size_bytes: u64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LeasedPayload {
    pub id: String,
    pub payload_index: i64,
    pub device_id: String,
    #[serde(serialize_with = "i64_to_string")]
    pub thread_id: i64,
    pub metric_payload_json: String,
    pub diagnostics: serde_json::Value,
    pub installation_info: serde_json::Value,
    pub matched_dsyms: Vec<MatchedDsym>,
    pub attempts: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LeaseResponse {
    pub payloads: Vec<LeasedPayload>,
}

async fn lease_pending_symbolications(
    Query(query): Query<LeaseQuery>,
    State(app_context): State<AppContext>,
) -> Result<Json<LeaseResponse>, ApiError> {
    let n = query.n.clamp(1, 50);

    let (newly_failed, leased) = app_context
        .db_client()
        .lease_pending_symbolications(n, LEASE_TTL)
        .await
        .map_err(ApiError::DatabaseError)?;

    for failed in newly_failed {
        // Support-only like every other post in this flow. Without the prefix
        // this one reached the reporter's in-app chat, which is how a backend
        // retry budget became a user-facing message.
        let message = support_only(&format!(
            ":warning: MK Diagnostics {} symbolication failed (after {} attempts): {}",
            failed.payload_index,
            failed.attempts,
            failed
                .last_error
                .as_deref()
                .unwrap_or("(no error recorded)"),
        ))
        .into_owned();
        if let Err(err) = app_context
            .discord_client()
            .send_message(failed.thread_id, &message, None, None)
            .await
        {
            tracing::error!(?err, id = %failed.id, "Failed to post Discord :warning: for exhausted symbolication");
        }
        // The payload outlives the failure, so a later symbolicator fix can
        // still reach it. `reap_expired_failed_payloads` clears it on age.
    }

    reap_expired_failed_payloads(&app_context).await;

    let mut payloads = Vec::with_capacity(leased.len());
    for row in leased {
        let metric_payload_json = match tokio::fs::read_to_string(&row.payload_path).await {
            Ok(text) => text,
            Err(err) => {
                tracing::error!(
                    ?err,
                    id = %row.id,
                    path = %row.payload_path,
                    "Could not read leased payload from disk; releasing lease"
                );
                let _ = app_context
                    .db_client()
                    .release_lease_with_error(&row.id, &format!("payload missing on disk: {err}"))
                    .await;
                continue;
            }
        };

        let diagnostics: serde_json::Value =
            serde_json::from_str(&row.diagnostics_json).map_err(|e| {
                ApiError::SymbolicationError(anyhow::anyhow!("invalid diagnostics_json: {e}"))
            })?;
        let installation_info: serde_json::Value =
            serde_json::from_str(&row.installation_info_json).map_err(|e| {
                ApiError::SymbolicationError(anyhow::anyhow!("invalid installation_info_json: {e}"))
            })?;
        let binary_uuids: Vec<String> =
            serde_json::from_str(&row.binary_uuids_json).map_err(|e| {
                ApiError::SymbolicationError(anyhow::anyhow!("invalid binary_uuids_json: {e}"))
            })?;

        let mut matched_dsyms = Vec::new();
        for uuid in binary_uuids {
            if let Some(path) = app_context.symbolicate_client().dsym_path_for_uuid(&uuid) {
                let metadata = match tokio::fs::metadata(&path).await {
                    Ok(m) => m,
                    Err(err) => {
                        tracing::warn!(?err, %uuid, "Cached dSYM unreadable; skipping");
                        continue;
                    }
                };
                let breakpad_id = uuid_to_breakpad_id(&uuid).unwrap_or_default();
                let filename = path
                    .file_name()
                    .map(|f| f.to_string_lossy().to_string())
                    .unwrap_or_else(|| uuid.clone());
                matched_dsyms.push(MatchedDsym {
                    uuid: uuid.to_ascii_uppercase(),
                    breakpad_id,
                    filename,
                    size_bytes: metadata.len(),
                });
            }
        }

        payloads.push(LeasedPayload {
            id: row.id,
            payload_index: row.payload_index,
            device_id: row.device_id,
            thread_id: row.thread_id,
            metric_payload_json,
            diagnostics,
            installation_info,
            matched_dsyms,
            attempts: row.attempts,
        });
    }

    Ok(Json(LeaseResponse { payloads }))
}

fn uuid_to_breakpad_id(uuid: &str) -> Option<String> {
    let parsed = Uuid::parse_str(uuid).ok()?;
    if parsed.is_nil() {
        return None;
    }
    Some(
        samply_symbols::debugid::DebugId::from_uuid(parsed)
            .breakpad()
            .to_string(),
    )
}

async fn get_dsym_by_uuid(
    Path(uuid): Path<String>,
    State(app_context): State<AppContext>,
) -> Result<Response, ApiError> {
    let Some(path) = app_context.symbolicate_client().dsym_path_for_uuid(&uuid) else {
        return Err(ApiError::NotFound(format!(
            "No cached dSYM for UUID {uuid}"
        )));
    };

    let file = tokio::fs::File::open(&path)
        .await
        .map_err(|e| ApiError::SymbolicationError(anyhow::Error::from(e)))?;
    let metadata = file
        .metadata()
        .await
        .map_err(|e| ApiError::SymbolicationError(anyhow::Error::from(e)))?;
    let filename = path
        .file_name()
        .map(|f| f.to_string_lossy().to_string())
        .unwrap_or_else(|| uuid.clone());

    let stream = ReaderStream::new(file);
    let body = Body::from_stream(stream);
    Ok((
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, "application/octet-stream".to_string()),
            (header::CONTENT_LENGTH, metadata.len().to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("attachment; filename=\"{filename}\""),
            ),
        ],
        body,
    )
        .into_response())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SymbolicationResultRequest {
    id: String,
    #[serde(default)]
    symbolicated_text: Option<String>,
    #[serde(default)]
    error: Option<String>,
}

/// How long a permanently-failed symbolication's payload is kept on disk.
///
/// Long enough that a symbolicator fix shipped in response to the failure can
/// still be applied to it, bounded so the volume does not grow without limit.
const FAILED_PAYLOAD_RETENTION: Duration = Duration::from_secs(30 * 24 * 60 * 60);

/// Delete payload files of symbolications that failed longer ago than
/// `FAILED_PAYLOAD_RETENTION`.
///
/// Driven from the lease endpoint rather than a timer: the worker polls it on a
/// schedule already, and a sweep that only runs when there is a worker to serve
/// is a sweep that cannot delete anything behind a stopped worker's back.
///
/// Best-effort - a payload that fails to delete is simply retried next sweep.
async fn reap_expired_failed_payloads(app_context: &AppContext) {
    let cutoff_ms =
        chrono::Utc::now().timestamp_millis() - (FAILED_PAYLOAD_RETENTION.as_millis() as i64);

    let expired = match app_context
        .db_client()
        .expired_failed_payloads(cutoff_ms)
        .await
    {
        Ok(rows) => rows,
        Err(err) => {
            tracing::warn!(?err, "Could not list expired failed symbolication payloads");
            return;
        }
    };

    for (id, payload_path) in expired {
        match tokio::fs::remove_file(&payload_path).await {
            Ok(()) => {}
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => {
                tracing::warn!(?err, %id, path = %payload_path, "Could not reap failed symbolication payload");
                continue;
            }
        }
        if let Err(err) = app_context.db_client().mark_payload_reaped(&id).await {
            tracing::warn!(?err, %id, "Could not mark symbolication payload as reaped");
        } else {
            tracing::info!(%id, path = %payload_path, "Reaped payload of long-failed symbolication");
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RequeueSymbolicationsRequest {
    /// Restrict the requeue to payloads whose recorded error contains this
    /// substring. Omitting it requeues every exhausted payload.
    #[serde(default)]
    error_contains: Option<String>,
    /// Report what would be requeued without changing anything.
    #[serde(default)]
    dry_run: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RequeueSymbolicationsResponse {
    requeued: usize,
    ids: Vec<String>,
}

/// Returns exhausted symbolications to the queue.
///
/// Exists because a payload that fails three times is out of the worker's reach
/// forever, even once the bug that failed it is fixed - the deep-stack crashes
/// rejected by the old parser being the case in point. Requeueing is how a
/// deploy that fixes symbolication gets applied to the crashes it already lost.
async fn requeue_symbolications(
    State(app_context): State<AppContext>,
    Json(req): Json<RequeueSymbolicationsRequest>,
) -> Result<Json<RequeueSymbolicationsResponse>, ApiError> {
    if req.dry_run {
        let candidates = app_context
            .db_client()
            .failed_symbolication_ids(req.error_contains.as_deref())
            .await
            .map_err(ApiError::DatabaseError)?;
        tracing::info!(
            count = candidates.len(),
            error_contains = req.error_contains.as_deref().unwrap_or("*"),
            "Dry run: symbolications eligible for requeue"
        );
        return Ok(Json(RequeueSymbolicationsResponse {
            requeued: candidates.len(),
            ids: candidates,
        }));
    }

    let rows = app_context
        .db_client()
        .requeue_failed_symbolications(req.error_contains.as_deref())
        .await
        .map_err(ApiError::DatabaseError)?;

    let ids: Vec<String> = rows.iter().map(|row| row.id.clone()).collect();
    tracing::info!(
        count = ids.len(),
        error_contains = req.error_contains.as_deref().unwrap_or("*"),
        "Requeued failed symbolications"
    );

    Ok(Json(RequeueSymbolicationsResponse {
        requeued: ids.len(),
        ids,
    }))
}

// ---------------------------------------------------------------------------
// Crash review tracking
// ---------------------------------------------------------------------------

/// Records a freshly symbolicated crash and, when it matches a known rule,
/// replies in-thread and marks it reviewed.
///
/// Crashes that match nothing stay unreviewed, forming the queue a human works
/// through via `GET /v2/crashes?unreviewed=true`. A match
/// from a version that already carries the rule's fix
/// ([`FixStatus::Unfixed`](crate::crash_rules::FixStatus::Unfixed)) is replied
/// to but *also* left in that queue: the diagnosis is worth posting, but a
/// stack outliving its fix is not something to close automatically.
async fn auto_review_crash(
    app_context: &AppContext,
    thread_id: i64,
    crash_message_id: i64,
    report: &str,
) -> anyhow::Result<()> {
    let facts = crate::crash_rules::CrashFacts::from_report(report);
    app_context
        .db_client()
        .record_crash_for_review(thread_id, Some(crash_message_id), &facts)
        .await?;

    let Some(matched) = crate::crash_rules::match_rule(report, &facts) else {
        tracing::info!(
            thread_id,
            app_version = ?facts.app_version,
            "Crash recorded with no matching rule; left for manual review"
        );
        return Ok(());
    };
    let rule = matched.rule;

    let reply = app_context
        .discord_client()
        .send_reply(
            thread_id,
            &support_only(&matched.reply(&facts)),
            Some(crash_message_id),
            false,
        )
        .await?;

    let review_note = matched.review_note(&facts);

    if matched.status == crate::crash_rules::FixStatus::Unfixed {
        app_context
            .db_client()
            .note_rule_match(thread_id, rule.id, &review_note)
            .await?;
        tracing::warn!(
            thread_id,
            rule = rule.id,
            app_version = ?facts.app_version,
            fixed_in = ?rule.fixed_in,
            "Crash matched a rule whose fix already shipped; replied but left unreviewed"
        );
        return Ok(());
    }

    app_context
        .db_client()
        .mark_thread_reviewed(
            thread_id,
            Some(&format!("auto:{}", rule.id)),
            Some(reply.id),
            Some(rule.id),
            Some(&review_note),
        )
        .await?;

    tracing::info!(
        thread_id,
        rule = rule.id,
        status = ?matched.status,
        "Auto-reviewed crash"
    );
    Ok(())
}

fn default_crash_limit() -> i64 {
    50
}

#[derive(Debug, Deserialize)]
pub struct ListCrashesQuery {
    /// Only threads whose newest crash has not been reviewed yet.
    #[serde(default)]
    unreviewed: bool,
    /// Exact match on the crash's `appVersion` - the build that died.
    #[serde(default)]
    app_version: Option<String>,
    /// Exact match on the release the reporting device had installed when it
    /// uploaded the payload, which after an update is newer than
    /// `app_version`. See `CrashFacts::installed_version`.
    #[serde(default)]
    installed_version: Option<String>,
    /// Page backwards: pass the previous page's last `latest_crash_at_ms`.
    #[serde(default)]
    before_ms: Option<i64>,
    #[serde(default = "default_crash_limit")]
    limit: i64,
}

#[derive(Debug, Serialize)]
pub struct ListCrashesResponse {
    crashes: Vec<crate::database::CrashReview>,
    /// Cursor for the next page, or `null` when the last page was returned.
    next_before_ms: Option<i64>,
}

async fn list_crashes(
    State(app_context): State<AppContext>,
    Query(query): Query<ListCrashesQuery>,
) -> Result<Json<ListCrashesResponse>, ApiError> {
    let limit = query.limit.clamp(1, 200);
    let crashes = app_context
        .db_client()
        .list_crash_reviews(
            query.unreviewed,
            query.app_version.as_deref(),
            query.installed_version.as_deref(),
            query.before_ms,
            limit,
        )
        .await
        .map_err(ApiError::DatabaseError)?;

    // Only advertise another page when this one was full; otherwise the caller
    // would loop once more just to get an empty list.
    let next_before_ms = (crashes.len() as i64 == limit)
        .then(|| crashes.last().map(|c| c.latest_crash_at_ms))
        .flatten();

    Ok(Json(ListCrashesResponse {
        crashes,
        next_before_ms,
    }))
}

async fn get_crash(
    State(app_context): State<AppContext>,
    Path(thread_id): Path<i64>,
) -> Result<Json<crate::database::CrashReview>, ApiError> {
    app_context
        .db_client()
        .get_crash_review(thread_id)
        .await
        .map_err(ApiError::DatabaseError)?
        .map(Json)
        .ok_or_else(|| ApiError::NotFound(format!("No tracked crash for thread {thread_id}")))
}

async fn list_crash_rules() -> Json<&'static [crate::crash_rules::CrashRule]> {
    Json(crate::crash_rules::RULES)
}

#[derive(Debug, Default, Deserialize)]
pub struct ReviewCrashRequest {
    /// Free-form attribution, e.g. a person's handle. Defaults to `manual`.
    #[serde(default)]
    reviewed_by: Option<String>,
    /// Id of the reply that resolved this crash, if one was posted.
    #[serde(default)]
    reviewed_message_id: Option<String>,
    #[serde(default)]
    matched_rule_id: Option<String>,
    #[serde(default)]
    note: Option<String>,
}

async fn review_crash(
    State(app_context): State<AppContext>,
    Path(thread_id): Path<i64>,
    body: Option<Json<ReviewCrashRequest>>,
) -> Result<Json<crate::database::CrashReview>, ApiError> {
    let Json(req) = body.unwrap_or_default();
    let reviewed_message_id =
        parse_snowflake(req.reviewed_message_id.as_ref(), "reviewed_message_id")?;
    app_context
        .db_client()
        .mark_thread_reviewed(
            thread_id,
            Some(req.reviewed_by.as_deref().unwrap_or("manual")),
            reviewed_message_id,
            req.matched_rule_id.as_deref(),
            req.note.as_deref(),
        )
        .await
        .map_err(ApiError::DatabaseError)?
        .map(Json)
        .ok_or_else(|| ApiError::NotFound(format!("No tracked crash for thread {thread_id}")))
}

async fn unreview_crash(
    State(app_context): State<AppContext>,
    Path(thread_id): Path<i64>,
) -> Result<Json<crate::database::CrashReview>, ApiError> {
    app_context
        .db_client()
        .mark_thread_unreviewed(thread_id)
        .await
        .map_err(ApiError::DatabaseError)?
        .map(Json)
        .ok_or_else(|| ApiError::NotFound(format!("No tracked crash for thread {thread_id}")))
}

// ---------------------------------------------------------------------------
// Discord proxy
// ---------------------------------------------------------------------------

fn default_archived_pages() -> usize {
    3
}

#[derive(Debug, Deserialize)]
pub struct ListThreadsQuery {
    /// How many pages (100 each) of archived threads to walk. 0 = active only.
    #[serde(default = "default_archived_pages")]
    archived_pages: usize,
}

async fn list_discord_threads(
    State(app_context): State<AppContext>,
    Query(query): Query<ListThreadsQuery>,
) -> Result<Json<Vec<crate::discord::Thread>>, ApiError> {
    let threads = app_context
        .discord_client()
        .list_all_threads(query.archived_pages.min(20))
        .await?;
    Ok(Json(threads))
}

/// Snowflake ids arrive as strings (they exceed JS's safe integer range), so
/// query and body fields carrying them are parsed rather than deserialized
/// straight to `i64`.
fn parse_snowflake(value: Option<&String>, field: &str) -> Result<Option<i64>, ApiError> {
    value
        .map(|raw| {
            raw.parse::<i64>()
                .map_err(|_| ApiError::BadRequest(format!("Invalid {field}: {raw}")))
        })
        .transpose()
}

#[derive(Debug, Deserialize)]
pub struct ListMessagesQuery {
    /// Newest-first pagination: return messages older than this id.
    #[serde(default)]
    before: Option<String>,
    /// Return messages newer than this id.
    #[serde(default)]
    after: Option<String>,
    #[serde(default)]
    limit: Option<u8>,
}

async fn list_discord_messages(
    State(app_context): State<AppContext>,
    Path(thread_id): Path<i64>,
    Query(query): Query<ListMessagesQuery>,
) -> Result<Json<Vec<DiscordMessage>>, ApiError> {
    let before = parse_snowflake(query.before.as_ref(), "before")?;
    let after = parse_snowflake(query.after.as_ref(), "after")?;
    let messages = app_context
        .discord_client()
        .get_messages_paginated(thread_id, after, before, query.limit.or(Some(50)))
        .await?;
    Ok(Json(messages))
}

async fn get_discord_message(
    State(app_context): State<AppContext>,
    Path((thread_id, message_id)): Path<(i64, i64)>,
) -> Result<Json<DiscordMessage>, ApiError> {
    let message = app_context
        .discord_client()
        .get_message(thread_id, message_id)
        .await?;
    Ok(Json(message))
}

#[derive(Debug, Deserialize)]
pub struct PostMessageRequest {
    content: String,
    /// Post as a threaded reply to this message.
    #[serde(default)]
    reply_to_message_id: Option<String>,
    #[serde(default)]
    notify: Option<bool>,
}

async fn post_discord_message(
    State(app_context): State<AppContext>,
    Path(thread_id): Path<i64>,
    Json(req): Json<PostMessageRequest>,
) -> Result<Json<DiscordMessage>, ApiError> {
    let reply_to = parse_snowflake(req.reply_to_message_id.as_ref(), "reply_to_message_id")?;
    let message = app_context
        .discord_client()
        .send_reply(
            thread_id,
            &req.content,
            reply_to,
            req.notify.unwrap_or(false),
        )
        .await?;
    Ok(Json(message))
}

/// Streams an attachment straight through from Discord's CDN.
///
/// The bytes are piped from the upstream response into the client response
/// without ever being collected: these are symbolicated reports and full
/// diagnostics dumps, and buffering them would put arbitrary attachment sizes
/// into backend memory.
async fn stream_discord_attachment(
    State(app_context): State<AppContext>,
    Path((thread_id, message_id, attachment_id)): Path<(i64, i64, i64)>,
) -> Result<Response, ApiError> {
    let message = app_context
        .discord_client()
        .get_message(thread_id, message_id)
        .await?;

    let attachment = message
        .attachments
        .iter()
        .find(|a| a.id == attachment_id)
        .ok_or_else(|| {
            ApiError::NotFound(format!(
                "Message {message_id} has no attachment {attachment_id}"
            ))
        })?;

    let upstream = app_context
        .discord_client()
        .stream_attachment(&attachment.url)
        .await?;

    let content_type = attachment
        .content_type
        .clone()
        .unwrap_or_else(|| "application/octet-stream".to_string());
    let content_length = upstream.content_length();
    let filename = attachment.filename.clone();

    let mut response = Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .header(
            header::CONTENT_DISPOSITION,
            format!("inline; filename=\"{}\"", filename.replace('"', "")),
        );
    if let Some(len) = content_length {
        response = response.header(header::CONTENT_LENGTH, len);
    }

    response
        .body(Body::from_stream(upstream.bytes_stream()))
        .map_err(|e| ApiError::SymbolicationError(anyhow::Error::from(e)))
}

async fn submit_symbolication_result(
    State(app_context): State<AppContext>,
    Json(req): Json<SymbolicationResultRequest>,
) -> Result<(), ApiError> {
    match (req.symbolicated_text, req.error) {
        (Some(text), _) => {
            let Some(row) = app_context
                .db_client()
                .complete_pending_symbolication(&req.id)
                .await
                .map_err(ApiError::DatabaseError)?
            else {
                return Err(ApiError::NotFound(format!(
                    "No pending symbolication with id {}",
                    req.id
                )));
            };

            let message = support_only(&format!(
                "MK Diagnostics {} Symbolicated",
                row.payload_index
            ))
            .into_owned();
            let posted = app_context
                .discord_client()
                .send_message(
                    row.thread_id,
                    &message,
                    Some(DiscordFileUpload {
                        content_type: "text/plain".to_string(),
                        filename: "symbolicated.txt".to_string(),
                        data: text.clone().into_bytes(),
                        paired_messages: vec![],
                    }),
                    Some(&DiscordMessageOptions::default()),
                )
                .await?;

            // Track the crash for review, then let the rules engine try to
            // close it out. A failure here must not fail the symbolication
            // result the worker just delivered, so everything is logged rather
            // than propagated.
            if let Err(err) = auto_review_crash(&app_context, row.thread_id, posted.id, &text).await
            {
                tracing::error!(
                    ?err,
                    thread_id = row.thread_id,
                    "Failed to record or auto-review crash"
                );
            }

            if let Err(err) = tokio::fs::remove_file(&row.payload_path).await
                && err.kind() != std::io::ErrorKind::NotFound
            {
                tracing::warn!(
                    ?err,
                    path = %row.payload_path,
                    "Failed to remove cached payload after symbolication"
                );
            }
            Ok(())
        }
        (None, Some(err_text)) => {
            let Some(row) = app_context
                .db_client()
                .release_lease_with_error(&req.id, &err_text)
                .await
                .map_err(ApiError::DatabaseError)?
            else {
                return Err(ApiError::NotFound(format!(
                    "No active pending symbolication with id {}",
                    req.id
                )));
            };
            tracing::warn!(
                id = %row.id,
                attempts = row.attempts,
                error = %err_text,
                "Worker reported symbolication failure"
            );
            Ok(())
        }
        (None, None) => Err(ApiError::BadRequest(
            "Body must include either `symbolicatedText` or `error`".to_string(),
        )),
    }
}

async fn new_message(
    State(app_context): State<AppContext>,
    Extension(caller): Extension<Caller>,
    Json(message_request): Json<MessageRequestV2>,
) -> Result<Json<DiscordMessageDownload>, ApiError> {
    let MessageRequestV2 {
        content,
        user_id: device_id,
        installation_info,
        attachment,
        nonce,
    } = message_request;
    caller.authorize_user(&device_id)?;
    let attachment_summary = attachment
        .as_ref()
        .map(|attachment| {
            format!(
                "{} bytes={} type={} paired_messages={}",
                attachment.filename,
                attachment.data.len(),
                attachment.content_type,
                attachment.paired_messages.len()
            )
        })
        .unwrap_or_else(|| "none".to_string());
    tracing::info!(
        user_id = %device_id,
        nonce = nonce.as_deref().unwrap_or("--"),
        content_bytes = content.len(),
        attachment = %attachment_summary,
        "Received new-message request"
    );
    let options = DiscordMessageOptions {
        nonce,
        ..Default::default()
    };

    if content.is_empty() && attachment.is_none() {
        tracing::warn!(
            user_id = %device_id,
            "Rejecting new-message request with no content or attachment"
        );
        return Err(ApiError::BadRequest(
            "Content or attachments must be provided".to_string(),
        ));
    }

    let user = app_context
        .get_or_create_user(
            &device_id,
            &UserUpdate {
                apns_token: None,
                device_info: installation_info.clone(),
                thread_id: None,
            },
        )
        .await?;

    let user = app_context
        .refresh_user(user, None, &installation_info)
        .await?;
    if app_context.ai_responder_enabled()
        && let Some(ai_client) = app_context.ai_responder_discord_client()
        && let Err(err) = ai_client.join_thread(user.thread_id).await
    {
        tracing::warn!(
            user_id = %device_id,
            thread_id = user.thread_id,
            error = ?err,
            "AI responder bot could not access or join support thread before user message"
        );
    }
    tracing::info!(
        user_id = %device_id,
        thread_id = user.thread_id,
        "Sending new-message request to Discord"
    );
    let message_result = app_context
        .discord_client()
        .send_message(user.thread_id, &content, attachment, Some(&options))
        .await?;
    tracing::info!(
        user_id = %device_id,
        thread_id = user.thread_id,
        discord_message_id = message_result.id,
        "Sent new-message request to Discord"
    );
    Ok(Json(
        DiscordMessageDownload::prepare(
            message_result,
            app_context.ai_responder_discord_bot_id(),
            app_context.ai_responder_human_support_user_id(),
        )
        .await?,
    ))
}

async fn new_message_old(
    State(app_context): State<AppContext>,
    Extension(caller): Extension<Caller>,
    Json(message_request): Json<MessageRequest>,
) -> Result<(), ApiError> {
    let MessageRequest {
        content,
        apns_token,
        user_id: device_id,
        installation_info,
        attachments,
        nonce,
    } = message_request;
    caller.authorize_user(&device_id)?;
    let options = DiscordMessageOptions {
        nonce,
        ..Default::default()
    };

    if content.is_none()
        && apns_token.is_none()
        && attachments.as_ref().is_none_or(|a| a.is_empty())
    {
        return Err(ApiError::BadRequest(
            "Content or apns_token must be provided".to_string(),
        ));
    }

    let user = app_context
        .get_or_create_user(
            &device_id,
            &UserUpdate {
                apns_token: apns_token.clone(),
                device_info: installation_info.clone(),
                thread_id: None,
            },
        )
        .await?;

    let user = app_context
        .refresh_user(user, apns_token.as_ref(), &installation_info)
        .await?;
    if content.as_ref().is_some_and(|c| !c.is_empty())
        || attachments.as_ref().is_some_and(|a| !a.is_empty())
    {
        app_context
            .discord_client()
            .send_message_multiple_attachments(
                user.thread_id,
                &content.unwrap_or_default(),
                attachments.unwrap_or_default(),
                Some(&options),
            )
            .await?;
        return Ok(());
    }
    Ok(())
}

async fn upload_diagnostics(
    Path(diagnostic_key): Path<String>,
    Extension(caller): Extension<Caller>,
    State(app_context): State<AppContext>,
    body: Body,
) -> Result<String, ApiError> {
    // Previous versions of debug logs had a diagnostic key in the form of "xxx-xxx-xxx-date"
    if diagnostic_key.len() < 11 {
        return Err(ApiError::BadRequest(
            "Diagnostic key is too short to carry a user id".to_string(),
        ));
    }
    let device_id = diagnostic_key[..11].to_string();
    caller.authorize_user(&device_id)?;
    let user = app_context
        .get_or_create_user(
            &device_id,
            &UserUpdate {
                apns_token: None,
                device_info: None,
                thread_id: None,
            },
        )
        .await?;

    let body = to_bytes(body, UPLOAD_LIMIT)
        .await
        .map_err(|e| ApiError::BadRequest(format!("Error reading body: {e}")))?;
    app_context
        .discord_client()
        .send_message_multiple_attachments(
            user.thread_id,
            SUPPORT_ONLY_PREFIX,
            vec![DiscordFileUpload {
                content_type: "application/json".to_string(),
                filename: "diagnostics.json".to_string(),
                data: body.to_vec(),
                paired_messages: vec![],
            }],
            None,
        )
        .await?;

    Ok("OK".to_string())
}

#[derive(Serialize)]
struct UserInfoResponse {
    user: User,
    messages: Vec<DiscordMessage>,
}

async fn get_user_info(
    Query(query): Query<AfterQuery>,
    Path(user_id): Path<String>,
    State(app_context): State<AppContext>,
) -> Result<Json<UserInfoResponse>, ApiError> {
    let user = app_context
        .db_client()
        .get_user_with_id(&user_id)
        .await
        .map_err(ApiError::DatabaseError)?
        .ok_or_else(|| ApiError::NotFound(format!("User with id {user_id} not found")))?;

    let messages = app_context
        .discord_client()
        .get_messages_in_thread(user.thread_id, query.after)
        .await?
        .into_iter()
        .filter(|m| !m.is_hidden())
        .map(|m| m.normalize())
        .collect();

    Ok(Json(UserInfoResponse { user, messages }))
}

async fn update_user_typing(
    Path(user_id): Path<String>,
    Extension(caller): Extension<Caller>,
    State(app_context): State<AppContext>,
) -> Result<(), ApiError> {
    caller.authorize_user(&user_id)?;
    let Some(user) = app_context
        .db_client()
        .get_user_with_id(&user_id)
        .await
        .map_err(ApiError::DatabaseError)?
    else {
        tracing::info!("Trying to update typing for non-existent user {}", user_id);
        return Ok(());
    };
    if let Err(err) = app_context.notify_self_typing(&user).await {
        tracing::error!(error = ?err, "Error notifying self typing");
        return Ok(());
    };

    app_context
        .discord_client()
        .send_typing(user.thread_id)
        .await?;

    Ok(())
}

async fn get_thread_info(
    Query(query): Query<AfterQuery>,
    Path(thread_id): Path<i64>,
    State(app_context): State<AppContext>,
) -> Result<Json<UserInfoResponse>, ApiError> {
    let user = app_context
        .db_client()
        .get_user_with_thread(thread_id)
        .await
        .map_err(ApiError::DatabaseError)?
        .ok_or_else(|| ApiError::NotFound(format!("Thread with id {thread_id} not found")))?;

    let messages = app_context
        .discord_client()
        .get_messages_in_thread(thread_id, query.after)
        .await?
        .into_iter()
        .filter(|m| !m.is_hidden())
        .map(|m| m.normalize())
        .collect();

    Ok(Json(UserInfoResponse { user, messages }))
}

mod error {
    use crate::utils::serialize_anyhow;
    use axum::{
        Json,
        body::Body,
        http::{HeaderMap, HeaderValue, StatusCode, header::WWW_AUTHENTICATE},
        response::{IntoResponse, Response},
    };
    use serde::Serialize;

    /// Why a 401 happened, as a token a client can branch on.
    ///
    /// The sentences the routes write are for a person reading a log, and a
    /// client that wants to tell "your credential is gone" from "that one
    /// request was no good" cannot match on prose without breaking the moment
    /// someone rewords it. This is the part that is promised to stay put.
    ///
    /// The distinction that matters to the app is narrow: only `KeyUnknown` and
    /// `KeyRevoked` mean the Secure Enclave key behind the credential is worth
    /// nothing now. Every other reason describes one bad request, and a client
    /// that reads them as "start over" burns an App Attest registration --
    /// which Apple rate limits -- for nothing. That is not hypothetical: a
    /// server-side signature bug once turned every assertion into
    /// `AssertionInvalid`, and clients that could not tell the difference
    /// registered a fresh key every few seconds.
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
    #[serde(rename_all = "snake_case")]
    pub enum UnauthorizedReason {
        /// The backend has no record of this attestation key.
        KeyUnknown,
        /// The key is on file but has been revoked.
        KeyRevoked,
        /// A required assertion header was not sent at all.
        AssertionMissing,
        /// The assertion did not decode, or its signature did not verify.
        AssertionInvalid,
        /// The signature was good but covers a different session, method,
        /// path, or moment than the request it arrived on.
        AssertionMismatch,
        /// The assertion's counter has already been spent.
        AssertionReplayed,
        /// The challenge was never issued, is spent, or has expired.
        ChallengeInvalid,
        /// The App Attest attestation object did not verify.
        AttestationInvalid,
        /// The App Store receipt did not verify.
        ReceiptInvalid,
        /// The receipt fallback is closed on this deployment.
        FallbackClosed,
        /// The session token is unknown, expired, or malformed.
        SessionInvalid,
        /// The credential is fine; the server could not finish this one
        /// request. Retrying is the right move.
        Transient,
    }

    #[derive(Debug, thiserror::Error, Serialize)]
    pub enum ApiError {
        #[error("Discord error {0}")]
        DiscordError(#[from] crate::discord::DiscordError),
        #[error("Symbolication error {0}")]
        SymbolicationError(#[serde(serialize_with = "serialize_anyhow")] anyhow::Error),
        #[error("Unauthorized")]
        Unauthorized(String),
        /// The same 401 as `Unauthorized`, plus the machine-readable reason.
        /// It serialises to the old shape with one extra field; see
        /// `into_response`.
        #[error("Unauthorized")]
        UnauthorizedBecause(UnauthorizedReason, String),
        #[error("Bad request: {0}")]
        BadRequest(String),
        #[error("Database error {0}")]
        DatabaseError(#[serde(serialize_with = "serialize_anyhow")] anyhow::Error),
        #[error("Not found: {0}")]
        NotFound(String),
        #[error("Rate limited: {0}")]
        RateLimited(String),
    }

    impl IntoResponse for ApiError {
        fn into_response(self) -> Response<Body> {
            let headers = match &self {
                Self::Unauthorized(_) | Self::UnauthorizedBecause(..) => {
                    [(WWW_AUTHENTICATE, HeaderValue::from_static("X-API-KEY"))]
                        .into_iter()
                        .collect::<HeaderMap>()
                }
                _ => HeaderMap::default(),
            };
            match &self {
                // User errors don't get logged
                Self::Unauthorized { .. }
                | Self::UnauthorizedBecause { .. }
                | Self::RateLimited { .. } => {}
                _ => {
                    tracing::error!(error = ?self, "Request error");
                }
            }
            let status_code = self.status_code();
            match self {
                // Written by hand rather than derived, because the shape is a
                // compatibility promise. Builds already in the field read the
                // human sentence out of `Unauthorized`, so it stays exactly
                // where it was and the reason arrives beside it, in a field
                // those builds ignore. Deriving this would have nested it
                // under `UnauthorizedBecause` and broken every one of them.
                Self::UnauthorizedBecause(reason, message) => (
                    status_code,
                    headers,
                    Json(serde_json::json!({
                        "Unauthorized": message,
                        "reason": reason,
                    })),
                )
                    .into_response(),
                other => (status_code, headers, Json(other)).into_response(),
            }
        }
    }

    impl ApiError {
        /// A 401 that says why, for anything a client might reasonably act on.
        pub fn unauthorized(reason: UnauthorizedReason, message: impl Into<String>) -> Self {
            Self::UnauthorizedBecause(reason, message.into())
        }

        fn status_code(&self) -> StatusCode {
            match self {
                Self::Unauthorized(_) | Self::UnauthorizedBecause(..) => StatusCode::UNAUTHORIZED,
                Self::DatabaseError(_) => StatusCode::INTERNAL_SERVER_ERROR,
                Self::NotFound(_) => StatusCode::NOT_FOUND,
                Self::DiscordError(crate::discord::DiscordError::RateLimited { .. }) => {
                    StatusCode::TOO_MANY_REQUESTS
                }
                Self::SymbolicationError(_) => StatusCode::INTERNAL_SERVER_ERROR,
                Self::DiscordError(_) => StatusCode::INTERNAL_SERVER_ERROR,
                Self::BadRequest(_) => StatusCode::BAD_REQUEST,
                Self::RateLimited(_) => StatusCode::TOO_MANY_REQUESTS,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::to_bytes;
    use tower::ServiceExt;

    /// A throwaway P-256 key in the shape `ApnsClient` parses. Nothing signs
    /// with it; it exists so `AppContext::new` can be built in a test.
    const TEST_APNS_KEY: &str = "LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JR0hBZ0VBTUJNR0J5cUdTTTQ5QWdFR0NDcUdTTTQ5QXdFSEJHMHdhd0lCQVFRZzY0QVRVemJIcmdLMSt5RmEKYVUvUEl0Z3FHTytLY2IzRUg4Si9uVE4zeWhXaFJBTkNBQVFSR0VjcUpWS3BnTUViMGFjS3liRm1lLzk5TU02ZwpudUtoMTBRVHp5UHFqelpibjVKTStmWEpTR2F5ZWp2MFQzaVB3dkwzL3MvYlJ5QnZDbC82K2xiUwotLS0tLUVORCBQUklWQVRFIEtFWS0tLS0tCg";

    const CRASH_KEY: &str = "crash-key-for-tests";
    const LEGACY_KEY: &str = "legacy-app-key-for-tests";

    async fn test_app() -> (Router, tempfile::TempDir) {
        let dir = tempfile::tempdir().expect("tempdir");
        let cli = crate::cli::RoamCli::parse_from([
            "roam-backend",
            "--backend-url",
            "http://localhost:8080",
            "--crash-api-key",
            CRASH_KEY,
            "--legacy-app-api-key",
            LEGACY_KEY,
            "--data-dir",
            dir.path().to_str().unwrap(),
            "--apns-key-id",
            "TESTKEYID1",
            "--apns-team-id",
            "TESTTEAMID",
            "--apns-bundle-id",
            "com.msdrigg.roam",
            "--apns-private-key",
            TEST_APNS_KEY,
            "--apns-disabled",
        ]);
        let app_context = AppContext::new(cli).await.expect("app context");
        (build_app(app_context), dir)
    }

    /// Sends one request and reports the status. Auth runs ahead of every
    /// handler, so a rejection is observable without any of the Discord or
    /// APNS machinery a 200 would need.
    async fn status(app: &Router, method: &str, path: &str, key: Option<(&str, &str)>) -> u16 {
        let mut builder = Request::builder().method(method).uri(path);
        if let Some((header, value)) = key {
            builder = builder.header(header, value);
        }
        let request = builder
            .header("content-type", "application/json")
            .body(Body::from("{}"))
            .expect("request");
        app.clone()
            .oneshot(request)
            .await
            .expect("response")
            .status()
            .as_u16()
    }

    #[tokio::test]
    async fn health_needs_no_credential() {
        let (app, _dir) = test_app().await;
        assert_eq!(status(&app, "GET", "/health", None).await, 200);
    }

    #[tokio::test]
    async fn the_crash_zone_takes_only_the_crash_key() {
        let (app, _dir) = test_app().await;
        for path in [
            "/v2/crashes",
            "/v2/discord/threads",
            "/v2/symbolicate/lease",
            "/user-info/aaa-bbb-ccc",
        ] {
            assert_eq!(
                status(&app, "GET", path, None).await,
                401,
                "{path} unguarded"
            );
            assert_eq!(
                status(&app, "GET", path, Some(("x-api-key", LEGACY_KEY))).await,
                401,
                "{path} accepted the key older app builds ship"
            );
        }
    }

    #[tokio::test]
    async fn the_crash_key_does_not_open_the_app_zone() {
        let (app, _dir) = test_app().await;
        assert_eq!(
            status(
                &app,
                "GET",
                "/updates/aaa-bbb-ccc",
                Some(("x-api-key", CRASH_KEY))
            )
            .await,
            401
        );
    }

    #[tokio::test]
    async fn the_app_zone_refuses_an_unauthenticated_caller() {
        let (app, _dir) = test_app().await;
        for (method, path) in [
            ("GET", "/updates/aaa-bbb-ccc"),
            ("GET", "/messages/aaa-bbb-ccc"),
            ("POST", "/v2/new-message"),
            ("POST", "/new-apns"),
            ("POST", "/typing/aaa-bbb-ccc"),
        ] {
            assert_eq!(status(&app, method, path, None).await, 401, "{path}");
        }
    }

    #[tokio::test]
    async fn a_bogus_bearer_token_is_refused() {
        let (app, _dir) = test_app().await;
        assert_eq!(
            status(
                &app,
                "GET",
                "/updates/aaa-bbb-ccc",
                Some(("authorization", "Bearer not-a-real-session")),
            )
            .await,
            401
        );
    }

    #[tokio::test]
    async fn a_challenge_is_issued_without_a_credential_and_spends_once() {
        let (app, dir) = test_app().await;
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v3/attest/challenge")
                    .header("content-type", "application/json")
                    .body(Body::from("{}"))
                    .expect("request"),
            )
            .await
            .expect("response");
        assert_eq!(response.status(), 200);

        let body = to_bytes(response.into_body(), 64 * 1024)
            .await
            .expect("body");
        let issued: serde_json::Value = serde_json::from_slice(&body).expect("json");
        let challenge = issued["challenge"].as_str().expect("challenge");
        assert_eq!(challenge.len(), 64);

        // Registration is what spends it, and this attestation is nonsense, so
        // the call fails. The challenge is gone either way.
        let register = |body: String| {
            let app = app.clone();
            async move {
                app.oneshot(
                    Request::builder()
                        .method("POST")
                        .uri("/v3/attest/register")
                        .header("content-type", "application/json")
                        .body(Body::from(body))
                        .expect("request"),
                )
                .await
                .expect("response")
                .status()
                .as_u16()
            }
        };
        let payload = serde_json::json!({
            "keyId": BASE64_STANDARD.encode([0u8; 32]),
            "attestation": BASE64_STANDARD.encode(b"not an attestation"),
            "challenge": challenge,
            "userId": "aaa-bbb-ccc",
        })
        .to_string();
        assert_eq!(register(payload.clone()).await, 401);
        assert_eq!(
            register(payload).await,
            401,
            "the challenge cannot be presented a second time"
        );
        drop(dir);
    }

    /// Posts a JSON body and hands back the status and the parsed body.
    async fn post_json(
        app: &Router,
        path: &str,
        body: serde_json::Value,
    ) -> (u16, serde_json::Value) {
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(path)
                    .header("content-type", "application/json")
                    .body(Body::from(body.to_string()))
                    .expect("request"),
            )
            .await
            .expect("response");
        let status = response.status().as_u16();
        let bytes = to_bytes(response.into_body(), 64 * 1024)
            .await
            .expect("body");
        (status, serde_json::from_slice(&bytes).expect("json"))
    }

    /// The client deletes its Secure Enclave key and registers a new one only
    /// when the backend says the key itself is gone, so "which 401 is this"
    /// has to survive the trip. The human sentence stays under `Unauthorized`
    /// where releases already in the field read it.
    #[tokio::test]
    async fn a_401_names_its_reason_without_moving_the_old_message() {
        let (app, _dir) = test_app().await;

        let (status, body) = post_json(
            &app,
            "/v3/attest/session",
            serde_json::json!({
                "keyId": BASE64_STANDARD.encode([9u8; 32]),
                "assertion": BASE64_STANDARD.encode(b"not an assertion"),
                "clientData": BASE64_STANDARD.encode(b"{}"),
            }),
        )
        .await;
        assert_eq!(status, 401);
        assert_eq!(body["Unauthorized"], "Attested key is unknown");
        assert_eq!(body["reason"], "key_unknown");
    }

    /// Everything else on the same route has to read as "this one request was
    /// no good", or a server-side bug turns into a key-registration loop.
    #[tokio::test]
    async fn a_spent_challenge_is_not_a_missing_key() {
        let (app, _dir) = test_app().await;

        let (status, body) = post_json(
            &app,
            "/v3/attest/register",
            serde_json::json!({
                "keyId": BASE64_STANDARD.encode([0u8; 32]),
                "attestation": BASE64_STANDARD.encode(b"not an attestation"),
                "challenge": "never-issued",
                "userId": "aaa-bbb-ccc",
            }),
        )
        .await;
        assert_eq!(status, 401);
        assert_eq!(
            body["Unauthorized"],
            "Challenge is unknown, spent, or expired"
        );
        assert_eq!(body["reason"], "challenge_invalid");
    }

    /// The 401s that predate reason codes still serialise the way they always
    /// have, so nothing that reads them has to learn a new shape at once.
    #[tokio::test]
    async fn an_unlabelled_401_keeps_the_original_body() {
        let response = ApiError::Unauthorized("Unauthorized".to_string()).into_response();
        assert_eq!(response.status(), 401);
        let bytes = to_bytes(response.into_body(), 64 * 1024)
            .await
            .expect("body");
        let body: serde_json::Value = serde_json::from_slice(&bytes).expect("json");
        assert_eq!(body, serde_json::json!({ "Unauthorized": "Unauthorized" }));
    }

    #[tokio::test]
    async fn a_legacy_caller_reaches_the_app_zone_but_not_the_crash_zone() {
        let (app, _dir) = test_app().await;
        // A legacy read gets past auth and into the handler, which then fails
        // reaching Discord. Anything other than 401 proves the key was taken.
        assert_ne!(
            status(
                &app,
                "GET",
                "/updates/aaa-bbb-ccc",
                Some(("x-api-key", LEGACY_KEY))
            )
            .await,
            401
        );
        assert_eq!(
            status(&app, "GET", "/v2/crashes", Some(("x-api-key", LEGACY_KEY))).await,
            401
        );
    }
}
