// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// `hostname` (RFC 1123 preferred name syntax): ASCII only, and an A-label is
/// judged through its decoded Punycode form by the UTS #46 ToASCII pipeline
/// rather than on its LDH spelling alone. UTS #46 mapping is deliberately not
/// applied here: a non-ASCII spelling is `idn-hostname`'s job, so
/// `example\u{FF0E}com` fails instead of being mapped to `example.com`.
fn format_hostname(value : String) -> Bool {
  if !format_is_ascii(value) {
    return false
  }
  format_idna_domain(value)
}

///|
/// `idn-hostname`: the full UTS #46 ToASCII pipeline — mapping (the U+3002,
/// U+FF0E and U+FF61 label separators included), NFC, A-label decoding,
/// derived-property/CONTEXTJ/CONTEXTO validation, the RFC 5893 Bidi rule and the
/// DNS length bounds. A rejected domain is an assertion failure, never a silent
/// pass.
fn format_idn_hostname(value : String) -> Bool {
  format_idna_domain(value)
}

///|
/// UTS #46 ToASCII followed by IDNA2008 label validity on the decoded U-labels.
/// `@idna` owns mapping, Punycode, the hyphen rules, the Bidi rule, ContextJ and
/// the DNS length bounds; `format_idna2008_label` owns the RFC 5892 derived
/// property and the ContextO rules it does not implement.
fn format_idna_domain(value : String) -> Bool {
  let ascii = @idna.to_ascii(value) catch { _ => return false }
  let unicode = @idna.to_unicode(ascii) catch { _ => return false }
  for label in unicode.split(".") {
    if !format_idna2008_label(label) {
      return false
    }
  }
  true
}

///|
fn format_is_ascii(value : String) -> Bool {
  for ch in value[:] {
    if ch.to_int() >= 0x80 {
      return false
    }
  }
  true
}

///|
/// Dot-separated labels of the domain after `@` in a mailbox. This is the RFC
/// 5321 `Domain` grammar, not UTS #46: `idn-email` has to accept spellings that
/// IDNA processing would reject or normalize away, so the two contracts stay
/// apart.
fn format_domain_labels(
  chars : Array[Char],
  start : Int32,
  end : Int32,
  ascii_only~ : Bool,
) -> Bool {
  if end <= start {
    return false
  }
  let mut label_start = start
  let mut index = start
  while index <= end {
    if index == end || chars[index] == '.' {
      if !format_label(chars, label_start, index, ascii_only~) {
        return false
      }
      label_start = index + 1
    }
    index = index + 1
  }
  format_domain_length(chars, start, end)
}

///|
/// One label, in the character space the format asserts: ASCII LDH for the
/// `email` domain, the structural U-label rules for `idn-email`.
fn format_label(
  chars : Array[Char],
  start : Int32,
  end : Int32,
  ascii_only~ : Bool,
) -> Bool {
  if end <= start || chars[start] == '-' || chars[end - 1] == '-' {
    return false
  }
  if end - start > 63 {
    return false
  }
  for index in start..<end {
    let ch = chars[index]
    if !ascii_only && ch.to_int() >= 0x80 {
      continue
    }
    if !format_is_alnum(ch) && ch != '-' {
      return false
    }
  }
  true
}

///|
/// Overall length of a domain name: 253 octets, the RFC 1035 limit that leaves
/// room for the root label inside the 255-octet wire form. A U-label domain is
/// measured in octets of its spelling, not of its A-label expansion, because the
/// mailbox grammar performs no mapping.
fn format_domain_length(
  chars : Array[Char],
  start : Int32,
  end : Int32,
) -> Bool {
  format_octets(chars, start, end) <= 253
}
