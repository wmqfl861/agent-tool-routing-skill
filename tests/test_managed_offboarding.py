from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def normalized(relative: str) -> str:
    text = (ROOT / relative).read_text(encoding="utf-8")
    return " ".join(text.split())


class ManagedOffboardingContractTests(unittest.TestCase):
    def test_short_removal_request_triggers_complete_offboarding(self) -> None:
        trigger = "request to remove, delete, or uninstall"
        for relative in (
            "SKILL.md",
            "references/lifecycle.md",
            "examples/AGENTS.md.snippet",
            "examples/CLAUDE.md.snippet",
        ):
            content = normalized(relative)
            self.assertIn(trigger, content, relative)
            self.assertIn("complete managed offboarding", content, relative)

        self.assertEqual(
            (ROOT / "examples/AGENTS.md.snippet").read_bytes(),
            (ROOT / "examples/CLAUDE.md.snippet").read_bytes(),
        )
        self.assertIn("opt-in gate delegates", normalized("SKILL.md"))
        self.assertIn(
            "After lifecycle activation", normalized("references/lifecycle.md")
        )

    def test_user_does_not_have_to_enumerate_dependent_cleanup(self) -> None:
        skill = normalized("SKILL.md")
        lifecycle = normalized("references/lifecycle.md")
        route_tests = normalized("references/route-tests.md")

        self.assertIn("Do not ask the user to restate or separately authorize", skill)
        self.assertIn(
            'Do not require the user to append "and clean its Skill, inventory, and routes."',
            lifecycle,
        )
        self.assertIn("Delete Example Crawler.", route_tests)
        self.assertIn("without requiring the user to enumerate", route_tests)

    def test_automatic_skill_deletion_requires_proven_ownership(self) -> None:
        inventory = normalized("references/managed-inventory.md")
        lifecycle = normalized("references/lifecycle.md")

        for ownership in (
            "managed-exclusive",
            "managed-shared",
            "external",
            "unknown",
        ):
            self.assertIn(ownership, inventory)
        self.assertIn('`skill.management` to `managed`, `external`, or `unknown`', inventory)
        self.assertIn("`skill.active_refcount`", inventory)
        self.assertIn("It is not the deletion gate by itself", inventory)
        self.assertIn("current digest matches the last managed digest", lifecycle)
        self.assertIn("post-change active reference count", lifecycle)
        self.assertIn("shared before its final reference was removed", lifecycle)

    def test_inventory_routes_and_global_rules_publish_together(self) -> None:
        inventory = normalized("references/managed-inventory.md")
        lifecycle = normalized("references/lifecycle.md")

        self.assertIn("inventory tombstone", lifecycle)
        self.assertIn("managed global sections as one recoverable managed-state change", lifecycle)
        self.assertIn("Record the disposition of every affected managed artifact", inventory)
        self.assertIn("Run a negative route test", lifecycle)

    def test_remover_side_effects_require_a_narrow_gate(self) -> None:
        lifecycle = normalized("references/lifecycle.md")
        route_tests = normalized("references/route-tests.md")

        self.assertIn(
            "inspect the normal local removal mechanism's documented side effects and flags",
            lifecycle,
        )
        self.assertIn("keep-data, keep-config, or keep-profile", lifecycle)
        self.assertIn("recorded installed provenance and verified official documentation", lifecycle)
        self.assertIn("never infer `pip`, `npm`, `brew`", lifecycle)
        self.assertIn("stop before invoking it", lifecycle)
        self.assertIn("additional destructive authorization", lifecycle)
        self.assertIn("asks one narrow destructive-authorization question", route_tests)
        self.assertIn("never guesses `pip`, `npm`, `brew`", route_tests)

    def test_post_change_refcount_handles_the_last_shared_reference(self) -> None:
        inventory = normalized("references/managed-inventory.md")
        lifecycle = normalized("references/lifecycle.md")

        self.assertIn("Recompute the post-change reference count", inventory)
        self.assertIn("pre-change compatibility label was `managed-shared`", inventory)
        self.assertIn("zero-reference guide automatically", lifecycle)
        self.assertIn("shared before its final reference was removed", lifecycle)

    def test_non_deletable_orphans_cannot_remain_discoverable(self) -> None:
        inventory = normalized("references/managed-inventory.md")
        lifecycle = normalized("references/lifecycle.md")

        self.assertIn("recoverable archive outside every Agent discovery root", inventory)
        self.assertIn("outside every discovery root", lifecycle)
        self.assertIn("cannot route to the removed capability", lifecycle)
        self.assertIn("`blocked` or `needs-input`", lifecycle)

    def test_plugin_scope_is_capability_aware(self) -> None:
        lifecycle = normalized("references/lifecycle.md")
        route_tests = normalized("references/route-tests.md")

        self.assertIn("separately inventoried capabilities", lifecycle)
        self.assertIn("does not authorize uninstalling the whole plugin", lifecycle)
        self.assertIn("no per-capability disable or removal mechanism", lifecycle)
        self.assertIn("every capability it provides exclusively", lifecycle)
        self.assertIn("Test both plugin directions", route_tests)
        self.assertLess(
            lifecycle.index("Before selecting or invoking any remover"),
            lifecycle.index("After plugin scope is resolved"),
        )

    def test_rollback_never_reactivates_a_missing_capability(self) -> None:
        lifecycle = normalized("references/lifecycle.md")
        route_tests = normalized("references/route-tests.md")

        self.assertIn("exact installed version/source", lifecycle)
        self.assertIn("tool-removal and managed-state publication as separate phases", lifecycle)
        self.assertIn("only after the exact capability has been reinstalled", lifecycle)
        self.assertIn("never restore a route that points to a missing capability", lifecycle)
        self.assertIn("`needs-repair`", route_tests)

    def test_protected_and_unrelated_state_is_not_implied_cleanup(self) -> None:
        lifecycle = normalized("references/lifecycle.md")
        for protected in (
            "credentials",
            "caches",
            "browser profiles",
            "user data",
            "accounts",
            "unrelated capabilities",
        ):
            self.assertIn(protected, lifecycle)

    def test_bilingual_readmes_document_the_short_request(self) -> None:
        english = normalized("README.md")
        chinese = normalized("README.zh-CN.md")

        self.assertIn("delete Example Crawler", english)
        self.assertIn("complete managed offboarding", english)
        self.assertIn("When `-AddOnboardingRules` installs the opt-in gate", english)
        self.assertIn("Without the opt-in gate", english)
        self.assertIn("Explicitly invoke the architecture skill", english)
        self.assertIn("Example Crawler", chinese)
        self.assertIn("inventory tombstone", chinese)
        self.assertIn("使用 `-AddOnboardingRules` 安装可选门禁后", chinese)
        self.assertIn("如果没有安装这个可选门禁", chinese)
        self.assertIn("必须显式调用架构 Skill", chinese)


if __name__ == "__main__":
    unittest.main()
