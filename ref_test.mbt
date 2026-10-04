///|
fn ref_schema(text : String) -> @json-schema.Schema raise {
  @json-schema.Schema::compile(@json-schema.parse(text))
}

///|
test "$defs pointer refs validate and report target schema paths" {
  let schema = compiled(
    "{\"$defs\":{\"positive\":{\"type\":\"integer\",\"minimum\":1}},\"properties\":{\"a\":{\"$ref\":\"#/$defs/positive\"}}}",
  )
  assert_true(schema.valid(@json-schema.parse("{\"a\":3}")))
  assert_false(schema.valid(@json-schema.parse("{\"a\":0}")))
  assert_false(schema.valid(@json-schema.parse("{\"a\":\"x\"}")))
  let failures = schema.faults(@json-schema.parse("{\"a\":-2}"))
  assert_eq(failures.length(), 1)
  assert_eq(failures[0].instance_path, "/a")
  assert_eq(failures[0].schema_path, "/$defs/positive/minimum")
  assert_eq(failures[0].keyword, "minimum")
}

///|
test "pointer escapes and percent escapes address awkward member names" {
  let schema = compiled(
    "{\"$defs\":{\"tilde~field\":{\"type\":\"integer\"},\"slash/field\":{\"type\":\"integer\"},\"percent%field\":{\"type\":\"integer\"},\"quote\\\"field\":{\"type\":\"integer\"}},\"properties\":{\"tilde\":{\"$ref\":\"#/$defs/tilde~0field\"},\"slash\":{\"$ref\":\"#/$defs/slash~1field\"},\"percent\":{\"$ref\":\"#/$defs/percent%25field\"},\"quote\":{\"$ref\":\"#/$defs/quote%22field\"}}}",
  )
  let good = "{\"tilde\":1,\"slash\":2,\"percent\":3,\"quote\":4}"
  assert_true(schema.valid(@json-schema.parse(good)))
  let bad = "{\"tilde\":\"x\",\"slash\":2,\"percent\":3,\"quote\":4}"
  assert_false(schema.valid(@json-schema.parse(bad)))
}

///|
test "percent decoding happens before pointer unescaping" {
  // %7E0 decodes to the pointer escape ~0, which then unescapes to ~.
  let schema = compiled(
    "{\"$defs\":{\"a~b\":{\"type\":\"string\"}},\"properties\":{\"a~b\":{\"$ref\":\"#/%24defs/a%7E0b\"}}}",
  )
  assert_true(schema.valid(@json-schema.parse("{\"a~b\":\"x\"}")))
  assert_false(schema.valid(@json-schema.parse("{\"a~b\":1}")))
}

///|
test "percent-encoded UTF-8 fragments decode as bytes" {
  let schema = compiled(
    "{\"$defs\":{\"café\":{\"type\":\"string\"}},\"properties\":{\"café\":{\"$ref\":\"#/$defs/caf%C3%A9\"}}}",
  )
  assert_true(schema.valid(@json-schema.parse("{\"café\":\"x\"}")))
  assert_false(schema.valid(@json-schema.parse("{\"café\":1}")))
}

///|
test "empty fragment, empty reference and #/ all reach the root" {
  let schema = compiled(
    "{\"type\":\"object\",\"properties\":{\"a\":{\"$ref\":\"#\"},\"b\":{\"$ref\":\"\"}}}",
  )
  assert_true(schema.valid(@json-schema.parse("{\"a\":{},\"b\":{}}")))
  assert_false(schema.valid(@json-schema.parse("{\"a\":1,\"b\":{}}")))
  let named = compiled(
    "{\"$defs\":{\"root\":{\"type\":\"string\"}},\"$ref\":\"#/$defs/root\"}",
  )
  assert_true(named.valid(@json-schema.parse("\"x\"")))
}

///|
test "forward and chained references resolve to later positions" {
  let schema = compiled(
    "{\"properties\":{\"a\":{\"$ref\":\"#/$defs/one\"}},\"$defs\":{\"one\":{\"$ref\":\"#/$defs/two\"},\"two\":{\"const\":42}}}",
  )
  assert_true(schema.valid(@json-schema.parse("{\"a\":42}")))
  assert_false(schema.valid(@json-schema.parse("{\"a\":41}")))
}

///|
test "repeated references share one compiled target" {
  let schema = compiled(
    "{\"$defs\":{\"flag\":{\"const\":true}},\"properties\":{\"a\":{\"$ref\":\"#/$defs/flag\"},\"b\":{\"$ref\":\"#/$defs/flag\"}}}",
  )
  assert_true(schema.valid(@json-schema.parse("{\"a\":true,\"b\":true}")))
  assert_false(schema.valid(@json-schema.parse("{\"a\":true,\"b\":false}")))
}

///|
test "adjacent keywords evaluate alongside $ref" {
  let schema = compiled(
    "{\"$defs\":{\"str\":{\"type\":\"string\"}},\"$ref\":\"#/$defs/str\",\"maxLength\":2}",
  )
  assert_true(schema.valid(@json-schema.parse("\"ab\"")))
  assert_false(schema.valid(@json-schema.parse("\"abc\"")))
  assert_false(schema.valid(@json-schema.parse("3")))
}

///|
test "boolean schema and array positions are valid targets" {
  let never = compiled(
    "{\"$defs\":{\"no\":false,\"yes\":true},\"properties\":{\"a\":{\"$ref\":\"#/$defs/no\"},\"b\":{\"$ref\":\"#/$defs/yes\"}}}",
  )
  assert_false(never.valid(@json-schema.parse("{\"a\":1,\"b\":2}")))
  assert_true(never.valid(@json-schema.parse("{\"b\":2}")))
  let failures = never.faults(@json-schema.parse("{\"a\":1,\"b\":2}"))
  assert_eq(failures[0].schema_path, "/$defs/no")
  assert_eq(failures[0].keyword, "false")
  let positional = compiled(
    "{\"prefixItems\":[{\"type\":\"integer\"}],\"items\":{\"$ref\":\"#/prefixItems/0\"}}",
  )
  assert_true(positional.valid(@json-schema.parse("[1,2,3]")))
  assert_false(positional.valid(@json-schema.parse("[1,\"x\"]")))
}

///|
test "productive recursive object and array refs terminate" {
  let tree = compiled(
    "{\"type\":\"object\",\"required\":[\"value\"],\"properties\":{\"value\":{\"type\":\"integer\"},\"children\":{\"type\":\"array\",\"items\":{\"$ref\":\"#\"}}}}",
  )
  let ok = @json-schema.parse(
    "{\"value\":1,\"children\":[{\"value\":2,\"children\":[]},{\"value\":3}]}",
  )
  assert_true(tree.valid(ok))
  let bad = @json-schema.parse(
    "{\"value\":1,\"children\":[{\"value\":\"no\"}]}",
  )
  assert_false(tree.valid(bad))
}

///|
test "cyclic references exhaust the evaluation budget as an error" {
  let definitions : Map[String, Json] = Map([])
  for index in 0..<256 {
    definitions[index.to_string()] = if index == 255 {
      Json::boolean(true)
    } else {
      ({ "$ref": "#/$defs/" + (index + 1).to_string() } : Json)
    }
  }
  let chained : Json = {
    "$ref": "#/$defs/0",
    "$defs": Json::object(definitions),
  }
  try @json-schema.Schema::compile(chained, max_depth=32) catch {
    @json-schema.CompileError::DepthLimit(_) => ()
    error => raise error
  } noraise {
    _ => fail("flat reference chains must obey the compile budget")
  }
  let schema = compiled("{\"properties\":{\"a\":{\"$ref\":\"#\"}}}")
  try
    schema.valid(@json-schema.parse("{\"a\":{\"a\":{\"a\":1}}}"), max_depth=4)
  catch {
    @json-schema.EvaluationError::DepthLimit(_) => ()
    error => raise error
  } noraise {
    _ => fail("expected evaluation depth limit")
  }
  // A finite instance within budget still validates productively.
  assert_true(schema.valid(@json-schema.parse("{\"a\":{\"a\":{\"a\":1}}}")))
}

///|
test "empty enum is a valid 2020-12 schema that rejects every instance" {
  // Official suite draft2020-12/enum.json group "empty enum": the 2020-12
  // meta-schema only requires an array, so [] matches nothing.
  let schema = compiled("{\"enum\":[]}")
  for instance in ["\"foo\"", "42", "null", "{}", "[]", "false"] {
    assert_false(schema.valid(@json-schema.parse(instance)))
  }
}

///|
test "malformed and unresolvable references fail compilation" {
  for
    source in [
      "{\"$ref\":\"#/missing\"}", "{\"$defs\":{\"x\":5},\"$ref\":\"#/$defs/x\"}",
      "{\"$defs\":{\"x\":{}},\"$ref\":\"#/$defs/x/y\"}", "{\"$defs\":{\"x\":[]},\"$ref\":\"#/$defs/x/0\"}",
      "{\"$defs\":{\"x\":{}},\"$ref\":\"#/$defs/x~2y\"}", "{\"$defs\":{\"x\":{}},\"$ref\":\"#/$defs/x~\"}",
      "{\"$ref\":\"#/%2\"}", "{\"$ref\":\"#/%GG\"}", "{\"$ref\":\"#/%C3\"}", "{\"$ref\":5}",
      "{\"$ref\":\"#/prefixItems/01\",\"prefixItems\":[true]}", "{\"$ref\":\"#/prefixItems/-\",\"prefixItems\":[true]}",
      "{\"$ref\":\"#/prefixItems/2147483647\",\"prefixItems\":[true]}", "{\"$ref\":\"#/prefixItems/2147483648\",\"prefixItems\":[true]}",
      "{\"$ref\":\"#/prefixItems/9999999999999999999999999\",\"prefixItems\":[true]}",
    ] {
    try ref_schema(source) catch {
      @json-schema.CompileError::InvalidKeyword(..) => ()
      error => raise error
    } noraise {
      _ => fail("expected InvalidKeyword: " + source)
    }
  }
}

///|
test "external, anchor-style and identityful references stay unsupported" {
  for
    entry in [
      ("$ref", "{\"$ref\":\"http://localhost:1234/draft2020-12/tree\"}"),
      ("$ref", "{\"$ref\":\"other.json#/foo\"}"),
      ("$ref", "{\"$ref\":\"urn:example:tree\"}"),
      ("$anchor", "{\"$ref\":\"#anchor\"}"),
      ("$anchor", "{\"$ref\":\"#%66oo\"}"),
    ] {
    let (expected, source) = entry
    try ref_schema(source) catch {
      @json-schema.CompileError::UnsupportedKeyword(keyword~, ..) =>
        assert_eq(keyword, expected)
      error => raise error
    } noraise {
      _ => fail("expected UnsupportedKeyword: " + source)
    }
  }
  for
    entry in [
      ("$id", "{\"$id\":\"https://example.com/a\",\"type\":\"string\"}"),
      ("$anchor", "{\"$anchor\":\"meta\",\"type\":\"string\"}"),
      ("$dynamicRef", "{\"$dynamicRef\":\"#meta\"}"),
      ("$dynamicAnchor", "{\"$dynamicAnchor\":\"meta\"}"),
      ("unevaluatedProperties", "{\"unevaluatedProperties\":false}"),
    ] {
    let (expected, source) = entry
    try ref_schema(source) catch {
      @json-schema.CompileError::UnsupportedKeyword(keyword~, ..) =>
        assert_eq(keyword, expected)
      error => raise error
    } noraise {
      _ => fail("expected UnsupportedKeyword: " + source)
    }
  }
}
