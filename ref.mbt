///|
/// Compile-time reference context. The arena arrays (`paths`, `targets`,
/// `visited`, `doc_of`, `resource_of`, `nodes`) are indexed by slot; every
/// slot belongs to one source document (`Doc`) and one schema resource.
/// `registry` maps canonical resource identity URIs to resource indexes;
/// `sites` records where each resource lives (document + root pointer).
/// Resolution descends the indexed documents directly: compilation stays
/// I/O-free and unknown external URIs fail compilation, never fetch.
priv struct RefIndex {
  docs : Array[Doc]
  paths : Array[String]
  targets : Array[Json]
  visited : Array[Bool]
  doc_of : Array[Int32]
  resource_of : Array[Int32]
  mut reference_depth : Int32
  nodes : Array[Plan]
  resources : Array[ResourceMeta]
  sites : Array[(Int32, String)]
  registry : Map[String, Int32]
  anchors : Map[Int32, Map[String, Int32]]
  mut collect_evaluated : Bool
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
      compile_into(
        index,
        index.doc_of[slot],
        index.resource_of[slot],
        index.targets[slot],
        index.paths[slot],
        0,
        limit,
      ),
    )
  }
}

///|
fn slot_at(
  index : RefIndex,
  doc : Int32,
  pointer : String,
  path : String,
) -> Int32 raise CompileError {
  match index.docs[doc].slots.get(pointer) {
    Some(slot) => slot
    // Unreachable for positions the resource scan has seen; reachable when a
    // pointer fragment addresses a non-schema registry document root.
    None => {
      invalid_keyword(path, "reference does not resolve to a schema")
      0
    }
  }
}

///|
/// Split a reference into the part before `#` and the raw fragment. An empty
/// prefix keeps resolution inside the current resource; a nonempty prefix
/// names a resource by URI and must be registered.
fn resolve_reference(
  index : RefIndex,
  resource : Int32,
  reference : String,
  path : String,
  limit : Int32,
) -> (Int32, String?) raise CompileError {
  validate_uri_reference(reference, path)
  match split_at_first(reference, '#') {
    (before, fragment) =>
      if before is "" {
        (resource, fragment)
      } else {
        let identity = canonical_uri(index.resources[resource].uri, before)
        match index.registry.get(identity) {
          Some(target) => (target, fragment)
          None => {
            let mut candidate : Int32? = None
            for doc, source in index.docs {
              if source.identity == Some(identity) ||
                document_has_identity(source.root, source.identity, identity) {
                if candidate is Some(_) {
                  invalid_keyword(
                    path,
                    "ambiguous supplied resource identity: " + identity,
                  )
                }
                candidate = Some(doc)
              }
            }
            match candidate {
              Some(doc) => {
                scan_resource(
                  index,
                  doc,
                  index.docs[doc].root,
                  "",
                  0,
                  true,
                  0,
                  limit,
                )
                match index.registry.get(identity) {
                  Some(target) => (target, fragment)
                  None => {
                    invalid_keyword(
                      path,
                      "resource identity was not registered: " + identity,
                    )
                    (0, None)
                  }
                }
              }
              None => {
                invalid_keyword(
                  path,
                  "reference does not resolve: no supplied schema resource \"" +
                  identity +
                  "\"",
                )
                (0, None)
              }
            }
          }
        }
      }
  }
}

///|
/// The slot of the schema a resource's root position occupies. Missing only
/// for registry entries whose document is not a schema at all.
fn resource_root_slot(
  index : RefIndex,
  doc : Int32,
  root_pointer : String,
  path : String,
) -> Int32 raise CompileError {
  match index.docs[doc].slots.get(root_pointer) {
    Some(slot) => slot
    None => {
      invalid_keyword(path, "reference target is not a schema")
      0
    }
  }
}

///|
fn static_anchor_slot(
  index : RefIndex,
  resource : Int32,
  name : String,
) -> Int32? {
  let ordinary = match index.anchors.get(resource) {
    Some(anchors) => anchors.get(name)
    None => None
  }
  match ordinary {
    Some(slot) => Some(slot)
    None => index.resources[resource].dynamic_anchors.get(name)
  }
}

///|
/// Resolve a `$ref` to its arena slot. The reference resolves against the
/// canonical URI of the current schema resource (RFC 3986): an empty fragment
/// is the resource root, a `/`-led fragment is a JSON Pointer relative to
/// that root, and a plain-name fragment is an `$anchor` of the resource.
fn resolve_ref(
  index : RefIndex,
  resource : Int32,
  reference : String,
  path : String,
  limit : Int32,
) -> Int32 raise CompileError {
  let (target, fragment) = resolve_reference(
    index, resource, reference, path, limit,
  )
  let (doc, root_pointer) = index.sites[target]
  match fragment {
    None | Some("") => {
      let slot = resource_root_slot(index, doc, root_pointer, path)
      ensure_compiled(index, slot, limit)
      slot
    }
    Some(raw) => {
      let decoded = percent_decode(raw, path)
      let slot = if decoded.get_char(0) == Some('/') {
        descend_pointer(index, doc, root_pointer, decoded, path)
      } else {
        let name = decoded
        match static_anchor_slot(index, target, name) {
          Some(slot) => slot
          None => {
            invalid_keyword(
              path,
              "reference does not resolve: unknown anchor \"" + name + "\"",
            )
            0
          }
        }
      }
      ensure_compiled(index, slot, limit)
      slot
    }
  }
}

///|
/// Resolve a `$dynamicRef` to its initial target and dynamic name. Per
/// 2020-12 core section 8.2.3.2, runtime resolution participates only when
/// the initially resolved target carries a `$dynamicAnchor` with the
/// fragment's name; otherwise the reference behaves exactly like `$ref` —
/// including pointer fragments, empty fragments and static `$anchor` targets.
/// The evaluator then replaces the initial target with the outermost
/// resource of the dynamic scope defining the same `$dynamicAnchor`.
fn resolve_dynamic_ref(
  index : RefIndex,
  resource : Int32,
  reference : String,
  path : String,
  limit : Int32,
) -> (Int32, String?) raise CompileError {
  let (target, fragment) = resolve_reference(
    index, resource, reference, path, limit,
  )
  let (doc, root_pointer) = index.sites[target]
  match fragment {
    None | Some("") => {
      let slot = resource_root_slot(index, doc, root_pointer, path)
      ensure_compiled(index, slot, limit)
      (slot, None)
    }
    Some(raw) => {
      let decoded = percent_decode(raw, path)
      if decoded.get_char(0) == Some('/') {
        let slot = descend_pointer(index, doc, root_pointer, decoded, path)
        ensure_compiled(index, slot, limit)
        (slot, None)
      } else {
        let name = decoded
        match index.resources[target].dynamic_anchors.get(name) {
          Some(slot) => {
            ensure_compiled(index, slot, limit)
            (slot, Some(name))
          }
          None =>
            match static_anchor_slot(index, target, name) {
              Some(slot) => {
                ensure_compiled(index, slot, limit)
                (slot, None)
              }
              None => {
                invalid_keyword(
                  path,
                  "dynamic reference does not resolve: no \"$dynamicAnchor\" named \"" +
                  name +
                  "\"",
                )
                (0, None)
              }
            }
        }
      }
    }
  }
}

///|
/// Walk a percent-decoded JSON Pointer from a document root through the
/// resource's embedded position, building the canonical pointer used for
/// slot lookup. The resource root pointer is already canonical (escaped), so
/// its segments only need unescaping to step through values; fragment
/// segments are decoded first, then re-escaped canonically.
fn descend_pointer(
  index : RefIndex,
  doc : Int32,
  root_pointer : String,
  decoded : String,
  path : String,
) -> Int32 raise CompileError {
  let mut current = index.docs[doc].root
  for segment in root_pointer.split("/")[1:] {
    current = pointer_child(current, pointer_unescape(segment, path), path)
  }
  let mut canonical = root_pointer
  for segment in decoded.split("/")[1:] {
    let key = pointer_unescape(segment, path)
    current = pointer_child(current, key, path)
    canonical = pointer_step(canonical, key)
  }
  guard current is (Object(_) | True | False) else {
    invalid_keyword(path, "reference target is not a schema")
    return 0
  }
  slot_at(index, doc, canonical, path)
}

///|
fn pointer_child(
  current : Json,
  key : String,
  path : String,
) -> Json raise CompileError {
  match current {
    Object(fields) =>
      match fields.get(key) {
        Some(child) => child
        None => {
          invalid_keyword(path, "reference does not resolve: missing member")
          Json::null()
        }
      }
    Array(values) =>
      match array_token(key) {
        Some(position) =>
          if position < values.length() {
            values[position]
          } else {
            invalid_keyword(
              path, "reference does not resolve: array index out of range",
            )
            Json::null()
          }
        None => {
          invalid_keyword(
            path, "reference does not resolve: invalid array index token",
          )
          Json::null()
        }
      }
    _ => {
      invalid_keyword(path, "reference does not resolve through a scalar")
      Json::null()
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
