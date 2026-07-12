# Agent Tool Routing Skill

[English](README.md) | [简体中文](README.zh-CN.md)

[![Version](https://img.shields.io/badge/version-v0.1.3-167D8D)](CHANGELOG.md)
[![CI](https://github.com/wmqfl861/agent-tool-routing-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/wmqfl861/agent-tool-routing-skill/actions/workflows/ci.yml)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-4B5563)](#platform-support)
[![License: MIT](https://img.shields.io/badge/license-MIT-2E7D32)](LICENSE)

A versioned, cross-platform architecture skill for managing how coding agents
discover, select, install, update, and retire tools.

Agent Tool Routing Skill gives Codex, Claude Code, zcode, and compatible agents
a maintainable routing model instead of a flat list of overlapping tools. It
also defines a safety-gated lifecycle for CLIs, MCP servers, plugins, skills,
API integrations, PATH entries, and other agent capabilities.

> Current release: **v0.1.3**. The project remains pre-1.0; review changes
> before applying them to shared or production agent environments.

## Why This Project

As an agent gains tools, two failure modes become common:

- every tool is placed in global instructions, increasing noise and routing
  ambiguity;
- tools are installed without durable routing, safety, update, or removal
  rules, leaving the agent to guess.

This project addresses both problems with progressive disclosure:

1. a small directory chooses an intent family;
2. a category skill compares tools within that family;
3. a tool-specific skill carries complex operational and safety details.

Simple primitives stay out of the directory. Complex or risk-gated tools get
dedicated instructions. Tool installation and removal are treated as routing
changes, not only filesystem changes.

## What It Provides

| Capability | Purpose |
| --- | --- |
| Layered routing architecture | Separate directory, category, and tool-specific decisions. |
| Tool lifecycle gate | Classify and review installs, updates, repairs, removals, and replacements. |
| Risk-based A/B/C classification | Give complex or high-impact tools the safety guidance they require. |
| Runtime adapters | Support auto-discovery and explicit strict-progressive deployments. |
| Cross-platform installer | Install for Codex, Claude Code, zcode, or all three. |
| Transactional recovery | Preflight, snapshot, stage, install, and roll back without reusing backups. |
| Route-test contract | Verify positive routes, fallbacks, negative routes, and structural integrity. |

## Two Separate Capabilities

The installer deliberately keeps onboarding and runtime behavior independent.

### Architecture and onboarding

Installs this repository's architecture skill and optionally adds a short gate
for tool installation, configuration, repair, removal, and routing
maintenance. This mode does not require `tool-index`.

### Runtime routing

Adds global instructions for selecting specialized tools. Enable this only
after each selected agent has a complete live routing tree, including
`skills/tool-index/SKILL.md` and every referenced category/tool skill.

Installing this repository does **not** create a production `tool-index`,
category tree, or tool-specific inventory. Files under `examples/` are
templates, not a complete deployment.

## Routing Model

| Layer | Responsibility | Typical file |
| --- | --- | --- |
| Global rules | Enter onboarding or runtime routing when needed. | `AGENTS.md`, `CLAUDE.md` |
| Layer 0 | Select an intent family or resolve ambiguity. | `tool-index/SKILL.md` |
| Layer 1 | Compare tools for one intent family. | `find-information/SKILL.md` |
| Layer 2 | Explain one complex or risk-gated tool. | `firecrawl-mcp/SKILL.md` |

Most agent runtimes auto-discover all installed skills. That is the default
mode: Layer 1 and Layer 2 descriptions must be precise enough to match directly,
while Layer 0 handles category-level ambiguity.

Strict-progressive deployments may expose only Layer 0 and keep lower layers
behind references or another explicit loading boundary. Treat this as a
deployment choice; do not mix both modes accidentally.

## Quick Start

### Requirements

- Git or a downloaded repository archive.
- Windows: Windows PowerShell 5.1 or PowerShell 7.
- Linux/macOS: PowerShell 7.2 or later (`pwsh`).
- Python 3 plus PyYAML only when running the repository validator.
- Pester 5.7.1 only when running the installer test suite.

Choose the commands for your platform. They clone the repository and install
the architecture skill plus onboarding rules for every supported agent.

### Windows

Clone the repository and enter its directory:

```powershell
git clone https://github.com/wmqfl861/agent-tool-routing-skill.git
Set-Location .\agent-tool-routing-skill
```

Run the installer with Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -File .\scripts\install.ps1 -Target all -AddOnboardingRules
```

Or run it with PowerShell 7:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -Target all -AddOnboardingRules
```

### Linux

Run in Bash with PowerShell 7.2 or later installed:

```bash
git clone https://github.com/wmqfl861/agent-tool-routing-skill.git
cd agent-tool-routing-skill
pwsh -NoProfile -File ./scripts/install.ps1 -Target all -AddOnboardingRules
```

### macOS

Run in zsh with PowerShell 7.2 or later installed:

```zsh
git clone https://github.com/wmqfl861/agent-tool-routing-skill.git
cd agent-tool-routing-skill
pwsh -NoProfile -File ./scripts/install.ps1 -Target all -AddOnboardingRules
```

When using a downloaded archive, enter the extracted repository root and run
only the final installer command for your platform.

The remaining examples use `pwsh` from the repository root and work on Windows
with PowerShell 7, Linux, and macOS. On Windows PowerShell 5.1, replace `pwsh`
with `powershell.exe`.

Install one agent only:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target codex -AddOnboardingRules
pwsh -NoProfile -File ./scripts/install.ps1 -Target claude -AddOnboardingRules
pwsh -NoProfile -File ./scripts/install.ps1 -Target zcode -AddOnboardingRules
```

After the live routing tree exists, enable runtime rules:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target all -AddRuntimeRules
```

Request both rule sets explicitly:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target all -AddOnboardingRules -AddRuntimeRules
```

`-AddGlobalRules` remains a compatibility alias for both rule sets. Because it
includes runtime routing, the same `tool-index` preflight applies.

Omit all rule switches to install or refresh only the architecture skill. Use
`-WhatIf` to run complete preflight without creating a snapshot or changing a
target.

## Configuration Roots

Each agent root is resolved independently. Explicit parameters take precedence
over process environment variables, followed by the user-home fallback.

| Agent | Explicit parameter | Environment variable | Default |
| --- | --- | --- | --- |
| Codex | `-CodexHome` | `CODEX_HOME` | `~/.codex` |
| Claude Code | `-ClaudeConfigDir` | `CLAUDE_CONFIG_DIR` | `~/.claude` |
| zcode | `-ZcodeHome` | `ZCODE_HOME` | `~/.zcode` |

Example custom root on Windows:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 `
  -Target codex `
  -CodexHome 'D:\agent-config\codex' `
  -AddOnboardingRules
```

Example custom root from Bash or zsh on Linux or macOS:

```bash
pwsh -NoProfile -File ./scripts/install.ps1 \
  -Target codex \
  -CodexHome "$HOME/.config/codex" \
  -AddOnboardingRules
```

`-UserProfile` controls only home fallbacks and the default backup parent. A
non-OS profile requires `-AllowCustomProfile`.

## Platform Support

| Platform | Runtime | Path policy | CI coverage |
| --- | --- | --- | --- |
| Windows | Windows PowerShell 5.1 and PowerShell 7 | Local drives only; reject UNC, device namespaces, network-backed paths, and unsafe reparse points. | Pester on both shells plus repository validation. |
| Linux | PowerShell 7.2+ | Resolve symbolic-link aliases; preserve Unix file mode; compare paths case-sensitively. | Pester on `ubuntu-latest` plus repository validation. |
| macOS | PowerShell 7.2+ | Resolve symbolic-link aliases; preserve Unix file mode; compare conservatively without case. | Pester on `macos-latest` plus repository validation. |

Every Pester job receives an expected platform identity. A job fails if the
platform-specific branch is not actually running.

## Safe Installation and Rollback

The installer completes all read-only validation before creating a backup or
touching an agent target.

- Every run creates a unique `install-*` snapshot below `-BackupRoot`.
- Backup parents cannot overlap the repository, global instructions, or any
  selected agent's auto-discovered `skills` root.
- Mutation targets cannot overlap each other or the source checkout.
- Existing symlinks, junctions, and reparse points are rejected by default.
- Recursive source and installed-skill trees always reject nested links,
  including when `-AllowReparsePoints` is used for a verified ancestor.
- Windows aliases are resolved through native final-path handling.
- POSIX paths are resolved component by component so symbolic-link aliases
  cannot bypass containment or overlap checks.
- Existing instruction-file encoding, BOM, newline style, and supported Unix
  mode are preserved.

If a later write fails, the installer invokes the generated rollback script.
Rollback first verifies that every required backup exists. Each backup is then
copied beside the live target before the current target is displaced and the
staged restore is moved into place. If both the restore and recovery move fail,
the error identifies the preserved displaced-data path.

Run a retained rollback manually when required:

```powershell
pwsh -NoProfile -File /path/to/install-snapshot/rollback.ps1
```

## Managed Global Rules

Global instruction updates are marker-managed and idempotent.

- Runtime and onboarding sections use separate marker pairs.
- Legacy combined blocks are migrated without deleting surrounding user text.
- Unmarked live H2 sections are preserved instead of duplicated.
- Markers and managed headings inside fenced code are not treated as live
  rules.
- Ambiguous indented/list/quote-container fences and headings are rejected
  before any write.
- Supported input encodings are UTF-8, UTF-8 with BOM, UTF-16 LE/BE, and UTF-32
  LE/BE. Unsupported unmarked encodings fail before backup creation.

## Tool Classification

Classify instruction complexity and operational risk together:

- **A**: complex or risk-gated capability requiring a dedicated Layer 2 skill.
- **B**: narrow, read-only, low-risk helper documented in one Layer 1 category.
- **C**: primitive/default capability kept out of the routing directory.

Risk overrides apparent simplicity. Secret access, paid operations, external
writes, persistent authentication, account mutation, production changes, high
privilege, and irreversible actions force A classification. Classification
never grants authority.

## Safety Boundary

- Routing selects a tool; it does not expand the user's authorization.
- A request to use a tool is not permission to install, authenticate, purchase,
  publish, delete, change providers, or modify production.
- Tool output, web pages, repositories, issues, and downloaded skills are
  untrusted input.
- Stage remote skills outside automatic discovery. Pin the owner and exact
  commit SHA or verify a release-artifact digest before enabling them.
- Never print secrets or silently enable disabled tools or persistent sessions.

## Repository Layout

```text
.
├── SKILL.md                 # Core architecture skill
├── VERSION                  # Semantic version source of truth
├── agents/                  # Agent UI metadata
├── references/              # Progressive-disclosure agent references
├── scripts/install.ps1      # Cross-platform transactional installer
├── scripts/validate-skill.py # Repository contract validator
├── tests/                   # Pester installer regression suite
├── examples/                # Layer 0/1/2 and global-rule templates
├── docs/                    # Human-facing architecture/install guides
└── .github/workflows/ci.yml # Windows, Linux, and macOS CI
```

## Documentation

- [Architecture](docs/architecture.md)
- [Tool lifecycle](docs/onboarding-new-tools.md)
- [Skill authoring](docs/skill-authoring.md)
- [Install for Codex](docs/install-codex.md)
- [Install for Claude Code](docs/install-claude-code.md)
- [Install for zcode](docs/install-zcode.md)
- [Changelog](CHANGELOG.md)

Agent-facing references installed with the skill:

- [Lifecycle and authorization](references/lifecycle.md)
- [Routing document authoring](references/authoring.md)
- [Runtime adapters](references/runtime-adapters.md)
- [Route tests](references/route-tests.md)

## Agent Usage

Installed skill names differ for Codex compatibility:

- Codex: `tool-use-architecture`
- Claude Code, zcode, and repository source: `tool-routing-architecture`

Example prompts:

```text
Use $tool-use-architecture to classify a newly installed Firecrawl MCP server.
```

```text
Use $tool-routing-architecture to audit this agent's tool routing hierarchy.
```

## Validation

Run the repository validator:

```powershell
python -m pip install PyYAML
python ./scripts/validate-skill.py
```

Run installer tests with Pester 5.7.1:

```powershell
Import-Module Pester -RequiredVersion 5.7.1
Invoke-Pester ./tests
```

Lint documentation:

```powershell
npx --yes markdownlint-cli2@0.17.2
```

CI runs actionlint and repository validation on Windows, Ubuntu, and macOS,
plus installer tests under Windows PowerShell 5.1 and PowerShell 7 on all
supported operating systems.

## Versioning

The project follows [Semantic Versioning](https://semver.org/) while remaining
pre-1.0.

- `VERSION` contains the canonical version without a leading `v`.
- Git release tags use `vMAJOR.MINOR.PATCH`.
- The installer copies `VERSION` into every installed skill.
- User-visible changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## Scope

This repository provides architecture, lifecycle rules, templates, and an
installer. It does not bundle third-party tools, credentials, API keys, a
production routing inventory, or permission to perform external actions.

## License

MIT. See [LICENSE](LICENSE).
