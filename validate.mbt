///|
/// Validate without allocating a diagnostic array. Invalid JSON numbers and
/// exhausted traversal budgets are errors, not ordinary validation failures.
pub fn Schema::valid(
  self : Schema,
  value : Json,
  max_depth~ : Int32 = 128,
) -> Bool raise {
  check_instance(value, 0, max_depth)
  evaluate(self.plan, self.plan.nodes[0], value, "", None, 0, max_depth)
}

///|
/// Collect assertion failures. Paths are RFC 6901 JSON Pointers; failed
/// speculative anyOf/oneOf/not/if branches do not leak their diagnostics.
pub fn Schema::faults(
  self : Schema,
  value : Json,
  max_depth~ : Int32 = 128,
) -> Array[Fault] raise {
  check_instance(value, 0, max_depth)
  let failures : Array[Fault] = []
  ignore(
    evaluate(
      self.plan,
      self.plan.nodes[0],
      value,
      "",
      Some(failures),
      0,
      max_depth,
    ),
  )
  failures
}

///|
// Validate without constructing an escaped JSON Pointer at every successful
// array element and object field. Build it only for a numeric error.
fn check_instance(value : Json, depth : Int32, limit : Int32) -> Unit raise EvaluationError {
  let segments : Array[String] = []
  check_instance_tree(value, segments, depth, limit)
}

///|
fn check_instance_tree(
  value : Json,
  segments : Array[String],
  depth : Int32,
  limit : Int32,
) -> Unit raise EvaluationError {
  if limit < 1 || depth > limit {
    raise EvaluationError::DepthLimit(limit)
  }
  match value {
    Number(number, repr~) => {
      if (repr is Some(_) && ExactNumber::of_json(value) is None) ||
        (repr is None && (number.is_inf() || number.is_nan())) {
        let mut path = ""
        for segment in segments { path = pointer_step(path, segment) }
        raise InvalidNumber(path~)
      }
    }
    Object(fields) =>
      for name, child in fields {
        segments.push(name)
        check_instance_tree(child, segments, depth + 1, limit)
        ignore(segments.pop())
      }
    Array(values) =>
      for index, child in values {
        segments.push(index.to_string())
        check_instance_tree(child, segments, depth + 1, limit)
        ignore(segments.pop())
      }
    _ => ()
  }
}

///|
fn numeric_value(
  value : Json,
  path : String,
) -> ExactNumber raise EvaluationError {
  match ExactNumber::of_json(value) {
    Some(number) => number
    None => raise InvalidNumber(path~)
  }
}

///|
fn number_has_repr(value : Json) -> Bool {
  match value {
    Number(_, repr~) => repr is Some(_)
    _ => false
  }
}

///|
// JSON Schema equality compares numbers mathematically, including nested ones.
// Inputs have already passed numeric/depth checks before this recursion.
fn schema_equal(left : Json, right : Json) -> Bool raise NumericError {
  match (left, right) {
    (Number(a, ..), Number(b, ..)) => {
      if !number_has_repr(left) && !number_has_repr(right) {
        a == b
      } else {
        match (ExactNumber::of_json(left), ExactNumber::of_json(right)) {
          (Some(a), Some(b)) => a.equal(b)
          _ => false
        }
      }
    }
    (Object(a), Object(b)) => {
      if a.length() != b.length() {
        return false
      }
      for key, value in a {
        match b.get(key) {
          Some(other) => if !schema_equal(value, other) { return false }
          None => return false
        }
      }
      true
    }
    (Array(a), Array(b)) => {
      if a.length() != b.length() {
        return false
      }
      for index, value in a {
        if !schema_equal(value, b[index]) {
          return false
        }
      }
      true
    }
    _ => left == right
  }
}

///|
fn fail(
  failures : Array[Fault]?,
  instance_path : String,
  schema_path : String,
  keyword : String,
  message : String,
) -> Bool {
  if failures is Some(entries) {
    entries.push({
      instance_path,
      schema_path,
      schema_uri: None,
      keyword,
      message,
    })
  }
  false
}

///|
fn matches_type(kind : ValueType, value : Json, path : String) -> Bool raise {
  match (kind, value) {
    (NullType, Null)
    | (BooleanType, True)
    | (BooleanType, False)
    | (NumberType, Number(_, ..))
    | (StringType, String(_))
    | (ArrayType, Array(_))
    | (ObjectType, Object(_)) => true
    (IntegerType, Number(_, ..)) => numeric_value(value, path).is_integer()
    _ => false
  }
}

///|
fn evaluate_rule(
  program : Program,
  rule : Rule,
  value : Json,
  path : String,
  failures : Array[Fault]?,
  depth : Int32,
  limit : Int32,
  scope~ : Array[Int32],
  evaluated~ : EvaluationMarks?,
) -> Bool raise {
  match rule {
    Types(types, location) => {
      for kind in types {
        if matches_type(kind, value, path) {
          return true
        }
      }
      fail(
        failures, path, location, "type", "instance has none of the permitted types",
      )
    }
    Constant(expected, location) =>
      schema_equal(value, expected) ||
      fail(
        failures, path, location, "const", "instance differs from the constant",
      )
    Enumeration(values, location) =>
      values.any(expected => schema_equal(value, expected)) ||
      fail(
        failures, path, location, "enum", "instance is not an enumerated value",
      )
    Lower(bound, exclusive, location) => {
      guard value is Number(_, ..) else { return true }
      let ordering = numeric_value(value, path).compare(bound)
      (if exclusive { ordering > 0 } else { ordering >= 0 }) ||
      fail(
        failures,
        path,
        location,
        if exclusive {
          "exclusiveMinimum"
        } else {
          "minimum"
        },
        "number is below its lower bound",
      )
    }
    Upper(bound, exclusive, location) => {
      guard value is Number(_, ..) else { return true }
      let ordering = numeric_value(value, path).compare(bound)
      (if exclusive { ordering < 0 } else { ordering <= 0 }) ||
      fail(
        failures,
        path,
        location,
        if exclusive {
          "exclusiveMaximum"
        } else {
          "maximum"
        },
        "number exceeds its upper bound",
      )
    }
    Multiple(divisor, location) => {
      guard value is Number(_, ..) else { return true }
      numeric_value(value, path).multiple_of(divisor) ||
      fail(
        failures, path, location, "multipleOf", "number is not an exact multiple",
      )
    }
    StringLength(minimum, maximum, location) => {
      guard value is String(text) else { return true }
      let length = text.char_length()
      let mut valid = true
      if minimum is Some(bound) && length < bound {
        valid = fail(
          failures,
          path,
          pointer_step(location, "minLength"),
          "minLength",
          "string has too few Unicode code points",
        )
        if failures is None {
          return false
        }
      }
      if maximum is Some(bound) && length > bound {
        valid = fail(
          failures,
          path,
          pointer_step(location, "maxLength"),
          "maxLength",
          "string has too many Unicode code points",
        )
      }
      valid
    }
    Pattern(pattern, location) => {
      guard value is String(text) else { return true }
      pattern_matches(pattern, text) ||
      fail(
        failures, path, location, "pattern", "string does not match the pattern",
      )
    }
    _ =>
      evaluate_applicator(
        program, rule, value, path, failures, depth, limit, scope, evaluated,
      )
  }
}
