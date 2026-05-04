use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    time::Duration,
};

use anyhow::{Context, Result};
use futures::StreamExt;
use serde::{Deserialize, Serialize};

use crate::cli::RoamCli;
use crate::database::DeviceInfo;
use crate::symbolicate::{RoamDebugInfo, SymbolicationClient};

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MatchedDsym {
    uuid: String,
    breakpad_id: String,
    filename: String,
    #[allow(dead_code)]
    size_bytes: u64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LeasedPayload {
    id: String,
    payload_index: i64,
    #[allow(dead_code)]
    device_id: String,
    #[serde(deserialize_with = "string_to_i64")]
    #[allow(dead_code)]
    thread_id: i64,
    metric_payload_json: String,
    diagnostics: serde_json::Value,
    installation_info: serde_json::Value,
    matched_dsyms: Vec<MatchedDsym>,
    attempts: i64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LeaseResponse {
    payloads: Vec<LeasedPayload>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ResultRequest<'a> {
    id: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    symbolicated_text: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<&'a str>,
}

fn string_to_i64<'de, D>(deserializer: D) -> Result<i64, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    s.parse().map_err(serde::de::Error::custom)
}

#[derive(Clone)]
struct WorkerApi {
    base_url: String,
    api_key: String,
    http: reqwest::Client,
}

impl WorkerApi {
    fn new(base_url: String, api_key: String) -> Result<Self> {
        let http = reqwest::Client::builder()
            // Lease responses can include payload bodies up to 70 MB and dSYM
            // metadata for many UUIDs; budget generously. Individual dSYM
            // downloads use their own request and may take longer for large
            // dSYMs over slow links.
            .timeout(Duration::from_secs(300))
            .build()
            .context("building reqwest client for symbolication worker")?;
        Ok(Self {
            base_url,
            api_key,
            http,
        })
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.base_url.trim_end_matches('/'), path)
    }

    async fn lease(&self, n: i64) -> Result<LeaseResponse> {
        let resp = self
            .http
            .get(self.url(&format!("/v2/symbolicate/lease?n={n}")))
            .header("x-api-key", &self.api_key)
            .send()
            .await
            .context("requesting symbolication lease")?
            .error_for_status()
            .context("symbolication lease returned error status")?;
        resp.json::<LeaseResponse>()
            .await
            .context("parsing symbolication lease response")
    }

    async fn fetch_dsym(&self, uuid: &str) -> Result<Vec<u8>> {
        let resp = self
            .http
            .get(self.url(&format!("/v2/symbolicate/dsym/{uuid}")))
            .header("x-api-key", &self.api_key)
            // dSYMs can run hundreds of MB; allow a much longer timeout than
            // the default for control-plane calls.
            .timeout(Duration::from_secs(60 * 60))
            .send()
            .await
            .with_context(|| format!("fetching dSYM {uuid}"))?
            .error_for_status()
            .with_context(|| format!("dSYM fetch returned error status for {uuid}"))?;
        let bytes = resp
            .bytes()
            .await
            .with_context(|| format!("reading dSYM body for {uuid}"))?;
        Ok(bytes.to_vec())
    }

    async fn report_success(&self, id: &str, text: &str) -> Result<()> {
        self.http
            .post(self.url("/v2/symbolicate/result"))
            .header("x-api-key", &self.api_key)
            .json(&ResultRequest {
                id,
                symbolicated_text: Some(text),
                error: None,
            })
            .send()
            .await
            .context("posting symbolication result")?
            .error_for_status()
            .context("symbolication result returned error status")?;
        Ok(())
    }

    async fn report_failure(&self, id: &str, error: &str) -> Result<()> {
        self.http
            .post(self.url("/v2/symbolicate/result"))
            .header("x-api-key", &self.api_key)
            .json(&ResultRequest {
                id,
                symbolicated_text: None,
                error: Some(error),
            })
            .send()
            .await
            .context("posting symbolication failure")?
            .error_for_status()
            .context("symbolication failure returned error status")?;
        Ok(())
    }
}

pub async fn run(cli: RoamCli) -> Result<()> {
    let dsym_dir = cli
        .dsym_dir()
        .await
        .context("preparing dSYM cache directory")?;
    let client = SymbolicationClient::new(dsym_dir.clone());
    let api = WorkerApi::new(cli.backend_url.clone(), cli.backend_api_key.clone())?;

    let payloads_dir = PathBuf::from(&cli.data_dir).join("worker-payloads");
    tokio::fs::create_dir_all(&payloads_dir)
        .await
        .with_context(|| format!("creating worker payloads dir {}", payloads_dir.display()))?;

    let batch_size = cli.symbolicate_batch_size.max(1);
    let idle = Duration::from_secs(cli.symbolicate_idle_seconds);

    tracing::info!(
        backend_url = %cli.backend_url,
        dsym_dir = %dsym_dir.display(),
        batch_size,
        idle_seconds = idle.as_secs(),
        "Symbolication worker starting"
    );

    loop {
        let lease = match api.lease(batch_size as i64).await {
            Ok(l) => l,
            Err(err) => {
                tracing::error!(?err, "Failed to lease pending symbolications; backing off");
                tokio::time::sleep(Duration::from_secs(30)).await;
                continue;
            }
        };

        if lease.payloads.is_empty() {
            tracing::info!(
                idle_seconds = idle.as_secs(),
                "No pending symbolications; sleeping before next poll"
            );
            tokio::time::sleep(idle).await;
            continue;
        }

        tracing::info!(
            count = lease.payloads.len(),
            "Leased pending symbolications"
        );

        ensure_dsyms_cached(&api, &client, &lease.payloads).await;

        let parallelism = batch_size;
        futures::stream::iter(lease.payloads)
            .map(|payload| {
                let client = client.clone();
                let api = api.clone();
                let payloads_dir = payloads_dir.clone();
                async move {
                    let id = payload.id.clone();
                    let attempts = payload.attempts;
                    if let Err(err) =
                        symbolicate_and_upload(&client, &api, &payloads_dir, payload).await
                    {
                        tracing::error!(?err, %id, attempts, "Worker symbolication failed");
                        if let Err(report_err) = api.report_failure(&id, &format!("{err:#}")).await
                        {
                            tracing::error!(?report_err, %id, "Could not report failure to server");
                        }
                    }
                }
            })
            .buffer_unordered(parallelism)
            .collect::<Vec<()>>()
            .await;
        // Restart loop immediately — keep draining until lease returns 0.
    }
}

async fn ensure_dsyms_cached(
    api: &WorkerApi,
    client: &SymbolicationClient,
    payloads: &[LeasedPayload],
) {
    let mut needed: BTreeMap<String, MatchedDsym> = BTreeMap::new();
    for p in payloads {
        for d in &p.matched_dsyms {
            needed.entry(d.uuid.clone()).or_insert_with(|| d.clone());
        }
    }

    for (uuid, dsym) in needed {
        if client.dsym_path_for_uuid(&uuid).is_some() {
            continue;
        }
        let bytes = match api.fetch_dsym(&uuid).await {
            Ok(b) => b,
            Err(err) => {
                tracing::warn!(?err, %uuid, "Could not fetch dSYM; binary will not symbolicate");
                continue;
            }
        };

        let storage_dir = client.root().join("uploads").join("worker").join(&uuid);
        if let Err(err) = tokio::fs::create_dir_all(&storage_dir).await {
            tracing::warn!(?err, %uuid, "Could not create worker dSYM dir");
            continue;
        }
        let storage_path = storage_dir.join(&dsym.filename);
        if let Err(err) = tokio::fs::write(&storage_path, &bytes).await {
            tracing::warn!(?err, %uuid, path = %storage_path.display(), "Could not write fetched dSYM");
            continue;
        }
        if let Err(err) = client.index_dsym_file(&uuid, &dsym.breakpad_id, &storage_path) {
            tracing::warn!(?err, %uuid, "Could not index fetched dSYM into cache");
        } else {
            tracing::info!(%uuid, bytes = bytes.len(), "Fetched and indexed dSYM");
        }
    }
}

async fn symbolicate_and_upload(
    client: &SymbolicationClient,
    api: &WorkerApi,
    payloads_dir: &Path,
    payload: LeasedPayload,
) -> Result<()> {
    let installation_info: DeviceInfo = serde_json::from_value(payload.installation_info)
        .context("decoding installation info from lease response")?;
    let diagnostics: RoamDebugInfo = serde_json::from_value(payload.diagnostics)
        .context("decoding diagnostics from lease response")?;

    let payload_path = payloads_dir.join(format!("{}.json", payload.id));
    tokio::fs::write(&payload_path, payload.metric_payload_json.as_bytes())
        .await
        .with_context(|| format!("writing leased payload to {}", payload_path.display()))?;

    let symbolicated_path = client
        .symbolicate_diagnostics(&diagnostics, &installation_info, &payload_path)
        .await;

    let symbolicated_path = match symbolicated_path {
        Ok(p) => p,
        Err(err) => {
            let _ = tokio::fs::remove_file(&payload_path).await;
            return Err(err.context("symbolicate_diagnostics failed"));
        }
    };

    let report = tokio::fs::read_to_string(&symbolicated_path)
        .await
        .with_context(|| format!("reading {}", symbolicated_path.display()))?;

    api.report_success(&payload.id, &report).await?;

    if let Err(err) = tokio::fs::remove_file(&payload_path).await {
        if err.kind() != std::io::ErrorKind::NotFound {
            tracing::warn!(?err, path = %payload_path.display(), "Failed to remove worker payload file");
        }
    }
    if let Err(err) = tokio::fs::remove_file(&symbolicated_path).await {
        if err.kind() != std::io::ErrorKind::NotFound {
            tracing::warn!(?err, path = %symbolicated_path.display(), "Failed to remove symbolicated report file");
        }
    }

    tracing::info!(
        id = %payload.id,
        index = payload.payload_index,
        "Symbolication completed and uploaded"
    );
    Ok(())
}
