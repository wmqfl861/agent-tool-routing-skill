# Install for Codex

Codex installs this repository under the compatibility name
`tool-use-architecture`. The installer converts both skill metadata and global
rule references automatically.

## Install for One Agent

Choose the one command for your platform. It is pinned to `v0.2.3`, verifies
the bootstrap and every payload file before execution, and installs only the
Codex architecture skill. It does not change Claude Code or zcode, add global
rules, or queue routing initialization.

The Windows command targets Windows 10 1803+, Windows Server 2019+, or another
supported Windows release that provides `curl.exe`.

### Windows

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.3/scripts/install-remote.ps1';$h='4ffc0ae2428096d9eeffa1a8293a1dcd1a1c3bccb14a513850634d5d2c42ce8e';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target codex}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

### Linux

```bash
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.3/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '4ffc0ae2428096d9eeffa1a8293a1dcd1a1c3bccb14a513850634d5d2c42ce8e' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target codex)
```

### macOS

```zsh
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.3/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' '4ffc0ae2428096d9eeffa1a8293a1dcd1a1c3bccb14a513850634d5d2c42ce8e' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target codex)
```

`-Target` is required, and only explicit `-Target all` may change multiple
Agents. Add `-AddOnboardingRules` only when a Codex global lifecycle gate is
intended. Add `-InitializeRouting` only to queue a durable one-shot request.
That request is bound to the recorded Codex configuration root and remains
inert until the current user explicitly asks a fresh Codex session to initialize
or resume routing. It must not interrupt another task.

The consuming Agent inventories capabilities registered with or discoverable by
Codex, not every executable on `PATH`. It routes resolved A and B capabilities
through active intent routes. Every C capability remains in the managed
inventory with an exclusion rationale and bypasses active intent routing.
Missing A guides are checked first against local or bundled Skills, then against
a pinned canonical official source staged outside auto-discovery and reviewed
before activation. A minimal guide may be authored from sufficient reviewed
official documentation. If evidence is insufficient, the job remains resumable
and the generated runtime tree stays inactive.

## Configuration Root

The remaining examples require a reviewed local checkout. `pwsh` uses the same
syntax with PowerShell 7 on Windows, Linux, and macOS. On Windows PowerShell
5.1, replace `pwsh` with `powershell.exe`.

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

The initial-index job activates runtime routing only after its complete tree
passes validation. For an architecture-only installation or a manually built
tree, first create and validate the live routing tree. At minimum, Codex must
have:

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
`-AddGlobalRules` is no longer accepted because one switch must not enable two
independent global rule sets. Use `-AddOnboardingRules` and/or
`-AddRuntimeRules` explicitly.

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
source or existing skill trees are always rejected so copy and rollback never
traverse outside the reviewed tree. `-AllowReparsePoints` applies only to an
independently verified path or ancestor, not to entries inside a recursively
copied tree.
On Linux and macOS, symlink aliases are resolved for overlap comparisons and
existing global-file modes are preserved through install and rollback.

The installer holds one cross-process lock per Codex config root through
recovery and automatic rollback. Skill replacement persists a journal and the
verified prepared-tree digest before displacing the live directory; a later run
restores, finalizes, or fails closed on an ambiguous or modified retained
transaction.
The hidden container remains on the `skills` filesystem for same-filesystem
moves, has no direct `SKILL.md`, and must be excluded by any non-standard
recursive Skill scanner.

This protects the Skill-directory swap, not the entire multi-file install as a
power-loss atomic transaction. Rerun the installer after a process or host
interruption. Snapshot rollback restores ordinary contents but does not promise
to preserve ACLs, extended attributes, hardlink relationships, or directory
identity. A manually launched rollback script does not acquire the installer
lock and must not run concurrently with installation.

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

## Recovery and Reinstallation

Use the verified one-command installer or a reviewed local checkout instead of
reconstructing the installed directory manually:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target codex
```

The transactional installer includes `VERSION`, `SKILL.md`, `agents/`, all
references, and the complete `examples/` template set. It also performs the
required Codex compatibility conversion, preserves a resumable initial-index
request, manages global-rule markers, creates an isolated backup, and prints a
rollback path. A hand-written partial copy can omit required templates or leave
generic `tool-routing-architecture` names in the Codex installation.

To restore a retained snapshot instead, run its generated `rollback.ps1`.

## Validate

```powershell
$codexHome = if ($env:CODEX_HOME) {
  $env:CODEX_HOME
} else {
  Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
}
$skill = Join-Path $codexHome 'skills/tool-use-architecture/SKILL.md'
Test-Path -LiteralPath $skill
Select-String -LiteralPath $skill -Pattern '^name: tool-use-architecture$'
```

Only after installing with `-AddOnboardingRules`, validate the optional global
gate:

```powershell
$global = Join-Path $codexHome 'AGENTS.md'
Test-Path -LiteralPath $global
Select-String -LiteralPath $global -Pattern 'Tool Onboarding Gate'
Select-String -LiteralPath $global -Pattern 'delegates a direct current-user request'
```

After runtime activation, also check for `Tool Directory Routing`. Start a new
Codex session so skill metadata and global instructions are reloaded.

Test onboarding with:

```text
Use $tool-use-architecture to audit how the installed Firecrawl MCP server
should be represented in this Agent's routing architecture.
```

The architecture may choose a route, but it must not install, authenticate,
enable, or change provider settings unless the user separately authorizes that
action.
