// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// Component of a URI/IRI reference that constrains the character set.
priv enum FormatPart {
  UserInfo
  Host
  Path
  Query
  Fragment
}

///|
/// `uri` (RFC 3986 `URI`): an absolute URI, so a scheme is mandatory.
fn format_uri(value : String) -> Bool {
  format_uri_like(value, iri=false, absolute=true)
}

///|
/// `uri-reference` (RFC 3986 `URI-reference`, including the empty reference).
fn format_uri_reference(value : String) -> Bool {
  format_uri_like(value, iri=false, absolute=false)
}

///|
/// `iri` (RFC 3987 `IRI`): an absolute IRI, so a scheme is mandatory.
fn format_iri(value : String) -> Bool {
  format_uri_like(value, iri=true, absolute=true)
}

///|
/// `iri-reference` (RFC 3987 `IRI-reference`, including the empty reference).
fn format_iri_reference(value : String) -> Bool {
  format_uri_like(value, iri=true, absolute=false)
}

///|
/// RFC 3986 section 3 splitting and RFC 3986/3987 component productions. The
/// package's `Uri::parse` owns scheme/hier-part/query/fragment splitting, so
/// this only has to decide whether every component matches its ABNF
/// alternative.
fn format_uri_like(value : String, iri : Bool, absolute : Bool) -> Bool {
  let parsed = Uri::parse(value)
  if absolute && parsed.scheme is None {
    return false
  }
  let authority_present = parsed.authority is Some(_)
  if parsed.authority is Some(authority) && !format_authority(authority, iri) {
    return false
  }
  if !format_part_valid(parsed.path[:], Path, iri) {
    return false
  }
  if parsed.query is Some(query) && !format_part_valid(query[:], Query, iri) {
    return false
  }
  if parsed.fragment is Some(fragment) &&
    !format_part_valid(fragment[:], Fragment, iri) {
    return false
  }
  // RFC 3986 3.3: with no authority the path is `path-absolute`,
  // `path-rootless` or `path-empty`; a relative reference additionally uses
  // `path-noscheme`, whose first segment may not contain a colon. `Uri::parse`
  // already routes a leading `//` to the authority, so no further split checks
  // are needed for `path-abempty`.
  if parsed.scheme is None && !authority_present {
    let path = parsed.path
    if path != "" && !path.has_prefix("/") &&
      !format_first_segment_colon_free(path) {
      return false
    }
  }
  true
}

///|
/// `path-noscheme`: the first segment of a relative-path reference may not
/// contain `:` (`./this:that` is fine because of the leading dot segment).
fn format_first_segment_colon_free(path : String) -> Bool {
  let mut index = 0
  while index < path.length() {
    match path.get_char(index) {
      Some('/') => return true
      Some(':') => return false
      Some(ch) => index = index + char_width(ch)
      None => return false
    }
  }
  true
}

///|
/// `authority = [ userinfo "@" ] host [ ":" port ]` with at most one `@`.
fn format_authority(authority : String, iri : Bool) -> Bool {
  let (userinfo, hostport) = match split_at_first(authority, '@') {
    (info, Some(tail)) => (Some(info), tail)
    (rest, None) => (None, rest)
  }
  if hostport.contains_char('@') {
    return false
  }
  if userinfo is Some(info) && !format_part_valid(info[:], UserInfo, iri) {
    return false
  }
  let (host, port) = split_host_port(hostport)
  if port is Some(digits) && !digits.is_empty() {
    if !format_all_digits(digits[:]) {
      return false
    }
  }
  if host.is_empty() {
    return true
  }
  if host.has_prefix("[") {
    return valid_ip_literal(host)
  }
  format_part_valid(host[:], Host, iri)
}

///|
fn format_part_valid(text : StringView, part : FormatPart, iri : Bool) -> Bool {
  let mut index = 0
  while index < text.length() {
    let next = text.get_char(index)
    if next is Some('%') {
      guard index + 2 < text.length() &&
        text.get_char(index + 1) is Some(high) && format_is_hex(high) &&
        text.get_char(index + 2) is Some(low) && format_is_hex(low) else {
        return false
      }
      index = index + 3
    } else if next is Some(ch) {
      if !format_component_char(ch, part, iri) {
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
fn format_component_char(ch : Char, part : FormatPart, iri : Bool) -> Bool {
  if is_unreserved_byte(ch.to_int()) || uri_subdelimiter(ch) {
    return true
  }
  if ch.to_int() > 0x7F {
    if !iri {
      return false
    }
    return match part {
      Query => format_is_ucschar(ch) || format_is_iprivate(ch)
      _ => format_is_ucschar(ch)
    }
  }
  match part {
    UserInfo => ch == ':'
    Path => ch == ':' || ch == '@' || ch == '/'
    Query | Fragment => ch == ':' || ch == '@' || ch == '/' || ch == '?'
    Host => false
  }
}

///|
/// RFC 3987 `ucschar`: the non-ASCII-visible part of an IRI.
fn format_is_ucschar(ch : Char) -> Bool {
  let code = ch.to_int()
  if code < 0xA0 {
    false
  } else if code <= 0xD7FF {
    true
  } else if code >= 0xF900 && code <= 0xFDCF {
    true
  } else if code >= 0xFDF0 && code <= 0xFFEF {
    true
  } else if code >= 0x10000 && code <= 0xEFFFD {
    let low = code & 0xFFFF
    if code >= 0xE0000 {
      low >= 0x1000
    } else {
      low <= 0xFFFD
    }
  } else {
    false
  }
}

///|
/// RFC 3987 `iprivate`: private-use code points, which appear in queries but
/// not in hosts, paths or fragments.
fn format_is_iprivate(ch : Char) -> Bool {
  let code = ch.to_int()
  (code >= 0xE000 && code <= 0xF8FF) ||
  (code >= 0xF0000 && code <= 0xFFFFD) ||
  (code >= 0x100000 && code <= 0x10FFFD)
}
