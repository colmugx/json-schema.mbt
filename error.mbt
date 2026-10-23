///|
pub(all) suberror CompileError {
  InvalidKeyword(path~ : String, reason~ : String)
  UnknownDialect(String)
  UnsupportedVocabulary(dialect~ : String, vocabulary~ : String)
  UnsupportedKeyword(path~ : String, keyword~ : String)
  UnsupportedPattern(path~ : String, pattern~ : String, reason~ : String)
  DepthLimit(Int32)
  /// A well-formed JSON number whose exponent or decimal scale leaves the
  /// ±100000 exact-arithmetic budget. This is a validator resource limit, not
  /// a malformed number: shrink the exponent/scale instead of rewording the
  /// literal. The path locates the offending number in the schema document.
  NumericBudget(path~ : String)
} derive(Debug)

///|
pub(all) suberror EvaluationError {
  DepthLimit(Int32)
  InvalidNumber(path~ : String)
} derive(Debug)

///|
/// One assertion failure. `schema_path` is a JSON Pointer relative to the
/// schema document that owns the failing schema; `schema_uri` identifies that
/// document (`None` when the document was supplied without any URI), so
/// `schema_uri + "#" + schema_path` dereferences the failing position.
pub(all) struct Fault {
  instance_path : String
  schema_path : String
  keyword : String
  message : String
  schema_uri : String?
} derive(Debug, Eq)

///|
pub extend CompileError with @debug.Debug::{to_repr}

///|
pub extend EvaluationError with @debug.Debug::{to_repr}

///|
pub extend Fault with @debug.Debug::{to_repr}

///|
pub extend Fault with Eq::{equal, not_equal}
