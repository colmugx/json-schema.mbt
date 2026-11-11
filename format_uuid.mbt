// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// `uuid` (RFC 4122 textual representation): `8-4-4-4-12` lowercase or
/// uppercase hexadecimal digits. Version and variant nibbles are not
/// constrained, and no URN or brace spelling is accepted.
fn format_uuid(value : String) -> Bool {
  if value.length() != 36 {
    return false
  }
  for i in 0..<36 {
    let expected_dash = i == 8 || i == 13 || i == 18 || i == 23
    match value.get_char(i) {
      Some(ch) =>
        if expected_dash {
          if ch != '-' {
            return false
          }
        } else if !format_is_hex(ch) {
          return false
        }
      None => return false
    }
  }
  true
}
