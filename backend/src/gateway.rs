use serenity::{
    all::{Context, EventHandler, GatewayIntents, Message, Ready, ResumedEvent},
    async_trait, Client,
};

use crate::AppContext;

pub async fn setup_client(ctx: AppContext) -> Result<Client, serenity::Error> {
    // Intents are a bitflag, bitwise operations can be used to dictate which intents to use
    let intents = GatewayIntents::GUILD_MESSAGES | GatewayIntents::MESSAGE_CONTENT;
    let token = ctx.discord_token().to_string();
    let handler = Handler::new(ctx);
    // Build our client.
    return Client::builder(token, intents).event_handler(handler).await;
}

struct Handler {
    ctx: AppContext,
}

impl Handler {
    pub fn new(ctx: AppContext) -> Handler {
        Handler { ctx }
    }
}

#[async_trait]
impl EventHandler for Handler {
    // This event will be dispatched for guilds, but not for direct messages.
    async fn message(&self, _ctx: Context, msg: Message) {
        tracing::info!(
            "Received gateway message: {} at channel {}",
            msg.content,
            msg.channel_id
        );

        self.ctx
            .send_pushes()
            .await
            .map_err(|e| tracing::error!("Error sending apple alerts: {:?}", e))
            .ok();
    }

    async fn ready(&self, _: Context, ready: Ready) {
        tracing::info!("{} is connected!", ready.user.name);
    }

    async fn resume(&self, _: Context, _: ResumedEvent) {
        tracing::info!("Handler resumed!");
    }
}
