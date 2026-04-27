use crate::{
    database::{DeviceInfo, User, UserUpdate},
    discord::{DiscordAuthor, DiscordFile, DiscordFileUpload, DiscordMessageOptions},
    presence::UserPresenceInfo,
    symbolicate::{DsymUploadMetadata, RoamDebugInfo},
    utils::{base64_data_de, i64_to_string, string_to_i64_optional},
};
use anyhow::Context;
use axum::{
    body::{to_bytes, Body},
    extract::{DefaultBodyLimit, Path, Query, State},
    http::{HeaderName, Request},
    routing::post,
    Json,
};
use axum::{routing::get, serve::ListenerExt, Router};
use base64::{prelude::BASE64_STANDARD, Engine};
pub use error::ApiError;
use futures::{stream, StreamExt};
use opentelemetry::trace::{SpanKind, TraceContextExt};
use serde::{Deserialize, Serialize};
use tokio::{net::TcpListener, task::JoinHandle};
use tower_http::{
    catch_panic::CatchPanicLayer,
    cors::{AllowHeaders, AllowMethods, AllowOrigin, CorsLayer},
    request_id::{MakeRequestId, PropagateRequestIdLayer, RequestId, SetRequestIdLayer},
    trace::{DefaultOnFailure, DefaultOnRequest, DefaultOnResponse, TraceLayer},
    validate_request::{ValidateRequest, ValidateRequestHeaderLayer},
};
use tracing::{Level, Span};
use tracing_opentelemetry::OpenTelemetrySpanExt;
use uuid::Uuid;

use crate::{discord::DiscordMessage, AppContext};

const UPLOAD_LIMIT: usize = 10 * 1024 * 1024;

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
        .layer(ValidateRequestHeaderLayer::custom(ValidateApiKey::new(
            app_context.backend_api_key,
        )))
        .layer(PropagateRequestIdLayer::new(x_request_id))
        .layer(CatchPanicLayer::new())
        .layer(DefaultBodyLimit::max(
            1024 * 1024 * 70, // 70 MB
        ))
}

#[derive(Clone, Debug)]
struct ValidateApiKey {
    api_key: String,
}

impl ValidateApiKey {
    fn new(api_key: String) -> Self {
        Self { api_key }
    }
}

impl ValidateRequest<axum::body::Body> for ValidateApiKey {
    type ResponseBody = axum::body::Body;

    fn validate(
        &mut self,
        request: &mut Request<axum::body::Body>,
    ) -> Result<(), axum::http::Response<Self::ResponseBody>> {
        let path = request.uri().path();
        // If path is /health, don't require an API key
        if path == "/health" {
            return Ok(());
        }
        let api_key = request
            .headers()
            .get("x-api-key")
            .and_then(|value| value.to_str().ok())
            .unwrap_or_default();

        if api_key != self.api_key {
            return Err(axum::http::Response::builder()
                .status(401)
                .body(Body::from("Unauthorized"))
                .unwrap());
        }

        Ok(())
    }
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

fn router(app_context: AppContext) -> Router {
    Router::new()
        .route("/health", get(|| async { "Healthy!" }))
        .route("/", get(|| async { "Hello, world!" }))
        .route("/messages/{user_id}", get(get_user_messages))
        .route("/updates/{user_id}", get(get_user_state))
        .route("/new-message", post(new_message_old))
        .route("/v2/new-message", post(new_message))
        .route("/v2/upload-diagnostics", post(upload_metric_diagnostics))
        .route("/v2/upload-roam-dsym", post(upload_roam_dsym))
        .route("/new-apns", post(new_apns))
        .route(
            "/upload-diagnostics/{diagnostic_key}",
            post(upload_diagnostics),
        )
        .route("/user-info/{user_id}", get(get_user_info))
        .route("/typing/{user_id}", post(update_user_typing))
        .route("/thread-info/{thread_id}", get(get_thread_info))
        .with_state(app_context)
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
        let ai_message = Some(message.author.id) == ai_bot_id;
        let human_support_message = Some(message.author.id) == human_support_user_id;
        let attachments = stream::iter(message.attachments.into_iter())
            .map(|attachment| async move {
                let url = attachment.url;
                let id = attachment.id;
                let data = match reqwest::get(&url).await {
                    Ok(response) => match response.bytes().await {
                        Ok(bytes) => bytes.to_vec(),
                        Err(e) => {
                            return Err(ApiError::BadRequest(format!(
                                "Error reading attachment: {e}"
                            )))
                        }
                    },
                    Err(e) => {
                        return Err(ApiError::BadRequest(format!(
                            "Error downloading attachment: {e}"
                        )))
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
    State(app_context): State<AppContext>,
) -> Result<Json<UserState>, ApiError> {
    let user = app_context
        .get_or_create_user(&device_id, &UserUpdate::default())
        .await?;

    let messages = app_context
        .discord_client()
        .get_messages_in_thread(user.thread_id, query.after)
        .await?
        .into_iter()
        .filter(|m| !m.is_hidden())
        .map(|m| m.normalize());
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
    State(app_context): State<AppContext>,
) -> Result<Json<Vec<DiscordMessage>>, ApiError> {
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
    Json(req): Json<ApnsRequest>,
) -> Result<String, ApiError> {
    let ApnsRequest {
        apns_token,
        user_id: device_id,
        installation_info,
    } = req;

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
    Json(diagnostic_request): Json<DiagnosticRequest>,
) -> Result<(), ApiError> {
    let DiagnosticRequest {
        user_id: device_id,
        installation_info,
        diagnostics,
        metrics_payloads,
    } = diagnostic_request;

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
            ":ninja: MK Diagnostics Payload Received",
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
            ":ninja: MK Diagnostics Supporting Data",
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

    for (idx, payload_b64) in metrics_payloads.iter().enumerate() {
        let payload = match BASE64_STANDARD.decode(payload_b64) {
            Ok(data) => data,
            Err(e) => {
                tracing::error!(?payload_b64, "Error decoding base64 payload: {}", e);
                continue;
            }
        };

        let symbolication_dir = app_context.data_dir.join("symbolication").join(&device_id);
        let metric_uuid = Uuid::new_v4();
        tokio::fs::create_dir_all(&symbolication_dir)
            .await
            .map_err(|e| ApiError::BadRequest(format!("Error creating symbolication dir: {e}")))?;
        let metric_file_path = symbolication_dir.join(format!("{metric_uuid}.json"));
        tokio::fs::write(&metric_file_path, payload)
            .await
            .map_err(|e| ApiError::BadRequest(format!("Error writing metric file: {e}")))?;

        let symbolicated = match app_context
            .symbolicate_diagnostics(&diagnostics, &installation_info, &metric_file_path)
            .await
        {
            Ok(s) => s,
            Err(e) => {
                tracing::error!(?e, "Error creating symbolicated diagnostics");
                continue;
            }
        };

        let report = match tokio::fs::read_to_string(&symbolicated)
            .await
            .map_err(|e| ApiError::SymbolicationError(anyhow::anyhow!(e)))
        {
            Ok(report) => report,
            Err(e) => {
                tracing::error!(?e, "Error reading symbolicated diagnostics");
                continue;
            }
        };

        app_context
            .discord_client()
            .send_message(
                user.thread_id,
                &format!(
                    ":ninja: MK Diagnostics {} Symbolicated at {}",
                    idx,
                    symbolicated.display()
                ),
                Some(DiscordFileUpload {
                    content_type: "text/plain".to_string(),
                    filename: "symbolicated.txt".to_string(),
                    data: report.as_bytes().to_vec(),
                    paired_messages: vec![],
                }),
                Some(&DiscordMessageOptions::default()),
            )
            .await?;
    }

    Ok(())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DsymUploadRequest {
    bundle_identifier: String,
    app_version: String,
    build_version: String,
    platform: String,
    #[serde(deserialize_with = "base64_data_de")]
    dsym_zip: Vec<u8>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DsymUploadResponse {
    extracted_root: String,
    indexed_debug_ids: Vec<String>,
}

async fn upload_roam_dsym(
    State(app_context): State<AppContext>,
    Json(dsym_request): Json<DsymUploadRequest>,
) -> Result<Json<DsymUploadResponse>, ApiError> {
    let DsymUploadRequest {
        bundle_identifier,
        app_version,
        build_version,
        platform,
        dsym_zip,
    } = dsym_request;

    if bundle_identifier.trim().is_empty()
        || app_version.trim().is_empty()
        || build_version.trim().is_empty()
        || platform.trim().is_empty()
    {
        return Err(ApiError::BadRequest(
            "bundleIdentifier, appVersion, buildVersion, and platform are required".to_string(),
        ));
    }

    let metadata = DsymUploadMetadata {
        bundle_identifier,
        app_version,
        build_version,
        platform,
    };
    let stored = app_context.store_dsym_zip(metadata, dsym_zip).await?;
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

async fn new_message(
    State(app_context): State<AppContext>,
    Json(message_request): Json<MessageRequestV2>,
) -> Result<Json<DiscordMessageDownload>, ApiError> {
    let MessageRequestV2 {
        content,
        user_id: device_id,
        installation_info,
        attachment,
        nonce,
    } = message_request;
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
    if app_context.ai_responder_enabled() {
        if let Some(ai_client) = app_context.ai_responder_discord_client() {
            if let Err(err) = ai_client.join_thread(user.thread_id).await {
                tracing::warn!(
                    user_id = %device_id,
                    thread_id = user.thread_id,
                    error = ?err,
                    "AI responder bot could not access or join support thread before user message"
                );
            }
        }
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
    State(app_context): State<AppContext>,
    body: Body,
) -> Result<String, ApiError> {
    // Previous versions of debug logs had a diagnostic key in the form of "xxx-xxx-xxx-date"
    let device_id = diagnostic_key[..11].to_string();
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
            ":ninja:",
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
    State(app_context): State<AppContext>,
) -> Result<(), ApiError> {
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
        body::Body,
        http::{header::WWW_AUTHENTICATE, HeaderMap, HeaderValue, StatusCode},
        response::{IntoResponse, Response},
        Json,
    };
    use serde::Serialize;

    #[derive(Debug, thiserror::Error, Serialize)]
    pub enum ApiError {
        #[error("Discord error {0}")]
        DiscordError(#[from] crate::discord::DiscordError),
        #[error("Symbolication error {0}")]
        SymbolicationError(#[serde(serialize_with = "serialize_anyhow")] anyhow::Error),
        #[error("Unauthorized")]
        Unauthorized(String),
        #[error("Bad request: {0}")]
        BadRequest(String),
        #[error("Database error {0}")]
        DatabaseError(#[serde(serialize_with = "serialize_anyhow")] anyhow::Error),
        #[error("Not found: {0}")]
        NotFound(String),
    }

    impl IntoResponse for ApiError {
        fn into_response(self) -> Response<Body> {
            let headers = match &self {
                Self::Unauthorized(_) => {
                    [(WWW_AUTHENTICATE, HeaderValue::from_static("X-API-KEY"))]
                        .into_iter()
                        .collect::<HeaderMap>()
                }
                _ => HeaderMap::default(),
            };
            match &self {
                // User errors don't get logged
                Self::Unauthorized { .. } => {}
                _ => {
                    tracing::error!(error = ?self, "Request error");
                }
            }
            let status_code = self.status_code();
            (status_code, headers, Json(self)).into_response()
        }
    }

    impl ApiError {
        fn status_code(&self) -> StatusCode {
            match self {
                Self::Unauthorized(_) => StatusCode::UNAUTHORIZED,
                Self::DatabaseError(_) => StatusCode::INTERNAL_SERVER_ERROR,
                Self::NotFound(_) => StatusCode::NOT_FOUND,
                Self::DiscordError(crate::discord::DiscordError::RateLimited { .. }) => {
                    StatusCode::TOO_MANY_REQUESTS
                }
                Self::SymbolicationError(_) => StatusCode::INTERNAL_SERVER_ERROR,
                Self::DiscordError(_) => StatusCode::INTERNAL_SERVER_ERROR,
                Self::BadRequest(_) => StatusCode::BAD_REQUEST,
            }
        }
    }
}
