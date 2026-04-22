use std::fs;
use std::time::Instant;

fn bench_file(path: &str, iterations: usize) {
    let data = fs::read(path).unwrap();
    let size = data.len();

    // Warmup
    for _ in 0..10 {
        let _: serde_json::Value = serde_json::from_slice(&data).unwrap();
    }

    // Measure
    let start = Instant::now();
    for _ in 0..iterations {
        let _: serde_json::Value = serde_json::from_slice(&data).unwrap();
    }
    let elapsed = start.elapsed();

    let total_bytes = size * iterations;
    let mb_per_sec = total_bytes as f64 / elapsed.as_secs_f64() / 1_000_000.0;

    println!(
        "{}: {:.1} MB/s ({} iterations, {:.0} ms)",
        path,
        mb_per_sec,
        iterations,
        elapsed.as_millis()
    );
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: bench <file> [iterations]");
        std::process::exit(1);
    }
    let iterations = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(500);
    bench_file(&args[1], iterations);
}
