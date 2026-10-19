///|
priv struct Dialect {
  uri : String
  active : Set[String]
  meta_slot : Int32?
}

///|
fn standard_dialect() -> Dialect {
  {
    uri: "https://json-schema.org/draft/2020-12/schema",
    active: Set([
      "applicator", "validation", "unevaluated", "meta-data", "format-annotation",
      "content",
    ]),
    meta_slot: None,
  }
}

///|
fn vocabulary_family(uri : String) -> String? {
  let prefix = "https://json-schema.org/draft/2020-12/vocab/"
  if uri.has_prefix(prefix) {
    let family = uri[prefix.length():].to_owned()
    if [
        "core", "applicator", "validation", "unevaluated", "meta-data", "format-annotation",
        "content",
      ].contains(family) {
      return Some(family)
    }
  }
  None
}

///|
fn keyword_family(keyword : String) -> String? {
  match keyword {
    "properties"
    | "patternProperties"
    | "additionalProperties"
    | "propertyNames"
    | "dependentSchemas"
    | "prefixItems"
    | "items"
    | "contains"
    | "allOf"
    | "anyOf"
    | "oneOf"
    | "not"
    | "if"
    | "then"
    | "else" => Some("applicator")
    "type"
    | "const"
    | "enum"
    | "minimum"
    | "maximum"
    | "exclusiveMinimum"
    | "exclusiveMaximum"
    | "multipleOf"
    | "minLength"
    | "maxLength"
    | "pattern"
    | "required"
    | "dependentRequired"
    | "minProperties"
    | "maxProperties"
    | "minItems"
    | "maxItems"
    | "uniqueItems"
    | "minContains"
    | "maxContains" => Some("validation")
    "unevaluatedProperties" | "unevaluatedItems" => Some("unevaluated")
    "title"
    | "description"
    | "default"
    | "deprecated"
    | "readOnly"
    | "writeOnly"
    | "examples" => Some("meta-data")
    "format" => Some("format-annotation")
    "contentEncoding" | "contentMediaType" | "contentSchema" => Some("content")
    _ => None
  }
}

///|
fn dialect_fields(
  fields : Map[String, Json],
  dialect : Dialect,
) -> Map[String, Json] {
  if dialect.active.length() == 6 {
    return fields
  }
  let active : Map[String, Json] = Map([])
  for key, value in fields {
    match keyword_family(key) {
      Some(family) => if dialect.active.contains(family) { active[key] = value }
      None => active[key] = value
    }
  }
  active
}

///|
fn load_resource(
  index : RefIndex,
  identity : String,
  path : String,
  limit : Int32,
  as_dialect~ : Bool = false,
) -> Int32 raise CompileError {
  if index.registry.get(identity) is Some(resource) {
    return resource
  }
  let mut candidate : Int32? = None
  for doc, source in index.docs {
    if source.identity == Some(identity) ||
      document_has_identity(
        index,
        source.root,
        source.identity,
        identity,
        standard_dialect(),
      ) {
      if candidate is Some(_) {
        invalid_keyword(
          path,
          "ambiguous supplied resource identity: " + identity,
        )
      }
      candidate = Some(doc)
    }
  }
  let doc = match candidate {
    Some(doc) => doc
    None =>
      match builtin_metaschema(identity) {
        Some(document) => add_document(index, document, Some(identity), limit)
        None => {
          if as_dialect {
            raise UnknownDialect(identity)
          }
          invalid_keyword(path, "no supplied schema resource: " + identity)
          0
        }
      }
  }
  scan_resource(index, doc, index.docs[doc].root, "", 0, true, 0, limit)
  match index.registry.get(identity) {
    Some(resource) => resource
    None => {
      invalid_keyword(path, "resource identity was not registered: " + identity)
      0
    }
  }
}

///|
fn dialect_identifier(text : String) -> String {
  let uri = Uri::parse(text).normalize()
  match uri.fragment {
    Some(fragment) if fragment != "" => uri.identity() + "#" + fragment
    _ => uri.identity()
  }
}

///|
fn validate_meta_locations(
  index : RefIndex,
  doc : Int32,
  value : Json,
  path : String,
  inherited : Dialect,
  is_root : Bool,
  depth : Int32,
  limit : Int32,
) -> Unit raise CompileError {
  if depth > limit {
    raise CompileError::DepthLimit(limit)
  }
  guard value is Object(fields) else { return }
  if !is_root && !fields.contains("$id") && fields.contains("$vocabulary") {
    invalid_keyword(
      pointer_step(path, "$vocabulary"),
      "$vocabulary is only allowed at a metaschema resource root",
    )
  }
  let dialect = match index.docs[doc].slots.get(path) {
    Some(slot) if index.resource_of[slot] >= 0 =>
      index.resources[index.resource_of[slot]].dialect
    _ => inherited
  }
  for entry in schema_children(dialect_fields(fields, dialect), path) {
    let (child_path, child) = entry
    validate_meta_locations(
      index,
      doc,
      child,
      child_path,
      dialect,
      false,
      depth + 1,
      limit,
    )
  }
}

///|
fn resolve_dialect(
  index : RefIndex,
  identifier : String,
  path : String,
  limit : Int32,
) -> Dialect raise CompileError {
  validate_uri_reference(identifier, path)
  if Uri::parse(identifier).scheme is None {
    invalid_keyword(path, "dialect URI must be absolute")
  }
  let uri = dialect_identifier(identifier)
  if uri == standard_dialect().uri {
    return standard_dialect()
  }
  if index.dialects.get(uri) is Some(dialect) {
    return dialect
  }
  if index.resolving_dialects.contains(uri) {
    invalid_keyword(path, "cyclic dialect declaration: " + uri)
  }
  if index.resolving_dialects.length() >= limit {
    raise CompileError::DepthLimit(limit)
  }
  index.resolving_dialects.add(uri)
  defer ignore(index.resolving_dialects.remove(uri))
  let resource = load_resource(
    index,
    canonical_document_uri(uri),
    path,
    limit,
    as_dialect=true,
  )
  let (doc, pointer) = index.sites[resource]
  let slot = match Uri::parse(uri).fragment {
    Some(fragment) => resolve_ref(index, resource, "#" + fragment, path, limit)
    None => resource_root_slot(index, doc, pointer, path)
  }
  let (_, root_pointer) = index.sites[index.resource_of[slot]]
  if root_pointer != index.paths[slot] {
    invalid_keyword(path, "$schema must identify a metaschema resource root")
  }
  validate_meta_locations(
    index,
    index.doc_of[slot],
    index.targets[slot],
    index.paths[slot],
    index.resources[index.resource_of[slot]].dialect,
    true,
    0,
    limit,
  )
  let mut active = standard_dialect().active
  if index.targets[slot] is Object(fields) &&
    fields.get("$vocabulary") is Some(declaration) {
    guard declaration is Object(vocabularies) else {
      invalid_keyword(path, "metaschema $vocabulary must be an object: " + uri)
      return standard_dialect()
    }
    active = Set([])
    let mut core = false
    let seen : Set[String] = Set([])
    for identifier, required in vocabularies {
      validate_uri_reference(identifier, path)
      if Uri::parse(identifier).scheme is None {
        invalid_keyword(path, "vocabulary URI must be absolute")
      }
      let vocabulary = dialect_identifier(identifier)
      if seen.contains(vocabulary) {
        invalid_keyword(
          path,
          "duplicate normalized vocabulary URI: " + vocabulary,
        )
      }
      seen.add(vocabulary)
      guard required is (True | False) else {
        invalid_keyword(
          path,
          "vocabulary requirement must be boolean: " + vocabulary,
        )
        continue
      }
      match vocabulary_family(vocabulary) {
        Some("core") => {
          if required is False {
            invalid_keyword(path, "core vocabulary must be required: " + uri)
          }
          core = true
        }
        Some(family) => active.add(family)
        None =>
          if required is True {
            raise UnsupportedVocabulary(dialect=uri, vocabulary~)
          }
      }
    }
    if !core {
      invalid_keyword(path, "metaschema $vocabulary must require core: " + uri)
    }
  }
  let dialect : Dialect = { uri, active, meta_slot: Some(slot), }
  index.dialects[uri] = dialect
  dialect
}

///|
// Discovery only selects candidate namespaces. Validation is deferred until a
// source is actually loaded; unrelated legacy dialects must not affect a call.
fn discovery_dialect(
  index : RefIndex,
  fields : Map[String, Json],
  inherited : Dialect,
) -> Dialect {
  guard fields.get("$schema") is Some(String(identifier)) else {
    return inherited
  }
  let uri = dialect_identifier(identifier)
  if uri == standard_dialect().uri {
    return standard_dialect()
  }
  if index.dialects.get(uri) is Some(dialect) {
    return dialect
  }
  for source in index.docs {
    let base = canonical_document_uri(uri)
    let identified = source.identity == Some(base) ||
      (match source.root {
        Object(meta) =>
          match meta.get("$id") {
            Some(String(id)) => canonical_uri(source.identity, id) == base
            _ => false
          }
        _ => false
      })
    if identified {
      if source.root is Object(meta) &&
        meta.get("$vocabulary") is Some(Object(vocabularies)) {
        let active : Set[String] = Set([])
        for id, value in vocabularies {
          if value is (True | False) &&
            vocabulary_family(dialect_identifier(id)) is Some(family) &&
            family != "core" {
            active.add(family)
          }
        }
        return { uri, active, meta_slot: None, }
      }
      return standard_dialect()
    }
  }
  { uri, active: Set([]), meta_slot: None, }
}
