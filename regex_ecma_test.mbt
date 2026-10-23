///|
/// Regression cases transcribed from the pinned official conformance suite
/// (benchmark-results/official/tests/v1/optional/ecmascript-regex.json and
/// non-bmp-regex.json) at the pattern-semantics layer. The schema-level
/// `pattern`/`patternProperties` channels run the same compiled patterns; the
/// full corpus stays evidence for the conformance runner.
fn ecma_matched(pattern : String, text : String) -> Bool raise {
  @json-schema.pattern_matches(@json-schema.compile_pattern(pattern), text)
}

///|
test "ecma262: $ does not match a trailing newline" {
  assert_false(ecma_matched("^abc$", "abc\n"))
  assert_true(ecma_matched("^abc$", "abc"))
}

///|
test "ecma262: \\t is a horizontal tab escape" {
  assert_false(ecma_matched("^\\t$", "\\t"))
  assert_true(ecma_matched("^\\t$", "\t"))
}

///|
test "ecma262: control escapes \\c with upper and lower letters" {
  assert_false(ecma_matched("^\\cC$", "\\cC"))
  assert_true(ecma_matched("^\\cC$", "\u{0003}"))
  assert_false(ecma_matched("^\\cc$", "\\cc"))
  assert_true(ecma_matched("^\\cc$", "\u{0003}"))
}

///|
test "ecma262: \\d and \\D are ASCII-only" {
  assert_true(ecma_matched("^\\d$", "0"))
  assert_false(ecma_matched("^\\d$", "߀"))
  assert_false(ecma_matched("^\\D$", "0"))
  assert_true(ecma_matched("^\\D$", "߀"))
  assert_true(ecma_matched("^\\d+$", "42"))
  assert_false(ecma_matched("^\\d+$", "-%#"))
  assert_false(ecma_matched("^\\d+$", "৪২"))
  assert_true(ecma_matched("^\\p{digit}+$", "৪২"))
  assert_true(ecma_matched("^\\p{digit}+$", "42"))
}

///|
test "ecma262: \\w and \\W are ASCII word classes" {
  assert_true(ecma_matched("^\\w$", "a"))
  assert_false(ecma_matched("^\\w$", "é"))
  assert_false(ecma_matched("^\\W$", "a"))
  assert_true(ecma_matched("^\\W$", "é"))
  assert_true(ecma_matched("\\wcole", "l'ecole"))
  assert_false(ecma_matched("\\wcole", "l'école"))
  assert_false(ecma_matched("\\wcole", "L'ÉCOLE"))
}

///|
test "ecma262: \\s and \\S cover the ECMA whitespace set" {
  for
    text in [
      " ", "\t", "\u{000B}", "\u{000C}", "\u{00A0}", "\u{FEFF}", "\n", "\u{2029}",
      "\u{2003}",
    ] {
    assert_true(ecma_matched("^\\s$", text))
    assert_false(ecma_matched("^\\S$", text))
  }
  assert_false(ecma_matched("^\\s$", "\u{0001}"))
  assert_true(ecma_matched("^\\S$", "\u{0001}"))
  assert_false(ecma_matched("^\\s$", "\u{2013}"))
  assert_true(ecma_matched("^\\S$", "\u{2013}"))
}

///|
test "ecma262: \\p{Letter} keeps case-sensitive Unicode semantics" {
  assert_true(ecma_matched("\\p{Letter}cole", "l'ecole"))
  assert_true(ecma_matched("\\p{Letter}cole", "l'école"))
  assert_false(ecma_matched("\\p{Letter}cole", "L'ÉCOLE"))
  assert_false(ecma_matched("[a-z]cole", "l'école"))
  assert_true(ecma_matched("[a-z]cole", "l'ecole"))
}

///|
test "non-bmp: surrogate pairs are matched as single code points" {
  assert_true(ecma_matched("🐲*", ""))
  assert_true(ecma_matched("🐲*", "🐲"))
  assert_true(ecma_matched("🐲*", "🐲🐲"))
  assert_false(ecma_matched("^🐲$", "🐉"))
  assert_false(ecma_matched("^🐲$", "D"))
  assert_false(ecma_matched("^🐲$", "DD"))
}
