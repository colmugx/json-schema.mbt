///|
test "pattern compatibility: repeated captures preserve choice, empty and scalar boundaries" {
  let bounded = @json-schema.compile_pattern("^a{257}$")
  assert_true(
    @json-schema.pattern_matches(bounded, Array::make(257, "a").join("")),
  )
  assert_false(
    @json-schema.pattern_matches(bounded, Array::make(256, "a").join("")),
  )
  for
    (pattern, text, expected) in [
      ("^(a|aa)\\1$", "aaaa", true),
      ("^(a|aa)\\1$", "aaa", false),
      ("^(a*)\\1$", "", true),
      ("^(😀+)\\1$", "😀😀", true),
      ("^(😀+)\\1$", "😀", false),
      ("^((?:ab|cd)+)\\1$", "abcdabcd", true),
      ("^(a+)\\1$", "aaba", false),
      // Leftmost-first backtracking is the engine's own behavior now; these
      // previously-compilable patterns keep their ECMA results.
      ("^(a$)\\1$", "aa", false),
      ("^(a\\b)\\1$", "aa", false),
    ] {
    assert_eq(
      @json-schema.pattern_matches(@json-schema.compile_pattern(pattern), text),
      expected,
    )
  }
}

///|
test "pattern compatibility: Unicode categories and hexadecimal escapes" {
  for
    (pattern, text, expected) in [
      ("^\\p{General_Category=Lu}+$", "ΑB", true),
      ("^\\p{gc=Lu}$", "A", true),
      ("^\\p{Uppercase_Letter}+$", "a", false),
      ("^[\\p{Lu}0-9]+$", "Α3", true),
      ("^\\P{Lu}+$", "中文a", true),
      ("^\\P{Lu}+$", "A", false),
      // Negated properties inside classes are engine-native.
      ("^[\\P{Lu}]+$", "中文a", true),
      ("^[\\P{Lu}]+$", "A", false),
      ("^\\x41$", "A", true),
      ("^[\\x41-\\x43]+$", "ABC", true),
      ("^\\v$", "\u{000B}", true),
      ("^[\\v]$", "\u{000B}", true),
      // ECMA-262 empty classes: `[]` never matches, `[^]` matches everything.
      ("^[]$", "a", false),
      ("^[^]$", "a", true),
      ("^[^]$", "\n", true),
    ] {
    assert_eq(
      @json-schema.pattern_matches(@json-schema.compile_pattern(pattern), text),
      expected,
    )
  }
}

///|
test "pattern compatibility: unsupported features remain explicit errors" {
  for
    pattern in [
      // The engine implements General_Category only; scripts and binary
      // properties are typed engine rejections, never silent non-matches.
      "\\p{Script=Greek}", "\\p{Alphabetic}", "\\p{gc}",
      // Malformed escapes.
       "\\xZZ",
    ] {
    let support = @json-schema.compile_pattern(pattern)
    assert_true(support is Unsupported(..), msg=pattern)
    try @json-schema.pattern_matches(support, "anything") catch {
      @json-schema.PatternError::NotSupported(_) => ()
    } noraise {
      _ => fail("unsupported pattern must not become a boolean")
    }
  }
}
