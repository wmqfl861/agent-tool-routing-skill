# Agent Tool Routing Skill

[English](README.md) | [简体中文](README.zh-CN.md)

[![Version](https://img.shields.io/badge/version-v0.2.3-167D8D)](CHANGELOG.md)
[![CI](https://github.com/wmqfl861/agent-tool-routing-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/wmqfl861/agent-tool-routing-skill/actions/workflows/ci.yml)
[![Platforms](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-4B5563)](#platform-support)
[![License: MIT](https://img.shields.io/badge/license-MIT-2E7D32)](LICENSE)

A versioned, cross-platform architecture skill for managing how coding agents
discover, select, install, update, and retire tools.

Agent Tool Routing Skill gives Codex, Claude Code, zcode, and compatible agents
a maintainable routing model instead of a flat list of overlapping tools. It
also defines a safety-gated lifecycle for CLIs, MCP servers, plugins, skills,
API integrations, PATH entries, and other agent capabilities.

> Current release: **v0.2.3**. The project remains pre-1.0; review changes
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

Progressive disclosure is designed to limit irrelevant instructions loaded for
each task. Token efficiency is an architectural objective, not an assumed
measured result. A byte or code-point benchmark measures structural context
load, not model tokens. Quantified token-reduction claims require a
model-specific benchmark that records the runtime, tokenizer, and inventory.

In the canonical synthetic fixture, the unsupported eager-all-documents
anti-pattern loads `11,916` metadata bytes plus `98,901` body bytes, or
`110,817` total. Supported paths load `7,287` total bytes for strict-progressive
A, `4,779` for strict-progressive B, `2,783` for auto-discovery A, `2,375` for
auto-discovery B, and `0` for C bypass. These exact file sizes are not token,
cost, cache, latency, or complete system-prompt measurements. See the
[benchmark methodology](docs/context-benchmark.md).

One isolated Claude Code catalog-matching smoke test requested
`claude-fable-5` with effort `max` and scored `18/18`: A `11/11`, B `4/4`, C
`3/3`, including `4/4` expected abstentions. This is a small synthetic fixture,
not evidence of generalized or production routing accuracy. The model name is
the exact CLI request value; the run cannot prove an immutable backend model
snapshot. The answer-bearing, hash-verified artifacts are preserved under
[`benchmarks/runs/`](benchmarks/runs/).

## What It Provides

| Capability | Purpose |
| --- | --- |
| Layered routing architecture | Separate directory, category, and tool-specific decisions. |
| Opt-in tool lifecycle gate | When explicitly installed, treat a concise delete/uninstall request as complete managed offboarding, with safe ownership checks. |
| Risk-based A/B/C classification | Give complex or high-impact tools the safety guidance they require. |
| Durable index handoff | Queue a per-Agent request for a reviewed, resumable inventory and routing build. |
| Versioned managed inventory | Keep one canonical, revisioned A/B/C record outside discoverable Skill and plugin roots. |
| Runtime adapters | Support auto-discovery and explicit strict-progressive deployments. |
| Cross-platform installer | Install one explicitly named Agent, or all three only with explicit `-Target all`. |
| Locked, journaled recovery | Serialize writers, verify staged trees, recover interrupted Skill swaps, and retain rollback snapshots. |
| Route-test contract | Verify positive routes, fallbacks, negative routes, and structural integrity. |

## Architecture, Initialization, and Runtime

The installer keeps core installation, durable request queuing, Agent-executed
indexing, and ordinary runtime behavior as separate authorization and
validation boundaries.

### Architecture and onboarding

Installs this repository's architecture skill and optionally adds a short gate
for tool installation, configuration, repair, removal, and routing
maintenance. This mode does not require `tool-index`.

When `-AddOnboardingRules` installs the opt-in gate, a current-user request such
as `delete Example Crawler` or `uninstall Example Crawler` for a named or
otherwise unambiguous capability delegates to the architecture skill and
authorizes the complete managed offboarding workflow. The Agent backs up
affected state and removes the capability through the least-destructive
mechanism verified for its actual
installed provenance instead of guessing from its name, removes active routes,
recomputes guide reference counts, deletes unchanged managed orphans, archives
eligible modified or unknown orphans outside discovery, writes an inventory
tombstone, reconciles managed global rules, checks dangling references, and
runs a negative route test. Tool removal and recoverable managed-state
publication are journaled separately; an active route is never restored to a
missing capability.

The user does not need to enumerate those dependent cleanup steps. The Agent
asks only when identity or Agent scope is ambiguous, the remover must destroy
protected state, a plugin-wide removal would expand the named capability's
scope, or a retained shared/external guide cannot be isolated from the removed
capability. Credentials, caches, browser profiles, user data, accounts, and
unrelated capabilities remain untouched unless separately authorized. Exact
tool rollback is promised only when a tested reinstall or restore path was
captured before removal.

Without the opt-in gate, a direct tool lifecycle request alone does not select
the auto-discovered architecture skill. Explicitly invoke the architecture skill
for managed offboarding in a skill-only installation.

### Agent-executed initial routing index

`-InitializeRouting` explicitly authorizes the installer to queue a one-shot
inventory and routing job. During the same locked install and rollback
operation, the verified installer creates a durable `pending` request or
preserves an existing resumable request. The installer does not inventory
capabilities, search for or download Skills, author guides, build routes, or
launch another Agent process.

The pending request is inert until the current user explicitly asks the target
Agent to initialize or resume routing. It must not replace an unrelated task,
and it is valid only for the recorded `target_agent`, `target_config_root`, and
single-Agent mutation scope. A running Agent is not guaranteed to hot-reload a
newly installed skill, so start a fresh target-Agent session before explicitly
resuming the job.

The index covers capabilities registered with or discoverable by the selected
Agent, including enabled MCP servers, plugins, skills, and configured
integrations where the runtime exposes them. It does not classify every
executable on `PATH` or crawl unrelated workspaces. Resolved A and B
capabilities enter active intent routes. Every C capability remains managed in
the inventory with its exclusion rationale and bypasses active intent routing.
Complete inventory management does not mean that every class generates a
route.

The successful index publishes one canonical inventory at
`<agent-config-root>/tool-routing-state/inventory.json`, outside discoverable
Skill and plugin roots. It uses stable capability ids and monotonic revisions,
and it is committed with the matching route tree and managed global sections.
Per-job inventories are resumable working copies, not the long-term source of
truth.

Only the Agent that consumes the pending job publishes stable phase progress
while it inventories, classifies, sources, builds, and validates the tree. The
installer reports installation and request-queue results, not indexing phase
progress. During an Agent-mediated lifecycle operation, a newly added A
capability without a usable local or bundled guide triggers one question:
search and review the canonical official source, author from sufficient
reviewed official documentation, or leave the capability unrouted. Tools added
outside an Agent lifecycle operation are discovered during the next explicit
onboarding sync or index.

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

Choose one command for your operating system and Agent. Each command installs
only the verified architecture skill for that explicit target. It does not
modify another Agent, add global onboarding/runtime rules, or queue indexing.
Those changes require separate explicit switches. The installer can run from
any directory and does not require Git.

The commands are pinned to `v0.2.3`. They download the bootstrap to a private
temporary file, verify its embedded SHA-256 before execution, and then verify a
bootstrap-anchored manifest plus every runtime payload file before invoking the
transactional installer. No command pipes unverified network content into a
shell.

### Windows

Run in Windows PowerShell 5.1 or PowerShell 7.

#### Codex

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.3/scripts/install-remote.ps1';$h='4ffc0ae2428096d9eeffa1a8293a1dcd1a1c3bccb14a513850634d5d2c42ce8e';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target codex}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

#### Claude Code

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.3/scripts/install-remote.ps1';$h='4ffc0ae2428096d9eeffa1a8293a1dcd1a1c3bccb14a513850634d5d2c42ce8e';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target claude}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

#### zcode

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.3/scripts/install-remote.ps1';$h='4ffc0ae2428096d9eeffa1a8293a1dcd1a1c3bccb14a513850634d5d2c42ce8e';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target zcode}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

### Linux

Run in Bash.

#### Codex

```bash
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.3/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '4ffc0ae2428096d9eeffa1a8293a1dcd1a1c3bccb14a513850634d5d2c42ce8e' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target codex)
```

#### Claude Code

```bash
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.3/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '4ffc0ae2428096d9eeffa1a8293a1dcd1a1c3bccb14a513850634d5d2c42ce8e' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target claude)
```

#### zcode

```bash
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.3/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '4ffc0ae2428096d9eeffa1a8293a1dcd1a1c3bccb14a513850634d5d2c42ce8e' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target zcode)
```

### macOS

Run in zsh.

#### Codex

```zsh
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.3/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '4ffc0ae2428096d9eeffa1a8293a1dcd1a1c3bccb14a513850634d5d2c42ce8e' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target codex)
```

#### Claude Code

```zsh
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.3/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '4ffc0ae2428096d9eeffa1a8293a1dcd1a1c3bccb14a513850634d5d2c42ce8e' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target claude)
```

#### zcode

```zsh
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.3/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '4ffc0ae2428096d9eeffa1a8293a1dcd1a1c3bccb14a513850634d5d2c42ce8e' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target zcode)
```

The quick-start commands stop after verified single-Agent installation. Add
`-AddOnboardingRules` only when the target Agent's global lifecycle gate is
desired. Add `-InitializeRouting` only to queue an explicit pending index job;
that job remains inert until the current user asks the recorded target Agent to
initialize or resume it. Neither option authorizes writes to another Agent
configuration root.

The Agent consuming the request checks local and bundled skills first. For a
missing A guide, an official candidate is pinned, downloaded outside
auto-discovery, and reviewed before activation; otherwise a minimal guide may
be authored from sufficient reviewed official documentation. If source
ownership or evidence is insufficient, the A capability remains unresolved and
the new runtime tree is not activated. Re-running the command retains the
snapshot, staging, rollback, and resumable-job safeguards.

## Advanced Local Installation

Use a reviewed local checkout for offline installation, custom roots, or
runtime-rule activation. The following examples run from the repository root
with PowerShell 7 on every platform; Windows PowerShell 5.1 users can replace
`pwsh` with `powershell.exe`.

Install only the architecture skill for one Agent:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target codex
```

Queue an initial-index request separately when that work is intended:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target codex -InitializeRouting
```

Then explicitly ask a fresh Codex session to initialize or resume routing. A
pending request never takes priority over an unrelated current task. Use
`-Target all` only when changing Codex, Claude Code, and zcode together is the
intended scope.

After the live routing tree exists, enable runtime rules:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target all -AddRuntimeRules
```

Request both rule sets explicitly:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target all -AddOnboardingRules -AddRuntimeRules
```

`-AddGlobalRules` is retained only to return a migration error because one
switch must not silently enable two independent global rule sets. Use
`-AddOnboardingRules` and/or `-AddRuntimeRules` explicitly.
The remote bootstrap still accepts `-SkipOnboardingRules` for compatibility;
it is redundant now that skill-only installation is the default, and it cannot
be combined with `-AddOnboardingRules`.

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
- A deterministic per-config-root Mutex prevents concurrent installers from
  planning and rolling back the same Agent state at once.
- Skill replacement verifies a private prepared tree and persists a journal
  plus its tree digest below a non-Skill transaction container before moving
  the live directory.

The transaction container stays on the Skill root's filesystem so directory
moves remain same-filesystem operations. Its direct child has no `SKILL.md`;
payloads are nested one level deeper. Standard immediate-child Skill discovery
therefore ignores it, but a non-standard recursive discovery implementation
must explicitly exclude `.agent-tool-routing-transactions`.

If a later write fails, the installer invokes the generated rollback script.
Rollback first verifies that every required backup exists. Each backup is then
copied beside the live target before the current target is displaced and the
staged restore is moved into place. If both the restore and recovery move fail,
the error identifies the preserved displaced-data path.

The journal closes the live-directory gap for interrupted Skill swaps; it does
not make Skill, global instructions, and initial-index state one power-loss
atomic transaction. After a process or host interruption, rerun the installer
to recover the retained journal and complete the idempotent install. Snapshot
rollback restores ordinary contents but does not promise to preserve ACLs,
extended attributes, hardlink relationships, or directory identity. A manual
rollback script does not acquire the installer Mutex, so do not run it in
parallel with an installation.

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
- **C**: primitive/default capability retained in the managed inventory with
  an exclusion rationale while bypassing active intent routing.

Risk overrides apparent simplicity. Secret access, paid operations, external
writes, persistent authentication, account mutation, production changes, high
privilege, and irreversible actions force A classification. Classification
never grants authority.

## Safety Boundary

- Routing selects a tool; it does not expand the user's authorization.
- A request to use a tool is not permission to install, authenticate, purchase,
  publish, delete, change providers, or modify production.
- When delegated by the opt-in onboarding gate, or when the architecture skill
  is explicitly activated for that work, a request to remove, delete, or
  uninstall an unambiguously identified tool is permission for its complete
  managed offboarding, not for deleting shared or user-modified artifacts,
  credentials, caches, user data, accounts, or other capabilities.
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
│   ├── benchmark-routing.py # Context-load and blind-route benchmark CLI
│   ├── install.ps1          # Cross-platform transactional installer
│   ├── install-remote.ps1   # Verified release bootstrap
│   ├── install-manifest.json # Release payload digests and sizes
│   ├── update-install-manifest.py # Deterministic manifest generator
│   └── validate-skill.py    # Repository contract validator
├── benchmarks/              # Synthetic topology, canonical context result, blind cases
├── tests/                   # Pester and Python regression suites
├── examples/                # Layer 0/1/2 and global-rule templates
├── docs/                    # Human-facing architecture/install guides
└── .github/workflows/ci.yml # Windows, Linux, and macOS CI
```

## Documentation

- [Architecture](docs/architecture.md)
- [Tool lifecycle](docs/onboarding-new-tools.md)
- [Skill authoring](docs/skill-authoring.md)
- [Context load and routing benchmark](docs/context-benchmark.md)
- [Install for Codex](docs/install-codex.md)
- [Install for Claude Code](docs/install-claude-code.md)
- [Install for zcode](docs/install-zcode.md)
- [Changelog](CHANGELOG.md)

Agent-facing references installed with the skill:

- [Lifecycle and authorization](references/lifecycle.md)
- [Initial indexing](references/initial-index.md)
- [Managed capability inventory](references/managed-inventory.md)
- [Routing document authoring](references/authoring.md)
- [Runtime adapters](references/runtime-adapters.md)
- [Route tests](references/route-tests.md)

## Agent Usage

Installed skill names differ for Codex compatibility:

- Codex: `tool-use-architecture`
- Claude Code, zcode, and repository source: `tool-routing-architecture`

Example prompts:

```text
Use $tool-use-architecture to audit this Codex routing architecture.
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

`tests/test_activation_boundaries.py` validates metadata, installed-rule, and
non-interference contracts. It intentionally does not implement a substitute
model selector or claim to prove how every future host model will auto-select a
Skill; host-level claims require a separately recorded runtime run.

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
