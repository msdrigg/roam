use crate::{
    database::{DeviceInfo, User, UserUpdate},
    discord::DiscordFile,
    utils::string_to_i64_optional,
};
use anyhow::Context;
use axum::{
    body::{to_bytes, Body},
    extract::{Path, Query, State},
    http::{HeaderName, Request},
    routing::post,
    Json,
};
use axum::{routing::get, serve::ListenerExt, Router};
pub use error::ApiError;
use futures::FutureExt;
use opentelemetry::trace::{SpanKind, TraceContextExt};
use serde::Serialize;
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

pub async fn start_server(app_context: AppContext) -> anyhow::Result<JoinHandle<()>> {
    let port = app_context.port;
    let router = build_app(app_context);
    let router = router.clone();
    let future = async move {
        let tcp_listener = TcpListener::bind(format!("0.0.0.0:{port}"))
            .await
            .context(format!("Error binding to port {}", port))?
            .tap_io(|tcp_stream| {
                if let Err(err) = tcp_stream.set_nodelay(true) {
                    tracing::info!("failed to set TCP_NODELAY on incoming connection: {err:#}");
                }
            });

        let server = axum::serve(tcp_listener, router.into_make_service());
        server.await.context("error running HTTP server")?;
        anyhow::Result::Ok(())
    }
    .map(|_: Result<(), anyhow::Error>| ());

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
        .route("/new-message", post(new_message))
        .route(
            "/upload-diagnostics/{diagnostic_key}",
            post(upload_diagnostics),
        )
        .route("/user-info/{user_id}", get(get_user_info))
        .route("/thread-info/{thread_id}", get(get_thread_info))
        .with_state(app_context)
}

#[derive(serde::Deserialize)]
struct GetMessagesQuery {
    #[serde(default, deserialize_with = "string_to_i64_optional")]
    after: Option<i64>,
}

async fn get_user_messages(
    Path(device_id): Path<String>,
    Query(query): Query<GetMessagesQuery>,
    State(app_context): State<AppContext>,
) -> Result<Json<Vec<DiscordMessage>>, ApiError> {
    let user = app_context
        .db_client()
        .get_user_with_id(&device_id)
        .await
        .map_err(ApiError::DatabaseError)?
        .ok_or_else(|| ApiError::NotFound(format!("User with id {} not found", device_id)))?;

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
struct MessageRequest {
    content: Option<String>,
    apns_token: Option<String>,
    user_id: String,
    #[serde(default)]
    installation_info: Option<DeviceInfo>,
}

async fn new_message(
    State(app_context): State<AppContext>,
    Json(message_request): Json<MessageRequest>,
) -> Result<String, ApiError> {
    let MessageRequest {
        content,
        apns_token,
        user_id: device_id,
        installation_info,
    } = message_request;

    if content.is_none() && apns_token.is_none() {
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

    if let Some(content) = content {
        app_context
            .discord_client()
            .send_message(user.thread_id, &content)
            .await?;
    }

    Ok("OK".to_string())
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
        .map_err(|e| ApiError::BadRequest(format!("Error reading body: {}", e)))?;
    app_context
        .discord_client()
        .send_attachment(
            user.thread_id,
            DiscordFile {
                content_type: "application/json".to_string(),
                name: "diagnostics.json".to_string(),
                data: body.to_vec(),
            },
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
    Query(query): Query<GetMessagesQuery>,
    Path(user_id): Path<String>,
    State(app_context): State<AppContext>,
) -> Result<Json<UserInfoResponse>, ApiError> {
    let user = app_context
        .db_client()
        .get_user_with_id(&user_id)
        .await
        .map_err(ApiError::DatabaseError)?
        .ok_or_else(|| ApiError::NotFound(format!("User with id {} not found", user_id)))?;

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

async fn get_thread_info(
    Query(query): Query<GetMessagesQuery>,
    Path(thread_id): Path<i64>,
    State(app_context): State<AppContext>,
) -> Result<Json<UserInfoResponse>, ApiError> {
    let user = app_context
        .db_client()
        .get_user_with_thread(thread_id)
        .await
        .map_err(ApiError::DatabaseError)?
        .ok_or_else(|| ApiError::NotFound(format!("Thread with id {} not found", thread_id)))?;

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
                Self::DiscordError(_) => StatusCode::INTERNAL_SERVER_ERROR,
                Self::BadRequest(_) => StatusCode::BAD_REQUEST,
            }
        }
    }
}
