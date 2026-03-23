#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PG_SRC="$(dirname "$SCRIPT_DIR")"
PG_INSTALL="$HOME/pg-install"
PG_DATA="$HOME/pgdata"
RESULTS="$SCRIPT_DIR/results"
BENCH_DURATION=120
PERF_DURATION=30
PERF_FREQ=99
PGBENCH_SCALE=10

mkdir -p "$RESULTS"

# ── Phase 0: Install dependencies ──

if ! command -v perf &>/dev/null || ! command -v gcc &>/dev/null; then
  echo "=== Installing dependencies ==="
  if command -v dnf &>/dev/null; then
    sudo dnf install -y gcc make bison flex readline-devel zlib-devel \
      openssl-devel pkg-config git perf perl-FindBin perl-IPC-Run
  elif command -v apt-get &>/dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq build-essential bison flex libreadline-dev \
      zlib1g-dev libssl-dev pkg-config git "linux-tools-$(uname -r)" 2>/dev/null \
      || sudo apt-get install -y -qq linux-tools-generic
  fi
  sudo sysctl -w kernel.perf_event_paranoid=1
fi

if [ ! -d /opt/FlameGraph ]; then
  sudo git clone --depth 1 https://github.com/brendangregg/FlameGraph.git /opt/FlameGraph
fi
export PATH="/opt/FlameGraph:$PG_INSTALL/bin:$PATH"

# ── Phase 1: Build PostgreSQL + pg_stat_statements ──

echo "=== Building PostgreSQL ==="
cd "$PG_SRC"
./configure --prefix="$PG_INSTALL" --enable-debug CFLAGS="-O2 -g -fno-omit-frame-pointer" --without-icu
make clean -s 2>/dev/null || true
make -j"$(nproc)" -s
make install -s

echo "=== Building pg_stat_statements ==="
cd "$PG_SRC/contrib/pg_stat_statements"
make -s
make install -s

export LD_LIBRARY_PATH="$PG_INSTALL/lib"

# ── Phase 2: Init cluster ──

echo "=== Initializing data directory ==="
rm -rf "$PG_DATA"
initdb -D "$PG_DATA" --no-locale -E UTF8 -A trust

cat >> "$PG_DATA/postgresql.conf" <<CONF
listen_addresses = ''
unix_socket_directories = '/tmp'
fsync = off
full_page_writes = off
autovacuum = off
CONF

# ── Phase 3a: Baseline (no pg_stat_statements) ──

echo "=== Baseline run (without pg_stat_statements) ==="
pg_ctl -D "$PG_DATA" -l /tmp/pg.log start -w

createdb -h /tmp bench
pgbench -i -s "$PGBENCH_SCALE" -h /tmp bench 2>/dev/null

pgbench -S -c 1 -T "$BENCH_DURATION" -h /tmp bench > /tmp/pgbench_baseline.out 2>&1
grep 'tps.*without' /tmp/pgbench_baseline.out | tee "$RESULTS/baseline_tps.txt"

pg_ctl -D "$PG_DATA" stop -w

# ── Phase 3b: With pg_stat_statements + profiling ──

echo "=== PGSS run (with pg_stat_statements + perf) ==="
echo "shared_preload_libraries = 'pg_stat_statements'" >> "$PG_DATA/postgresql.conf"

pg_ctl -D "$PG_DATA" -l /tmp/pg.log start -w

psql -h /tmp bench -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"

pgbench -S -c 1 -T "$BENCH_DURATION" -h /tmp bench > /tmp/pgbench_pgss.out 2>&1 &
PGBENCH_PID=$!

sleep 5

BACKEND_PID=$(psql -h /tmp bench -Atc \
  "SELECT pid FROM pg_stat_activity WHERE application_name = 'pgbench' AND pid <> pg_backend_pid() LIMIT 1")

if [ -z "$BACKEND_PID" ]; then
  echo "ERROR: could not find pgbench backend PID"
  kill $PGBENCH_PID 2>/dev/null
  exit 1
fi

echo "Profiling backend PID $BACKEND_PID for ${PERF_DURATION}s ..."

perf stat -p "$BACKEND_PID" -o "$RESULTS/pgss_perf_stat.txt" -- sleep "$PERF_DURATION" &
PERF_STAT_PID=$!

perf record -g -p "$BACKEND_PID" -F "$PERF_FREQ" -o /tmp/perf.data -- sleep "$PERF_DURATION"

wait $PERF_STAT_PID
wait $PGBENCH_PID || true

grep 'tps.*without' /tmp/pgbench_pgss.out | tee "$RESULTS/pgss_tps.txt"

pg_ctl -D "$PG_DATA" stop -w

# ── Phase 4: Generate flamegraph ──

echo "=== Generating flamegraph ==="
perf script -i /tmp/perf.data \
  | stackcollapse-perf.pl \
  | flamegraph.pl --title "pg_stat_statements overhead (pgbench -S -c1)" \
  > "$RESULTS/pgss_flamegraph.svg"

# ── Summary ──

echo ""
echo "========================================"
echo "  Results in $RESULTS/"
echo "========================================"
echo "Baseline: $(cat "$RESULTS/baseline_tps.txt")"
echo "With PGSS: $(cat "$RESULTS/pgss_tps.txt")"
echo ""
cat "$RESULTS/pgss_perf_stat.txt"
echo ""
echo "Flamegraph: $RESULTS/pgss_flamegraph.svg"
