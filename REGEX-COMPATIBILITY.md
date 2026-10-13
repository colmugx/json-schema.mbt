# Regex compatibility layer

The validator uses `moonbitlang/regexp@0.3.6`, restoring the regexp engine used
by the original benchmarks after its compiler-compatibility update. This is not
a feature upgrade or a full ECMA-262 conformance claim. Dynamic patterns remain
compiled once per schema. Rejected patterns produce explicit `Unsupported` /
typed errors, never a silently substituted non-match.

## Retained compatibility profile

- ECMA ASCII digit/word classes, whitespace (including vertical tab, NBSP and
  BOM), and dot line-terminator exclusions.
- Hexadecimal `\\xHH` escapes translated to Unicode escapes.
- General_Category short/long aliases are handled by the dependency. The adapter
  normalizes `General_Category=Lu` to `Lu`; it no longer vendors Unicode range or
  alias tables. Negative properties inside classes and property range endpoints
  remain explicitly unsupported in this profile.
- Anchored leading positive/negative lookahead chains are checked using separate
  compiled expressions. Nested captures/lookarounds and ambiguous alternatives
  remain unsupported.
- The exact `^(body)\\1$` repeated-capture profile added during the core migration
  is retained: identical, scalar-boundary-valid halves, with the first half
  checked against the captured expression. Nested noncapturing groups are allowed;
  nested captures, assertions, boundaries and anchors are refused.

Other numeric/named backreferences and script/binary properties remain explicit
unsupported errors. The core-specific repetition limit no longer applies:
`^a{257}$` now has positive and negative regression checks.

## Maintenance markers

Remaining private shims use
`#deprecated(message, skip_current_package=true)` as reminders to review future
upstream releases. Public APIs are not deprecated, and internal calls do not
produce warnings. Remove a shim only when its behavior is covered by the upstream
engine and existing regression tests still pass.

## Verification and benchmark ownership

Native and JS library tests: **33/33** each. Native/JS/Wasm checks and native
release compilation pass. Public pattern signatures are unchanged. The moonx
source generator imports the same pinned regexp version as the native library;
both existing benchmark execution paths remain in place.

Historical full-corpus record from the previous core migration, pin
`5b0ee1613e45fcc2bddac00e07c19cd49b00d8a8`:

- Required: **962/1301**, 0 mismatch, 337 unsupported, 2 rejected.
- Optional: **535/1036**, 480 mismatch, 21 unsupported.

That full corpus and dual-runtime performance campaign were not rerun during this
compiler-compatibility restoration. Do not treat those historical counts or
measurements as freshly verified results for 0.3.6. Use the existing scripts in
`benchmarks/README.md` for the next campaign; this change establishes no new
performance baseline.
