use std::time::Duration;

use tokio::task::JoinHandle;

use crate::{ai_responder, AppContext};

pub async fn start_tasks(app_context: AppContext) -> Result<JoinHandle<()>, Box<anyhow::Error>> {
    let task_handle = tokio::spawn(async move {
        let mut push_interval = tokio::time::interval(Duration::from_secs(60 * 5));
        let mut rename_interval = tokio::time::interval(Duration::from_secs(60 * 30));
        loop {
            tokio::select! {
                _ = push_interval.tick() => {
                    tracing::info!("Checking apple alerts to send");
                    if let Err(err) = app_context.send_pushes().await {
                        tracing::error!("Error sending apple alerts: {:?}", err);
                    } else {
                        tracing::info!("Apple alerts sent");
                    }
                }
                _ = rename_interval.tick() => {
                    tracing::info!("Checking old support threads for AI responder follow-up");
                    if let Err(err) = ai_responder::respond_to_old_messages(app_context.clone()).await {
                        tracing::error!("Error responding to old support threads: {:?}", err);
                    } else {
                        tracing::info!("Old support thread AI responder check finished");
                    }

                    tracing::info!("Checking recent support threads to rename");
                    if let Err(err) = ai_responder::rename_recent_threads(app_context.clone()).await {
                        tracing::error!("Error renaming recent support threads: {:?}", err);
                    } else {
                        tracing::info!("Recent support thread rename check finished");
                    }
                }
            }
        }
    });

    Ok(task_handle)
}
