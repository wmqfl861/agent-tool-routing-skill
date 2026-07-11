#!/usr/bin/env python3
"""Validate repository skill metadata, YAML, and local Markdown links."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any
from urllib.parse import unquote

try:
    import yaml
except ImportError:
    print(
        "ERROR: PyYAML is required. Install it with: "
        f"{sys.executable} -m pip install PyYAML",
        file=sys.stderr,
    )
    raise SystemExit(2)


ROOT = Path(__file__).resolve().parent.parent
SKILL_FRONTMATTER_FILES = (
    ROOT / "SKILL.md",
    ROOT / "examples" / "tool-index.SKILL.md",
    ROOT / "examples" / "category-skill.example.md",
    ROOT / "examples" / "tool-specific-skill.example.md",
)
YAML_FILES = tuple(
    sorted(
        {
            ROOT / ".markdownlint-cli2.yaml",
            *ROOT.glob("agents/**/*.yaml"),
            *ROOT.glob("agents/**/*.yml"),
            *ROOT.glob(".github/workflows/*.yaml"),
            *ROOT.glob(".github/workflows/*.yml"),
        }
    )
)
MARKDOWN_FILES = tuple(
    path for path in sorted(ROOT.rglob("*.md")) if ".git" not in path.parts
)
LINK_RE = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")
FRONTMATTER_RE = re.compile(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|\Z)", re.DOTALL)
WINDOWS_ABSOLUTE_RE = re.compile(r"^[A-Za-z]:[\\/]")
SEMVER_RE = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"
)
TEXT_SUFFIXES = {".md", ".ps1", ".py", ".snippet", ".yaml", ".yml"}


class Validation:
    def __init__(self) -> None:
        self.errors: list[str] = []

    def error(self, path: Path, message: str) -> None:
        try:
            display = path.relative_to(ROOT).as_posix()
        except ValueError:
            display = str(path)
        self.errors.append(f"{display}: {message}")


def read_utf8(path: Path, validation: Validation) -> str | None:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        validation.error(path, f"cannot read file: {exc}")
        return None

    try:
        return raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        validation.error(path, f"is not valid UTF-8: {exc}")
        return None


def parse_yaml(text: str, path: Path, validation: Validation) -> Any:
    try:
        return yaml.safe_load(text)
    except yaml.YAMLError as exc:
        validation.error(path, f"invalid YAML: {exc}")
        return None


def validate_frontmatter(path: Path, validation: Validation) -> None:
    text = read_utf8(path, validation)
    if text is None:
        return

    match = FRONTMATTER_RE.match(text)
    if not match:
        validation.error(path, "missing leading YAML frontmatter block")
        return

    data = parse_yaml(match.group(1), path, validation)
    if data is None:
        return
    if not isinstance(data, dict):
        validation.error(path, "frontmatter must be a YAML mapping")
        return

    for key in ("name", "description"):
        value = data.get(key)
        if not isinstance(value, str) or not value.strip():
            validation.error(path, f"frontmatter '{key}' must be a non-empty string")

    name = data.get("name")
    if isinstance(name, str) and not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name):
        validation.error(path, "frontmatter 'name' must use lowercase kebab-case")


def validate_yaml_file(path: Path, validation: Validation) -> None:
    text = read_utf8(path, validation)
    if text is None:
        return
    data = parse_yaml(text, path, validation)
    if data is None:
        return
    if not isinstance(data, dict):
        validation.error(path, "top-level YAML value must be a mapping")


def markdown_link_target(raw_target: str) -> str:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    elif " " in target:
        target = target.split(" ", 1)[0]
    return unquote(target)


def validate_markdown_links(path: Path, validation: Validation) -> None:
    text = read_utf8(path, validation)
    if text is None:
        return

    for match in LINK_RE.finditer(text):
        target = markdown_link_target(match.group(1))
        if not target or target.startswith("#"):
            continue
        if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target):
            if WINDOWS_ABSOLUTE_RE.match(target):
                validation.error(path, f"local link must be repository-relative: {target}")
            continue

        file_part = target.split("#", 1)[0].split("?", 1)[0]
        if not file_part:
            continue
        candidate = (path.parent / file_part).resolve()
        try:
            candidate.relative_to(ROOT)
        except ValueError:
            validation.error(path, f"local link escapes repository: {target}")
            continue
        if not candidate.exists():
            validation.error(path, f"broken local link: {target}")


def validate_openai_metadata(validation: Validation) -> None:
    path = ROOT / "agents" / "openai.yaml"
    text = read_utf8(path, validation)
    if text is None:
        return
    data = parse_yaml(text, path, validation)
    if not isinstance(data, dict):
        return
    interface = data.get("interface")
    if not isinstance(interface, dict):
        validation.error(path, "'interface' must be a mapping")
        return
    for key in ("display_name", "short_description", "default_prompt"):
        value = interface.get(key)
        if not isinstance(value, str) or not value.strip():
            validation.error(path, f"interface.{key} must be a non-empty string")
    prompt = interface.get("default_prompt")
    if isinstance(prompt, str) and "$tool-routing-architecture" not in prompt:
        validation.error(
            path,
            "interface.default_prompt must reference $tool-routing-architecture",
        )


def validate_text_hygiene(validation: Validation) -> None:
    paths = {
        *(
            path
            for path in ROOT.rglob("*")
            if path.is_file()
            and ".git" not in path.parts
            and path.suffix.lower() in TEXT_SUFFIXES
        ),
        ROOT / ".gitattributes",
        ROOT / ".gitignore",
        ROOT / "VERSION",
    }
    for path in sorted(paths):
        text = read_utf8(path, validation)
        if text is None:
            continue
        if "\x00" in text:
            validation.error(path, "text file contains a NUL byte")
        for line_number, line in enumerate(text.splitlines(), start=1):
            if line.endswith((" ", "\t")):
                validation.error(path, f"line {line_number} has trailing whitespace")


def validate_windows_powershell_sources(validation: Validation) -> None:
    for path in (
        ROOT / "scripts" / "install.ps1",
        ROOT / "tests" / "install.Tests.ps1",
    ):
        try:
            raw = path.read_bytes()
        except OSError as exc:
            validation.error(path, f"cannot inspect PowerShell encoding: {exc}")
            continue
        has_bom = raw.startswith((b"\xef\xbb\xbf", b"\xff\xfe", b"\xfe\xff"))
        if not has_bom and any(byte > 0x7F for byte in raw):
            validation.error(
                path,
                "PowerShell source with non-ASCII text needs a BOM for Windows PowerShell 5.1",
            )


def validate_repository_contract(validation: Validation) -> None:
    required = (
        ROOT / "README.md",
        ROOT / "README.zh-CN.md",
        ROOT / "CHANGELOG.md",
        ROOT / "LICENSE",
        ROOT / "VERSION",
        ROOT / "SKILL.md",
        ROOT / "agents" / "openai.yaml",
        ROOT / "scripts" / "install.ps1",
        ROOT / "tests" / "install.Tests.ps1",
        ROOT / "examples" / "AGENTS.md.snippet",
        ROOT / "examples" / "CLAUDE.md.snippet",
        ROOT / "references" / "authoring.md",
        ROOT / "references" / "lifecycle.md",
        ROOT / "references" / "route-tests.md",
        ROOT / "references" / "runtime-adapters.md",
        ROOT / ".github" / "workflows" / "ci.yml",
    )
    for path in required:
        if not path.is_file():
            validation.error(path, "required repository file is missing")

    version: str | None = None
    version_text = read_utf8(ROOT / "VERSION", validation)
    if version_text is not None:
        version = version_text.strip()
        if version_text != f"{version}\n":
            validation.error(
                ROOT / "VERSION",
                "must contain exactly one semantic version followed by LF",
            )
        if not SEMVER_RE.fullmatch(version):
            validation.error(
                ROOT / "VERSION",
                "must contain a valid semantic version without a leading 'v'",
            )

    english_readme = read_utf8(ROOT / "README.md", validation)
    chinese_readme = read_utf8(ROOT / "README.zh-CN.md", validation)
    changelog_text = read_utf8(ROOT / "CHANGELOG.md", validation)
    if english_readme is not None:
        if "README.zh-CN.md" not in english_readme:
            validation.error(ROOT / "README.md", "must link to the Chinese README")
        if version is not None and f"v{version}" not in english_readme:
            validation.error(ROOT / "README.md", f"must display release v{version}")
    if chinese_readme is not None:
        if "README.md" not in chinese_readme:
            validation.error(ROOT / "README.zh-CN.md", "must link to the English README")
        if version is not None and f"v{version}" not in chinese_readme:
            validation.error(ROOT / "README.zh-CN.md", f"must display release v{version}")
    if changelog_text is not None and version is not None:
        if f"## [{version}]" not in changelog_text:
            validation.error(
                ROOT / "CHANGELOG.md",
                f"must contain a [{version}] release heading",
            )

    skill_text = read_utf8(ROOT / "SKILL.md", validation)
    if skill_text is not None:
        if "name: tool-routing-architecture" not in skill_text:
            validation.error(ROOT / "SKILL.md", "unexpected source skill name")
        physical_lines = len(skill_text.splitlines())
        if physical_lines > 500:
            validation.error(
                ROOT / "SKILL.md",
                f"main skill must stay at or below 500 physical lines (found {physical_lines})",
            )
        if "remains explicit when the tool name is formatted" not in skill_text:
            validation.error(
                ROOT / "SKILL.md",
                "quoted or backticked current-user tool names must remain explicit",
            )

    install_text = read_utf8(ROOT / "scripts" / "install.ps1", validation)
    if install_text is not None:
        for parameter in (
            "AddOnboardingRules",
            "AddRuntimeRules",
            "AddGlobalRules",
            "CodexHome",
            "ClaudeConfigDir",
            "ZcodeHome",
        ):
            if not re.search(rf"\[switch\]\s*\${parameter}|\[string\]\s*\${parameter}", install_text):
                validation.error(
                    ROOT / "scripts" / "install.ps1",
                    f"missing installer parameter -{parameter}",
                )
        codex_literal_conversion = re.compile(
            r"\.Replace\(\s*['\"]`tool-routing-architecture`['\"]\s*,\s*"
            r"['\"]`tool-use-architecture`['\"]\s*\)"
        )
        if not codex_literal_conversion.search(install_text):
            validation.error(
                ROOT / "scripts" / "install.ps1",
                "Codex conversion must rewrite the backticked architecture skill name",
            )
        for requirement, description in (
            ("$VersionSource", "version source validation"),
            ("Copy-Item -LiteralPath $VersionSource", "installed version copy"),
            ("$IsMacOSPlatform", "macOS path-comparison policy"),
            ("LinkTarget", "broken POSIX symbolic-link detection"),
            ("ResolveLinkTarget", "POSIX symbolic-link canonicalization"),
            ("GetUnixFileMode", "Unix file-mode capture"),
            ("SetUnixFileMode", "Unix file-mode restoration"),
            ("PowerShell 7.2 or later", "POSIX PowerShell version gate"),
        ):
            if requirement not in install_text:
                validation.error(
                    ROOT / "scripts" / "install.ps1",
                    f"missing cross-platform contract: {description}",
                )

    tests_text = read_utf8(ROOT / "tests" / "install.Tests.ps1", validation)
    if tests_text is not None:
        for requirement, description in (
            ("VERSION", "installed version test"),
            ("EXPECTED_TEST_OS", "CI runner identity assertion"),
            ("SymbolicLink", "POSIX symbolic-link tests"),
            ("UnixFileMode", "Unix permission-preservation tests"),
            ("IsMacOSTest", "macOS-specific tests"),
            ("IsLinuxTest", "Linux-specific tests"),
        ):
            if requirement not in tests_text:
                validation.error(
                    ROOT / "tests" / "install.Tests.ps1",
                    f"missing cross-platform test contract: {description}",
                )

    ci_text = read_utf8(ROOT / ".github" / "workflows" / "ci.yml", validation)
    if ci_text is not None:
        for requirement in (
            "windows-latest",
            "ubuntu-latest",
            "macos-latest",
            "EXPECTED_TEST_OS",
            "actionlint",
        ):
            if requirement not in ci_text:
                validation.error(
                    ROOT / ".github" / "workflows" / "ci.yml",
                    f"CI must include cross-platform requirement '{requirement}'",
                )
        if re.search(r"(?m)^\s*shell:\s*\$\{\{\s*matrix\.", ci_text):
            validation.error(
                ROOT / ".github" / "workflows" / "ci.yml",
                "GitHub Actions does not allow matrix context in a step shell field",
            )

    snippet_paths = (
        ROOT / "examples" / "AGENTS.md.snippet",
        ROOT / "examples" / "CLAUDE.md.snippet",
    )
    snippet_texts: list[str] = []
    for path in snippet_paths:
        text = read_utf8(path, validation)
        if text is None:
            continue
        snippet_texts.append(text.replace("\r\n", "\n").replace("\r", "\n"))
        for heading in ("## Tool Directory Routing", "## Tool Onboarding Gate"):
            if text.count(heading) != 1:
                validation.error(path, f"must contain exactly one '{heading}' heading")
    if len(snippet_texts) == 2 and snippet_texts[0] != snippet_texts[1]:
        validation.error(
            snippet_paths[1],
            "Claude and AGENTS snippets must remain text-identical",
        )

    route_tests_text = read_utf8(ROOT / "references" / "route-tests.md", validation)
    if route_tests_text is not None:
        if "commit/tag are pinned" in route_tests_text:
            validation.error(
                ROOT / "references" / "route-tests.md",
                "a mutable tag alone must not satisfy remote-skill provenance",
            )
        if not re.search(
            r"A mutable tag\s+alone is not sufficient provenance",
            route_tests_text,
        ):
            validation.error(
                ROOT / "references" / "route-tests.md",
                "remote-skill tests must require an exact SHA or verified artifact digest",
            )


def main() -> int:
    validation = Validation()
    validate_repository_contract(validation)

    for path in SKILL_FRONTMATTER_FILES:
        if not path.is_file():
            validation.error(path, "expected skill template is missing")
        else:
            validate_frontmatter(path, validation)

    for path in YAML_FILES:
        validate_yaml_file(path, validation)
    validate_openai_metadata(validation)

    for path in MARKDOWN_FILES:
        validate_markdown_links(path, validation)
    validate_text_hygiene(validation)
    validate_windows_powershell_sources(validation)

    if validation.errors:
        print(f"Repository validation failed with {len(validation.errors)} error(s):")
        for error in validation.errors:
            print(f"- {error}")
        return 1

    print(
        "Repository validation passed: "
        f"{len(SKILL_FRONTMATTER_FILES)} frontmatter files, "
        f"{len(YAML_FILES)} YAML files, and {len(MARKDOWN_FILES)} Markdown files."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
