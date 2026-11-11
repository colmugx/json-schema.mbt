// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// RFC 5321 4.5.3.1 fixes the local part at 64 octets: every implementation
/// must accept that length and must not exceed it.
let format_local_octet_limit : Int32 = 64

///|
/// `email` (RFC 5321 `Mailbox`): one ASCII `Local-part "@" Domain`, where the
/// local part is an RFC 5322 `dot-atom` or `quoted-string`. A display name, a
/// comment, an unquoted space or a comma-separated list fails, because all of
/// those are header syntax rather than a mailbox.
fn format_email(value : String) -> Bool {
  format_mailbox(value[:].to_array(), ascii_only=true)
}

///|
/// `idn-email` (RFC 6531 internationalized `Mailbox`): the same grammar with
/// `atext`, `qtext` and quoted pairs extended by `UTF8-non-ascii`, so a Unicode
/// local part and a U-label domain are valid. Labels are checked in U-label
/// space, so IDNA2008 derived properties, ContextJ and the Bidi rule are not
/// asserted here.
fn format_idn_email(value : String) -> Bool {
  format_mailbox(value[:].to_array(), ascii_only=false)
}

///|
fn format_mailbox(chars : Array[Char], ascii_only~ : Bool) -> Bool {
  guard format_mailbox_separator(chars) is Some(separator) else { return false }
  if separator == 0 || separator == chars.length() - 1 {
    return false
  }
  if format_octets(chars, 0, separator) > format_local_octet_limit {
    return false
  }
  if !format_local_part(chars, 0, separator, ascii_only~) {
    return false
  }
  format_mailbox_domain(chars, separator + 1, chars.length(), ascii_only~)
}

///|
/// Position of the `@` that separates the local part from the domain. A quoted
/// local part may contain `@`, so the scan tracks quotes and quoted pairs; a
/// second separator, or a quote left open, yields `None`.
fn format_mailbox_separator(chars : Array[Char]) -> Int32? {
  let mut separator : Int32? = None
  let mut index = 0
  let mut quoted = false
  let mut escaped = false
  while index < chars.length() {
    let ch = chars[index]
    if escaped {
      escaped = false
    } else if quoted && ch == '\\' {
      escaped = true
    } else if ch == '"' {
      quoted = !quoted
    } else if ch == '@' && !quoted {
      if separator is Some(_) {
        return None
      }
      separator = Some(index)
    }
    index = index + 1
  }
  guard !quoted && !escaped else { return None }
  separator
}

///|
fn format_local_part(
  chars : Array[Char],
  start : Int32,
  end : Int32,
  ascii_only~ : Bool,
) -> Bool {
  if chars[start] == '"' {
    format_quoted_local(chars, start, end, ascii_only~)
  } else {
    format_dot_atom(chars, start, end, ascii_only~)
  }
}

///|
/// RFC 5322 3.2.4 `quoted-string`, including both quotes: the closing quote has
/// to be the last character of the local part, so trailing text fails.
fn format_quoted_local(
  chars : Array[Char],
  start : Int32,
  end : Int32,
  ascii_only~ : Bool,
) -> Bool {
  if end - start < 2 {
    return false
  }
  let mut index = start + 1
  while index < end {
    let ch = chars[index]
    if ch == '"' {
      return index == end - 1
    }
    if ch == '\\' {
      if index + 1 >= end || !format_quoted_pair(chars[index + 1], ascii_only~) {
        return false
      }
      index = index + 2
    } else if format_qtext(ch, ascii_only~) {
      index = index + 1
    } else {
      return false
    }
  }
  false
}

///|
/// RFC 5322 3.2.1 `quoted-pair`: a backslash followed by one printable
/// character. RFC 6531 extends the operand to `UTF8-non-ascii`.
fn format_quoted_pair(ch : Char, ascii_only~ : Bool) -> Bool {
  if ch is (' '..<='~') {
    return true
  }
  !ascii_only && ch.to_int() >= 0x80
}

///|
/// RFC 5322 3.2.4 `qtext`: printable ASCII without the quote and the backslash,
/// which the grammar reaches through dedicated productions.
fn format_qtext(ch : Char, ascii_only~ : Bool) -> Bool {
  if ch is (' '..<='!' | '#'..<='[' | ']'..<='~') {
    return true
  }
  !ascii_only && ch.to_int() >= 0x80
}

///|
/// RFC 5322 3.2.3 `atext`, extended by RFC 6531 `UTF8-non-ascii` outside ASCII
/// mode. Every remaining printable ASCII character is a `special`, so an
/// unquoted local part can never carry one.
fn format_atext(ch : Char, ascii_only~ : Bool) -> Bool {
  if format_is_alnum(ch) {
    return true
  }
  if !ascii_only && ch.to_int() >= 0x80 {
    return true
  }
  ch
  is ('!'
  | '#'
  | '$'
  | '%'
  | '&'
  | '\''
  | '*'
  | '+'
  | '-'
  | '/'
  | '='
  | '?'
  | '^'
  | '_'
  | '`'
  | '{'
  | '|'
  | '}'
  | '~')
}

///|
/// RFC 5322 3.2.3 `dot-atom`: `atext` runs separated by single dots, so a
/// leading, trailing or doubled dot fails.
fn format_dot_atom(
  chars : Array[Char],
  start : Int32,
  end : Int32,
  ascii_only~ : Bool,
) -> Bool {
  let mut expect_atext = true
  for index in start..<end {
    let ch = chars[index]
    if ch == '.' {
      if expect_atext {
        return false
      }
      expect_atext = true
    } else {
      if !format_atext(ch, ascii_only~) {
        return false
      }
      expect_atext = false
    }
  }
  !expect_atext
}

///|
/// RFC 5321 4.1.2 `Domain / address-literal`, the part after the separator.
fn format_mailbox_domain(
  chars : Array[Char],
  start : Int32,
  end : Int32,
  ascii_only~ : Bool,
) -> Bool {
  if end <= start {
    return false
  }
  if chars[start] == '[' {
    format_address_literal(chars, start, end)
  } else {
    format_domain_labels(chars, start, end, ascii_only~)
  }
}

///|
/// RFC 5321 4.1.3 `address-literal`: `[` IPv4 `]` or `[` `IPv6:` IPv6 `]`.
/// The tag is case-insensitive, and a bare bracketed string that is neither an
/// IPv4 nor a tagged IPv6 literal fails.
fn format_address_literal(
  chars : Array[Char],
  start : Int32,
  end : Int32,
) -> Bool {
  if end - start < 4 || chars[end - 1] != ']' {
    return false
  }
  let text = format_text(chars, start + 1, end - 1)
  if text[:5].to_lower() == "ipv6:" {
    format_ipv6(text[5:].to_owned())
  } else {
    format_ipv4(text)
  }
}

///|
/// Octet length of `[start, end)`, which is what the RFC 5321 size limits are
/// stated in; a U-label cannot be measured in characters.
fn format_octets(chars : Array[Char], start : Int32, end : Int32) -> Int32 {
  let mut octets = 0
  for index in start..<end {
    let code = chars[index].to_int()
    octets = octets +
      (if code < 0x80 {
        1
      } else if code < 0x800 {
        2
      } else if code < 0x10000 {
        3
      } else {
        4
      })
  }
  octets
}

///|
fn format_text(chars : Array[Char], start : Int32, end : Int32) -> String {
  let out : Array[Char] = []
  for index in start..<end {
    out.push(chars[index])
  }
  String::from_array(out)
}
