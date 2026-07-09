# Install for Codex

This guide installs the `tool-use-architecture` skill for Codex and adds
the global trigger rules that make the routing hierarchy usable.

## 1. Install the Skill

One-command install:

```powershell
.\scripts\install.ps1 -Target codex -AddGlobalRules
```

The installer backs up existing files and prints a rollback script path. Omit
`-AddGlobalRules` to install only the skill files. If existing unmarked routing
and onboarding sections are already present, the installer leaves them unchanged
instead of appending duplicates.

From this repository root:

```powershell
function Convert-CodexRoutingText {
  param([string]$Content)
  $updated = [regex]::Replace(
    $Content,
    '(?m)^name:\s*tool-routing-architecture\s*$',
    'name: tool-use-architecture'
  )
  $updated = $updated.Replace('$tool-routing-architecture', '$tool-use-architecture')
  $updated = $updated.Replace(
    'Use this single-skill gate when only `tool-routing-architecture` is installed.',
    'Use this single-skill gate when only `tool-use-architecture` is installed.'
  )
  $updated = $updated.Replace(
    'read the tool-routing architecture skill',
    'read the tool-use-architecture skill'
  )
  return $updated
}

function Set-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

$skills = "$env:USERPROFILE\.codex\skills"
$target = "$skills\tool-use-architecture"
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -Force ".\SKILL.md" "$target\SKILL.md"
Copy-Item -Recurse -Force ".\agents" "$target\agents"

Convert-CodexRoutingText (Get-Content "$target\SKILL.md" -Raw) |
  ForEach-Object { Set-Utf8NoBom "$target\SKILL.md" $_ }

Convert-CodexRoutingText (Get-Content "$target\agents\openai.yaml" -Raw) |
  ForEach-Object { Set-Utf8NoBom "$target\agents\openai.yaml" $_ }
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

For manual Codex installs, transform the snippet and write it with markers so
re-running the command updates the managed block instead of appending
duplicates:

```powershell
function Convert-CodexRoutingText {
  param([string]$Content)
  $updated = [regex]::Replace(
    $Content,
    '(?m)^name:\s*tool-routing-architecture\s*$',
    'name: tool-use-architecture'
  )
  $updated = $updated.Replace('$tool-routing-architecture', '$tool-use-architecture')
  $updated = $updated.Replace(
    'Use this single-skill gate when only `tool-routing-architecture` is installed.',
    'Use this single-skill gate when only `tool-use-architecture` is installed.'
  )
  $updated = $updated.Replace(
    'read the tool-routing architecture skill',
    'read the tool-use-architecture skill'
  )
  return $updated
}

function Set-Utf8NoBom {
  param([string]$Path, [string]$Content)
  $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
  [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

$global = "$env:USERPROFILE\.codex\AGENTS.md"
$start = '<!-- agent-tool-routing-skill:start -->'
$end = '<!-- agent-tool-routing-skill:end -->'
$snippet = Convert-CodexRoutingText (Get-Content ".\examples\AGENTS.md.snippet" -Raw)
$block = "$start`r`n$($snippet.Trim())`r`n$end"

$existing = ''
if (Test-Path $global) {
  $existing = Get-Content $global -Raw
}

$pattern = '(?s)<!-- agent-tool-routing-skill:start -->.*?<!-- agent-tool-routing-skill:end -->'
$match = [regex]::Match($existing, $pattern)
if ($match.Success) {
  $updated = $existing.Substring(0, $match.Index) +
    $block +
    $existing.Substring($match.Index + $match.Length)
} elseif (
  $existing -match '(?m)^##\s+Tool Directory Routing\b' -and
  $existing -match '(?m)^##\s+Tool Onboarding Gate\b'
) {
  Write-Warning 'Existing unmarked routing rules found; leaving them unchanged.'
  $updated = $null
} elseif ([string]::IsNullOrWhiteSpace($existing)) {
  $updated = $block + "`r`n"
} else {
  $updated = $existing.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
}

if ($null -ne $updated) {
  Set-Utf8NoBom $global $updated
}
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
