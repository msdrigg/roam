use clap::Parser;
use roam_backend::{ai_responder, cli::RoamCli, gateway, logging, server, tasks};

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();
    let cli = RoamCli::parse();
    logging::setup_logging(&cli);

    let app_context = roam_backend::AppContext::new(cli)
        .await
        .expect("Error creating app context");

    let mut gateway_client = match gateway::setup_client(app_context.clone()).await {
        Ok(client) => client,
        Err(why) => {
            tracing::error!("Gateway client setup error: {:?}", why);
            return;
        }
    };
    let mut server = match server::start_server(app_context.clone()).await {
        Ok(server) => server,
        Err(why) => {
            tracing::error!("Server setup error: {why:?}");
            return;
        }
    };
    let mut task_handle = match tasks::start_tasks(app_context.clone()).await {
        Ok(handle) => handle,
        Err(why) => {
            tracing::error!("Task setup error: {why:?}");
            return;
        }
    };
    let mut ai_responder_handle = match ai_responder::start_client(app_context.clone()).await {
        Ok(handle) => handle,
        Err(why) => {
            tracing::error!("AI responder setup error: {why:?}");
            return;
        }
    };

    tokio::select! {
        res = gateway_client.start() => {
            ai_responder_handle.abort();
            if let Err(why) = res {
                tracing::error!("Gateway client error: {why:?}");
            } else {
                tracing::warn!("Gateway client exited");
            }
        }
        res = &mut server => {
            task_handle.abort();
            ai_responder_handle.abort();
            if let Err(why) = res {
                tracing::error!("Server error: {why:?}");
            } else {
                tracing::warn!("Server exited");
            }
        }
        res = &mut task_handle => {
            server.abort();
            ai_responder_handle.abort();
            if let Err(why) = res {
                tracing::error!("Task error: {why:?}");
            } else {
                tracing::warn!("Task exited");
            }
        }
        res = &mut ai_responder_handle => {
            server.abort();
            task_handle.abort();
            if let Err(why) = res {
                tracing::error!("AI responder error: {why:?}");
            } else {
                tracing::warn!("AI responder exited");
            }
        }
        _ = tokio::signal::ctrl_c() => {
            tracing::warn!("Received SIGINT, shutting down");
            server.abort();
            task_handle.abort();
            ai_responder_handle.abort();
        }
    }
}
