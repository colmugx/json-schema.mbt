///|
fn exact(text : String) -> @json-schema.ExactNumber {
  @json-schema.ExactNumber::from_literal(text).unwrap()
}

///|
test "numeric: aligned coefficients preserve arbitrary decimal digits" {
  assert_true(exact("0.3").multiple_of(exact("0.1")))
  assert_true(exact("-0.3").multiple_of(exact("0.1")))
  assert_false(exact("1.00000000000000000000000000001").multiple_of(exact("1")))
  assert_false(exact("1000000000.5").multiple_of(exact("1")))
  assert_true(
    exact("900719925474099300").multiple_of(exact("9007199254740993")),
  )
  assert_false(
    exact("900719925474099301").multiple_of(exact("9007199254740993")),
  )
  assert_eq(exact("9007199254740993").compare(exact("9007199254740992")), 1)
  assert_true(exact("1e400").equal(exact("10e399")))
  assert_true(exact("1e-400").equal(exact("0.1e-399")))
  assert_true(exact("-0").equal(exact("0.000")))
  assert_true(exact("3.0e1").is_integer())
  assert_false(exact("1e-400").is_integer())
}

///|
test "numeric: invalid literals and inconsistent repr are not silently ignored" {
  for text in ["", "01", "NaN", "Infinity", "+1", "1e", "1.", "1e100001"] {
    assert_true(@json-schema.ExactNumber::from_literal(text) is None, msg=text)
  }
  assert_true(
    @json-schema.ExactNumber::of_json(Json::number(1, repr="2")) is None,
  )
  assert_true(
    @json-schema.ExactNumber::of_json(Json::number(1, repr="bad")) is None,
  )
  assert_true(
    @json-schema.ExactNumber::of_json(Json::number(1.0 / 0.0)) is None,
  )
  assert_true(
    @json-schema.ExactNumber::of_json(Json::number(0.0 / 0.0)) is None,
  )
  let invalid = @json-schema.ExactNumber::from_double(0.0 / 0.0)
  let raised = try {
    ignore(invalid.compare(exact("1")))
    false
  } catch {
    @json-schema.NumericError::InvalidNumber => true
  }
  assert_true(raised)
  assert_true(
    @json-schema.ExactNumber::from_double(0.3).multiple_of(exact("0.1")),
  )
}

///|
test "numeric: const enum and uniqueItems use nested exact equality" {
  let constant = @json-schema.Schema::compile(
    @json-schema.parse("{\"const\":{\"n\":[9007199254740993]}}"),
  )
  assert_true(
    constant.valid(@json-schema.parse("{\"n\":[9007199254740993.0]}")),
  )
  assert_false(constant.valid(@json-schema.parse("{\"n\":[9007199254740992]}")))
  let enumeration = @json-schema.Schema::compile(
    @json-schema.parse("{\"enum\":[9007199254740993]}"),
  )
  assert_false(enumeration.valid(@json-schema.parse("9007199254740992")))
  let unique = @json-schema.Schema::compile(
    @json-schema.parse("{\"uniqueItems\":true}"),
  )
  assert_true(
    unique.valid(@json-schema.parse("[9007199254740992,9007199254740993]")),
  )
  assert_false(
    unique.valid(@json-schema.parse("[9007199254740993,9007199254740993.0]")),
  )
}

///|
test "numeric: constructed-double fast paths preserve exact contract" {
  let one = @json-schema.ExactNumber::from_double(1.0)
  let neg_zero = @json-schema.ExactNumber::from_double(-0.0)
  assert_true(one.equal(@json-schema.ExactNumber::from_double(1.0)))
  assert_false(one.equal(@json-schema.ExactNumber::from_double(2.0)))
  assert_eq(one.compare(@json-schema.ExactNumber::from_double(2.0)), -1)
  assert_eq(one.sign(), 1)
  assert_eq(neg_zero.sign(), 0)
  assert_true(neg_zero.is_integer())
  assert_false(@json-schema.ExactNumber::from_double(0.125).is_integer())
  assert_true(@json-schema.ExactNumber::from_double(9007199254740992.0).is_integer())
  assert_false(one.equal(exact("1.0000000000000001")))
  assert_true(one.equal(exact("1.00")))
}

///|
test "uniqueItems: large primitive arrays hash without changing exact semantics" {
  let schema = @json-schema.Schema::compile(@json-schema.parse("{\"uniqueItems\":true}"))
  let numbers : Array[Json] = []
  for i in 0..<128 { numbers.push(Json::number(i.to_double())) }
  assert_true(schema.valid(Json::array(numbers)))
  numbers[127] = Json::number(-0.0)
  assert_false(schema.valid(Json::array(numbers)))
  assert_eq(schema.faults(Json::array(numbers))[0].instance_path, "/127")
  let strings : Array[Json] = []
  for i in 0..<128 { strings.push(Json::string(i.to_string())) }
  assert_true(schema.valid(Json::array(strings)))
  strings[127] = Json::string("0")
  assert_eq(schema.faults(Json::array(strings))[0].instance_path, "/127")
  assert_false(schema.valid(@json-schema.parse("[1,1.0]")))
  assert_true(schema.valid(@json-schema.parse("[9007199254740992,9007199254740993]")))
  assert_false(schema.valid(@json-schema.parse("[{\"n\":1},{\"n\":1.0}]")))
}


///|
test "numeric: zero-bound comparison handles exact exponents and nonfinite" {
  for zero in ["0", "-0", "0e400", "0.0000000000000000"] {
    let z = exact(zero)
    assert_eq(@json-schema.ExactNumber::from_double(-2.5).compare(z), -1)
    assert_eq(@json-schema.ExactNumber::from_double(0.0).compare(z), 0)
    assert_eq(@json-schema.ExactNumber::from_double(-0.0).compare(z), 0)
    assert_eq(@json-schema.ExactNumber::from_double(2.5).compare(z), 1)
    assert_eq(z.compare(@json-schema.ExactNumber::from_double(-2.5)), 1)
    assert_eq(z.compare(@json-schema.ExactNumber::from_double(0.0)), 0)
    assert_eq(z.compare(@json-schema.ExactNumber::from_double(2.5)), -1)
  }
  assert_eq(@json-schema.ExactNumber::from_double(2.5).compare(exact("1e400")), -1)
  let nonfinite = @json-schema.ExactNumber::from_double(1.0 / 0.0)
  let raised = try {
    ignore(nonfinite.compare(exact("0")))
    false
  } catch {
    @json-schema.NumericError::InvalidNumber => true
  }
  assert_true(raised)
}

///|
test "uniqueItems: unchecked prior array read stays inside proven bounds" {
  let unique = @json-schema.Schema::compile(@json-schema.parse("{\"uniqueItems\":true}"))
  assert_true(unique.valid(@json-schema.parse("[]")))
  assert_true(unique.valid(@json-schema.parse("[[],[1],[1,2]]")))
  assert_false(unique.valid(@json-schema.parse("[[],[1],[]]")))
  assert_false(unique.valid(@json-schema.parse("[{\"a\":[1]},{\"a\":[1.0]}]")))
  assert_true(unique.valid(@json-schema.parse("[[1],[1,2]]")))
  let constant = @json-schema.Schema::compile(
    @json-schema.parse("{\"const\":[{\"a\":[1,2]},[3]]}"),
  )
  assert_true(constant.valid(@json-schema.parse("[{\"a\":[1.0,2]},[3]]")))
  assert_false(constant.valid(@json-schema.parse("[{\"a\":[1]},[3]]")))
}
