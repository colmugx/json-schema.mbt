///|
fn resource_compile_error(
  f : () -> @json-schema.Schema raise @json-schema.CompileError,
) -> Unit raise {
  try f() catch {
    @json-schema.CompileError::InvalidKeyword(..) => ()
    error => raise error
  } noraise {
    _ => fail("expected InvalidKeyword")
  }
}

///|
test "resources: retrieval aliases, nested ids and resource-relative pointers" {
  let external : Json = {
    "$id": "https://example.com/canonical/root",
    "$defs": {
      "inner": { "$id": "inner", "$anchor": "value", "type": "integer" },
    },
  }
  let resources : Map[String, Json] = {
    "https://example.com/fetched": external,
  }
  for
    reference in [
      "https://example.com/fetched#/$defs/inner", "https://example.com/canonical/root#/$defs/inner",
      "https://example.com/canonical/inner#value",
    ] {
    let schema = @json-schema.Schema::compile({ "$ref": reference }, resources~)
    assert_true(schema.valid(Json::number(4)))
    let faults = schema.faults(Json::string("no"))
    assert_false(faults.is_empty())
    assert_eq(faults[0].schema_uri, Some("https://example.com/fetched"))
    assert_eq(faults[0].schema_path, "/$defs/inner/type")
  }
}

///|
test "resources: base URI query and nested paths resolve relative refs" {
  let resources : Map[String, Json] = {
    "https://example.com/a/target?version=2": { "const": 5 },
  }
  let schema = @json-schema.Schema::compile(
    { "$ref": "../target?version=2" },
    base_uri="https://example.com/a/b/root?old=1",
    resources~,
  )
  assert_true(schema.valid(Json::number(5)))
  assert_false(schema.valid(Json::number(6)))
}

///|
test "resources: mutually recursive resources compile without expansion" {
  let resources : Map[String, Json] = {
    "urn:example:a": {
      "type": "object",
      "properties": { "next": { "$ref": "urn:example:b" } },
    },
    "urn:example:b": {
      "type": "object",
      "properties": { "next": { "$ref": "urn:example:a" } },
    },
  }
  let schema = @json-schema.Schema::compile(
    { "$ref": "urn:example:a" },
    resources~,
  )
  assert_true(schema.valid({ "next": { "next": {} } }))
  assert_false(schema.valid({ "next": { "next": false } }))
}

///|
test "resources: owned plans do not observe registry or constant mutations" {
  let payload : Map[String, Json] = { "x": 1 }
  let remote : Map[String, Json] = { "const": Json::object(payload) }
  let resources : Map[String, Json] = {
    "urn:example:value": Json::object(remote),
  }
  let schema = @json-schema.Schema::compile(
    { "$ref": "urn:example:value" },
    resources~,
  )
  payload["x"] = 2
  remote["const"] = false
  resources["urn:example:value"] = false
  assert_true(schema.valid({ "x": 1 }))
  assert_false(schema.valid({ "x": 2 }))
}

///|
test "resources: annotation data never defines identities or anchors" {
  let schema = @json-schema.Schema::compile({
    "const": { "$id": 3, "$anchor": 4 },
  })
  assert_true(schema.valid({ "$id": 3, "$anchor": 4 }))
  resource_compile_error(() => {
    @json-schema.Schema::compile({
      "examples": [{ "$id": "urn:example:hidden", "type": "integer" }],
      "$ref": "urn:example:hidden",
    })
  })
  let resources : Map[String, Json] = {
    "urn:example:unused": {
      "$schema": "http://json-schema.org/draft-07/schema#",
      "$id": "#legacy",
    },
  }
  assert_true(
    @json-schema.Schema::compile(true, resources~).valid(Json::null()),
  )
}

///|
test "resources: lazy pointer targets retain the nearest schema resource" {
  let document : Json = {
    "$id": "https://example.com/root",
    "$defs": {
      "inner": {
        "$id": "branch/",
        "custom": { "$ref": "leaf" },
        "$ref": "#/custom",
      },
    },
    "$ref": "branch/",
  }
  let resources : Map[String, Json] = {
    "https://example.com/branch/leaf": { "type": "string" },
  }
  let schema = @json-schema.Schema::compile(document, resources~)
  assert_true(schema.valid(Json::string("yes")))
  assert_false(schema.valid(Json::number(3)))
  let pointer = @json-schema.Schema::compile({
    "$defs": { "a": { "const": 1 } },
    "$ref": "#%2F$defs%2Fa",
  })
  assert_true(pointer.valid(Json::number(1)))
  assert_false(pointer.valid(Json::number(2)))
}

///|
test "resources: dynamic refs fall back to static anchors and refs can target dynamic anchors" {
  let resources : Map[String, Json] = {
    "urn:example:static": { "$anchor": "node", "const": 5 },
    "urn:example:dynamic": { "$dynamicAnchor": "node", "type": "string" },
  }
  let fallback = @json-schema.Schema::compile(
    { "$dynamicAnchor": "node", "$dynamicRef": "urn:example:static#node" },
    resources~,
  )
  assert_true(fallback.valid(Json::number(5)))
  assert_false(fallback.valid(Json::number(6)))
  let static_ref = @json-schema.Schema::compile(
    { "$ref": "urn:example:dynamic#node" },
    resources~,
  )
  assert_true(static_ref.valid(Json::string("yes")))
  assert_false(static_ref.valid(Json::number(5)))
}

///|
test "resources: dynamically selected targets under inactive applicators compile" {
  let resources : Map[String, Json] = {
    "urn:example:inner": { "$dynamicAnchor": "node", "$dynamicRef": "#node" },
  }
  let schema = @json-schema.Schema::compile(
    {
      "$id": "urn:example:outer",
      "then": { "$dynamicAnchor": "node", "const": 5 },
      "$ref": "urn:example:inner",
    },
    resources~,
  )
  assert_true(schema.valid(Json::number(5)))
  assert_false(schema.valid(Json::number(6)))
  assert_false(schema.faults(Json::number(6)).is_empty())
}

///|
test "resources: nonproductive dynamic recursion raises a traversal error" {
  let schema = @json-schema.Schema::compile({
    "$dynamicAnchor": "loop",
    "$dynamicRef": "#loop",
  })
  for diagnostics in [false, true] {
    try {
      if diagnostics {
        schema.faults(Json::null(), max_depth=8).is_empty()
      } else {
        schema.valid(Json::null(), max_depth=8)
      }
    } catch {
      @json-schema.EvaluationError::DepthLimit(limit) => assert_eq(limit, 8)
      error => raise error
    } noraise {
      _ => fail("expected dynamic recursion depth limit")
    }
  }
}

///|
test "resources: invalid and unresolved identities fail explicitly" {
  for
    document in [
      ({ "$id": 3 } : Json),
      { "$id": "relative-without-base" },
      { "$id": "http://[x]/invalid" },
      { "$id": "https://example.com/a#fragment" },
      { "$anchor": "1bad" },
      { "$anchor": "has space" },
      { "$defs": { "a": { "$anchor": "same" }, "b": { "$anchor": "same" } } },
      {
        "$id": "urn:example:root",
        "$defs": { "a": { "$id": "urn:example:root" } },
      },
      { "$ref": "https://example.com/not-loaded" },
      { "$ref": "#unknown" },
      { "$ref": "http://example.com/%GG" },
      { "$ref": "http://[broken/path" },
      { "$ref": "http://example.com:bad/path" },
      { "$ref": "invalid space" },
    ] {
    resource_compile_error(() => @json-schema.Schema::compile(document))
  }
  resource_compile_error(() => {
    @json-schema.Schema::compile(true, base_uri="relative/path")
  })
  let resources : Map[String, Json] = {
    "HTTP://EXAMPLE.COM:80/path": true,
    "http://example.com/path": false,
  }
  resource_compile_error(() => @json-schema.Schema::compile(true, resources~))
}
