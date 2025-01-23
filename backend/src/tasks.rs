use std::time::Duration;

use tokio::task::JoinHandle;

use crate::AppContext;

pub async fn start_tasks(app_context: AppContext) -> Result<JoinHandle<()>, Box<anyhow::Error>> {
    let task_handle = tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(60 * 5));
        loop {
            interval.tick().await;

            tracing::info!("Checking apple alerts to send");
            if let Err(err) = app_context.send_pushes().await {
                tracing::error!("Error sending apple alerts: {:?}", err);
            } else {
                tracing::info!("Apple alerts sent");
            }
        }
    });

    Ok(task_handle)
}
