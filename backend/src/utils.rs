use axum::http::StatusCode;
use serde::{Deserialize, Deserializer, Serializer};

pub fn serialize_reqwest<S>(error: &reqwest::Error, serializer: S) -> Result<S::Ok, S::Error>
where
    S: serde::Serializer,
{
    serializer.serialize_str(&error.to_string())
}

pub fn serialize_anyhow<S>(error: &anyhow::Error, serializer: S) -> Result<S::Ok, S::Error>
where
    S: serde::Serializer,
{
    serializer.serialize_str(&error.to_string())
}

pub fn serialize_status_code<S>(status: &StatusCode, serializer: S) -> Result<S::Ok, S::Error>
where
    S: serde::Serializer,
{
    serializer.serialize_u16(status.as_u16())
}

pub fn string_to_i64<'de, D>(deserializer: D) -> Result<i64, D::Error>
where
    D: Deserializer<'de>,
{
    let s: &str = Deserialize::deserialize(deserializer)?;
    s.parse::<i64>().map_err(serde::de::Error::custom)
}

pub fn i64_to_string<S>(number: &i64, serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    serializer.serialize_str(&number.to_string())
}

pub fn string_to_i64_optional<'de, D>(deserializer: D) -> Result<Option<i64>, D::Error>
where
    D: Deserializer<'de>,
{
    let s: Option<&str> = Deserialize::deserialize(deserializer)?;
    match s {
        Some(s) => s.parse::<i64>().map(Some).map_err(serde::de::Error::custom),
        None => Ok(None),
    }
}
