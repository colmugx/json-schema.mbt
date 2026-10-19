///|
fn uri_subdelimiter(ch : Char) -> Bool {
  ch is ('!' | '$' | '&' | '\'' | '(' | ')' | '*' | '+' | ',' | ';' | '=')
}

///|
fn valid_ipv4(text : StringView) -> Bool {
  let parts = text.split(".").to_array()
  if parts.length() != 4 {
    return false
  }
  for part in parts {
    if part.is_empty() ||
      part.length() > 3 ||
      (part.length() > 1 && part[0] == '0') {
      return false
    }
    let mut value = 0
    for ch in part {
      if !(ch is ('0'..<='9')) {
        return false
      }
      value = value * 10 + ch.to_int() - '0'.to_int()
    }
    if value > 255 {
      return false
    }
  }
  true
}

///|
fn ipv6_units(text : StringView, ipv4~ : Bool) -> Int32? {
  if text.is_empty() {
    return Some(0)
  }
  let groups = text.split(":").to_array()
  let mut units = 0
  for index, group in groups {
    if group.contains(".") {
      if !ipv4 || index != groups.length() - 1 || !valid_ipv4(group) {
        return None
      }
      units += 2
    } else {
      if group.is_empty() || group.length() > 4 {
        return None
      }
      for ch in group {
        if !(ch is ('0'..<='9' | 'a'..<='f' | 'A'..<='F')) {
          return None
        }
      }
      units += 1
    }
  }
  Some(units)
}

///|
fn valid_ip_literal(host : String) -> Bool {
  if host.length() <= 2 || !host.has_suffix("]") {
    return false
  }
  let inner = host[1:host.length() - 1]
  if inner.has_prefix("v") || inner.has_prefix("V") {
    let parts = inner[1:].split(".").to_array()
    if parts.length() < 2 || parts[0].is_empty() {
      return false
    }
    for ch in parts[0] {
      if !(ch is ('0'..<='9' | 'a'..<='f' | 'A'..<='F')) {
        return false
      }
    }
    let offset = parts[0].length() + 2
    if offset >= inner.length() {
      return false
    }
    for ch in inner[offset:] {
      if !(is_unreserved_byte(ch.to_int()) || uri_subdelimiter(ch) || ch == ':') {
        return false
      }
    }
    return true
  }
  let halves = inner.split("::").to_array()
  match halves[:] {
    [whole] => ipv6_units(whole, ipv4=true) == Some(8)
    [left, right] =>
      match (ipv6_units(left, ipv4=false), ipv6_units(right, ipv4=true)) {
        (Some(a), Some(b)) => a + b < 8
        _ => false
      }
    _ => false
  }
}
