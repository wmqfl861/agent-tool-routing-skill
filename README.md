# Agent Tool Routing Skill

A reusable skill for Codex, Claude Code, zcode, and similar AI coding agents.
It helps an agent decide when to read tool documentation, how to choose
between overlapping tools, and how newly installed tools should enter the
routing hierarchy.

中文简介：这是一个给 Codex/Claude Code/zcode 等 agent 使用的工具路由 skill。它把工具说明拆成轻量目录、分类说明和具体工具说明三层，让 agent 在需要时自己判断该读哪个说明、该调用哪个工具，同时避免每次普通操作都变慢。

## What This Repository Contains

- `SKILL.md`: the installable agent skill. This is the source of truth that an
  agent reads when designing, installing, auditing, or repairing a tool-routing
  architecture.
- `agents/openai.yaml`: display metadata for OpenAI/Codex skill UIs.
- `docs/`: human-facing installation, architecture, and maintenance guides.
- `examples/`: copyable instruction snippets and sample skill files.

## Why Use It

Modern agents often receive many tools at once: native shell tools, MCP servers,
browser controllers, web crawlers, search tools, file converters, image tools,
and project-specific helpers. If every tool is listed directly in global
instructions, routing becomes noisy and slow. If nothing is documented, agents
guess and misuse tools.

This project uses a layered model:

1. **Global rule**: a short trigger in `AGENTS.md` or equivalent.
2. **Layer 0 directory**: a light `tool-index` skill that chooses a category.
3. **Layer 1 category skills**: compare tools for one intent family.
4. **Layer 2 tool skills**: detailed instructions for complex tools.

Simple primitives stay out of the directory. Complex tools get specific skills.
New tool installs must be classified as A/B/C before setup is considered done.

## Quick Start

Clone or download this repository, then install the skill directory into the
agent's skill location.

For Codex:

```powershell
$skills = "$env:USERPROFILE\.codex\skills"
$target = "$skills\tool-use-architecture"
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -Force ".\SKILL.md" "$target\SKILL.md"
Copy-Item -Recurse -Force ".\agents" "$target\agents"

$skill = Get-Content "$target\SKILL.md" -Raw
$skill.Replace('name: tool-routing-architecture', 'name: tool-use-architecture') |
  Set-Content "$target\SKILL.md" -Encoding UTF8

$metadata = Get-Content "$target\agents\openai.yaml" -Raw
$metadata.Replace('$tool-routing-architecture', '$tool-use-architecture') |
  Set-Content "$target\agents\openai.yaml" -Encoding UTF8
```

Then add the global routing and onboarding snippets from
[`examples/AGENTS.md.snippet`](examples/AGENTS.md.snippet) to:

```text
%USERPROFILE%\.codex\AGENTS.md
```

For Claude Code and zcode, see:

- [Install for Claude Code](docs/install-claude-code.md)
- [Install for zcode](docs/install-zcode.md)
- [Install for Codex](docs/install-codex.md)

## Agent Usage

After installation, an agent should use this skill when:

- setting up or repairing a tool-routing hierarchy;
- deciding whether a tool needs a dedicated skill;
- adding a new MCP server, CLI, plugin, API service, PATH entry, or skill;
- auditing whether tool instructions are too broad, missing, or duplicated;
- creating `tool-index`, category skills, or tool-specific skills.

Common installed skill names are:

- Codex live compatibility install: `tool-use-architecture`
- Claude Code, zcode, and the generic repository skill: `tool-routing-architecture`

Example user prompt:

```text
Use $tool-use-architecture to add this new Firecrawl MCP server into my
tool-routing hierarchy.
```

For Claude Code and zcode, use `$tool-routing-architecture` instead.

## Architecture Overview

Read [Architecture](docs/architecture.md) for the full model.

Short version:

| Layer | Purpose | Typical file |
| --- | --- | --- |
| Global rule | Decide when to enter routing | `AGENTS.md`, `CLAUDE.md` |
| Layer 0 | Choose a tool category | `tool-index/SKILL.md` |
| Layer 1 | Compare tools in one category | `find-information/SKILL.md` |
| Layer 2 | Explain one complex tool | `firecrawl-mcp/SKILL.md` |

## Tool Classification

Every new capability is classified before it is wired into the hierarchy:

- **A**: complex three-layer tool. Requires a Layer 2 tool-specific skill.
- **B**: simple category-only helper. Mention it inside one category skill.
- **C**: primitive/default capability. Keep it out of the directory.

Read [Tool Lifecycle](docs/onboarding-new-tools.md) for the exact process.

## Removing Tools

Deleting a binary, MCP server, plugin, API key, or skill folder is not enough.
Removing, disabling, or replacing a tool is complete only after the routing
hierarchy no longer points to the removed capability.

Removal cleanup should:

- remove Layer 1 routes to the tool;
- delete or archive unused Layer 2 tool skills;
- update replacement guidance;
- clean global instructions, README, docs, examples, and MCP/plugin/CLI/API/PATH
  references;
- search for dangling tool names, commands, env vars, paths, and config keys;
- run a negative route test proving the removed tool is no longer selected.

## Updating This Skill

When this repository changes, update installed copies deliberately:

1. Back up the live agent instructions and skill folders.
2. Pull the latest repository changes.
3. Re-copy `SKILL.md` and `agents/` into the installed skill directory.
4. For Codex compatibility installs, keep the installed folder and frontmatter
   name as `tool-use-architecture`.
5. Re-check whether the global snippets changed and merge only the needed
   routing updates into `AGENTS.md` or `CLAUDE.md`.
6. Re-run validation and at least one route test.

The snippets in `examples/` are routing-only starting points. Add local safety
rules such as MCP bans, model/provider change restrictions, and temp-directory
policies separately before treating a deployment as production-ready.

## Examples

- [`examples/AGENTS.md.snippet`](examples/AGENTS.md.snippet): global Codex rule.
- [`examples/CLAUDE.md.snippet`](examples/CLAUDE.md.snippet): global Claude Code rule.
- [`examples/tool-index.SKILL.md`](examples/tool-index.SKILL.md): sample Layer 0 directory.
- [`examples/category-skill.example.md`](examples/category-skill.example.md): sample Layer 1 category skill.
- [`examples/tool-specific-skill.example.md`](examples/tool-specific-skill.example.md): sample Layer 2 tool skill.

## Validation

At minimum, validate:

```powershell
git status --short
Test-Path .\SKILL.md
Test-Path .\agents\openai.yaml
Select-String -Path .\SKILL.md -Pattern '^name: tool-routing-architecture$'
```

If you have Codex skill validation scripts available, run them against the
installed skill directory as well.

## Design Notes

- Keep global instructions short.
- Keep native primitives out of the routing tree.
- Do not force every tool call through the directory.
- Prefer official tool skills when available.
- For missing official skills, write concise Layer 2 skills from official docs,
  CLI help, MCP schemas, examples, auth notes, and failure modes.
- Do not silently enable plugins or change model/provider/API endpoint settings
  while onboarding a tool.
- Do not remove a tool without also removing dangling route, skill, docs,
  examples, and config references.

## License

MIT. See [LICENSE](LICENSE).
