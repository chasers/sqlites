#!/usr/bin/env bash
# Litestream density benchmark: for each database count, generate the
# databases, start litestream replicating all of them (file:// replica),
# measure initial-sync time and steady-state RSS/CPU under write load.
#
#   ./bench/litestream_density/run.sh "1000 10000 50000" [write_rate]
set -euo pipefail

cd "$(dirname "$0")/../.."

COUNTS=${1:-"1000 10000"}
RATE=${2:-100}
BENCH_ROOT=${BENCH_ROOT:-/tmp/litestream-bench}

sample_proc() {
  ps -o rss=,pcpu= -p "$1" 2>/dev/null || echo "0 0"
}

for COUNT in $COUNTS; do
  WORK="$BENCH_ROOT/n$COUNT"
  rm -rf "$WORK"
  mkdir -p "$WORK"

  echo "=== N=$COUNT ==="
  mix run --no-start bench/litestream_density/gen_dbs.exs "$COUNT" "$WORK"

  SYNC_START=$(date +%s)
  litestream replicate -config "$WORK/litestream.yml" >"$WORK/litestream.log" 2>&1 &
  LS_PID=$!
  trap 'kill $LS_PID 2>/dev/null || true' EXIT

  # Initial sync is done when every db has a replica directory.
  until [ "$(ls "$WORK/replica" 2>/dev/null | wc -l | tr -d ' ')" -ge "$COUNT" ]; do
    if ! kill -0 $LS_PID 2>/dev/null; then echo "litestream died"; tail -5 "$WORK/litestream.log"; exit 1; fi
    sleep 2
  done
  SYNC_S=$(( $(date +%s) - SYNC_START ))

  read RSS_IDLE CPU_IDLE <<<"$(sample_proc $LS_PID)"

  mix run --no-start bench/litestream_density/writer.exs "$COUNT" "$WORK" "$RATE" 30 >/dev/null &
  WRITER_PID=$!
  sleep 15
  read RSS_LOAD CPU_LOAD <<<"$(sample_proc $LS_PID)"
  wait $WRITER_PID

  sleep 5
  read RSS_AFTER _ <<<"$(sample_proc $LS_PID)"

  ERRORS=$(grep -ci "error" "$WORK/litestream.log" || true)

  echo "RESULT n=$COUNT initial_sync_s=$SYNC_S rss_idle_mb=$((RSS_IDLE / 1024)) rss_under_load_mb=$((RSS_LOAD / 1024)) cpu_under_load_pct=$CPU_LOAD rss_after_mb=$((RSS_AFTER / 1024)) log_errors=$ERRORS"

  kill $LS_PID 2>/dev/null || true
  wait $LS_PID 2>/dev/null || true
done
