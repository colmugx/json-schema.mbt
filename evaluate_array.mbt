///|
fn evaluate_array(
  program : Program,
  plan : ArrayPlan,
  value : Json,
  path : String,
  failures : Array[Fault]?,
  depth : Int32,
  limit : Int32,
  scope : Array[Int32],
  evaluated : EvaluationMarks?,
) -> Bool raise {
  guard value is Array(values) else { return true }
  let mut valid = true
  // Only homogeneous arrays of constructed primitive values can be hashed
  // without losing the exact decimal and recursive JSON equality contract.
  let mut unique_kind = if plan.unique && values.length() >= 16 { 3 } else { 0 }
  if unique_kind != 0 {
    for item in values {
      match item {
        String(_) => {
          if unique_kind == 3 { unique_kind = 1 }
          else if unique_kind != 1 { unique_kind = 0; break }
        }
        Number(_, repr~) => {
          if repr is Some(_) { unique_kind = 0; break }
          if unique_kind == 3 { unique_kind = 2 }
          else if unique_kind != 2 { unique_kind = 0; break }
        }
        _ => { unique_kind = 0; break }
      }
    }
  }
  // Construct only the set used by this schema. Non-unique arrays (including
  // array1024) must not allocate hash tables merely to evaluate their items.
  let seen_strings : Set[String]? = if unique_kind == 1 { Some(Set([])) } else { None }
  let seen_numbers : Set[Double]? = if unique_kind == 2 { Some(Set([])) } else { None }
  if plan.minimum is Some(bound) && values.length() < bound {
    valid = fail(
      failures,
      path,
      pointer_step(plan.path, "minItems"),
      "minItems",
      "array has too few items",
    )
    if failures is None {
      return false
    }
  }
  if plan.maximum is Some(bound) && values.length() > bound {
    valid = fail(
      failures,
      path,
      pointer_step(plan.path, "maxItems"),
      "maxItems",
      "array has too many items",
    )
    if failures is None {
      return false
    }
  }
  let contains = fresh_marks(evaluated is Some(_))
  let mut prefix_valid = true
  let mut items_valid = true
  let mut matches = 0
  for index, child in values {
    let child_path = if failures is None { "" } else { pointer_step(path, index.to_string()) }
    let schema = if index < plan.prefix.length() {
      Some(plan.prefix[index])
    } else {
      plan.items
    }
    if schema is Some(node) &&
      !evaluate(
        program,
        node,
        child,
        child_path,
        failures,
        depth + 1,
        limit,
        scope~,
      ) {
      valid = false
      if index < plan.prefix.length() {
        prefix_valid = false
      } else {
        items_valid = false
      }
      if failures is None {
        return false
      }
    }
    if plan.contains is Some(node) &&
      evaluate(program, node, child, child_path, None, depth + 1, limit, scope~) {
      matches += 1
      if contains is Some(marks) {
        marks.items.add(index)
      }
    }
    if plan.unique {
      let duplicate = if unique_kind == 1 {
        let key = match child {
          String(text) => text
          _ => abort("unique kind")
        }
        let seen = seen_strings.unwrap()
        let duplicate = seen.contains(key)
        seen.add(key)
        duplicate
      } else if unique_kind == 2 {
        let number = match child {
          Number(number, ..) => number
          _ => abort("unique kind")
        }
        // Core Hash[Double] normalizes signed zero and hashes the IEEE bits
        // directly. No decimal rendering or string allocation per element.
        let seen = seen_numbers.unwrap()
        let duplicate = seen.contains(number)
        seen.add(number)
        duplicate
      } else {
        let mut duplicate = false
        for previous in 0..<index {
          if schema_equal(values[previous], child) {
            duplicate = true
            break
          }
        }
        duplicate
      }
      if duplicate {
        valid = fail(
          failures,
          child_path,
          pointer_step(plan.path, "uniqueItems"),
          "uniqueItems",
          "array contains equal items",
        )
        if failures is None {
          return false
        }
      }
    }
  }
  if evaluated is Some(marks) {
    if prefix_valid {
      for index in 0..<values.length().min(plan.prefix.length()) {
        marks.items.add(index)
      }
    }
    if items_valid && plan.items is Some(_) {
      for index in plan.prefix.length()..<values.length() {
        marks.items.add(index)
      }
    }
  }
  if plan.contains is Some(_) {
    let mut contains_valid = true
    if matches < plan.min_contains {
      valid = fail(
        failures,
        path,
        pointer_step(plan.path, "contains"),
        "contains",
        "too few items matched contains",
      )
      contains_valid = false
      if failures is None {
        return false
      }
    }
    if plan.max_contains is Some(bound) && matches > bound {
      valid = fail(
        failures,
        path,
        pointer_step(plan.path, "maxContains"),
        "maxContains",
        "too many items matched contains",
      )
      contains_valid = false
    }
    if contains_valid {
      merge_marks(evaluated, contains)
    }
  }
  valid
}
