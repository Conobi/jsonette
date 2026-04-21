#include "simdjson.h"
#include <chrono>
#include <iostream>

int main(int argc, char *argv[]) {
    if (argc < 2) { std::cerr << "Usage: bench <file>\n"; return 1; }

    simdjson::padded_string json = simdjson::padded_string::load(argv[1]).value();
    simdjson::dom::parser parser;

    // Warmup
    for (int i = 0; i < 10; i++) {
        auto doc = parser.parse(json);
    }

    // Measure
    constexpr int ITERS = 500;
    auto start = std::chrono::high_resolution_clock::now();
    for (int i = 0; i < ITERS; i++) {
        auto doc = parser.parse(json);
    }
    auto end = std::chrono::high_resolution_clock::now();

    auto ns = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
    double bytes = json.size() * ITERS;
    double gb_per_s = bytes / ns;
    double mb_per_s = gb_per_s * 1000.0;

    std::cout << argv[1] << ": " << mb_per_s << " MB/s (" << ITERS << " iterations, " << ns/1000000 << " ms total)" << std::endl;
    return 0;
}
