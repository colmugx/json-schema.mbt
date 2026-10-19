///|
/// Parsed RFC 3986 URI reference. Parsing preserves the raw spelling of every
/// component; canonicalization (`Uri::normalize`) applies the scheme/host
/// case folding, percent-encoding normalization and dot-segment removal that
/// make two spellings of the same resource collide in the registry.
priv struct Uri {
  scheme : String? // lowercase, without ":"
  authority : String? // without leading "//"
  path : String
  query : String? // without "?"
  fragment : String? // without "#"
}

///|
/// First position of `mark` as a UTF-16 offset, if present.
fn find_unit(text : String, mark : Char) -> Int32? {
  for i in 0..<text.length() {
    if text.get_char(i) == Some(mark) {
      return Some(i)
    }
  }
  None
}

///|
fn find_last_unit(text : String, mark : Char) -> Int32? {
  for i = text.length() - 1; i >= 0; i = i - 1 {
    if text.get_char(i) == Some(mark) {
      return Some(i)
    }
  }
  None
}

///|
fn validate_uri_reference(
  text : String,
  path : String,
) -> Unit raise CompileError {
  let mut position = 0
  let mut fragment = false
  while position < text.length() {
    let unit = text[position]
    if unit <= 0x20 ||
      unit >= 0x7f ||
      unit is ('\\' | '"' | '<' | '>' | '^' | '`' | '{' | '|' | '}') {
      invalid_keyword(path, "invalid character in URI-reference")
    }
    if unit is '#' {
      if fragment {
        invalid_keyword(path, "multiple fragment delimiters in URI-reference")
      }
      fragment = true
    }
    if unit is '%' {
      if position + 2 >= text.length() {
        invalid_keyword(path, "truncated percent-escape in URI-reference")
      }
      for index in (position + 1)..<=(position + 2) {
        if !(text[index] is ('0'..<='9' | 'a'..<='f' | 'A'..<='F')) {
          invalid_keyword(path, "invalid percent-escape in URI-reference")
        }
      }
      position += 3
    } else {
      position += 1
    }
  }
  let parsed = Uri::parse(text)
  for ch in parsed.path {
    if !(is_unreserved_byte(ch.to_int()) ||
      uri_subdelimiter(ch) ||
      ch is ('%' | ':' | '@' | '/')) {
      invalid_keyword(path, "invalid URI path character")
    }
  }
  for component in [parsed.query, parsed.fragment] {
    if component is Some(value) {
      for ch in value {
        if !(is_unreserved_byte(ch.to_int()) ||
          uri_subdelimiter(ch) ||
          ch is ('%' | ':' | '@' | '/' | '?')) {
          invalid_keyword(path, "invalid URI query or fragment character")
        }
      }
    }
  }
  if parsed.scheme is None && parsed.authority is None {
    let first = parsed.path.split("/").next().unwrap_or("")
    if first.contains(":") {
      invalid_keyword(path, "invalid URI scheme or relative first segment")
    }
  }
  if parsed.authority is Some(authority) {
    let hostport = match split_at_first(authority, '@') {
      (_, Some(rest)) => rest
      (rest, None) => rest
    }
    if hostport.contains("@") {
      invalid_keyword(path, "multiple URI userinfo delimiters")
    }
    let (host, port) = split_host_port(hostport)
    if host.has_prefix("[") {
      if !valid_ip_literal(host) {
        invalid_keyword(path, "invalid bracketed URI host")
      }
    } else {
      for ch in host {
        if !(is_unreserved_byte(ch.to_int()) ||
          uri_subdelimiter(ch) ||
          ch == '%') {
          invalid_keyword(path, "invalid URI host")
        }
      }
    }
    if port is Some(port) {
      for unit in port {
        if !(unit is ('0'..<='9')) {
          invalid_keyword(path, "invalid URI port")
        }
      }
    }
  }
}

///|
fn validate_document_uri(
  text : String,
  path : String,
) -> Unit raise CompileError {
  validate_uri_reference(text, path)
  let uri = Uri::parse(text)
  if uri.scheme is None {
    invalid_keyword(path, "document URI must be absolute")
  }
  if uri.fragment is Some(fragment) && fragment != "" {
    invalid_keyword(path, "document URI must not contain a non-empty fragment")
  }
}

///|
fn split_at_first(text : String, mark : Char) -> (String, String?) {
  match find_unit(text, mark) {
    Some(i) => (text[:i].to_owned(), Some(text[i + 1:].to_owned()))
    None => (text, None)
  }
}

///|
fn Uri::parse(text : String) -> Uri {
  let (before_fragment, fragment) = split_at_first(text, '#')
  let (before_query, query) = split_at_first(before_fragment, '?')
  let (scheme, after_scheme) = split_scheme(before_query)
  let (authority, path) = if after_scheme.has_prefix("//") {
    let remainder = after_scheme[2:].to_owned()
    match split_at_first(remainder, '/') {
      (authority, Some(path)) => (Some(authority), "/" + path)
      (authority, None) => (Some(authority), "")
    }
  } else {
    (None, after_scheme)
  }
  { scheme, authority, path, query, fragment, }
}

///|
/// RFC 3986 scheme production: `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`
/// followed by ":". A colon appearing after "/", "?" or a non-scheme
/// character is part of the path, not a scheme delimiter.
fn split_scheme(text : String) -> (String?, String) {
  let units = text.length()
  guard units > 0 else { return (None, text) }
  guard text.get_char(0) is Some('a'..<='z' | 'A'..<='Z') else {
    return (None, text)
  }
  let mut cursor = 1
  while cursor < units {
    match text.get_char(cursor) {
      Some(':') =>
        return (
          Some(text[:cursor].to_owned().to_lower()),
          text[cursor + 1:].to_owned(),
        )
      Some('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '+' | '-' | '.') =>
        cursor += 1
      _ => return (None, text)
    }
  }
  (None, text)
}

///|
/// RFC 3986 section 5.2.2 reference resolution with the base as receiver.
fn Uri::resolve(self : Uri, reference : Uri) -> Uri {
  if reference.scheme is Some(_) {
    return {
      scheme: reference.scheme,
      authority: reference.authority,
      path: remove_dot_segments(reference.path),
      query: reference.query,
      fragment: reference.fragment,
    }
  }
  let authority = match reference.authority {
    Some(_) => reference.authority
    None => self.authority
  }
  let (path, query) = if reference.authority is Some(_) {
    (remove_dot_segments(reference.path), reference.query)
  } else if reference.path is "" {
    let inherited = match reference.query {
      Some(_) => reference.query
      None => self.query
    }
    (self.path, inherited)
  } else if reference.path.has_prefix("/") {
    (remove_dot_segments(reference.path), reference.query)
  } else {
    (remove_dot_segments(merge_paths(self, reference.path)), reference.query)
  }
  { scheme: self.scheme, authority, path, query, fragment: reference.fragment, }
}

///|
/// RFC 3986 section 5.2.3 path merge for relative references.
fn merge_paths(base : Uri, path : String) -> String {
  if base.authority is Some(_) && base.path is "" {
    return "/" + path
  }
  match find_last_unit(base.path, '/') {
    None => path
    Some(last) => base.path[:last + 1].to_owned() + path
  }
}

///|
/// RFC 3986 section 5.2.4 dot-segment removal over the whole path.
fn remove_dot_segments(path : String) -> String {
  let mut input : StringView = path[:]
  let output = StringBuilder()
  while input.length() > 0 {
    if input.has_prefix("../") {
      input = input[3:]
    } else if input.has_prefix("./") {
      input = input[2:]
    } else if input.has_prefix("/./") {
      // "/./x" -> "/x": dropping two units keeps the leading slash.
      input = input[2:]
    } else if input == "/." {
      input = "/"[:]
    } else if input.has_prefix("/../") {
      input = input[3:]
      remove_last_segment(output)
    } else if input == "/.." {
      input = "/"[:]
      remove_last_segment(output)
    } else if input == "." || input == ".." {
      input = ""[:]
    } else {
      let mut end = 1
      let len = input.length()
      while end < len && input.get_char(end) != Some('/') {
        end += 1
      }
      output.write_string(input[:end].to_owned())
      input = input[end:]
    }
  }
  output.to_string()
}

///|
/// Remove the final segment and its preceding slash (RFC 3986, 5.2.4).
fn remove_last_segment(output : StringBuilder) -> Unit {
  let text = output.to_string()
  output.reset()
  match find_last_unit(text, '/') {
    Some(last) => output.write_string(text[:last].to_owned())
    None => ()
  }
}

///|
/// Percent-encoding normalization (RFC 3986 section 6.2.2.2): uppercase hex
/// triplets and decoding of unreserved characters. Invalid or truncated
/// escapes pass through untouched. Components may carry raw UTF-8, so the
/// bytes are rebuilt as a whole; undecodable output keeps the input spelling.
fn percent_normalize(text : String) -> String {
  let raw = @utf8.encode(text)
  let out : Array[Byte] = []
  let length = raw.length()
  let mut cursor = 0
  while cursor < length {
    if raw[cursor] is b'%' &&
      cursor + 2 < length &&
      hex_digit(raw[cursor + 1]) is Some(high) &&
      hex_digit(raw[cursor + 2]) is Some(low) {
      let value = high * 16 + low
      if is_unreserved_byte(value) {
        out.push(value.to_byte())
      } else {
        out.push(b'%')
        out.push(upper_hex_digit(high))
        out.push(upper_hex_digit(low))
      }
      cursor += 3
    } else {
      out.push(raw[cursor])
      cursor += 1
    }
  }
  @utf8.decode(Bytes::from_array(out[:])) catch {
    _ => abort("URI normalization produced invalid UTF-8")
  }
}

///|
fn is_unreserved_byte(value : Int32) -> Bool {
  (value >= 'A'.to_int() && value <= 'Z'.to_int()) ||
  (value >= 'a'.to_int() && value <= 'z'.to_int()) ||
  (value >= '0'.to_int() && value <= '9'.to_int()) ||
  value == '-'.to_int() ||
  value == '.'.to_int() ||
  value == '_'.to_int() ||
  value == '~'.to_int()
}

///|
fn upper_hex_digit(value : Int32) -> Byte {
  if value < 10 {
    ('0'.to_int() + value).to_byte()
  } else {
    ('A'.to_int() + value - 10).to_byte()
  }
}

///|
/// Host case folding (RFC 3986 section 6.2.2.1) plus default-port removal
/// for the schemes where the port is famously fixed.
fn normalize_authority(authority : String, scheme : String?) -> String {
  let (userinfo, hostport) = match split_at_first(authority, '@') {
    (info, Some(rest)) => (Some(info), rest)
    (rest, None) => (None, rest)
  }
  let (host, port) = split_host_port(hostport)
  let trimmed = match (scheme, port) {
    (Some("http"), Some(p)) if p == "80" => None
    (Some("https"), Some(p)) if p == "443" => None
    (_, other) => other
  }
  let mut combined = percent_normalize(host).to_lower()
  if trimmed is Some(p) {
    combined = combined + ":" + p
  }
  match userinfo {
    Some(info) => percent_normalize(info) + "@" + combined
    None => combined
  }
}

///|
/// Split host and port, keeping IPv6 literals (`[::1]:80`) intact.
fn split_host_port(hostport : String) -> (String, String?) {
  if hostport.has_prefix("[") {
    match find_unit(hostport, ']') {
      Some(close) =>
        if close + 1 < hostport.length() &&
          hostport.get_char(close + 1) == Some(':') {
          (
            hostport[:close + 1].to_owned(),
            Some(hostport[close + 2:].to_owned()),
          )
        } else {
          (hostport, None)
        }
      None => (hostport, None)
    }
  } else {
    match split_at_first(hostport, ':') {
      (host, Some(port)) => (host, Some(port))
      (host, None) => (host, None)
    }
  }
}

///|
/// Canonical form used for resource identity: percent- and case-normalized,
/// without the fragment. Fragment-less identity is what the registry keys on.
fn Uri::identity(self : Uri) -> String {
  let builder = StringBuilder()
  if self.scheme is Some(scheme) {
    builder.write_string(scheme + ":")
  }
  if self.authority is Some(authority) {
    builder.write_string("//" + authority)
  }
  builder.write_string(self.path)
  if self.query is Some(query) {
    builder.write_string("?" + query)
  }
  builder.to_string()
}

///|
fn Uri::normalize(self : Uri) -> Uri {
  {
    scheme: self.scheme,
    authority: self.authority.map(a => normalize_authority(a, self.scheme)),
    path: remove_dot_segments(percent_normalize(self.path)),
    query: self.query.map(percent_normalize),
    fragment: self.fragment.map(percent_normalize),
  }
}

///|
/// Canonical document identity for a URI-reference supplied as base or
/// registry key: resolved, normalized, fragment stripped.
fn canonical_document_uri(text : String) -> String {
  Uri::parse(text).normalize().identity()
}

///|
/// Resolve a URI-reference (the value of `$id`, `$ref` or `$dynamicRef`)
/// against `base` and return the canonical fragment-less identity URI.
fn canonical_uri(base : String?, reference : String) -> String {
  let parsed = Uri::parse(reference)
  let resolved = if parsed.scheme is Some(_) {
    parsed
  } else {
    let base_uri = match base {
      Some(text) => Uri::parse(text)
      None =>
        {
          scheme: None,
          authority: None,
          path: "",
          query: None,
          fragment: None,
        }
    }
    base_uri.resolve(parsed)
  }
  resolved.normalize().identity()
}

///|
/// `$anchor`/`$dynamicAnchor` fragment names: start with a letter or
/// underscore, then letters, digits, hyphens, underscores or periods
/// (2020-12 core, US-ASCII part of XML's NCName production).
fn plain_name(text : StringView) -> Bool {
  let length = text.length()
  guard length > 0 else { return false }
  guard text.get_char(0) is Some('a'..<='z' | 'A'..<='Z' | '_') else {
    return false
  }
  for i in 1..<length {
    guard text.get_char(i)
      is Some('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '-' | '_' | '.') else {
      return false
    }
  }
  true
}
