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
}
