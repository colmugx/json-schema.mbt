// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
#deprecated("Temporary Unicode property expansion: recheck moonbitlang/regexp before removing", skip_current_package=true)
fn unicode_property(
  pattern : String,
  start : Int32,
  in_class : Bool,
) -> (String, Int32) raise PatternError {
  guard start + 2 < pattern.length() && pattern[start + 2] == '{' else {
    raise NotSupported("malformed Unicode property escape")
  }
  let mut end = start + 3
  while end < pattern.length() && pattern[end] != '}' {
    end += 1
  }
  guard end < pattern.length() else {
    raise NotSupported("unterminated Unicode property escape")
  }
  let name = pattern[start + 3:end].to_owned()
  let bare = if name.has_prefix("General_Category=") {
    name[17:].to_owned()
  } else {
    name
  }
  guard general_category_property_value_alises.get(bare) is Some(category) else {
    raise NotSupported("unsupported Unicode property: " + name)
  }
  guard general_category_ranges.get(category) is Some(ranges) else {
    raise NotSupported("missing Unicode category ranges: " + category)
  }
  let negated = pattern[start + 1] == 'P'
  if in_class && negated {
    raise NotSupported("negated Unicode property inside a class is unsupported")
  }
  if in_class &&
    (
      (start > 0 && pattern[start - 1] == '-') ||
      (end + 1 < pattern.length() && pattern[end + 1] == '-')
    ) {
    raise NotSupported(
      "Unicode properties used as range endpoints are unsupported",
    )
  }
  let output = StringBuilder()
  if !in_class {
    output.write_string(if negated { "[^" } else { "[" })
  }
  for i = 0; i < ranges.length(); i = i + 2 {
    // Escaping scalar values avoids accidental class syntax in generated data.
    output.write_string("\\u{" + ranges[i].to_int().to_string(radix=16) + "}")
    if ranges[i] != ranges[i + 1] {
      output.write_string(
        "-\\u{" + ranges[i + 1].to_int().to_string(radix=16) + "}",
      )
    }
  }
  if !in_class {
    output.write_string("]")
  }
  (output.to_string(), end + 1)
}

///|
// Exactly ^(body)\1$: there is a single capture and no surrounding context.
// Splitting in equal halves removes capture-choice ambiguity; nested captures,
// assertions and context-sensitive anchors are explicitly refused.
#deprecated("Temporary anchored backreference profile: recheck moonbitlang/regexp before removing", skip_current_package=true)
fn repeated_capture_body(pattern : String) -> String? raise PatternError {
  if !pattern.has_prefix("^(") ||
    pattern.has_prefix("^(?") ||
    !pattern.has_suffix(")\\1$") {
    return None
  }
  let mut depth = 1
  let mut in_class = false
  let mut index = 2
  while index < pattern.length() {
    let c = char_at(pattern, index)
    if c == '\\' && index + 1 < pattern.length() {
      let next = char_at(pattern, index + 1)
      if next is ('0'..<='9') ||
        next == 'k' ||
        (!in_class && (next == 'b' || next == 'B')) {
        raise NotSupported(
          "nested backreferences or boundaries in repeated captures are unsupported",
        )
      }
      index += 1 + char_width(next)
      continue
    }
    if c == '[' && !in_class {
      in_class = true
    } else if c == ']' && in_class {
      in_class = false
    }
    if !in_class {
      if c == '^' || c == '$' {
        raise NotSupported("anchors inside repeated captures are unsupported")
      }
      if c == '(' {
        if !pattern[index:].has_prefix("(?:") {
          raise NotSupported(
            "nested captures or assertions in repeated captures are unsupported",
          )
        }
        depth += 1
      } else if c == ')' {
        depth -= 1
        if depth == 0 {
          if index != pattern.length() - 4 {
            return None
          }
          return Some(pattern[2:index].to_owned())
        }
      }
    }
    index += char_width(c)
  }
  None
}

///|
#deprecated("Temporary anchored backreference matcher: recheck moonbitlang/regexp before removing", skip_current_package=true)
fn repeated_capture_matches(expression : @string.Regex, text : String) -> Bool {
  if text.length() % 2 != 0 {
    return false
  }
  let middle = text.length() / 2
  guard text.get_view(start=0, end=middle) is Some(first) &&
    text.get_view(start=middle) is Some(second) else {
    return false
  }
  first == second && expression.execute(first) is Some(_)
}
