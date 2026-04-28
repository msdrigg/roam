use std::path::PathBuf;

use clap::Parser;

/// A simple application to manage Discord and backend configuration
#[derive(Parser)]
#[command(author = "Your Name", version = "1.0", about = "Configuration Manager", long_about = None)]
pub struct RoamCli {
    /// Discord Help Channel ID
    #[arg(long, env)]
    pub discord_help_channel: i64,

    /// Discord Bot ID
    #[arg(long, env)]
    pub discord_bot_id: i64,

    /// Discord Guild ID
    #[arg(long, env)]
    pub discord_guild_id: i64,

    /// Discord Token
    #[arg(long, env)]
    pub discord_token: String,

    /// Backend URL
    #[arg(long, env)]
    pub backend_url: String,

    /// Backend API Key
    #[arg(long, env)]
    pub backend_api_key: String,

    /// APNS Key ID
    #[arg(long, env)]
    pub apns_key_id: String,

    /// APNS Team ID
    #[arg(long, env)]
    pub apns_team_id: String,

    /// APNS Private Key
    #[arg(long, env)]
    pub apns_private_key: String,

    /// APNS Bundle ID
    #[arg(long, env)]
    pub apns_bundle_id: String,

    /// Database Path
    #[arg(long, env)]
    pub data_dir: String,

    /// Log Jaeger
    #[arg(long, env)]
    pub log_jaeger: bool,

    /// HTTP Port
    /// Default: 8080
    #[arg(long, env, default_value = "8080")]
    pub port: u16,

    /// Disable APNS
    #[arg(long, env)]
    pub apns_disabled: bool,

    /// Enable the AI responder Discord bot
    #[arg(long, env, default_value = "false")]
    pub ai_responder_enabled: bool,

    /// Discord Token for the AI responder bot
    #[arg(long, env)]
    pub ai_responder_discord_token: Option<String>,

    /// Discord Bot ID for the AI responder bot
    #[arg(long, env)]
    pub ai_responder_discord_bot_id: Option<i64>,

    /// Discord user ID to mention when the AI responder escalates to a human
    #[arg(long, env)]
    pub ai_responder_human_support_user_id: Option<i64>,

    /// OpenAI API key used by the AI responder
    #[arg(long, env)]
    pub openai_api_key: Option<String>,

    /// OpenAI model used by the AI responder
    #[arg(long, env, default_value = "gpt-5.5")]
    pub ai_responder_model: String,

    /// Delay before the AI responder answers the latest user message
    #[arg(long, env, default_value = "30")]
    pub ai_responder_delay_seconds: u64,

    /// Local docs directory used to build the AI responder docs search index
    #[arg(long, env, default_value = "../docs/src/pages")]
    pub ai_responder_docs_dir: String,
}

impl RoamCli {
    pub async fn dsym_dir(&self) -> Result<PathBuf, std::io::Error> {
        let mut path = PathBuf::from(&self.data_dir);
        path.push("dsym");
        if !path.exists() {
            tokio::fs::create_dir_all(&path).await?;
        }
        // Normalize the path to ensure it is absolute
        path = tokio::fs::canonicalize(path).await?;
        Ok(path)
    }
}
