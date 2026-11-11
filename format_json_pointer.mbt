// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// `json-pointer` (RFC 6901): the empty string, or a string that starts with
/// `/` where every `~` introduces the escapes `~0` or `~1`. Any other
/// character, including control characters and non-ASCII text, is allowed by
/// the reference-token production; URI-fragment spellings such as `#/a` are not.
fn format_json_pointer(value : String) -> Bool {
  if value.is_empty() {
    return true
  }
  if !value.has_prefix("/") {
    return false
  }
  format_json_pointer_tail(value[:])
}

///|
fn format_json_pointer_tail(text : StringView) -> Bool {
  let mut index = 0
  while index < text.length() {
    let next = text.get_char(index)
    if next is Some('~') {
      guard text.get_char(index + 1) is Some(escape) &&
        (escape == '0' || escape == '1') else {
        return false
      }
      index = index + 2
    } else if next is Some(ch) {
      index = index + char_width(ch)
    } else {
      return false
    }
  }
  true
}

///|
/// `relative-json-pointer` (relative JSON pointer draft): a non-negative
/// integer with no redundant leading zero, then either nothing, `#` or a
/// `json-pointer`.
fn format_relative_json_pointer(value : String) -> Bool {
  let text = value[:]
  if text.is_empty() {
    return false
  }
  guard text.get_char(0) is Some(first) && format_is_digit(first) else {
    return false
  }
  let mut index = 1
  if first != '0' {
    while index < text.length() {
      let next = text.get_char(index)
      if next is Some(ch) && format_is_digit(ch) {
        index = index + 1
      } else {
        break
      }
    }
  }
  if index == text.length() {
    return true
  }
  if text.get_char(index) == Some('#') {
    return index + 1 == text.length()
  }
  if text.get_char(index) == Some('/') {
    return format_json_pointer(text[index:].to_owned())
  }
  false
}
