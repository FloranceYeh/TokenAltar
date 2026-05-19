use std::{
    collections::BTreeSet,
    convert::Infallible,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use axum::{
    extract::State,
    response::sse::{Event, KeepAlive, Sse},
};
use futures_util::{Stream, StreamExt};
use serde::Serialize;
use tokio::sync::broadcast;
use tokio_stream::wrappers::{BroadcastStream, errors::BroadcastStreamRecvError};
use tracing::warn;

use crate::{
    auth::ConsoleAuth,
    error::{AppError, AppResult},
    models::User,
};

const EVENT_QUEUE_CAPACITY: usize = 1024;

pub const TOPIC_API_KEYS: &str = "apiKeys";
pub const TOPIC_AFFINITY_RULES: &str = "affinityRules";
pub const TOPIC_CHANNELS: &str = "channels";
pub const TOPIC_DASHBOARD: &str = "dashboard";
pub const TOPIC_LEDGER: &str = "ledger";
pub const TOPIC_LEADERBOARDS: &str = "leaderboards";
pub const TOPIC_ME: &str = "me";
pub const TOPIC_PRICES: &str = "prices";
pub const TOPIC_REDPACKETS: &str = "redPackets";
pub const TOPIC_RUNTIME_SETTINGS: &str = "runtimeSettings";
pub const TOPIC_SETTINGS: &str = "settings";
pub const TOPIC_TRANSFERS: &str = "transfers";
pub const TOPIC_USERS: &str = "users";

#[derive(Clone)]
pub struct ConsoleEventBus {
    tx: broadcast::Sender<ConsoleEvent>,
}

#[derive(Clone, Debug, Serialize)]
pub struct ConsoleEvent {
    pub id: u64,
    pub visibility: EventVisibility,
    pub topics: Vec<&'static str>,
    pub created_at_ms: u128,
}

#[derive(Clone, Copy, Debug, Serialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum EventVisibility {
    Global,
    AdminOnly,
    User { user_id: i64 },
}

impl Default for ConsoleEventBus {
    fn default() -> Self {
        Self::new(EVENT_QUEUE_CAPACITY)
    }
}

impl ConsoleEventBus {
    pub fn new(queue_capacity: usize) -> Self {
        let (tx, _) = broadcast::channel(queue_capacity);
        Self { tx }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<ConsoleEvent> {
        self.tx.subscribe()
    }

    pub fn publish(&self, visibility: EventVisibility, topics: impl IntoTopics) {
        let topics = topics.into_topics();
        if topics.is_empty() {
            return;
        }
        let event = ConsoleEvent {
            id: next_event_id(),
            visibility,
            topics,
            created_at_ms: current_epoch_ms(),
        };
        let _ = self.tx.send(event);
    }
}

pub trait IntoTopics {
    fn into_topics(self) -> Vec<&'static str>;
}

impl IntoTopics for &'static str {
    fn into_topics(self) -> Vec<&'static str> {
        vec![self]
    }
}

impl<const N: usize> IntoTopics for [&'static str; N] {
    fn into_topics(self) -> Vec<&'static str> {
        unique_topics(self)
    }
}

impl IntoTopics for Vec<&'static str> {
    fn into_topics(self) -> Vec<&'static str> {
        unique_topics(self)
    }
}

pub async fn console_events(
    State(state): State<crate::app::AppState>,
    ConsoleAuth(auth): ConsoleAuth,
) -> AppResult<Sse<impl Stream<Item = Result<Event, Infallible>>>> {
    let connected = ConsoleEvent {
        id: next_event_id(),
        visibility: EventVisibility::Global,
        topics: vec!["connected"],
        created_at_ms: current_epoch_ms(),
    };
    let initial_event = Event::default()
        .event("console-update")
        .json_data(connected)
        .map_err(|err| AppError::Anyhow(anyhow::anyhow!(err)))?;
    let stream = futures_util::stream::once(async move { Ok(initial_event) }).chain(
        BroadcastStream::new(state.events.subscribe()).filter_map(move |item| {
            let user = auth.user.clone();
            async move { event_for_user(item, &user) }
        }),
    );
    Ok(Sse::new(stream).keep_alive(
        KeepAlive::new()
            .interval(Duration::from_secs(15))
            .text("keep-alive"),
    ))
}

pub fn publish_user_event(state: &crate::app::AppState, user_id: i64, topics: impl IntoTopics) {
    state
        .events
        .publish(EventVisibility::User { user_id }, topics);
}

pub fn publish_admin_event(state: &crate::app::AppState, topics: impl IntoTopics) {
    state.events.publish(EventVisibility::AdminOnly, topics);
}

pub fn publish_global_event(state: &crate::app::AppState, topics: impl IntoTopics) {
    state.events.publish(EventVisibility::Global, topics);
}

pub fn publish_channel_owner_event(
    state: &crate::app::AppState,
    owner_user_id: i64,
    topics: impl IntoTopics,
) {
    state.events.publish(
        EventVisibility::User {
            user_id: owner_user_id,
        },
        topics,
    );
}

fn event_for_user(
    item: Result<ConsoleEvent, BroadcastStreamRecvError>,
    user: &User,
) -> Option<Result<Event, Infallible>> {
    let event = match item {
        Ok(event) => event,
        Err(BroadcastStreamRecvError::Lagged(skipped)) => {
            warn!(skipped, "console event stream lagged");
            ConsoleEvent {
                id: next_event_id(),
                visibility: EventVisibility::Global,
                topics: vec!["sync"],
                created_at_ms: current_epoch_ms(),
            }
        }
    };
    if !can_see_event(user, &event) {
        return None;
    }
    let sse = Event::default()
        .event("console-update")
        .id(event.id.to_string())
        .json_data(event)
        .unwrap_or_else(|err| {
            warn!(?err, "failed to serialize console event");
            Event::default()
                .event("console-update")
                .data(r#"{"topics":["sync"]}"#)
        });
    Some(Ok(sse))
}

fn can_see_event(user: &User, event: &ConsoleEvent) -> bool {
    match event.visibility {
        EventVisibility::Global => true,
        EventVisibility::AdminOnly => user.role == "admin",
        EventVisibility::User { user_id } => user.id == user_id || user.role == "admin",
    }
}

fn unique_topics(topics: impl IntoIterator<Item = &'static str>) -> Vec<&'static str> {
    let mut seen = BTreeSet::new();
    topics
        .into_iter()
        .filter(|topic| seen.insert(*topic))
        .collect()
}

fn next_event_id() -> u64 {
    static NEXT_EVENT_ID: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
    NEXT_EVENT_ID.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
}

fn current_epoch_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}
