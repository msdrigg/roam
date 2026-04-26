mod diagnostics;
mod sym;

use std::{fmt::Display, str::FromStr};

pub use diagnostics::RoamDebugInfo;
pub use sym::{DsymUploadMetadata, StoredDsymArchive, SymbolicationClient};

#[allow(clippy::enum_variant_names)]
pub enum ApplePlatformVersion {
    IOs,
    MacOs,
    VisionOs,
    WatchOs,
}

impl Display for ApplePlatformVersion {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ApplePlatformVersion::IOs => write!(f, "iOS"),
            ApplePlatformVersion::MacOs => write!(f, "macOS"),
            ApplePlatformVersion::VisionOs => write!(f, "visionOS"),
            ApplePlatformVersion::WatchOs => write!(f, "watchOS"),
        }
    }
}
impl FromStr for ApplePlatformVersion {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "ios" => Ok(ApplePlatformVersion::IOs),
            "macos" => Ok(ApplePlatformVersion::MacOs),
            "visionos" => Ok(ApplePlatformVersion::VisionOs),
            "watchos" => Ok(ApplePlatformVersion::WatchOs),
            _ => Err(anyhow::anyhow!("Unknown OS version: {}", s)),
        }
    }
}
