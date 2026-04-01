# pg_stat_statements Spinlock Overhead: Findings

## Background

A `calls_aborted` patch was submitted to pgsql-hackers (2025-08-12). Andres Freund responded that pg_stat_statements has accumulated too much overhead in its spinlock-protected section (~185 instructions with floating-point divisions), measurable even on single-threaded read-only pgbench. This document captures profiling results that quantify and visualize the overhead.

Mailing list threads:
- Original patch: https://www.postgresql.org/message-id/CAHUgstAuVpiSr1yRXtCR1mT5U9kvkur6P%2BkCs1M0dp1c_mDMUQ%40mail.gmail.com
- Andres's response: https://www.postgresql.org/message-id/btsjlfnqge3y6yypkwe7yvhv2tcopt6pug7gigz6xaha2iemkw%40lflv3psi7xoz
- Follow-up: https://www.postgresql.org/message-id/91EB8C15-5A15-4B07-A7CE-6133FB9948AC%40gmail.com

## Test Setup

Single-client profiling and flamegraph: AWS EC2 t3.micro (x86_64, Amazon Linux 2023, GCC 11.5.0)
Contention scaling and mixed workload: AWS EC2 c6i.2xlarge (8 vCPUs, non-burstable)
Build: PostgreSQL 19devel, `-O2 -g -fno-omit-frame-pointer`, `--without-icu`
Workload: `pgbench -S` (SELECT-only) and custom mixed script (10 query types)
Profiling: `perf record -g -F 99` for 30s, `perf stat` for 30s, `objdump` disassembly, FlameGraph SVG generation
Config: `fsync=off`, `full_page_writes=off`, `autovacuum=off` (isolate CPU overhead only)

Note on data provenance: the TPS numbers in the "Results" section below are from the t3.micro EC2 session. The committed result files in `pgss-bench/results/` (showing 55,877 / 49,099 TPS) are from an earlier Docker run on a different host. The hardware counters in `pgss-bench/results/pgss_perf_stat_ec2.txt` are from the t3.micro run.

## How the Sampling Works

The profiling uses Linux `perf`, which is completely external to PostgreSQL -- no code changes or instrumentation needed.

During the pgbench run, we query `pg_stat_activity` to find the backend PID serving the pgbench connection. Then `perf record -g -p <PID> -F 99` tells the kernel to set up a timer interrupt firing 99 times per second on that process. On each interrupt, the kernel captures the current instruction pointer and walks the call stack by following frame pointers up through each function's stack frame. PostgreSQL is unaware this is happening -- it's a kernel-level interrupt, transparent to the profiled process.

Two compile flags make the stacks readable. `-g` embeds a symbol table so perf can translate memory addresses into function names like `pgss_store`. `-fno-omit-frame-pointer` ensures each function's stack frame contains a pointer to its caller's frame, allowing the kernel to walk from the current function all the way up to `main`. Without frame pointers (the GCC default at `-O2`), the stack traces are broken and show `[unknown]` frames.

Over 30 seconds at 99 Hz, we capture ~2,400 stack snapshots. `perf script` dumps these as text, `stackcollapse-perf.pl` merges identical stacks and counts them, and `flamegraph.pl` renders the SVG where each bar's width represents the proportion of samples in which that function appeared. If `pgss_store` shows up in 0.88% of samples, it consumed roughly 0.88% of CPU time.

`perf stat` runs separately and reads hardware performance counters (cycles, instructions, branches, branch-misses) directly from the CPU's Performance Monitoring Unit, giving exact counts rather than statistical estimates. Note: hardware PMU counters are only available on EC2 instance types that expose them to the guest VM. The t3.micro exposed counters; the c6i.2xlarge did not (`<not supported>` for all hardware counters despite setting `perf_event_paranoid=1`).

## Flamegraph

![pg_stat_statements overhead flamegraph](pgss_flamegraph_ec2_annotated.svg)

The annotated flamegraph recolors pgss-specific frames: red for `pgss_store` (the spinlock section), blue for `clock_gettime` (timing calls), orange for hook dispatch functions, and muted green for wrapper functions like `pgss_ExecutorRun` that contain normal query execution. Callout labels highlight the three key areas of overhead. The clean (unannotated) version is at `pgss_flamegraph_ec2.svg`.

### How to read pgss overhead in the flamegraph

A flamegraph does not directly show "overhead" -- it shows where CPU time is spent. To identify pgss overhead, you need to know which functions belong to pgss and would disappear if the extension were unloaded. This is not obvious because `pgss_ExecutorRun` wraps `standard_ExecutorRun`, so all normal query execution (btree walks, buffer management, heap access) appears visually inside the pgss frame. The flamegraph shows `pgss_ExecutorRun` occupying ~23.5% of CPU inclusively, but that's almost entirely real query work happening inside the wrapper.

The actual pgss overhead is visible as thin slivers alongside the normal execution: `pgss_store` (0.88%), `clock_gettime` under pgss hooks (0.81%), and hook dispatch self-time (~0.5%). These add up to ~2.2% of CPU. You can only see this as overhead if you compare it to a baseline run without pgss, which is what the TPS comparison provides. The flamegraph shows WHERE the overhead is; the TPS comparison shows HOW MUCH it costs.

Source SVG: `pgss-bench/results/pgss_flamegraph_ec2_frameptr.svg`

## Results

### TPS comparison (t3.micro, single client)

```
Without pg_stat_statements: 41,370 TPS (24.2 μs/query)
With pg_stat_statements:    33,363 TPS (30.0 μs/query)
```

Three ways to express this overhead:

```
Throughput loss:   19.4%  — (41370 - 33363) / 41370 — fewer queries per second
Latency increase:  24.0%  — (30.0 - 24.2) / 24.2 — each query takes longer
CPU overhead:       2.2%  — from flamegraph sampling — fraction of CPU in pgss functions
Added time:         5.8 μs — per query — the fixed cost pgss adds
```

The gap between 2.2% CPU overhead and 19.4% throughput loss is because each SELECT takes only 24μs. Adding 5.8μs is a small fraction of total CPU time but a large fraction of each query's runtime.

### Hardware counters (perf stat, 30s, t3.micro with pgss enabled)

From `pgss-bench/results/pgss_perf_stat_ec2.txt`:

```
33.8 billion cycles           (1.865 GHz)
46.2 billion instructions     (1.37 insn per cycle)
9.1 billion branches          (499 M/sec)
98.4 million branch-misses    (1.09%)
```

### Overhead breakdown from flamegraph

`pgss_store` (the spinlock-protected section, lines 1417-1517 of pg_stat_statements.c) consumes 0.88% of total CPU. The top consumers inside it are `LWLockRelease`, self-time in `pgss_store` (covering Welford's variance division and 20+ counter increments), `LWLockAttemptLock`, `__memcmp_evex_movbe` (hash key comparison), and `hash_bytes` (computing the hash).

`clock_gettime` calls under pgss hooks consume 0.81% of total CPU. pg_stat_statements times both planning and execution phases, requiring at least 4 clock reads per query through the vDSO. This costs almost as much as the spinlock section itself.

Hook dispatch self-time (`pgss_ExecutorStart/End/Finish`, `pgss_planner`, `pgss_post_parse_analyze`) adds roughly another 0.5%.

## The Hot Path (lines 1417-1517)

What happens under the `entry->mutex` spinlock for every query:

1. Welford's online variance: floating-point division by `calls[kind]` (line 1441)
2. Mean/min/max time updates with conditional branches
3. 12 block counter increments (shared/local/temp hit/read/dirtied/written)
4. 6 time conversions via `INSTR_TIME_GET_MILLISEC` (shared/local/temp read/write time)
5. WAL counters: records, fpi, bytes, buffers_full
6. JIT counters: 8 fields with conditional checks on each
7. Parallel worker counters
8. Plan cache counters (generic vs custom)
9. Usage tracking via `USAGE_EXEC`

## Instruction-Level Analysis

Disassembling the compiled `pgss_store` function with `objdump` and counting instructions between `SpinLockAcquire` (`lock xchg`) and `SpinLockRelease` (`movb $0x0`) gives 233 instructions in the spinlock-protected section, with 16 `divsd` (double-precision floating-point division) instructions. Andres estimated ~185 instructions; the actual compiled output is roughly 1.3x worse. The gap likely comes from register spills, calling convention setup, and the compiler generating separate divisions for each timing category rather than sharing a divisor.

The 16 divisions come from Welford's variance computation across multiple timing categories. Each `divsd` on modern x86 has a latency of 13-20 cycles and cannot be pipelined when there are data dependencies. That's 200-320 cycles of division alone inside the spinlock, during which every other backend wanting to update pgss must spin-wait.

`perf annotate` confirmed `pgss_store` is being sampled (though only 4 samples fell inside the function during our 30s window at 99 Hz, too few for per-instruction breakdown). A longer profiling window or higher sampling frequency would improve granularity.

## Contention Scaling

To test Andres's claim that pgss overhead makes it "practically unusable for any busy workload", we ran pgbench at increasing concurrency on a c6i.2xlarge (8 vCPUs, non-burstable) with and without pgss.

### SELECT-only workload (`pgbench -S`)

```
clients  baseline_tps    pgss_tps        overhead
1        20,077          19,433          3.2%
2        40,628          38,679          4.8%
4        63,714          60,973          4.3%
8        151,052         141,126         6.6%
16       139,531         130,559         6.4%
32       133,165         121,773         8.6%
64       132,067         123,745         6.3%
```

The overhead grows roughly 2.7x from `-c 1` to its peak at `-c 32` (3.2% to 8.6%), confirming that contention amplifies the per-query cost. At `-c 8`, that's ~10,000 lost TPS. The peak at `-c 32` then drops at `-c 64` because with only 8 vCPUs, extreme oversubscription shifts the bottleneck from spinlock contention to OS scheduling. On a machine with 32+ physical cores, the contention curve would likely continue climbing since all backends could run and hit the spinlock simultaneously.

Note: the `-c 1` overhead on the c6i (3.2%) is lower than on the t3.micro (19.4%) because the t3.micro was using burst CPU credits, inflating its baseline TPS to 41k. The c6i at sustained clock speed shows 20k TPS baseline. The per-query overhead (~6μs) is consistent across both machines; the percentage differs because the baseline query time differs.

The contention data for `-c 1` through `-c 8` is generated by `bench.sh`. The `-c 16,32,64` data points were gathered manually on the same c6i instance.

### Mixed workload (10 query types)

We also tested with a custom pgbench script (`pgss-bench/mixed_workload.sql`) containing PK lookups, range scans, joins, aggregates, updates, inserts, and subqueries to approximate a more realistic workload.

```
clients  baseline_tps  pgss_tps  overhead
1        137           134       2.3%
2        214           209       2.3%
4        288           289       noise
8        346           343       1.1%
```

The overhead disappears into measurement noise. Each mixed query takes ~7.3ms on average, so the fixed ~6μs pgss overhead is only 0.08% of query time. This tells us that pgss overhead is a fixed per-query cost, not a percentage. It becomes significant for sub-millisecond OLTP workloads (simple index lookups, key-value access patterns) where the per-query overhead is a meaningful fraction of query time, but is invisible when queries take multiple milliseconds.

### What this means

Andres's critique is specifically about high-throughput OLTP workloads where queries are sub-millisecond. A production system doing 100k+ simple lookups per second loses thousands of TPS to pgss bookkeeping. The contention scaling from 3.2% to 8.6% on an 8-vCPU machine suggests the problem gets worse on larger machines with 32+ cores where more backends contend simultaneously. For typical mixed workloads with slower queries, pgss overhead is negligible in practice.

## Possible Improvements (not implemented, for future work)

### Move variance computation outside the spinlock

Accumulate `total_time` and `total_time_squared` under the spinlock (two additions), compute variance on read in `pg_stat_statements()` view function. This removes the floating-point division from the hot path. Trade-off: slightly different numerical stability vs Welford, but for query timing statistics the precision loss would be negligible.

### Per-backend buffering with periodic flush

Each backend accumulates counter deltas in process-local memory and flushes to shared memory every N queries or on a timer. This eliminates the spinlock entirely for the common case. Trade-off: statistics become slightly stale, and the flush logic adds complexity. Similar to how `pgstat_report_stat()` works for other stats.

### Split the Counters struct for cache efficiency

The current `Counters` struct packs everything together. Splitting hot fields (calls, total_time) from cold fields (JIT counters, WAL stats, parallel worker counts) into separate cache lines would reduce the amount of memory touched under the spinlock.

### Reduce timing calls

Instead of timing planning and execution separately, consider a single timing bracket around the entire query lifecycle. This would halve the `clock_gettime` overhead. Trade-off: loses the ability to distinguish planning time from execution time.

### Use atomic operations instead of a spinlock

For simple counter increments (calls, rows, block counters), `__sync_fetch_and_add` or C11 atomics would work without any lock. Only the variance computation needs mutual exclusion (and only if kept as Welford). This would allow concurrent updates from multiple backends without contention.

## Reproducing

```bash
git clone --branch pgss-slow-part https://github.com/benoittgt/postgres.git
cd postgres/pgss-bench
chmod +x bench.sh
./bench.sh
# Results in pgss-bench/results/
```

The script handles dependency installation (Debian/Ubuntu via apt, Amazon Linux via dnf), builds PostgreSQL from source with frame pointers, runs both benchmark passes (baseline and pgss), generates the flamegraph SVG, disassembles `pgss_store`, runs `perf annotate`, and runs the contention scaling test at `-c 1,2,4,8` with a mixed workload variant.

## Lightning Talk Outline (5 min)

Act 1 (~1 min): Show the `calls_aborted` patch. Small, clean, passes tests. Submitted to pgsql-hackers.

Act 2 (~1 min): Andres Freund's quote: "I think it's pretty insane to do things like variance computation while holding a spinlock, for every friggin query execution. The spinlock'ed section is ~185 instructions for me, with plenty high-latency instructions like divisions."

Act 3 (~2 min): Show the flamegraph, explain which slivers are pgss-specific overhead. Then the TPS comparison: 5.8μs added per query, 19.4% throughput loss on the t3.micro. Reveal: `objdump` shows 233 instructions in the spinlocked section (more than Andres's estimate), 16 floating-point divisions. The `clock_gettime` overhead is a surprise finding: nearly as expensive as the spinlock section itself.

Act 4 (~1 min): Show the contention scaling table: overhead grows from 3.2% to 8.6% on 8 vCPUs. Then show the mixed workload result: overhead vanishes when queries take milliseconds instead of microseconds. The punchline: pgss's problem is specifically about high-throughput fast-query workloads, and it gets worse with more cores. What could be done: per-backend buffering, moving variance to read-time, atomics for simple counters.
