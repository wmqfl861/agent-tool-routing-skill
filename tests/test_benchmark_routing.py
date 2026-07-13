import hashlib
import json
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "benchmark-routing.py"
TOPOLOGY = ROOT / "benchmarks" / "reference-topology.json"
CASES = ROOT / "benchmarks" / "route-cases.jsonl"
CATALOG = ROOT / "benchmarks" / "reference-route-catalog.json"
CONTEXT_RESULT = ROOT / "benchmarks" / "reference-context-result.json"
RUN_PROTOCOL = ROOT / "benchmarks" / "runs" / "README.md"
RUN_ID = "claude-fable-5-max-20260713T060022Z"
RUN_DIR = ROOT / "benchmarks" / "runs" / RUN_ID
RUN_PROMPT = RUN_DIR / "prompt.txt"
RUN_RAW = RUN_DIR / "raw-output.txt"
RUN_PREDICTIONS = RUN_DIR / "predictions.jsonl"
RUN_INVOCATION = RUN_DIR / "invocation.json"
RUN_SCORE = RUN_DIR / "score.json"


def markdown_components(path: Path) -> dict[str, dict[str, int]]:
    raw = path.read_bytes()
    closing = raw.find(b"\n---\n", len(b"---\n"))
    if not raw.startswith(b"---\n") or closing < 0:
        raise AssertionError(f"{path} does not have LF-delimited frontmatter")
    boundary = closing + len(b"\n---\n")
    metadata = raw[:boundary]
    body = raw[boundary:]
    return {
        "metadata": {
            "utf8_bytes": len(metadata),
            "unicode_codepoints": len(metadata.decode("utf-8")),
        },
        "body": {
            "utf8_bytes": len(body),
            "unicode_codepoints": len(body.decode("utf-8")),
        },
        "total": {
            "utf8_bytes": len(raw),
            "unicode_codepoints": len(raw.decode("utf-8")),
        },
    }


class BenchmarkRoutingTests(unittest.TestCase):
    def run_cli(
        self, *arguments: str, input_text: str | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *arguments],
            cwd=ROOT,
            check=False,
            capture_output=True,
            input=input_text,
            text=True,
        )

    def reference_context_report(self) -> dict:
        result = self.run_cli(
            "context", "--topology", str(TOPOLOGY), "--root", str(ROOT)
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_reference_context_metrics_are_exact_and_modes_are_distinct(self) -> None:
        report = self.reference_context_report()
        paths = {
            "layer0-index": ROOT / "examples" / "tool-index.SKILL.md",
            "layer1-category-template": (
                ROOT / "examples" / "category-skill.example.md"
            ),
            "layer2-tool-template": (
                ROOT / "examples" / "tool-specific-skill.example.md"
            ),
        }
        sizes = {key: markdown_components(path) for key, path in paths.items()}
        instances = {
            "layer0-index": 1,
            "layer1-category-template": 8,
            "layer2-tool-template": 32,
        }
        baseline = report["synthetic_eager_all_documents"]
        self.assertFalse(baseline["supported_mode"])
        self.assertIn("anti-pattern", baseline["label"])
        for component in ("metadata", "body", "total"):
            for unit in ("utf8_bytes", "unicode_codepoints"):
                expected = sum(
                    sizes[document_id][component][unit] * instances[document_id]
                    for document_id in sizes
                )
                self.assertEqual(baseline["loaded"][component][unit], expected)

        routes = {item["id"]: item for item in report["routes"]}
        expected_selections = {
            "strict-progressive-a": [
                "layer0-index",
                "layer1-category-template",
                "layer2-tool-template",
            ],
            "auto-discovery-a": ["layer2-tool-template"],
            "strict-progressive-b": [
                "layer0-index",
                "layer1-category-template",
            ],
            "auto-discovery-b": ["layer1-category-template"],
            "c-bypass": [],
        }
        expected_modes = {
            "strict-progressive-a": "strict-progressive",
            "auto-discovery-a": "auto-discovery",
            "strict-progressive-b": "strict-progressive",
            "auto-discovery-b": "auto-discovery",
            "c-bypass": "bypass",
        }
        expected_metadata_selections = {
            "strict-progressive-a": ["layer0-index"],
            "auto-discovery-a": ["layer2-tool-template"],
            "strict-progressive-b": ["layer0-index"],
            "auto-discovery-b": ["layer1-category-template"],
            "c-bypass": [],
        }
        for route_id, selected_ids in expected_selections.items():
            with self.subTest(route=route_id):
                route = routes[route_id]
                self.assertEqual(route["mode"], expected_modes[route_id])
                self.assertEqual(
                    sorted(route["selected_instances"]), sorted(selected_ids)
                )
                metadata_ids = expected_metadata_selections[route_id]
                self.assertEqual(
                    sorted(route["selected_metadata_instances"]),
                    sorted(metadata_ids),
                )
                expected_metadata = sum(
                    sizes[document_id]["metadata"]["utf8_bytes"]
                    for document_id in metadata_ids
                )
                expected_body = sum(
                    sizes[document_id]["body"]["utf8_bytes"]
                    for document_id in selected_ids
                )
                self.assertEqual(
                    route["loaded"]["metadata"]["utf8_bytes"], expected_metadata
                )
                self.assertEqual(
                    route["loaded"]["body"]["utf8_bytes"], expected_body
                )
                self.assertEqual(
                    route["loaded"]["total"]["utf8_bytes"],
                    expected_metadata + expected_body,
                )

        self.assertIsNone(report["measurement"]["tokenizer"])
        self.assertIn("not a model token", report["measurement"]["claim"])

    def test_canonical_context_artifact_matches_measurement(self) -> None:
        report = self.reference_context_report()
        expected = json.loads(CONTEXT_RESULT.read_text(encoding="utf-8"))
        self.assertEqual(report, expected)
        verified = self.run_cli(
            "context",
            "--topology",
            str(TOPOLOGY),
            "--root",
            str(ROOT),
            "--verify",
            str(CONTEXT_RESULT),
        )
        self.assertEqual(verified.returncode, 0, verified.stderr)

    def test_context_rejects_selection_above_available_instances(self) -> None:
        topology = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
        topology["routes"][0]["selected_instances"]["layer2-tool-template"] = 33
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad-topology.json"
            path.write_text(json.dumps(topology), encoding="utf-8")
            result = self.run_cli(
                "context", "--topology", str(path), "--root", str(ROOT)
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("only 32 are available", result.stderr)

    def test_context_requires_yaml_frontmatter(self) -> None:
        topology = json.loads(TOPOLOGY.read_text(encoding="utf-8"))
        topology["documents"][0]["path"] = "README.md"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad-topology.json"
            path.write_text(json.dumps(topology), encoding="utf-8")
            result = self.run_cli(
                "context", "--topology", str(path), "--root", str(ROOT)
            )
        self.assertEqual(result.returncode, 2)
        self.assertIn("must begin with YAML frontmatter", result.stderr)

    def test_export_prompts_uses_opaque_ids_and_removes_answers(self) -> None:
        result = self.run_cli("export-prompts", "--cases", str(CASES))
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(len(report["prompts"]), 18)
        self.assertTrue(
            all(re.fullmatch(r"r[0-9]{3,}", item["id"]) for item in report["prompts"])
        )
        serialized = json.dumps(report)
        self.assertNotIn("expected_route", serialized)
        self.assertNotIn("classification", serialized)
        self.assertNotIn("scenario", serialized)
        self.assertNotIn("research/agent-reach", serialized)

    def test_cases_cover_failure_safety_and_adversarial_scenarios(self) -> None:
        cases = [
            json.loads(line)
            for line in CASES.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        scenarios = {case["scenario"] for case in cases}
        for required in (
            "unavailable-tool",
            "missing-layer-2",
            "authorization-boundary",
            "adversarial-injected-tool-name",
            "explicit-selection",
            "correct-abstention-insufficient-details",
        ):
            self.assertIn(required, scenarios)
        self.assertGreaterEqual(
            sum(case["expected_action"] == "abstain" for case in cases), 4
        )

    def test_build_prompt_is_exact_and_answer_separated(self) -> None:
        first = self.run_cli(
            "build-prompt", "--cases", str(CASES), "--catalog", str(CATALOG)
        )
        second = self.run_cli(
            "build-prompt", "--cases", str(CASES), "--catalog", str(CATALOG)
        )
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(first.stdout, second.stdout)
        self.assertIn("ROUTE CATALOG", first.stdout)
        self.assertIn("OPAQUE CASES", first.stdout)
        self.assertIn("correct when no listed route is available", first.stdout)
        self.assertNotIn("expected_action", first.stdout)
        self.assertNotIn("expected_route", first.stdout)
        self.assertNotIn('"classification"', first.stdout)
        self.assertNotIn('"scenario"', first.stdout)

    def test_score_counts_expected_abstention_as_exact_match(self) -> None:
        predictions = [
            {"id": "r001", "action": "route", "route": "research/agent-reach"},
            {"id": "r002", "action": "abstain", "route": None},
            {"id": "r013", "action": "abstain", "route": None},
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "predictions.jsonl"
            path.write_text(
                "\n".join(json.dumps(item) for item in predictions) + "\n",
                encoding="utf-8",
            )
            result = self.run_cli(
                "score", "--cases", str(CASES), "--predictions", str(path)
            )
        self.assertEqual(result.returncode, 1)
        report = json.loads(result.stdout)
        self.assertEqual(report["exact_matches"], 2)
        self.assertEqual(report["abstained_ids"], ["r002", "r013"])
        self.assertEqual(report["correct_abstained_ids"], ["r013"])
        self.assertEqual(report["incorrect_abstained_ids"], ["r002"])
        self.assertEqual(len(report["missing_ids"]), 15)
        self.assertEqual(report["coverage"], round(3 / 18, 6))

    def test_score_accepts_complete_predictions_and_reports_per_class_accuracy(self) -> None:
        cases = [
            json.loads(line)
            for line in CASES.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        predictions = [
            {
                "id": case["id"],
                "action": case["expected_action"],
                "route": case["expected_route"],
            }
            for case in cases
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "predictions.jsonl"
            path.write_text(
                "\n".join(json.dumps(item) for item in predictions) + "\n",
                encoding="utf-8",
            )
            result = self.run_cli(
                "score", "--cases", str(CASES), "--predictions", str(path)
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["accuracy"], 1.0)
        self.assertEqual(report["coverage"], 1.0)
        self.assertEqual(
            report["correct_abstained_ids"], ["r013", "r014", "r015", "r018"]
        )
        for classification in ("A", "B", "C"):
            self.assertEqual(
                report["by_classification"][classification]["accuracy"], 1.0
            )

    def test_score_accepts_predictions_from_standard_input(self) -> None:
        prediction = {
            "id": "r001",
            "action": "route",
            "route": "research/agent-reach",
        }
        result = self.run_cli(
            "score",
            "--cases",
            str(CASES),
            "--predictions",
            "-",
            input_text=json.dumps(prediction) + "\n",
        )
        self.assertEqual(result.returncode, 1)
        report = json.loads(result.stdout)
        self.assertEqual(report["exact_matches"], 1)
        self.assertEqual(report["predictions"], 1)

    def test_score_rejects_duplicate_unknown_and_nonopaque_prediction_ids(self) -> None:
        scenarios = (
            [
                {"id": "r001", "action": "bypass", "route": None},
                {"id": "r001", "action": "bypass", "route": None},
            ],
            [{"id": "r999", "action": "bypass", "route": None}],
            [{"id": "a-answer-leak", "action": "bypass", "route": None}],
        )
        for predictions in scenarios:
            with self.subTest(predictions=predictions):
                with tempfile.TemporaryDirectory() as directory:
                    path = Path(directory) / "predictions.jsonl"
                    path.write_text(
                        "\n".join(json.dumps(item) for item in predictions) + "\n",
                        encoding="utf-8",
                    )
                    result = self.run_cli(
                        "score", "--cases", str(CASES), "--predictions", str(path)
                    )
                self.assertEqual(result.returncode, 2)

    def test_documented_context_numbers_match_canonical_artifact(self) -> None:
        report = json.loads(CONTEXT_RESULT.read_text(encoding="utf-8"))
        routes = {route["id"]: route for route in report["routes"]}
        expected_values = {
            "metadata": report["synthetic_eager_all_documents"]["loaded"][
                "metadata"
            ]["utf8_bytes"],
            "body": report["synthetic_eager_all_documents"]["loaded"]["body"][
                "utf8_bytes"
            ],
            "total": report["synthetic_eager_all_documents"]["loaded"]["total"][
                "utf8_bytes"
            ],
            "strict-a": routes["strict-progressive-a"]["loaded"]["total"][
                "utf8_bytes"
            ],
            "strict-b": routes["strict-progressive-b"]["loaded"]["total"][
                "utf8_bytes"
            ],
            "auto-a": routes["auto-discovery-a"]["loaded"]["total"][
                "utf8_bytes"
            ],
            "auto-b": routes["auto-discovery-b"]["loaded"]["total"][
                "utf8_bytes"
            ],
        }
        for relative in (
            "README.md",
            "README.zh-CN.md",
            "CHANGELOG.md",
            "docs/context-benchmark.md",
        ):
            text = (ROOT / relative).read_text(encoding="utf-8")
            with self.subTest(document=relative):
                for label, value in expected_values.items():
                    self.assertIn(f"`{value:,}`", text, f"missing {label}")
                self.assertNotIn("92.9471%", text)
                self.assertNotIn("12/12", text)

    def test_run_artifact_protocol_requires_reproducibility_evidence(self) -> None:
        protocol = RUN_PROTOCOL.read_text(encoding="utf-8")
        for required in (
            "prompt.txt",
            "raw-output.txt",
            "predictions.jsonl",
            "invocation.json",
            "score.json",
            "SHA-256",
            "answer-bearing",
            "CLI version",
            "runtime",
            "working_directory",
        ):
            self.assertIn(required, protocol)
        invocation_hash = hashlib.sha256(RUN_INVOCATION.read_bytes()).hexdigest()
        self.assertEqual(
            invocation_hash,
            "eec6beffbd09e05949615a9f9ca9e064ef78cda9dc57f3803c39f1a9ff99ba5b",
        )
        self.assertIn(f"`{invocation_hash}`", protocol)

    def test_recorded_run_artifacts_are_complete_and_hash_verified(self) -> None:
        expected_names = {
            "prompt.txt",
            "raw-output.txt",
            "predictions.jsonl",
            "invocation.json",
            "score.json",
        }
        self.assertEqual(
            {path.name for path in RUN_DIR.iterdir() if path.is_file()},
            expected_names,
        )
        invocation = json.loads(RUN_INVOCATION.read_text(encoding="utf-8"))
        self.assertTrue(invocation["answer_bearing"])
        self.assertEqual(invocation["run_id"], RUN_ID)
        hashed_inputs = {
            "cases": CASES,
            "catalog": CATALOG,
            "prompt.txt": RUN_PROMPT,
            "raw-output.txt": RUN_RAW,
            "predictions.jsonl": RUN_PREDICTIONS,
            "score.json": RUN_SCORE,
        }
        for key, path in hashed_inputs.items():
            with self.subTest(artifact=key):
                self.assertEqual(
                    invocation["sha256"][key],
                    hashlib.sha256(path.read_bytes()).hexdigest(),
                )
        self.assertEqual(RUN_RAW.read_bytes(), RUN_PREDICTIONS.read_bytes())
        self.assertEqual(
            invocation["sha256"]["raw-output.txt"],
            invocation["sha256"]["predictions.jsonl"],
        )

    def test_recorded_run_prompt_and_score_replay_exactly(self) -> None:
        prompt = self.run_cli(
            "build-prompt", "--cases", str(CASES), "--catalog", str(CATALOG)
        )
        self.assertEqual(prompt.returncode, 0, prompt.stderr)
        self.assertEqual(prompt.stdout, RUN_PROMPT.read_text(encoding="utf-8"))

        scored = self.run_cli(
            "score",
            "--cases",
            str(CASES),
            "--predictions",
            str(RUN_PREDICTIONS),
        )
        self.assertEqual(scored.returncode, 0, scored.stderr)
        self.assertEqual(
            json.loads(scored.stdout),
            json.loads(RUN_SCORE.read_text(encoding="utf-8")),
        )
        score = json.loads(scored.stdout)
        self.assertEqual(score["exact_matches"], 18)
        self.assertEqual(score["cases"], 18)
        self.assertEqual(score["correct_abstained_ids"], [
            "r013",
            "r014",
            "r015",
            "r018",
        ])
        self.assertEqual(score["incorrect_abstained_ids"], [])
        self.assertEqual(score["errors"], [])
        self.assertEqual(
            score["action_confusion"],
            {"abstain->abstain": 4, "bypass->bypass": 3, "route->route": 11},
        )
        for classification, count in (("A", 11), ("B", 4), ("C", 3)):
            self.assertEqual(
                score["by_classification"][classification],
                {"accuracy": 1.0, "cases": count, "exact_matches": count},
            )

    def test_recorded_run_captures_exact_model_and_isolation_contract(self) -> None:
        invocation = json.loads(RUN_INVOCATION.read_text(encoding="utf-8"))
        runner = invocation["runner"]
        self.assertEqual(runner["requested_model_identifier"], "claude-fable-5")
        self.assertEqual(runner["reasoning_or_effort"], "max")
        self.assertEqual(runner["cli_version"], "2.1.199")
        self.assertEqual(runner["permission_mode"], "plan")
        self.assertTrue(runner["safe_mode"])
        self.assertFalse(runner["slash_commands"])
        self.assertFalse(runner["session_persistence"])
        self.assertIn("immutable model snapshot", runner["model_identifier_scope"])
        self.assertIn("outside the repository", runner["working_directory_state"])
        self.assertEqual(
            invocation["invocation"]["argv"],
            [
                "pwsh",
                "-NoProfile",
                "-File",
                "D:\\npm-global\\claude.ps1",
                "-p",
                "--model",
                "claude-fable-5",
                "--effort",
                "max",
                "--permission-mode",
                "plan",
                "--safe-mode",
                "--tools",
                "",
                "--disable-slash-commands",
                "--no-session-persistence",
                "--output-format",
                "text",
            ],
        )
        self.assertEqual(invocation["invocation"]["exit_code"], 0)
        self.assertEqual(invocation["invocation"]["stderr_utf8_bytes"], 0)
        self.assertIn("empty string", invocation["invocation"]["stderr"])
        self.assertIn(
            "tool access was disabled",
            invocation["environment"]["repository_access"],
        )
        self.assertEqual(
            invocation["environment"]["os"],
            "Microsoft Windows Server 2019 Datacenter 10.0.17763 "
            "(OS build 17763.8880)",
        )
        self.assertEqual(invocation["environment"]["locale"], "en-US")
        self.assertEqual(invocation["environment"]["ui_locale"], "en-US")
        self.assertIn(
            "generated route catalog and answer-free opaque cases",
            invocation["environment"]["repository_access"],
        )
        self.assertIn(
            "Not independently enumerated",
            invocation["environment"]["discovered_skill_state"],
        )
        self.assertFalse(invocation["extraction"]["modified_values"])
        self.assertTrue(invocation["extraction"]["predictions_identical_to_raw_output"])

    def test_documented_recorded_score_matches_run(self) -> None:
        for relative in (
            "README.md",
            "README.zh-CN.md",
            "CHANGELOG.md",
            "docs/context-benchmark.md",
        ):
            text = (ROOT / relative).read_text(encoding="utf-8")
            with self.subTest(document=relative):
                for value in (
                    "`claude-fable-5`",
                    "`18/18`",
                    "`11/11`",
                    "`4/4`",
                    "`3/3`",
                    "smoke test",
                ):
                    self.assertIn(value, text)
                self.assertNotIn("12/12", text)


if __name__ == "__main__":
    unittest.main()
