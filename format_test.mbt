// Blackbox tests run against the package's public API. Use `@json-schema` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
test "format: email local part forms" {
  for
    value in [
      "joe.bloggs@example.com", "te.s.t@example.com", "te~st@example.com", "\"joe bloggs\"@example.com",
      "\"joe..bloggs\"@example.com", "\"joe@bloggs\"@example.com", "\"\"@iana.org",
      "\"\\\\\"@iana.org", "\"test\"@iana.org",
    ] {
    assert_true(@json-schema.format_valid("email", value))
  }
  for
    value in [
      "2962", "", ".test@example.com", "test.@example.com", "te..st@example.com",
      "a@b@c.org", "test\\@test@iana.org", "\"test\"test@iana.org", "\"test@iana.org",
      "test\"@iana.org", "[1.2.3.4]@iana.org", "@example.com", "joe.bloggs@", "joe bloggs@example.com",
      " a@iana.org", "a\tb@iana.org", "a,b@iana.org", "a@b(c).org", "a\u{00E9}@iana.org",
      "a\u{FF20}iana.org", "test@iana.org\n", "test@iana.org\r", "a@iana.org ",
    ] {
    assert_false(@json-schema.format_valid("email", value))
  }
}

///|
test "format: email domain and address literals" {
  for
    value in [
      "test@255.255.255.255", "test@123.com", "test@c--n.com", "test@io", "joe.bloggs@[127.0.0.1]",
      "joe.bloggs@[IPv6:::1]", "a@[ipv6:::1]",
    ] {
    assert_true(@json-schema.format_valid("email", value))
  }
  for
    value in [
      "joe.bloggs@[127.0.0.300]", "test@[1.2.3.4", "a@[]", "a@[1.2.3]", "a@[1.2.3.4.5]",
      "test@[RFC-5322-domain-literal]", "test@a[255.255.255.255]", "test@-iana.org",
      "test@iana-.com", "test@.iana.org", "test@iana.org.", "test@iana..com", "a@\u{00E9}.org",
    ] {
    assert_false(@json-schema.format_valid("email", value))
  }
}

///|
test "format: idn-email extends the local part to non-ASCII" {
  for
    value in [
      "실례@실례.테스트", "δοκιμή@example.com", "\"δοκιμή\"@example.com",
      "user@cafe\u{0301}.com", "cafe\u{0301}@example.com", "\u{0085}@example.com",
      "\u{FFFF}@example.com", "\u{1D54F}@example.com", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa@example.com",
    ] {
    assert_true(@json-schema.format_valid("idn-email", value))
  }
  for
    value in [
      "2962", "user\u{FF20}example.com", "δοκιμή@-example.com", "δοκιμή@example-.com",
      "δοκιμή@.example.com", "δοκιμή@example.com.", "δοκιμή@example..com",
      "δοκιμή@",
    ] {
    assert_false(@json-schema.format_valid("idn-email", value))
  }
}

///|
test "format: hostname is RFC 1123 LDH" {
  for
    value in [
      "www.example.com", "hostname", "host-name", "h0stn4me", "1host", "hostnam3",
      "a--b.com", "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijk.com",
    ] {
    assert_true(@json-schema.format_valid("hostname", value))
  }
  for
    value in [
      "", ".", ".example", "example.", "example\u{FF0E}com", "-hostname", "hostname-",
      "host_name", "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijkl.com",
      "\u{212A}elvin.example.com", "example.com\n",
    ] {
    assert_false(@json-schema.format_valid("hostname", value))
  }
}

///|
test "format: hostname judges an A-label by its decoded form" {
  for
    value in [
      "xn--9n2bp8q.xn--9t4b11yi5a", "xn--zca29lwxobi7a", "xn--qmbc", "xn--ll-0ea",
      "xn--wva3je", "xn--4dbc5h", "xn--4dbc8h", "xn--k8j5u", "xn--bck0j", "xn--vek778f",
      "xn--ngba1o", "xn--0-gyc", "xn--11b2ezcw70k", "xn--11b2ezcs70k", "xn--ngba5hb2804a",
    ] {
    assert_true(@json-schema.format_valid("hostname", value))
  }
  for
    value in [
      "xn--X", "xn--07jt112bpxg.xn--9t4b11yi5a", "xn--hello-txk", "xn--hello-zed",
      "xn--hello-6bf", "xn--chb89f", "xn--07jceefgh4c", "xn--al-0ea", "xn--l-fda",
      "xn--la-0ea", "xn--l-gda", "xn--S-jib3p", "xn--wva3j", "xn--A-2hc5h", "xn--5db1e",
      "xn--A-2hc8h", "xn--5db3e", "xn--defabc-k64e", "xn--vek", "xn--ngb6iyr", "xn--11b2er09f",
      "xn--02b508i", "XN--aa---o47jg78q", "xn--7a", "xn---9uc",
    ] {
    assert_false(@json-schema.format_valid("hostname", value))
  }
}

///|
test "format: idn-hostname maps separators and asserts IDNA2008 validity" {
  for
    value in [
      "실례.테스트", "a.b", "a\u{3002}b", "a\u{FF0E}b", "a\u{FF61}b", "\u{FF11}\u{FF12}\u{FF13}",
      "a\u{200B}b", "cafe\u{0301}.com", "hostname", "host-name", "xn--ihqwcrb4cv8a8dqg056pqjye",
      "xn--NXASMQ6B", "l\u{00B7}l", "\u{03B1}\u{0375}\u{03B2}", "\u{05D0}\u{05F3}\u{05D1}",
      "\u{05D0}\u{05F4}\u{05D1}", "\u{30FB}\u{3041}", "\u{30FB}\u{30A1}", "\u{30FB}\u{4E08}",
      "\u{0628}\u{0660}.\u{0628}\u{06F0}",
    ] {
    assert_true(@json-schema.format_valid("idn-hostname", value))
  }
  for
    value in [
      "", ".", "\u{3002}", "\u{FF0E}", "\u{FF61}", ".example", "example.", "example\u{3002}",
      "a..b", "-hello", "hello-", "-hello-", "-> $1.00 <--", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "\u{302E}실례.테스트", "실\u{302E}례.테스트", "\u{0640}\u{07FA}",
      "\u{3031}\u{3032}\u{3033}\u{3034}\u{3035}\u{302E}\u{302F}\u{303B}", "a\u{00B7}l",
      "\u{00B7}l", "l\u{00B7}a", "l\u{00B7}", "\u{03B1}\u{0375}S", "\u{03B1}\u{0375}",
      "A\u{05F3}\u{05D1}", "\u{05F3}\u{05D1}", "A\u{05F4}\u{05D1}", "\u{05F4}\u{05D1}",
      "def\u{30FB}abc", "\u{30FB}", "\u{0628}\u{0660}\u{06F0}", "\u{0660}\u{0661}",
      "xn--7a",
    ] {
    assert_false(@json-schema.format_valid("idn-hostname", value))
  }
}

///|
test "format: regex checks pattern syntax, not a match" {
  assert_true(@json-schema.format_valid("regex", "([abc])+\\s+$"))
  assert_true(@json-schema.format_valid("regex", "^a{2,3}$"))
  assert_false(@json-schema.format_valid("regex", "^(abc]"))
}

///|
test "format: annotation-only names never fail" {
  assert_true(@json-schema.format_valid("unknown", "anything"))
  assert_true(@json-schema.format_valid("", "anything"))
}
