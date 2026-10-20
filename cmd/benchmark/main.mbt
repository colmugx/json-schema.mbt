///|
struct Options {
  manifest : String
  conformance : String
  output : String
  scenario : String
  smoke : Bool
}

///|
fn options(args : Array[String]) -> Options raise {
  let mut manifest = "benchmark-results/manifest.json"
  let mut conformance = "benchmark-results/conformance.json"
  let mut output = "benchmark-results/measurement.json"
  let mut scenario = "official_validate"
  let mut smoke = false
  let mut index = 1
  while index < args.length() {
    let key = args[index]
    if key == "--smoke" {
      smoke = true
      index += 1
      continue
    }
    guard index + 1 < args.length() else { fail("missing value: " + key) }
    let value = args[index + 1]
    match key {
      "--manifest" => manifest = value
      "--conformance" => conformance = value
      "--output" => output = value
      "--scenario" => scenario = value
      _ => fail("unknown option: " + key)
    }
    index += 2
  }
  { manifest, conformance, output, scenario, smoke, }
}

///|
fn validate_workload(workload : Workload) -> Int32 raise {
  let mut expected_true = 0
  for group in workload.groups {
    for instance in group.instances {
      guard group.compiled.valid(instance.value) == instance.expected &&
        group.compiled.faults(instance.value).is_empty() == instance.expected else {
        fail("incorrect workload: " + instance.id)
      }
      if instance.expected {
        expected_true += 1
      }
    }
  }
  expected_true
}

///|
// Registry reuse is a distinct compilation path: independently validate every
// official timing-eligible case before treating its compile cost as evidence.
fn validate_registry_workload(workload : Workload) -> Unit raise {
  for group in workload.groups {
    let registry = group.registry.unwrap()
    let compiled = registry.compile(group.document)
    for instance in group.instances {
      guard compiled.valid(instance.value) == instance.expected &&
        compiled.faults(instance.value).is_empty() == instance.expected else {
        fail("registry compiled plan disagrees with official corpus: " + instance.id)
      }
    }
  }
}

///|
fn batch(
  workload : Workload,
  mode : String,
  sink : @bench.Bench,
) -> (Int32, Int32) raise {
  // Measure the one-time cost explicitly instead of concealing registry
  // construction outside the reusable-compile timing window.
  if mode == "registry_prepare" {
    sink.keep(@schema.SchemaRegistry::new(workload.groups[0].resources))
    return (1, 1)
  }
  let mut operations = 0
  let mut accepted = 0
  for group in workload.groups {
    if mode == "compile_registry" {
      let registry = group.registry.unwrap()
      sink.keep(registry.compile(group.document))
      operations += 1
      accepted += 1
      continue
    }
    if mode == "compile" || mode == "compile_registry" {
      sink.keep(
        @schema.Schema::compile(group.document, resources=group.resources),
      )
      operations += 1
      accepted += 1
      continue
    }
    let compiled = if mode == "compile_validate" {
      @schema.Schema::compile(group.document, resources=group.resources)
    } else {
      group.compiled
    }
    for instance in group.instances {
      let result = if mode == "diagnostics" {
        compiled.faults(instance.value).is_empty()
      } else {
        compiled.valid(instance.value)
      }
      if result {
        accepted += 1
      }
      operations += 1
    }
  }
  (operations, accepted)
}

///|
fn execute(options : Options) -> Unit raise {
  let from_official = options.scenario.has_prefix("official_")
  let workload = if from_official {
    official(options.manifest, options.conformance)
  } else {
    synthetic(options.scenario)
  }
  let mode = match options.scenario {
    "official_compile" => "compile"
    "official_compile_registry" => "compile_registry"
    "official_registry_prepare" => "registry_prepare"
    "official_compile_validate" => "compile_validate"
    "official_diagnostics" => "diagnostics"
    "official_validate"
    | "tool_arguments"
    | "structured_result"
    | "array1024"
    | "unique128"
    | "branches"
    | "exact_decimal"
    | "pattern" => "validate"
    _ => fail("unknown scenario: " + options.scenario)
  }
  let true_count = validate_workload(workload)
  if mode == "compile_registry" {
    validate_registry_workload(workload)
  }
  let expected_operations = if mode == "registry_prepare" {
    1
  } else if mode == "compile" || mode == "compile_registry" {
    workload.groups.length()
  } else {
    workload.ids.length()
  }
  let expected_accepted = if mode == "registry_prepare" {
    1
  } else if mode == "compile" || mode == "compile_registry" {
    workload.groups.length()
  } else {
    true_count
  }
  guard expected_operations > 0 else { fail("empty workload") }
  let sink = @bench.Bench()
  let warmup_batches = if options.smoke { 1 } else { 5 }
  for _ in 0..<warmup_batches {
    let (operations, accepted) = batch(workload, mode, sink)
    guard operations == expected_operations && accepted == expected_accepted else {
      fail("warmup correctness counter failed")
    }
  }
  let target_us = if options.smoke { 20000.0 } else { 200000.0 }
  let mut iterations = 0
  let mut total_operations = 0L
  let mut total_accepted = 0L
  let start = @bench.monotonic_clock_start()
  let mut elapsed_us = 0.0
  while elapsed_us < target_us {
    let (operations, accepted) = batch(workload, mode, sink)
    total_operations += operations.to_int64()
    total_accepted += accepted.to_int64()
    iterations += 1
    elapsed_us = @bench.monotonic_clock_end(start)
  }
  guard total_operations ==
    expected_operations.to_int64() * iterations.to_int64() &&
    total_accepted == expected_accepted.to_int64() * iterations.to_int64() &&
    elapsed_us > 0 else {
    fail("measurement correctness counter failed")
  }
  let manifest = object(@json.parse(@fs.read_file_to_string(options.manifest)))
  let (runtime, target, build_mode) = execution_identity()
  let result : Json = {
    "version": 2,
    "runtime": runtime,
    "scenario": options.scenario,
    "revision": text(manifest, "revision"),
    "target": target,
    "build_mode": build_mode,
    "smoke": options.smoke,
    "mode": mode,
    "operation_unit": if mode == "registry_prepare" {
      "registry"
    } else if mode == "compile" || mode == "compile_registry" {
      "schema"
    } else {
      "instance"
    },
    "operations": total_operations.to_double(),
    "accepted": total_accepted.to_double(),
    "iterations": iterations,
    "operations_per_batch": expected_operations,
    "accepted_per_batch": expected_accepted,
    "elapsed_us": elapsed_us,
    "ns_per_operation": elapsed_us * 1000 / total_operations.to_double(),
    "operations_per_second": total_operations.to_double() * 1000000 / elapsed_us,
    "warmup_batches": warmup_batches,
    "eligible_case_ids": Json(workload.ids),
    "excluded_cases": workload.excluded,
    "eligible_schemas": workload.groups.length(),
    "timing_contract": "parse/startup/report excluded; loop and counter bookkeeping included; compile mode uses optimizer sink",
  }
  @fs.write_string_to_file(options.output, result.stringify(indent=2))
  println(
    "\{options.scenario}: \{total_operations} operations in \{elapsed_us} us",
  )
}

///|
fn main {
  let code = try {
    execute(options(@env.args()))
    0
  } catch {
    error => {
      println("BENCHMARK HARNESS ERROR: \{error}")
      2
    }
  }
  @sys.exit(code)
}
