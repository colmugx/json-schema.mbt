///|
// Shared by native, JS and Wasm. File I/O and report publication stay in main.
fn evaluate_case(
  compiled : Result[@schema.Schema, @schema.CompileError],
  value : Json,
  expected : Bool,
  id : String,
) -> (String, Bool?, String?) raise {
  match compiled {
    Ok(schema) => {
      let actual = schema.valid(value)
      guard schema.faults(value).is_empty() == actual else {
        fail("valid/faults disagreement: " + id)
      }
      (if actual == expected { "pass" } else { "mismatch" }, Some(actual), None)
    }
    Err(error) => (compile_status(error), None, Some("\{Repr(error)}"))
  }
}
