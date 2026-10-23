# Draft 2020-12 conformance contract and evidence

This is the single entry point for the independent validator's supported profiles,
limitations and current validation evidence. Passing a finite official corpus is
not a proof of every normative requirement. Historical reports remain historical.

## Reproduced baseline

The roadmap started from validator commit
`ac6f89371e1cacf87848e86af0c1d97d95bb2880` (version 0.1.4, clean validator sources).
The fixed official corpus is
`5b0ee1613e45fcc2bddac00e07c19cd49b00d8a8`.

Toolchain: `moon 0.1.20261016 (1af328f)`;
`moonc v0.10.16+b1a0e846e`; `moonrun 0.1.20261016`.

| Actual execution target | Standard | Optional | Report |
| --- | --- | --- | --- |
| native release | 1301/1301 | 547/1036 | `benchmark-results/roadmap/baseline-conformance.json` |
| Node/JS release | 1301/1301 | 547/1036 | `benchmark-results/roadmap/baseline-js-conformance.json` |
| linear-memory Wasm release | 1301/1301 | 547/1036 | `benchmark-results/roadmap/baseline-wasm-conformance.json` |

The native baseline preceded the runner portability change; JS/Wasm used the same
validator sources with a shared scoring function and a Node argv adapter. These
were actual `moon run cmd/conformance --target TARGET --release --output-json`
executions, not checks, and not native children mislabeled as Wasm.

Every baseline runner returned exit **1**, deliberately: optional gaps keep the
full campaign incomplete, even though all standard cases passed. Exit 2 denotes a
harness/runtime failure and is never accepted as ordinary incomplete coverage.

Optional baseline accounting: 480 mismatches, 6 unsupported and 3 rejected.
`benchmarks/summarize-conformance.mbtx` preserves every failed case ID and groups
it without removing anything from the denominator:

- 466 format-fixture mismatches: format assertion is disabled in the default
  annotation-only profile; these are not relabeled as passes.
- 14 legacy `dependencies` compatibility mismatches. The obsolete keyword is not
  an assertion of the standard 2020-12 dialect. This is a separate compatibility
  profile, not permission to change unknown-keyword semantics.
- 4 unsupported ECMA control-escape cases (`\\cC`, `\\cc`).
- 4 format-assertion/meta-schema cases rejected or unsupported.
- 1 cross-draft case requiring the excluded 2019-09 dialect.

Detailed baseline classification:
`benchmark-results/roadmap/baseline-summary.json`. These artifacts are retained as
run evidence, not temporary probes. Reproduce from this independent module root;
do not run a new campaign over an existing evidence directory.

## Scope and normative obligations

Normative strength below is kept separate from implementation status. The matrix
is an audit index, not an assertion that the entire specification has been proved.

| Requirement / scope | Strength and contract | Owner / evidence | Roadmap verification |
| --- | --- | --- | --- |
| JSON Schema data model and numeric equality | Core 4.2: mathematical values, not binary64 approximations; object order irrelevant | `numeric.mbt`, `validate.mbt`, numeric tests; standard `enum`, `const`, `multipleOf`, `uniqueItems` | Audit extreme exponents, equivalent literal spellings and resource-error distinctions |
| Nonnegative integer counts | Validation 6: integer constraints have no Int32 semantic upper bound | `compile_count`, object/array plans and evaluators | Remove count-range rejection without truncation or floating conversion |
| Pattern matching | Core 6.4 / Validation 6.3.3: not implicitly anchored (MUST); ECMA and Unicode interoperability recommendations (SHOULD) | `regex_adapter.mbt`, `regex_compatibility.mbt`; official ECMA/non-BMP files | Preserve unsupported errors; separately document the actual supported regex language |
| Core identifiers, references, schema resources | Core 8/9: canonical/resource identities and lexical/dynamic scope | `resource*.mbt`, `ref.mbt`, `uri*.mbt`; official reference/anchor/dynamic cases | Audit rebasing, bundling, duplicate identities, percent escapes and recursive graphs |
| Dialects and vocabularies | Core 8.1: unknown required vocabulary cannot be silently accepted; core remains required | `dialect.mbt`, `builtin_metaschemas.mbt`, dialect tests | Audit resource-local dialect changes and metaschema boundaries |
| Applicators | Core 10: combine assertion results and annotations with keyword-specific semantics | `evaluate*.mbt`; all/any/one/not/conditional/dependency official files | Supplement branch order, failed-branch isolation and reference combinations |
| Unevaluated keywords | Core 11: evaluated annotations from applicable successful evaluation affect remaining locations | `EvaluationMarks`, object/array evaluators; official unevaluated files | Keep internal marks distinct from the public annotation-result API |
| Metadata and unknown keywords | Core 7.7 and Validation 9: annotations, not instance mutation | schema compiler and explicit result collection | Collect only when requested; never apply default or leak failed branch annotations |
| Format annotation | Validation 7.2.1: default assertion evaluation disabled; collect format when collecting annotations | `dialect.mbt` and explicit annotation/output path | Preserve default behavior and unknown format annotation values |
| Format assertion | Validation 7.2.2: OPTIONAL vocabulary; when declared required, provide its complete supported contract or refuse schema | format implementation, dialect integration, format fixtures | Separate assertion profile; no DNS, network or entity-existence checks |
| Content keywords | Validation 8: annotations, not automatic decoding or asserted rejection | compiler and annotation output | Do not fetch, decode, execute or change overall validity by default |
| Standard output | Core 12 and official output schema; distinguish result shape from message wording | explicit output implementation/tests | Validate serialized output and reference-sensitive locations; flat Fault is not automatically standard Basic |
| Resource limits | Operational limits are not assertion failures | parser/compiler/evaluation typed errors and budget tests | Terminate adversarial inputs and distinguish budget exhaustion from malformed numbers |

## Profile boundaries

- The default dialect is 2020-12, with no implicit network resource loader.
- Resources are supplied explicitly, and compiled plans own the data they need.
- Custom dialects combine recognized vocabularies and enforce metaschemas. This
  does not imply a general runtime plugin system for arbitrary custom vocabularies.
- No implicit migration to another draft, obsolete dependency keyword semantics,
  Hyper-Schema, or future proposal vocabulary is promised.
- Annotation-only `format` and an explicit format-assertion profile are different
  contracts and must receive separate reports.
- Invalid instances return false/diagnostics; malformed schemas, unsupported
  required semantics, invalid number representations and resource exhaustion must
  remain visible errors rather than being swallowed into false.

## Validation gates

All `moon check`, `moon test` and `moon build` invocations use `--output-json`.
The primary gate is native. JS runs the same pure validator code; Wasm must be
executed to claim Wasm corpus evidence, not merely type-checked.

New official case filters are for TDD only. Full reports keep all standard and
optional cases, including unsupported/rejected cases. A change in corpus revision
requires a new denominator and separate evidence, never a retroactive replacement
of this baseline. Performance measurements use only independently verified case
IDs; changing eligible sets invalidates a direct speed comparison.

The completion roadmap is still in progress until the final profile, output,
resource-limit and multi-target evidence is recorded here. No whole-draft or
fastest-validator claim follows from the baseline above.
