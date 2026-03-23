# pg_stat_statements Spinlock Overhead Profiling

## Context

A patch adding `calls_aborted` to pg_stat_statements was submitted to pgsql-hackers (2025-08-12). Andres Freund responded that the module's spinlock-protected section has become too expensive, with ~185 instructions including floating-point divisions (Welford's variance), and the overhead is measurable even on single-threaded read-only pgbench.

The goal is to produce concrete profiling data (flamegraphs + instruction counts) to quantify and visualize this overhead, feeding a 5-minute lightning talk.

## What We're Building

### Docker Environment

A Dockerfile based on Debian containing build tools for PostgreSQL, `perf` (linux-perf), and Brendan Gregg's FlameGraph scripts. The PostgreSQL source tree is mounted from the host so code can be edited on macOS and rebuilt inside the container.

The container runs with `--privileged` for `perf` to access hardware performance counters.

Directory structure:

```
pgss-bench/
  Dockerfile
  docker-compose.yml
  bench.sh
```

### bench.sh

Four phases, fully idempotent (wipes on every run):

Phase 1 -- Build PostgreSQL from source with `-O2 -g` (optimized + debug symbols). Build and install `contrib/pg_stat_statements`. Uses `make -j$(nproc)`.

Phase 2 -- Wipe data directory, `initdb`, configure `shared_preload_libraries = 'pg_stat_statements'`, start server, `CREATE EXTENSION`, `pgbench -i`.

Phase 3 -- Run `pgbench -S -c 1 -T 120` (single client, read-only, 120 seconds). During the run, capture `perf record -g -p <backend_pid> -F 99` for 30 seconds and `perf stat -p <backend_pid>` for 30 seconds. Backend PID from `pg_stat_activity`.

Phase 4 -- Generate flamegraph SVG via `stackcollapse-perf.pl | flamegraph.pl`. Copy outputs to `results/` mounted to host.

### Comparative Baseline

The script runs pgbench twice:

Run 1 -- Without pg_stat_statements (no `shared_preload_libraries`). Captures TPS only.

Run 2 -- With pg_stat_statements loaded. Captures TPS + `perf record` flamegraph + `perf stat` instruction counts.

Output in `results/`:

```
results/
  baseline_tps.txt
  pgss_tps.txt
  pgss_flamegraph.svg
  pgss_perf_stat.txt
```

## The Hot Path (lines 1417-1517 of pg_stat_statements.c)

The spinlock-protected section executes on every query and includes:

- Welford's online variance computation with a floating-point division (`/ entry->counters.calls[kind]`)
- min/max time comparisons
- 12 block counter increments (shared/local/temp, hit/read/dirtied/written)
- 6 time conversions via `INSTR_TIME_GET_MILLISEC`
- WAL counters (records, fpi, bytes, buffers_full)
- JIT counters (8 fields with conditional checks)
- Parallel worker counters
- Plan cache counters

All while other backends spin-wait on `entry->mutex`.

## Lightning Talk Structure (5 min)

Act 1 (~1 min) -- The patch. `calls_aborted` counter for tracking cancelled queries. Small, clean, tests pass.

Act 2 (~1 min) -- The rejection. Andres Freund's quote: "I think it's pretty insane to do things like variance computation while holding a spinlock, for every friggin query execution."

Act 3 (~2 min) -- The measurement. Baseline vs pgss TPS numbers. Flamegraph zoomed into `pgss_store`. `perf stat` instruction count. The audience sees for themselves.

Act 4 (~1 min) -- What could be done. Possible improvements: accumulate in a local struct and memcpy under lock, move variance outside the lock, per-backend buffering with periodic flush.

## Explicit Non-Goals

- No OpenTelemetry (wrong granularity -- microseconds vs nanoseconds)
- No code changes to pg_stat_statements (measurement only)
- No multi-client benchmarks (isolate CPU cost, not contention)
- No custom instrumentation inside the spinlock (would distort measurement)
