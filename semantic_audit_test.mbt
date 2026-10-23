///|
test "audit: bundling dynamic resources preserves recursive unevaluated semantics" {
  let tree : Json = {
    "$id": "https://example.com/audit/tree",
    "$dynamicAnchor": "node",
    "type": "object",
    "properties": {
      "value": { "type": "integer" },
      "children": { "type": "array", "items": { "$dynamicRef": "#node" } },
    },
  }
  let root : Map[String, Json] = {
    "$id": "https://example.com/audit/strict",
    "$dynamicAnchor": "node",
    "$ref": "tree",
    "unevaluatedProperties": false,
  }
  let remote = @json-schema.Schema::compile(Json::object(root), resources={
    "https://example.com/audit/tree": tree,
  })
  root["$defs"] = { "tree": tree }
  let bundled = @json-schema.Schema::compile(Json::object(root))
  for
    (instance, expected) in [
      (({} : Json), true),
      ({ "value": 1 }, true),
      ({ "value": "wrong" }, false),
      ({ "extra": 1 }, false),
      ({ "children": [{ "value": 2 }] }, true),
      ({ "children": [{ "extra": 2 }] }, false),
      ({ "children": [{ "children": [{ "value": 3 }] }] }, true),
      ({ "children": [{ "children": [{ "extra": 3 }] }] }, false),
    ] {
    assert_eq(remote.valid(instance), expected)
    assert_eq(bundled.valid(instance), expected)
    assert_eq(remote.faults(instance).is_empty(), expected)
    assert_eq(bundled.faults(instance).is_empty(), expected)
  }
}

///|
test "audit: successful anyOf annotations are independent of branch and resource order" {
  let first : Json = {
    "properties": { "a": { "type": "integer" } },
    "required": ["a"],
  }
  let second : Json = {
    "properties": { "b": { "type": "string" } },
    "required": ["b"],
  }
  for reverse in [false, true] {
    let resources : Map[String, Json] = Map([])
    let branches : Array[Json] = if reverse {
      resources["urn:audit:b"] = second
      resources["urn:audit:a"] = first
      [{ "$ref": "urn:audit:b" }, { "$ref": "urn:audit:a" }]
    } else {
      resources["urn:audit:a"] = first
      resources["urn:audit:b"] = second
      [{ "$ref": "urn:audit:a" }, { "$ref": "urn:audit:b" }]
    }
    let schema = @json-schema.Schema::compile(
      {
        "type": "object",
        "anyOf": Json::array(branches),
        "unevaluatedProperties": false,
      },
      resources~,
    )
    for
      (instance, expected) in [
        (({} : Json), false),
        ({ "a": 1 }, true),
        ({ "b": "yes" }, true),
        ({ "a": 1, "b": "yes" }, true),
        ({ "a": "wrong", "b": "yes" }, false),
        ({ "a": 1, "b": 2 }, false),
        ({ "a": 1, "extra": 2 }, false),
      ] {
      assert_eq(schema.valid(instance), expected)
      assert_eq(schema.faults(instance).is_empty(), expected)
    }
  }
}
