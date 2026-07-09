//! kostya JSON benchmark — Rust/serde_json "Untyped" variant.
//!
//! Mirror of ``json/json.rs/src/json_value.rs`` in kostya's suite (the
//! entry labelled "Rust (Serde Untyped)"). We parse ``/tmp/1.json`` into
//! a fully-materialised ``serde_json::Value`` tree, then walk it by
//! name and sum x/y/z — the closest apples-to-apples with a DOM parse
//! into a generic value tree.
//!
//! Timing scaffolding lives in ``lib.rs`` so all three variants share
//! self-check + WARMUP/ITERS + min-time reporting (parity with the
//! C++/simdjson and jsonette runners in this directory).

use kostya_rust::{run, Coord};
use serde_json::Value;

fn calc(text: &str) -> Coord {
    let value: Value = serde_json::from_str(text).unwrap();
    let coords = value.get("coordinates").unwrap().as_array().unwrap();
    let mut x = 0.0f64;
    let mut y = 0.0f64;
    let mut z = 0.0f64;
    for coord in coords.iter() {
        x += coord.get("x").unwrap().as_f64().unwrap();
        y += coord.get("y").unwrap().as_f64().unwrap();
        z += coord.get("z").unwrap().as_f64().unwrap();
    }
    let n = coords.len() as f64;
    Coord { x: x / n, y: y / n, z: z / n }
}

fn main() {
    run("Serde Untyped", calc);
}
