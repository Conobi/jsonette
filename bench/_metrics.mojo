"""Bench-only hardware performance counters and peak-memory readers.

This module is for the benchmark harness only; it is never imported by the
parser. It exposes Linux `perf_event_open` hardware counters (CPU cycles and
retired instructions) grouped so both counters cover the exact same measured
region, plus two independent peak-resident-memory readers (`getrusage` and
`/proc/self/status`).

Because this is an FFI boundary, raw `UnsafePointer` use is expected and the
validator's M9 rule does not apply.

Usage (per-iteration measurement):
    var g = PerfGroup()
    g.open()
    g.reset(); g.enable()
    # ... measured work ...
    g.disable()
    var cyc = g.cycles()
    var ins = g.instructions()
    g.close()

If `perf_event_open` is unavailable (e.g. `perf_event_paranoid` too high), the
group degrades gracefully: `available` stays `False` and all reads return 0.
"""

from std.ffi import external_call
from std.memory.unsafe_pointer import alloc
from std.memory import memset_zero


comptime SYS_read = 0
comptime SYS_perf_event_open = 298
comptime ATTR_SIZE = 128
comptime PERF_TYPE_HARDWARE = 0
comptime PERF_COUNT_HW_CPU_CYCLES = 0
comptime PERF_COUNT_HW_INSTRUCTIONS = 1
comptime PERF_EVENT_IOC_ENABLE = 0x2400
comptime PERF_EVENT_IOC_DISABLE = 0x2401
comptime PERF_EVENT_IOC_RESET = 0x2403
comptime PERF_IOC_FLAG_GROUP = 1

comptime RUSAGE_SELF = 0


def _syscall6(
    num: Int64, a1: Int64, a2: Int64, a3: Int64, a4: Int64, a5: Int64
) -> Int64:
    """Invoke the raw libc `syscall` with a single fixed 6-argument signature.

    All raw syscalls in this module funnel through here so the `syscall`
    external symbol is bound with exactly one signature; mixing signatures for
    the same symbol fails to link. Pointer arguments are passed as their
    integer address (`Int(ptr)`).

    Args:
        num: The Linux syscall number.
        a1: First syscall argument (or pointer address).
        a2: Second syscall argument (or pointer address).
        a3: Third syscall argument.
        a4: Fourth syscall argument.
        a5: Fifth syscall argument.

    Returns:
        The syscall return value (negative on error).
    """
    return external_call["syscall", Int64](num, a1, a2, a3, a4, a5)


def _open_counter(config: UInt64, group_fd: Int64) -> Int64:
    """Open a single hardware perf counter via `perf_event_open`.

    Builds a zeroed `perf_event_attr` of `ATTR_SIZE` bytes, sets the hardware
    type, attr size, and event config, and excludes kernel/hypervisor samples
    so a non-privileged process can read the counter. The group leader
    (`group_fd < 0`) is opened `disabled` so the whole group can be started
    atomically later.

    Args:
        config: The `PERF_COUNT_HW_*` event selector.
        group_fd: The leader fd to join, or a negative value to be the leader.

    Returns:
        The counter file descriptor, or a negative value on failure.
    """
    var attr = alloc[UInt8](ATTR_SIZE).as_any_origin()
    memset_zero(attr, ATTR_SIZE)
    (attr + 0).bitcast[UInt32]()[] = UInt32(PERF_TYPE_HARDWARE)
    (attr + 4).bitcast[UInt32]()[] = UInt32(ATTR_SIZE)
    (attr + 8).bitcast[UInt64]()[] = config
    var flags = (UInt64(1) << 5) | (UInt64(1) << 6)  # exclude_kernel | exclude_hv
    if group_fd < 0:
        flags = flags | (UInt64(1) << 0)  # disabled (leader starts stopped)
    (attr + 40).bitcast[UInt64]()[] = flags
    var fd = _syscall6(
        Int64(SYS_perf_event_open),
        Int64(Int(attr)),
        Int64(0),
        Int64(-1),
        group_fd,
        Int64(0),
    )
    attr.free()
    return fd


def _ioctl_leader(leader_fd: Int64, request: Int64):
    """Issue an ioctl on the group-leader fd.

    Enabling, disabling, or resetting the leader fd applies atomically to the
    whole group, keeping cycles and instructions over the same region.

    `PERF_IOC_FLAG_GROUP` is passed so the operation applies to every counter
    in the group, not just the leader — without it `PERF_EVENT_IOC_RESET` zeroes
    only the leader and the other counters accumulate across iterations.

    Args:
        leader_fd: The cycles counter fd (the group leader).
        request: One of `PERF_EVENT_IOC_ENABLE` / `_DISABLE` / `_RESET`.
    """
    _ = external_call["ioctl", Int32](
        Int32(leader_fd), Int32(request), Int32(PERF_IOC_FLAG_GROUP)
    )


def _read_counter(fd: Int64) -> UInt64:
    """Read a single 64-bit counter value from a perf fd.

    Args:
        fd: The counter file descriptor.

    Returns:
        The accumulated counter value, or 0 if the read failed.
    """
    var buf = alloc[UInt64](1).as_any_origin()
    buf[] = UInt64(0)
    # Read via the raw syscall (read == syscall 0 on x86-64). The stdlib binds
    # external_call["read", ...] with a different signature for file I/O, and
    # two conflicting signatures for the same symbol fail to link; perf fds are
    # pipe-like so pread/ESPIPE is not an option either. The raw syscall
    # sidesteps both problems and reuses the module's single syscall signature.
    var n = _syscall6(
        Int64(SYS_read),
        fd,
        Int64(Int(buf)),
        Int64(8),
        Int64(0),
        Int64(0),
    )
    var value = UInt64(0)
    if n == 8:
        value = buf[]
    buf.free()
    return value


struct PerfGroup:
    """A grouped pair of hardware perf counters: CPU cycles + instructions.

    Cycles is the group leader; instructions joins the group so a single
    enable/disable/reset on the leader fd covers both counters over the same
    region. If the kernel rejects `perf_event_open`, `available` is `False` and
    all reads return 0, allowing a harness to run on machines without perf
    access.
    """

    var available: Bool
    var cycles_fd: Int64
    var instructions_fd: Int64

    def __init__(out self):
        """Construct an unopened group; call `open` before measuring."""
        self.available = False
        self.cycles_fd = Int64(-1)
        self.instructions_fd = Int64(-1)

    def open(mut self):
        """Open the cycles+instructions counter group.

        Cycles is opened as the disabled group leader; instructions joins it.
        On any failure the counters are closed and `available` stays `False`.
        """
        self.cycles_fd = _open_counter(
            UInt64(PERF_COUNT_HW_CPU_CYCLES), Int64(-1)
        )
        if self.cycles_fd < 0:
            self.available = False
            return
        self.instructions_fd = _open_counter(
            UInt64(PERF_COUNT_HW_INSTRUCTIONS), self.cycles_fd
        )
        if self.instructions_fd < 0:
            _ = external_call["close", Int32](Int32(self.cycles_fd))
            self.cycles_fd = Int64(-1)
            self.available = False
            return
        self.available = True

    def reset(self):
        """Zero both counters (no-op if the group is unavailable)."""
        if self.available:
            _ioctl_leader(self.cycles_fd, Int64(PERF_EVENT_IOC_RESET))

    def enable(self):
        """Start counting on both counters (no-op if unavailable)."""
        if self.available:
            _ioctl_leader(self.cycles_fd, Int64(PERF_EVENT_IOC_ENABLE))

    def disable(self):
        """Stop counting on both counters (no-op if unavailable)."""
        if self.available:
            _ioctl_leader(self.cycles_fd, Int64(PERF_EVENT_IOC_DISABLE))

    def cycles(self) -> UInt64:
        """Return accumulated CPU cycles, or 0 if the group is unavailable."""
        if not self.available:
            return UInt64(0)
        return _read_counter(self.cycles_fd)

    def instructions(self) -> UInt64:
        """Return accumulated retired instructions, or 0 if unavailable."""
        if not self.available:
            return UInt64(0)
        return _read_counter(self.instructions_fd)

    def close(mut self):
        """Close both counter fds and mark the group unavailable."""
        if self.instructions_fd >= 0:
            _ = external_call["close", Int32](Int32(self.instructions_fd))
            self.instructions_fd = Int64(-1)
        if self.cycles_fd >= 0:
            _ = external_call["close", Int32](Int32(self.cycles_fd))
            self.cycles_fd = Int64(-1)
        self.available = False


def peak_rss_kb() -> Int:
    """Return peak resident set size in KB via `getrusage(RUSAGE_SELF)`.

    The `rusage` struct begins with two 16-byte `timeval`s (`ru_utime`,
    `ru_stime`); `ru_maxrss` is the 5th `long` (index 4) and is reported in
    kilobytes on Linux.

    Returns:
        Peak RSS in KB, or 0 if the call failed.
    """
    var buf = alloc[Int64](18).as_any_origin()
    memset_zero(buf, 18)
    var rc = external_call["getrusage", Int32](Int32(RUSAGE_SELF), buf)
    var maxrss = Int(0)
    if rc == 0:
        maxrss = Int(buf[4])
    buf.free()
    return maxrss


def vm_hwm_kb() raises -> Int:
    """Return peak resident memory in KB by parsing `/proc/self/status`.

    Reads the `VmHWM:` line ("high water mark" RSS) and extracts its KB digit
    run. This is an independent cross-check against `peak_rss_kb`.

    Returns:
        VmHWM in KB, or 0 if the line was not found.
    """
    var contents: String
    with open("/proc/self/status", "r") as f:
        contents = f.read()
    var lines = contents.split("\n")
    for ref line in lines:
        if line.startswith("VmHWM:"):
            var digits = String("")
            for ref ch in line.codepoints():
                var c = ch.to_u32()
                if c >= UInt32(ord("0")) and c <= UInt32(ord("9")):
                    digits += String(ch)
            if digits.byte_length() > 0:
                return Int(atol(digits))
    return 0


def _spin(rounds: Int) -> Int64:
    """Burn a deterministic amount of work so counters track it.

    Args:
        rounds: Number of accumulation iterations.

    Returns:
        An accumulator (returned to prevent the loop being optimised away).
    """
    var acc = Int64(0)
    for i in range(rounds):
        acc = acc + Int64(i) * Int64(3) - (acc >> 1)
    return acc


def main() raises:
    """Self-test: prove counters track work and print memory readers."""
    var g = PerfGroup()
    g.open()
    print("perf available:", g.available)

    # Small workload.
    g.reset()
    g.enable()
    var s_acc = _spin(100_000)
    g.disable()
    var small_cyc = g.cycles()
    var small_ins = g.instructions()
    print("small: cycles =", small_cyc, " instructions =", small_ins, " (acc", s_acc, ")")

    # Large workload (100x).
    g.reset()
    g.enable()
    var l_acc = _spin(10_000_000)
    g.disable()
    var large_cyc = g.cycles()
    var large_ins = g.instructions()
    print("large: cycles =", large_cyc, " instructions =", large_ins, " (acc", l_acc, ")")

    if g.available:
        if large_cyc <= small_cyc:
            raise Error("counter did not track work: large cycles <= small cycles")
        if large_ins <= small_ins:
            raise Error("counter did not track work: large instructions <= small instructions")
        print("OK: large > small for both counters")
    else:
        print("perf unavailable; cycle assertions skipped (rss still reported)")

    g.close()

    print("peak_rss_kb =", peak_rss_kb())
    print("vm_hwm_kb   =", vm_hwm_kb())
