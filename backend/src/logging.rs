use std::env;
use std::str::FromStr;

use opentelemetry::trace::TracerProvider;
use opentelemetry_otlp::{SpanExporter, WithExportConfig};
use opentelemetry_sdk::{runtime, trace as sdktrace};
use tracing_subscriber::Registry;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

use crate::cli::RoamCli;

const SERVICE_NAME: &str = "cloud-backend";
const DEFAULT_LOG_FILTER: &str = "info,sqlx=warn";

pub fn setup_logging(cli: &RoamCli) {
    let filter = EnvFilter::from_str(
        &env::var("RUST_LOG").unwrap_or_else(|_| DEFAULT_LOG_FILTER.to_string()),
    )
    .expect("RUST_LOG should be a valid filter");

    let jaeger_layer = if cli.log_jaeger {
        let exporter = SpanExporter::builder()
            .with_tonic()
            .with_endpoint("http://localhost:4317")
            .build()
            .expect("Failed to create Jaeger exporter");

        let provider = sdktrace::TracerProvider::builder()
            .with_batch_exporter(exporter, runtime::Tokio)
            .build();

        let telemetry = tracing_opentelemetry::layer().with_tracer(provider.tracer(SERVICE_NAME));

        Some(telemetry)
    } else {
        None
    };

    let stdout_layer = fmt::Layer::new();

    Registry::default()
        .with(jaeger_layer)
        .with(stdout_layer)
        .with(filter)
        .init();
}
