///|
/// One indexed source document: the compiled root document or a registry
/// entry. `slots` maps the canonical escaped pointer of every position to its
/// arena slot; `identity` is the URI the document was supplied under (the
/// base URI or the registry key). It is the `document_uri` of the document's
/// resources and the dereferencing companion of schema pointers.
priv struct Doc {
  root : Json
  identity : String?
  slots : Map[String, Int32]
  // Cached documents share immutable pointer maps. Their slot numbers refer
  // to the template; map them into the private compilation arena by offset.
  slot_offset : Int32
}

///|
fn Doc::slot(self : Doc, path : String) -> Int32? {
  self.slots.get(path).map(slot => slot + self.slot_offset)
}

///|
/// Assign arena slots to every position of one document, including positions
/// the keyword walk never visits (annotation payloads, unknown extension
/// keywords), so lazily referenced pointer targets compile through the same
/// entry point. `resource_of` is refined afterwards by `scan_resource`.
fn index_walk(
  index : RefIndex,
  doc : Int32,
  value : Json,
  pointer : String,
  depth : Int32,
  limit : Int32,
) -> Unit raise CompileError {
  if depth > limit {
    raise CompileError::DepthLimit(limit)
  }
  if value is (Object(_) | True | False) {
    let slot = index.nodes.length()
    index.docs[doc].slots[pointer] = slot
    index.paths.push(pointer)
    index.targets.push(value)
    index.visited.push(false)
    index.doc_of.push(doc)
    index.resource_of.push(-1)
    index.nodes.push(Pending)
  }
  match value {
    Object(fields) =>
      for name, child in fields {
        index_walk(
          index,
          doc,
          child,
          pointer_step(pointer, name),
          depth + 1,
          limit,
        )
      }
    Array(values) =>
      for position, child in values {
        index_walk(
          index,
          doc,
          child,
          pointer_step(pointer, position.to_string()),
          depth + 1,
          limit,
        )
      }
    _ => ()
  }
}

///|
/// A reusable, immutable snapshot of a registry's validated documents and
/// preindexed schema positions. The snapshot never contains compiled plans or
/// mutable reference-resolution state.
///
/// Build this once when compiling many independent roots against the same
/// resources. Mutation of the caller's original JSON or map after creation
/// cannot affect the registry; each compilation independently owns its plans.
pub struct SchemaRegistry {
  priv template : RefIndex
  priv max_depth : Int32
}

///|
/// Validate and preindex a registry exactly once. All resources are validated,
/// including ones no compiled root eventually references.
pub fn SchemaRegistry::new(
  resources : Map[String, Json],
  max_depth~ : Int32 = 128,
) -> SchemaRegistry raise CompileError {
  if max_depth < 1 { raise CompileError::DepthLimit(max_depth) }
  let template = empty_ref_index()
  let seen : Set[String] = Set([])
  for key, value in resources {
    check_schema_json(value, "", 0, max_depth)
    validate_document_uri(key, "resources")
    let identity = canonical_document_uri(key)
    if seen.contains(identity) || builtin_metaschema_uri(identity) {
      invalid_keyword("resources", "duplicate retrieval URI: " + identity)
    }
    seen.add(identity)
    // Copy before indexing: the caller may mutate its original tree later.
    ignore(add_document(template, owned_json(value), Some(identity), max_depth))
  }
  { template, max_depth, }
}

///|
// Share immutable source pointer maps across compilations and map their slot
// indices into private per-compilation arenas by an offset. Never reuse
// visited, resource_of or compiled Plan state from another invocation.
fn append_registry_template(index : RefIndex, cached : SchemaRegistry) -> Unit {
  let doc_offset = index.docs.length()
  let slot_offset = index.nodes.length()
  // SAFETY/ownership: only index_walk mutates Doc.slots, and it is called
  // exclusively by add_document on fresh documents. Cached maps remain
  // immutable and are shared read-only between independent compilations.
  for original in cached.template.docs {
    index.docs.push({
      root: original.root,
      identity: original.identity,
      slots: original.slots,
      slot_offset,
    })
  }
  for i in 0..<cached.template.paths.length() {
    index.paths.push(cached.template.paths[i])
    index.targets.push(cached.template.targets[i])
    index.visited.push(false)
    index.doc_of.push(cached.template.doc_of[i] + doc_offset)
    index.resource_of.push(-1)
    index.nodes.push(Pending)
  }
}

///|
fn add_document(
  index : RefIndex,
  value : Json,
  identity : String?,
  limit : Int32,
) -> Int32 raise CompileError {
  let doc = index.docs.length()
  index.docs.push({ root: value, identity, slots: Map([]), slot_offset: 0, })
  index_walk(index, doc, value, "", 0, limit)
  doc
}

///|
/// Pre-compilation indexing over the root document and every supplied
/// registry document. Resource namespaces are registered when their document
/// is referenced, so unrelated legacy documents do not change the active dialect.
/// Schema-aware discovery still finds embedded canonical `$id` aliases.
fn empty_ref_index() -> RefIndex {
  {
    docs: [],
    paths: [],
    targets: [],
    visited: [],
    doc_of: [],
    resource_of: [],
    reference_depth: 0,
    nodes: [],
    resources: [],
    sites: [],
    registry: Map([]),
    anchors: Map([]),
    collect_evaluated: false,
    track_dynamic_scope: false,
    dialects: Map([]),
    resolving_dialects: Set([]),
  }
}

///|
fn index_program(
  document : Json,
  base_uri : String?,
  resources : Map[String, Json]?,
  limit : Int32,
  cached : SchemaRegistry?,
) -> RefIndex raise CompileError {
  let index = empty_ref_index()
  match base_uri {
    Some(uri) => validate_document_uri(uri, "base_uri")
    None => ()
  }
  // The root document is indexed first, so its root resource is resource 0.
  let doc = add_document(
    index,
    document,
    base_uri.map(canonical_document_uri),
    limit,
  )
  match resources {
    Some(entries) => {
      let seen : Set[String] = Set([])
      for key, entry in entries {
        validate_document_uri(key, "resources")
        let identity = canonical_document_uri(key)
        if seen.contains(identity) ||
          builtin_metaschema_uri(identity) ||
          base_uri.map(canonical_document_uri) == Some(identity) {
          invalid_keyword("resources", "duplicate retrieval URI: " + identity)
        }
        seen.add(identity)
        ignore(add_document(index, entry, Some(identity), limit))
      }
    }
    None => ()
  }
  if cached is Some(snapshot) {
    if snapshot.max_depth != limit {
      // A preindexed tree's recursion bound must match the compile bound.
      raise CompileError::DepthLimit(limit)
    }
    for source in snapshot.template.docs {
      if source.identity == base_uri.map(canonical_document_uri) {
        invalid_keyword(
          "resources",
          "duplicate retrieval URI: " + source.identity.unwrap(),
        )
      }
    }
    append_registry_template(index, snapshot)
  }
  let supplied = index.docs.length()
  scan_resource(index, doc, document, "", 0, true, 0, limit)
  for doc in 1..<supplied {
    if index.docs[doc].identity is Some(identity) &&
      index.registry.get(identity) is Some(resource) {
      let (owner, _) = index.sites[resource]
      if owner != doc {
        invalid_keyword("resources", "duplicate retrieval URI: " + identity)
      }
    }
  }
  index
}

///|
/// Walk one schema position for resource semantics only; compilation happens
/// later in `compile_into`. An object position carrying `$id` opens a schema
/// resource whose canonical URI rebases every relative reference beneath it;
/// `$anchor`/`$dynamicAnchor` register plain-name fragments in the resource
/// that is current here. The walk descends exclusively through keywords that
/// own subschemas, so resource identity never leaks into annotation or
/// `const` data: an `$id` inside a JSON constant is opaque content.
fn scan_resource(
  index : RefIndex,
  doc : Int32,
  value : Json,
  pointer : String,
  resource : Int32,
  root_position : Bool,
  depth : Int32,
  limit : Int32,
) -> Unit raise CompileError {
  if depth > limit {
    raise CompileError::DepthLimit(limit)
  }
  let inherited = if root_position {
    standard_dialect()
  } else {
    index.resources[resource].dialect
  }
  let dialect = if value is Object(fields) &&
    fields.get("$schema") is Some(declaration) {
    if !root_position && !fields.contains("$id") {
      invalid_keyword(
        pointer_step(pointer, "$schema"),
        "$schema is only allowed at a resource root",
      )
    }
    guard declaration is String(uri) else {
      invalid_keyword(
        pointer_step(pointer, "$schema"),
        "expected a dialect URI",
      )
      return
    }
    resolve_dialect(index, uri, pointer_step(pointer, "$schema"), limit)
  } else {
    inherited
  }
  let current = match value {
    Object(fields) =>
      match fields.get("$id") {
        Some(id_value) =>
          claim_id_resource(
            index,
            doc,
            pointer,
            if root_position {
              index.docs[doc].identity
            } else {
              index.resources[resource].uri
            },
            id_value,
            dialect,
          )
        None =>
          if root_position {
            // 2020-12 core 9.1.1: without a root $id, the document identity
            // is the canonical URI of the root schema resource.
            make_resource(
              index,
              doc,
              pointer,
              index.docs[doc].identity,
              [],
              pointer_step(pointer, "$id"),
              dialect,
            )
          } else {
            resource
          }
      }
    _ =>
      if root_position {
        // A boolean (or, for registry entries, non-schema) document root
        // still claims the resource namespace it was supplied under.
        make_resource(
          index,
          doc,
          pointer,
          index.docs[doc].identity,
          [],
          pointer_step(pointer, "$id"),
          dialect,
        )
      } else {
        resource
      }
  }
  if value is (True | False) {
    assign_resource_slot(index, doc, pointer, current)
    return
  }
  guard value is Object(fields) else {
    // Non-schema roots get no slots; referencing one fails explicitly.
    return
  }
  assign_resource_slot(index, doc, pointer, current)
  if fields.get("$anchor") is Some(name) {
    register_anchor(
      index,
      current,
      name,
      false,
      doc,
      pointer,
      pointer_step(pointer, "$anchor"),
    )
  }
  if fields.get("$dynamicAnchor") is Some(name) {
    register_anchor(
      index,
      current,
      name,
      true,
      doc,
      pointer,
      pointer_step(pointer, "$dynamicAnchor"),
    )
  }
  for entry in schema_children(dialect_fields(fields, dialect), pointer) {
    let (location, child) = entry
    scan_resource(index, doc, child, location, current, false, depth + 1, limit)
  }
}

///|
/// Register the resource a `$id` opens: its canonical identity plus, when
/// different, the enclosing document identity as a retrieval alias.
fn claim_id_resource(
  index : RefIndex,
  doc : Int32,
  pointer : String,
  base : String?,
  id_value : Json,
  dialect : Dialect,
) -> Int32 raise CompileError {
  let location = pointer_step(pointer, "$id")
  guard id_value is String(text) else {
    invalid_keyword(location, "expected a URI-reference string")
    return 0
  }
  validate_uri_reference(text, location)
  match split_at_first(text, '#') {
    (_, Some(fragment)) =>
      if fragment != "" {
        invalid_keyword(location, "$id must not contain a non-empty fragment")
        return 0
      }
    (_, None) => ()
  }
  let identity = canonical_uri(base, text)
  if Uri::parse(identity).scheme is None {
    invalid_keyword(location, "relative $id requires an absolute base URI")
  }
  let aliases : Array[String] = []
  if pointer == "" && base is Some(key) && key != identity {
    aliases.push(key)
  }
  if builtin_metaschema(identity) is Some(expected) &&
    index.docs[doc].root != expected {
    invalid_keyword(
      location,
      "reserved built-in metaschema identity: " + identity,
    )
  }
  make_resource(index, doc, pointer, Some(identity), aliases, location, dialect)
}

///|
fn make_resource(
  index : RefIndex,
  doc : Int32,
  pointer : String,
  uri : String?,
  aliases : Array[String],
  location : String,
  dialect : Dialect,
) -> Int32 raise CompileError {
  match uri {
    Some(identity) =>
      if index.registry.contains(identity) {
        invalid_keyword(location, "duplicate resource identity: " + identity)
      }
    None => ()
  }
  for retrieval in aliases {
    if index.registry.contains(retrieval) {
      invalid_keyword(location, "duplicate resource identity: " + retrieval)
    }
  }
  let resource = index.resources.length()
  index.resources.push({
    uri,
    document_uri: match index.docs[doc].identity {
      Some(identity) => Some(identity)
      None =>
        if pointer == "" {
          uri
        } else {
          index.resources[index.resource_of[index.docs[doc].slot("").unwrap()]].document_uri
        }
    },
    dynamic_anchors: Map([]),
    dialect,
  })
  index.sites.push((doc, pointer))
  match uri {
    Some(identity) => index.registry[identity] = resource
    None => ()
  }
  for retrieval in aliases {
    index.registry[retrieval] = resource
  }
  resource
}

///|
fn ensure_slot_resource(
  index : RefIndex,
  slot : Int32,
  limit : Int32,
) -> Int32 raise CompileError {
  if index.resource_of[slot] >= 0 {
    return index.resource_of[slot]
  }
  let doc = index.doc_of[slot]
  let pointer = index.paths[slot]
  let mut inherited = 0
  let mut nearest = -1
  for ancestor, raw_candidate in index.docs[doc].slots {
    let candidate = raw_candidate + index.docs[doc].slot_offset
    if index.resource_of[candidate] >= 0 &&
      ancestor.length() > nearest &&
      (ancestor == "" || pointer.has_prefix(ancestor + "/")) {
      nearest = ancestor.length()
      inherited = index.resource_of[candidate]
    }
  }
  scan_resource(
    index,
    doc,
    index.targets[slot],
    pointer,
    inherited,
    false,
    0,
    limit,
  )
  index.resource_of[slot]
}

///|
fn assign_resource_slot(
  index : RefIndex,
  doc : Int32,
  pointer : String,
  resource : Int32,
) -> Unit {
  match index.docs[doc].slot(pointer) {
    Some(slot) => index.resource_of[slot] = resource
    // Unreachable: every object/boolean position receives a slot.
    None => ()
  }
}

///|
/// Register a plain-name fragment in the resource current at its position.
/// Static and dynamic anchors share one namespace: 2020-12 core leaves
/// duplicate fragment names within a resource undefined, so compilation
/// rejects them explicitly instead of picking a winner.
fn register_anchor(
  index : RefIndex,
  resource : Int32,
  value : Json,
  dynamic : Bool,
  doc : Int32,
  pointer : String,
  location : String,
) -> Unit raise CompileError {
  guard value is String(text) else {
    invalid_keyword(location, "expected a plain-name fragment string")
    return
  }
  if !plain_name(text) {
    invalid_keyword(
      location, "fragment name must start with a letter or underscore and contain only letters, digits, '-', '_' or '.'",
    )
  }
  let dynamic_anchors = index.resources[resource].dynamic_anchors
  let static_anchors = match index.anchors.get(resource) {
    Some(existing) => existing
    None => {
      let fresh : Map[String, Int32] = Map([])
      index.anchors[resource] = fresh
      fresh
    }
  }
  if static_anchors.contains(text) || dynamic_anchors.contains(text) {
    invalid_keyword(location, "duplicate fragment name in resource: " + text)
  }
  let slot = match index.docs[doc].slot(pointer) {
    Some(slot) => slot
    // Unreachable: anchors are scanned on object schema positions.
    None => 0
  }
  if dynamic {
    dynamic_anchors[text] = slot
  } else {
    static_anchors[text] = slot
  }
}
