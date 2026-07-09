# Install for Claude Code

This guide adapts the skill for Claude Code. Paths may vary by installation, so
verify the active Claude Code config directory on your machine before editing.

## 1. Install the Skill

One-command install:

```powershell
.\scripts\install.ps1 -Target claude -AddGlobalRules
```

The installer backs up existing files and prints a rollback script path. Omit
`-AddGlobalRules` to install only the skill files. If existing unmarked routing
and onboarding sections are already present, the installer leaves them unchanged
instead of appending duplicates.

Typical user-level location:

```text
%USERPROFILE%\.claude\skills\tool-routing-architecture
```

From this repository root:

```powershell
$target = "$env:USERPROFILE\.claude\skills\tool-routing-architecture"
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -Force ".\SKILL.md" "$target\SKILL.md"
Copy-Item -Recurse -Force ".\agents" "$target\agents"
```

## 2. Add Global Routing Rules

Open or create:

```text
%USERPROFILE%\.claude\CLAUDE.md
```

Append the contents of:

```text
examples/CLAUDE.md.snippet
```

Use the single-skill gate when only `tool-routing-architecture` is installed.
If Claude Code also has a separate `tool-onboarding` skill, point the setup
gate at `tool-onboarding`; that skill should delegate to this architecture
skill for A/B/C classification and layer rules.

The snippet is a routing-only baseline. Add local safety rules separately, such
as MCP server bans, model/provider/API endpoint change restrictions, and
temporary-directory policy.

## 3. Adapt Tool Names

Claude Code may expose different native tool names or MCP naming conventions
than Codex. Keep the architecture, but adapt concrete tool references in Layer 1
and Layer 2 skills to the actual tools Claude Code exposes.

Do not enable plugins, MCP servers, or provider settings just because a skill
mentions them. Enabling a tool is a separate setup action.

## 4. Validate

Run file-based checks first:

```powershell
Test-Path "$env:USERPROFILE\.claude\skills\tool-routing-architecture\SKILL.md"
Test-Path "$env:USERPROFILE\.claude\skills\tool-routing-architecture\agents\openai.yaml"
Select-String -Path "$env:USERPROFILE\.claude\skills\tool-routing-architecture\SKILL.md" -Pattern "^name: tool-routing-architecture$"
Select-String -Path "$env:USERPROFILE\.claude\CLAUDE.md" -Pattern "Tool Directory Routing"
```

Restart Claude Code or start a new session, then ask:

```text
Use $tool-routing-architecture to audit whether a new MCP server should be an
A, B, or C tool.
```

Expected behavior:

- Claude Code reads the installed skill.
- It asks for or inspects the tool details.
- It classifies the capability.
- It updates routing only when needed.
