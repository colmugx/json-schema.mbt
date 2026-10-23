# colmugx/json-schema

A compile-once JSON Schema validator for MoonBit, built around **precise
2020-12 validation scenarios** rather than permissive approximations.

**Status: development milestone, not a complete 2020-12 implementation.**
Static and dynamic references, resource identifiers and anchors, and
`unevaluatedProperties`/`unevaluatedItems` are supported. Cross-resource references
use an explicit preloaded registry: the compiler and validator never fetch URIs.
Custom dialects can combine recognized standard vocabularies and enforce their
metaschemas; unknown required vocabularies fail compilation. This is not a general
plugin API for arbitrary vocabulary execution. Current profile boundaries and
reproduced evidence are maintained in [the conformance contract](CONFORMANCE.md).

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

### Preload referenced resources

Pass external documents as a URI-to-schema map. `base_uri` is the root document's
retrieval URI; `$id` establishes canonical resource identities and resolves
relative references. An embedded `$id` starts a new resource, with its own anchors.
Registry keys and `base_uri` must be absolute URIs; a relative `$id` requires an
absolute base. Resource namespaces are registered when referenced, so unrelated
legacy-dialect documents can coexist in the registry without being compiled.

```mbt check
///|
test "preloaded resource references" {
  let resources : Map[String, Json] = Map::from_array([
    (
      "https://example.com/schemas/positive",
      { "type": "integer", "minimum": 1 },
    ),
  ])
  let schema = @json-schema.Schema::compile(
    { "$ref": "positive" },
    base_uri="https://example.com/schemas/request",
    resources~,
  )
  assert_true(schema.valid(Json::number(2)))
  assert_false(schema.valid(Json::number(0)))
}
```

Missing resources or anchors and conflicting identities are compile errors,
not network requests or ignored constraints. The compiled schema owns its plan;
mutating the registry or source documents afterwards does not change validation.
`$dynamicRef` uses the evaluation's dynamic resource scope rather than always
following a fixed target. `unevaluated*` observes successful evaluation marks,
including marks from references and all successful `anyOf` branches.

Faults retain document-relative `schema_path` JSON Pointers. `schema_uri`, when
available, identifies the source document containing that pointer, so failures
from different documents can be distinguished without changing pointer syntax.

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
`allOf`/`anyOf`/`oneOf`/`not`/`if`/`then`/`else`, static `$ref` (including
`$defs`, forward references, recursive schemas and preloaded external resources),
`$id`, `$anchor`, `$dynamicAnchor`/`$dynamicRef`, and
`unevaluatedProperties`/`unevaluatedItems`.

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

The completion-roadmap baseline was reproduced on actual native, JS and Wasm
execution: **1301/1301** standard cases, with **0 mismatches, 0 unsupported and
0 rejected**. Optional annotation-mode results were **547/1036**: 480 mismatches,
6 unsupported and 3 rejected. This baseline is not a complete-draft claim and is
not silently relabeled as evidence for later implementation changes.

Use [the conformance contract](CONFORMANCE.md) for the current evidence
entry point, exact provenance, profile distinctions and case-level gap accounting.
Unsupported/rejected cases remain in their original denominator. Historical
`benchmark-results/conformance.json` and `conformance-dialects.json` are historical
snapshots, not automatically the newest checkout's acceptance result.

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
The implementation retains numeric/depth preflight. `uniqueItems` uses exact
pairwise equality generally, with specialized set-based paths for eligible
homogeneous constructed primitive arrays. Precision-bearing and structured values
retain their exact comparison semantics. It does **not** claim to be the fastest
validator. Performance claims require reproducible benchmarks,
representative valid/invalid cases and the same semantics on both sides.

## License

Apache-2.0. Vendored conformance data, when present, retains its upstream license
and pinned-source attribution.
