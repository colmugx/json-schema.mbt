// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

// Whitebox regression tests for the exact count-bound representation
// (`CountBound`) and the malformed-vs-budget lexer classification. Public
// keyword behavior lives in count_test.mbt.

///|
fn count_bound(text : String) -> CountBound raise NumericError {
  CountBound::of_exact(ExactNumber::from_literal(text).unwrap())
}

///|
test "count: compare_int is exact across width, tie and fractional scales" {
  // Zero bounds in every spelling.
  assert_eq(count_bound("0").compare_int(0), 0)
  assert_eq(count_bound("0").compare_int(7), -1)
  assert_eq(count_bound("0.000").compare_int(0), 0)
  assert_eq(count_bound("0e400").compare_int(0), 0)
  assert_eq(count_bound("0.00e500").compare_int(0), 0)
  // Small exact ordering, including the Int64 tie branch.
  assert_eq(count_bound("3").compare_int(2), 1)
  assert_eq(count_bound("3").compare_int(3), 0)
  assert_eq(count_bound("3").compare_int(4), -1)
  assert_eq(count_bound("3.0").compare_int(3), 0)
  assert_eq(count_bound("0.3e1").compare_int(3), 0)
  assert_eq(count_bound("30e-1").compare_int(3), 0)
  assert_eq(count_bound("1e2").compare_int(100), 0)
  assert_eq(count_bound("1e9").compare_int(1000000000), 0)
  assert_eq(count_bound("1e9").compare_int(999999999), 1)
  assert_eq(count_bound("1e9").compare_int(1000000001), -1)
  // The exponent >= 10 width branch.
  assert_eq(count_bound("1e10").compare_int(2147483647), 1)
  // The Int32 ceiling neighborhood.
  assert_eq(count_bound("2147483647").compare_int(2147483647), 0)
  assert_eq(count_bound("2147483647").compare_int(2147483646), 1)
  assert_eq(count_bound("2147483648").compare_int(2147483647), 1)
  assert_eq(count_bound("10000000000").compare_int(2147483647), 1)
  assert_eq(count_bound("2147483646").compare_int(2147483647), -1)
  // Fractional scales normalize by exact divisibility, not by doubling.
  assert_eq(count_bound("5.00").compare_int(5), 0)
  assert_eq(count_bound("5.00").compare_int(4), 1)
  assert_eq(count_bound("5.00").compare_int(6), -1)
  assert_eq(count_bound("6.0").compare_int(5), 1)
  // Huge bounds decide by width without any decimal expansion.
  assert_eq(count_bound("1e100000").compare_int(2147483647), 1)
  assert_eq(count_bound("1.5e100000").compare_int(2147483647), 1)
}

///|
test "count: of_int and compact storage keep no expanded decimals" {
  assert_eq(CountBound::of_int(0).compare_int(0), 0)
  assert_eq(CountBound::of_int(1).compare_int(0), 1)
  assert_eq(CountBound::of_int(1).compare_int(2), -1)
  let huge = count_bound("1e100000")
  assert_eq(huge.coefficient.to_int64(), 1L)
  assert_eq(huge.exponent, 100000)
  let scaled = count_bound("5.00")
  assert_eq(scaled.coefficient.to_int64(), 5L)
  assert_eq(scaled.exponent, 0)
  let zero = count_bound("0.00e500")
  assert_true(zero.coefficient.is_zero())
  assert_eq(zero.exponent, 0)
}

///|
test "count: lexer separates malformed literals from budget exhaustion" {
  for text in ["", "01", "+1", "1.", "1e", "1e+", "-x", "1e1.5", "0x10", "--1"] {
    assert_true(parse_parts(text) is MalformedLiteral, msg=text)
  }
  // Well-formed, but the derived scale leaves the ±100000 budget; an
  // exponent magnitude beyond Int64 is necessarily out of budget too.
  for text in ["1e100001", "1e-100001", "1e-99999999999999999999"] {
    assert_true(parse_parts(text) is BudgetExceeded, msg=text)
  }
  // The budget constrains the derived scale, not the written exponent.
  for text in ["1e100000", "1e-100000", "0.1e100001", "10e-100000"] {
    assert_true(parse_parts(text) is Parsed(_), msg=text)
  }
  // The public literal contract is unchanged: budget exhaustion is not a
  // representable ExactNumber.
  assert_true(ExactNumber::from_literal("1e100001") is None)
  assert_true(ExactNumber::from_literal("0.1e100001") is Some(_))
}
