# Agent Tool Routing Skill

[English](README.md) | [简体中文](README.zh-CN.md)

[![Version](https://img.shields.io/badge/version-v0.2.0-167D8D)](CHANGELOG.md)
[![CI](https://github.com/wmqfl861/agent-tool-routing-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/wmqfl861/agent-tool-routing-skill/actions/workflows/ci.yml)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-4B5563)](#platform-support)
[![License: MIT](https://img.shields.io/badge/license-MIT-2E7D32)](LICENSE)

A versioned, cross-platform architecture skill for managing how coding agents
discover, select, install, update, and retire tools.

Agent Tool Routing Skill gives Codex, Claude Code, zcode, and compatible agents
a maintainable routing model instead of a flat list of overlapping tools. It
also defines a safety-gated lifecycle for CLIs, MCP servers, plugins, skills,
API integrations, PATH entries, and other agent capabilities.

> Current release: **v0.2.0**. The project remains pre-1.0; review changes
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
| Initial routing index | Inventory registered capabilities and build a reviewed, resumable routing tree. |
| Runtime adapters | Support auto-discovery and explicit strict-progressive deployments. |
| Cross-platform installer | Install for Codex, Claude Code, zcode, or all three. |
| Transactional recovery | Preflight, snapshot, stage, install, and roll back without reusing backups. |
| Route-test contract | Verify positive routes, fallbacks, negative routes, and structural integrity. |

## Architecture, Initialization, and Runtime

The installer keeps core installation, initial indexing, and ordinary runtime
behavior as separate authorization and validation boundaries.

### Architecture and onboarding

Installs this repository's architecture skill and optionally adds a short gate
for tool installation, configuration, repair, removal, and routing
maintenance. This mode does not require `tool-index`.

### Initial routing index

`-InitializeRouting` explicitly requests a one-shot inventory and routing
build. In the same transactional recovery boundary as the core installation,
the verified installer creates a durable `pending` request or preserves an
existing resumable request. It queues the work; it does not launch another
Agent process.

When an Agent invokes the installer, that Agent must continue the pending job
before ordinary work. When the command runs directly in a terminal, the next
fresh turn of the target Agent consumes the request before ordinary work. A
running Agent is not guaranteed to hot-reload newly installed skills or global
instructions, so same-turn processing is not guaranteed.

The index covers capabilities registered with or discoverable by the selected
Agent, including enabled MCP servers, plugins, skills, and configured
integrations where the runtime exposes them. It does not classify every
executable on `PATH` or crawl unrelated workspaces. Resolved A and B
capabilities enter intent-based routes; C primitives remain in the inventory
with their exclusion rationale.

The Agent that processes the job publishes stable phase progress while it
inventories, classifies, sources, builds, and validates the tree. During an
Agent-mediated lifecycle operation, a newly added A capability without a usable
local or bundled guide triggers one question: search and review the canonical
official source, author from sufficient reviewed official documentation, or
leave the capability unrouted. Tools added outside an Agent lifecycle operation
are discovered during the next explicit onboarding sync or index.

### Runtime routing

Adds global instructions for selecting specialized tools. Enable this only
after each selected agent has a complete live routing tree, including
`skills/tool-index/SKILL.md` and every referenced category/tool skill.

An architecture-only installation does **not** create a production
`tool-index`, category tree, or tool inventory. `-InitializeRouting` asks the
Agent to build them from the effective environment; files under `examples/`
remain templates, not a prebuilt deployment.

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

- Windows 10 1803+, Windows Server 2019+, or another supported Windows release
  with Windows PowerShell 5.1 or PowerShell 7, `curl.exe`, and HTTPS access.
- Linux: Bash, `curl`, `sha256sum`, and PowerShell 7.2 or later (`pwsh`).
- macOS: zsh, `curl`, `shasum`, and PowerShell 7.2 or later (`pwsh`).
- Python 3 plus PyYAML only when running the repository validator.
- Pester 5.7.1 only when running the installer test suite.

Choose one command for your operating system and agent. Each command installs
the verified architecture skill and onboarding gate, then creates a pending
one-shot request to initialize that Agent's routing tree. It can be run from
any directory and does not require Git.

The commands are pinned to `v0.2.0`. They download the bootstrap to a private
temporary file, verify its embedded SHA-256 before execution, and then verify a
bootstrap-anchored manifest plus every runtime payload file before invoking the
transactional installer. No command pipes unverified network content into a
shell.

### Windows

Run in Windows PowerShell 5.1 or PowerShell 7.

#### Codex

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.0/scripts/install-remote.ps1';$h='dbf60fc240741068788ea0e96136af53fd810d8c0e081ac378899e0ff95f64d6';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target codex -InitializeRouting}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

#### Claude Code

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.0/scripts/install-remote.ps1';$h='dbf60fc240741068788ea0e96136af53fd810d8c0e081ac378899e0ff95f64d6';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target claude -InitializeRouting}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

#### zcode

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.0/scripts/install-remote.ps1';$h='dbf60fc240741068788ea0e96136af53fd810d8c0e081ac378899e0ff95f64d6';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target zcode -InitializeRouting}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

### Linux

Run in Bash.

#### Codex

```bash
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.0/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'dbf60fc240741068788ea0e96136af53fd810d8c0e081ac378899e0ff95f64d6' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target codex -InitializeRouting)
```

#### Claude Code

```bash
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.0/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'dbf60fc240741068788ea0e96136af53fd810d8c0e081ac378899e0ff95f64d6' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target claude -InitializeRouting)
```

#### zcode

```bash
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.0/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'dbf60fc240741068788ea0e96136af53fd810d8c0e081ac378899e0ff95f64d6' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target zcode -InitializeRouting)
```

### macOS

Run in zsh.

#### Codex

```zsh
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.0/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'dbf60fc240741068788ea0e96136af53fd810d8c0e081ac378899e0ff95f64d6' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target codex -InitializeRouting)
```

#### Claude Code

```zsh
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.0/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'dbf60fc240741068788ea0e96136af53fd810d8c0e081ac378899e0ff95f64d6' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target claude -InitializeRouting)
```

#### zcode

```zsh
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.0/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'dbf60fc240741068788ea0e96136af53fd810d8c0e081ac378899e0ff95f64d6' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target zcode -InitializeRouting)
```

After verified core installation, `-InitializeRouting` transactionally writes
or preserves the pending one-shot request. It does not launch another Agent.
An Agent that invoked the command must continue the job before ordinary work;
after a direct terminal install, the next fresh target-Agent turn consumes it.
There is no guarantee that a running Agent will hot-reload the new skill or
global rules or complete the index in the installation turn.

The indexer checks local and bundled skills first. For a missing A guide, an
official candidate is pinned, downloaded outside auto-discovery, and reviewed
before activation; otherwise a minimal guide may be authored from sufficient
reviewed official documentation. If source ownership or evidence is
insufficient, the A capability remains unresolved and the new runtime tree is
not activated. Re-running the command retains the snapshot, staging, rollback,
and resumable-job safeguards.

## Advanced Local Installation

Use a reviewed local checkout for offline installation, custom roots, or
runtime-rule activation. The following examples run from the repository root
with PowerShell 7 on every platform; Windows PowerShell 5.1 users can replace
`pwsh` with `powershell.exe`.

Install and create the same initial-index request from a local checkout:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target all -InitializeRouting
```

The local installer also only queues the durable request. The Agent processing
that request emits indexing progress and removes it only after successful
completion.

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
| Windows 10 1803+ / Server 2019+ | Windows PowerShell 5.1 or PowerShell 7 with `curl.exe` | Local drives only; reject UNC, device namespaces, network-backed paths, and unsafe reparse points. | Pester on both shells plus repository validation. |
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
├── scripts/
│   ├── install.ps1          # Cross-platform transactional installer
│   ├── install-remote.ps1   # Verified release bootstrap
│   ├── install-manifest.json # Release payload digests and sizes
│   ├── update-install-manifest.py # Deterministic manifest generator
│   └── validate-skill.py    # Repository contract validator
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

Release maintainers regenerate the verified payload manifest before validation:

```powershell
python ./scripts/update-install-manifest.py
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
