# Install for Claude Code

Claude Code installs this repository as `tool-routing-architecture`.

## Install Architecture and Onboarding

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target claude -AddOnboardingRules
```

This installs the architecture skill and lifecycle gate without activating
ordinary runtime routing.

The Claude Code config root resolves in this order:

1. `-ClaudeConfigDir`
2. `CLAUDE_CONFIG_DIR`
3. `~/.claude`

For a non-default root:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 `
  -Target claude `
  -ClaudeConfigDir 'D:\agent-config\claude' `
  -AddOnboardingRules
```

The resulting paths are:

```text
<ClaudeConfigDir>/skills/tool-routing-architecture/SKILL.md
<ClaudeConfigDir>/CLAUDE.md
```

## Activate Runtime Routing

Runtime routing requires this live file and all skills it references:

```text
<ClaudeConfigDir>/skills/tool-index/SKILL.md
```

After building and testing that routing tree, run:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target claude -AddRuntimeRules
```

The runtime preflight occurs before any files are changed. The compatibility
switch `-AddGlobalRules` requests onboarding plus runtime rules and therefore
has the same requirement. Combining it with a new switch takes the union.

Claude Code may expose different native or MCP tool names from Codex. Keep the
architecture, but adapt Layer 1 and Layer 2 references to tools Claude Code
actually exposes.

## Backup and Rollback

Every run creates a unique snapshot under the `-BackupRoot` parent and, after a
successful install, prints the generated rollback script. A write failure
triggers automatic rollback; use the retained script manually only if automatic
rollback reports a failure or you later restore that snapshot. PowerShell 5.1
and 7 are supported on Windows; Linux and macOS require PowerShell 7.2 or later.

Keep both the backup parent and all mutation targets outside the source
repository, and keep the backup parent outside the Claude Code `skills` root.
On Windows, repository, config, and backup paths must resolve to local drives;
device-namespace, UNC, and network-backed paths are rejected. Nested
symlinks, junctions, and other reparse entries in recursively
copied source or existing skill trees are always rejected so backup and
rollback can preserve the tree. `-AllowReparsePoints` applies only to an
independently verified path or ancestor, not to entries inside a recursively
copied tree.
On Linux and macOS, symlink aliases are resolved for overlap comparisons and
existing global-file modes are preserved through install and rollback.

## Manual Recovery Install

Prefer the installer. For manual recovery, use a unique staging directory and
replace the target directory as a unit. This makes repeated copies idempotent
and prevents a nested `agents/agents` directory.

```powershell
$claudeHome = if ($env:CLAUDE_CONFIG_DIR) {
  $env:CLAUDE_CONFIG_DIR
} else {
  Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude'
}
$target = Join-Path $claudeHome 'skills/tool-routing-architecture'
$stage = Join-Path ([IO.Path]::GetTempPath()) (
  'tool-routing-architecture-' + [guid]::NewGuid().ToString('N')
)

New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -LiteralPath './SKILL.md' -Destination (Join-Path $stage 'SKILL.md')
Copy-Item -LiteralPath './agents' -Destination (Join-Path $stage 'agents') -Recurse
Copy-Item -LiteralPath './references' -Destination (Join-Path $stage 'references') -Recurse

if (Test-Path -LiteralPath $target) {
  $backup = "$target.backup-$([guid]::NewGuid().ToString('N'))"
  Copy-Item -LiteralPath $target -Destination $backup -Recurse
  Remove-Item -LiteralPath $target -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
Move-Item -LiteralPath $stage -Destination $target
```

Use the installer, not a hand-written regex, to manage global rule markers.

## Validate

```powershell
$claudeHome = if ($env:CLAUDE_CONFIG_DIR) {
  $env:CLAUDE_CONFIG_DIR
} else {
  Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude'
}
$skill = Join-Path $claudeHome 'skills/tool-routing-architecture/SKILL.md'
$global = Join-Path $claudeHome 'CLAUDE.md'

Test-Path -LiteralPath $skill
Select-String -LiteralPath $skill -Pattern '^name: tool-routing-architecture$'
Select-String -LiteralPath $global -Pattern 'Tool Onboarding Gate'
```

After runtime activation, also check for `Tool Directory Routing`. Start a new
Claude Code session and test:

```text
Use $tool-routing-architecture to audit whether a new MCP server is A, B, or C.
```

Do not enable plugins, MCP servers, authentication, or provider settings merely
because a staged skill or external README asks for them.
