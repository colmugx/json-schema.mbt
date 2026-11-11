// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// `duration` (RFC 3339 appendix A). The ABNF nests the components, so a later
/// unit may only appear when the unit before it is present as well: `P1Y2D` and
/// `PT1H2S` are not derivable, while `P1M2D` and `PT1M2S` are. Weeks are
/// exclusive, fractional values are not allowed and a time part needs at least
/// one component (`P1YT`, `PT`).
fn format_duration(value : String) -> Bool {
  let text = value[:]
  if text.length() < 2 || !text.has_prefix("P") {
    return false
  }
  let mut index = 1
  // 1 = years, 2 = months, 3 = days; 0 means "no date component yet".
  let mut date_rank = 0
  // 1 = hours, 2 = minutes, 3 = seconds; 0 means "no time component yet".
  let mut time_rank = 0
  let mut in_time = false
  let mut saw_component = false
  while index < text.length() {
    if !in_time && text.get_char(index) == Some('T') {
      in_time = true
      index = index + 1
      continue
    }
    let digits_start = index
    while index < text.length() {
      let next = text.get_char(index)
      if next is Some(ch) && format_is_digit(ch) {
        index = index + 1
      } else {
        break
      }
    }
    if index == digits_start || index >= text.length() {
      return false
    }
    let unit = text.get_char(index)
    index = index + 1
    if in_time {
      // dur-hour = hours "H" [dur-minute]; dur-minute = minutes "M" [dur-second]
      let rank = match unit {
        Some('H') => 1
        Some('M') => 2
        Some('S') => 3
        _ => return false
      }
      if !(time_rank == 0 ||
        (rank == 2 && time_rank == 1) ||
        (rank == 3 && time_rank == 2)) {
        return false
      }
      time_rank = rank
    } else if unit == Some('W') {
      // dur-week = weeks "W" is its own branch of the duration production.
      if saw_component || index != text.length() {
        return false
      }
      return true
    } else {
      // dur-year = years "Y" [dur-month]; dur-month = months "M" [dur-day];
      // dur-day = days "D" is also allowed on its own.
      let rank = match unit {
        Some('Y') => 1
        Some('M') => 2
        Some('D') => 3
        _ => return false
      }
      if !((date_rank == 0 && rank == 1) ||
        (rank == 2 && (date_rank == 0 || date_rank == 1)) ||
        (rank == 3 && (date_rank == 0 || date_rank == 2))) {
        return false
      }
      date_rank = rank
    }
    saw_component = true
  }
  saw_component && !(in_time && time_rank == 0)
}
