#!/usr/bin/env bash
# Host-load audit gate for benchmarking.
# Aborts (exit 1) unless the machine is quiet enough for verdict-grade numbers.
# Usage: bash scripts/audit_host.sh && <run bench>
set -euo pipefail

THRESHOLD="${AUDIT_THRESHOLD:-0.5}"   # max acceptable 1-minute load average
echo "--- host audit (1-min load threshold ${THRESHOLD}) ---"
cat /proc/loadavg

load1="$(awk '{print $1}' /proc/loadavg)"
# Abort if 1-min load exceeds the threshold.
if awk -v l="$load1" -v t="$THRESHOLD" 'BEGIN { exit !(l > t) }'; then
  echo "ABORT: 1-min load ${load1} exceeds threshold ${THRESHOLD} — machine too busy for a trustworthy bench."
  exit 1
fi

# Abort if a foreign CPU-heavy process is competing (>50% CPU, excluding this
# script). Skip self/infra processes: the `ps` measurement tool itself (a
# freshly-spawned ps shows ~100% pcpu = cputime/walltime artifact) and the
# steam-run FHS sandbox wrapper (`bwrap`/`steam-run`/`reaper`) that this audit
# is invoked *inside* — none of these are competing foreign workloads.
foreign="$(ps -eo pcpu,comm --sort=-pcpu | awk 'NR>1 && $1>50 \
  && $2!="ps" && $2!="bwrap" && $2!="steam-run" && $2!="reaper" && $2!="srt-bwrap" {print}')"
if [ -n "$foreign" ]; then
  echo "ABORT: foreign process(es) >50% CPU detected:"
  echo "$foreign"
  exit 1
fi

echo "host quiet (load ${load1}) — OK to bench"
