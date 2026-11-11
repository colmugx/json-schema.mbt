// Copyright (c) 2026 colmugx
// SPDX-License-Identifier: Apache-2.0

///|
/// `regex` (ECMA-262 pattern syntax): the value must compile as a pattern in
/// this module's documented regex profile, so this is a syntax check and never a
/// match. Patterns the profile refuses rather than miscompiles — nested
/// lookarounds, dialect-invalid escapes — report `false` even where ECMA-262
/// itself would accept them, so the assertion never turns a supported-by-spec
/// pattern into a silent non-match.
fn format_regex(value : String) -> Bool {
  compile_pattern(value) is Supported(_)
}
