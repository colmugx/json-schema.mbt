// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// `ipv4` (RFC 2673 dotted-quad, as referenced by RFC 3986): exactly four
/// decimal octets in 0-255, no shorthand forms, no leading zeros, no
/// whitespace. The package already owns the octet grammar in `uri_host.mbt`.
fn format_ipv4(value : String) -> Bool {
  valid_ipv4(value[:])
}

///|
/// `ipv6` (RFC 3986 `IPv6address`): the value is the bare address, never the
/// bracketed `IP-literal` spelling, so a surrounding pair of brackets is a
/// failure rather than something to strip.
fn format_ipv6(value : String) -> Bool {
  if value.contains_char('[') || value.contains_char(']') {
    return false
  }
  valid_ip_literal("[" + value + "]")
}
