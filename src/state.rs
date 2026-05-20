use std::{
    collections::VecDeque,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

const SURGE_WINDOW: Duration = Duration::from_secs(60 * 60);
const SURGE_BUCKET: Duration = Duration::from_secs(60);

#[derive(Clone)]
pub struct MetricsState {
    rolling_hour_points: Arc<Mutex<RollingPointWindow>>,
}

impl Default for MetricsState {
    fn default() -> Self {
        Self {
            rolling_hour_points: Arc::new(Mutex::new(RollingPointWindow::default())),
        }
    }
}

impl MetricsState {
    pub fn add_points(&self, points: f64) {
        self.add_points_at(points, Instant::now());
    }

    pub fn points_last_hour(&self) -> f64 {
        self.points_last_hour_at(Instant::now())
    }

    fn add_points_at(&self, points: f64, now: Instant) {
        self.rolling_hour_points
            .lock()
            .expect("metrics window mutex poisoned")
            .add(points, now);
    }

    fn points_last_hour_at(&self, now: Instant) -> f64 {
        self.rolling_hour_points
            .lock()
            .expect("metrics window mutex poisoned")
            .total(now)
    }
}

#[derive(Default)]
struct RollingPointWindow {
    buckets: VecDeque<PointBucket>,
}

struct PointBucket {
    started_at: Instant,
    points: f64,
}

impl RollingPointWindow {
    fn add(&mut self, points: f64, now: Instant) {
        self.prune(now);
        if let Some(last) = self.buckets.back_mut()
            && now
                .checked_duration_since(last.started_at)
                .is_some_and(|age| age < SURGE_BUCKET)
        {
            last.points += points;
            return;
        }
        self.buckets.push_back(PointBucket {
            started_at: now,
            points,
        });
    }

    fn total(&mut self, now: Instant) -> f64 {
        self.prune(now);
        self.buckets.iter().map(|bucket| bucket.points).sum()
    }

    fn prune(&mut self, now: Instant) {
        while self
            .buckets
            .front()
            .and_then(|bucket| now.checked_duration_since(bucket.started_at))
            .is_some_and(|age| age >= SURGE_WINDOW)
        {
            self.buckets.pop_front();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rolling_window_drops_points_outside_last_hour() {
        let metrics = MetricsState::default();
        let now = Instant::now();

        metrics.add_points_at(100.0, now - Duration::from_secs(61 * 60));
        metrics.add_points_at(40.0, now - Duration::from_secs(30 * 60));
        metrics.add_points_at(2.5, now);

        assert_eq!(metrics.points_last_hour_at(now), 42.5);
    }

    #[test]
    fn rolling_window_groups_minute_bucket() {
        let metrics = MetricsState::default();
        let now = Instant::now();

        metrics.add_points_at(10.0, now);
        metrics.add_points_at(15.25, now + Duration::from_secs(30));

        assert_eq!(
            metrics.points_last_hour_at(now + Duration::from_secs(30)),
            25.25
        );
    }
}
