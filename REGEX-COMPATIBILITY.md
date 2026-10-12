# Core regex compatibility layer

The validator now uses `moonbitlang/core/string.Regex`; it no longer depends on
`moonbitlang/regexp`. Dynamic patterns remain compiled once per schema. An
unexecutable pattern is an explicit `Unsupported` result / typed error, never a
false match silently substituted for a compilation error.

## Supported compatibility profile

- ECMA ASCII digit/word classes, including their supported character-class forms.
- ECMA whitespace (including U+000B, NBSP and BOM) and dot line-terminator exclusions.
- `\\xHH` and vertical-tab escapes translated to core Unicode escapes.
- General_Category short and long aliases, including `General_Category=Lu`,
  translated into scalar ranges. Positive properties work inside classes;
  negative properties inside classes and property range endpoints are refused.
- Existing anchored leading positive/negative lookahead chains, evaluated as
  separate anchored core expressions. Nested captures/lookarounds and ambiguous
  top-level alternatives remain unsupported.
- The precise backreference profile `^(body)\\1$`: a single capture repeated once
  over the whole input. Nested noncapturing groups are allowed. Captures,
  lookarounds, boundaries and anchors inside `body` are refused. Equal UTF-16
  halves must be valid scalar-boundary views and identical, then the first half
  is validated against the captured expression. This preserves the existing
  `^(a)\\1$` contract without pretending to implement general backtracking.

Other numeric/named backreferences, script/binary properties and core-rejected
syntax remain explicit unsupported errors. The installed core currently rejects
bounded repetitions above 256; this is an implementation limit, not a language
specification maximum. This migration is not a full ECMA-262 conformance claim.

## Revisit markers

Private shims and Unicode data are marked
`#deprecated(message, skip_current_package=true)`. These mark maintenance debt,
not a deprecated customer API. Internal calls do not emit warnings, so the
warning-free build gate stays meaningful. This document is the review checklist;
the attribute does not automatically detect upstream releases.

Recheck <https://github.com/moonbitlang/regexp.mbt> after toolchain-compatible
releases. Remove a shim only after equivalent semantics and native/JS/Wasm
support are demonstrated by its regression tests and the complete official
corpus. Do not simply delete successful assertions or convert compiler errors to
ordinary non-matches. The public pattern API and generated interface are unchanged.

## Unicode data provenance

`regex_unicode_ranges.mbt` and `regex_unicode_aliases.mbt` retain the generated
range/alias data from the installed `moonbitlang/regexp@0.3.5` package:

- `internal/unicode/general_category.mbt`
- `internal/unicode/property_value_alises.mbt`

Source project: <https://github.com/moonbitlang/regexp.mbt>, Apache-2.0. Local
changes are attribution headers, private visibility and maintenance attributes;
the data itself is unchanged. The package did not identify the Unicode data
version in these files, so no guessed Unicode-version guarantee is made. Its
surrogate-category ranges are deliberately empty, as in the upstream scalar-based
engine. The applicable upstream notice is retained in
[REGEX-THIRD-PARTY-NOTICE.md](REGEX-THIRD-PARTY-NOTICE.md); the project's LICENSE
contains Apache-2.0. No regexp engine code or external runtime dependency is vendored.

## Migration verification

Complete pinned corpus revision `5b0ee1613e45fcc2bddac00e07c19cd49b00d8a8`:

- Required: **962/1301**, 0 mismatch, 337 unsupported, 2 rejected.
- Optional: **535/1036**, 480 mismatch, 21 unsupported.

Counts are unchanged from the prior implementation. The runner exits 1 with
`coverage_incomplete`, not a compilation/runtime failure. Required cases remain
in the denominator; this does not claim complete draft2020-12 support.

All 30 existing unit tests pass unchanged in intent, plus 3 focused adapter
regressions (33/33 native and JS). Wasm type checking and native release build
pass. The real moonx-Wasm and native-release `pattern` workload both passed smoke
execution; smoke timings are not a new performance baseline. Existing campaign
artifacts were preserved rather than overwritten.
