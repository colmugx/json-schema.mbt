# colmugx/json-schema

A compile-once JSON Schema validator for MoonBit, built around **precise
2020-12 validation scenarios** rather than permissive approximations.

**Status: development milestone, not a complete 2020-12 implementation.**
Local static JSON Pointer references are supported, including recursive plans.
Remote references, resource identifiers, dynamic scope and unevaluated semantics
are not implemented; schemas requesting those semantics fail compilation explicitly. See
[the support contract](docs/conformance.md) before adopting the library.

## Use it for

- Closed tool/request argument objects (`additionalProperties: false`).
- Structured result validation, tuples, array membership and dependencies.
- Exact decimal `multipleOf`, integer checks and numeric bounds.
- Unicode code-point string lengths and an explicitly supported pattern profile.
- Reusing one owned compiled schema for many instances.

The module is maintained as an independent repository and has no dependency on
MCP. Run the commands below from this module's root, including when it is checked
out as a workspace member. Runners use `moon run` instead of assuming a fixed
binary output path inside an enclosing workspace.

## Quick start

Import `"colmugx/json-schema"` in your package. Parse numbers through this
library when their original decimal values matter:

```moonbit nocheck
///|
let document = @json-schema.parse(
  "{\"type\":\"object\",\"required\":[\"amount\"],\"properties\":{\"amount\":{\"type\":\"number\",\"multipleOf\":0.1}},\"additionalProperties\":false}",
)

///|
let schema = @json-schema.Schema::compile(document)

///|
let instance = @json-schema.parse("{\"amount\":0.3}")

///|
let valid = schema.valid(instance)

///|
let failures = schema.faults(instance)
```

These operations can raise errors; propagate or catch them at your application's
boundary. A malformed/unsupported schema is not a valid compiled schema. A
malformed numeric node or exhausted traversal budget is not an ordinary `false`
validation result.

### Choose the result you need

- `schema.valid(instance)` short-circuits assertion failures and does not build
  a diagnostic array.
- `schema.faults(instance)` returns failures with `instance_path`, `schema_path`,
  `keyword` and `message`. Paths use JSON Pointer escaping.
- Both methods check the instance's numeric representations and traversal budget.
  Failed speculative `anyOf`, `oneOf`, `not` and `if` branches do not leak errors
  into a successful result.

### Preserve number precision

A floating-point value cannot recover digits lost before validation. This
library's parser keeps number lexemes in `Json::Number`'s `repr` field; numeric
predicates use integer coefficients and decimal scales, not an epsilon or a
rounded decimal quotient. Core-parsed or programmatically constructed numbers
without a lexeme use the available finite `Double` representation instead.

Parsing and arithmetic support are separate: the parser retains valid JSON
number literals even when their exponent exceeds the evaluator's supported
range. Exact arithmetic currently bounds the exponent and decimal scale to
±100000; schema compilation or evaluation outside that range raises a typed
error rather than rounding a value or returning an ordinary validation failure.
This lets protocol callers safely round-trip such literals without claiming
that the validator can execute constraints over every possible decimal scale.

Do not construct inconsistent `Json::number(value, repr=...)` nodes: numeric
representations are checked, not silently discarded.

## Supported now

The compiler/evaluator covers boolean schemas, `type`, `const`, `enum`, numeric
bounds and `multipleOf`, string lengths and patterns, object properties/names/
dependencies, 2020-12 `prefixItems`/`items`, array counts/`contains`/`uniqueItems`,
`allOf`/`anyOf`/`oneOf`/`not`/`if`/`then`/`else`, and same-document static
`$ref` (including `$defs`, forward references and recursive schemas).

Patterns use `moonbitlang/regexp@0.3.6` with a small explicit compatibility layer.
The adapter preserves ECMA shorthand,
whitespace/dot handling, General_Category properties and leading lookahead chains.
Backreferences currently support only the exact `^(body)\\1$` profile; other
unsupported syntax raises a typed error, never a silent non-match. See
[the compatibility profile and upstream review checklist](REGEX-COMPATIBILITY.md).

`format` and content keywords are annotations, **not format/content assertions**.
Unknown extension keywords are annotations. Known malformed supported keywords
are compile errors. An unimplemented known semantic keyword is an explicit
unsupported error, not an ignored assertion.

## Evidence and development

The full pinned official draft2020-12 corpus currently reports **962/1301**
standard cases matched: **0 mismatches, 337 unsupported, 2 rejected**. Optional
cases are reported separately (**535/1036**); format assertions are not enabled.
This is visible progress toward conformance, **not a complete-draft claim**.
Unsupported and rejected cases stay in the denominator.

Run these commands from this independent module's root:

```sh
moon check --target native --deny-warn --output-json
moon test --target native --deny-warn --output-json
moon check --target js --deny-warn --output-json
moon test --target js --deny-warn --output-json
moon check --target wasm --deny-warn --output-json
moonx benchmarks/run-campaign.mbtx
```

The campaign downloads the official corpus, runs every official case, and measures
11 scenarios in **two execution environments**, each with five fresh processes
(110 measurements total):

- `moonx`: validator and timing loop execute inside its linear-memory Wasm sandbox,
  providing a portable-runtime performance baseline.
- `moon run --target native --release`: validator and timing loop execute in the
  device's compiled native binary, providing its native performance baseline.

The two environments use the same workloads and counters, but publish separate
median/min/max tables. A Wasm orchestrator launching native children is not itself
a Wasm validator benchmark. See the [runner guide](benchmarks/README.md) for the
same-source entry generation and build-layout differences.

It saves the corpus, provenance, detailed outcomes and logs in
`benchmark-results/`. Move or remove the previous campaign's `logs/` and `runs/`
before starting another; existing evidence is not overwritten silently.

For a shorter infrastructure check, use
`moonx benchmarks/run-campaign.mbtx smoke`. For case-level TDD, see
[the runner guide](benchmarks/README.md). Ordinary official-suite gaps do not
fail CI; compilation, runtime/harness failures and invalid performance results
**do**. Unit tests cover library-specific contracts rather than duplicating the
full official corpus.

The independent [benchmark workflow](.github/workflows/schema-benchmark.yml)
runs on pushes to `main` and manual dispatch from this independent repository. Standalone `.mbtx` orchestration uses **`moonx`**; the native
package runners can be invoked with `moon run`.

## Performance policy

Correctness comes first. Compilation hoists schema parsing and regular-expression
compilation out of repeated validation; object checks share a property walk.
The current implementation still performs a numeric/depth preflight and uses a
quadratic exact-equality check for `uniqueItems`. It does **not** yet claim to be
the fastest validator. Performance claims require reproducible benchmarks,
representative valid/invalid cases and the same semantics on both sides.

## License

Apache-2.0. Vendored conformance data, when present, retains its upstream license
and pinned-source attribution.
