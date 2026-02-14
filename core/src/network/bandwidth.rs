//! # Bandwidth Control Module
//!
//! Implements bandwidth throttling and Quality of Service (QoS) using
//! the token bucket algorithm for precise rate limiting.
//!
//! ## Features
//! - Token bucket with configurable rate and burst capacity
//! - Priority-based QoS (Critical, High, Medium, Low)
//! - Timeout support to prevent indefinite blocking
//! - Precise token tracking with nanosecond resolution
//! - Thread-safe async implementation

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::Duration;
use std::collections::VecDeque;

// Use tokio::time::Instant in tests for deterministic time control
#[cfg(test)]
use tokio::time::Instant;

// Use std::time::Instant in production for better performance
#[cfg(not(test))]
use std::time::Instant;

use tokio::sync::{Mutex, Notify};
use tokio::time::{sleep, timeout};
use thiserror::Error;

/// Errors that can occur during bandwidth acquisition
#[derive(Error, Debug, Clone)]
pub enum AcquireError {
    #[error("Requested {requested} bytes exceeds capacity {capacity} bytes")]
    TooLarge { requested: u64, capacity: u64 },
    
    #[error("Acquisition timed out after {0:?}")]
    Timeout(Duration),
    
    #[error("Bandwidth limiter is closed")]
    Closed,
    
    #[error("Insufficient tokens available right now")]
    Insufficient,
}

/// Configuration (atomic, can be changed at runtime)
struct LimiterConfig {
    /// Rate in bytes per second
    rate: AtomicU64,
    /// Maximum burst capacity (bucket size)
    capacity: AtomicU64,
    /// Burst multiplier (scaled by 1000 for precision)
    burst_multiplier_scaled: AtomicU64,
}

/// Newtype wrapper for scaled byte values (bytes * 1e9)
/// Prevents unit confusion between raw bytes and scaled tokens
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct ScaledBytes(u128);

impl ScaledBytes {
    /// Scaling factor (1 billion) to allow nanosecond precision
    const SCALE: u128 = 1_000_000_000;

    /// Create from raw bytes
    fn from_bytes(bytes: u64) -> Self {
        Self((bytes as u128) * Self::SCALE)
    }

    /// Convert back to raw bytes (truncating remainder)
    fn to_bytes(self) -> u64 {
        (self.0 / Self::SCALE) as u64
    }

    /// Create from raw scaled value (internal use)
    fn from_raw(raw: u128) -> Self {
        Self(raw)
    }

    /// Get raw scaled value (internal use)
    fn as_raw(self) -> u128 {
        self.0
    }

    /// Add another ScaledBytes
    fn add(self, other: Self) -> Self {
        Self(self.0 + other.0)
    }

    /// Subtract another ScaledBytes
    fn sub(self, other: Self) -> Self {
        Self(self.0 - other.0)
    }

    /// Saturating subtraction
    fn saturating_sub(self, other: Self) -> Self {
        Self(self.0.saturating_sub(other.0))
    }

    /// Minimum of two values
    fn min(self, other: Self) -> Self {
        Self(self.0.min(other.0))
    }
}

/// Bucket state (protected by mutex)
struct BucketState {
    /// Current token count (type-safe wrapper)
    tokens: ScaledBytes,
    /// Last refill timestamp
    last_refill: Instant,
    /// Remainder from last refill (in nanoseconds, always < 1e9)
    remainder_nanos: u128,
    /// Whether the limiter is closed
    closed: bool,
}

/// Metrics (can be read independently)
struct LimiterMetrics {
    /// Total bytes sent
    bytes_sent_total: AtomicU64,
    /// Timestamp when tracking started
    tracking_start: Mutex<Instant>,
    /// Recent usage samples for sliding window (timestamp, bytes)
    usage_samples: Mutex<VecDeque<(Instant, u64)>>,
}

/// Bandwidth limiter using token bucket algorithm
#[derive(Clone)]
pub struct BandwidthLimiter {
    config: Arc<LimiterConfig>,
    state: Arc<Mutex<BucketState>>,
    metrics: Arc<LimiterMetrics>,
    /// Notifies waiters when tokens are available or rate changes
    notify: Arc<Notify>,
}

/// Maximum number of usage samples to keep in memory
const MAX_SAMPLES: usize = 10_000;

/// Maximum elapsed time to process in one refill (prevents overflow)
const MAX_ELAPSED_SECS: u64 = 10;

/// Maximum refill rounds per call (prevents CPU spikes after long pauses)
const MAX_REFILL_ROUNDS: usize = 5;

impl BandwidthLimiter {
    /// Create a new bandwidth limiter
    pub fn new(rate: u64) -> Self {
        Self::with_capacity(rate, rate * 2)
    }

    /// Create a bandwidth limiter with custom capacity
    pub fn with_capacity(rate: u64, capacity: u64) -> Self {
        let now = Instant::now();
        let burst_multiplier = if rate > 0 {
            ((capacity as u128 * 1000) / rate as u128) as u64
        } else {
            2000 // 2.0x default
        };
        
        Self {
            config: Arc::new(LimiterConfig {
                rate: AtomicU64::new(rate),
                capacity: AtomicU64::new(capacity),
                burst_multiplier_scaled: AtomicU64::new(burst_multiplier),
            }),
            state: Arc::new(Mutex::new(BucketState {
                tokens: ScaledBytes::from_bytes(capacity),
                last_refill: now,
                remainder_nanos: 0,
                closed: false,
            })),
            metrics: Arc::new(LimiterMetrics {
                bytes_sent_total: AtomicU64::new(0),
                tracking_start: Mutex::new(now),
                usage_samples: Mutex::new(VecDeque::new()),
            }),
            notify: Arc::new(Notify::new()),
        }
    }

    /// Set the bandwidth limit and capacity
    pub async fn set_limit(&self, rate: u64, capacity: u64) {
        self.config.rate.store(rate, Ordering::Relaxed);
        self.config.capacity.store(capacity, Ordering::Relaxed);
        
        let burst_multiplier = if rate > 0 {
            ((capacity as u128 * 1000) / rate as u128) as u64
        } else {
            2000
        };
        self.config.burst_multiplier_scaled.store(burst_multiplier, Ordering::Relaxed);
        
        let mut state = self.state.lock().await;
        // Clamp tokens to new capacity (type-safe)
        let max_tokens = ScaledBytes::from_bytes(capacity);
        if state.tokens > max_tokens {
            state.tokens = max_tokens;
        }
        
        // precise: Do NOT reset last_refill or remainder here.
        // This preserves the time base so pending elapsed time is credited correctly
        // (albeit at the new rate effective from the next refill check)
        
        drop(state);
        // Notify all waiters that rate/capacity changed
        self.notify.notify_waiters();
    }

    /// Set only the rate
    pub async fn set_rate(&self, rate: u64) {
        let burst_multiplier = self.config.burst_multiplier_scaled.load(Ordering::Relaxed);
        let capacity = (rate as u128 * burst_multiplier as u128 / 1000) as u64;
        self.set_limit(rate, capacity).await;
    }

    /// Get current rate limit
    pub fn get_rate(&self) -> u64 {
        self.config.rate.load(Ordering::Relaxed)
    }

    /// Get current capacity
    pub fn get_capacity(&self) -> u64 {
        self.config.capacity.load(Ordering::Relaxed)
    }

    /// Acquire tokens for sending data
    pub async fn acquire(&self, bytes: usize) -> Result<(), AcquireError> {
        self.acquire_with_timeout(bytes, Duration::from_secs(30)).await
    }

    /// Acquire tokens with timeout
    pub async fn acquire_with_timeout(
        &self,
        bytes: usize,
        timeout_duration: Duration,
    ) -> Result<(), AcquireError> {
        let bytes_u64 = bytes as u64;
        let capacity = self.config.capacity.load(Ordering::Relaxed);

        if bytes_u64 > capacity {
            return Err(AcquireError::TooLarge {
                requested: bytes_u64,
                capacity,
            });
        }

        match timeout(timeout_duration, self.acquire_internal(bytes)).await {
            Ok(result) => result,
            Err(_) => Err(AcquireError::Timeout(timeout_duration)),
        }
    }

    /// Internal acquisition logic with event-driven waiting
    async fn acquire_internal(&self, bytes: usize) -> Result<(), AcquireError> {
        let bytes_scaled = ScaledBytes::from_bytes(bytes as u64);

        loop {
            // Need to check condition
            let wait_time = {
                let mut state = self.state.lock().await;

                if state.closed {
                    return Err(AcquireError::Closed);
                }

                self.refill_tokens(&mut state);

                if state.tokens >= bytes_scaled {
                    state.tokens = state.tokens.sub(bytes_scaled);
                    
                    self.metrics.bytes_sent_total.fetch_add(bytes as u64, Ordering::Relaxed);
                    
                    drop(state);
                    
                    let mut samples = self.metrics.usage_samples.lock().await;
                    samples.push_back((Instant::now(), bytes as u64));
                    
                    while samples.len() > MAX_SAMPLES {
                        samples.pop_front();
                    }
                    
                    return Ok(());
                }

                self.calculate_wait_time(bytes_scaled, state.tokens)
            };
            
            // Wait for either:
            // 1. Notification (rate changed, tokens added manually, etc.)
            // 2. Timeout (refill time reached)
            if wait_time > Duration::from_nanos(0) {
                tokio::select! {
                    _ = self.notify.notified() => {
                        // State changed, retry immediately
                        continue; 
                    }
                    _ = sleep(wait_time) => {
                        // Refill time reached, retry
                        continue;
                    }
                }
            } else {
                tokio::task::yield_now().await;
            }
        }
    }

    /// Refill tokens based on elapsed time (type-safe)
    fn refill_tokens(&self, state: &mut BucketState) {
        let now = Instant::now();
        let mut remaining_elapsed = now.duration_since(state.last_refill);

        if remaining_elapsed.as_nanos() == 0 {
            return;
        }

        let rate = self.config.rate.load(Ordering::Relaxed) as u128;
        
        if rate == 0 {
            state.last_refill = now;
            return;
        }
        
        let capacity = self.config.capacity.load(Ordering::Relaxed) as u128;
        let max_tokens = ScaledBytes::from_bytes(capacity as u64);
        let max_elapsed_nanos = (MAX_ELAPSED_SECS as u128) * 1_000_000_000;
        
        for _ in 0..MAX_REFILL_ROUNDS {
            let elapsed_nanos = remaining_elapsed.as_nanos();
            
            if elapsed_nanos == 0 {
                break;
            }
            
            let elapsed_nanos_used = elapsed_nanos.min(max_elapsed_nanos);
            
            let total_nanos = elapsed_nanos_used + state.remainder_nanos;
            
            let add_raw = (rate * total_nanos * ScaledBytes::SCALE) / 1_000_000_000;
            let add_scaled = ScaledBytes::from_raw(add_raw);
            
            state.remainder_nanos = total_nanos % 1_000_000_000;

            if add_raw > 0 {
                state.tokens = state.tokens.add(add_scaled).min(max_tokens);
            }
            
            let used_nanos = elapsed_nanos_used.min(u64::MAX as u128) as u64;
            state.last_refill = state.last_refill + Duration::from_nanos(used_nanos);
            
            if state.tokens >= max_tokens {
                break;
            }
            
            remaining_elapsed = now.duration_since(state.last_refill);
        }
    }

    /// Calculate wait time (type-safe)
    fn calculate_wait_time(&self, needed: ScaledBytes, available: ScaledBytes) -> Duration {
        let deficit = needed.saturating_sub(available);
        let rate = self.config.rate.load(Ordering::Relaxed) as u128;

        if rate == 0 {
            return Duration::from_millis(100);
        }

        // wait_nanos = deficit_raw / rate (scaled bytes / bytes per second = seconds * 1e9 = nanos)
        let wait_nanos = (deficit.as_raw() * 1_000_000_000) / (rate * ScaledBytes::SCALE);
        
        let buffer_nanos = (wait_nanos / 10).clamp(100_000, 1_000_000);
        let wait_nanos = wait_nanos + buffer_nanos;
        
        Duration::from_nanos(wait_nanos.min(u64::MAX as u128) as u64)
    }

    /// Get current available tokens
    pub async fn available_tokens(&self) -> u64 {
        let state = self.state.lock().await;
        state.tokens.to_bytes()
    }

    /// Get current bandwidth usage (bytes per second)
    pub async fn get_usage(&self) -> f64 {
        let tracking_start = self.metrics.tracking_start.lock().await;
        let elapsed = Instant::now().duration_since(*tracking_start);
        
        if elapsed.as_secs_f64() < 0.001 {
            return 0.0;
        }

        let total_bytes = self.metrics.bytes_sent_total.load(Ordering::Relaxed);
        total_bytes as f64 / elapsed.as_secs_f64()
    }

    /// Get bandwidth usage over a sliding window
    pub async fn get_usage_window(&self, window: Duration) -> f64 {
        let mut samples = self.metrics.usage_samples.lock().await;
        let now = Instant::now();
        let cutoff = now - window;
        
        while let Some((timestamp, _)) = samples.front() {
            if *timestamp <= cutoff {
                samples.pop_front();
            } else {
                break;
            }
        }
        
        if samples.is_empty() {
            return 0.0;
        }
        
        let total_bytes: u64 = samples.iter().map(|(_, bytes)| bytes).sum();
        let elapsed = now.duration_since(samples[0].0).as_secs_f64().max(0.05);
        
        if elapsed < 0.001 {
            return 0.0;
        }
        
        total_bytes as f64 / elapsed
    }

    /// Reset usage statistics
    pub async fn reset_stats(&self) {
        self.metrics.bytes_sent_total.store(0, Ordering::Relaxed);
        *self.metrics.tracking_start.lock().await = Instant::now();
    }

    /// Close the limiter
    pub async fn close(&self) {
        let mut state = self.state.lock().await;
        state.closed = true;
        drop(state);
        self.notify.notify_waiters();
    }

    /// Check if the limiter is closed
    pub async fn is_closed(&self) -> bool {
        let state = self.state.lock().await;
        state.closed
    }

    /// Try to acquire tokens without waiting
    pub async fn try_acquire(&self, bytes: usize) -> Result<(), AcquireError> {
        let bytes_scaled = ScaledBytes::from_bytes(bytes as u64);
        let bytes_u64 = bytes as u64;
        let capacity = self.config.capacity.load(Ordering::Relaxed);

        if bytes_u64 > capacity {
            return Err(AcquireError::TooLarge {
                requested: bytes_u64,
                capacity,
            });
        }

        let mut state = self.state.lock().await;

        if state.closed {
            return Err(AcquireError::Closed);
        }

        self.refill_tokens(&mut state);

        if state.tokens >= bytes_scaled {
            state.tokens = state.tokens.sub(bytes_scaled);
            self.metrics.bytes_sent_total.fetch_add(bytes_u64, Ordering::Relaxed);
            
            drop(state);
            
            let mut samples = self.metrics.usage_samples.lock().await;
            samples.push_back((Instant::now(), bytes_u64));
            
            while samples.len() > MAX_SAMPLES {
                samples.pop_front();
            }
            
            Ok(())
        } else {
            Err(AcquireError::Insufficient)
        }
    }

    /// Acquire tokens for multiple chunks
    pub async fn acquire_many(&self, chunks: &[usize]) -> Result<(), AcquireError> {
        let total_bytes: usize = chunks.iter().sum();
        self.acquire(total_bytes).await
    }

    /// Calculate time to wait for specified bytes to be available
    pub async fn wait_time_for(&self, bytes: usize) -> Duration {
        let mut state = self.state.lock().await;
        self.refill_tokens(&mut state);
        let needed = ScaledBytes::from_bytes(bytes as u64);
        if state.tokens >= needed {
            return Duration::ZERO;
        }
        self.calculate_wait_time(needed, state.tokens)
    }

    /// Get the notification object
    pub fn get_notify(&self) -> Arc<Notify> {
        self.notify.clone()
    }
}


/// Priority levels for QoS
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Priority {
    Low = 0,
    Medium = 1,
    High = 2,
    Critical = 3,
}

/// Packet with priority for QoS
pub struct PrioritizedPacket {
    pub data: bytes::Bytes,
    pub priority: Priority,
    pub timestamp: Instant,
}

use tokio::sync::oneshot;

/// Request for bandwidth in the QoS queue
struct QosRequest {
    bytes: usize,
    result_tx: oneshot::Sender<Result<(), AcquireError>>,
}

/// QoS-aware bandwidth limiter with priority queues and shared token bucket
#[derive(Clone)]
pub struct SharedQosBandwidthLimiter {
    /// Underlying token bucket (shared across all priorities)
    limiter: Arc<BandwidthLimiter>,
    /// Queues for each priority level
    queues: [Arc<Mutex<VecDeque<QosRequest>>>; 4],
    /// Notify scheduler when a new request arrives
    scheduler_notify: Arc<Notify>,
}

impl SharedQosBandwidthLimiter {
    /// Create a new QoS bandwidth limiter
    pub fn new(rate: u64) -> Self {
        let limiter = Arc::new(BandwidthLimiter::new(rate));
        let queues = [
            Arc::new(Mutex::new(VecDeque::new())),
            Arc::new(Mutex::new(VecDeque::new())),
            Arc::new(Mutex::new(VecDeque::new())),
            Arc::new(Mutex::new(VecDeque::new())),
        ];
        let scheduler_notify = Arc::new(Notify::new());

        let qos_limiter = Self {
            limiter: limiter.clone(),
            queues: queues.clone(),
            scheduler_notify: scheduler_notify.clone(),
        };

        // Spawn background scheduler
        tokio::spawn(async move {
            qos_limiter.run_scheduler().await;
        });

        Self {
            limiter,
            queues,
            scheduler_notify,
        }
    }

    /// Acquire tokens with priority
    pub async fn acquire(&self, bytes: usize, priority: Priority) -> Result<(), AcquireError> {
        let (tx, rx) = oneshot::channel();
        let request = QosRequest {
            bytes,
            result_tx: tx,
        };

        // Push to appropriate queue
        {
            let mut queue = self.queues[priority as usize].lock().await;
            queue.push_back(request);
        }

        // Wake up scheduler
        self.scheduler_notify.notify_one();

        // Wait for result
        rx.await.unwrap_or(Err(AcquireError::Closed))
    }

    /// Set total bandwidth rate
    pub async fn set_total_rate(&self, rate: u64) {
        self.limiter.set_rate(rate).await;
    }

    /// Scheduler loop to process requests using Deficit Round Robin (DRR)
    pub async fn run_scheduler(&self) {
        // Weights (Quantum in bytes per round)
        const QUANTUM: [usize; 4] = [1000, 3000, 6000, 10000]; // Low, Med, High, Crit
        
        let mut deficits = [0isize; 4];
        
        // DRR Order: Crit, High, Med, Low
        let priorities: [usize; 4] = [3, 2, 1, 0]; 
        let mut start_index = 0; // Rotate starting point for fairness

        loop {
            let mut queues_with_work = false;
            let mut work_done = false;
            let mut all_blocked_on_tokens = true;

            // Iterate through priorities starting from start_index
            for i in 0..4 {
                let p_idx = (start_index + i) % 4;
                let p = priorities[p_idx];

                let queue = self.queues[p].lock().await;
                if queue.is_empty() {
                    deficits[p] = 0; 
                    continue;
                }
                drop(queue); 

                queues_with_work = true;
                deficits[p] += QUANTUM[p] as isize;
                
                // Cap deficit to prevent infinite accumulation? 
                // e.g. max 2x Quantum to prevent huge bursts after idle.
                // Keeping it simple for now.

                loop {
                    let queue = self.queues[p].lock().await;
                    if let Some(req) = queue.front() {
                        let size = req.bytes;
                        if (size as isize) <= deficits[p] {
                            drop(queue);
                            
                            match self.limiter.try_acquire(size).await {
                                Ok(_) => {
                                    let mut queue = self.queues[p].lock().await;
                                    if let Some(popped) = queue.pop_front() {
                                        let _ = popped.result_tx.send(Ok(()));
                                        deficits[p] -= size as isize;
                                        work_done = true;
                                        all_blocked_on_tokens = false;
                                        
                                        // If we successfully processed a packet, do we continue ONLY this queue?
                                        // Standard DRR continues until deficit empty.
                                        // But to prevent "Token Hogging" on slow links, we could yield?
                                        // Let's stick to DRR: continue.
                                    }
                                },
                                Err(AcquireError::Insufficient) => {
                                    // Blocked on tokens. 
                                    // Stop processing this queue for now.
                                    // But keep deficit.
                                    break; 
                                },
                                Err(e) => {
                                    let mut queue = self.queues[p].lock().await;
                                    if let Some(popped) = queue.pop_front() {
                                        let _ = popped.result_tx.send(Err(e));
                                    }
                                    break;
                                }
                            }
                        } else {
                            all_blocked_on_tokens = false; // Blocked on deficit
                            break;
                        }
                    } else {
                         deficits[p] = 0;
                         break;
                    }
                }
            }

            // Rotate start index if we did a round of checks
            // This ensures next time we wake up (after sleep), we give chance to next queue
            // provided the previous ones exhausted deficit OR were blocked.
            // Actually, simply rotating every loop ensures check fairness.
            start_index = (start_index + 1) % 4;

            // 2. Wait Logic
            if !queues_with_work {
                self.scheduler_notify.notified().await;
            } else if all_blocked_on_tokens && !work_done {
                // Find min needed
                let mut min_needed = usize::MAX;
                for &p in &priorities {
                    let queue = self.queues[p].lock().await;
                    if let Some(req) = queue.front() {
                        if (req.bytes as isize) <= deficits[p] {
                             min_needed = min_needed.min(req.bytes);
                        }
                    }
                }
                
                if min_needed == usize::MAX { min_needed = 1; }

                let wait_duration = self.limiter.wait_time_for(min_needed).await;
                
                tokio::select! {
                     _ = sleep(wait_duration) => {},
                     _ = self.scheduler_notify.notified() => {},
                }
            } else {
                if !work_done {
                     tokio::task::yield_now().await;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_rate_limit_not_faster_than_expected() {
        let limiter = BandwidthLimiter::with_capacity(1000, 1000); // 1KB/s, burst 1KB

        // Drain burst capacity
        limiter.acquire(1000).await.unwrap();

        // Need 500 more bytes => theoretical min wait = 0.5s
        let start = Instant::now();
        limiter.acquire(500).await.unwrap();
        let elapsed = start.elapsed();

        // Allow 100ms jitter margin
        assert!(elapsed >= Duration::from_millis(400), 
            "Acquired tokens too fast: {:?} < 400ms (violates rate limit)", elapsed);
    }

    #[tokio::test]
    async fn test_never_exceeds_capacity() {
        let limiter = BandwidthLimiter::with_capacity(1000, 1000);

        tokio::time::sleep(Duration::from_secs(2)).await;

        let tokens = limiter.available_tokens().await;
        assert!(tokens <= 1000, 
            "Tokens {} exceed capacity 1000", tokens);
    }

    #[tokio::test]
    async fn test_deterministic_refill() {
        tokio::time::pause();

        let limiter = BandwidthLimiter::with_capacity(1000, 1000);
        limiter.acquire(1000).await.unwrap(); // drain

        let limiter_clone = limiter.clone();
        let task = tokio::spawn(async move { 
            limiter_clone.acquire(500).await.unwrap();
        });

        tokio::time::advance(Duration::from_millis(499)).await;
        tokio::task::yield_now().await;
        assert!(!task.is_finished(), "Task finished too early");

        tokio::time::advance(Duration::from_millis(2)).await;
        tokio::time::sleep(Duration::from_millis(1)).await; // Allow task to run
        assert!(task.await.is_ok(), "Task should complete after sufficient time");
    }

    #[tokio::test]
    async fn test_too_large_request() {
        let limiter = BandwidthLimiter::with_capacity(1000, 500);
        
        let result = limiter.acquire(1000).await;
        assert!(matches!(result, Err(AcquireError::TooLarge { .. })));
    }

    #[tokio::test]
    async fn test_timeout() {
        tokio::time::pause();
        
        // Use very slow rate with no burst: 10 bytes/s, capacity = 10 bytes
        // This means need exactly 1000ms to refill 10 bytes
        let limiter = BandwidthLimiter::with_capacity(10, 10);
        
        // Drain all tokens
        limiter.acquire(10).await.unwrap();
        
        // Spawn task that will try to acquire with 50ms timeout
        let limiter_clone = limiter.clone();
        let handle = tokio::spawn(async move {
            limiter_clone.acquire_with_timeout(10, Duration::from_millis(50)).await
        });
        
        // Advance time past timeout (51ms)
        tokio::time::advance(Duration::from_millis(51)).await;
        
        // Task should have timed out
        let result = handle.await.unwrap();
        assert!(matches!(result, Err(AcquireError::Timeout(_))),
            "Expected Timeout error, got: {:?}", result);
    }

    #[tokio::test]
    async fn test_set_limit() {
        let limiter = BandwidthLimiter::new(1000);
        assert_eq!(limiter.get_rate(), 1000);

        limiter.set_rate(2000).await;
        assert_eq!(limiter.get_rate(), 2000);
    }

    #[tokio::test]
    async fn test_close() {
        let limiter = BandwidthLimiter::new(1000);
        limiter.close().await;
        
        let result = limiter.acquire(100).await;
        assert!(matches!(result, Err(AcquireError::Closed)));
    }

    #[tokio::test]
    async fn test_usage_tracking() {
        let limiter = BandwidthLimiter::new(10000); // 10KB/s
        
        limiter.reset_stats().await;
        let _ = limiter.acquire(1000).await;
        
        tokio::time::sleep(Duration::from_millis(100)).await;
        
        let usage = limiter.get_usage().await;
        assert!(usage > 0.0);
    }

    #[tokio::test]
    async fn test_qos_limiter() {
        let qos = SharedQosBandwidthLimiter::new(1000);
        
        // Critical should get access. 
        // Note: With shared limiter, priority is about ordering, not just partition.
        // But since we use a single bucket, both should eventually succeed if rate allows.
        assert!(qos.acquire(250, Priority::Critical).await.is_ok());
        assert!(qos.acquire(100, Priority::Low).await.is_ok());
    }

    #[tokio::test]
    async fn test_qos_fairness() {
        tokio::time::pause();
        let qos = SharedQosBandwidthLimiter::new(100); // 100 bytes/s
        
        // Queue many Critical requests (should saturate bandwidth)
        for _ in 0..10 {
            let qos_c = qos.clone();
            tokio::spawn(async move {
                let _ = qos_c.acquire(100, Priority::Critical).await;
            });
        }
        
        // Queue one Low request
        let qos_l = qos.clone();
        let low_task = tokio::spawn(async move {
            qos_l.acquire(50, Priority::Low).await
        });
        
        // Advance time.
        // Critical weight = 10000. Low = 1000.
        // Critical will drain tokens initially.
        // But eventually Low should get served due to deficit accumulation or interleaving?
        // With DRR, if Critical keeps coming, it consumes its quantum.
        // Low gets its quantum (1000).
        // Since rate is slow (100/s).
        // Round 1:
        // Critical deficit 10000. Low 1000.
        // Limiter has 100 tokens?
        // Critical takes 100. (Deficit 9900).
        // Limiter empty. Wait.
        // Next time tokens available:
        // Critical takes 100.
        // ...
        // Critical uses all 10000 deficit?
        // Yes, standard DRR exhausts quantum before switching if backlog exists.
        // So Critical runs for 100 seconds? (100 x 100 bytes / 100 rate).
        // This means "latency" for Low is high, but "Bandwidth Share" is fair over long term.
        
        // Wait enough time for Critical to finish SOME, but ensure Low also finishes?
        // Actually, with such high weight diff (10:1), Critical dominates.
        // But Low *will* run eventually.
        
        tokio::time::advance(Duration::from_secs(60)).await;
        
        // Low needs 50 bytes = 0.5s.
        // Even if deep in queue, 60s is enough?
        // 10 Critical x 100 = 1000 bytes = 10s.
        // Total load = 10.5s.
        // 60s is enough for ALL to finish.
        assert!(low_task.is_finished(), "Low task should ensure service eventually");
    }

    #[tokio::test]
    async fn test_try_acquire_insufficient() {
        let limiter = BandwidthLimiter::new(1000);
        
        // Drain all tokens
        limiter.acquire(2000).await.unwrap();
        
        // try_acquire should return Insufficient immediately
        let result = limiter.try_acquire(100).await;
        assert!(matches!(result, Err(AcquireError::Insufficient)));
    }

    #[tokio::test]
    async fn test_multi_round_refill_recovery() {
        tokio::time::pause();
        
        let limiter = BandwidthLimiter::with_capacity(1000, 1000);
        
        // Drain tokens
        limiter.acquire(1000).await.unwrap();
        
        // Simulate long pause (60 seconds)
        tokio::time::advance(Duration::from_secs(60)).await;
        
        // Should be able to acquire immediately (multi-round refill catches up)
        let limiter_clone = limiter.clone();
        let task = tokio::spawn(async move {
            let start = Instant::now();
            limiter_clone.acquire(1000).await.unwrap();
            start.elapsed()
        });
        
        // Allow task to run
        tokio::time::sleep(Duration::from_millis(10)).await;
        
        let elapsed = task.await.unwrap();
        
        // Should complete quickly with paused time (not wait for 60 rounds)
        assert!(elapsed < Duration::from_millis(100), 
            "Multi-round refill should catch up quickly, took {:?}", elapsed);
        
        // But should not exceed capacity
        let tokens = limiter.available_tokens().await;
        assert!(tokens <= 1000);
    }
}
