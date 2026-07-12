#!/usr/bin/env python3
"""Validate repository skill metadata, YAML, and local Markdown links."""

from __future__ import annotations

import hashlib
import json
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
TEXT_SUFFIXES = {".json", ".md", ".ps1", ".py", ".snippet", ".yaml", ".yml"}
REMOTE_REPOSITORY = "wmqfl861/agent-tool-routing-skill"
REMOTE_FIXED_PAYLOAD = (
    "VERSION",
    "SKILL.md",
    "examples/AGENTS.md.snippet",
    "examples/CLAUDE.md.snippet",
    "scripts/install.ps1",
)
REMOTE_PAYLOAD_DIRECTORIES = ("agents", "references")
REMOTE_BOOTSTRAP_MAXIMUM_BYTES = 131072
REMOTE_AGENT_TARGETS = (
    ("Codex", "codex"),
    ("Claude Code", "claude"),
    ("zcode", "zcode"),
)
REMOTE_PLATFORM_LANGUAGES = {
    "Windows": "powershell",
    "Linux": "bash",
    "macOS": "zsh",
}
FENCED_BLOCK_RE = re.compile(
    r"(?ms)^(?P<indent>[ \t]{0,3})(?P<fence>`{3,}|~{3,})"
    r"(?P<language>[^\r\n]*)\r?\n(?P<command>.*?)\r?\n"
    r"(?P=indent)(?P=fence)[ \t]*(?=\r?$)"
)


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


def find_markdown_sections(text: str, level: int, heading: str) -> list[str]:
    marker = "#" * level
    pattern = re.compile(
        rf"^{re.escape(marker)}[ \t]+{re.escape(heading)}[ \t]*\r?\n"
        rf"(.*?)(?=^#{{1,{level}}}[ \t]+|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    return [match.group(1) for match in pattern.finditer(text)]


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def remote_payload_paths() -> list[Path]:
    paths = {ROOT / relative for relative in REMOTE_FIXED_PAYLOAD}
    for relative in REMOTE_PAYLOAD_DIRECTORIES:
        directory = ROOT / relative
        if directory.is_dir():
            paths.update(path for path in directory.rglob("*") if path.is_file())
    return sorted(paths, key=lambda path: path.relative_to(ROOT).as_posix())


def expected_remote_manifest(version: str) -> dict[str, Any]:
    files = []
    for path in remote_payload_paths():
        content = path.read_bytes()
        files.append(
            {
                "path": path.relative_to(ROOT).as_posix(),
                "sha256": sha256_bytes(content),
                "size": len(content),
            }
        )
    return {
        "schema_version": 1,
        "repository": REMOTE_REPOSITORY,
        "version": version,
        "files": files,
    }


def validate_remote_payload_line_endings(validation: Validation) -> None:
    for path in remote_payload_paths():
        try:
            content = path.read_bytes()
        except OSError:
            continue
        if b"\r" in content:
            validation.error(
                path,
                "remote payload must use LF newlines so release digests are stable",
            )


def build_remote_install_command(
    version: str,
    bootstrap_hash: str,
    target: str,
    platform: str,
) -> str:
    url = (
        "https://raw.githubusercontent.com/"
        f"{REMOTE_REPOSITORY}/v{version}/scripts/install-remote.ps1"
    )
    if platform == "Windows":
        return (
            f"$u='{url}';$h='{bootstrap_hash}';"
            "$p=Join-Path ([IO.Path]::GetTempPath()) "
            "('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');"
            "try{"
            "& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 "
            "--connect-timeout 30 --max-time 60 --limit-rate 128K "
            f"--max-filesize {REMOTE_BOOTSTRAP_MAXIMUM_BYTES} -fsSL $u -o $p;"
            "if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};"
            f"if((Get-Item -LiteralPath $p).Length -gt {REMOTE_BOOTSTRAP_MAXIMUM_BYTES})"
            "{throw 'Installer exceeds the maximum expected size.'};"
            "if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() "
            "-ne $h){throw 'Installer SHA-256 verification failed.'};"
            "& ([scriptblock]::Create([IO.File]::ReadAllText($p))) "
            f"-Target {target}" +
            "}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}"
        )

    checksum_command = "sha256sum -c -" if platform == "Linux" else "shasum -a 256 -c -"
    return (
        "(set -eu;umask 077;d=\"$(mktemp -d)\";p=\"$d/install.ps1\";"
        "trap 'rm -f \"$p\";rmdir \"$d\"' EXIT;"
        "curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 "
        "--connect-timeout 30 --max-time 60 --limit-rate 128K "
        f"--max-filesize {REMOTE_BOOTSTRAP_MAXIMUM_BYTES} -fsSL '{url}' -o \"$p\";"
        f"printf '%s  %s\\n' '{bootstrap_hash}' \"$p\" | {checksum_command} >/dev/null;"
        f"pwsh -NoProfile -File \"$p\" -Target {target})"
    )


def validate_single_command_block(
    validation: Validation,
    path: Path,
    section: str,
    language: str,
    expected_command: str,
    label: str,
) -> None:
    blocks = list(FENCED_BLOCK_RE.finditer(section))
    if len(blocks) != 1:
        validation.error(path, f"{label} must contain exactly one fenced command block")
        return
    block = blocks[0]
    outside = section[: block.start()] + section[block.end() :]
    if re.search(r"(?m)^[ \t]{0,3}(?:`{3,}|~{3,})", outside) or re.search(
        r"(?m)^(?: {4}|\t)\S",
        outside,
    ):
        validation.error(path, f"{label} must not contain an additional command block")
    actual_language = block.group("language")
    command = block.group("command")
    if actual_language.strip() != language:
        validation.error(path, f"{label} command fence must use '{language}'")
    if "\n" in command or "\r" in command:
        validation.error(path, f"{label} command must occupy one physical line")
    if command != expected_command:
        validation.error(path, f"{label} command does not match the release bootstrap contract")


def validate_remote_install_contract(
    validation: Validation,
    version: str,
) -> str | None:
    manifest_path = ROOT / "scripts" / "install-manifest.json"
    bootstrap_path = ROOT / "scripts" / "install-remote.ps1"
    validate_remote_payload_line_endings(validation)

    try:
        manifest_bytes = manifest_path.read_bytes()
    except OSError as exc:
        validation.error(manifest_path, f"cannot read remote install manifest: {exc}")
        return None
    if manifest_bytes.startswith(b"\xef\xbb\xbf") or b"\r" in manifest_bytes:
        validation.error(manifest_path, "must be UTF-8 without BOM and use LF newlines")
    if not manifest_bytes.endswith(b"\n"):
        validation.error(manifest_path, "must end with one LF newline")
    try:
        manifest = json.loads(manifest_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        validation.error(manifest_path, f"invalid UTF-8 JSON manifest: {exc}")
        manifest = None

    try:
        expected_manifest = expected_remote_manifest(version)
    except OSError as exc:
        validation.error(manifest_path, f"cannot build expected payload manifest: {exc}")
        expected_manifest = None
    if manifest is not None and expected_manifest is not None and manifest != expected_manifest:
        validation.error(
            manifest_path,
            "payload hashes, sizes, paths, or metadata are stale; run update-install-manifest.py",
        )
    manifest_hash = sha256_bytes(manifest_bytes)

    try:
        bootstrap_bytes = bootstrap_path.read_bytes()
    except OSError as exc:
        validation.error(bootstrap_path, f"cannot read remote bootstrap: {exc}")
        return None
    if (
        bootstrap_bytes.startswith(
            (b"\xef\xbb\xbf", b"\xff\xfe", b"\xfe\xff", b"\x00\x00\xfe\xff", b"\xff\xfe\x00\x00")
        )
        or b"\r" in bootstrap_bytes
        or not bootstrap_bytes.endswith(b"\n")
    ):
        validation.error(
            bootstrap_path,
            "must be UTF-8 without BOM, use LF newlines, and end with LF",
        )
    try:
        bootstrap_text = bootstrap_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        validation.error(bootstrap_path, f"remote bootstrap is not valid UTF-8: {exc}")
        return None

    constant_contracts = (
        (r"(?m)^\$ReleaseVersion = '([^']+)'$", version, "release version"),
        (r"(?m)^\$Repository = '([^']+)'$", REMOTE_REPOSITORY, "repository"),
        (r"(?m)^\$ManifestSha256 = '([^']+)'$", manifest_hash, "manifest SHA-256"),
    )
    for pattern, expected, label in constant_contracts:
        match = re.search(pattern, bootstrap_text)
        if match is None or match.group(1) != expected:
            validation.error(bootstrap_path, f"remote bootstrap {label} is stale or missing")

    required_block = re.search(
        r"(?ms)^\$RequiredPayloadPaths = @\((.*?)^\)$",
        bootstrap_text,
    )
    if required_block is None:
        validation.error(bootstrap_path, "missing RequiredPayloadPaths allowlist")
    elif expected_manifest is not None:
        bootstrap_paths = re.findall(r"'([^']+)'", required_block.group(1))
        expected_paths = [entry["path"] for entry in expected_manifest["files"]]
        if sorted(path.lower() for path in bootstrap_paths) != sorted(
            path.lower() for path in expected_paths
        ):
            validation.error(
                bootstrap_path,
                "RequiredPayloadPaths must exactly match the generated manifest",
            )

    for requirement, description in (
        ("AllowAutoRedirect = $false", "HTTPS redirect rejection"),
        ("CancellationTokenSource", "bounded network timeout"),
        ("ResponseContentRead", "bounded response buffering"),
        ("MaxResponseContentBufferSize", "response size limit"),
        ("MaximumBytes", "verified response size"),
        ("ConvertFrom-Json", "structured manifest parsing"),
        ("Get-Sha256", "payload digest verification"),
        ("Get-NormalizedFullPath", "filesystem-root-safe staging paths"),
        ("Remove-VerifiedStagingDirectory", "bounded staging cleanup"),
        ("SourceRoot", "verified offline test source"),
    ):
        if requirement not in bootstrap_text:
            validation.error(bootstrap_path, f"missing remote install contract: {description}")
    if "__MANIFEST_SHA256__" in bootstrap_text:
        validation.error(bootstrap_path, "contains an unresolved manifest hash placeholder")

    return sha256_bytes(bootstrap_bytes)


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
        ROOT / "scripts" / "install-remote.ps1",
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
        ROOT / "scripts" / "install-remote.ps1",
        ROOT / "scripts" / "install-manifest.json",
        ROOT / "scripts" / "update-install-manifest.py",
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

    bootstrap_hash = (
        validate_remote_install_contract(validation, version)
        if version is not None and SEMVER_RE.fullmatch(version)
        else None
    )

    english_readme = read_utf8(ROOT / "README.md", validation)
    chinese_readme = read_utf8(ROOT / "README.zh-CN.md", validation)
    changelog_text = read_utf8(ROOT / "CHANGELOG.md", validation)
    if english_readme is not None:
        if "README.zh-CN.md" not in english_readme:
            validation.error(ROOT / "README.md", "must link to the Chinese README")
    if chinese_readme is not None:
        if "README.md" not in chinese_readme:
            validation.error(ROOT / "README.zh-CN.md", "must link to the English README")

    if version is not None:
        expected_badge_prefix = (
            "[![Version](https://img.shields.io/badge/"
            f"version-v{version}-"
        )
        readme_contracts = (
            (
                ROOT / "README.md",
                english_readme,
                f"> Current release: **v{version}**.",
                "Quick Start",
            ),
            (
                ROOT / "README.zh-CN.md",
                chinese_readme,
                f"> 当前版本：**v{version}**。",
                "快速开始",
            ),
        )
        for path, text, expected_notice, quick_start_heading in readme_contracts:
            if text is None:
                continue
            if expected_badge_prefix not in text:
                validation.error(path, f"must display the v{version} version badge")
            if expected_notice not in text:
                validation.error(path, f"must display the current release as v{version}")

            quick_start_sections = find_markdown_sections(text, 2, quick_start_heading)
            if len(quick_start_sections) != 1:
                validation.error(
                    path,
                    f"must contain exactly one '## {quick_start_heading}' section",
                )
                continue
            quick_start = quick_start_sections[0]
            for forbidden in ("git clone", "Set-Location", "cd agent-tool-routing-skill", "-Target all"):
                if forbidden in quick_start:
                    validation.error(
                        path,
                        f"quick start must not contain legacy install text: {forbidden}",
                    )
            if "/main/" in quick_start or "/latest/" in quick_start:
                validation.error(path, "quick start must use a version-pinned bootstrap URL")

            if bootstrap_hash is None:
                continue
            for platform, language in REMOTE_PLATFORM_LANGUAGES.items():
                platform_sections = find_markdown_sections(quick_start, 3, platform)
                if len(platform_sections) != 1:
                    validation.error(
                        path,
                        f"quick start must contain exactly one '### {platform}' section",
                    )
                    continue
                for agent_name, target in REMOTE_AGENT_TARGETS:
                    agent_sections = find_markdown_sections(
                        platform_sections[0],
                        4,
                        agent_name,
                    )
                    if len(agent_sections) != 1:
                        validation.error(
                            path,
                            f"{platform} must contain exactly one '#### {agent_name}' section",
                        )
                        continue
                    validate_single_command_block(
                        validation,
                        path,
                        agent_sections[0],
                        language,
                        build_remote_install_command(
                            version,
                            bootstrap_hash,
                            target,
                            platform,
                        ),
                        f"{platform}/{agent_name}",
                    )

        install_doc_contracts = (
            (ROOT / "docs" / "install-codex.md", "codex"),
            (ROOT / "docs" / "install-claude-code.md", "claude"),
            (ROOT / "docs" / "install-zcode.md", "zcode"),
        )
        for path, target in install_doc_contracts:
            text = read_utf8(path, validation)
            if text is None:
                continue
            install_sections = find_markdown_sections(
                text,
                2,
                "Install Architecture and Onboarding",
            )
            if len(install_sections) != 1:
                validation.error(
                    path,
                    "must contain exactly one architecture install section",
                )
                continue
            if bootstrap_hash is None:
                continue
            for platform, language in REMOTE_PLATFORM_LANGUAGES.items():
                sections = find_markdown_sections(install_sections[0], 3, platform)
                if len(sections) != 1:
                    validation.error(
                        path,
                        f"must contain exactly one '### {platform}' install section",
                    )
                    continue
                validate_single_command_block(
                    validation,
                    path,
                    sections[0],
                    language,
                    build_remote_install_command(
                        version,
                        bootstrap_hash,
                        target,
                        platform,
                    ),
                    f"{platform}/{target}",
                )

    if changelog_text is not None and version is not None:
        if f"## [{version}]" not in changelog_text:
            validation.error(
                ROOT / "CHANGELOG.md",
                f"must contain a [{version}] release heading",
            )
        release_link = (
            f"[{version}]: https://github.com/wmqfl861/"
            f"agent-tool-routing-skill/releases/tag/v{version}"
        )
        if release_link not in changelog_text:
            validation.error(
                ROOT / "CHANGELOG.md",
                f"must contain the v{version} release link",
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
            ("scripts/install-remote.ps1", "remote bootstrap test suite"),
            ("SourceRoot", "verified local payload test path"),
            ("remote-payload-tamper", "payload tampering rejection test"),
            ("remote-manifest-tamper", "manifest tampering rejection test"),
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
        if ci_text.count("$result.PassedCount -ne 43") != 3:
            validation.error(
                ROOT / ".github" / "workflows" / "ci.yml",
                "every Pester job must require exactly 43 passing tests",
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
