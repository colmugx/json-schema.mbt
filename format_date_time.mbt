// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// `full-date` (RFC 3339 5.6): four-digit year, `01`-`12` month and a day that
/// exists in that month, including the Gregorian leap-year rule.
fn format_date(value : String) -> Bool {
  format_full_date(value[:])
}

///|
fn format_full_date(text : StringView) -> Bool {
  if text.length() != 10 {
    return false
  }
  guard text.get_char(4) == Some('-') && text.get_char(7) == Some('-') else {
    return false
  }
  guard format_uint(text[:4]) is Some(year) else { return false }
  guard format_two_digits(text, 5) is Some(month) else { return false }
  guard format_two_digits(text, 8) is Some(day) else { return false }
  format_calendar_day(year, month, day)
}

///|
fn format_calendar_day(year : Int, month : Int, day : Int) -> Bool {
  if month < 1 || month > 12 || day < 1 {
    return false
  }
  let limit = match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    _ =>
      if format_is_leap_year(year) {
        29
      } else {
        28
      }
  }
  day <= limit
}

///|
/// Proleptic Gregorian leap rule: divisible by 4, not by 100, unless by 400.
fn format_is_leap_year(year : Int) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
/// `full-time` (RFC 3339 5.6): `partial-time` with a mandatory UTC offset.
fn format_time(value : String) -> Bool {
  format_full_time(value[:])
}

///|
fn format_full_time(text : StringView) -> Bool {
  if text.length() < 9 {
    return false
  }
  guard text.get_char(2) == Some(':') && text.get_char(5) == Some(':') else {
    return false
  }
  guard format_two_digits(text, 0) is Some(hour) else { return false }
  guard format_two_digits(text, 3) is Some(minute) else { return false }
  guard format_two_digits(text, 6) is Some(second) else { return false }
  let mut index = 8
  if text.get_char(index) == Some('.') {
    index = index + 1
    let fraction_start = index
    while index < text.length() {
      let next = text.get_char(index)
      if next is Some(ch) && format_is_digit(ch) {
        index = index + 1
      } else {
        break
      }
    }
    if index == fraction_start {
      return false
    }
  }
  let mut offset = 0
  let marker = text.get_char(index)
  if marker is Some(ch) && (ch == 'Z' || ch == 'z') {
    index = index + 1
  } else if marker is Some(ch) && (ch == '+' || ch == '-') {
    guard format_two_digits(text, index + 1) is Some(offset_hour) else {
      return false
    }
    guard text.get_char(index + 3) == Some(':') else { return false }
    guard format_two_digits(text, index + 4) is Some(offset_minute) else {
      return false
    }
    if offset_hour > 23 || offset_minute > 59 {
      return false
    }
    let magnitude = offset_hour * 60 + offset_minute
    offset = if ch == '+' { magnitude } else { -magnitude }
    index = index + 6
  } else {
    return false
  }
  if index != text.length() {
    return false
  }
  if hour > 23 || minute > 59 || second > 60 {
    return false
  }
  if second == 60 {
    format_leap_second(hour, minute, offset)
  } else {
    true
  }
}

///|
/// A leap second may only be `:60` when the instant it names is 23:59:60 UTC,
/// so the local hour/minute and the numeric offset must agree.
fn format_leap_second(hour : Int, minute : Int, offset : Int) -> Bool {
  let mut utc = (hour * 60 + minute - offset) % 1440
  if utc < 0 {
    utc = utc + 1440
  }
  utc == 23 * 60 + 59
}

///|
/// `date-time` (RFC 3339 5.6): `full-date "T" full-time`, where the `T` and
/// the zone designator are case-insensitive.
fn format_date_time(value : String) -> Bool {
  let mut split = -1
  for i in 0..<value.length() {
    match value.get_char(i) {
      Some(ch) =>
        if ch == 'T' || ch == 't' {
          if split >= 0 {
            return false
          }
          split = i
        }
      None => return false
    }
  }
  if split != 10 {
    return false
  }
  format_full_date(value[:split]) && format_full_time(value[split + 1:])
}
