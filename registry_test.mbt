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
