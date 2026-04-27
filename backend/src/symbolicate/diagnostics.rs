use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::database::DeviceInfo;

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
pub struct DebugLanguage {
    pub device_language_code: String,
    pub translated_language_code: String,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RoamDebugInfo {
    pub installation_info: DeviceInfo,
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
