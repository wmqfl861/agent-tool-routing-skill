# Blind Route Run Artifacts

This directory defines the evidence required for a publishable model-routing
run. A completed run belongs in a uniquely named child directory. Predictions,
raw output, scores, and any manifest that reports them are answer-bearing; keep
the entire child directory unavailable to the evaluator until its response has
been captured.

The recorded
[`claude-fable-5-max-20260713T060022Z`](claude-fable-5-max-20260713T060022Z/)
directory is one completed example. Its requested model name is a CLI input,
not evidence of an immutable backend snapshot. Its `invocation.json` SHA-256,
which cannot be embedded in that same file without self-reference, is
`eec6beffbd09e05949615a9f9ca9e064ef78cda9dc57f3803c39f1a9ff99ba5b`.

Do not publish an accuracy claim from terminal history or a reconstructed
transcript. Preserve these five files exactly:

```text
benchmarks/runs/<run-id>/
├── prompt.txt          # Exact bytes supplied to the evaluator
├── raw-output.txt      # Exact primary response/stdout before cleanup
├── predictions.jsonl   # Parsed JSONL submitted to the scorer
├── invocation.json     # Runner, command, environment, and input hashes
└── score.json          # Unedited scorer JSON
```

Generate `prompt.txt` with the benchmark CLI before entering the isolated
evaluator environment:

```bash
python scripts/benchmark-routing.py build-prompt \
  --cases benchmarks/route-cases.jsonl \
  --catalog benchmarks/reference-route-catalog.json
```

The evaluator must receive the exact `prompt.txt`; it must not receive the
answer-bearing `route-cases.jsonl`, a previous run directory, or repository
tools that can discover either one. Save its response byte-for-byte as
`raw-output.txt`, then extract only prediction records into `predictions.jsonl`.
Never silently repair a model answer. Record any extraction rule or rejected
text in `invocation.json`.

## Invocation Manifest

`invocation.json` uses benchmark schema version 2 and records at least:

```json
{
  "schema_version": 2,
  "answer_bearing": true,
  "run_id": "agent-model-effort-YYYY-MM-DDTHHMMSSZ",
  "recorded_at_utc": "RFC-3339 timestamp",
  "runner": {
    "agent": "Agent product name",
    "requested_model_identifier": "Exact CLI model identifier",
    "model_identifier_scope": "What model identity the client can and cannot prove",
    "reasoning_or_effort": "Exact requested value",
    "cli_version": "Exact CLI version",
    "runtime": "Runtime and version",
    "permission_mode": "Exact mode",
    "tool_access": "Allowed or forbidden tools and enforcement method",
    "working_directory": "Absolute or isolated-directory description"
  },
  "invocation": {
    "argv": ["Exact", "unredacted", "argument", "vector"],
    "stdin_artifact": "prompt.txt",
    "exit_code": 0,
    "started_at_utc": "RFC-3339 timestamp",
    "finished_at_utc": "RFC-3339 timestamp"
  },
  "environment": {
    "os": "OS name and version",
    "architecture": "CPU architecture",
    "locale": "Locale and encoding",
    "relevant_configuration": "Skill discovery and evaluator isolation state"
  },
  "sha256": {
    "cases": "SHA-256 of benchmarks/route-cases.jsonl",
    "catalog": "SHA-256 of benchmarks/reference-route-catalog.json",
    "prompt.txt": "SHA-256 of the exact prompt",
    "raw-output.txt": "SHA-256 of the raw response",
    "predictions.jsonl": "SHA-256 of parsed predictions",
    "score.json": "SHA-256 of the scorer output"
  },
  "extraction": {
    "method": "How predictions were derived from raw output",
    "modified_values": false
  }
}
```

Secrets must not be placed in the command or manifest. If reproducibility would
require a secret, record the credential mechanism and redaction boundary, not
the value. A run with a missing artifact, missing requested model identifier,
unrecorded CLI/runtime version, changed prediction value, mismatched SHA-256, or
an unsupported claim about backend snapshot identity is incomplete and must not
support a score claim.
