use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, sync::Arc};

#[derive(Debug, Deserialize, Serialize)]
pub struct DebugError {
    pub message: String,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct BadResponseError {
    pub message: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LogEntry {
    pub message: String,
    pub timestamp: DateTime<Utc>,
    pub level: Option<String>,
    pub category: Option<String>,
    pub subsystem: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResponseData {
    pub headers: HashMap<String, String>,
    pub status_code: i32,
    pub data: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceDebugInfo {
    pub device: DeviceAppEntity,
    pub success_response: Option<ResponseData>,
    pub error_response: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InstallationInfo {
    pub user_id: String,
    pub build_version: Option<String>,
    pub release_version: Option<String>,
    pub os_platform: Option<String>,
    pub os_version: Option<String>,
    pub user_locale: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DebugLanguage {
    pub device_language_code: String,
    pub translated_language_code: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RoamDebugInfo {
    pub installation_info: InstallationInfo,
    pub user_defaults: HashMap<String, String>,
    pub space_on_device: Option<i64>,
    pub devices: Vec<DeviceDebugInfo>,
    pub app_links: Vec<AppLinkAppEntity>,
    pub interfaces: Vec<Addressed4NetworkInterface>,
    pub logs: Vec<LogEntry>,
    pub debug_errors: Vec<String>,
    pub language: DebugLanguage,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Addressed4NetworkInterface {
    pub name: String,
    pub family: i32,
    pub family_description: String,
    pub address: String, // IP4Address as string
    pub netmask: String, // IP4Address as string
    pub flags: u32,
    pub flag_list: Vec<String>,
    pub interface_type: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeviceAppEntity {
    pub udn: String,
    pub name: String,
    pub location: String,
    pub last_selected_at: Option<DateTime<Utc>>,
    pub last_online_at: Option<DateTime<Utc>>,
    pub last_scanned_at: Option<DateTime<Utc>>,
    pub last_sent_to_watch: Option<DateTime<Utc>>,
    pub deleted_at: Option<DateTime<Utc>>,
    pub hidden_at: Option<DateTime<Utc>>,
    pub power_mode: Option<String>,
    pub network_type: Option<String>,
    pub wifi_mac: Option<String>,
    pub ethernet_mac: Option<String>,
    pub rtcp_port: Option<u16>,
    pub supports_datagram: Option<bool>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppLinkAppEntity {
    pub id: String,
    pub r#type: String, // 'type' is a keyword in Rust, so we use 'r#type'
    pub name: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RoamMetricDiagnosticPayload {
    pub cpu_exception_diagnostics: Vec<CpuExceptionDiagnostic>,
    pub disk_write_exception_diagnostics: Vec<DiskWriteExceptionDiagnostic>,
    pub hang_diagnostics: Vec<HangDiagnostic>,
    pub app_launch_diagnostics: Vec<AppLaunchDiagnostic>,
    pub crash_diagnostics: Vec<CrashDiagnostic>,
    pub time_stamp_begin: DateTime<Utc>,
    pub time_stamp_end: DateTime<Utc>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct MetaData {
    pub application_build_version: String,
    pub device_type: String,
    pub is_test_flight_app: bool,
    pub low_power_mode_enabled: bool,
    pub os_version: String,
    pub platform_architecture: String,
    pub region_format: String,
    pub pid: i32,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SignpostRecord {
    pub begin_time_stamp: DateTime<Utc>,
    pub category: String,
    pub duration: Option<f64>, // Duration in seconds
    pub end_time_stamp: Option<DateTime<Utc>>,
    pub is_interval: bool,
    pub name: String,
    pub subsystem: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HangDiagnostic {
    pub hang_duration: f64,
    pub stack_trace: Option<StackTrace>,
    pub meta_data: MetaData,
    pub application_version: String,
    pub signpost_data: Vec<SignpostRecord>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CrashDiagnostic {
    pub exception_type: Option<i64>,
    pub exception_code: Option<i64>,
    pub signal: Option<i64>,
    pub exception_reason: Option<CrashDiagnosticObjectiveCExceptionReason>,
    pub termination_reason: Option<String>,
    pub virtual_memory_region_info: Option<String>,
    pub stack_trace: Option<StackTrace>,
    pub meta_data: MetaData,
    pub application_version: String,
    pub signpost_data: Vec<SignpostRecord>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CrashDiagnosticObjectiveCExceptionReason {
    pub arguments: Vec<String>,
    pub class_name: String,
    pub composed_message: String,
    pub exception_name: String,
    pub exception_type: String,
    pub format_string: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DiskWriteExceptionDiagnostic {
    pub total_writes: f64,
    pub stack_trace: Option<StackTrace>,
    pub meta_data: MetaData,
    pub application_version: String,
    pub signpost_data: Vec<SignpostRecord>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppLaunchDiagnostic {
    pub launch_duration: f64,
    pub stack_trace: Option<StackTrace>,
    pub meta_data: MetaData,
    pub application_version: String,
    pub signpost_data: Vec<SignpostRecord>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CpuExceptionDiagnostic {
    pub total_cpu_time: f64,
    pub total_sampled_time: f64,
    pub stack_trace: Option<StackTrace>,
    pub meta_data: MetaData,
    pub application_version: String,
    pub signpost_data: Vec<SignpostRecord>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StackTrace {
    pub call_stack_per_thread: bool,
    pub call_stacks: Vec<CallStack>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CallStack {
    pub thread_attributed: bool,
    pub call_stack_root_frames: Vec<Frame>,
}

#[derive(Debug, Deserialize, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Frame {
    pub binary_uuid: String,
    pub offset_into_binary_text_segment: i64,
    pub sample_count: i64,
    pub binary_name: String,
    pub address: i64,
    pub subframes: Option<Arc<Vec<Frame>>>,
}
