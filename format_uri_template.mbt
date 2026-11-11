// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// `uri-template` (RFC 6570). The template is a run of literals and
/// expressions; literals are restricted to the RFC 3986/3987 character sets
/// plus the two braces that delimit expressions, and each expression is an
/// operator-free or operator-led variable list of varspecs.
fn format_uri_template(value : String) -> Bool {
  let text = value[:]
  let mut index = 0
  while index < text.length() {
    let next = text.get_char(index)
    if next is Some('{') {
      let rest = text[index:].to_owned()
      guard format_template_expression(rest) is Some(consumed) else {
        return false
      }
      index = index + consumed
    } else if next is Some('}') {
      return false
    } else if next is Some('%') {
      guard index + 2 < text.length() &&
        text.get_char(index + 1) is Some(high) &&
        format_is_hex(high) &&
        text.get_char(index + 2) is Some(low) &&
        format_is_hex(low) else {
        return false
      }
      index = index + 3
    } else if next is Some(ch) {
      if !format_template_literal_char(ch) {
        return false
      }
      index = index + char_width(ch)
    } else {
      return false
    }
  }
  true
}

///|
/// Literal characters: `unreserved / reserved / ucschar / iprivate`, with
/// percent-encoded triplets handled by the caller.
fn format_template_literal_char(ch : Char) -> Bool {
  if is_unreserved_byte(ch.to_int()) ||
    uri_subdelimiter(ch) ||
    ch is (':' | '/' | '?' | '#' | '[' | ']' | '@') {
    return true
  }
  ch.to_int() > 0x7F && (format_is_ucschar(ch) || format_is_iprivate(ch))
}

///|
/// One `{ ... }` expression starting at the start of `text`. Returns the
/// number of code units consumed, including both braces.
fn format_template_expression(text : StringView) -> Int32? {
  guard text.has_prefix("{") else { return None }
  let mut index = 1
  if index < text.length() {
    let next = text.get_char(index)
    if next is Some(ch) && format_template_operator(ch) {
      index = index + 1
    }
  }
  let mut varspecs = 0
  while index < text.length() {
    match text.get_char(index) {
      Some('}') =>
        if varspecs == 0 {
          return None
        } else {
          return Some(index + 1)
        }
      Some(',') => if varspecs == 0 { return None } else { index = index + 1 }
      _ => {
        guard format_template_varspec(text, index) is Some(end) else {
          return None
        }
        index = end
        varspecs = varspecs + 1
      }
    }
  }
  None
}

///|
fn format_template_operator(ch : Char) -> Bool {
  ch is ('+' | '#' | '.' | '/' | ';' | '?' | '&')
}

///|
/// `varspec = varname [ ":" max-length ] [ "*" ]`, where
/// `varname = varchar *( varchar / "." )` and `varchar = ALPHA / DIGIT / "_" /
/// pct-encoded`.
fn format_template_varspec(text : StringView, start : Int32) -> Int32? {
  let mut index = start
  while index < text.length() {
    let next = text.get_char(index)
    if next is Some('%') {
      guard index + 2 < text.length() &&
        text.get_char(index + 1) is Some(high) &&
        format_is_hex(high) &&
        text.get_char(index + 2) is Some(low) &&
        format_is_hex(low) else {
        return None
      }
      index = index + 3
    } else if next is Some(ch) && (format_is_alnum(ch) || ch == '_') {
      index = index + 1
    } else {
      break
    }
  }
  if index == start {
    return None
  }
  // A dot may only separate two non-empty name characters.
  while index < text.length() {
    if text.get_char(index) != Some('.') {
      break
    }
    let after_dot = index + 1
    guard text.get_char(after_dot) is Some(ch) &&
      (format_is_alnum(ch) || ch == '_') else {
      return None
    }
    index = after_dot
    while index < text.length() {
      let next = text.get_char(index)
      if next is Some('%') {
        guard index + 2 < text.length() &&
          text.get_char(index + 1) is Some(high) &&
          format_is_hex(high) &&
          text.get_char(index + 2) is Some(low) &&
          format_is_hex(low) else {
          return None
        }
        index = index + 3
      } else if next is Some(ch) && (format_is_alnum(ch) || ch == '_') {
        index = index + 1
      } else {
        break
      }
    }
  }
  if text.get_char(index) == Some(':') {
    index = index + 1
    guard text.get_char(index) is Some(first) && first is ('1'..<='9') else {
      return None
    }
    index = index + 1
    let mut digits = 1
    while digits < 4 {
      guard text.get_char(index) is Some(ch) && format_is_digit(ch) else {
        break
      }
      index = index + 1
      digits = digits + 1
    }
    // `{v:10000}` has a fifth digit, which is not part of max-length.
    guard text.get_char(index) is Some(ch) && format_is_digit(ch) else {
      return Some(index)
    }
    return None
  }
  if text.get_char(index) == Some('*') {
    return Some(index + 1)
  }
  Some(index)
}
