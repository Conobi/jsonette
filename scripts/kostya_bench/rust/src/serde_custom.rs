//! kostya JSON benchmark — Rust/serde_json "Custom visitor" variant.
//!
//! Mirror of ``json/json.rs/src/json_pull.rs`` in kostya's suite (the
//! entry labelled "Rust (Serde Custom)" — the fastest Rust entry on the
//! reference table at ~0.103 s). Instead of allocating a
//! ``Vec<Coordinate>``, we hand serde a hand-rolled ``Visitor`` that
//! streams the array and accumulates sums as elements arrive, so the
//! only work per coordinate is three ``f64`` decodes and three adds.
//!
//! This is the interpretation of "serde with custom typing" that maps
//! onto a bespoke pull-style deserializer — the number the OSS
//! reviewer meant when saying "serde with custom typing could be very
//! fast".

use kostya_rust::{run, Coord};
use serde::de::{SeqAccess, Visitor};
use serde::{Deserialize, Deserializer};
use std::fmt::{self, Formatter};

#[derive(Deserialize)]
struct RawCoord {
    x: f64,
    y: f64,
    z: f64,
}

struct AccState {
    x: f64,
    y: f64,
    z: f64,
    len: usize,
}

#[derive(Deserialize)]
struct TestStruct {
    #[serde(
        deserialize_with = "deserialize_add",
        rename(deserialize = "coordinates")
    )]
    state: AccState,
}

fn deserialize_add<'de, D>(deserializer: D) -> Result<AccState, D::Error>
where
    D: Deserializer<'de>,
{
    struct StateVisitor;

    impl<'de> Visitor<'de> for StateVisitor {
        type Value = AccState;

        fn expecting(&self, formatter: &mut Formatter) -> fmt::Result {
            write!(formatter, "an array of coordinates")
        }

        fn visit_seq<V>(self, mut visitor: V) -> Result<AccState, V::Error>
        where
            V: SeqAccess<'de>,
        {
            let mut ac = AccState { x: 0.0, y: 0.0, z: 0.0, len: 0 };
            while let Some(v) = visitor.next_element::<RawCoord>()? {
                ac.x += v.x;
                ac.y += v.y;
                ac.z += v.z;
                ac.len += 1;
            }
            Ok(ac)
        }
    }

    deserializer.deserialize_seq(StateVisitor)
}

fn calc(text: &str) -> Coord {
    let test: TestStruct = serde_json::from_str(text).unwrap();
    let n = test.state.len as f64;
    Coord {
        x: test.state.x / n,
        y: test.state.y / n,
        z: test.state.z / n,
    }
}

fn main() {
    run("Serde Custom", calc);
}
