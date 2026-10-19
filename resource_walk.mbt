///|
fn schema_children(
  fields : Map[String, Json],
  pointer : String,
) -> Array[(String, Json)] {
  let children : Array[(String, Json)] = []
  for key, value in fields {
    let path = pointer_step(pointer, key)
    match key {
      "prefixItems" | "allOf" | "anyOf" | "oneOf" =>
        if value is Array(schemas) {
          for position, schema in schemas {
            children.push((pointer_step(path, position.to_string()), schema))
          }
        }
      "properties" | "patternProperties" | "dependentSchemas" | "$defs" =>
        if value is Object(schemas) {
          for name, schema in schemas {
            children.push((pointer_step(path, name), schema))
          }
        }
      "items"
      | "contains"
      | "propertyNames"
      | "if"
      | "then"
      | "else"
      | "not"
      | "additionalProperties"
      | "unevaluatedProperties"
      | "unevaluatedItems"
      | "contentSchema" => children.push((path, value))
      _ => ()
    }
  }
  children
}

///|
// Discover aliases without registering unrelated documents' resource namespaces.
// Loading one matching source later performs the actual validation/collision check.
fn document_has_identity(
  index : RefIndex,
  value : Json,
  base : String?,
  identity : String,
  inherited : Dialect,
) -> Bool {
  guard value is Object(fields) else { return false }
  let current = match fields.get("$id") {
    Some(String(id)) => Some(canonical_uri(base, id))
    _ => base
  }
  if current == Some(identity) {
    return true
  }
  let dialect = discovery_dialect(index, fields, inherited)
  for entry in schema_children(dialect_fields(fields, dialect), "") {
    let (_, child) = entry
    if document_has_identity(index, child, current, identity, dialect) {
      return true
    }
  }
  false
}
