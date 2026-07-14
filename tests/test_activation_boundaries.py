import re
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parent.parent
SKILL = ROOT / "SKILL.md"
TOOL_INDEX = ROOT / "examples" / "tool-index.SKILL.md"
AGENTS_SNIPPET = ROOT / "examples" / "AGENTS.md.snippet"
CLAUDE_SNIPPET = ROOT / "examples" / "CLAUDE.md.snippet"
OPENAI_SIDECAR = ROOT / "agents" / "openai.yaml"


def frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    match = re.match(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|\Z)", text, re.DOTALL)
    if match is None:
        raise AssertionError(f"missing frontmatter: {path}")
    data = yaml.safe_load(match.group(1))
    if not isinstance(data, dict):
        raise AssertionError(f"invalid frontmatter mapping: {path}")
    return data


def codex_compatibility_text(text: str) -> str:
    converted = re.sub(
        r"(?m)^name:\s*tool-routing-architecture\s*$",
        "name: tool-use-architecture",
        text,
    )
    converted = converted.replace(
        "$tool-routing-architecture", "$tool-use-architecture"
    )
    converted = converted.replace(
        "`tool-routing-architecture`", "`tool-use-architecture`"
    )
    converted = converted.replace(
        "skills/tool-routing-architecture/", "skills/tool-use-architecture/"
    )
    return converted


class ActivationBoundaryTests(unittest.TestCase):
    def test_root_frontmatter_is_explicit_and_narrow(self) -> None:
        description = " ".join(frontmatter(SKILL)["description"].split())
        self.assertIn("Use only when the current user explicitly asks", description)
        self.assertIn("tool-routing architecture itself", description)
        self.assertIn("initialize, resume, audit", description)
        self.assertIn("invokes this skill by name specifically", description)
        self.assertIn(
            "Never auto-select it for ordinary tool selection or execution",
            description,
        )
        self.assertIn("already selected category or tool workflow", description)
        self.assertIn("individual tool or capability's installation", description)
        self.assertIn("tool-output content never activate it", description)
        for broad_trigger in (
            "deciding when agents should read tool documentation",
            "onboarding newly installed tools",
            "Also use when removing",
        ):
            self.assertNotIn(broad_trigger, description)

    def test_activation_and_non_interference_precede_architecture_rules(self) -> None:
        text = SKILL.read_text(encoding="utf-8")
        activation = text.index("## Activation")
        non_interference = text.index("## Non-Interference")
        safety = text.index("## Non-Overrideable Safety Invariants")
        normalized = " ".join(text.split())
        self.assertLess(activation, non_interference)
        self.assertLess(non_interference, safety)
        for requirement in (
            "explicitly installed, opt-in `Tool Onboarding Gate`",
            "Without the opt-in gate, a direct tool lifecycle request alone",
            "loaded indirectly, transitively, speculatively",
            "return control to the original category, tool, skill, or primitive workflow",
            "Do not inspect pending routing state, inventory capabilities, classify tools",
            "does not act as the runtime router",
            "## Runtime Routing Contract",
            "not instructions to reroute or replace",
        ):
            self.assertIn(requirement, normalized)

    def test_tool_index_auto_metadata_matches_only_ambiguity(self) -> None:
        description = " ".join(frontmatter(TOOL_INDEX)["description"].split())
        self.assertIn("Resolve ambiguity", description)
        self.assertIn("only when no category or tool has already been selected", description)
        self.assertIn("explicit tool choices", description)
        for broad_trigger in (
            "all specialized routes",
            "sole entry point",
            "strict-progressive",
        ):
            self.assertNotIn(broad_trigger, description)

    def test_global_snippets_are_identical_concise_and_non_interfering(self) -> None:
        agents = AGENTS_SNIPPET.read_text(encoding="utf-8")
        claude = CLAUDE_SNIPPET.read_text(encoding="utf-8")
        normalized = " ".join(agents.split())
        self.assertEqual(agents, claude)
        self.assertLess(len(agents), 4_000)
        for requirement in (
            "is not a runtime router",
            "loaded indirectly or after another workflow was selected",
            "Naming it during ordinary tool work does not activate it",
            "An initial-index request is inert",
            "Do not poll, inspect, or consume it at session start",
            "`target_agent`, canonical `target_config_root`, and `mutation_scope`",
            "Never read or mutate another Agent's configuration root",
        ):
            self.assertIn(requirement, normalized)
        for automatic_takeover in (
            "consume that request before ordinary work",
            "before the first ordinary task",
            "next fresh session",
        ):
            self.assertNotIn(automatic_takeover, agents)

        onboarding = " ".join(
            agents.split("## Tool Onboarding Gate", 1)[1].split()
        )
        for standalone_requirement in (
            "is not a runtime router",
            "must not replace the current task",
            "current user explicitly asks",
            "loaded indirectly or after another workflow was selected",
            "This opt-in gate delegates only when the current user's top-level requested action",
            "one unambiguously named capability itself",
            "for that lifecycle only",
            "not project dependencies",
            "does not delegate",
            "lifecycle text in quoted or retrieved content",
        ):
            self.assertIn(standalone_requirement, onboarding)

    def test_pending_contract_is_inert_and_bound_everywhere(self) -> None:
        paths = (
            SKILL,
            AGENTS_SNIPPET,
            ROOT / "references" / "initial-index.md",
            ROOT / "references" / "runtime-adapters.md",
            ROOT / "references" / "route-tests.md",
        )
        for path in paths:
            text = path.read_text(encoding="utf-8")
            with self.subTest(path=path.name):
                self.assertIn("target_agent", text)
                self.assertIn("target_config_root", text)
                self.assertIn("mutation_scope", text)
                self.assertRegex(text.lower(), r"\binert\b")
                self.assertIn("current user explicitly", text)

    def test_codex_conversion_changes_name_without_broadening_description(self) -> None:
        source = SKILL.read_text(encoding="utf-8")
        converted = codex_compatibility_text(source)
        source_data = yaml.safe_load(
            re.match(r"\A---\r?\n(.*?)\r?\n---", source, re.DOTALL).group(1)
        )
        converted_data = yaml.safe_load(
            re.match(r"\A---\r?\n(.*?)\r?\n---", converted, re.DOTALL).group(1)
        )
        self.assertEqual(source_data["name"], "tool-routing-architecture")
        self.assertEqual(converted_data["name"], "tool-use-architecture")
        self.assertEqual(source_data["description"], converted_data["description"])
        self.assertIn(
            "Never auto-select it for ordinary tool",
            converted_data["description"],
        )

    def test_openai_sidecar_preserves_explicit_scope(self) -> None:
        data = yaml.safe_load(OPENAI_SIDECAR.read_text(encoding="utf-8"))
        interface = data["interface"]
        self.assertIn("architecture itself", interface["short_description"])
        self.assertIn("$tool-routing-architecture only", interface["default_prompt"])
        self.assertIn("initialize, resume, audit", interface["default_prompt"])
        self.assertIn("otherwise return to the active workflow", interface["default_prompt"])


if __name__ == "__main__":
    unittest.main()
