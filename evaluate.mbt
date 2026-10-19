///|
priv struct EvaluationMarks {
  properties : Set[String]
  items : Set[Int32]
}

///|
fn fresh_marks(enabled : Bool) -> EvaluationMarks? {
  if enabled {
    Some({ properties: Set([]), items: Set([]), })
  } else {
    None
  }
}

///|
fn merge_marks(into : EvaluationMarks?, source : EvaluationMarks?) -> Unit {
  if into is Some(target) && source is Some(source) {
    for name in source.properties {
      target.properties.add(name)
    }
    for index in source.items {
      target.items.add(index)
    }
  }
}

///|
fn evaluate(
  program : Program,
  plan : Plan,
  value : Json,
  path : String,
  failures : Array[Fault]?,
  depth : Int32,
  limit : Int32,
  scope~ : Array[Int32] = [],
  evaluated~ : EvaluationMarks? = None,
) -> Bool raise {
  if depth > limit {
    raise EvaluationError::DepthLimit(limit)
  }
  match plan {
    Pending => abort("uncompiled schema arena slot")
    Located(resource, inner) => {
      let next_scope = if scope.last() == Some(resource) {
        scope
      } else {
        let next = scope.copy()
        next.push(resource)
        next
      }
      let start = match failures {
        Some(entries) => entries.length()
        None => 0
      }
      let valid = evaluate(
        program,
        inner,
        value,
        path,
        failures,
        depth,
        limit,
        scope=next_scope,
        evaluated~,
      )
      if failures is Some(entries) {
        for index in start..<entries.length() {
          let fault = entries[index]
          if fault.schema_uri is None {
            entries[index] = {
              instance_path: fault.instance_path,
              schema_path: fault.schema_path,
              schema_uri: program.resources[resource].document_uri,
              keyword: fault.keyword,
              message: fault.message,
            }
          }
        }
      }
      valid
    }
    Accept => true
    Reject(location) =>
      fail(
        failures, path, location, "false", "boolean schema rejects every instance",
      )
    Rules(rules) => {
      let marks = fresh_marks(
        program.collect_evaluated && value is (Object(_) | Array(_)),
      )
      let mut valid = true
      // Unevaluated applicators depend on every adjacent in-place applicator,
      // never on the insertion order of the schema object's members.
      for rule in rules {
        if rule is (UnevaluatedProperties(_, _) | UnevaluatedItems(_, _)) {
          continue
        }
        if !evaluate_rule(
            program,
            rule,
            value,
            path,
            failures,
            depth,
            limit,
            scope~,
            evaluated=marks,
          ) {
          valid = false
          if failures is None {
            return false
          }
        }
      }
      for rule in rules {
        if rule is (UnevaluatedProperties(_, _) | UnevaluatedItems(_, _)) {
          if !evaluate_rule(
              program,
              rule,
              value,
              path,
              failures,
              depth,
              limit,
              scope~,
              evaluated=marks,
            ) {
            valid = false
            if failures is None {
              return false
            }
          }
        }
      }
      if valid {
        merge_marks(evaluated, marks)
      }
      valid
    }
  }
}

///|
fn evaluate_applicator(
  program : Program,
  rule : Rule,
  value : Json,
  path : String,
  failures : Array[Fault]?,
  depth : Int32,
  limit : Int32,
  scope : Array[Int32],
  evaluated : EvaluationMarks?,
) -> Bool raise {
  match rule {
    Objects(plan) =>
      evaluate_object(
        program, plan, value, path, failures, depth, limit, scope, evaluated,
      )
    Arrays(plan) =>
      evaluate_array(
        program, plan, value, path, failures, depth, limit, scope, evaluated,
      )
    All(branches, location) => {
      let marks = fresh_marks(evaluated is Some(_))
      let mut valid = true
      for branch in branches {
        if !evaluate(
            program,
            branch,
            value,
            path,
            failures,
            depth + 1,
            limit,
            scope~,
            evaluated=marks,
          ) {
          valid = false
          if failures is None {
            return false
          }
        }
      }
      if valid {
        merge_marks(evaluated, marks)
      } else if failures is Some(_) {
        ignore(
          fail(failures, path, location, "allOf", "not every branch matched"),
        )
      }
      valid
    }
    Any(branches, location) => {
      let marks = fresh_marks(evaluated is Some(_))
      let mut valid = false
      for branch in branches {
        if evaluate(
            program,
            branch,
            value,
            path,
            None,
            depth + 1,
            limit,
            scope~,
            evaluated=marks,
          ) {
          valid = true
          if evaluated is None {
            return true
          }
        }
      }
      if valid {
        merge_marks(evaluated, marks)
        true
      } else {
        fail(failures, path, location, "anyOf", "no branch matched")
      }
    }
    One(branches, location) => {
      let marks = fresh_marks(evaluated is Some(_))
      let mut matches = 0
      for branch in branches {
        if evaluate(
            program,
            branch,
            value,
            path,
            None,
            depth + 1,
            limit,
            scope~,
            evaluated=marks,
          ) {
          matches += 1
          if matches > 1 {
            break
          }
        }
      }
      if matches == 1 {
        merge_marks(evaluated, marks)
        true
      } else {
        fail(
          failures, path, location, "oneOf", "expected exactly one matching branch",
        )
      }
    }
    Negate(branch, location) =>
      !evaluate(program, branch, value, path, None, depth + 1, limit, scope~) ||
      fail(failures, path, location, "not", "negated schema matched")
    Conditional(predicate, consequent, alternate) => {
      let marks = fresh_marks(evaluated is Some(_))
      let matched = evaluate(
        program,
        predicate,
        value,
        path,
        None,
        depth + 1,
        limit,
        scope~,
        evaluated=marks,
      )
      let arm = if matched {
        merge_marks(evaluated, marks)
        consequent
      } else {
        alternate
      }
      match arm {
        Some(branch) =>
          evaluate(
            program,
            branch,
            value,
            path,
            failures,
            depth + 1,
            limit,
            scope~,
            evaluated~,
          )
        None => true
      }
    }
    Ref(target) =>
      evaluate(
        program,
        program.nodes[target],
        value,
        path,
        failures,
        depth + 1,
        limit,
        scope~,
        evaluated~,
      )
    DynamicRef(initial, name) => {
      let mut target = initial
      if name is Some(name) {
        for resource in scope {
          if program.resources[resource].dynamic_anchors.get(name) is Some(slot) {
            target = slot
            break
          }
        }
      }
      evaluate(
        program,
        program.nodes[target],
        value,
        path,
        failures,
        depth + 1,
        limit,
        scope~,
        evaluated~,
      )
    }
    UnevaluatedProperties(schema, location) => {
      guard value is Object(fields) else { return true }
      let mut valid = true
      for name, child in fields {
        if evaluated is Some(marks) && marks.properties.contains(name) {
          continue
        }
        if !evaluate(
            program,
            schema,
            child,
            pointer_step(path, name),
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
      if valid {
        if evaluated is Some(marks) {
          for name, _ in fields {
            marks.properties.add(name)
          }
        }
      } else {
        ignore(
          fail(
            failures, path, location, "unevaluatedProperties", "unevaluated property failed its schema",
          ),
        )
      }
      valid
    }
    UnevaluatedItems(schema, location) => {
      guard value is Array(values) else { return true }
      let mut valid = true
      for index, child in values {
        if evaluated is Some(marks) && marks.items.contains(index) {
          continue
        }
        if !evaluate(
            program,
            schema,
            child,
            pointer_step(path, index.to_string()),
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
      if valid {
        if evaluated is Some(marks) {
          for index in 0..<values.length() {
            marks.items.add(index)
          }
        }
      } else {
        ignore(
          fail(
            failures, path, location, "unevaluatedItems", "unevaluated item failed its schema",
          ),
        )
      }
      valid
    }
    _ => abort("scalar rule passed to applicator evaluator")
  }
}
