#[cfg(test)]
mod tests {
    use crate::network::bandwidth::{Priority, SharedQosBandwidthLimiter};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;
    use tokio::time::{Duration, Instant};

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn benchmark_throughput_uncontended() {
        println!("\n=== Benchmark: Uncontended Throughput (Single Task) ===");

        let rate = 1_000_000_000;
        let limiter = SharedQosBandwidthLimiter::new(rate);

        let duration = Duration::from_secs(5);
        let start = Instant::now();
        let mut bytes_acquired = 0;
        let chunk_size = 1000;

        while start.elapsed() < duration {
            limiter.acquire(chunk_size, Priority::Medium).await.unwrap();
            bytes_acquired += chunk_size;
        }

        let elapsed = start.elapsed();
        let throughput_mb = (bytes_acquired as f64 / 1024.0 / 1024.0) / elapsed.as_secs_f64();
        let ops_sec = (bytes_acquired / chunk_size) as f64 / elapsed.as_secs_f64();

        println!("Throughput: {:.2} MB/s", throughput_mb);
        println!("Ops/sec:    {:.2}", ops_sec);
        println!("Total:      {} bytes in {:.2?}", bytes_acquired, elapsed);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn benchmark_qos_latency_under_load() {
        println!("\n=== Benchmark: QoS Latency Under Load ===");

        let rate = 10_000_000;
        let limiter = SharedQosBandwidthLimiter::new(rate);

        let limiter_noise = limiter.clone();
        let running = Arc::new(AtomicUsize::new(1));
        let running_clone = running.clone();

        tokio::spawn(async move {
            while running_clone.load(Ordering::Relaxed) == 1 {
                let _ = limiter_noise.acquire(10_000, Priority::Medium).await;
            }
        });

        // Benchmark Critical vs Low latency
        // Run sequentially to see impact

        let run_benchmark = |priority: Priority,
                             name: &'static str,
                             limiter: SharedQosBandwidthLimiter| async move {
            let iterations = 100;
            let mut total_latency = Duration::ZERO;

            for _ in 0..iterations {
                let start = Instant::now();
                limiter.acquire(1000, priority).await.unwrap();
                total_latency += start.elapsed();
                tokio::time::sleep(Duration::from_millis(1)).await;
            }

            let avg = total_latency / iterations;
            println!("{}: Avg Latency = {:.2?}", name, avg);
        };

        // Wait for noise to start
        tokio::time::sleep(Duration::from_millis(100)).await;

        run_benchmark(Priority::Critical, "Critical", limiter.clone()).await;
        run_benchmark(Priority::Low, "Low     ", limiter.clone()).await;

        running.store(0, Ordering::Relaxed);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn benchmark_high_concurrency() {
        println!("\n=== Benchmark: High Concurrency (100 Tasks) ===");

        let rate = 100_000_000;
        let limiter = SharedQosBandwidthLimiter::new(rate);
        let start = Instant::now();
        let count = 100;

        let mut handles = vec![];
        for _ in 0..count {
            let l = limiter.clone();
            handles.push(tokio::spawn(async move {
                for _ in 0..100 {
                    l.acquire(1000, Priority::High).await.unwrap();
                }
            }));
        }

        for h in handles {
            h.await.unwrap();
        }

        let elapsed = start.elapsed();
        let total_ops = count * 100;
        let ops_sec = total_ops as f64 / elapsed.as_secs_f64();

        println!("Total Ops: {}", total_ops);
        println!("Time:      {:.2?}", elapsed);
        println!("Ops/sec:   {:.2}", ops_sec);
    }
}
