///|
test "metaschema: format assertion resource is available without network access" {
  let uri = "https://json-schema.org/draft/2020-12/meta/format-assertion"
  assert_true(builtin_metaschema_uri(uri))
  let document = builtin_metaschema(uri).unwrap()
  let schema = Schema::compile(document)
  assert_true(schema.valid({ "format": "ipv4" }))
  assert_true(schema.valid(Json::boolean(true)))
  assert_false(schema.valid({ "format": 12 }))
  assert_false(builtin_metaschema_uri("https://example.test/unknown"))
  assert_true(builtin_metaschema("https://example.test/unknown") is None)
}
