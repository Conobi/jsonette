// kostya_perf.h — minimal perf_event_open wrapper for the kostya bench.
//
// Opens a hardware cycles counter and a groupped instructions counter via the
// Linux perf_event_open syscall (arch/x86_64 syscall number 298 — the same
// one bench/_metrics.mojo uses on the Mojo side, so the numbers reported by
// C++/simdjson and jsonette are apples-to-apples). Reset/enable before the
// timed region, disable after, read counters. Silently degrades to
// ``available=false`` on hosts where perf_event_open is refused (e.g.
// perf_event_paranoid too strict, no CAP_PERFMON, unsupported kernel) — the
// bench then reports ``cyc/B=n/a`` / ``ins/B=n/a`` like it did before this
// header existed.
//
// Kept header-only and dependency-free (only <linux/perf_event.h>,
// <sys/syscall.h>, <unistd.h>) so the C++ variants stay a single
// ``g++ ... -o binary`` invocation.

#pragma once

#include <linux/perf_event.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <cstdint>
#include <cstdio>
#include <cstring>

namespace kostya_perf {

inline long perf_event_open_syscall(struct perf_event_attr* attr, pid_t pid,
                                    int cpu, int group_fd, unsigned long flags) {
    return syscall(SYS_perf_event_open, attr, pid, cpu, group_fd, flags);
}

class PerfGroup {
public:
    PerfGroup() = default;

    ~PerfGroup() {
        if (cycles_fd_ >= 0) ::close(cycles_fd_);
        if (instructions_fd_ >= 0) ::close(instructions_fd_);
    }

    PerfGroup(const PerfGroup&) = delete;
    PerfGroup& operator=(const PerfGroup&) = delete;

    // Open a two-counter group (cycles leader + instructions follower). Sets
    // ``available = true`` on success; otherwise leaves counters closed and
    // callers treat the group as absent.
    void open() {
        struct perf_event_attr attr {};
        attr.type = PERF_TYPE_HARDWARE;
        attr.size = sizeof(attr);
        attr.config = PERF_COUNT_HW_CPU_CYCLES;
        attr.disabled = 1;
        attr.exclude_kernel = 1;
        attr.exclude_hv = 1;
        cycles_fd_ = perf_event_open_syscall(&attr, 0, -1, -1, 0);
        if (cycles_fd_ < 0) return;

        struct perf_event_attr iattr {};
        iattr.type = PERF_TYPE_HARDWARE;
        iattr.size = sizeof(iattr);
        iattr.config = PERF_COUNT_HW_INSTRUCTIONS;
        iattr.disabled = 0;   // follower — enable/disable rides the leader.
        iattr.exclude_kernel = 1;
        iattr.exclude_hv = 1;
        instructions_fd_ = perf_event_open_syscall(&iattr, 0, -1, cycles_fd_, 0);
        if (instructions_fd_ < 0) {
            ::close(cycles_fd_);
            cycles_fd_ = -1;
            return;
        }
        available_ = true;
    }

    bool available() const { return available_; }

    // The following ops are no-ops when ``available()`` is false, so callers
    // don't need to guard them.
    void reset() {
        if (!available_) return;
        ::ioctl(cycles_fd_, PERF_EVENT_IOC_RESET, PERF_IOC_FLAG_GROUP);
    }
    void enable() {
        if (!available_) return;
        ::ioctl(cycles_fd_, PERF_EVENT_IOC_ENABLE, PERF_IOC_FLAG_GROUP);
    }
    void disable() {
        if (!available_) return;
        ::ioctl(cycles_fd_, PERF_EVENT_IOC_DISABLE, PERF_IOC_FLAG_GROUP);
    }
    uint64_t cycles() const {
        if (!available_) return 0;
        uint64_t v = 0;
        auto _ = ::read(cycles_fd_, &v, sizeof(v));
        (void)_;
        return v;
    }
    uint64_t instructions() const {
        if (!available_) return 0;
        uint64_t v = 0;
        auto _ = ::read(instructions_fd_, &v, sizeof(v));
        (void)_;
        return v;
    }

private:
    int cycles_fd_ = -1;
    int instructions_fd_ = -1;
    bool available_ = false;
};

// Peak-RSS reader shared by the C++ variants. Parses ``VmHWM:`` from
// ``/proc/self/status`` (kilobytes) — matches ``bench/_metrics.mojo``'s
// ``vm_hwm_kb`` and the Rust helper in ``rust/src/lib.rs`` so the memory
// footprint column is measured the same way across all three languages.
// Returns -1 if the file can't be read or the field isn't present.
inline long read_vm_hwm_kib() {
    FILE* f = std::fopen("/proc/self/status", "r");
    if (f == nullptr) return -1;
    char buf[256];
    long kb = -1;
    while (std::fgets(buf, sizeof(buf), f) != nullptr) {
        if (std::sscanf(buf, "VmHWM: %ld kB", &kb) == 1) {
            std::fclose(f);
            return kb;
        }
    }
    std::fclose(f);
    return -1;
}

}  // namespace kostya_perf
