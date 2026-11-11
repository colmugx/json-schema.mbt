// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// Pure predicate for the Draft 2020-12 `format` assertion vocabulary
/// (Validation 7.2.2). `value` is an already-decoded instance string, so the
/// predicate performs no I/O: no DNS lookup, no file access and no
/// entity-existence check. Unknown format names are annotations only and are
/// therefore never failing.
///
/// Supported names, each with its own file:
///
/// - `date-time`, `date`, `time` (RFC 3339) - `format_date_time.mbt`
/// - `duration` (RFC 3339 appendix A) - `format_duration.mbt`
/// - `ipv4`, `ipv6` (RFC 2673 / RFC 3986 literals) - `format_ip.mbt`
/// - `uuid` (RFC 4122 textual form) - `format_uuid.mbt`
/// - `json-pointer`, `relative-json-pointer` (RFC 6901 / draft-handrews) -
///   `format_json_pointer.mbt`
/// - `uri`, `uri-reference`, `iri`, `iri-reference` (RFC 3986 / RFC 3987) -
///   `format_uri.mbt`
/// - `uri-template` (RFC 6570) - `format_uri_template.mbt`
/// - `email`, `idn-email` (RFC 5322 / RFC 6531 address syntax) -
///   `format_email.mbt`
/// - `hostname` (RFC 1123 LDH labels), `idn-hostname` (structural subset) -
///   `format_host.mbt`
/// - `regex` (ECMA-262 pattern syntax) - `format_regex.mbt`
///
/// The two internationalized host formats are the documented gaps: IDNA2008
/// derived properties, UTS#46 mapping, the Bidi rule and ContextO/ContextJ
/// rules need Unicode tables that this module does not carry, so `hostname`
/// asserts only the ASCII LDH syntax (A-labels stay structurally accepted) and
/// `idn-hostname` asserts only its table-free structural rules.
///
/// # Example
///
/// ```mbt check
/// test {
///   assert_true(@json-schema.format_valid("date", "2020-02-29"))
///   assert_false(@json-schema.format_valid("date", "2021-02-29"))
///   assert_true(@json-schema.format_valid("unknown", "anything"))
/// }
/// ```
pub fn format_valid(name : String, value : String) -> Bool {
  match name {
    "date-time" => format_date_time(value)
    "date" => format_date(value)
    "time" => format_time(value)
    "duration" => format_duration(value)
    "email" => format_email(value)
    "idn-email" => format_idn_email(value)
    "hostname" => format_hostname(value)
    "idn-hostname" => format_idn_hostname(value)
    "ipv4" => format_ipv4(value)
    "ipv6" => format_ipv6(value)
    "uri" => format_uri(value)
    "uri-reference" => format_uri_reference(value)
    "iri" => format_iri(value)
    "iri-reference" => format_iri_reference(value)
    "uri-template" => format_uri_template(value)
    "json-pointer" => format_json_pointer(value)
    "relative-json-pointer" => format_relative_json_pointer(value)
    "regex" => format_regex(value)
    "uuid" => format_uuid(value)
    _ => true
  }
}

///|
fn format_is_digit(ch : Char) -> Bool {
  ch is ('0'..<='9')
}

///|
fn format_is_alpha(ch : Char) -> Bool {
  (ch is ('a'..<='z')) | ('A'..<='Z')
}

///|
fn format_is_alnum(ch : Char) -> Bool {
  (ch is ('0'..<='9')) | ('a'..<='z') | ('A'..<='Z')
}

///|
fn format_is_hex(ch : Char) -> Bool {
  (ch is ('0'..<='9')) | ('a'..<='f') | ('A'..<='F')
}

///|
/// Decimal value of a run of ASCII digits. `None` for an empty run, a non-ASCII
/// digit or any other character; values above 10^9 saturate instead of
/// overflowing so range decisions stay correct for absurd spellings.
fn format_uint(text : StringView) -> Int32? {
  if text.is_empty() {
    return None
  }
  let mut value = 0
  for i in 0..<text.length() {
    let digit = match text.get_char(i) {
      Some(ch) =>
        if format_is_digit(ch) {
          ch.to_int() - '0'.to_int()
        } else {
          return None
        }
      None => return None
    }
    if value <= 1_000_000_000 {
      value = value * 10 + digit
    }
  }
  Some(value)
}

///|
fn format_all_digits(text : StringView) -> Bool {
  if text.is_empty() {
    return false
  }
  for i in 0..<text.length() {
    guard text.get_char(i) is Some(ch) && format_is_digit(ch) else {
      return false
    }
  }
  true
}

///|
/// Two-digit field at `[start, start + 2)`, or `None` when either position is
/// not an ASCII digit.
fn format_two_digits(text : StringView, start : Int32) -> Int32? {
  guard text.get_char(start) is Some(high) && format_is_digit(high) else {
    return None
  }
  guard text.get_char(start + 1) is Some(low) && format_is_digit(low) else {
    return None
  }
  Some((high.to_int() - '0'.to_int()) * 10 + (low.to_int() - '0'.to_int()))
}
