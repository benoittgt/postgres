#!/usr/bin/env python3
"""
Annotate the pg_stat_statements flamegraph SVG:
- Recolor pgss_store frames (spinlock hot path) in red
- Recolor clock_gettime frames in blue
- Recolor pgss hook dispatch frames in orange
- Add a legend and callout annotations
"""

import re
import sys

INPUT = "pgss-bench/results/pgss_flamegraph_ec2_frameptr.svg"
OUTPUT = "docs/plans/pgss_flamegraph_ec2_annotated.svg"

with open(INPUT) as f:
    svg = f.read()

# --- Recolor frames by function name ---

def recolor(svg, title_pattern, new_fill):
    """Find <g> blocks whose <title> matches pattern and replace rect fill."""
    pattern = re.compile(
        r'(<title>' + title_pattern + r'[^<]*</title>'
        r'<rect [^>]*?)fill="[^"]*"',
        re.DOTALL
    )
    return pattern.sub(r'\1fill="' + new_fill + '"', svg)

# pgss_store: the spinlock-protected section (bright red)
svg = recolor(svg, r'pgss_store', '#e03030')

# clock_gettime and __vdso_clock_gettime: timing overhead (blue)
svg = recolor(svg, r'clock_gettime', '#3070d0')
svg = recolor(svg, r'__vdso_clock_gettime', '#3070d0')

# pgss hook dispatch functions (orange)
for fn in ['pgss_ExecutorStart', 'pgss_ExecutorEnd', 'pgss_ExecutorFinish',
           'pgss_post_parse_analyze', 'pgss_planner']:
    svg = recolor(svg, fn, '#e09020')

# pgss_ExecutorRun: wrapper only (muted gray-green to de-emphasize)
svg = recolor(svg, r'pgss_ExecutorRun', '#90b090')

# LWLock functions under pgss (darker red for lock contention)
for fn in ['LWLockRelease', 'LWLockAttemptLock', 'LWLockAcquire']:
    svg = recolor(svg, fn, '#c04040')

# hash functions in pgss path (salmon)
for fn in ['hash_bytes_extended', 'hash_bytes ']:
    svg = recolor(svg, fn, '#d06050')

# --- Add annotations before closing </svg> ---

# Key coordinates from the SVG:
# pgss_store (0.72%):     x=105.7  y=421  w=8.5
# pgss_store (0.16%):     x=485.5  y=437  w=1.9
# clock_gettime (0.58%):  x=392.2  y=405  w=6.8
# clock_gettime (0.16%):  x=115.2  y=405  w=1.9
# pgss_ExecutorEnd:       x=104.6  y=437  w=9.6
# pgss_ExecutorStart:     x=418.4  y=453  w=42.0
# pgss_ExecutorRun:       x=135.2  y=437  w=277.1 (wrapper)
# pgss_planner:           x=645.2  y=421  w=301.5 (wrapper)

annotations = """
<!-- ═══════ ANNOTATIONS ═══════ -->
<g id="annotations" style="pointer-events: none;">

  <!-- Legend box -->
  <rect x="14" y="48" width="295" height="108" rx="4" ry="4"
        fill="white" fill-opacity="0.92" stroke="#999" stroke-width="0.8"/>
  <text x="24" y="66" font-family="Verdana" font-size="11" font-weight="bold"
        fill="#333">pg_stat_statements overhead legend</text>

  <rect x="24" y="74" width="14" height="10" fill="#e03030" rx="2" ry="2"/>
  <text x="44" y="83" font-family="Verdana" font-size="10" fill="#333">
    pgss_store — spinlock hot path (0.88% CPU)</text>

  <rect x="24" y="90" width="14" height="10" fill="#3070d0" rx="2" ry="2"/>
  <text x="44" y="99" font-family="Verdana" font-size="10" fill="#333">
    clock_gettime — timing overhead (0.81% CPU)</text>

  <rect x="24" y="106" width="14" height="10" fill="#e09020" rx="2" ry="2"/>
  <text x="44" y="115" font-family="Verdana" font-size="10" fill="#333">
    pgss hooks — dispatch self-time (~0.5% CPU)</text>

  <rect x="24" y="122" width="14" height="10" fill="#90b090" rx="2" ry="2"/>
  <text x="44" y="131" font-family="Verdana" font-size="10" fill="#333">
    pgss wrappers — no overhead (normal execution inside)</text>

  <text x="24" y="150" font-family="Verdana" font-size="10" font-style="italic"
        fill="#666">Total pgss-specific overhead: ~2.2% CPU → 19% TPS drop</text>

  <!-- Callout 1: pgss_store — placed upper-left, line goes up-left -->
  <line x1="110" y1="421" x2="40" y2="280" stroke="#e03030" stroke-width="1.5"
        stroke-dasharray="4,2"/>
  <rect x="5" y="230" width="235" height="50" rx="3" ry="3"
        fill="white" fill-opacity="0.92" stroke="#e03030" stroke-width="1"/>
  <text x="12" y="247" font-family="Verdana" font-size="9.5" fill="#c02020"
        font-weight="bold">pgss_store (spinlock section)</text>
  <text x="12" y="260" font-family="Verdana" font-size="9" fill="#555">
    Welford's variance division, 20+ counter</text>
  <text x="12" y="272" font-family="Verdana" font-size="9" fill="#555">
    updates, LWLock acquire/release</text>

  <!-- Callout 2: clock_gettime — placed upper-right, line goes up-right -->
  <line x1="395" y1="405" x2="480" y2="295" stroke="#3070d0" stroke-width="1.5"
        stroke-dasharray="4,2"/>
  <rect x="440" y="245" width="240" height="50" rx="3" ry="3"
        fill="white" fill-opacity="0.92" stroke="#3070d0" stroke-width="1"/>
  <text x="447" y="262" font-family="Verdana" font-size="9.5" fill="#2060b0"
        font-weight="bold">clock_gettime (timing calls)</text>
  <text x="447" y="275" font-family="Verdana" font-size="9" fill="#555">
    4 vDSO reads per query (plan start/end,</text>
  <text x="447" y="287" font-family="Verdana" font-size="9" fill="#555">
    exec start/end). Almost = spinlock cost.</text>

  <!-- Callout 3: pgss_ExecutorRun wrapper — far right -->
  <line x1="274" y1="437" x2="700" y2="370" stroke="#666" stroke-width="1"
        stroke-dasharray="3,3"/>
  <rect x="700" y="345" width="285" height="38" rx="3" ry="3"
        fill="white" fill-opacity="0.92" stroke="#666" stroke-width="0.8"/>
  <text x="707" y="362" font-family="Verdana" font-size="9.5" fill="#555"
        font-style="italic">pgss_ExecutorRun wraps standard_ExecutorRun</text>
  <text x="707" y="375" font-family="Verdana" font-size="9" fill="#888">
    23.5% inclusive, but no overhead — just a wrapper.</text>

</g>
"""

svg = svg.replace("</svg>", annotations + "\n</svg>")

with open(OUTPUT, "w") as f:
    f.write(svg)

print(f"Annotated flamegraph written to {OUTPUT}")
