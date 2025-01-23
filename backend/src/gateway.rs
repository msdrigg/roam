use serenity::{
    all::{Context, EventHandler, GatewayIntents, Message, Ready, ResumedEvent},
    async_trait, Client,
};

use crate::{discord::DiscordMessage, AppContext};

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
        if msg.author.id == self.ctx.discord_bot_id as u64 {
            tracing::info!(
                "Received gateway message from bot at channel {}",
                msg.channel_id
            );
            return;
        } else {
            tracing::info!(
                "Received gateway message from non-bot at channel {}",
                msg.channel_id
            );
        }
        let thread_id = u64::from(msg.channel_id) as i64;
        let message_id = u64::from(msg.id) as i64;

        if let Err(err) = self
            .ctx
            .db_client()
            .set_last_alerted_message(message_id)
            .await
        {
            tracing::error!("Error setting last alerted message: {:?}", err);
            return;
        }

        match self.ctx.db_client().get_user_with_thread(thread_id).await {
            Ok(Some(user)) => {
                self.ctx
                    .notify_user(
                        &user,
                        DiscordMessage::new(
                            message_id,
                            msg.content,
                            u64::from(msg.author.id) as i64,
                            u8::from(msg.kind),
                        ),
                    )
                    .await
                    .inspect_err(|e| tracing::error!("Error sending apple alerts: {:?}", e))
                    .ok();
            }
            Ok(None) => {
                tracing::info!("No user found for thread {}", thread_id);
            }
            Err(e) => {
                tracing::error!("Error getting user for thread {}: {:?}", thread_id, e);
            }
        }
    }

    async fn ready(&self, _: Context, ready: Ready) {
        tracing::info!("{} is connected!", ready.user.name);
    }

    async fn resume(&self, _: Context, _: ResumedEvent) {
        tracing::info!("Handler resumed!");
    }
}
