# Install for zcode

This guide adapts the skill for zcode.

## 1. Install the Skill

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

## 3. zcode-Specific Safety Notes

- Keep disabled plugins disabled unless the user explicitly asks to enable them.
- Be careful with plugin-provided MCP servers: some generated MCP tool names can
  become too long for specific model providers.
- Do not modify model, provider, base URL, API key, context, compaction, or
  reasoning settings unless the user explicitly requests that exact change.
- Prefer file-based skills for this architecture. Avoid plugin-based installs
  unless the user specifically wants a plugin.

## 4. Validate

If the zcode CLI is available:

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
