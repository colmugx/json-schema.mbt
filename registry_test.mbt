///|
test "registry snapshot: repeated compilations stay independent of input mutation" {
  let resources : Map[String, Json] = Map([])
  resources["https://example.com/remote"] = @json-schema.parse(
    "{\"$id\":\"https://example.com/remote\",\"$defs\":{\"value\":{\"type\":\"integer\"}}}",
  )
  let registry = @json-schema.SchemaRegistry::new(resources)
  let document = @json-schema.parse(
    "{\"$ref\":\"https://example.com/remote#/$defs/value\"}",
  )
  let a = registry.compile(document)
  assert_true(a.valid(@json-schema.parse("3")))
  assert_false(a.valid(@json-schema.parse("\"x\"")))
  resources["https://example.com/remote"] = @json-schema.parse("false")
  let b = registry.compile(document)
  assert_true(b.valid(@json-schema.parse("3")))
  assert_false(b.valid(@json-schema.parse("\"x\"")))
  let legacy = @json-schema.Schema::compile(document, resources={
    "https://example.com/remote": @json-schema.parse(
      "{\"$id\":\"https://example.com/remote\",\"$defs\":{\"value\":{\"type\":\"integer\"}}}",
    ),
  })
  assert_eq(a.valid(@json-schema.parse("3")), legacy.valid(@json-schema.parse("3")))
}

///|
test "registry snapshot: separate roots select independent local references" {
  let resources : Map[String, Json] = Map([])
  resources["https://example.com/remote"] = @json-schema.parse(
    "{\"$id\":\"https://example.com/remote\",\"$defs\":{\"value\":{\"type\":\"string\"}}}",
  )
  let registry = @json-schema.SchemaRegistry::new(resources)
  let first = registry.compile(
    @json-schema.parse("{\"$ref\":\"https://example.com/remote#/$defs/value\"}"),
  )
  let second = registry.compile(@json-schema.parse("{\"type\":\"integer\"}"))
  assert_true(first.valid(@json-schema.parse("\"ok\"")))
  assert_false(second.valid(@json-schema.parse("\"ok\"")))
  assert_true(second.valid(@json-schema.parse("7")))
}

///|
test "registry snapshot: invalid unused resources remain rejected" {
  let resources : Map[String, Json] = Map([])
  resources["https://example.com/unused"] = Json::object({
    "annotation": Json::array([Json::number(0.0 / 0.0)]),
  })
  let rejected = try {
    ignore(@json-schema.SchemaRegistry::new(resources))
    false
  } catch {
    @json-schema.CompileError::InvalidKeyword(..) => true
  }
  assert_true(rejected)
}

///|
test "registry snapshot: duplicate root retrieval identity remains rejected" {
  let resources : Map[String, Json] = Map([])
  resources["https://example.com/shared"] = @json-schema.parse("true")
  let registry = @json-schema.SchemaRegistry::new(resources)
  let rejected = try {
    ignore(registry.compile(@json-schema.parse("true"), base_uri="https://example.com/shared"))
    false
  } catch {
    @json-schema.CompileError::InvalidKeyword(..) => true
  }
  assert_true(rejected)
}

///|
test "registry snapshot: preserves JSON pointer and escaped anchors" {
  let resources : Map[String, Json] = Map([])
  resources["https://example.com/references"] = @json-schema.parse(
    "{\"$id\":\"https://example.com/references\",\"$defs\":{\"a~b\":{\"type\":\"integer\"}}}",
  )
  let registry = @json-schema.SchemaRegistry::new(resources)
  let schema = registry.compile(@json-schema.parse(
    "{\"properties\":{\"n\":{\"$ref\":\"https://example.com/references#/$defs/a~0b\"}}}",
  ))
  assert_true(schema.valid(@json-schema.parse("{\"n\":3}")))
  assert_false(schema.valid(@json-schema.parse("{\"n\":\"bad\"}")))
  assert_eq(schema.faults(@json-schema.parse("{\"n\":\"bad\"}"))[0].instance_path, "/n")
}
