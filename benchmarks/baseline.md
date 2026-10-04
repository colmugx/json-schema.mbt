# Local performance baselines

These are local evidence, not cross-library comparisons or a claim to be the
fastest validator. Historical native-only measurements below stay native-only.

## Current milestone: two real execution environments

A full v2 campaign completed **110 measurements**: 11 scenarios × 5 fresh processes
× 2 runtimes. Native executes via `moon run --target native --release`; moonx
executes the timing loop and validator inside its Wasm sandbox, not a native child.
The runner rotates scenario/runtime order, warms five batches and measures at least
200 ms per process. Both environments passed their workload preflights, counters,
paired case-ID checks and failure probes. Standard coverage remains **962/1301**;
optional coverage is **535/1036**, separate from that denominator.

Environment: local Darwin arm64; Moon/moonrun `0.1.20260920` (`914d7da`),
moonc `0.10.14+7d59c7ec9`. Wasm uses the `moonx-default` script profile;
no unverified release-profile equivalence is claimed. Native uses separate
library/runner packages; the Wasm entry bundles the same checkout source with
namespace/private-helper renaming. Both include per-batch clock sampling cost.

| Scenario | Unit | Native median ns/op | moonx-Wasm median ns/op |
|---|---|---:|---:|
| Official compile | schema | 3132.56 | 8164.76 |
| Official boolean validation | instance | 395.04 | 1284.82 |
| Official compile + validation | instance | 1200.64 | 3467.63 |
| Official diagnostics | instance | 443.96 | 1393.05 |
| Tool arguments | instance | 1408.99 | 6514.39 |
| Structured result | instance | 1405.91 | 5144.50 |
| 1024-item array | instance | 414450.22 | 1468216.24 |
| Unique array workload | instance | 934653.62 | 3746306.33 |
| Composition branches | instance | 610.10 | 2697.71 |
| Exact decimals | instance | 1530.19 | 5448.03 |
| Pattern profile | instance | 873.42 | 4171.96 |

`benchmark-results/report.md` gives separate min/max tables; detailed JSON/logs
and generated/original source evidence remain in the artifact. Timing eligibility
is **962 instances / 244 schemas**, the same in both environments. Neither
startup nor source compilation is inside the workload clocks. Do not interpret
this ratio as isolated Wasmtime overhead: backend optimization, package layout,
clock host calls and sandbox costs differ. Portable execution is not constant
performance across devices, and native release is a configured baseline, not
proof of the optimal possible binary for every CPU.

## Historical native-only milestone: local static references

A subsequent full campaign added local `$ref`/`$defs` support and preserved the
same pinned corpus and compiler version. All 55 native release measurements
completed; no check/build/harness failures occurred. Current standard coverage
is **962/1301** (0 mismatches, 337 unsupported, 2 rejected); optional coverage
is **535/1036**, reported separately. Timing eligibility is now **962 instances /
244 schemas**, with 588 expected-valid and 374 expected-invalid instances.

| Scenario | Unit | Median ns/op | Min | Max |
|---|---|---:|---:|---:|
| Official compile | schema | 3008.76 | 2985.57 | 3056.17 |
| Official boolean validation | instance | 383.11 | 377.89 | 394.27 |
| Official compile + validation | instance | 1156.36 | 1152.76 | 1197.15 |
| Official diagnostics | instance | 426.58 | 424.22 | 438.29 |
| Tool arguments | instance | 1389.96 | 1374.67 | 1422.14 |
| Structured result | instance | 1393.77 | 1347.67 | 1447.85 |

These are a new correctness-verified workload, **not a same-corpus speed
comparison** with the first baseline below. The compile plan now indexes local
reference targets; no claim about the fastest implementation follows from these
numbers. Detailed JSON and counters remain in `benchmark-results/`.

## First baseline: environment and corpus

- Local Darwin arm64, kernel 27.0.0; exact CPU model not recorded.
- Moon `0.1.20260920` (`914d7da`); moonc `v0.10.14+7d59c7ec9`.
- Native release, command: `moonx benchmarks/run-campaign.mbtx`.
- Five serial fresh processes per scenario; five warmup batches and at least
  200 ms measured time per process. Scenario order rotates across repetitions.
- Official revision: `5b0ee1613e45fcc2bddac00e07c19cd49b00d8a8`.
- Full standard conformance: **921/1301**, 0 mismatches, 372 unsupported and
  8 rejected. Optional: 525/1036, recorded separately; no proposal cases.
- Official timing eligibility: **921 instances / 230 schemas**, including
  572 expected-valid and 349 expected-invalid instances. The other 380 standard
  cases remain in conformance but are excluded from timing.
- Local development tree, not a tagged independent release. The surrounding
  Git HEAD is not an independent library revision. CI artifacts after moving
  this module to its own repository will provide the actual library commit.

## Results

Values below are **median [min, max] across five process averages**, in ns/op,
rounded for readability. Raw JSON preserves counters and unrounded values.

| Scenario | Unit | Median ns/op | Min | Max |
|---|---|---:|---:|---:|
| Official compile | schema | 2090.75 | 2072.67 | 2141.73 |
| Official boolean validation | instance | 362.69 | 359.72 | 363.29 |
| Official compile + validation | instance | 895.99 | 884.74 | 899.90 |
| Official diagnostics | instance | 403.94 | 399.58 | 406.57 |
| Tool arguments | instance | 1366.58 | 1350.84 | 1375.39 |
| Structured result | instance | 1354.36 | 1329.78 | 1372.66 |
| 1024-item array | instance | 393805.69 | 391956.21 | 398014.25 |
| Unique array workload | instance | 887967.55 | 885032.81 | 895806.36 |
| Composition branches | instance | 585.81 | 576.92 | 591.10 |
| Exact decimals | instance | 1468.63 | 1459.35 | 1484.42 |
| Pattern profile | instance | 825.71 | 817.98 | 833.88 |

Startup, parsing/loading, preflight and JSON reporting are excluded. Timed loops
include operation/acceptance counting. Compile uses an optimizer sink; cached
validation includes numeric/depth preflight. Compile+validate recompiles once
per group, so it is **not** compilation per instance. Diagnostics includes
failure-array construction. Synthetic scenarios mix their declared valid and
invalid examples; `unique128` includes a distinct 128-item array and a short
duplicate rejection, not 128-item work on every operation.

## Interpretation

The official average reflects only the current correctness-verified subset;
it does not measure references, dynamic scopes or unevaluated semantics. As
coverage grows, that subset changes. Preserve eligible case IDs and compare a
fixed common subset before interpreting a throughput change as an optimization.

Large arrays and uniqueness already cost substantially more than small tool
objects. This evidence supports targeted optimization work rather than a single
misleading "JSON Schema speed" number. No hard speed gate is imposed on noisy
hosted runners. Do not infer individual request latency percentiles from these
aggregate process measurements.

The campaign retained original corpus/license, manifest, per-case conformance,
55 measurement JSON files and command/stdout/stderr/status evidence under
`benchmark-results/`. These generated artifacts are ignored locally and uploaded
by the independent workflow. See [the reproduction guide](README.md).
