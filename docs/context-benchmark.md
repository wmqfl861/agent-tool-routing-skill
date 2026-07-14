# Context Load And Routing Benchmark

This benchmark keeps two claims separate:

1. how many bytes and Unicode code points a defined route loads from Skill
   files;
2. whether an evaluator selects the expected route for answer-separated user
   intents.

The first is deterministic and model-independent. The second requires a fresh,
fully recorded evaluator run. Neither result is a model-token, billing, cache,
latency, or end-to-end tool-success measurement.

## Context Load

Run and verify the canonical synthetic result from the repository root:

```bash
python scripts/benchmark-routing.py context \
  --topology benchmarks/reference-topology.json \
  --root . \
  --verify benchmarks/reference-context-result.json
```

The fixture scales the repository templates to one Layer 0 index, eight Layer 1
categories, and 32 Layer 2 tool guides. It parses each file's YAML frontmatter
instead of treating the complete Markdown file as body text. `metadata` includes
the opening and closing delimiters and their line endings; `body` is every byte
after the closing delimiter; `total` is their sum.

The eager-all-documents row is a **synthetic anti-pattern scaling baseline**.
It is not a supported project mode. The supported route rows model these exact
document chains:

- strict-progressive A: the Layer 0 Skill + one plain Layer 1 reference + one
  plain Layer 2 reference;
- auto-discovery A: one directly discovered Layer 2;
- strict-progressive B: the Layer 0 Skill + one plain Layer 1 reference;
- auto-discovery B: one directly discovered Layer 1;
- C bypass: no active routing Skill file.

| Synthetic path | Documents | Metadata bytes | Body bytes | Total bytes |
| --- | ---: | ---: | ---: | ---: |
| Eager all documents, unsupported anti-pattern | 41 | `11,916` | `98,901` | `110,817` |
| Strict-progressive A | 3 | `260` | `7,027` | `7,287` |
| Strict-progressive B | 2 | `260` | `4,519` | `4,779` |
| Auto-discovery A | 1 | `275` | `2,508` | `2,783` |
| Auto-discovery B | 1 | `357` | `2,018` | `2,375` |
| C bypass | 0 | `0` | `0` | `0` |

The canonical artifact is
`benchmarks/reference-context-result.json`. It contains topology and document
SHA-256 values, exact UTF-8 byte and Unicode code-point components, selections,
and reductions relative to the synthetic anti-pattern. CI remeasures it and
also verifies that the hard-coded documentation figures match it.

The strict-progressive rows count frontmatter only for Layer 0 because Layer 1
and Layer 2 are installed as plain, non-discoverable references. The
auto-discovery rows count the selected Skill file only. Real runtimes may also
expose discovery metadata elsewhere in a system prompt. The benchmark does not
infer or estimate that runtime-specific overhead, nor does it model cache
behavior, conversation history, tool output, retries, or instructions outside
the fixture.

No tokenizer is selected because Codex, Claude Code, and zcode need not share
one. Do not rename bytes or code points to tokens. A model-token benchmark must
record the exact model, tokenizer and version, runtime, cache state, inventory,
and raw input artifacts.

## Blind Route Accuracy

The answer-bearing case file uses opaque IDs such as `r001`; IDs do not reveal
A/B/C class or expected action. It includes ordinary A/B/C routing plus an
unavailable tool, missing Layer 2 guide, authorization boundary, adversarial
tool name in quoted content, explicit current-user selection, and correct
abstention when essential details are absent.

Build the exact evaluator prompt, which contains the available route catalog,
decision policy, and answer-free opaque cases:

```bash
python scripts/benchmark-routing.py build-prompt \
  --cases benchmarks/route-cases.jsonl \
  --catalog benchmarks/reference-route-catalog.json
```

For inspection only, export the answer-free case objects without the catalog:

```bash
python scripts/benchmark-routing.py export-prompts \
  --cases benchmarks/route-cases.jsonl
```

Run the generated prompt in a fresh isolated evaluator that cannot inspect
`route-cases.jsonl`, repository source, or earlier results. Capture the exact
prompt, invocation, environment, and raw response before parsing predictions.
The evaluator returns one JSONL object per opaque ID:

```json
{"id":"r001","action":"route","route":"category/tool"}
{"id":"r013","action":"abstain","route":null}
{"id":"r009","action":"bypass","route":null}
```

`abstain` is a first-class expected answer when no catalog route can operate
within availability, guide, authorization, or minimum-information boundaries.
The scorer distinguishes correct from incorrect abstentions:

```bash
python scripts/benchmark-routing.py score \
  --cases benchmarks/route-cases.jsonl \
  --predictions /path/to/predictions.jsonl
```

Use `--predictions -` to read JSONL from standard input. The scorer reports
exact-match accuracy, coverage, correct and incorrect abstentions, per-class
accuracy, action confusion, missing IDs, and deterministic errors. Missing
predictions return exit code `1`; malformed, duplicate, or unknown IDs return
exit code `2`.

The reference catalog is a synthetic availability contract. Its answers do not
apply to an installation with a different tool inventory, guide state, or
authorization policy. Version a separate catalog and cases file for a
materially different environment.

## Reproducible Runs

The recorded run
[`claude-fable-5-max-20260713T060022Z`](../benchmarks/runs/claude-fable-5-max-20260713T060022Z/)
used Claude Code CLI `2.1.199` in an empty directory outside the repository. It
requested model identifier `claude-fable-5`, effort `max`, plan permission mode,
safe mode, no tools, no slash commands, and no session persistence. The model
identifier is the exact CLI request value; the client-visible evidence cannot
prove which immutable backend model snapshot served that alias.

The run scored `18/18`: A `11/11`, B `4/4`, C `3/3`, with all `4/4` expected
abstentions correct. Its exact prompt, raw stdout, byte-identical predictions,
invocation/environment record, input and artifact SHA-256 values, and complete
scorer output are preserved together.

This result is a small synthetic catalog-matching smoke test. The catalog was
included in the prompt, and several cases deliberately restate its decision
boundaries. The result does not establish accuracy on new catalogs, held-out
intent distributions, multilingual or long-context inputs, another runtime,
tool discovery, actual tool execution, production authorization decisions, or
future responses from the requested model identifier.

Every future score must preserve all artifacts defined in
[`benchmarks/runs/README.md`](../benchmarks/runs/README.md): `prompt.txt`,
`raw-output.txt`, `predictions.jsonl`, `invocation.json`, and `score.json`, with
their SHA-256 values. A completed run directory is answer-bearing and must stay
unavailable to the evaluator until its response is captured.

## Interpretation

Use the context result to compare specified file-loading paths and blind scores
to compare route decisions. Do not infer total session-token savings from file
bytes, or tool-execution reliability from route selection alone.
