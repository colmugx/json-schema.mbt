///|
/// Compile a schema once, optionally together with a registry of further
/// schema documents (`resources`, keyed by the URI each document was supplied
/// under) and the document's own `base_uri`. Reference resolution follows
/// RFC 3986 against `$id`-established resource identities; the registry is
/// consulted in memory only — compilation never performs I/O. Unknown
/// extension keywords are annotations; known malformed keywords, unresolvable
/// references, unknown anchors and duplicate identities fail compilation.
/// The returned schema owns its plan: later mutations to the documents or to
/// the registry map are not observed.
pub fn Schema::compile(
  document : Json,
  base_uri? : String,
  resources? : Map[String, Json],
  max_depth~ : Int32 = 128,
) -> Schema raise CompileError {
  if max_depth < 1 {
    raise CompileError::DepthLimit(max_depth)
  }
  check_schema_json(document, "", 0, max_depth)
  match resources {
    Some(entries) =>
      for _, entry in entries {
        check_schema_json(entry, "", 0, max_depth)
      }
    None => ()
  }
  let index = index_program(document, base_uri, resources, max_depth)
  ignore(compile_into(index, 0, 0, document, "", 0, max_depth))
  // A dynamic target may live under an otherwise inactive applicator (for
  // example `then` without `if`). No runtime jump may reach an uncompiled slot.
  while true {
    let pending : Array[Int32] = []
    for resource in index.resources {
      if resource.dialect.meta_slot is Some(slot) && !index.visited[slot] {
        pending.push(slot)
      }
      for _, slot in resource.dynamic_anchors {
        if !index.visited[slot] {
          pending.push(slot)
        }
      }
    }
    if pending.is_empty() {
      break
    }
    for slot in pending {
      ensure_compiled(index, slot, max_depth)
    }
  }
  let program : Program = {
    nodes: index.nodes,
    resources: index.resources,
    collect_evaluated: index.collect_evaluated,
    track_dynamic_scope: index.track_dynamic_scope,
  }
  for resource, metadata in index.resources {
    if metadata.dialect.meta_slot is Some(target) {
      let (doc, pointer) = index.sites[resource]
      let slot = slot_at(index, doc, pointer, pointer)
      let valid = evaluate(
        program,
        program.nodes[target],
        index.targets[slot],
        "",
        None,
        0,
        max_depth,
      ) catch {
        EvaluationError::DepthLimit(_) =>
          raise CompileError::DepthLimit(max_depth)
        error => {
          invalid_keyword(pointer, "metaschema evaluation failed: \{error}")
          false
        }
      }
      if !valid {
        invalid_keyword(
          pointer,
          "schema does not satisfy metaschema: " + metadata.dialect.uri,
        )
      }
    }
  }
  { plan: program, }
}

///|
// Compile one schema position and store its `Located` plan in the arena, so
// `$ref` and `$dynamicRef` rules can jump to it. The structural walk visits
// every keyword-owned position once; lazily referenced positions compile
// through the same entry point. Raising the visited flag on entry marks the
// active compile chain, which keeps recursive targets finite, and refs stay
// indexed instead of inlined.
fn compile_into(
  index : RefIndex,
  doc : Int32,
  resource : Int32,
  document : Json,
  path : String,
  depth : Int32,
  limit : Int32,
) -> Plan raise CompileError {
  let slots = index.docs[doc].slots
  let resource = match slots.get(path) {
    Some(slot) => {
      let actual = ensure_slot_resource(index, slot, limit)
      index.visited[slot] = true
      actual
    }
    None => resource
  }
  let plan = compile_node(index, doc, resource, document, path, depth, limit)
  if slots.contains(path) {
    let slot = slots[path]
    index.nodes[slot] = Located(resource, plan)
    index.visited[slot] = true
  }
  Located(resource, plan)
}

///|
// Bound annotation/const/enum traversal too, not just schema-node recursion.
fn check_schema_json(
  value : Json,
  path : String,
  depth : Int32,
  limit : Int32,
) -> Unit raise CompileError {
  if depth > limit {
    raise CompileError::DepthLimit(limit)
  }
  match value {
    Number(_, ..) =>
      if ExactNumber::of_json(value) is None {
        invalid_keyword(path, "invalid JSON number or numeric representation")
      }
    Object(fields) =>
      for name, child in fields {
        check_schema_json(child, pointer_step(path, name), depth + 1, limit)
      }
    Array(values) =>
      for index, child in values {
        check_schema_json(
          child,
          pointer_step(path, index.to_string()),
          depth + 1,
          limit,
        )
      }
    _ => ()
  }
}

///|
fn invalid_keyword(path : String, reason : String) -> Unit raise CompileError {
  raise InvalidKeyword(path~, reason~)
}

///|
fn compile_number(
  value : Json,
  path : String,
) -> ExactNumber raise CompileError {
  match ExactNumber::of_json(value) {
    Some(number) => number
    None => {
      invalid_keyword(path, "expected a finite JSON number")
      ExactNumber::from_double(0.0)
    }
  }
}

///|
fn compile_count(
  fields : Map[String, Json],
  key : String,
  path : String,
) -> Int32? raise CompileError {
  match fields.get(key) {
    None => None
    Some(value) => {
      let location = pointer_step(path, key)
      let number = compile_number(value, location)
      let integer = number.is_integer() catch {
        _ =>
          raise InvalidKeyword(
            path=location,
            reason="invalid numeric representation",
          )
      }
      let sign = number.sign() catch {
        _ =>
          raise InvalidKeyword(
            path=location,
            reason="invalid numeric representation",
          )
      }
      if !integer || sign < 0 {
        invalid_keyword(location, "expected a nonnegative integer")
      }
      let ordering = number.compare(ExactNumber::from_double(2147483647.0)) catch {
        _ =>
          raise InvalidKeyword(
            path=location,
            reason="invalid numeric representation",
          )
      }
      if ordering > 0 {
        raise UnsupportedKeyword(
          path=location,
          keyword="count exceeds supported range",
        )
      }
      match value {
        Number(d, ..) => Some(d.to_int())
        _ => None
      }
    }
  }
}

///|
fn compile_strings(
  value : Json,
  path : String,
) -> Array[String] raise CompileError {
  guard value is Array(values) else {
    invalid_keyword(path, "expected an array of unique strings")
    return []
  }
  let strings : Array[String] = []
  let seen : Set[String] = Set([])
  for item in values {
    guard item is String(text) else {
      invalid_keyword(path, "expected an array of unique strings")
      continue
    }
    if seen.contains(text) {
      invalid_keyword(path, "duplicate string")
    }
    seen.add(text)
    strings.push(text)
  }
  strings
}

///|
fn compile_type(value : Json, path : String) -> ValueType raise CompileError {
  match value {
    "null" => NullType
    "boolean" => BooleanType
    "number" => NumberType
    "integer" => IntegerType
    "string" => StringType
    "array" => ArrayType
    "object" => ObjectType
    _ => {
      invalid_keyword(path, "unknown JSON Schema type")
      NullType
    }
  }
}

///|
fn optional_node(
  index : RefIndex,
  doc : Int32,
  resource : Int32,
  fields : Map[String, Json],
  key : String,
  path : String,
  depth : Int32,
  limit : Int32,
) -> Plan? raise CompileError {
  fields
  .get(key)
  .map(value => {
    compile_into(
      index,
      doc,
      resource,
      value,
      pointer_step(path, key),
      depth + 1,
      limit,
    )
  })
}

///|
fn compile_branches(
  index : RefIndex,
  doc : Int32,
  resource : Int32,
  value : Json,
  path : String,
  depth : Int32,
  limit : Int32,
) -> Array[Plan] raise CompileError {
  guard value is Array(branches) && !branches.is_empty() else {
    invalid_keyword(path, "expected a nonempty array of schemas")
    return []
  }
  branches.mapi((position, schema) => {
    compile_into(
      index,
      doc,
      resource,
      schema,
      pointer_step(path, position.to_string()),
      depth + 1,
      limit,
    )
  })
}

///|
fn compile_pattern_at(
  value : Json,
  path : String,
) -> PatternSupport raise CompileError {
  guard value is String(text) else {
    invalid_keyword(path, "expected a pattern string")
    return compile_pattern("")
  }
  let support = compile_pattern(text)
  match support {
    Unsupported(reason~) =>
      raise UnsupportedPattern(path~, pattern=text, reason~)
    Supported(_) => support
  }
}

///|
fn compile_node(
  index : RefIndex,
  doc : Int32,
  resource : Int32,
  document : Json,
  path : String,
  depth : Int32,
  limit : Int32,
) -> Plan raise CompileError {
  if depth > limit {
    raise CompileError::DepthLimit(limit)
  }
  match document {
    True => return Accept
    False => return Reject(path)
    Object(_) => ()
    _ => {
      invalid_keyword(path, "schema must be an object or boolean")
      return Accept
    }
  }
  guard document is Object(original_fields) else { return Accept }
  let fields = dialect_fields(
    original_fields,
    index.resources[resource].dialect,
  )
  let rules : Array[Rule] = []
  // `unevaluated*` assertions must observe every other keyword's evaluation,
  // so their rules compile like the rest but append after all of them.
  let mut unevaluated_properties : (Plan, String)? = None
  let mut unevaluated_items : (Plan, String)? = None
  for key, value in fields {
    let location = pointer_step(path, key)
    match key {
      "$schema" => {
        guard value is String(uri) else {
          invalid_keyword(location, "expected a dialect URI")
          continue
        }
        ignore(resolve_dialect(index, uri, location, limit))
      }
      "$ref" => {
        guard value is String(reference) else {
          invalid_keyword(location, "expected a reference URI string")
          continue
        }
        rules.push(
          Ref(resolve_ref(index, resource, reference, location, limit)),
        )
      }
      "$dynamicRef" => {
        guard value is String(reference) else {
          invalid_keyword(location, "expected a reference URI string")
          continue
        }
        let (slot, name) = resolve_dynamic_ref(
          index, resource, reference, location, limit,
        )
        if name is Some(_) { index.track_dynamic_scope = true }
        rules.push(DynamicRef(slot, name))
      }
      // Resource identity keywords were validated and registered by the
      // resource scan (`scan_resource`) before compilation started.
      "$id" | "$anchor" | "$dynamicAnchor" => ()
      // Declarations affect schemas that select this document as a metaschema,
      // not the semantics of this document while it is itself being validated.
      "$vocabulary" => ()
      "unevaluatedProperties" => {
        index.collect_evaluated = true
        unevaluated_properties = Some(
          (
            compile_into(
              index,
              doc,
              resource,
              value,
              location,
              depth + 1,
              limit,
            ),
            location,
          ),
        )
      }
      "unevaluatedItems" => {
        index.collect_evaluated = true
        unevaluated_items = Some(
          (
            compile_into(
              index,
              doc,
              resource,
              value,
              location,
              depth + 1,
              limit,
            ),
            location,
          ),
        )
      }
      "$defs" => {
        guard value is Object(definitions) else {
          invalid_keyword(location, "expected a map of schemas")
          continue
        }
        for name, schema in definitions {
          ignore(
            compile_into(
              index,
              doc,
              resource,
              schema,
              pointer_step(location, name),
              depth + 1,
              limit,
            ),
          )
        }
      }
      "type" => {
        let types = match value {
          Array(_) => {
            let names = compile_strings(value, location)
            if names.is_empty() {
              invalid_keyword(location, "type array must not be empty")
            }
            names.map(name => compile_type(Json::string(name), location))
          }
          _ => [compile_type(value, location)]
        }
        rules.push(Types(types, location))
      }
      "const" => rules.push(Constant(owned_json(value), location))
      "enum" => {
        // 2020-12 only requires an array: entries SHOULD be unique and the
        // array MAY be empty, in which case no instance ever matches.
        guard value is Array(values) else {
          invalid_keyword(location, "expected an array of enum values")
          continue
        }
        rules.push(Enumeration(values.map(owned_json), location))
      }
      "minimum" | "exclusiveMinimum" =>
        rules.push(
          Lower(
            compile_number(value, location),
            key == "exclusiveMinimum",
            location,
          ),
        )
      "maximum" | "exclusiveMaximum" =>
        rules.push(
          Upper(
            compile_number(value, location),
            key == "exclusiveMaximum",
            location,
          ),
        )
      "multipleOf" => {
        let divisor = compile_number(value, location)
        let sign = divisor.sign() catch {
          _ =>
            raise InvalidKeyword(
              path=location,
              reason="invalid numeric representation",
            )
        }
        if sign <= 0 {
          invalid_keyword(location, "multipleOf must be strictly positive")
        }
        rules.push(Multiple(divisor, location))
      }
      "pattern" =>
        rules.push(Pattern(compile_pattern_at(value, location), location))
      "allOf" =>
        rules.push(
          All(
            compile_branches(
              index, doc, resource, value, location, depth, limit,
            ),
            location,
          ),
        )
      "anyOf" =>
        rules.push(
          Any(
            compile_branches(
              index, doc, resource, value, location, depth, limit,
            ),
            location,
          ),
        )
      "oneOf" =>
        rules.push(
          One(
            compile_branches(
              index, doc, resource, value, location, depth, limit,
            ),
            location,
          ),
        )
      "not" =>
        rules.push(
          Negate(
            compile_into(
              index,
              doc,
              resource,
              value,
              location,
              depth + 1,
              limit,
            ),
            location,
          ),
        )
      "title"
      | "description"
      | "$comment"
      | "format"
      | "contentEncoding"
      | "contentMediaType" =>
        if !(value is String(_)) {
          invalid_keyword(location, "expected a string annotation")
        }
      "deprecated" | "readOnly" | "writeOnly" =>
        if value != Json::boolean(true) && value != Json::boolean(false) {
          invalid_keyword(location, "expected a boolean annotation")
        }
      "examples" =>
        if !(value is Array(_)) {
          invalid_keyword(location, "expected an array annotation")
        }
      "contentSchema" =>
        ignore(
          compile_into(index, doc, resource, value, location, depth + 1, limit),
        )
      _ => ()
    }
  }
  let min_length = compile_count(fields, "minLength", path)
  let max_length = compile_count(fields, "maxLength", path)
  if min_length is Some(_) || max_length is Some(_) {
    rules.push(StringLength(min_length, max_length, path))
  }
  // Compile conditional arms even when `if` is absent: their shapes must
  // still be legal, although their validation effects are then ignored.
  let condition = optional_node(
    index, doc, resource, fields, "if", path, depth, limit,
  )
  let consequent = optional_node(
    index, doc, resource, fields, "then", path, depth, limit,
  )
  let alternate = optional_node(
    index, doc, resource, fields, "else", path, depth, limit,
  )
  if condition is Some(predicate) {
    rules.push(Conditional(predicate, consequent, alternate))
  }
  let properties : Map[String, Plan] = Map([])
  if fields.get("properties") is Some(value) {
    guard value is Object(schemas) else {
      invalid_keyword(
        pointer_step(path, "properties"),
        "expected a map of schemas",
      )
      return Accept
    }
    for name, schema in schemas {
      properties.set(
        name,
        compile_into(
          index,
          doc,
          resource,
          schema,
          pointer_step(pointer_step(path, "properties"), name),
          depth + 1,
          limit,
        ),
      )
    }
  }
  let patterns : Array[(PatternSupport, Plan)] = []
  if fields.get("patternProperties") is Some(value) {
    guard value is Object(schemas) else {
      invalid_keyword(
        pointer_step(path, "patternProperties"),
        "expected a map of schemas",
      )
      return Accept
    }
    for expression, schema in schemas {
      let location = pointer_step(
        pointer_step(path, "patternProperties"),
        expression,
      )
      patterns.push(
        (
          compile_pattern_at(Json::string(expression), location),
          compile_into(index, doc, resource, schema, location, depth + 1, limit),
        ),
      )
    }
  }
  let required = match fields.get("required") {
    Some(value) => compile_strings(value, pointer_step(path, "required"))
    None => []
  }
  let dependent_required : Array[(String, Array[String])] = []
  if fields.get("dependentRequired") is Some(value) {
    guard value is Object(dependencies) else {
      invalid_keyword(pointer_step(path, "dependentRequired"), "expected a map")
      return Accept
    }
    for name, names in dependencies {
      dependent_required.push(
        (
          name,
          compile_strings(
            names,
            pointer_step(pointer_step(path, "dependentRequired"), name),
          ),
        ),
      )
    }
  }
  let dependent_schemas : Array[(String, Plan)] = []
  if fields.get("dependentSchemas") is Some(value) {
    guard value is Object(dependencies) else {
      invalid_keyword(pointer_step(path, "dependentSchemas"), "expected a map")
      return Accept
    }
    for name, schema in dependencies {
      dependent_schemas.push(
        (
          name,
          compile_into(
            index,
            doc,
            resource,
            schema,
            pointer_step(pointer_step(path, "dependentSchemas"), name),
            depth + 1,
            limit,
          ),
        ),
      )
    }
  }
  let object_plan : ObjectPlan = {
    path,
    properties,
    patterns,
    required,
    dependent_required,
    dependent_schemas,
    additional: optional_node(
      index, doc, resource, fields, "additionalProperties", path, depth, limit,
    ),
    names: optional_node(
      index, doc, resource, fields, "propertyNames", path, depth, limit,
    ),
    minimum: compile_count(fields, "minProperties", path),
    maximum: compile_count(fields, "maxProperties", path),
  }
  if [
      "properties", "patternProperties", "required", "additionalProperties", "propertyNames",
      "minProperties", "maxProperties", "dependentRequired", "dependentSchemas",
    ].any(key => fields.contains(key)) {
    rules.push(Objects(object_plan))
  }
  let prefix = match fields.get("prefixItems") {
    None => []
    Some(value) =>
      compile_branches(
        index,
        doc,
        resource,
        value,
        pointer_step(path, "prefixItems"),
        depth,
        limit,
      )
  }
  let unique = match fields.get("uniqueItems") {
    Some(True) => true
    None | Some(False) => false
    _ => {
      invalid_keyword(pointer_step(path, "uniqueItems"), "expected a boolean")
      false
    }
  }
  let array_plan : ArrayPlan = {
    path,
    prefix,
    unique,
    items: optional_node(
      index, doc, resource, fields, "items", path, depth, limit,
    ),
    contains: optional_node(
      index, doc, resource, fields, "contains", path, depth, limit,
    ),
    min_contains: compile_count(fields, "minContains", path).unwrap_or(1),
    max_contains: compile_count(fields, "maxContains", path),
    minimum: compile_count(fields, "minItems", path),
    maximum: compile_count(fields, "maxItems", path),
  }
  if [
      "prefixItems", "items", "contains", "minContains", "maxContains", "minItems",
      "maxItems", "uniqueItems",
    ].any(key => fields.contains(key)) {
    rules.push(Arrays(array_plan))
  }
  if unevaluated_properties is Some((plan, location)) {
    rules.push(UnevaluatedProperties(plan, location))
  }
  if unevaluated_items is Some((plan, location)) {
    rules.push(UnevaluatedItems(plan, location))
  }
  Rules(rules)
}
