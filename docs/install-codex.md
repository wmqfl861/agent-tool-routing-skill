# Install for Codex

Codex installs this repository under the compatibility name
`tool-use-architecture`. The installer converts both skill metadata and global
rule references automatically.

## Install Architecture and Onboarding

From the repository root, choose the command for your platform.

### Windows

Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -File .\scripts\install.ps1 -Target codex -AddOnboardingRules
```

PowerShell 7:

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 -Target codex -AddOnboardingRules
```

### Linux

PowerShell 7.2 or later from Bash:

```bash
pwsh -NoProfile -File ./scripts/install.ps1 -Target codex -AddOnboardingRules
```

### macOS

PowerShell 7.2 or later from zsh:

```zsh
pwsh -NoProfile -File ./scripts/install.ps1 -Target codex -AddOnboardingRules
```

This installs the architecture skill and adds only the tool lifecycle gate. It
does not activate ordinary runtime routing, so it is safe when no `tool-index`
has been built yet.

Subsequent `pwsh` commands use the same syntax with PowerShell 7 on Windows,
Linux, and macOS. On Windows PowerShell 5.1, replace `pwsh` with
`powershell.exe`.

The Codex config root resolves in this order:

1. `-CodexHome`
2. `CODEX_HOME`
3. `~/.codex`

For a non-default root on Windows:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 `
  -Target codex `
  -CodexHome 'D:\agent-config\codex' `
  -AddOnboardingRules
```

For a non-default root from Bash or zsh on Linux or macOS:

```bash
pwsh -NoProfile -File ./scripts/install.ps1 \
  -Target codex \
  -CodexHome "$HOME/.config/codex" \
  -AddOnboardingRules
```

The resulting paths are:

```text
<CodexHome>/skills/tool-use-architecture/SKILL.md
<CodexHome>/AGENTS.md
```

## Activate Runtime Routing

First create and validate the live routing tree. At minimum, Codex must have:

```text
<CodexHome>/skills/tool-index/SKILL.md
```

It must also have the Layer 1 category skills and any Layer 2 skills referenced
by that index. The repository's `examples/` files are templates and are not
installed as a complete routing tree.

Then enable the runtime rule:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target codex -AddRuntimeRules
```

The installer preflights `skills/tool-index/SKILL.md` before changing anything.
`-AddGlobalRules` is a compatibility alias for onboarding plus runtime rules,
so it performs the same preflight. Combining old and new switches takes their
union and is not an error.

## Backup and Rollback

Every run creates a unique snapshot below `-BackupRoot` and, after a successful
install, prints the snapshot and rollback script paths. `-BackupRoot` is a
parent directory, so repeated runs never merge snapshots. A write failure
triggers automatic rollback; run the retained `rollback.ps1` manually only if
automatic rollback reports a failure or you later choose to restore the
snapshot.

Keep both the backup parent and all mutation targets outside the source
repository, and keep the backup parent outside the Codex `skills` root.
On Windows, repository, config, and backup paths must resolve to local drives;
device-namespace, UNC, and network-backed paths are rejected.
Nested symlinks, junctions, and other reparse entries in recursively copied
source or existing skill trees are always rejected so backup and rollback can
preserve the tree. `-AllowReparsePoints` applies only to an independently
verified path or ancestor, not to entries inside a recursively copied tree.
On Linux and macOS, symlink aliases are resolved for overlap comparisons and
existing global-file modes are preserved through install and rollback.

Windows example:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 `
  -Target codex `
  -AddOnboardingRules `
  -BackupRoot 'D:\agent-backups'
```

Linux or macOS example from Bash or zsh:

```bash
pwsh -NoProfile -File ./scripts/install.ps1 \
  -Target codex \
  -AddOnboardingRules \
  -BackupRoot "$HOME/agent-backups"
```

Use Windows PowerShell 5.1 or PowerShell 7 on Windows. Linux and macOS require
PowerShell 7.2 or later.

## Manual Recovery Install

Prefer the installer. It handles encoding, path safety, marker validation,
Codex naming, backup isolation, and rollback.

If a manual recovery is unavoidable, build a unique staging directory and
replace the target as a unit. Do not recursively copy `agents/` into an existing
target because a second run can create `agents/agents/openai.yaml`.

```powershell
$codexHome = if ($env:CODEX_HOME) {
  $env:CODEX_HOME
} else {
  Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
}
$target = Join-Path $codexHome 'skills/tool-use-architecture'
$stage = Join-Path ([IO.Path]::GetTempPath()) (
  'tool-use-architecture-' + [guid]::NewGuid().ToString('N')
)

New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -LiteralPath './SKILL.md' -Destination (Join-Path $stage 'SKILL.md')
Copy-Item -LiteralPath './agents' -Destination (Join-Path $stage 'agents') -Recurse
Copy-Item -LiteralPath './references' -Destination (Join-Path $stage 'references') -Recurse

$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
foreach ($file in @(
  (Join-Path $stage 'SKILL.md'),
  (Join-Path $stage 'agents/openai.yaml')
)) {
  $text = [IO.File]::ReadAllText($file)
  $text = [regex]::Replace(
    $text,
    '(?m)^name:\s*tool-routing-architecture\s*$',
    'name: tool-use-architecture'
  )
  $text = $text.Replace('$tool-routing-architecture', '$tool-use-architecture')
  $text = $text.Replace('`tool-routing-architecture`', '`tool-use-architecture`')
  [IO.File]::WriteAllText($file, $text, $utf8)
}

if (Test-Path -LiteralPath $target) {
  $backup = "$target.backup-$([guid]::NewGuid().ToString('N'))"
  Copy-Item -LiteralPath $target -Destination $backup -Recurse
  Remove-Item -LiteralPath $target -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
Move-Item -LiteralPath $stage -Destination $target
```

Use the installer for global rules. Hand-editing marker blocks risks deleting
or duplicating existing instructions.

## Validate

```powershell
$codexHome = if ($env:CODEX_HOME) {
  $env:CODEX_HOME
} else {
  Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
}
$skill = Join-Path $codexHome 'skills/tool-use-architecture/SKILL.md'
$global = Join-Path $codexHome 'AGENTS.md'

Test-Path -LiteralPath $skill
Select-String -LiteralPath $skill -Pattern '^name: tool-use-architecture$'
Select-String -LiteralPath $global -Pattern 'Tool Onboarding Gate'
Select-String -LiteralPath $global -Pattern 'read `tool-use-architecture`'
```

After runtime activation, also check for `Tool Directory Routing`. Start a new
Codex session so skill metadata and global instructions are reloaded.

Test onboarding with:

```text
Use $tool-use-architecture to classify a newly installed Firecrawl MCP server.
```

The architecture may choose a route, but it must not install, authenticate,
enable, or change provider settings unless the user separately authorizes that
action.
