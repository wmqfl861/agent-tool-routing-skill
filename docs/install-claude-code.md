# Install for Claude Code

Claude Code installs this repository as `tool-routing-architecture`.

## Install, Onboard, and Initialize Routing

Choose the one command for your platform. It is pinned to `v0.2.0`, verifies
the bootstrap and every payload file before execution, and can run from any
directory without Git.

The Windows command targets Windows 10 1803+, Windows Server 2019+, or another
supported Windows release that provides `curl.exe`.

### Windows

```powershell
$u='https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.0/scripts/install-remote.ps1';$h='dbf60fc240741068788ea0e96136af53fd810d8c0e081ac378899e0ff95f64d6';$p=Join-Path ([IO.Path]::GetTempPath()) ('agent-tool-routing-'+[guid]::NewGuid().ToString('N')+'.ps1');try{& curl.exe -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL $u -o $p;if($LASTEXITCODE -ne 0){throw 'Installer download failed.'};if((Get-Item -LiteralPath $p).Length -gt 131072){throw 'Installer exceeds the maximum expected size.'};if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $h){throw 'Installer SHA-256 verification failed.'};& ([scriptblock]::Create([IO.File]::ReadAllText($p))) -Target claude -InitializeRouting}finally{Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue}
```

### Linux

```bash
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.0/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'dbf60fc240741068788ea0e96136af53fd810d8c0e081ac378899e0ff95f64d6' "$p" | sha256sum -c - >/dev/null;pwsh -NoProfile -File "$p" -Target claude -InitializeRouting)
```

### macOS

```zsh
(set -eu;umask 077;d="$(mktemp -d)";p="$d/install.ps1";trap 'rm -f "$p";rmdir "$d"' EXIT;curl -q --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 30 --max-time 60 --limit-rate 128K --max-filesize 131072 -fsSL 'https://raw.githubusercontent.com/wmqfl861/agent-tool-routing-skill/v0.2.0/scripts/install-remote.ps1' -o "$p";printf '%s  %s\n' 'dbf60fc240741068788ea0e96136af53fd810d8c0e081ac378899e0ff95f64d6' "$p" | shasum -a 256 -c - >/dev/null;pwsh -NoProfile -File "$p" -Target claude -InitializeRouting)
```

After the verified core install, `-InitializeRouting` transactionally records a
durable one-shot request or preserves an existing resumable request. It does not
launch another Claude Code process. A Claude Code session that invoked the
installer must continue the pending job before ordinary work; after a direct
terminal install, the next fresh Claude Code turn consumes it. A running
session is not guaranteed to hot-reload new skills or global instructions or
complete indexing in the installation turn. The Claude Code session processing
the job emits phase progress.

The job inventories capabilities registered with or discoverable by Claude
Code, not every executable on `PATH`. It routes resolved A and B capabilities
by intent and records C primitives as inventory-only. Missing A guides are
checked first against local or bundled Skills, then against a pinned canonical
official source staged outside auto-discovery and reviewed before activation. A
minimal guide may be authored from sufficient reviewed official documentation.
If evidence is insufficient, the job remains resumable and the generated
runtime tree stays inactive.

## Configuration Root

The remaining examples require a reviewed local checkout. `pwsh` uses the same
syntax with PowerShell 7 on Windows, Linux, and macOS. On Windows PowerShell
5.1, replace `pwsh` with `powershell.exe`.

The Claude Code config root resolves in this order:

1. `-ClaudeConfigDir`
2. `CLAUDE_CONFIG_DIR`
3. `~/.claude`

For a non-default root on Windows:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 `
  -Target claude `
  -ClaudeConfigDir 'D:\agent-config\claude' `
  -AddOnboardingRules
```

For a non-default root from Bash or zsh on Linux or macOS:

```bash
pwsh -NoProfile -File ./scripts/install.ps1 \
  -Target claude \
  -ClaudeConfigDir "$HOME/.config/claude" \
  -AddOnboardingRules
```

The resulting paths are:

```text
<ClaudeConfigDir>/skills/tool-routing-architecture/SKILL.md
<ClaudeConfigDir>/CLAUDE.md
```

## Activate Runtime Routing

The initial-index job activates runtime routing only after its complete tree
passes validation. For an architecture-only installation or a manually built
tree, runtime routing requires this live file and all skills it references:

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

## Recovery and Reinstallation

Use the verified one-command installer or a reviewed local checkout instead of
reconstructing the installed directory manually:

```powershell
pwsh -NoProfile -File ./scripts/install.ps1 -Target claude -InitializeRouting
```

The transactional installer includes `VERSION`, `SKILL.md`, `agents/`, all
references, and the complete `examples/` template set. It preserves a resumable
initial-index request, manages global-rule markers, creates an isolated backup,
and prints a rollback path. A hand-written partial copy can omit required
templates or produce a nested, incomplete installation.

To restore a retained snapshot instead, run its generated `rollback.ps1`.

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
