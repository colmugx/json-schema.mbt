// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

// Public regression tests for the count-keyword boundary phase: no Int32
// ceiling, no Double truncation, exact comparisons against huge bounds, and
// a typed resource error (`NumericBudget`) distinct from invalid numeric
// representations.

///|
test "count: bounds beyond Int32 compile and enforce exactly" {
  // One past the old Int32 ceiling is an ordinary bound now.
  let just_over = @json-schema.Schema::compile(
    @json-schema.parse("{\"minItems\":2147483648}"),
  )
  assert_false(just_over.valid(@json-schema.parse("[1,2]")))
  let faults = just_over.faults(@json-schema.parse("[1,2]"))
  assert_eq(faults.length(), 1)
  assert_eq(faults[0].keyword, "minItems")
  assert_eq(faults[0].schema_path, "/minItems")
  assert_eq(faults[0].instance_path, "")
  // The old ceiling itself keeps working in both directions.
  let ceiling = @json-schema.Schema::compile(
    @json-schema.parse("{\"minItems\":2147483647,\"maxItems\":2147483647}"),
  )
  assert_false(ceiling.valid(@json-schema.parse("[]")))
  assert_true(ceiling.faults(@json-schema.parse("[]"))[0].keyword == "minItems")
  let over = @json-schema.Schema::compile(
    @json-schema.parse("{\"maxItems\":2147483648}"),
  )
  assert_true(over.valid(@json-schema.parse("[1,2,3]")))
  // Exponent spellings stay exact and decide by digit width.
  let huge = @json-schema.Schema::compile(
    @json-schema.parse("{\"minItems\":1e30,\"maxItems\":1e40}"),
  )
  let three = @json-schema.parse("[1,2,3]")
  assert_false(huge.valid(three))
  let huge_faults = huge.faults(three)
  assert_eq(huge_faults.length(), 1)
  assert_eq(huge_faults[0].keyword, "minItems")
  // 1e100000 is the last supported exponent on both sides of the comparison.
  let max_edge = @json-schema.Schema::compile(
    @json-schema.parse("{\"maxItems\":1e100000}"),
  )
  assert_true(max_edge.valid(@json-schema.parse("[1]")))
  let min_edge = @json-schema.Schema::compile(
    @json-schema.parse("{\"minItems\":1e100000}"),
  )
  assert_false(min_edge.valid(@json-schema.parse("[1]")))
}

///|
test "count: string, object and contains keywords beyond Int32" {
  let long = @json-schema.Schema::compile(
    @json-schema.parse("{\"type\":\"string\",\"minLength\":3e9}"),
  )
  assert_false(long.valid(@json-schema.parse("\"abc\"")))
  assert_eq(long.faults(@json-schema.parse("\"abc\""))[0].keyword, "minLength")
  let capped = @json-schema.Schema::compile(
    @json-schema.parse("{\"type\":\"string\",\"maxLength\":2147483648}"),
  )
  assert_true(capped.valid(@json-schema.parse("\"abc\"")))
  let props = @json-schema.Schema::compile(
    @json-schema.parse("{\"minProperties\":2147483648}"),
  )
  assert_false(props.valid(@json-schema.parse("{\"a\":1}")))
  assert_eq(
    props.faults(@json-schema.parse("{\"a\":1}"))[0].keyword,
    "minProperties",
  )
  let roomy = @json-schema.Schema::compile(
    @json-schema.parse("{\"maxProperties\":1e30}"),
  )
  assert_true(roomy.valid(@json-schema.parse("{\"a\":1}")))
  let contains = @json-schema.Schema::compile(
    @json-schema.parse(
      "{\"contains\":{\"type\":\"number\"},\"minContains\":3e9}",
    ),
  )
  assert_false(contains.valid(@json-schema.parse("[1,\"a\"]")))
  assert_eq(
    contains.faults(@json-schema.parse("[1,\"a\"]"))[0].keyword,
    "contains",
  )
  let generous = @json-schema.Schema::compile(
    @json-schema.parse(
      "{\"contains\":{\"type\":\"number\"},\"maxContains\":3e9}",
    ),
  )
  assert_true(generous.valid(@json-schema.parse("[1,2,\"a\"]")))
  // The default minContains of 1 is unchanged.
  let default_min = @json-schema.Schema::compile(
    @json-schema.parse("{\"contains\":{\"type\":\"number\"}}"),
  )
  assert_false(default_min.valid(@json-schema.parse("[\"a\"]")))
  assert_true(default_min.valid(@json-schema.parse("[\"a\",2]")))
}

///|
test "count: equivalent spellings agree without Double truncation" {
  // Every spelling of the first integer past Int32 compiles and enforces.
  for
    spelling in [
      "2147483648", "2.147483648e9", "2147483648.0", "21474836480e-1",
    ] {
    let schema = @json-schema.Schema::compile(
      @json-schema.parse("{\"minItems\":" + spelling + "}"),
    )
    assert_false(schema.valid(@json-schema.parse("[1]")), msg=spelling)
    assert_true(
      schema.faults(@json-schema.parse("[1]"))[0].keyword == "minItems",
      msg=spelling,
    )
  }
  // Equal bounds written differently accept and reject the same instances.
  for spelling in ["3", "3.0", "3e0", "0.3e1", "30e-1"] {
    let schema = @json-schema.Schema::compile(
      @json-schema.parse(
        "{\"minItems\":" + spelling + ",\"maxItems\":" + spelling + "}",
      ),
    )
    assert_true(schema.valid(@json-schema.parse("[1,2,3]")), msg=spelling)
    assert_false(schema.valid(@json-schema.parse("[1,2]")), msg=spelling)
    assert_false(schema.valid(@json-schema.parse("[1,2,3,4]")), msg=spelling)
  }
  // Programmatically constructed doubles carry no literal; the finite value
  // is used exactly instead of being truncated into an Int.
  let constructed : Map[String, Json] = { "minItems": Json::number(3.0e9) }
  let schema = @json-schema.Schema::compile(Json::object(constructed))
  assert_false(schema.valid(@json-schema.parse("[1]")))
  assert_eq(schema.faults(@json-schema.parse("[1]"))[0].instance_path, "")
}

///|
test "count: huge fractional-scaled integer bounds stay exact" {
  // 1.5e100000 = 15 * 10^99999 is a nonnegative integer whose scale stays in
  // budget; the coefficient keeps every written digit.
  let schema = @json-schema.Schema::compile(
    @json-schema.parse("{\"minItems\":1.5e100000}"),
  )
  assert_false(schema.valid(@json-schema.parse("[1,2,3]")))
  // 0.1e100001 normalizes to 10^100000, inside the scale budget.
  let normalized = @json-schema.Schema::compile(
    @json-schema.parse("{\"maxItems\":0.1e100001}"),
  )
  assert_true(normalized.valid(@json-schema.parse("[1,2,3]")))
}

///|
test "count: invalid representations and resource budget are distinct errors" {
  // Fractional bound: keyword-level schema error.
  try
    @json-schema.Schema::compile(@json-schema.parse("{\"minItems\":1.5}"))
  catch {
    @json-schema.CompileError::InvalidKeyword(path~, reason~) => {
      assert_eq(path, "/minItems")
      assert_eq(reason, "expected a nonnegative integer")
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected InvalidKeyword for a fractional count")
  }
  // Negative bound: same classification.
  try
    @json-schema.Schema::compile(@json-schema.parse("{\"minItems\":-1}"))
  catch {
    @json-schema.CompileError::InvalidKeyword(path~, reason~) => {
      assert_eq(path, "/minItems")
      assert_eq(reason, "expected a nonnegative integer")
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected InvalidKeyword for a negative count")
  }
  // A tiny fractional number is a valid number but never an integer count.
  try
    @json-schema.Schema::compile(@json-schema.parse("{\"minItems\":1e-400}"))
  catch {
    @json-schema.CompileError::InvalidKeyword(path~, reason~) => {
      assert_eq(path, "/minItems")
      assert_eq(reason, "expected a nonnegative integer")
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected InvalidKeyword for a fractional count")
  }
  // Not a number at all: malformed schema.
  try
    @json-schema.Schema::compile(@json-schema.parse("{\"minItems\":\"3\"}"))
  catch {
    @json-schema.CompileError::InvalidKeyword(path~, reason~) => {
      assert_eq(path, "/minItems")
      assert_eq(reason, "expected a finite JSON number")
    }
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected InvalidKeyword for a non-numeric count")
  }
  // Well-formed literals beyond the ±100000 exact-arithmetic scale budget
  // raise the typed resource error, distinct from every schema error above.
  try
    @json-schema.Schema::compile(@json-schema.parse("{\"minItems\":1e100001}"))
  catch {
    @json-schema.CompileError::NumericBudget(path~) =>
      assert_eq(path, "/minItems")
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected NumericBudget for an out-of-budget count")
  }
  try
    @json-schema.Schema::compile(
      @json-schema.parse("{\"maxLength\":1e-100001}"),
    )
  catch {
    @json-schema.CompileError::NumericBudget(path~) =>
      assert_eq(path, "/maxLength")
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected NumericBudget for an out-of-budget count")
  }
  // Constructed non-finite and inconsistent numbers keep the
  // invalid-representation classification.
  let nan : Map[String, Json] = Map::from_array([
    ("minItems", Json::number(0.0 / 0.0)),
  ])
  try @json-schema.Schema::compile(Json::object(nan)) catch {
    @json-schema.CompileError::InvalidKeyword(path~, ..) =>
      assert_eq(path, "/minItems")
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected InvalidKeyword for a NaN count")
  }
  let mismatch : Map[String, Json] = Map::from_array([
    ("minItems", Json::number(1, repr="2")),
  ])
  try @json-schema.Schema::compile(Json::object(mismatch)) catch {
    @json-schema.CompileError::InvalidKeyword(path~, ..) =>
      assert_eq(path, "/minItems")
    error => fail("unexpected error: \{Repr(error)}")
  } noraise {
    _ => fail("expected InvalidKeyword for an inconsistent count repr")
  }
  // The same split applies on the instance side: a malformed instance number
  // is an EvaluationError, never an ordinary false or a budget error.
  let schema = @json-schema.Schema::compile(@json-schema.parse("{}"))
  try {
    ignore(schema.valid(Json::number(1, repr="2")))
    fail("expected EvaluationError::InvalidNumber")
  } catch {
    @json-schema.EvaluationError::InvalidNumber(path~) => assert_eq(path, "")
    error => fail("unexpected error: \{Repr(error)}")
  }
}

///|
test "count: valid and empty faults agree on normal completion" {
  let schemas = [
    "{\"minItems\":1e30}", "{\"maxItems\":1e30}", "{\"minContains\":1e30,\"contains\":{\"type\":\"number\"}}",
    "{\"maxContains\":1e30,\"contains\":{\"type\":\"number\"}}", "{\"minLength\":1e30,\"type\":\"string\"}",
    "{\"maxLength\":1e30,\"type\":\"string\"}", "{\"minProperties\":1e30}", "{\"maxProperties\":1e30}",
  ]
  let instances = ["[]", "[1]", "[1,2,3]", "\"abc\"", "{}", "{\"a\":1}", "null"]
  for schema_text in schemas {
    let schema = @json-schema.Schema::compile(@json-schema.parse(schema_text))
    for instance_text in instances {
      let instance = @json-schema.parse(instance_text)
      assert_eq(
        schema.valid(instance),
        schema.faults(instance).is_empty(),
        msg=schema_text + " vs " + instance_text,
      )
    }
  }
}
