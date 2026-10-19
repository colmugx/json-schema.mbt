///|
fn evaluated_case(
  source : String,
  instance : String,
  expected : Bool,
) -> Unit raise {
  let schema = compiled(source)
  let value = @json-schema.parse(instance)
  for _ in 0..<2 {
    assert_eq(schema.valid(value), expected)
    assert_eq(schema.faults(value).is_empty(), expected)
  }
}

///|
test "unevaluated: keyword order and all successful anyOf branches" {
  for
    source in [
      (
        #|{"unevaluatedProperties":false,"anyOf":[{"properties":{"x":true}},{"properties":{"y":true}}]}
      ),
      (
        #|{"anyOf":[{"properties":{"x":true}},{"properties":{"y":true}}],"unevaluatedProperties":false}
      ),
    ] {
    evaluated_case(source, "{\"x\":1,\"y\":2}", true)
    evaluated_case(source, "{\"x\":1,\"y\":2,\"z\":3}", false)
    evaluated_case(source, "{}", true)
    evaluated_case(source, "[]", true)
  }
}

///|
test "unevaluated: failed speculative branches do not publish marks" {
  evaluated_case(
    (
      #|{"anyOf":[{"properties":{"x":true},"required":["missing"]},{"properties":{"y":true}}],"unevaluatedProperties":false}
    ),
    "{\"x\":1,\"y\":2}",
    false,
  )
  evaluated_case(
    (
      #|{"oneOf":[{"properties":{"x":true},"required":["missing"]},{"properties":{"y":true}}],"unevaluatedProperties":false}
    ),
    "{\"y\":2}",
    true,
  )
  evaluated_case(
    (
      #|{"not":{"properties":{"x":true},"required":["missing"]},"unevaluatedProperties":false}
    ),
    "{\"x\":1}",
    false,
  )
}

///|
test "unevaluated: parent and child locations have separate marks" {
  let source =
    #|{"properties":{"child":{"properties":{"x":true},"unevaluatedProperties":false}},"unevaluatedProperties":false}
  evaluated_case(source, "{\"child\":{\"x\":1}}", true)
  evaluated_case(source, "{\"child\":{},\"x\":1}", false)
  evaluated_case(source, "{\"child\":{\"child\":1}}", false)
}

///|
test "unevaluated: conditional and dependent schema annotations" {
  let source =
    #|{"if":{"properties":{"kind":{"const":"x"}},"required":["kind"]},"then":{"properties":{"x":true}},"else":{"properties":{"y":true}},"unevaluatedProperties":false}
  evaluated_case(source, "{\"kind\":\"x\",\"x\":1}", true)
  evaluated_case(source, "{\"y\":1}", true)
  evaluated_case(source, "{\"kind\":\"other\",\"y\":1}", false)
  evaluated_case(
    (
      #|{"properties":{"trigger":true},"dependentSchemas":{"trigger":{"properties":{"extra":true}}},"unevaluatedProperties":false}
    ),
    "{\"trigger\":1,\"extra\":2}",
    true,
  )
}

///|
test "unevaluated: additionalProperties omission differs from true" {
  evaluated_case("{\"unevaluatedProperties\":false}", "{\"x\":1}", false)
  evaluated_case(
    "{\"additionalProperties\":true,\"unevaluatedProperties\":false}", "{\"x\":1}",
    true,
  )
  evaluated_case(
    (
      #|{"allOf":[{"patternProperties":{"^x":true}}],"unevaluatedProperties":{"type":"integer"}}
    ),
    "{\"x\":null,\"other\":3}",
    true,
  )
}

///|
test "unevaluated: contains marks individual indices rather than a prefix" {
  let source =
    #|{"contains":{"type":"integer"},"unevaluatedItems":{"type":"string"}}
  evaluated_case(source, "[\"a\",2,\"b\",4]", true)
  evaluated_case(source, "[\"a\",2,false]", false)
  evaluated_case(
    (
      #|{"contains":false,"minContains":0,"unevaluatedItems":false}
    ),
    "[1]",
    false,
  )
  evaluated_case(
    (
      #|{"contains":false,"minContains":0,"unevaluatedItems":false}
    ),
    "[]",
    true,
  )
}

///|
test "unevaluated: prefix items and items distinguish absence from true" {
  evaluated_case(
    (
      #|{"unevaluatedItems":false,"allOf":[{"prefixItems":[true]}]}
    ),
    "[1]",
    true,
  )
  evaluated_case(
    (
      #|{"unevaluatedItems":false,"allOf":[{"prefixItems":[true]}]}
    ),
    "[1,2]",
    false,
  )
  evaluated_case("{\"items\":true,\"unevaluatedItems\":false}", "[1,2]", true)
  evaluated_case(
    (
      #|{"anyOf":[{"prefixItems":[true]},{"prefixItems":[true,true]}],"unevaluatedItems":false}
    ),
    "[1,2]",
    true,
  )
}

///|
test "unevaluated: marks cross resource refs and dynamic scope" {
  let tree = @json-schema.parse(
    (
      #|{"$id":"https://example.com/tree","$dynamicAnchor":"node","type":"object","properties":{"data":true,"children":{"type":"array","items":{"$dynamicRef":"#node"}}}}
    ),
  )
  let schema = @json-schema.Schema::compile(
    @json-schema.parse(
      (
        #|{"$id":"https://example.com/strict","$dynamicAnchor":"node","$ref":"tree","unevaluatedProperties":false}
      ),
    ),
    resources=Map::from_array([("https://example.com/tree", tree)]),
  )
  for
    entry in [
      ("{\"data\":1,\"children\":[{\"data\":2}]}", true),
      ("{\"data\":1,\"children\":[{\"typo\":2}]}", false),
      ("{\"typo\":1}", false),
    ] {
    let (source, expected) = entry
    let instance = @json-schema.parse(source)
    assert_eq(schema.valid(instance), expected)
    assert_eq(schema.faults(instance).is_empty(), expected)
  }
}
