///|
struct Counts {
  mut total : Int32
  mut passed : Int32
  mut mismatch : Int32
  mut unsupported : Int32
  mut rejected : Int32
}

///|
fn Counts::Counts() -> Counts {
  { total: 0, passed: 0, mismatch: 0, unsupported: 0, rejected: 0, }
}

///|
fn Counts::record(self : Counts, status : String) -> Unit raise {
  match status {
    "pass" => self.passed += 1
    "mismatch" => self.mismatch += 1
    "unsupported" => self.unsupported += 1
    "rejected" => self.rejected += 1
    _ => fail("unknown case status: " + status)
  }
  self.total += 1
}

///|
fn Counts::json(self : Counts) -> Json {
  {
    "total": self.total,
    "passed": self.passed,
    "mismatch": self.mismatch,
    "unsupported": self.unsupported,
    "rejected": self.rejected,
  }
}

///|
fn object(value : Json) -> Map[String, Json] raise {
  guard value is Object(fields) else {
    fail("expected object in suite/manifest")
  }
  fields
}

///|
fn text(fields : Map[String, Json], key : String) -> String raise {
  guard fields.get(key) is Some(String(value)) else {
    fail("missing string field: " + key)
  }
  value
}

///|
fn count(fields : Map[String, Json], key : String) -> Int32 raise {
  guard fields.get(key) is Some(Number(value, ..)) &&
    value >= 0 &&
    value <= 2147483647.0 &&
    value.floor() == value else {
    fail("invalid integer field: " + key)
  }
  value.to_int()
}

///|
fn array(fields : Map[String, Json], key : String) -> Array[Json] raise {
  guard fields.get(key) is Some(Array(values)) else {
    fail("missing array field: " + key)
  }
  values
}

///|
fn boolean(fields : Map[String, Json], key : String) -> Bool raise {
  match fields.get(key) {
    Some(True) => true
    Some(False) => false
    _ => fail("missing boolean field: " + key)
  }
}

///|
fn safe_relative(path : String) -> Bool {
  !path.is_empty() &&
  !path.has_prefix("/") &&
  !path.contains("\\") &&
  !path.split("/").any(part => part == ".." || part == "." || part.is_empty())
}

///|
fn remote_entries(
  manifest : Map[String, Json],
) -> Array[(String, String)] raise {
  let seen : Set[String] = Set([])
  let entries : Array[(String, String)] = []
  for entry in array(manifest, "remotes") {
    let fields = object(entry)
    let uri = text(fields, "uri")
    let path = text(fields, "path")
    guard !uri.is_empty() && !seen.contains(uri) && safe_relative(path) else {
      fail("invalid or duplicate remote mapping: " + uri)
    }
    seen.add(uri)
    entries.push((uri, path))
  }
  entries
}

///|
fn compile_status(error : @schema.CompileError) -> String {
  match error {
    @schema.CompileError::UnsupportedKeyword(..)
    | @schema.CompileError::UnsupportedPattern(..)
    | @schema.CompileError::UnsupportedVocabulary(..)
    | @schema.CompileError::DepthLimit(_)
    | @schema.CompileError::NumericBudget(..) => "unsupported"
    @schema.CompileError::InvalidKeyword(..)
    | @schema.CompileError::UnknownDialect(_) => "rejected"
  }
}
