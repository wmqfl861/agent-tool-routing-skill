# Install for zcode

This guide adapts the skill for zcode.

## 1. Install the Skill

One-command install:

```powershell
.\scripts\install.ps1 -Target zcode -AddGlobalRules
```

The installer backs up existing files and prints a rollback script path. Omit
`-AddGlobalRules` to install only the skill files. If existing unmarked routing
and onboarding sections are already present, the installer leaves them unchanged
instead of appending duplicates.

Typical user-level location:

```text
%USERPROFILE%\.zcode\skills\tool-routing-architecture
```

From this repository root:

```powershell
$target = "$env:USERPROFILE\.zcode\skills\tool-routing-architecture"
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -Force ".\SKILL.md" "$target\SKILL.md"
Copy-Item -Recurse -Force ".\agents" "$target\agents"
```

## 2. Add Global Routing Rules

Open or create:

```text
%USERPROFILE%\.zcode\AGENTS.md
```

Append the contents of:

```text
examples/AGENTS.md.snippet
```

Use the single-skill gate when only `tool-routing-architecture` is installed.
If zcode also has a separate `tool-onboarding` skill, point the setup gate at
`tool-onboarding`; that skill should delegate to this architecture skill for
A/B/C classification and layer rules.

If zcode has a startup or workflow skill such as `using-superpowers`, obey that
startup workflow first. Then use the routing rule when a specialized tool
family needs selection.

The snippet is a routing-only baseline. Add local safety rules separately, such
as MCP server bans, model/provider/API endpoint change restrictions, and
temporary-directory policy.

## 3. zcode-Specific Safety Notes

- Keep disabled plugins disabled unless the user explicitly asks to enable them.
- Be careful with plugin-provided MCP servers: some generated MCP tool names can
  become too long for specific model providers.
- Do not modify model, provider, base URL, API key, context, compaction, or
  reasoning settings unless the user explicitly requests that exact change.
- Prefer file-based skills for this architecture. Avoid plugin-based installs
  unless the user specifically wants a plugin.

## 4. Validate

Run file-based checks first:

```powershell
Test-Path "$env:USERPROFILE\.zcode\skills\tool-routing-architecture\SKILL.md"
Test-Path "$env:USERPROFILE\.zcode\skills\tool-routing-architecture\agents\openai.yaml"
Select-String -Path "$env:USERPROFILE\.zcode\skills\tool-routing-architecture\SKILL.md" -Pattern "^name: tool-routing-architecture$"
Select-String -Path "$env:USERPROFILE\.zcode\AGENTS.md" -Pattern "Tool Directory Routing"
```

If the zcode CLI supports these commands, run them as optional health checks:

```powershell
zcode skills list --json
zcode plugins list --json
zcode doctor --json
```

Then start a fresh zcode desktop session and ask:

```text
Use $tool-routing-architecture to classify a newly installed crawler tool and
update the routing hierarchy if needed.
```

Expected behavior:

- zcode reads the skill.
- It classifies the tool as A/B/C.
- It does not silently enable disabled plugins.
- It does not change provider/model configuration.
