use tokio::sync::mpsc;
use tracing::{error, info};

use crate::{
    db::Database,
    events::{
        ConsoleEventBus, TOPIC_API_KEYS, TOPIC_CHANNELS, TOPIC_DASHBOARD, TOPIC_LEADERBOARDS,
        TOPIC_LEDGER, TOPIC_ME,
    },
    models::LedgerEvent,
    state::MetricsState,
};

pub type LedgerSender = mpsc::Sender<LedgerEvent>;

pub fn spawn_ledger_worker(
    db: Database,
    metrics: MetricsState,
    events: ConsoleEventBus,
    queue_capacity: usize,
) -> LedgerSender {
    let (tx, mut rx) = mpsc::channel::<LedgerEvent>(queue_capacity);
    tokio::spawn(async move {
        info!("ledger worker started");
        while let Some(event) = rx.recv().await {
            metrics.add_points(event.total_points);
            match db.apply_ledger_event(&event).await {
                Ok(true) => {
                    let consumer_topics = [
                        TOPIC_ME,
                        TOPIC_DASHBOARD,
                        TOPIC_LEDGER,
                        TOPIC_CHANNELS,
                        TOPIC_LEADERBOARDS,
                        TOPIC_API_KEYS,
                    ];
                    events.publish(
                        crate::events::EventVisibility::User {
                            user_id: event.user_id,
                        },
                        consumer_topics,
                    );
                    if event.provider_user_id != event.user_id {
                        let provider_topics = [
                            TOPIC_ME,
                            TOPIC_DASHBOARD,
                            TOPIC_CHANNELS,
                            TOPIC_LEADERBOARDS,
                        ];
                        events.publish(
                            crate::events::EventVisibility::User {
                                user_id: event.provider_user_id,
                            },
                            provider_topics,
                        );
                    }
                }
                Ok(false) => {}
                Err(err) => {
                    error!(?err, request_id = %event.request_id, "failed to apply ledger event");
                }
            }
        }
    });
    tx
}
