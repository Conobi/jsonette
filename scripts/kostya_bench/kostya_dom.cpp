// kostya_dom.cpp
//
// Port of github.com/kostya/benchmarks/blob/master/json/test_simdjson_dom.cpp
// with the ``libnotify`` timing wrapper replaced by ``std::chrono``. Reuses the
// simdjson single-header at ../cpp_bench/ so this file builds standalone.
//
// Behaviour mirrors the reference verbatim:
//   * Load ``/tmp/1.json`` outside the timed region.
//   * Self-check on two field-order permutations.
//   * Fresh ``dom::parser`` + ``pj.allocate(size)`` + ``pj.parse(text)`` per
//     call — this is the C++ DOM one-shot cost the kostya table publishes.
//
// Build:
//   g++ -O3 -march=native -I ../cpp_bench kostya_dom.cpp \
//       ../cpp_bench/simdjson.cpp -o kostya_dom

#include "simdjson.h"
#include "kostya_perf.h"

#include <chrono>
#include <cstdio>
#include <iomanip>
#include <iostream>
#include <limits>

using simdjson::padded_string;
namespace dom = simdjson::dom;

namespace {
constexpr int WARMUP = 3;
constexpr int ITERS = 10;
}  // namespace

struct coordinate_t {
    double x{};
    double y{};
    double z{};

    bool near(const coordinate_t& o, double tol = 1e-12) const {
        auto near1 = [tol](double a, double b) { return std::abs(a - b) <= tol; };
        return near1(x, o.x) && near1(y, o.y) && near1(z, o.z);
    }
};

std::ostream& operator<<(std::ostream& out, const coordinate_t& c) {
    // ``setprecision(17)`` is the minimum for round-trip f64; the Mojo and
    // Rust benches use their runtimes' shortest-round-trip formatting, so this
    // brings the C++ output up to the same precision. The ``Coordinate(x=...)``
    // shape matches the other two languages verbatim — makes the coordinate
    // line usable as a cross-language parity check.
    out << "Coordinate(x=" << std::setprecision(17) << c.x
        << ", y=" << c.y << ", z=" << c.z << ")";
    return out;
}

coordinate_t calc(const padded_string& text) {
    dom::parser pj;
    if (auto err = pj.allocate(text.size()); err) {
        std::cerr << "allocate: " << err << "\n";
        std::exit(1);
    }
    dom::element doc;
    if (auto err = pj.parse(text).get(doc); err) {
        std::cerr << "parse: " << err << "\n";
        std::exit(1);
    }
    double x = 0.0, y = 0.0, z = 0.0;
    int count = 0;
    for (auto coord : doc["coordinates"]) {
        x += double(coord["x"]);
        y += double(coord["y"]);
        z += double(coord["z"]);
        ++count;
    }
    return {x / count, y / count, z / count};
}

int main() {
    using namespace simdjson;  // NOLINT — enables the _padded UDL for literals.
    const coordinate_t want{2.0, 0.5, 0.25};
    for (const padded_string& v : {
             R"({"coordinates":[{"x":2.0,"y":0.5,"z":0.25}]})"_padded,
             R"({"coordinates":[{"y":0.5,"x":2.0,"z":0.25}]})"_padded,
         }) {
        auto got = calc(v);
        if (!got.near(want)) {
            std::cerr << "selfcheck failed: " << got << " != " << want << "\n";
            return 1;
        }
    }

    padded_string text;
    auto err = padded_string::load("/tmp/1.json").get(text);
    if (err) {
        std::cerr << "could not load /tmp/1.json: " << err << "\n";
        return 1;
    }

    kostya_perf::PerfGroup perf;
    perf.open();
    std::printf(
        "kostya DOM (C++/simdjson)  size=%.2f MiB  WARMUP=%d  ITERS=%d  perf=%s\n",
        double(text.size()) / (1024.0 * 1024.0), WARMUP, ITERS,
        perf.available() ? "true" : "false");

    // Baseline RSS captured AFTER file load + self-check, BEFORE any timed
    // work — matches kostya's ``base + increase`` methodology.
    long mem_base_kib = kostya_perf::read_vm_hwm_kib();

    for (int i = 0; i < WARMUP; ++i) {
        auto r = calc(text);
        (void)r;
    }

    // Pass 1 — min-time wall clock (no counter syscalls in the region).
    long long first_ns = 0;
    long long min_ns = std::numeric_limits<long long>::max();
    coordinate_t result{};
    double sink = 0.0;
    for (int i = 0; i < ITERS; ++i) {
        auto t0 = std::chrono::steady_clock::now();
        auto r = calc(text);
        auto t1 = std::chrono::steady_clock::now();
        auto dt = std::chrono::duration_cast<std::chrono::nanoseconds>(t1 - t0).count();
        if (i == 0) {
            first_ns = dt;
            result = r;
        }
        if (dt < min_ns) min_ns = dt;
        sink += r.x + r.y + r.z;
    }

    // Pass 2 — min cycles / instructions (separate so ioctl/read don't
    // pollute Pass 1). Skipped cleanly if perf_event_open was refused.
    uint64_t best_cyc = std::numeric_limits<uint64_t>::max();
    uint64_t best_ins = std::numeric_limits<uint64_t>::max();
    if (perf.available()) {
        for (int i = 0; i < ITERS; ++i) {
            perf.reset();
            perf.enable();
            auto r = calc(text);
            perf.disable();
            sink += r.x + r.y + r.z;
            auto c = perf.cycles();
            auto ins = perf.instructions();
            if (c < best_cyc) best_cyc = c;
            if (ins < best_ins) best_ins = ins;
        }
    }

    std::cout << result << "\n";
    std::printf("first_time_s=%.6f\n", double(first_ns) / 1e9);
    std::printf("min_time_s=%.6f\n", double(min_ns) / 1e9);
    std::printf("MB/s=%.1f\n", double(text.size()) / (double(min_ns) / 1e9) / 1e6);
    std::printf("ns/op=%lld\n", min_ns);
    if (perf.available()) {
        std::printf("cyc/B=%.2f\n", double(best_cyc) / double(text.size()));
        std::printf("ins/B=%.2f\n", double(best_ins) / double(text.size()));
    } else {
        std::printf("cyc/B=n/a\n");
        std::printf("ins/B=n/a\n");
    }
    long mem_peak_kib = kostya_perf::read_vm_hwm_kib();
    if (mem_base_kib < 0 || mem_peak_kib < 0) {
        std::printf("mem_base_MiB=n/a\nmem_peak_MiB=n/a\nmem_delta_MiB=n/a\n");
    } else {
        std::printf("mem_base_MiB=%.1f\n", double(mem_base_kib) / 1024.0);
        std::printf("mem_peak_MiB=%.1f\n", double(mem_peak_kib) / 1024.0);
        std::printf("mem_delta_MiB=%.1f\n",
                    double(mem_peak_kib - mem_base_kib) / 1024.0);
    }
    std::printf("sink=%.17g\n", sink);
    return 0;
}
