#!/usr/bin/env python3
"""Same-runner, alternating baseline/candidate benchmark for one execution runtime.

Every invocation runs on a dedicated runner, never concurrently with the other
runtime's measurement loop. Only the official benchmark's internal clocks
measure operations; shell startup, conformance, preparation and report are
outside those clocks. All pairing is performed before comparing any results.
"""
import json
import math
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import traceback

SCENARIOS = (
    "official_compile", "official_validate", "official_compile_validate",
    "official_diagnostics", "tool_arguments", "structured_result", "array1024",
    "unique128", "branches", "exact_decimal", "pattern",
)
RUNTIMES = {
    "native": ("native", "release"),
    "moonx-wasm": ("wasm", "moonx-default"),
}
TIMEOUT = 180
CONFORMANCE_TIMEOUT = 300


def command(cwd, logdir, name, argv, timeout=TIMEOUT, accepted=(0,)):
    logdir.mkdir(parents=True, exist_ok=True)
    target = logdir / (name + ".log")
    with target.open("w", encoding="utf-8") as stream:
        stream.write("cwd=" + str(cwd) + "\ncommand=" + repr(argv) + "\n\n")
        stream.flush()
        try:
            result = subprocess.run(
                argv, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                timeout=timeout, check=False,
            )
            code = result.returncode
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(f"{name} timed out after {timeout}s; see {target}") from exc
    if code not in accepted:
        tail = target.read_text(encoding="utf-8", errors="replace")[-6000:]
        raise RuntimeError(f"{name}: exit {code}; log {target}\n{tail}")
    return code


def read_json(path):
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def validate_conformance(root, label, evidence):
    source = root / "benchmark-results"
    report = read_json(source / "conformance.json")
    manifest = read_json(source / "manifest.json")
    require(report["version"] == 1 and not report["filtered"], f"{label}: invalid conformance report")
    require(report["revision"] == manifest["revision"], f"{label}: fixture revision mismatch")
    standard = report["counts"]["standard"]
    require(standard["total"] == manifest["totals"]["standard"], f"{label}: standard denominator mismatch")
    require(standard["passed"] == standard["total"], f"{label}: incomplete standard conformance {standard}")
    for name in ("conformance.json", "manifest.json", "suite-source.json"):
        shutil.copy2(source / name, evidence / (label + "-" + name))
    return {
        "suite_revision": report["revision"],
        "standard": standard,
        "optional": report["counts"]["optional"],
        "manifest": manifest,
    }


def setup_checkout(root, label, runtime, evidence):
    logs = evidence / "logs" / label
    command(root, logs, "revision", ["git", "rev-parse", "HEAD"])
    command(root, logs, "status", ["git", "status", "--porcelain"])
    command(root, logs, "dependencies", ["moon", "update"], timeout=240)
    command(root, logs, "fetch-suite", ["moonx", "benchmarks/fetch-suite.mbtx"], timeout=300)
    command(root, logs, "prepare-suite", ["moonx", "benchmarks/prepare-suite.mbtx"])
    command(root, logs, "native-check", ["moon", "check", "--target", "native", "--deny-warn", "--output-json"], timeout=240)
    command(root, logs, "unit-tests", ["moon", "test", "--target", "native", "--deny-warn", "--output-json"], timeout=300)
    command(root, logs, "build-conformance", ["moon", "build", "cmd/conformance", "--target", "native", "--release", "--deny-warn", "--output-json"], timeout=240)
    if runtime == "native":
        command(root, logs, "build-benchmark", ["moon", "build", "cmd/benchmark", "--target", "native", "--release", "--deny-warn", "--output-json"], timeout=240)
    else:
        command(root, logs, "wasm-check", ["moon", "check", "--target", "wasm", "--deny-warn", "--output-json"], timeout=240)
        command(root, logs, "prepare-moonx", ["moonx", "benchmarks/prepare-moonx.mbtx"])
        require((root / "benchmark-results/measurement.mbtx").exists(), f"{label}: wasm entry missing")
    # The eligible official workload is determined by this full native conformance
    # run. No native performance measurements are made on the moonx runner.
    result = root / "benchmark-results/conformance.json"
    if result.exists():
        result.unlink()
    command(root, logs, "conformance", [
        "moon", "run", "cmd/conformance", "--target", "native", "--release",
        "--deny-warn", "--output-json", "--",
        "--manifest", "benchmark-results/manifest.json",
        "--output", "benchmark-results/conformance.json",
    ], timeout=CONFORMANCE_TIMEOUT, accepted=(0, 1))
    return validate_conformance(root, label, evidence)


def check_sample(sample, runtime, smoke):
    target, profile = RUNTIMES[runtime]
    require(sample["version"] == 2 and sample["runtime"] == runtime, "runtime identity mismatch")
    require(sample["target"] == target and sample["build_mode"] == profile, "build profile mismatch")
    require(sample["smoke"] is smoke, "smoke/full configuration mismatch")
    require(sample["warmup_batches"] == (1 if smoke else 5), "warmup mismatch")
    require(sample["elapsed_us"] >= (20000 if smoke else 200000), "measurement duration too short")
    require(sample["operations"] > 0 and sample["iterations"] > 0, "missing operations")
    require(sample["operations"] == sample["iterations"] * sample["operations_per_batch"], "operation count mismatch")
    require(sample["accepted"] == sample["iterations"] * sample["accepted_per_batch"], "acceptance count mismatch")
    ns = sample["ns_per_operation"]
    require(math.isfinite(ns) and ns > 0, "invalid cost")
    require(math.isclose(ns, sample["elapsed_us"] * 1000 / sample["operations"], rel_tol=1e-9), "cost accounting mismatch")
    require(sample["eligible_case_ids"] and sample["eligible_schemas"] > 0, "eligible work missing")
    return ns


def measure(root, evidence, runtime, label, scenario, repetition, smoke):
    outfile = evidence / "samples" / label / (scenario + "-" + str(repetition) + ".json")
    outfile.parent.mkdir(parents=True, exist_ok=True)
    argv = [
        "--manifest", "benchmark-results/manifest.json",
        "--conformance", "benchmark-results/conformance.json",
        "--output", str(outfile),
        "--scenario", scenario,
    ]
    if smoke:
        argv.append("--smoke")
    if runtime == "native":
        launcher = ["moon", "run", "cmd/benchmark", "--target", "native", "--release",
                    "--deny-warn", "--output-json", "--"]
    else:
        launcher = ["moonx", "benchmark-results/measurement.mbtx"]
    command(root, evidence / "logs" / label, f"{runtime}-{scenario}-{repetition}",
            launcher + argv, timeout=240)
    require(outfile.exists(), f"{label}: missing {scenario}-{repetition}")
    sample = read_json(outfile)
    cost = check_sample(sample, runtime, smoke)
    require(sample["scenario"] == scenario, "incorrect scenario output")
    return sample, cost


def equivalent_workload(left, right):
    keys = (
        "revision", "scenario", "mode", "operation_unit", "operations_per_batch",
        "accepted_per_batch", "eligible_schemas", "eligible_case_ids",
        "excluded_cases", "timing_contract",
    )
    for key in keys:
        require(left[key] == right[key], f"workloads differ in {key}: {left['scenario']}")


def emit_report(evidence, runtime, base_sha, candidate_sha, smoke, records, standard):
    markdown = [
        f"# Same-runner paired performance — {runtime}",
        "",
        f"- Baseline: \`{base_sha}\`",
        f"- Candidate: \`{candidate_sha}\`",
        "- Runner: one isolated GitHub-hosted Ubuntu runner for this runtime; no other runtime benchmark executes in this job",
        f"- Standard conformance: **{standard['passed']}/{standard['total']}** for both revisions",
        f"- Repetitions: **{1 if smoke else 5}**; within each round baseline/candidate order alternates",
        "- Measured costs exclude checkout, builds, suite preparation, process startup, and reporting",
        "",
        "| Scenario | Baseline median ns/op | Candidate median ns/op | Median paired change | Pair range |",
        "|---|---:|---:|---:|---:|",
    ]
    output = {"version": 1, "runtime": runtime, "baseline": base_sha, "candidate": candidate_sha,
              "smoke": smoke, "standard_conformance": standard, "scenarios": {}}
    for scenario in SCENARIOS:
        pairs = records[scenario]
        baseline = statistics.median(p["baseline"] for p in pairs)
        candidate = statistics.median(p["candidate"] for p in pairs)
        ratios = [100 * (p["candidate"] / p["baseline"] - 1) for p in pairs]
        median_change = statistics.median(ratios)
        markdown.append(
            f"| {scenario} | {baseline:.2f} | {candidate:.2f} | "
            f"{median_change:+.2f}% | {min(ratios):+.2f}% to {max(ratios):+.2f}% |"
        )
        output["scenarios"][scenario] = {
            "baseline_median_ns": baseline, "candidate_median_ns": candidate,
            "paired_median_pct": median_change, "pair_pct": ratios, "pairs": pairs,
        }
    markdown += [
        "", "**Interpretation:** negative change = candidate is faster. Paired ratios",
        "compare adjacent processes on one runner, not independent hosted runners.",
        "Order alternates to limit time drift; thermal/cache effects and runner noise",
        "still exist. These are workload averages, not per-request latency percentiles.",
        "No arbitrary speed threshold determines CI success.",
    ]
    if smoke:
        markdown.append("**Smoke measurements are exploratory, not reliable speed claims.**")
    rendered = "\n".join(markdown) + "\n"
    (evidence / "comparison.md").write_text(rendered, encoding="utf-8")
    (evidence / "comparison.json").write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    print(rendered, flush=True)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as stream:
            stream.write(rendered)


def main():
    runtime = os.environ.get("BENCH_RUNTIME", "")
    require(runtime in RUNTIMES, "BENCH_RUNTIME must be native or moonx-wasm")
    smoke = os.environ.get("BENCH_SMOKE", "false").lower() == "true"
    candidate = Path.cwd().resolve()
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=candidate, text=True).strip()
    base_sha = os.environ.get("BENCH_BASE_SHA", "")
    if not base_sha or set(base_sha) == {"0"}:
        base_sha = subprocess.check_output(["git", "rev-parse", "HEAD^"], cwd=candidate, text=True).strip()
    base_sha = subprocess.check_output(["git", "rev-parse", base_sha + "^{commit}"],
                                       cwd=candidate, text=True).strip()
    require(base_sha != sha, "baseline and candidate commits are identical")
    evidence = candidate / "benchmark-results" / "paired"
    evidence.mkdir(parents=True, exist_ok=True)
    baseline = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / ("schema-baseline-" + runtime)
    command(candidate, evidence / "logs" / "setup", "worktree",
            ["git", "worktree", "add", "--detach", str(baseline), base_sha], timeout=120)
    (evidence / "provenance.json").write_text(json.dumps({
        "baseline": base_sha, "candidate": sha, "runtime": runtime,
        "runner_name": os.environ.get("RUNNER_NAME"),
        "runner_os": os.environ.get("RUNNER_OS"),
        "runner_arch": os.environ.get("RUNNER_ARCH"),
        "smoke": smoke,
    }, indent=2) + "\n", encoding="utf-8")
    # Preparation and correctness checks happen in both checkouts before clocks.
    base_check = setup_checkout(baseline, "baseline", runtime, evidence)
    head_check = setup_checkout(candidate, "candidate", runtime, evidence)
    require(base_check["suite_revision"] == head_check["suite_revision"], "suite revision changed")
    require(base_check["manifest"] == head_check["manifest"], "official corpus/workload manifest changed")
    require(base_check["standard"] == head_check["standard"], "standard conformance changed")
    repetitions = 1 if smoke else 5
    records = {scenario: [] for scenario in SCENARIOS}
    for i in range(repetitions):
        for offset in range(len(SCENARIOS)):
            scenario = SCENARIOS[(offset + i) % len(SCENARIOS)]
            sequence = ("baseline", "candidate") if (i + offset) % 2 == 0 else ("candidate", "baseline")
            costs = {}
            samples = {}
            for label in sequence:
                root = baseline if label == "baseline" else candidate
                sample, costs[label] = measure(root, evidence, runtime, label, scenario, i + 1, smoke)
                samples[label] = sample
                print(f"{runtime} {scenario} repetition {i+1} {label}: {costs[label]:.2f} ns/op", flush=True)
            equivalent_workload(samples["baseline"], samples["candidate"])
            records[scenario].append({"repetition": i + 1, "order": list(sequence),
                                      "baseline": costs["baseline"], "candidate": costs["candidate"]})
    emit_report(evidence, runtime, base_sha, sha, smoke, records, head_check["standard"])
    if runtime == "native":
        # Additional intra-candidate paired comparison. The legacy main checkout
        # cannot know this new API, so compare two compilation modes within the
        # candidate checkout, with identical documents and fresh process clocks.
        registry_pairs = []
        for iteration in range(1 if smoke else 5):
            order = (
                ("official_compile", "official_compile_registry")
                if iteration % 2 == 0 else
                ("official_compile_registry", "official_compile")
            )
            values = {}
            samples = {}
            for scenario in order:
                sample, ns = measure(candidate, evidence, runtime, "registry-" + scenario,
                                     scenario, iteration + 1, smoke)
                values[scenario] = ns
                samples[scenario] = sample
            legacy, cached = samples["official_compile"], samples["official_compile_registry"]
            for key in ("eligible_case_ids", "operations_per_batch", "accepted_per_batch",
                        "eligible_schemas", "excluded_cases", "revision"):
                require(legacy[key] == cached[key], f"registry comparison differs in {key}")
            registry_pairs.append({
                "order": list(order),
                "legacy_ns": values["official_compile"],
                "registry_ns": values["official_compile_registry"],
                "ratio_pct": 100 * (values["official_compile_registry"] /
                                    values["official_compile"] - 1),
            })
        median = statistics.median(item["ratio_pct"] for item in registry_pairs)
        startup_costs = []
        for iteration in range(1 if smoke else 5):
            sample, ns = measure(candidate, evidence, runtime, "registry-preparation",
                                 "official_registry_prepare", iteration + 1, smoke)
            require(sample["mode"] == "registry_prepare", "incorrect registry cost measurement")
            startup_costs.append(ns)
        startup_ns = statistics.median(startup_costs)
        saved_ns = statistics.median(p["legacy_ns"] - p["registry_ns"] for p in registry_pairs)
        break_even = math.ceil(startup_ns / saved_ns) if saved_ns > 0 else None
        output = {"version": 2, "repetitions": len(registry_pairs),
                  "cached_registry_preparation_excluded": True,
                  "median_paired_pct": median, "pairs": registry_pairs,
                  "median_snapshot_preparation_ns": startup_ns,
                  "snapshot_preparation_samples_ns": startup_costs,
                  "median_saved_per_compilation_ns": saved_ns,
                  "estimated_break_even_compilations": break_even}
        (evidence / "registry-comparison.json").write_text(
            json.dumps(output, indent=2) + "\n", encoding="utf-8")
        report = ("\n## Registry reused compilation vs legacy compilation\n\n"
                  f"Native same-runner median paired delta: {median:+.2f}% "
                  "(negative means reuse is faster). "
                  "Each candidate revision runs both implementations in "
                  "alternating order. Registry creation is timed independently "
                  "of reuse.\n"
                  f"Median one-time snapshot preparation: {startup_ns:,.0f} ns; "
                  f"median saving per schema: {saved_ns:,.0f} ns; "
                  f"estimated break-even: {break_even} schema compilations "
                  "(single shared resource corpus, steady-state workloads).\n")
        with (evidence / "comparison.md").open("a", encoding="utf-8") as out:
            out.write(report)
        print(report, flush=True)
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with open(summary, "a", encoding="utf-8") as out:
                out.write(report)



if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
