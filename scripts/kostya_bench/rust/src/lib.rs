//! Shared timing / self-check scaffolding for the kostya Rust variants.
//!
//! Every variant runs the same shape: two-string self-check for
//! ``Coordinate(2.0, 0.5, 0.25)``, load ``/tmp/1.json`` outside the timed
//! region, ``WARMUP`` + ``ITERS`` iterations, then two passes:
//!
//!   1. Wall clock (``first_time_s`` and ``min_time_s``) — no perf syscalls
//!      in the region, so ioctl/read cost never pollutes the timing.
//!   2. ``cyc/B`` and ``ins/B`` via ``perf_event_open`` (grouped cycles +
//!      instructions counters) — matched to ``bench/_metrics.mojo``'s
//!      ``PerfGroup`` and ``scripts/kostya_bench/kostya_perf.h`` so the
//!      three implementations are directly comparable. Reports ``n/a`` on
//!      hosts where ``perf_event_open`` is refused.
//!
//! Kept here so the per-variant files stay focused on the actual parse
//! strategy — struct-derive, ``serde_json::Value``, custom visitor.

use std::fs;
use std::time::Instant;

#[cfg(target_os = "linux")]
mod perf {
    //! Optional cycles+instructions counters via the ``perf-event`` crate.
    //! Returns ``None`` on the fallible ``Group::new()`` path (host refused
    //! ``perf_event_open``) so the caller can print ``n/a`` cleanly.

    use perf_event::events::Hardware;
    use perf_event::{Builder, Counter, Group};

    pub struct PerfGroup {
        group: Group,
        cycles: Counter,
        instructions: Counter,
    }

    impl PerfGroup {
        pub fn open() -> Option<Self> {
            let mut group = Group::new().ok()?;
            let cycles = Builder::new()
                .group(&mut group)
                .kind(Hardware::CPU_CYCLES)
                .build()
                .ok()?;
            let instructions = Builder::new()
                .group(&mut group)
                .kind(Hardware::INSTRUCTIONS)
                .build()
                .ok()?;
            Some(PerfGroup { group, cycles, instructions })
        }
        pub fn reset(&mut self) { let _ = self.group.reset(); }
        pub fn enable(&mut self) { let _ = self.group.enable(); }
        pub fn disable(&mut self) { let _ = self.group.disable(); }
        pub fn cycles(&mut self) -> u64 {
            self.cycles.read().unwrap_or(0)
        }
        pub fn instructions(&mut self) -> u64 {
            self.instructions.read().unwrap_or(0)
        }
    }
}

#[cfg(not(target_os = "linux"))]
mod perf {
    // Non-Linux hosts don't have perf_event_open; keep the API surface so
    // the caller code stays cfg-clean but every call is a no-op.
    pub struct PerfGroup;
    impl PerfGroup {
        pub fn open() -> Option<Self> { None }
        pub fn reset(&mut self) {}
        pub fn enable(&mut self) {}
        pub fn disable(&mut self) {}
        pub fn cycles(&mut self) -> u64 { 0 }
        pub fn instructions(&mut self) -> u64 { 0 }
    }
}

/// Peak-RSS reader: parses ``VmHWM:`` from ``/proc/self/status`` (kilobytes).
/// Matches ``kostya_perf.h::read_vm_hwm_kib`` (C++) and
/// ``bench/_metrics.mojo::vm_hwm_kb`` (Mojo) so the memory footprint column
/// is measured the same way across all three languages. Returns ``None`` if
/// ``/proc/self/status`` can't be read or the field isn't present (non-Linux
/// hosts).
fn read_vm_hwm_kib() -> Option<u64> {
    let s = std::fs::read_to_string("/proc/self/status").ok()?;
    for line in s.lines() {
        if let Some(rest) = line.strip_prefix("VmHWM:") {
            let n: u64 = rest.trim().split_whitespace().next()?.parse().ok()?;
            return Some(n);
        }
    }
    None
}

pub const WARMUP: usize = 3;
pub const ITERS: usize = 10;

#[derive(Debug, Clone, Copy)]
pub struct Coord {
    pub x: f64,
    pub y: f64,
    pub z: f64,
}

impl Coord {
    /// True iff each component is within ``tol`` of ``other``'s.
    pub fn near(&self, other: &Coord, tol: f64) -> bool {
        (self.x - other.x).abs() <= tol
            && (self.y - other.y).abs() <= tol
            && (self.z - other.z).abs() <= tol
    }
}

/// Run a full kostya-shaped benchmark: self-check, then time ``calc`` on
/// ``/tmp/1.json``. Prints a header, the coordinate result, and two timings.
pub fn run(label: &str, calc: impl Fn(&str) -> Coord) {
    let want = Coord { x: 2.0, y: 0.5, z: 0.25 };
    for v in &[
        r#"{"coordinates":[{"x":2.0,"y":0.5,"z":0.25}]}"#,
        r#"{"coordinates":[{"y":0.5,"x":2.0,"z":0.25}]}"#,
    ] {
        let got = calc(v);
        assert!(
            got.near(&want, 1e-12),
            "selfcheck failed: got ({}, {}, {})",
            got.x, got.y, got.z
        );
    }

    let text = fs::read_to_string("/tmp/1.json").expect("read /tmp/1.json");
    let size = text.len();
    let size_mib = size as f64 / (1024.0 * 1024.0);
    let mut perf = perf::PerfGroup::open();
    println!(
        "kostya {} (Rust)  size={:.2} MiB  WARMUP={}  ITERS={}  perf={}",
        label, size_mib, WARMUP, ITERS, perf.is_some()
    );

    // Baseline RSS captured AFTER file load + self-check, BEFORE any timed
    // work — matches kostya's ``base + increase`` methodology.
    let mem_base_kib = read_vm_hwm_kib();

    for _ in 0..WARMUP {
        let _ = calc(&text);
    }

    // Pass 1 — min-time wall clock (no counter syscalls in the region).
    let mut first_ns: u128 = 0;
    let mut min_ns: u128 = u128::MAX;
    let mut sink: f64 = 0.0;
    let mut result = Coord { x: 0.0, y: 0.0, z: 0.0 };
    for i in 0..ITERS {
        let t0 = Instant::now();
        let r = calc(&text);
        let dt = t0.elapsed().as_nanos();
        if i == 0 {
            first_ns = dt;
            result = r;
        }
        if dt < min_ns {
            min_ns = dt;
        }
        sink += r.x + r.y + r.z;
    }

    // Pass 2 — min cycles / instructions (separate so ioctl/read don't pollute P1).
    let mut best_cyc: u64 = u64::MAX;
    let mut best_ins: u64 = u64::MAX;
    if let Some(ref mut p) = perf {
        for _ in 0..ITERS {
            p.reset();
            p.enable();
            let r = calc(&text);
            p.disable();
            sink += r.x + r.y + r.z;
            let c = p.cycles();
            let i = p.instructions();
            if c < best_cyc { best_cyc = c; }
            if i < best_ins { best_ins = i; }
        }
    }

    println!("Coordinate(x={}, y={}, z={})", result.x, result.y, result.z);
    println!("first_time_s={:.6}", first_ns as f64 / 1e9);
    println!("min_time_s={:.6}", min_ns as f64 / 1e9);
    let mbs = size as f64 / (min_ns as f64 / 1e9) / 1e6;
    println!("MB/s={:.1}", mbs);
    println!("ns/op={}", min_ns);
    if perf.is_some() {
        println!("cyc/B={:.2}", best_cyc as f64 / size as f64);
        println!("ins/B={:.2}", best_ins as f64 / size as f64);
    } else {
        println!("cyc/B=n/a");
        println!("ins/B=n/a");
    }
    let mem_peak_kib = read_vm_hwm_kib();
    match (mem_base_kib, mem_peak_kib) {
        (Some(b), Some(p)) => {
            println!("mem_base_MiB={:.1}", b as f64 / 1024.0);
            println!("mem_peak_MiB={:.1}", p as f64 / 1024.0);
            println!("mem_delta_MiB={:.1}", (p.saturating_sub(b)) as f64 / 1024.0);
        }
        _ => {
            println!("mem_base_MiB=n/a");
            println!("mem_peak_MiB=n/a");
            println!("mem_delta_MiB=n/a");
        }
    }
    println!("sink={:e}", sink);
}
