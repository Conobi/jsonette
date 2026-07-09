//! kostya JSON benchmark — Rust/serde_json "Typed struct" variant.
//!
//! Mirror of ``json/json.rs/src/json_struct.rs`` in kostya's suite (the
//! entry labelled "Rust (Serde Typed)"). We deserialize into a bespoke
//! ``TestStruct { coordinates: Vec<Coordinate> }`` where ``Coordinate``
//! only carries ``x``, ``y``, ``z`` — so ``name`` and ``opts`` are
//! parsed once and immediately discarded by serde (Vec is still
//! materialised in full).
//!
//! This is the interpretation of "serde with custom typing" that maps
//! onto the derive macro path — the same tier the reference table
//! reports for "Rust (Serde Typed)".

use kostya_rust::{run, Coord};
use serde::Deserialize;

#[derive(Deserialize)]
struct RawCoord {
    x: f64,
    y: f64,
    z: f64,
}

#[derive(Deserialize)]
struct TestStruct {
    coordinates: Vec<RawCoord>,
}

fn calc(text: &str) -> Coord {
    let jobj: TestStruct = serde_json::from_str(text).unwrap();
    let n = jobj.coordinates.len() as f64;
    let mut x = 0.0f64;
    let mut y = 0.0f64;
    let mut z = 0.0f64;
    for c in &jobj.coordinates {
        x += c.x;
        y += c.y;
        z += c.z;
    }
    Coord { x: x / n, y: y / n, z: z / n }
}

fn main() {
    run("Serde Typed", calc);
}
