///|
fn matched(pattern : String, text : String) -> Bool raise {
  @json-schema.pattern_matches(@json-schema.compile_pattern(pattern), text)
}

///|
test "patterns: ASCII shorthand classes and class context" {
  assert_true(matched("^\\d{3}$", "123"))
  assert_false(matched("^\\d{3}$", "١٢٣"))
  assert_false(matched("^\\d{3}$", "x123"))
  assert_true(matched("^[\\dA-F]+$", "1AF"))
  assert_false(matched("^[^\\d]+$", "1AF"))
  assert_true(matched("^[^\\d]+$", "xyz"))
  assert_true(matched("^\\w+$", "a_bC1"))
  assert_false(matched("^\\w+$", "中文"))
  assert_true(matched("^\\D+$", "abc"))
  assert_false(matched("^\\D+$", "abc1"))
  // Negated shorthand classes are now engine-native, including inside classes.
  assert_true(matched("^[\\D]+$", "xyz"))
  assert_false(matched("^[\\D]+$", "x1z"))
  assert_true(matched("^[\\W]$", "é"))
  assert_true(matched("^[\\S]$", "a"))
}

///|
test "patterns: ECMA whitespace and dot line terminators" {
  for
    text in [
      " ", "\t", "\n", "\r", "\u{000B}", "\u{00A0}", "\u{2028}", "\u{FEFF}",
    ] {
    assert_true(matched("^\\s$", text))
    assert_true(matched("^[\\s]$", text))
    assert_false(matched("^\\S$", text))
  }
  for text in ["\n", "\r", "\u{2028}", "\u{2029}"] {
    assert_false(matched("^.$", text))
  }
  // The engine's dot excludes \u000A-\u0010; the adapter restores the exact
  // ECMA line-terminator class, so \u{000B} must still match `.`.
  assert_true(matched("^.$", "\u{000B}"))
  assert_false(matched("^\\s$", "\u{0085}"))
  assert_true(matched("^\\S$", "\u{0085}"))
}

///|
test "patterns: search semantics, captures, backreferences and emoji" {
  assert_true(matched("b{2}", "abbc"))
  assert_false(matched("^bb$", "abbc"))
  assert_true(matched("^(a)\\1$", "aa"))
  assert_false(matched("^(a)\\1$", "ab"))
  assert_true(matched("^(?<year>\\d{4})-\\d{2}$", "2024-03"))
  assert_true(matched("^😀\\d$", "😀1"))
  assert_false(matched("^😀\\d$", "😀x"))
  assert_true(matched("^\\[\\d\\]$", "[1]"))
  assert_true(matched("\\p{Lu}", "aB"))
}

///|
test "patterns: general backreferences are engine-native" {
  // Unanchored search with a backreference.
  assert_true(matched("(a)\\1", "xaa"))
  assert_false(matched("(a)\\1", "xab"))
  // Numbered backreferences beyond the first group.
  assert_true(matched("^(a)(b)\\2$", "abb"))
  assert_false(matched("^(a)(b)\\2$", "aba"))
  assert_true(matched("^(.)(.)\\2\\1$", "abba"))
  // Named groups and named backreferences.
  assert_true(matched("^(?<n>a)\\k<n>$", "aa"))
  assert_false(matched("^(?<n>a)\\k<n>$", "ab"))
  // Unset/empty backreferences match empty, per ECMA-262.
  assert_true(matched("^(?:x|(y))\\1$", "x"))
  // Recursive and undefined backreferences stay engine errors.
  for pattern in ["\\1", "(a)\\2", "(\\1a)", "(?<n>a)\\k<other>", "\\k<n>"] {
    let support = @json-schema.compile_pattern(pattern)
    assert_true(support is Unsupported(..), msg=pattern)
  }
}

///|
test "patterns: ECMA control escapes \\c" {
  assert_true(matched("^\\cC$", "\u{0003}"))
  assert_false(matched("^\\cC$", "\\cC"))
  assert_true(matched("^\\cc$", "\u{0003}"))
  assert_true(matched("^[\\cA]$", "\u{0001}"))
  assert_true(matched("^\\cI$", "\t"))
  assert_false(matched("^\\cJ$", "\t"))
}

///|
test "patterns: precise leading assertion chain" {
  assert_true(matched("^(?=\\d{3}$)\\d+$", "123"))
  assert_false(matched("^(?=\\d{3}$)\\d+$", "1234"))
  assert_true(matched("^(?=.{3}$)(?!000)\\d+$", "123"))
  assert_false(matched("^(?=.{3}$)(?!000)\\d+$", "000"))
  assert_true(matched("^(?=(?:ab|cd)$)[a-z]+$", "ab"))
  assert_false(matched("^(?=(?:ab|cd)$)[a-z]+$", "ef"))
}

///|
test "patterns: scoped inline flag groups use engine case folding" {
  assert_true(matched("^(?i:abc)$", "ABC"))
  assert_true(matched("^(?i:σ)$", "Σ"))
  assert_false(matched("^(?i:abc)$", "abd"))
  // Scoped flags are restored after the group.
  assert_true(matched("^(?i:a)b$", "Ab"))
  assert_false(matched("^(?i:a)b$", "AB"))
}

///|
test "patterns: unsupported constructs and malformed patterns never become false" {
  for
    pattern in [
      "[", "a(?=b)", "(?=a)a", "(?<=a)b", "^(?=(a))a", "^(?=a)a|b", "(?i)a", "(?P<name>x)",
      "(?#c)a", "\\c3", "\\c", "\\xZZ", "\\xD",
    ] {
    let support = @json-schema.compile_pattern(pattern)
    assert_true(support is Unsupported(..), msg=pattern)
    let errored = try {
      ignore(@json-schema.pattern_matches(support, "anything"))
      false
    } catch {
      _ => true
    }
    assert_true(errored)
  }
}
