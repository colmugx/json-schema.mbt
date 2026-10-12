///|
/// Compile-time reference context. `slots` maps the canonical escaped pointer
/// of every object/boolean schema position to its arena index in `nodes`;
/// slot 0 is always the document root. Positions the keyword walk never
/// visits (unknown extension keywords, annotation payloads) stay unvisited
/// and are compiled on first reference, so unreferenced annotation content
/// is never schema-checked while referenced targets always are. `visited`
/// also marks the active compile chain, so mutually recursive unknown-keyword
/// targets terminate. Resolution descends `root` directly: compilation stays
/// I/O-free and external URIs are refused, never fetched.
priv struct RefIndex {
  root : Json
  slots : Map[String, Int32]
  paths : Array[String]
  targets : Array[Json]
  visited : Array[Bool]
  mut reference_depth : Int32
  nodes : Array[Plan]
}

///|
fn index_walk(
  index : RefIndex,
  value : Json,
  pointer : String,
  depth : Int32,
  limit : Int32,
) -> Unit raise CompileError {
  if depth > limit {
    raise CompileError::DepthLimit(limit)
  }
  if value is (Object(_) | True | False) {
    let slot = index.slots.length()
    index.slots[pointer] = slot
    index.paths.push(pointer)
    index.targets.push(value)
    index.visited.push(false)
    index.nodes.push(Accept)
  }
  match value {
    Object(fields) =>
      for name, child in fields {
        index_walk(index, child, pointer_step(pointer, name), depth + 1, limit)
      }
    Array(values) =>
      for position, child in values {
        index_walk(
          index,
          child,
          pointer_step(pointer, position.to_string()),
          depth + 1,
          limit,
        )
      }
    _ => ()
  }
}

///|
/// One pre-compilation pass assigns an arena slot to every schema position,
/// including positions that appear textually after the `$ref` keywords that
/// target them, so forward references need no fixup phase.
fn index_document(
  document : Json,
  limit : Int32,
) -> RefIndex raise CompileError {
  let index : RefIndex = {
    root: document,
    slots: Map([]),
    paths: [],
    targets: [],
    visited: [],
    reference_depth: 0,
    nodes: [],
  }
  index_walk(index, document, "", 0, limit)
  index
}

///|
/// Compile an arena slot if no walk has reached it yet. The visited flag is
/// raised on entry to `compile_into`, so it doubles as the active-chain mark
/// and mutually recursive unknown-keyword targets terminate: the frame that
/// owns the slot writes its plan on return.
fn ensure_compiled(
  index : RefIndex,
  slot : Int32,
  limit : Int32,
) -> Unit raise CompileError {
  if !index.visited[slot] {
    if index.reference_depth >= limit {
      raise CompileError::DepthLimit(limit)
    }
    index.reference_depth += 1
    defer {
      index.reference_depth -= 1
    }
    ignore(
      compile_into(index, index.targets[slot], index.paths[slot], 0, limit),
    )
  }
}

///|
fn slot_at(
  index : RefIndex,
  pointer : String,
  path : String,
) -> Int32 raise CompileError {
  match index.slots.get(pointer) {
    Some(slot) => slot
    // Unreachable: every object/boolean position receives a slot.
    None => {
      invalid_keyword(path, "reference does not resolve to a schema")
      0
    }
  }
}

///|
/// RFC 3986 percent-decoding over UTF-8 bytes. Decoding happens before JSON
/// Pointer unescaping (URI layer first). Malformed escapes and non-UTF-8
/// byte sequences fail compilation instead of silently mangling a pointer.
fn percent_decode(text : String, path : String) -> String raise CompileError {
  let raw = @utf8.encode(text)
  let bytes : Array[Byte] = []
  let length = raw.length()
  let mut cursor = 0
  while cursor < length {
    if raw[cursor] is b'%' {
      if cursor + 2 >= length {
        invalid_keyword(path, "truncated percent-escape in reference")
        return ""
      }
      let high = hex_digit(raw[cursor + 1])
      let low = hex_digit(raw[cursor + 2])
      if high is None || low is None {
        invalid_keyword(path, "invalid percent-escape in reference")
        return ""
      }
      bytes.push((high.unwrap() * 16 + low.unwrap()).to_byte())
      cursor += 3
    } else {
      bytes.push(raw[cursor])
      cursor += 1
    }
  }
  @utf8.decode(Bytes::from_array(bytes[:])) catch {
    _ => {
      invalid_keyword(path, "reference fragment is not valid UTF-8")
      ""
    }
  }
}

///|
fn hex_digit(unit : Byte) -> Int32? {
  let value = unit.to_int()
  let digit = value - '0'.to_int()
  if digit >= 0 && digit <= 9 {
    Some(digit)
  } else if value >= 'a'.to_int() && value <= 'f'.to_int() {
    Some(value - 'a'.to_int() + 10)
  } else if value >= 'A'.to_int() && value <= 'F'.to_int() {
    Some(value - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// JSON Pointer unescaping: `~1` becomes `/` and `~0` becomes `~`. A `~`
/// followed by any other unit, or a trailing `~`, is a malformed pointer.
fn pointer_unescape(
  segment : StringView,
  path : String,
) -> String raise CompileError {
  let builder = StringBuilder()
  let mut escaped = false
  for ch in segment {
    if escaped {
      match ch {
        '0' => {
          builder.write_char('~')
          escaped = false
        }
        '1' => {
          builder.write_char('/')
          escaped = false
        }
        _ => {
          invalid_keyword(path, "invalid JSON Pointer escape in reference")
          return ""
        }
      }
    } else if ch is '~' {
      escaped = true
    } else {
      builder.write_char(ch)
    }
  }
  if escaped {
    invalid_keyword(path, "invalid JSON Pointer escape in reference")
    return ""
  }
  builder.to_string()
}

///|
/// RFC 6901 array tokens: `"0"` or a canonical decimal without leading zeros.
/// `-` and non-canonical forms never match, so they resolve as dangling.
fn array_token(segment : String) -> Int32? {
  let length = segment.length()
  if length <= 0 {
    return None
  }
  let first = segment[0].to_int() - '0'.to_int()
  if first < 0 || first > 9 {
    return None
  }
  if length == 1 {
    return Some(first)
  }
  if first == 0 {
    return None
  }
  let mut value = first
  for position in 1..<length {
    let digit = segment[position].to_int() - '0'.to_int()
    if digit < 0 || digit > 9 {
      return None
    }
    if value > 214748364 || (value == 214748364 && digit > 7) {
      return None
    }
    value = value * 10 + digit
  }
  Some(value)
}

///|
/// Resolve a same-document reference to its arena slot. The part before `#`
/// must be empty (other resources stay unsupported); an empty fragment is the
/// root; a fragment starting with `/` is a JSON Pointer; anything else is an
/// anchor-style name, which requires the unsupported `$anchor` vocabulary.
fn resolve_ref(
  index : RefIndex,
  reference : String,
  path : String,
  limit : Int32,
) -> Int32 raise CompileError {
  let mut split = -1
  let units = reference.length()
  for position in 0..<units {
    if reference[position] is '#' {
      split = position
      break
    }
  }
  if split > 0 {
    raise UnsupportedKeyword(path~, keyword="$ref")
  }
  let raw = if split >= 0 {
    reference[split + 1:].to_owned()
  } else {
    reference
  }
  let decoded = percent_decode(raw, path)
  if decoded is "" {
    let slot = slot_at(index, "", path)
    ensure_compiled(index, slot, limit)
    return slot
  }
  if split < 0 {
    // A nonempty reference without a fragment names another resource.
    raise UnsupportedKeyword(path~, keyword="$ref")
  }
  if !(decoded.get_char(0) is Some('/')) {
    // Plain-name fragments are anchors, which stay unsupported.
    raise UnsupportedKeyword(path~, keyword="$anchor")
  }
  let mut current = index.root
  let mut canonical = ""
  for segment in decoded.split("/")[1:] {
    let key = pointer_unescape(segment, path)
    match current {
      Object(fields) =>
        match fields.get(key) {
          Some(child) => {
            current = child
            canonical = pointer_step(canonical, key)
          }
          None => {
            invalid_keyword(path, "reference does not resolve: missing member")
            return 0
          }
        }
      Array(values) =>
        match array_token(key) {
          Some(position) =>
            if position < values.length() {
              current = values[position]
              canonical = pointer_step(canonical, key)
            } else {
              invalid_keyword(
                path, "reference does not resolve: array index out of range",
              )
              return 0
            }
          None => {
            invalid_keyword(
              path, "reference does not resolve: invalid array index token",
            )
            return 0
          }
        }
      _ => {
        invalid_keyword(path, "reference does not resolve through a scalar")
        return 0
      }
    }
  }
  guard current is (Object(_) | True | False) else {
    invalid_keyword(path, "reference target is not a schema")
    return 0
  }
  let slot = slot_at(index, canonical, path)
  ensure_compiled(index, slot, limit)
  slot
}
