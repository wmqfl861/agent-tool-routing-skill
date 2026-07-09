[CmdletBinding()]
param(
    [ValidateSet('all', 'codex', 'claude', 'zcode')]
    [string]$Target = 'all',

    [switch]$AddGlobalRules,

    [string]$BackupRoot,

    [string]$UserProfile = [Environment]::GetFolderPath('UserProfile'),

    [switch]$AllowCustomProfile
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SkillSource = Join-Path $RepoRoot 'SKILL.md'
$AgentsSource = Join-Path $RepoRoot 'agents'
$ExamplesSource = Join-Path $RepoRoot 'examples'

if (-not (Test-Path -LiteralPath $SkillSource)) {
    throw "Missing SKILL.md at repository root: $SkillSource"
}

if (-not (Test-Path -LiteralPath $AgentsSource)) {
    throw "Missing agents directory at repository root: $AgentsSource"
}

function Normalize-RootPath {
    param([string]$Path)
    return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\', '/')
}

$OsUserProfileFull = Normalize-RootPath -Path ([Environment]::GetFolderPath('UserProfile'))
$UserProfileFull = Normalize-RootPath -Path $UserProfile

if (-not [string]::Equals($UserProfileFull, $OsUserProfileFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    if (-not $AllowCustomProfile) {
        throw "Refusing custom -UserProfile '$UserProfileFull' without -AllowCustomProfile. This protects the installer from writing outside the OS user profile."
    }

    Write-Warning "Using custom profile root for installation and safety checks: $UserProfileFull"
}

if (-not $BackupRoot) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $BackupRoot = Join-Path $UserProfile "agent-tool-routing-backups\install-$stamp"
    $suffix = 1
    while (Test-Path -LiteralPath $BackupRoot) {
        $BackupRoot = Join-Path $UserProfile "agent-tool-routing-backups\install-$stamp-$suffix"
        $suffix++
    }
}

New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

$RollbackCommands = New-Object System.Collections.Generic.List[string]
$Results = New-Object System.Collections.Generic.List[object]

function Quote-PowerShellLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Assert-UnderUserProfile {
    param([string]$Path)
    $full = Normalize-RootPath -Path $Path
    $isProfileRoot = [string]::Equals($full, $UserProfileFull, [System.StringComparison]::OrdinalIgnoreCase)
    $isUnderProfileRoot = $full.StartsWith($UserProfileFull + '\', [System.StringComparison]::OrdinalIgnoreCase)
    if (-not ($isProfileRoot -or $isUnderProfileRoot)) {
        throw "Refusing to modify path outside user profile: $full"
    }
}

function Backup-Path {
    param(
        [string]$Path,
        [string]$Label
    )

    Assert-UnderUserProfile -Path $Path

    $backupPath = Join-Path $BackupRoot $Label
    if (Test-Path -LiteralPath $Path) {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Recurse -Force
        $RollbackCommands.Add("if (Test-Path -LiteralPath $(Quote-PowerShellLiteral $Path)) { Remove-Item -LiteralPath $(Quote-PowerShellLiteral $Path) -Recurse -Force }")
        $RollbackCommands.Add("Copy-Item -LiteralPath $(Quote-PowerShellLiteral $backupPath) -Destination $(Quote-PowerShellLiteral $Path) -Recurse -Force")
        return $backupPath
    }

    $RollbackCommands.Add("if (Test-Path -LiteralPath $(Quote-PowerShellLiteral $Path)) { Remove-Item -LiteralPath $(Quote-PowerShellLiteral $Path) -Recurse -Force }")
    return $null
}

function Set-TextFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Convert-CodexCompatibilityText {
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

function Get-AgentConfig {
    param([string]$Agent)

    switch ($Agent) {
        'codex' {
            return [pscustomobject]@{
                Name = 'codex'
                SkillName = 'tool-use-architecture'
                SkillDir = Join-Path $UserProfile '.codex\skills\tool-use-architecture'
                GlobalFile = Join-Path $UserProfile '.codex\AGENTS.md'
                Snippet = Join-Path $ExamplesSource 'AGENTS.md.snippet'
            }
        }
        'claude' {
            return [pscustomobject]@{
                Name = 'claude'
                SkillName = 'tool-routing-architecture'
                SkillDir = Join-Path $UserProfile '.claude\skills\tool-routing-architecture'
                GlobalFile = Join-Path $UserProfile '.claude\CLAUDE.md'
                Snippet = Join-Path $ExamplesSource 'CLAUDE.md.snippet'
            }
        }
        'zcode' {
            return [pscustomobject]@{
                Name = 'zcode'
                SkillName = 'tool-routing-architecture'
                SkillDir = Join-Path $UserProfile '.zcode\skills\tool-routing-architecture'
                GlobalFile = Join-Path $UserProfile '.zcode\AGENTS.md'
                Snippet = Join-Path $ExamplesSource 'AGENTS.md.snippet'
            }
        }
        default {
            throw "Unknown agent target: $Agent"
        }
    }
}

function Convert-SkillForAgent {
    param(
        [string]$Agent,
        [string]$SkillDir
    )

    if ($Agent -ne 'codex') {
        return
    }

    $skillPath = Join-Path $SkillDir 'SKILL.md'
    $metadataPath = Join-Path $SkillDir 'agents\openai.yaml'

    $skill = Get-Content -LiteralPath $skillPath -Raw
    $skill = Convert-CodexCompatibilityText -Content $skill
    Set-TextFile -Path $skillPath -Content $skill

    if (Test-Path -LiteralPath $metadataPath) {
        $metadata = Get-Content -LiteralPath $metadataPath -Raw
        $metadata = Convert-CodexCompatibilityText -Content $metadata
        Set-TextFile -Path $metadataPath -Content $metadata
    }
}

function Install-AgentSkill {
    param([object]$Config)

    Backup-Path -Path $Config.SkillDir -Label "$($Config.Name)-skill" | Out-Null

    if (Test-Path -LiteralPath $Config.SkillDir) {
        Remove-Item -LiteralPath $Config.SkillDir -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $Config.SkillDir | Out-Null
    Copy-Item -LiteralPath $SkillSource -Destination (Join-Path $Config.SkillDir 'SKILL.md') -Force
    Copy-Item -LiteralPath $AgentsSource -Destination (Join-Path $Config.SkillDir 'agents') -Recurse -Force

    Convert-SkillForAgent -Agent $Config.Name -SkillDir $Config.SkillDir

    $skillPath = Join-Path $Config.SkillDir 'SKILL.md'
    $nameMatch = Select-String -LiteralPath $skillPath -Pattern '^name:\s*(.+)$' | Select-Object -First 1
    if (-not $nameMatch) {
        throw "No 'name:' field found in installed SKILL.md for $($Config.Name): $skillPath"
    }

    $installedName = $nameMatch.Matches.Groups[1].Value.Trim()
    if ($installedName -ne $Config.SkillName) {
        throw "Installed skill name mismatch for $($Config.Name): expected $($Config.SkillName), got $installedName"
    }
}

function Get-SnippetForAgent {
    param([object]$Config)

    if (-not (Test-Path -LiteralPath $Config.Snippet)) {
        throw "Missing global instruction snippet: $($Config.Snippet)"
    }

    $snippet = Get-Content -LiteralPath $Config.Snippet -Raw

    if ($Config.Name -eq 'codex') {
        $snippet = Convert-CodexCompatibilityText -Content $snippet
    }

    return $snippet.Trim()
}

function Test-ExistingUnmanagedGlobalRules {
    param([string]$Content)

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $false
    }

    $hasDirectory = $Content -match '(?m)^##\s+Tool Directory Routing\b'
    $hasOnboarding = $Content -match '(?m)^##\s+Tool Onboarding Gate\b'

    return ($hasDirectory -and $hasOnboarding)
}

function Install-GlobalRules {
    param([object]$Config)

    Backup-Path -Path $Config.GlobalFile -Label "$($Config.Name)-global" | Out-Null

    $start = '<!-- agent-tool-routing-skill:start -->'
    $end = '<!-- agent-tool-routing-skill:end -->'
    $snippet = Get-SnippetForAgent -Config $Config
    $block = "$start`r`n$snippet`r`n$end"

    $existing = ''
    if (Test-Path -LiteralPath $Config.GlobalFile) {
        $existing = Get-Content -LiteralPath $Config.GlobalFile -Raw
    }

    $pattern = '(?s)<!-- agent-tool-routing-skill:start -->.*?<!-- agent-tool-routing-skill:end -->'
    $match = [regex]::Match($existing, $pattern)
    if ($match.Success) {
        $updated = $existing.Substring(0, $match.Index) +
            $block +
            $existing.Substring($match.Index + $match.Length)
    } elseif ([string]::IsNullOrWhiteSpace($existing)) {
        $updated = $block + "`r`n"
    } elseif (Test-ExistingUnmanagedGlobalRules -Content $existing) {
        Write-Warning "Existing unmarked tool-routing rules found in $($Config.GlobalFile); leaving them unchanged to avoid duplicate global instructions."
        return 'existing unmarked; left unchanged'
    } else {
        $updated = $existing.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
    }

    Set-TextFile -Path $Config.GlobalFile -Content $updated
    return 'installed or updated'
}

function Install-Agent {
    param([string]$Agent)

    $config = Get-AgentConfig -Agent $Agent
    Install-AgentSkill -Config $config

    $globalStatus = 'not requested'
    if ($AddGlobalRules) {
        $globalStatus = Install-GlobalRules -Config $config
    }

    $Results.Add([pscustomobject]@{
        Agent = $config.Name
        Skill = $config.SkillName
        SkillDir = $config.SkillDir
        GlobalFile = $config.GlobalFile
        GlobalRules = $globalStatus
    })
}

$rollbackPath = Join-Path $BackupRoot 'rollback.ps1'
$rollbackHeader = @(
    '$ErrorActionPreference = ''Stop'''
    '# Generated rollback for agent-tool-routing-skill installation.'
)

function Write-RollbackScript {
    Set-TextFile -Path $rollbackPath -Content (($rollbackHeader + $RollbackCommands.ToArray() + "Write-Output 'Rollback complete.'") -join "`r`n")
}

$targets = if ($Target -eq 'all') { @('codex', 'claude', 'zcode') } else { @($Target) }
$installCompleted = $false

try {
    foreach ($agent in $targets) {
        Install-Agent -Agent $agent
    }

    $installCompleted = $true
} finally {
    Write-RollbackScript
    if (-not $installCompleted) {
        Write-Warning "Installation did not complete. Backup: $BackupRoot"
        Write-Warning "Rollback: $rollbackPath"
    }
}

Write-Output 'Installed agent tool-routing skill.'
Write-Output "Backup: $BackupRoot"
Write-Output "Rollback: $rollbackPath"
$Results | Format-Table -AutoSize
