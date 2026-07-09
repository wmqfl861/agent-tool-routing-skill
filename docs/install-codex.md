# Install for Codex

This guide installs the `tool-routing-architecture` skill for Codex and adds
the global trigger rules that make the routing hierarchy usable.

## 1. Install the Skill

From this repository root:

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

## 2. Add Global Routing Rules

Open or create:

```text
%USERPROFILE%\.codex\AGENTS.md
```

Append the contents of:

```text
examples/AGENTS.md.snippet
```

Keep the snippet short. Do not copy all of `SKILL.md` into `AGENTS.md`.

The snippet is a routing-only baseline. Add local safety rules separately, such
as MCP server bans, model/provider/API endpoint change restrictions, and
temporary-directory policy.

## 3. Install or Create Routing Skills

At minimum, a working hierarchy needs:

- `tool-index`
- one or more Layer 1 category skills
- Layer 2 tool skills for every A-class tool

Use the examples in `examples/` as starting points. Replace placeholder tool
names with your actual installed tools.

## 4. Validate

Run:

```powershell
Test-Path "$env:USERPROFILE\.codex\skills\tool-use-architecture\SKILL.md"
Test-Path "$env:USERPROFILE\.codex\skills\tool-use-architecture\agents\openai.yaml"
Select-String -Path "$env:USERPROFILE\.codex\skills\tool-use-architecture\SKILL.md" -Pattern "^name: tool-use-architecture$"
Select-String -Path "$env:USERPROFILE\.codex\AGENTS.md" -Pattern "Tool Directory Routing"
```

Then restart Codex or start a fresh Codex session so the new skill metadata is
loaded.

## 5. Test

Ask:

```text
Use $tool-use-architecture to classify a newly installed Firecrawl MCP
server and decide where it belongs in the hierarchy.
```

Expected behavior:

- Codex reads this skill.
- Codex classifies the capability as A/B/C.
- Codex updates or proposes the correct Layer 1/Layer 2 routing.
- Codex does not change model/provider/API endpoint settings unless explicitly
  asked.
