// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

// Explicit 2020-12 output collection (core chapter 12). Validation itself
// stays on the allocation-free `Schema::valid` fast path; callers opt into
// output units only when they need diagnostics or annotations.

///|
/// The four 2020-12 output formats.
///
/// * `Flag` reports only the boolean result and reuses the ordinary
///   short-circuiting evaluator.
/// * `Basic` flattens every failed keyword and every collected annotation.
/// * `Detailed` keeps a hierarchical failure tree but retains only the first
///   failed child at each level.
/// * `Verbose` keeps every collected failure and annotation.
pub(all) enum OutputFormat {
  Flag
  Basic
  Detailed
  Verbose
}

///|
/// One 2020-12 output unit.
///
/// `keyword_location` is a JSON Pointer into the source document that owns
/// the keyword; `absolute_keyword_location` re-bases it onto the containing
/// schema resource's canonical URI (using its `$id`, or the document URI when
/// the resource is anonymous). `instance_location` is a JSON Pointer into the
/// validated instance. `annotation` is present only on annotation units and
/// `error` only on assertion failures; a unit never carries both.
pub(all) struct OutputUnit {
  valid : Bool
  keyword_location : String
  absolute_keyword_location : String?
  instance_location : String
  error : String?
  annotation : Json?
  errors : Array[OutputUnit]
  annotations : Array[OutputUnit]
}

///|
/// Serialize a unit to the standard 2020-12 output object. Empty `errors` /
/// `annotations` arrays and absent optional members are omitted.
pub fn OutputUnit::to_json(self : OutputUnit) -> Json {
  let members : Map[String, Json] = Map([])
  members.set("valid", Json::boolean(self.valid))
  members.set("keywordLocation", Json::string(self.keyword_location))
  members.set("instanceLocation", Json::string(self.instance_location))
  if self.absolute_keyword_location is Some(location) {
    members.set("absoluteKeywordLocation", Json::string(location))
  }
  if self.error is Some(message) {
    members.set("error", Json::string(message))
  }
  if self.annotation is Some(value) {
    members.set("annotation", value)
  }
  if !self.errors.is_empty() {
    members.set("errors", Json::array(self.errors.map(unit => unit.to_json())))
  }
  if !self.annotations.is_empty() {
    members.set(
      "annotations", Json::array(self.annotations.map(unit => unit.to_json())),
    )
  }
  Json::object(members)
}

///|
pub impl Show for OutputUnit with output(self, logger) {
  logger.write_string(self.to_json().stringify())
}

///|
/// Collect the requested output format for one instance. Numeric
/// representations and the traversal budget are checked before collection, so
/// an invalid numeric node or exhausted depth raises instead of producing an
/// ordinary `valid: false` unit.
pub fn Schema::output(
  self : Schema,
  value : Json,
  format~ : OutputFormat = Basic,
  max_depth~ : Int32 = 128,
) -> OutputUnit raise {
  check_instance(value, 0, max_depth)
  match format {
    Flag => {
      // The flag format must not pay for annotation or diagnostic collection.
      let valid = evaluate(
        self.plan, self.plan.nodes[0], value, "", None, 0, max_depth,
      )
      if valid {
        output_unit(self.plan, 0, "", "", true)
      } else {
        output_unit(
          self.plan,
          0,
          "",
          "",
          false,
          error="schema does not validate the instance",
        )
      }
    }
    Basic => {
      let tree = collect_tree(self.plan, value, max_depth)
      basic_output(tree)
    }
    Detailed => {
      let tree = collect_tree(self.plan, value, max_depth)
      detailed_output(tree)
    }
    Verbose => collect_tree(self.plan, value, max_depth)
  }
}

///|
fn collect_tree(program : Program, value : Json, limit : Int32) -> OutputUnit raise {
  collect_node(
    program,
    0,
    "",
    program.nodes[0],
    value,
    "",
    0,
    limit,
    [],
    None,
  )
}

///|
// Re-base a document-relative keyword pointer onto the resource identity.
// The resource root itself (relative pointer "") is the bare URI; deeper
// keywords use the URI fragment form `uri#/pointer`.
fn absolute_keyword_location(
  program : Program,
  resource : Int32,
  location : String,
) -> String? {
  let meta = program.resources[resource]
  let base = match meta.uri {
    Some(uri) => Some(uri)
    None => meta.document_uri
  }
  match base {
    Some(base) => {
      let relative = if location.has_prefix(meta.root_pointer) {
        location[meta.root_pointer.length():].to_owned()
      } else {
        location
      }
      Some(if relative == "" { base } else { base + "#" + relative })
    }
    None => None
  }
}

///|
fn output_unit(
  program : Program,
  resource : Int32,
  keyword_location : String,
  instance_location : String,
  valid : Bool,
  error? : String,
  annotation? : Json,
  errors~ : Array[OutputUnit] = [],
  annotations~ : Array[OutputUnit] = [],
) -> OutputUnit {
  {
    valid,
    keyword_location,
    absolute_keyword_location: absolute_keyword_location(
      program, resource, keyword_location,
    ),
    instance_location,
    error,
    annotation,
    errors,
    annotations,
  }
}

///|
// Result of collecting one non-annotation keyword. `errors` is nonempty only
// when the keyword failed; `annotations` only when it succeeded.
priv struct RuleOutput {
  valid : Bool
  errors : Array[OutputUnit]
  annotations : Array[OutputUnit]
}

///|
fn rule_output(
  valid : Bool,
  errors~ : Array[OutputUnit] = [],
  annotations~ : Array[OutputUnit] = [],
) -> RuleOutput {
  { valid, errors, annotations }
}

///|
fn append_units(into : Array[OutputUnit], source : Array[OutputUnit]) -> Unit {
  for unit in source {
    into.push(unit)
  }
}

///|
// Collect one schema node. `Located` carries the owning resource and the
// node's canonical pointer, so keyword units get correct absolute locations
// even after a reference crosses into another document.
fn collect_node(
  program : Program,
  resource : Int32,
  node_path : String,
  plan : Plan,
  value : Json,
  instance_path : String,
  depth : Int32,
  limit : Int32,
  scope : Array[Int32],
  evaluated : EvaluationMarks?,
) -> OutputUnit raise {
  if depth > limit {
    raise EvaluationError::DepthLimit(limit)
  }
  match plan {
    Pending => abort("uncompiled schema arena slot")
    Located(next_resource, next_path, inner) => {
      let next_scope = if !program.track_dynamic_scope ||
        scope.last() == Some(next_resource) {
        scope
      } else {
        let next = scope.copy()
        next.push(next_resource)
        next
      }
      collect_node(
        program,
        next_resource,
        next_path,
        inner,
        value,
        instance_path,
        depth,
        limit,
        next_scope,
        evaluated,
      )
    }
    Accept => output_unit(program, resource, node_path, instance_path, true)
    Reject(location) =>
      output_unit(
        program,
        resource,
        location,
        instance_path,
        false,
        error="boolean schema rejects every instance",
      )
    Rules(rules) => {
      let marks = fresh_marks(
        program.collect_evaluated && value is (Object(_) | Array(_)),
      )
      let errors : Array[OutputUnit] = []
      let annotations : Array[OutputUnit] = []
      let metadata : Array[OutputUnit] = []
      let mut valid = true
      // Annotations are recorded separately: they are emitted only when every
      // keyword in this schema object succeeded.
      for rule in rules {
        match rule {
          Annotations(items) =>
            for item in items {
              metadata.push(
                output_unit(
                  program,
                  resource,
                  item.location,
                  instance_path,
                  true,
                  annotation=item.value,
                ),
              )
            }
          UnevaluatedProperties(_, _) | UnevaluatedItems(_, _) => ()
          _ => {
            let result = collect_rule(
              program,
              resource,
              rule,
              value,
              instance_path,
              depth,
              limit,
              scope,
              marks,
            )
            if result.valid {
              append_units(annotations, result.annotations)
            } else {
              valid = false
              append_units(errors, result.errors)
            }
          }
        }
      }
      // Unevaluated keywords observe every adjacent applicator, so they run
      // after the first pass exactly as in evaluation.
      if program.collect_evaluated {
        for rule in rules {
          match rule {
            UnevaluatedProperties(_, _) | UnevaluatedItems(_, _) => {
              let result = collect_rule(
                program,
                resource,
                rule,
                value,
                instance_path,
                depth,
                limit,
                scope,
                marks,
              )
              if result.valid {
                append_units(annotations, result.annotations)
              } else {
                valid = false
                append_units(errors, result.errors)
              }
            }
            _ => ()
          }
        }
      }
      if valid {
        merge_marks(evaluated, marks)
        append_units(metadata, annotations)
        output_unit(
          program,
          resource,
          node_path,
          instance_path,
          true,
          annotations=metadata,
        )
      } else {
        output_unit(
          program,
          resource,
          node_path,
          instance_path,
          false,
          errors~,
        )
      }
    }
  }
}

///|
// Evaluate one keyword and return the units it contributes. Assertion
// keywords produce a single error unit on failure. Applicators nest the
// failing child schema units under their keyword unit.
fn collect_rule(
  program : Program,
  resource : Int32,
  rule : Rule,
  value : Json,
  instance_path : String,
  depth : Int32,
  limit : Int32,
  scope : Array[Int32],
  evaluated : EvaluationMarks?,
) -> RuleOutput raise {
  match rule {
    Annotations(_) => rule_output(true)
    Types(types, location) => {
      let matches = types.any(kind => matches_type(kind, value, instance_path))
      if matches {
        rule_output(true)
      } else {
        rule_output(
          false,
          errors=[
            output_unit(
              program,
              resource,
              location,
              instance_path,
              false,
              error="instance has none of the permitted types",
            ),
          ],
        )
      }
    }
    Constant(expected, location) => {
      if schema_equal(value, expected) {
        rule_output(true)
      } else {
        rule_output(
          false,
          errors=[
            output_unit(
              program,
              resource,
              location,
              instance_path,
              false,
              error="instance differs from the constant",
            ),
          ],
        )
      }
    }
    Enumeration(values, location) => {
      if values.any(expected => schema_equal(value, expected)) {
        rule_output(true)
      } else {
        rule_output(
          false,
          errors=[
            output_unit(
              program,
              resource,
              location,
              instance_path,
              false,
              error="instance is not an enumerated value",
            ),
          ],
        )
      }
    }
    Lower(bound, exclusive, location) => {
      guard value is Number(_, ..) else { return rule_output(true) }
      let ordering = numeric_value(value, instance_path).compare(bound)
      let valid = if exclusive { ordering > 0 } else { ordering >= 0 }
      if valid {
        rule_output(true)
      } else {
        rule_output(
          false,
          errors=[
            output_unit(
              program,
              resource,
              location,
              instance_path,
              false,
              error="number is below its lower bound",
            ),
          ],
        )
      }
    }
    Upper(bound, exclusive, location) => {
      guard value is Number(_, ..) else { return rule_output(true) }
      let ordering = numeric_value(value, instance_path).compare(bound)
      let valid = if exclusive { ordering < 0 } else { ordering <= 0 }
      if valid {
        rule_output(true)
      } else {
        rule_output(
          false,
          errors=[
            output_unit(
              program,
              resource,
              location,
              instance_path,
              false,
              error="number exceeds its upper bound",
            ),
          ],
        )
      }
    }
    Multiple(divisor, location) => {
      guard value is Number(_, ..) else { return rule_output(true) }
      if numeric_value(value, instance_path).multiple_of(divisor) {
        rule_output(true)
      } else {
        rule_output(
          false,
          errors=[
            output_unit(
              program,
              resource,
              location,
              instance_path,
              false,
              error="number is not an exact multiple",
            ),
          ],
        )
      }
    }
    StringLength(minimum, maximum, location) => {
      guard value is String(text) else { return rule_output(true) }
      let length = text.char_length()
      let errors : Array[OutputUnit] = []
      if minimum is Some(bound) && bound.above(length) {
        errors.push(
          output_unit(
            program,
            resource,
            pointer_step(location, "minLength"),
            instance_path,
            false,
            error="string has too few Unicode code points",
          ),
        )
      }
      if maximum is Some(bound) && bound.below(length) {
        errors.push(
          output_unit(
            program,
            resource,
            pointer_step(location, "maxLength"),
            instance_path,
            false,
            error="string has too many Unicode code points",
          ),
        )
      }
      rule_output(errors.is_empty(), errors~)
    }
    Pattern(pattern, location) => {
      guard value is String(text) else { return rule_output(true) }
      if pattern_matches(pattern, text) {
        rule_output(true)
      } else {
        rule_output(
          false,
          errors=[
            output_unit(
              program,
              resource,
              location,
              instance_path,
              false,
              error="string does not match the pattern",
            ),
          ],
        )
      }
    }
    Objects(plan) =>
      collect_object(
        program, resource, plan, value, instance_path, depth, limit, scope,
        evaluated,
      )
    Arrays(plan) =>
      collect_array(
        program, resource, plan, value, instance_path, depth, limit, scope,
        evaluated,
      )
    All(branches, location) => {
      let marks = fresh_marks(evaluated is Some(_))
      let branch_errors : Array[OutputUnit] = []
      let branch_annotations : Array[OutputUnit] = []
      let mut valid = true
      for branch in branches {
        let node = collect_node(
          program,
          resource,
          "",
          branch,
          value,
          instance_path,
          depth + 1,
          limit,
          scope,
          marks,
        )
        if node.valid {
          append_units(branch_annotations, node.annotations)
        } else {
          valid = false
          branch_errors.push(node)
        }
      }
      if valid {
        merge_marks(evaluated, marks)
        rule_output(true, annotations=branch_annotations)
      } else {
        rule_output(
          false,
          errors=[
            output_unit(
              program,
              resource,
              location,
              instance_path,
              false,
              errors=branch_errors,
            ),
          ],
        )
      }
    }
    Any(branches, location) => {
      let marks = fresh_marks(evaluated is Some(_))
      let branch_annotations : Array[OutputUnit] = []
      let mut matched = false
      for branch in branches {
        let node = collect_node(
          program,
          resource,
          "",
          branch,
          value,
          instance_path,
          depth + 1,
          limit,
          scope,
          marks,
        )
        if node.valid {
          matched = true
          append_units(branch_annotations, node.annotations)
        }
      }
      if matched {
        merge_marks(evaluated, marks)
        rule_output(true, annotations=branch_annotations)
      } else {
        // Speculative branches are not asserted; only the applicator failure
        // is reported, matching `Schema::faults`.
        rule_output(
          false,
          errors=[
            output_unit(
              program,
              resource,
              location,
              instance_path,
              false,
              error="no branch matched",
            ),
          ],
        )
      }
    }
    One(branches, location) => {
      let marks = fresh_marks(evaluated is Some(_))
      let matching : Array[OutputUnit] = []
      for branch in branches {
        let node = collect_node(
          program,
          resource,
          "",
          branch,
          value,
          instance_path,
          depth + 1,
          limit,
          scope,
          marks,
        )
        if node.valid {
          matching.push(node)
          if matching.length() > 1 {
            break
          }
        }
      }
      if matching.length() == 1 {
        merge_marks(evaluated, marks)
        rule_output(true, annotations=matching[0].annotations)
      } else {
        rule_output(
          false,
          errors=[
            output_unit(
              program,
              resource,
              location,
              instance_path,
              false,
              error="expected exactly one matching branch",
            ),
          ],
        )
      }
    }
    Negate(branch, location) => {
      let node = collect_node(
        program,
        resource,
        "",
        branch,
        value,
        instance_path,
        depth + 1,
        limit,
        scope,
        None,
      )
      if node.valid {
        rule_output(
          false,
          errors=[
            output_unit(
              program,
              resource,
              location,
              instance_path,
              false,
              error="negated schema matched",
            ),
          ],
        )
      } else {
        rule_output(true)
      }
    }
    Conditional(predicate, consequent, alternate) => {
      let predicate_marks = fresh_marks(evaluated is Some(_))
      let condition = collect_node(
        program,
        resource,
        "",
        predicate,
        value,
        instance_path,
        depth + 1,
        limit,
        scope,
        predicate_marks,
      )
      let matched = condition.valid
      if matched {
        merge_marks(evaluated, predicate_marks)
      }
      let arm = if matched { consequent } else { alternate }
      match arm {
        Some(branch) => {
          let node = collect_node(
            program,
            resource,
            "",
            branch,
            value,
            instance_path,
            depth + 1,
            limit,
            scope,
            evaluated,
          )
          if node.valid {
            rule_output(true, annotations=node.annotations)
          } else {
            rule_output(false, errors=[node])
          }
        }
        None => rule_output(true)
      }
    }
    Ref(target) =>
      collect_reference(
        program, target, value, instance_path, depth, limit, scope, evaluated,
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
      collect_reference(
        program, target, value, instance_path, depth, limit, scope, evaluated,
      )
    }
    UnevaluatedProperties(schema, location) =>
      collect_unevaluated_properties(
        program,
        resource,
        schema,
        location,
        value,
        instance_path,
        depth,
        limit,
        scope,
        evaluated,
      )
    UnevaluatedItems(schema, location) =>
      collect_unevaluated_items(
        program,
        resource,
        schema,
        location,
        value,
        instance_path,
        depth,
        limit,
        scope,
        evaluated,
      )
  }
}

///|
fn collect_reference(
  program : Program,
  target : Int32,
  value : Json,
  instance_path : String,
  depth : Int32,
  limit : Int32,
  scope : Array[Int32],
  evaluated : EvaluationMarks?,
) -> RuleOutput raise {
  let node = collect_node(
    program,
    0,
    "",
    program.nodes[target],
    value,
    instance_path,
    depth + 1,
    limit,
    scope,
    evaluated,
  )
  if node.valid {
    rule_output(true, annotations=node.annotations)
  } else {
    rule_output(false, errors=[node])
  }
}

///|
fn collect_unevaluated_properties(
  program : Program,
  resource : Int32,
  schema : Plan,
  location : String,
  value : Json,
  instance_path : String,
  depth : Int32,
  limit : Int32,
  scope : Array[Int32],
  evaluated : EvaluationMarks?,
) -> RuleOutput raise {
  guard value is Object(fields) else { return rule_output(true) }
  let errors : Array[OutputUnit] = []
  let annotations : Array[OutputUnit] = []
  let applied : Array[String] = []
  let mut valid = true
  for name, child in fields {
    if evaluated is Some(marks) && marks.properties.contains(name) {
      continue
    }
    applied.push(name)
    let node = collect_node(
      program,
      resource,
      "",
      schema,
      child,
      pointer_step(instance_path, name),
      depth + 1,
      limit,
      scope,
      None,
    )
    if node.valid {
      append_units(annotations, node.annotations)
    } else {
      valid = false
      errors.push(node)
    }
  }
  if valid {
    if evaluated is Some(marks) {
      for name in applied {
        marks.properties.add(name)
      }
    }
    rule_output(
      true,
      annotations=[
        output_unit(
          program,
          resource,
          location,
          instance_path,
          true,
          annotation=Json::array(applied.map(name => Json::string(name))),
          annotations~,
        ),
      ],
    )
  } else {
    rule_output(
      false,
      errors=[
        output_unit(
          program,
          resource,
          location,
          instance_path,
          false,
          errors~,
        ),
      ],
    )
  }
}

///|
fn collect_unevaluated_items(
  program : Program,
  resource : Int32,
  schema : Plan,
  location : String,
  value : Json,
  instance_path : String,
  depth : Int32,
  limit : Int32,
  scope : Array[Int32],
  evaluated : EvaluationMarks?,
) -> RuleOutput raise {
  guard value is Array(values) else { return rule_output(true) }
  let errors : Array[OutputUnit] = []
  let annotations : Array[OutputUnit] = []
  let mut valid = true
  for index, child in values {
    if evaluated is Some(marks) && marks.items.contains(index) {
      continue
    }
    let node = collect_node(
      program,
      resource,
      "",
      schema,
      child,
      pointer_step(instance_path, index.to_string()),
      depth + 1,
      limit,
      scope,
      None,
    )
    if node.valid {
      append_units(annotations, node.annotations)
    } else {
      valid = false
      errors.push(node)
    }
  }
  if valid {
    if evaluated is Some(marks) {
      for index in 0..<values.length() {
        marks.items.add(index)
      }
    }
    rule_output(
      true,
      annotations=[
        output_unit(
          program,
          resource,
          location,
          instance_path,
          true,
          annotation=Json::boolean(true),
          annotations~,
        ),
      ],
    )
  } else {
    rule_output(
      false,
      errors=[
        output_unit(
          program,
          resource,
          location,
          instance_path,
          false,
          errors~,
        ),
      ],
    )
  }
}

///|
fn collect_object(
  program : Program,
  resource : Int32,
  plan : ObjectPlan,
  value : Json,
  instance_path : String,
  depth : Int32,
  limit : Int32,
  scope : Array[Int32],
  evaluated : EvaluationMarks?,
) -> RuleOutput raise {
  guard value is Object(fields) else { return rule_output(true) }
  let errors : Array[OutputUnit] = []
  let annotations : Array[OutputUnit] = []
  let mut valid = true
  if plan.minimum is Some(bound) && bound.above(fields.length()) {
    valid = false
    errors.push(
      output_unit(
        program,
        resource,
        pointer_step(plan.path, "minProperties"),
        instance_path,
        false,
        error="object has too few properties",
      ),
    )
  }
  if plan.maximum is Some(bound) && bound.below(fields.length()) {
    valid = false
    errors.push(
      output_unit(
        program,
        resource,
        pointer_step(plan.path, "maxProperties"),
        instance_path,
        false,
        error="object has too many properties",
      ),
    )
  }
  for name in plan.required {
    if !fields.contains(name) {
      valid = false
      errors.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "required"),
          instance_path,
          false,
          error="missing required property: " + name,
        ),
      )
    }
  }
  let properties_present = !plan.properties.is_empty()
  let patterns_present = !plan.patterns.is_empty()
  let additional_present = plan.additional is Some(_)
  let names_present = plan.names is Some(_)
  let property_marks = fresh_marks(evaluated is Some(_))
  let pattern_marks = fresh_marks(evaluated is Some(_))
  let additional_marks = fresh_marks(evaluated is Some(_))
  let property_errors : Array[OutputUnit] = []
  let property_annotations : Array[OutputUnit] = []
  let property_names : Array[String] = []
  let pattern_errors : Array[OutputUnit] = []
  let pattern_annotations : Array[OutputUnit] = []
  let pattern_names : Array[String] = []
  let additional_errors : Array[OutputUnit] = []
  let additional_annotations : Array[OutputUnit] = []
  let additional_names : Array[String] = []
  let names_errors : Array[OutputUnit] = []
  let mut properties_valid = true
  let mut patterns_valid = true
  let mut additional_valid = true
  let mut names_valid = true
  for name, child in fields {
    let child_path = pointer_step(instance_path, name)
    let mut covered = false
    if plan.properties.get(name) is Some(schema) {
      covered = true
      property_names.push(name)
      let node = collect_node(
        program,
        resource,
        "",
        schema,
        child,
        child_path,
        depth + 1,
        limit,
        scope,
        None,
      )
      if node.valid {
        append_units(property_annotations, node.annotations)
      } else {
        properties_valid = false
        property_errors.push(node)
      }
      if property_marks is Some(marks) {
        marks.properties.add(name)
      }
    }
    for entry in plan.patterns {
      let (pattern, schema) = entry
      if pattern_matches(pattern, name) {
        covered = true
        pattern_names.push(name)
        let node = collect_node(
          program,
          resource,
          "",
          schema,
          child,
          child_path,
          depth + 1,
          limit,
          scope,
          None,
        )
        if node.valid {
          append_units(pattern_annotations, node.annotations)
        } else {
          patterns_valid = false
          pattern_errors.push(node)
        }
        if pattern_marks is Some(marks) {
          marks.properties.add(name)
        }
      }
    }
    if !covered && plan.additional is Some(schema) {
      additional_names.push(name)
      let node = collect_node(
        program,
        resource,
        "",
        schema,
        child,
        child_path,
        depth + 1,
        limit,
        scope,
        None,
      )
      if node.valid {
        append_units(additional_annotations, node.annotations)
      } else {
        additional_valid = false
        additional_errors.push(node)
      }
      if additional_marks is Some(marks) {
        marks.properties.add(name)
      }
    }
    if plan.names is Some(schema) {
      let node = collect_node(
        program,
        resource,
        "",
        schema,
        Json::string(name),
        child_path,
        depth + 1,
        limit,
        scope,
        None,
      )
      if !node.valid {
        names_valid = false
        names_errors.push(node)
      }
    }
  }
  if properties_present {
    if properties_valid {
      annotations.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "properties"),
          instance_path,
          true,
          annotation=Json::array(
            property_names.map(name => Json::string(name)),
          ),
          annotations=property_annotations,
        ),
      )
    } else {
      valid = false
      errors.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "properties"),
          instance_path,
          false,
          errors=property_errors,
        ),
      )
    }
  }
  if properties_valid {
    merge_marks(evaluated, property_marks)
  }
  if patterns_present {
    if patterns_valid {
      annotations.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "patternProperties"),
          instance_path,
          true,
          annotation=Json::array(pattern_names.map(name => Json::string(name))),
          annotations=pattern_annotations,
        ),
      )
    } else {
      valid = false
      errors.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "patternProperties"),
          instance_path,
          false,
          errors=pattern_errors,
        ),
      )
    }
  }
  if patterns_valid {
    merge_marks(evaluated, pattern_marks)
  }
  if additional_present {
    if additional_valid {
      annotations.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "additionalProperties"),
          instance_path,
          true,
          annotation=Json::array(
            additional_names.map(name => Json::string(name)),
          ),
          annotations=additional_annotations,
        ),
      )
    } else {
      valid = false
      errors.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "additionalProperties"),
          instance_path,
          false,
          errors=additional_errors,
        ),
      )
    }
  }
  if additional_valid {
    merge_marks(evaluated, additional_marks)
  }
  if names_present && !names_valid {
    valid = false
    errors.push(
      output_unit(
        program,
        resource,
        pointer_step(plan.path, "propertyNames"),
        instance_path,
        false,
        errors=names_errors,
      ),
    )
  }
  for entry in plan.dependent_required {
    let (trigger, names) = entry
    if fields.contains(trigger) {
      for name in names {
        if !fields.contains(name) {
          valid = false
          errors.push(
            output_unit(
              program,
              resource,
              pointer_step(
                pointer_step(plan.path, "dependentRequired"), trigger,
              ),
              instance_path,
              false,
              error="missing dependent property: " + name,
            ),
          )
        }
      }
    }
  }
  let dependency_marks = fresh_marks(evaluated is Some(_))
  let dependency_errors : Array[OutputUnit] = []
  let dependency_annotations : Array[OutputUnit] = []
  let mut dependencies_valid = true
  for entry in plan.dependent_schemas {
    let (trigger, schema) = entry
    if fields.contains(trigger) {
      let node = collect_node(
        program,
        resource,
        "",
        schema,
        value,
        instance_path,
        depth + 1,
        limit,
        scope,
        dependency_marks,
      )
      if node.valid {
        append_units(dependency_annotations, node.annotations)
      } else {
        dependencies_valid = false
        dependency_errors.push(node)
      }
    }
  }
  if dependencies_valid {
    merge_marks(evaluated, dependency_marks)
    append_units(annotations, dependency_annotations)
  } else {
    valid = false
    errors.push(
      output_unit(
        program,
        resource,
        pointer_step(plan.path, "dependentSchemas"),
        instance_path,
        false,
        errors=dependency_errors,
      ),
    )
  }
  if valid {
    rule_output(true, annotations~)
  } else {
    rule_output(false, errors~)
  }
}

///|
fn collect_array(
  program : Program,
  resource : Int32,
  plan : ArrayPlan,
  value : Json,
  instance_path : String,
  depth : Int32,
  limit : Int32,
  scope : Array[Int32],
  evaluated : EvaluationMarks?,
) -> RuleOutput raise {
  guard value is Array(values) else { return rule_output(true) }
  let errors : Array[OutputUnit] = []
  let annotations : Array[OutputUnit] = []
  let mut valid = true
  if plan.minimum is Some(bound) && bound.above(values.length()) {
    valid = false
    errors.push(
      output_unit(
        program,
        resource,
        pointer_step(plan.path, "minItems"),
        instance_path,
        false,
        error="array has too few items",
      ),
    )
  }
  if plan.maximum is Some(bound) && bound.below(values.length()) {
    valid = false
    errors.push(
      output_unit(
        program,
        resource,
        pointer_step(plan.path, "maxItems"),
        instance_path,
        false,
        error="array has too many items",
      ),
    )
  }
  let prefix_errors : Array[OutputUnit] = []
  let prefix_annotations : Array[OutputUnit] = []
  let items_errors : Array[OutputUnit] = []
  let items_annotations : Array[OutputUnit] = []
  let mut prefix_valid = true
  let mut items_valid = true
  let mut matches = 0
  let contains_annotations : Array[OutputUnit] = []
  let contains_indices : Array[Int32] = []
  for index, child in values {
    let child_path = pointer_step(instance_path, index.to_string())
    if index < plan.prefix.length() {
      let node = collect_node(
        program,
        resource,
        "",
        plan.prefix[index],
        child,
        child_path,
        depth + 1,
        limit,
        scope,
        None,
      )
      if node.valid {
        append_units(prefix_annotations, node.annotations)
      } else {
        prefix_valid = false
        prefix_errors.push(node)
      }
    } else if plan.items is Some(schema) {
      let node = collect_node(
        program,
        resource,
        "",
        schema,
        child,
        child_path,
        depth + 1,
        limit,
        scope,
        None,
      )
      if node.valid {
        append_units(items_annotations, node.annotations)
      } else {
        items_valid = false
        items_errors.push(node)
      }
    }
    if plan.contains is Some(schema) {
      let node = collect_node(
        program,
        resource,
        "",
        schema,
        child,
        child_path,
        depth + 1,
        limit,
        scope,
        None,
      )
      if node.valid {
        matches += 1
        contains_indices.push(index)
        append_units(contains_annotations, node.annotations)
      }
    }
    if plan.unique {
      let mut duplicate = false
      for previous in 0..<index {
        if schema_equal(values[previous], child) {
          duplicate = true
          break
        }
      }
      if duplicate {
        valid = false
        errors.push(
          output_unit(
            program,
            resource,
            pointer_step(plan.path, "uniqueItems"),
            child_path,
            false,
            error="array contains equal items",
          ),
        )
      }
    }
  }
  let evaluated_indices = evaluated
  if prefix_valid {
    for index in 0..<values.length().min(plan.prefix.length()) {
      if evaluated_indices is Some(marks) {
        marks.items.add(index)
      }
    }
  }
  if items_valid && plan.items is Some(_) {
    for index in plan.prefix.length()..<values.length() {
      if evaluated_indices is Some(marks) {
        marks.items.add(index)
      }
    }
  }
  if !plan.prefix.is_empty() {
    if prefix_valid {
      let applied = values.length().min(plan.prefix.length())
      let annotation = if applied > 0 {
        Some(Json::number((applied - 1).to_double()))
      } else {
        None
      }
      annotations.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "prefixItems"),
          instance_path,
          true,
          annotation~,
          annotations=prefix_annotations,
        ),
      )
    } else {
      valid = false
      errors.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "prefixItems"),
          instance_path,
          false,
          errors=prefix_errors,
        ),
      )
    }
  }
  if plan.items is Some(_) {
    if items_valid {
      annotations.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "items"),
          instance_path,
          true,
          annotation=Json::boolean(true),
          annotations=items_annotations,
        ),
      )
    } else {
      valid = false
      errors.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "items"),
          instance_path,
          false,
          errors=items_errors,
        ),
      )
    }
  }
  if plan.contains is Some(_) {
    let mut contains_valid = true
    if plan.min_contains.above(matches) {
      valid = false
      contains_valid = false
      errors.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "contains"),
          instance_path,
          false,
          error="too few items matched contains",
        ),
      )
    }
    if plan.max_contains is Some(bound) && bound.below(matches) {
      valid = false
      contains_valid = false
      errors.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "maxContains"),
          instance_path,
          false,
          error="too many items matched contains",
        ),
      )
    }
    if contains_valid {
      if evaluated is Some(marks) {
        for index in contains_indices {
          marks.items.add(index)
        }
      }
      annotations.push(
        output_unit(
          program,
          resource,
          pointer_step(plan.path, "contains"),
          instance_path,
          true,
          annotation=Json::array(
            contains_indices.map(index => Json::number(index.to_double())),
          ),
          annotations=contains_annotations,
        ),
      )
    }
  }
  if valid {
    rule_output(true, annotations~)
  } else {
    rule_output(false, errors~)
  }
}

///|
// The basic format is flat: one unit per failed assertion keyword and one
// unit per collected annotation.
fn basic_output(tree : OutputUnit) -> OutputUnit {
  let errors : Array[OutputUnit] = []
  let annotations : Array[OutputUnit] = []
  flatten_errors(tree, errors)
  flatten_annotations(tree, annotations)
  {
    valid: tree.valid,
    keyword_location: tree.keyword_location,
    absolute_keyword_location: tree.absolute_keyword_location,
    instance_location: tree.instance_location,
    error: None,
    annotation: None,
    errors,
    annotations,
  }
}

///|
fn flatten_errors(unit : OutputUnit, into : Array[OutputUnit]) -> Unit {
  if unit.error is Some(_) {
    into.push(
      {
        valid: false,
        keyword_location: unit.keyword_location,
        absolute_keyword_location: unit.absolute_keyword_location,
        instance_location: unit.instance_location,
        error: unit.error,
        annotation: None,
        errors: [],
        annotations: [],
      },
    )
    return
  }
  for child in unit.errors {
    flatten_errors(child, into)
  }
}

///|
fn flatten_annotations(unit : OutputUnit, into : Array[OutputUnit]) -> Unit {
  if unit.annotation is Some(_) {
    into.push(
      {
        valid: true,
        keyword_location: unit.keyword_location,
        absolute_keyword_location: unit.absolute_keyword_location,
        instance_location: unit.instance_location,
        error: None,
        annotation: unit.annotation,
        errors: [],
        annotations: [],
      },
    )
  }
  for child in unit.annotations {
    flatten_annotations(child, into)
  }
}

///|
// The detailed format keeps the failure hierarchy but retains only the first
// failed child at each level, while preserving every collected annotation.
fn detailed_output(tree : OutputUnit) -> OutputUnit {
  {
    valid: tree.valid,
    keyword_location: tree.keyword_location,
    absolute_keyword_location: tree.absolute_keyword_location,
    instance_location: tree.instance_location,
    error: tree.error,
    annotation: tree.annotation,
    errors: if tree.errors.is_empty() {
      []
    } else {
      [detailed_output(tree.errors[0])]
    },
    annotations: tree.annotations.map(unit => detailed_output(unit)),
  }
}
