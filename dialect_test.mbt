///|
fn dialect_registry(declaration : Json) -> Map[String, Json] {
  {
    "urn:test:dialect": {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "$vocabulary": declaration,
    },
  }
}

///|
test "dialect: supported optional vocabularies still execute assertions" {
  let resources = dialect_registry({
    "https://json-schema.org/draft/2020-12/vocab/core": true,
    "https://json-schema.org/draft/2020-12/vocab/validation": false,
    "urn:test:unknown": false,
  })
  let schema = @json-schema.Schema::compile(
    { "$schema": "urn:test:dialect", "type": "integer" },
    resources~,
  )
  assert_true(schema.valid(Json::number(1)))
  assert_false(schema.valid(Json::string("1")))
  assert_false(schema.faults(Json::string("1")).is_empty())
}

///|
test "dialect: URI fragments preserve vocabulary identity and root anchor selection" {
  let resources = dialect_registry({
    "https://json-schema.org/draft/2020-12/vocab/core": true,
    "https://json-schema.org/draft/2020-12/vocab/validation#extension": false,
  })
  let ignored = @json-schema.Schema::compile(
    { "$schema": "urn:test:dialect", "type": "integer" },
    resources~,
  )
  assert_true(ignored.valid(Json::string("not an integer")))
  resources["urn:test:anchored"] = {
    "$anchor": "dialect",
    "$vocabulary": {
      "https://json-schema.org/draft/2020-12/vocab/core": true,
      "https://json-schema.org/draft/2020-12/vocab/validation": true,
    },
  }
  let selected = @json-schema.Schema::compile(
    { "$schema": "urn:test:anchored#dialect", "type": "integer" },
    resources~,
  )
  assert_true(selected.valid(Json::number(1)))
  assert_false(selected.valid(Json::string("no")))
}

///|
test "dialect: absent validation ignores malformed assertions but keeps applicators" {
  let resources = dialect_registry({
    "https://json-schema.org/draft/2020-12/vocab/core": true,
    "https://json-schema.org/draft/2020-12/vocab/applicator": true,
  })
  let schema = @json-schema.Schema::compile(
    {
      "$schema": "urn:test:dialect",
      "required": false,
      "type": 42,
      "properties": { "bad": false, "number": { "minimum": "not a number" } },
    },
    resources~,
  )
  assert_true(schema.valid({ "number": 1 }))
  assert_false(schema.valid({ "bad": 1 }))
  assert_true(schema.valid(Json::null()))
}

///|
test "dialect: disabled schema-bearing keywords do not register hidden identities" {
  let resources = dialect_registry({
    "https://json-schema.org/draft/2020-12/vocab/core": true,
  })
  let schema = @json-schema.Schema::compile(
    {
      "$schema": "urn:test:dialect",
      "properties": {
        "ignored": { "$id": 5, "$schema": "relative", "$anchor": false },
      },
      "items": 6,
    },
    resources~,
  )
  assert_true(schema.valid({ "anything": 1 }))
  assert_true(schema.valid([1, 2]))
  resources["urn:test:shadow"] = {
    "$schema": "urn:test:dialect",
    "$id": "urn:test:shadow",
    "properties": { "hidden": { "$id": "urn:test:target" } },
  }
  resources["urn:test:real"] = { "$id": "urn:test:target", "type": "number" }
  let target = @json-schema.Schema::compile(
    { "$ref": "urn:test:target" },
    resources~,
  )
  assert_true(target.valid(Json::number(1)))
  assert_false(target.valid(Json::string("no")))
}

///|
test "dialect: vocabulary is read from the metaschema not the application schema" {
  let schema = @json-schema.Schema::compile({
    "$vocabulary": { "https://json-schema.org/draft/2020-12/vocab/core": true },
    "type": "string",
  })
  assert_false(schema.valid(Json::number(1)))
  assert_true(
    @json-schema.Schema::compile({ "$vocabulary": 42 }).valid(Json::null()),
  )
  let meta : Json = { "$vocabulary": { "urn:test:unknown-required": true } }
  assert_true(@json-schema.Schema::compile(meta).valid(Json::null()))
  let resources : Map[String, Json] = { "urn:test:meta": meta }
  try
    @json-schema.Schema::compile({ "$schema": "urn:test:meta" }, resources~)
  catch {
    @json-schema.CompileError::UnsupportedVocabulary(dialect~, vocabulary~) => {
      assert_eq(dialect, "urn:test:meta")
      assert_eq(vocabulary, "urn:test:unknown-required")
    }
    error => raise error
  } noraise {
    _ => fail("unknown required vocabulary must fail")
  }
}

///|
test "dialect: declarations are not inherited through metaschema refs" {
  let resources = dialect_registry({
    "https://json-schema.org/draft/2020-12/vocab/core": true,
  })
  resources["urn:test:derived"] = { "$ref": "urn:test:dialect" }
  let schema = @json-schema.Schema::compile(
    { "$schema": "urn:test:derived", "type": "string" },
    resources~,
  )
  assert_true(schema.valid(Json::string("yes")))
  assert_false(schema.valid(Json::number(1)))
}

///|
test "dialect: metaschema structural constraints are enforced recursively" {
  let resources : Map[String, Json] = {
    "urn:test:strict-meta": {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "$dynamicAnchor": "meta",
      "$ref": "https://json-schema.org/draft/2020-12/schema",
      "required": ["type"],
    },
  }
  let valid = @json-schema.Schema::compile(
    {
      "$schema": "urn:test:strict-meta",
      "type": "object",
      "properties": { "x": { "type": "string" } },
    },
    resources~,
  )
  assert_true(valid.valid({ "x": "ok" }))
  resource_compile_error(() => {
    @json-schema.Schema::compile(
      { "$schema": "urn:test:strict-meta", "properties": {} },
      resources~,
    )
  })
  resource_compile_error(() => {
    @json-schema.Schema::compile(
      {
        "$schema": "urn:test:strict-meta",
        "type": "object",
        "properties": { "x": {} },
      },
      resources~,
    )
  })
}

///|
test "dialect: embedded inheritance and explicit external resource defaults are isolated" {
  let resources = dialect_registry({
    "https://json-schema.org/draft/2020-12/vocab/core": true,
    "https://json-schema.org/draft/2020-12/vocab/applicator": true,
  })
  resources["urn:test:external"] = { "type": "string" }
  let schema = @json-schema.Schema::compile(
    {
      "$schema": "urn:test:dialect",
      "properties": {
        "inherited": { "$id": "urn:test:embedded", "type": "string" },
        "switched": {
          "$id": "urn:test:switched",
          "$schema": "https://json-schema.org/draft/2020-12/schema",
          "type": "string",
        },
        "external": { "$ref": "urn:test:external" },
      },
    },
    resources~,
  )
  for
    entry in [
      (({ "inherited": 1, "switched": "yes", "external": "yes" } : Json), true),
      ({ "switched": 1 }, false),
      ({ "external": 1 }, false),
    ] {
    let (value, expected) = entry
    assert_eq(schema.valid(value), expected)
    assert_eq(schema.faults(value).is_empty(), expected)
  }
  resource_compile_error(() => {
    @json-schema.Schema::compile({
      "properties": {
        "x": { "$schema": "https://json-schema.org/draft/2020-12/schema" },
      },
    })
  })
}

///|
test "dialect: invalid declarations and unsupported format assertions are explicit errors" {
  for
    declaration in [
      (false : Json),
      {},
      { "https://json-schema.org/draft/2020-12/vocab/core": false },
      { "https://json-schema.org/draft/2020-12/vocab/core": 1 },
      {
        "https://json-schema.org/draft/2020-12/vocab/core": true,
        "relative": false,
      },
    ] {
    let resources = dialect_registry(declaration)
    resource_compile_error(() => {
      @json-schema.Schema::compile(
        { "$schema": "urn:test:dialect" },
        resources~,
      )
    })
  }
  let resources = dialect_registry({
    "https://json-schema.org/draft/2020-12/vocab/core": true,
    "https://json-schema.org/draft/2020-12/vocab/format-assertion": true,
  })
  try
    @json-schema.Schema::compile({ "$schema": "urn:test:dialect" }, resources~)
  catch {
    @json-schema.CompileError::UnsupportedVocabulary(vocabulary~, ..) =>
      assert_eq(
        vocabulary, "https://json-schema.org/draft/2020-12/vocab/format-assertion",
      )
    error => raise error
  } noraise {
    _ => fail("format assertions were not implemented")
  }
}

///|
test "dialect: vocabulary declarations are restricted only when processing a metaschema" {
  let document : Json = { "$defs": { "child": { "$vocabulary": {} } } }
  ignore(@json-schema.Schema::compile(document))
  let resources : Map[String, Json] = { "urn:test:nested-meta": document }
  resource_compile_error(() => {
    @json-schema.Schema::compile(
      { "$schema": "urn:test:nested-meta" },
      resources~,
    )
  })
}

///|
test "dialect: cyclic dialect chains and reserved builtin overrides fail" {
  let resources : Map[String, Json] = {
    "urn:test:a": { "$schema": "urn:test:b" },
    "urn:test:b": { "$schema": "urn:test:a" },
  }
  resource_compile_error(() => {
    @json-schema.Schema::compile({ "$schema": "urn:test:a" }, resources~)
  })
  let resources : Map[String, Json] = {
    "https://json-schema.org/draft/2020-12/schema": {},
  }
  resource_compile_error(() => @json-schema.Schema::compile(true, resources~))
  resource_compile_error(() => {
    @json-schema.Schema::compile({
      "$id": "https://json-schema.org/draft/2020-12/schema",
      "const": 7,
    })
  })
  let resources : Map[String, Json] = { "urn:test:duplicate": false }
  resource_compile_error(() => {
    @json-schema.Schema::compile({ "$id": "urn:test:duplicate" }, resources~)
  })
}

///|
test "dialect: builtin metaschema resources validate schemas as instances" {
  let schema = @json-schema.Schema::compile({
    "$ref": "https://json-schema.org/draft/2020-12/schema",
  })
  assert_true(
    schema.valid({ "type": "string", "$defs": { "a": { "minimum": 1 } } }),
  )
  assert_false(schema.valid({ "type": "not-a-type" }))
  assert_false(schema.valid({ "$defs": { "a": { "type": 1 } } }))
}
