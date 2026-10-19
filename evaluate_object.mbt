///|
fn evaluate_object(
  program : Program,
  plan : ObjectPlan,
  value : Json,
  path : String,
  failures : Array[Fault]?,
  depth : Int32,
  limit : Int32,
  scope : Array[Int32],
  evaluated : EvaluationMarks?,
) -> Bool raise {
  guard value is Object(fields) else { return true }
  let mut valid = true
  if plan.minimum is Some(bound) && fields.length() < bound {
    valid = fail(
      failures,
      path,
      pointer_step(plan.path, "minProperties"),
      "minProperties",
      "object has too few properties",
    )
    if failures is None {
      return false
    }
  }
  if plan.maximum is Some(bound) && fields.length() > bound {
    valid = fail(
      failures,
      path,
      pointer_step(plan.path, "maxProperties"),
      "maxProperties",
      "object has too many properties",
    )
    if failures is None {
      return false
    }
  }
  for name in plan.required {
    if !fields.contains(name) {
      valid = fail(
        failures,
        path,
        pointer_step(plan.path, "required"),
        "required",
        "missing required property: " + name,
      )
      if failures is None {
        return false
      }
    }
  }
  let properties = fresh_marks(evaluated is Some(_))
  let patterns = fresh_marks(evaluated is Some(_))
  let additional = fresh_marks(evaluated is Some(_))
  let mut properties_valid = true
  let mut patterns_valid = true
  let mut additional_valid = true
  for name, child in fields {
    let child_path = pointer_step(path, name)
    let mut covered = false
    if plan.properties.get(name) is Some(schema) {
      covered = true
      if !evaluate(
          program,
          schema,
          child,
          child_path,
          failures,
          depth + 1,
          limit,
          scope~,
        ) {
        valid = false
        properties_valid = false
        if failures is None {
          return false
        }
      }
      if properties is Some(marks) {
        marks.properties.add(name)
      }
    }
    for entry in plan.patterns {
      let (pattern, schema) = entry
      if pattern_matches(pattern, name) {
        covered = true
        if !evaluate(
            program,
            schema,
            child,
            child_path,
            failures,
            depth + 1,
            limit,
            scope~,
          ) {
          valid = false
          patterns_valid = false
          if failures is None {
            return false
          }
        }
        if patterns is Some(marks) {
          marks.properties.add(name)
        }
      }
    }
    if !covered && plan.additional is Some(schema) {
      if !evaluate(
          program,
          schema,
          child,
          child_path,
          failures,
          depth + 1,
          limit,
          scope~,
        ) {
        valid = false
        additional_valid = false
        if failures is None {
          return false
        }
      }
      if additional is Some(marks) {
        marks.properties.add(name)
      }
    }
    if plan.names is Some(schema) {
      if !evaluate(
          program,
          schema,
          Json::string(name),
          child_path,
          failures,
          depth + 1,
          limit,
          scope~,
        ) {
        valid = false
        if failures is None {
          return false
        }
      }
    }
  }
  if properties_valid {
    merge_marks(evaluated, properties)
  }
  if patterns_valid {
    merge_marks(evaluated, patterns)
  }
  if additional_valid {
    merge_marks(evaluated, additional)
  }
  for entry in plan.dependent_required {
    let (trigger, names) = entry
    if fields.contains(trigger) {
      for name in names {
        if !fields.contains(name) {
          valid = fail(
            failures,
            path,
            pointer_step(pointer_step(plan.path, "dependentRequired"), trigger),
            "dependentRequired",
            "missing dependent property: " + name,
          )
          if failures is None {
            return false
          }
        }
      }
    }
  }
  let dependencies = fresh_marks(evaluated is Some(_))
  let mut dependencies_valid = true
  for entry in plan.dependent_schemas {
    let (trigger, schema) = entry
    if fields.contains(trigger) &&
      !evaluate(
        program,
        schema,
        value,
        path,
        failures,
        depth + 1,
        limit,
        scope~,
        evaluated=dependencies,
      ) {
      valid = false
      dependencies_valid = false
      if failures is None {
        return false
      }
    }
  }
  if dependencies_valid {
    merge_marks(evaluated, dependencies)
  }
  valid
}
