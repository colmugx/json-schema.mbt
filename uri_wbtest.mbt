///|
test "URI resolution: RFC 3986 section 5.4 normal and abnormal examples" {
  let base = Some("http://a/b/c/d;p?q")
  for
    entry in [
      ("g:h", "g:h"),
      ("g", "http://a/b/c/g"),
      ("./g", "http://a/b/c/g"),
      ("g/", "http://a/b/c/g/"),
      ("/g", "http://a/g"),
      ("//g", "http://g"),
      ("?y", "http://a/b/c/d;p?y"),
      ("g?y", "http://a/b/c/g?y"),
      ("#s", "http://a/b/c/d;p?q"),
      ("g#s", "http://a/b/c/g"),
      ("g?y#s", "http://a/b/c/g?y"),
      (";x", "http://a/b/c/;x"),
      ("g;x", "http://a/b/c/g;x"),
      ("g;x?y#s", "http://a/b/c/g;x?y"),
      ("", "http://a/b/c/d;p?q"),
      (".", "http://a/b/c/"),
      ("./", "http://a/b/c/"),
      ("..", "http://a/b/"),
      ("../", "http://a/b/"),
      ("../g", "http://a/b/g"),
      ("../..", "http://a/"),
      ("../../", "http://a/"),
      ("../../g", "http://a/g"),
      ("../../../g", "http://a/g"),
      ("../../../../g", "http://a/g"),
      ("/./g", "http://a/g"),
      ("/../g", "http://a/g"),
      ("g.", "http://a/b/c/g."),
      (".g", "http://a/b/c/.g"),
      ("g..", "http://a/b/c/g.."),
      ("..g", "http://a/b/c/..g"),
      ("./../g", "http://a/b/g"),
      ("./g/.", "http://a/b/c/g/"),
      ("g/./h", "http://a/b/c/g/h"),
      ("g/../h", "http://a/b/c/h"),
      ("g;x=1/./y", "http://a/b/c/g;x=1/y"),
      ("g;x=1/../y", "http://a/b/c/y"),
      ("g?y/./x", "http://a/b/c/g?y/./x"),
      ("g?y/../x", "http://a/b/c/g?y/../x"),
      ("g#s/./x", "http://a/b/c/g"),
      ("g#s/../x", "http://a/b/c/g"),
      ("http:g", "http:g"),
    ] {
    let (reference, expected) = entry
    assert_eq(canonical_uri(base, reference), expected)
  }
}

///|
test "URI host syntax: IPv6 and IPvFuture literals" {
  for
    host in [
      "[::]", "[::1]", "[2001:db8:0:0:0:0:0:1]", "[::ffff:192.0.2.128]", "[v1.example:host]",
    ] {
    assert_true(valid_ip_literal(host))
  }
  for
    host in [
      "[]", "[x]", "[:::]", "[1::2::3]", "[1:2:3:4:5:6:7]", "[1:2:3:4:5:6:7:8:9]",
      "[::ffff:256.0.0.1]", "[v.example]", "[v1.]", "[::1]extra",
    ] {
    assert_false(valid_ip_literal(host))
  }
}

///|
test "URI normalization: scheme host ports percent encoding and URNs" {
  assert_eq(
    canonical_document_uri("HTTPS://EXAMPLE.COM:443/a/./b/../%7e?q=%41#"),
    "https://example.com/a/~?q=A",
  )
  assert_eq(
    canonical_document_uri("http://User@EXAMPLE.COM:80/a%2fb"),
    "http://User@example.com/a%2Fb",
  )
  assert_eq(canonical_document_uri("http://[::1]:80/a"), "http://[::1]/a")
  assert_eq(
    canonical_uri(Some("urn:example:root"), "#anchor"),
    "urn:example:root",
  )
  assert_eq(
    canonical_uri(Some("http://example.com"), "leaf"),
    "http://example.com/leaf",
  )
  assert_eq(
    canonical_uri(Some("http://example.com/a?old"), "?"),
    "http://example.com/a?",
  )
  assert_eq(
    canonical_uri(Some("http://example.com/a?old"), "/b//c"),
    "http://example.com/b//c",
  )
}
