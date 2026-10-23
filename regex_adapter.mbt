// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// Opaque compiled pattern. No external regexp type leaks through this API.
pub struct CompiledPattern {
  priv expression : @regexp.Regexp
  priv assertions : Array[(Bool, @regexp.Regexp)]
  priv anchored : Bool
}

///|
pub(all) enum PatternSupport {
  Supported(CompiledPattern)
  Unsupported(reason~ : String)
}

///|
pub(all) suberror PatternError {
  NotSupported(String)
} derive(Debug)

///|
pub extend PatternError with @debug.Debug::{to_repr}

///|
fn char_at(source : String, index : Int32) -> Char {
  source.get_char(index).unwrap_or_else(() => source[index].unsafe_to_char())
}

///|
fn char_width(c : Char) -> Int32 {
  if c.to_int() > 65535 {
    2
  } else {
    1
  }
}

///|
/// Two lowercase hexadecimal digits for a control code point (0..=0x1F).
fn control_hex(code : Int32) -> String {
  let digits = "0123456789abcdef"
  let high = (code >> 4) & 0xF
  let low = code & 0xF
  let builder = StringBuilder()
  builder.write_char(digits[high].unsafe_to_char())
  builder.write_char(digits[low].unsafe_to_char())
  builder.to_string()
}

///|
#deprecated("Temporary ECMA translation: recheck moonbitlang/regexp before removing", skip_current_package=true)
fn translate(pattern : String) -> String raise PatternError {
  let output = StringBuilder()
  let mut index = 0
  let mut in_class = false
  while index < pattern.length() {
    let c = char_at(pattern, index)
    if c == '\\' && index + 1 < pattern.length() {
      let next = char_at(pattern, index + 1)
      if next == 'p' || next == 'P' {
        let (replacement, after) = unicode_property(pattern, index)
        output.write_string(replacement)
        index = after
        continue
      }
      if next == 'x' {
        guard index + 3 < pattern.length() else {
          raise NotSupported("incomplete hexadecimal escape")
        }
        let hex = pattern[index + 2:index + 4].to_owned()
        for digit in hex {
          guard digit is ('0'..<='9' | 'a'..<='f' | 'A'..<='F') else {
            raise NotSupported("invalid hexadecimal escape")
          }
        }
        output.write_string("\\u00" + hex)
        index += 4
        continue
      }
      if next == 'c' {
        guard index + 2 < pattern.length() else {
          raise NotSupported("incomplete control escape")
        }
        let letter = char_at(pattern, index + 2)
        // ECMA-262 ClassControlLetter: `\c` plus exactly one ASCII letter.
        // The engine reserves `\c` as an error, so the adapter maps the letter
        // to its control code point. Non-letters stay typed-unsupported
        // instead of guessing between Annex B literal `c` and a SyntaxError.
        guard letter is ('A'..<='Z' | 'a'..<='z') else {
          raise NotSupported(
            "\\c control escapes require an ASCII letter operand",
          )
        }
        let upper = if letter is ('A'..<='Z') {
          letter.to_int()
        } else {
          letter.to_int() - 32
        }
        output.write_string("\\u00" + control_hex(upper & 0x1F))
        index += 3
        continue
      }
      // Backreferences (\1..\9, \k<name>), shorthand classes, identity escapes
      // and control character escapes pass through: the engine implements them
      // or rejects them as a typed compile error.
      output.write_char('\\')
      output.write_char(next)
      index += 1 + char_width(next)
      continue
    }
    if c == '[' && !in_class {
      in_class = true
    } else if c == ']' && in_class {
      in_class = false
    }
    if !in_class && c == '(' && pattern[index:].has_prefix("(?") {
      if pattern[index:].has_prefix("(?=") || pattern[index:].has_prefix("(?!") {
        raise NotSupported("only a leading lookahead chain is supported")
      }
      if pattern[index:].has_prefix("(?<=") ||
        pattern[index:].has_prefix("(?<!") {
        raise NotSupported("lookbehind is not supported")
      }
      // Other `(?...` forms (named groups, scoped flag groups) pass through;
      // the engine rejects dialect-invalid forms such as global inline flags
      // and Python/PCRE groups as typed compile errors.
    }
    if !in_class && c == '.' {
      output.write_string("[^\\n\\r\\u{2028}\\u{2029}]")
    } else {
      output.write_char(c)
    }
    index += char_width(c)
  }
  output.to_string()
}

///|
// Parse one assertion, retaining balanced noncapturing groups. Captures across
// assertions would change numbering/backreference semantics, so refuse them.
#deprecated("Temporary leading lookahead parser: recheck moonbitlang/regexp before removing", skip_current_package=true)
fn assertion_end(pattern : String, start : Int32) -> Int32 raise PatternError {
  let mut index = start + 3
  let mut nesting = 1
  let mut in_class = false
  while index < pattern.length() {
    let c = char_at(pattern, index)
    if c == '\\' && index + 1 < pattern.length() {
      index += 1 + char_width(char_at(pattern, index + 1))
      continue
    }
    if c == '[' && !in_class {
      in_class = true
    } else if c == ']' && in_class {
      in_class = false
    }
    if !in_class {
      if c == '(' {
        if !pattern[index:].has_prefix("(?:") {
          raise NotSupported(
            "captures and nested lookarounds inside assertions are not supported",
          )
        }
        nesting += 1
      } else if c == ')' {
        nesting -= 1
        if nesting == 0 {
          return index
        }
      }
    }
    index += char_width(c)
  }
  raise NotSupported("unterminated lookahead assertion")
}

///|
fn has_top_alternative(pattern : String) -> Bool {
  let mut nesting = 0
  let mut in_class = false
  let mut index = 0
  while index < pattern.length() {
    let c = char_at(pattern, index)
    if c == '\\' && index + 1 < pattern.length() {
      index += 1 + char_width(char_at(pattern, index + 1))
      continue
    }
    if c == '[' && !in_class {
      in_class = true
    } else if c == ']' && in_class {
      in_class = false
    }
    if !in_class {
      if c == '(' {
        nesting += 1
      } else if c == ')' {
        nesting -= 1
      } else if c == '|' && nesting == 0 {
        return true
      }
    }
    index += char_width(c)
  }
  false
}

///|
/// Unanchored search semantics. Patterns are passed to the regexp engine after
/// only the rewrites the engine lacks (see `translate`): the ECMA dot
/// line-terminator class, `\xHH` and `\cX` escapes, and General_Category
/// property-name normalization. Backreferences, named groups, scoped flag
/// groups and shorthand classes use the engine's own ECMA semantics, and
/// dialect-invalid syntax surfaces as a typed `Unsupported` result. A leading
/// anchored positive/negative lookahead chain is evaluated with separate
/// compiled expressions; other lookarounds are explicit unsupported errors.
pub fn compile_pattern(pattern : String) -> PatternSupport {
  try {
    let anchored = pattern.has_prefix("^")
    let mut offset = if anchored { 1 } else { 0 }
    let assertions : Array[(Bool, @regexp.Regexp)] = []
    while pattern[offset:].has_prefix("(?=") ||
          pattern[offset:].has_prefix("(?!") {
      if !anchored {
        raise NotSupported(
          "leading lookahead chains must be anchored with ^ in this profile",
        )
      }
      let positive = pattern[offset:].has_prefix("(?=")
      let end = assertion_end(pattern, offset)
      let body = pattern[offset + 3:end].to_owned()
      assertions.push(
        (positive, @regexp.compile("^(?:" + translate(body) + ")")),
      )
      offset = end + 1
    }
    let expression = if assertions.is_empty() {
      @regexp.compile(translate(pattern))
    } else {
      let tail = pattern[offset:].to_owned()
      if has_top_alternative(tail) {
        raise NotSupported(
          "top-level alternatives after a lookahead chain are not supported",
        )
      }
      @regexp.compile("^(?:" + translate(tail) + ")")
    }
    Supported({ expression, assertions, anchored, })
  } catch {
    NotSupported(reason) => Unsupported(reason~)
    _ => Unsupported(reason="pattern rejected by the regexp engine")
  }
}

///|
/// Unsupported patterns cannot silently turn into a false validation result.
pub fn pattern_matches(
  support : PatternSupport,
  text : String,
) -> Bool raise PatternError {
  match support {
    Unsupported(reason~) => raise NotSupported(reason)
    Supported(compiled) => {
      if !compiled.assertions.is_empty() && !compiled.anchored {
        raise NotSupported("invalid compiled assertion origin")
      }
      for entry in compiled.assertions {
        let (positive, assertion) = entry
        if assertion.execute(text).matched() != positive {
          return false
        }
      }
      compiled.expression.execute(text).matched()
    }
  }
}
