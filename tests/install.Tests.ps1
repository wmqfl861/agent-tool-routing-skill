BeforeAll {
$here = $PSScriptRoot
$repoRoot = Split-Path -Parent $here
$script:CreatedTestRoots = New-Object System.Collections.Generic.List[string]
$script:IsWindowsTest = [IO.Path]::DirectorySeparatorChar -eq [char]'\'
$script:IsMacOSTest = (-not $script:IsWindowsTest) -and
    [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::OSX
    )
$script:IsLinuxTest = (-not $script:IsWindowsTest) -and (-not $script:IsMacOSTest)
$script:TestPlatformName = if ($script:IsWindowsTest) {
    'Windows'
} elseif ($script:IsMacOSTest) {
    'macOS'
} else {
    'Linux'
}

function Join-TestPath {
    param(
        [string]$Root,
        [string[]]$Segments
    )

    $path = $Root
    foreach ($segment in $Segments) {
        $path = Join-Path $path $segment
    }
    return $path
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message = 'Expected condition to be true.'
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-False {
    param(
        [bool]$Condition,
        [string]$Message = 'Expected condition to be false.'
    )

    if ($Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [string]$Message = 'Values are not equal.'
    )

    if (($Actual -is [string]) -and ($Expected -is [string])) {
        $equal = [string]::Equals($Actual, $Expected, [StringComparison]::Ordinal)
    } else {
        $equal = $Actual -eq $Expected
    }
    if (-not $equal) {
        throw "$Message Actual: '$Actual'. Expected: '$Expected'."
    }
}

function Assert-BytePrefix {
    param(
        [byte[]]$Bytes,
        [byte[]]$Prefix,
        [string]$Message = 'Byte prefix does not match.'
    )

    if ($Bytes.Length -lt $Prefix.Length) {
        throw "$Message File has $($Bytes.Length) bytes; prefix requires $($Prefix.Length)."
    }
    for ($index = 0; $index -lt $Prefix.Length; $index++) {
        if ($Bytes[$index] -ne $Prefix[$index]) {
            throw "$Message Mismatch at index $index."
        }
    }
}

function Remove-TestDirectory {
    param([string]$Path)

    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        if (-not (Test-Path -LiteralPath $Path)) {
            return
        }
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return
        } catch {
            if ($attempt -eq 4) {
                throw
            }
            Start-Sleep -Milliseconds (40 * ($attempt + 1))
        }
    }
}

function Get-PhysicalTestPath {
    param([string]$Path)

    if ($script:IsWindowsTest) {
        return [IO.Path]::GetFullPath($Path)
    }

    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    $current = $root
    $relative = $full.Substring($root.Length)
    foreach ($segment in @($relative.Split(
        [char[]]@([IO.Path]::DirectorySeparatorChar),
        [StringSplitOptions]::RemoveEmptyEntries
    ))) {
        $next = Join-Path $current $segment
        $item = Get-Item -LiteralPath $next -Force
        $isLink = (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
            (-not [string]::IsNullOrEmpty([string]$item.LinkType))
        if ($isLink) {
            $item = $item.ResolveLinkTarget($true)
        }
        $current = $item.FullName
    }
    return [IO.Path]::GetFullPath($current)
}

$installer = Join-TestPath $repoRoot @('scripts', 'install.ps1')
$projectVersion = [IO.File]::ReadAllText((Join-Path $repoRoot 'VERSION')).Trim()

function New-InstallLayout {
    param([string]$Name = ([guid]::NewGuid().ToString('N')))

    $physicalTestDrive = Get-PhysicalTestPath -Path $TestDrive
    $root = Join-Path $physicalTestDrive $Name
    [void]$script:CreatedTestRoots.Add($root)
    $profileRoot = Join-Path $root 'profile'
    $config = Join-Path $root 'config'
    $backup = Join-Path $root 'backups'
    New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null
    return [pscustomobject]@{
        Root = $root
        Profile = $profileRoot
        Config = $config
        Backup = $backup
        Global = Join-Path $config 'AGENTS.md'
        Skill = Join-TestPath $config @('skills', 'tool-use-architecture')
    }
}

function Write-EncodedText {
    param(
        [string]$Path,
        [string]$Text,
        [System.Text.Encoding]$Encoding,
        [bool]$EmitBom
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $body = $Encoding.GetBytes($Text)
    $preamble = if ($EmitBom) { $Encoding.GetPreamble() } else { New-Object byte[] 0 }
    $bytes = New-Object byte[] ($preamble.Length + $body.Length)
    if ($preamble.Length -gt 0) {
        [Array]::Copy($preamble, 0, $bytes, 0, $preamble.Length)
    }
    [Array]::Copy($body, 0, $bytes, $preamble.Length, $body.Length)
    [IO.File]::WriteAllBytes($Path, $bytes)
}

function Get-SnapshotDirectories {
    param([string]$BackupParent)

    if (-not (Test-Path -LiteralPath $BackupParent)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $BackupParent -Directory | Where-Object { $_.Name -like 'install-*' })
}

function New-ToolIndexDependency {
    param([string]$ConfigRoot)

    $path = Join-TestPath $ConfigRoot @('skills', 'tool-index', 'SKILL.md')
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, "---`nname: tool-index`n---`n")
    return $path
}
}

Describe 'scripts/install.ps1' {
    BeforeEach {
        $script:CreatedTestRoots.Clear()
    }

    AfterEach {
        foreach ($root in @($script:CreatedTestRoots.ToArray())) {
            Remove-TestDirectory -Path $root
        }
        $script:CreatedTestRoots.Clear()
    }

    It 'runs on the CI platform declared by the workflow' {
        if ([string]::IsNullOrWhiteSpace($env:EXPECTED_TEST_OS)) {
            return
        }

        Assert-Equal $script:TestPlatformName $env:EXPECTED_TEST_OS
    }

    It 'installs clean onboarding rules without requiring tool-index' {
        $layout = New-InstallLayout 'clean-onboarding'

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

        Assert-True (Test-Path -LiteralPath $layout.Skill)
        Assert-True (Test-Path -LiteralPath $layout.Global)
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $layout.Skill 'VERSION')).Trim()) $projectVersion
        $global = [IO.File]::ReadAllText($layout.Global)
        Assert-True ($global.Contains('<!-- agent-tool-routing-skill:onboarding:start -->'))
        Assert-False ($global.Contains('<!-- agent-tool-routing-skill:runtime:start -->'))
        Assert-True ($global.Contains('`tool-use-architecture`'))

        $bytes = [IO.File]::ReadAllBytes($layout.Global)
        Assert-False (($bytes.Length -ge 3) -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

        foreach ($reference in @('lifecycle.md', 'authoring.md', 'runtime-adapters.md', 'route-tests.md')) {
            Assert-True (Test-Path -LiteralPath (Join-TestPath $layout.Skill @('references', $reference)))
        }

        $installedFiles = @(
            (Join-Path $layout.Skill 'SKILL.md'),
            (Join-TestPath $layout.Skill @('agents', 'openai.yaml')),
            $layout.Global
        )
        $genericMatches = @(Select-String -Path $installedFiles -Pattern 'tool-routing-architecture' -ErrorAction SilentlyContinue)
        Assert-Equal $genericMatches.Count 0
    }

    It 'preflights a missing runtime dependency before any target or backup change' {
        $layout = New-InstallLayout 'runtime-preflight'
        New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
        $sentinel = Join-Path $layout.Skill 'sentinel.txt'
        [IO.File]::WriteAllText($sentinel, 'keep-skill')
        New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null
        [IO.File]::WriteAllText($layout.Global, 'keep-global')

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup -AddRuntimeRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('requires tool-index'))
        Assert-Equal ([IO.File]::ReadAllText($sentinel)) 'keep-skill'
        Assert-Equal ([IO.File]::ReadAllText($layout.Global)) 'keep-global'
        Assert-False (Test-Path -LiteralPath $layout.Backup)
    }

    It 'treats AddGlobalRules as onboarding plus runtime after dependency preflight' {
        $layout = New-InstallLayout 'legacy-switch'
        $null = New-ToolIndexDependency $layout.Config

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddGlobalRules

        $global = [IO.File]::ReadAllText($layout.Global)
        Assert-True ($global.Contains('<!-- agent-tool-routing-skill:runtime:start -->'))
        Assert-True ($global.Contains('<!-- agent-tool-routing-skill:onboarding:start -->'))
        Assert-False ($global.Contains('<!-- agent-tool-routing-skill:start -->'))
    }

    It 'migrates a legacy managed block without losing surrounding user text' {
        $layout = New-InstallLayout 'legacy-marker-migration'
        $null = New-ToolIndexDependency $layout.Config
        New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null

        $snippetPath = Join-TestPath $repoRoot @('examples', 'AGENTS.md.snippet')
        $legacySnippet = [IO.File]::ReadAllText($snippetPath)
        $legacySnippet = $legacySnippet.Replace('`tool-routing-architecture`', '`tool-use-architecture`')
        $legacySnippet = $legacySnippet.Replace(
            'This installation uses `auto-discovery`:',
            "LEGACY_RUNTIME_SENTINEL`n`nThis installation uses `auto-discovery`:"
        )
        $legacyText = @(
            'USER_TEXT_BEFORE',
            '<!-- agent-tool-routing-skill:start -->',
            $legacySnippet.Trim(),
            '<!-- agent-tool-routing-skill:end -->',
            'USER_TEXT_AFTER',
            ''
        ) -join "`n"
        [IO.File]::WriteAllText($layout.Global, $legacyText)

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

        $updated = [IO.File]::ReadAllText($layout.Global)
        Assert-False ($updated.Contains('<!-- agent-tool-routing-skill:start -->'))
        Assert-True ($updated.Contains('<!-- agent-tool-routing-skill:runtime:start -->'))
        Assert-True ($updated.Contains('<!-- agent-tool-routing-skill:onboarding:start -->'))
        Assert-True ($updated.Contains('LEGACY_RUNTIME_SENTINEL'))
        Assert-True ($updated.Contains('USER_TEXT_BEFORE'))
        Assert-True ($updated.Contains('USER_TEXT_AFTER'))
        Assert-False ($updated.Contains('`tool-routing-architecture`'))
        Assert-True ($updated.Contains('`tool-use-architecture`'))
    }

    It 'preserves Unicode and UTF-8 without BOM under Windows PowerShell 5.1' {
        $layout = New-InstallLayout 'unicode-no-bom'
        $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
        $unicodeRule = -join ([char[]]@(
            0x7528, 0x6237, 0x89C4, 0x5219, 0xFF1A, 0x4E0D, 0x8981,
            0x4FEE, 0x6539, 0x6A21, 0x578B, 0x914D, 0x7F6E, 0x3002
        ))
        $original = $unicodeRule + "`r`n"
        Write-EncodedText -Path $layout.Global -Text $original -Encoding $utf8NoBom -EmitBom $false

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

        $bytes = [IO.File]::ReadAllBytes($layout.Global)
        Assert-False (($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF))
        $updated = $utf8NoBom.GetString($bytes)
        Assert-True ($updated.Contains($unicodeRule))
        Assert-True ($updated.Contains('## Tool Onboarding Gate'))
    }

    It 'preserves UTF-8 BOM and UTF-16 encodings when updating existing Markdown' {
        $unicodePrefix = -join ([char[]]@(0x4E2D, 0x6587, 0x4FDD, 0x7559))
        $specifications = @(
            [pscustomobject]@{
                Name = 'utf8-bom'
                Encoding = (New-Object System.Text.UTF8Encoding -ArgumentList $true, $true)
                Preamble = [byte[]](0xEF, 0xBB, 0xBF)
            },
            [pscustomobject]@{
                Name = 'utf16-le'
                Encoding = [System.Text.Encoding]::Unicode
                Preamble = [byte[]](0xFF, 0xFE)
            },
            [pscustomobject]@{
                Name = 'utf16-be'
                Encoding = [System.Text.Encoding]::BigEndianUnicode
                Preamble = [byte[]](0xFE, 0xFF)
            }
        )

        foreach ($specification in $specifications) {
            $layout = New-InstallLayout ("encoding-" + $specification.Name)
            Write-EncodedText -Path $layout.Global -Text "$unicodePrefix $($specification.Name)`r`n" `
                -Encoding $specification.Encoding -EmitBom $true

            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

            $bytes = [IO.File]::ReadAllBytes($layout.Global)
            Assert-BytePrefix -Bytes $bytes -Prefix $specification.Preamble
            $decoded = $specification.Encoding.GetString(
                $bytes,
                $specification.Preamble.Length,
                $bytes.Length - $specification.Preamble.Length
            )
            Assert-True ($decoded.Contains("$unicodePrefix $($specification.Name)"))
            Assert-True ($decoded.Contains('## Tool Onboarding Gate'))
        }
    }

    It 'rejects an unsupported unmarked encoding before any write' {
        $layout = New-InstallLayout 'unsupported-encoding'
        New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null
        $invalidUtf8 = [byte[]](0xC3, 0x28)
        [IO.File]::WriteAllBytes($layout.Global, $invalidUtf8)

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('Unsupported text encoding'))
        Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($layout.Global))) `
            ([Convert]::ToBase64String($invalidUtf8))
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-False (Test-Path -LiteralPath $layout.Skill)
    }

    It 'preserves Unix file mode through install and rollback' {
        if ($script:IsWindowsTest) {
            return
        }

        $layout = New-InstallLayout 'unix-file-mode'
        New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null
        [IO.File]::WriteAllText($layout.Global, 'mode-original')
        $mode = [System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite
        [IO.File]::SetUnixFileMode($layout.Global, $mode)

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

        Assert-Equal ([IO.File]::GetUnixFileMode($layout.Global)) $mode
        $snapshot = @(Get-SnapshotDirectories $layout.Backup)[0]
        $rollback = Join-Path $snapshot.FullName 'rollback.ps1'
        $null = & $rollback
        Assert-Equal ([IO.File]::ReadAllText($layout.Global)) 'mode-original'
        Assert-Equal ([IO.File]::GetUnixFileMode($layout.Global)) $mode
    }

    It 'writes a PS5-readable BOM rollback script and restores a Unicode path' {
        $unicodePathSuffix = -join ([char[]]@(0x4E2D, 0x6587, 0x8DEF, 0x5F84))
        $layout = New-InstallLayout ("rollback-" + $unicodePathSuffix)
        New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null
        [IO.File]::WriteAllText($layout.Global, 'rollback-original')

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

        $snapshot = @(Get-SnapshotDirectories $layout.Backup)[0]
        $rollback = Join-Path $snapshot.FullName 'rollback.ps1'
        $bytes = [IO.File]::ReadAllBytes($rollback)
        Assert-BytePrefix -Bytes $bytes -Prefix ([byte[]](0xEF, 0xBB, 0xBF))

        $null = & $rollback
        Assert-Equal ([IO.File]::ReadAllText($layout.Global)) 'rollback-original'
        Assert-False (Test-Path -LiteralPath $layout.Skill)
    }

    It 'preflights every rollback backup before changing any live target' {
        foreach ($missingLabel in @('codex-skill', 'codex-global')) {
            $layout = New-InstallLayout ("rollback-preflight-" + $missingLabel)
            New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
            [IO.File]::WriteAllText((Join-Path $layout.Skill 'sentinel.txt'), 'original-skill')
            [IO.File]::WriteAllText($layout.Global, 'original-global')

            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

            $installedSkill = [IO.File]::ReadAllText((Join-Path $layout.Skill 'SKILL.md'))
            $installedGlobal = [IO.File]::ReadAllText($layout.Global)
            $snapshot = @(Get-SnapshotDirectories $layout.Backup)[0]
            $rollback = Join-Path $snapshot.FullName 'rollback.ps1'
            $missingBackup = Join-Path $snapshot.FullName $missingLabel
            $unavailableBackup = Join-Path $snapshot.FullName ($missingLabel + '-unavailable')
            Move-Item -LiteralPath $missingBackup -Destination $unavailableBackup

            $threw = $false
            try {
                $null = & $rollback
            } catch {
                $threw = $true
                $errorMessage = $_.Exception.Message
            }

            Assert-True $threw
            Assert-True ($errorMessage.Contains('Rollback backup is missing'))
            Assert-Equal ([IO.File]::ReadAllText((Join-Path $layout.Skill 'SKILL.md'))) $installedSkill
            Assert-Equal ([IO.File]::ReadAllText($layout.Global)) $installedGlobal
            if ($missingLabel -eq 'codex-skill') {
                Assert-Equal ([IO.File]::ReadAllText((Join-Path $unavailableBackup 'sentinel.txt'))) 'original-skill'
            } else {
                Assert-Equal ([IO.File]::ReadAllText($unavailableBackup)) 'original-global'
            }
        }
    }

    It 'rejects unbalanced, duplicate, out-of-order, and mixed managed markers without changes' {
        $cases = @(
            '<!-- agent-tool-routing-skill:start -->',
            "<!-- agent-tool-routing-skill:runtime:start -->`n<!-- agent-tool-routing-skill:runtime:start -->`n<!-- agent-tool-routing-skill:runtime:end -->",
            "<!-- agent-tool-routing-skill:onboarding:end -->`n<!-- agent-tool-routing-skill:onboarding:start -->",
            "<!-- agent-tool-routing-skill:start -->`n## Tool Directory Routing`nx`n## Tool Onboarding Gate`ny`n<!-- agent-tool-routing-skill:end -->`n<!-- agent-tool-routing-skill:onboarding:start -->`nz`n<!-- agent-tool-routing-skill:onboarding:end -->"
        )

        for ($caseIndex = 0; $caseIndex -lt $cases.Count; $caseIndex++) {
            $layout = New-InstallLayout ("bad-marker-$caseIndex")
            New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null
            [IO.File]::WriteAllText($layout.Global, $cases[$caseIndex])
            New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
            $sentinel = Join-Path $layout.Skill 'sentinel.txt'
            [IO.File]::WriteAllText($sentinel, 'keep')

            $threw = $false
            try {
                $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                    -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules
            } catch {
                $threw = $true
            }

            Assert-True $threw
            Assert-Equal ([IO.File]::ReadAllText($layout.Global)) $cases[$caseIndex]
            Assert-Equal ([IO.File]::ReadAllText($sentinel)) 'keep'
            Assert-False (Test-Path -LiteralPath $layout.Backup)
        }
    }

    It 'creates a unique run directory for repeated use of the same BackupRoot parent' {
        $layout = New-InstallLayout 'unique-snapshots'

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules
        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

        $snapshots = @(Get-SnapshotDirectories $layout.Backup)
        Assert-Equal $snapshots.Count 2
        Assert-False ([string]::Equals($snapshots[0].FullName, $snapshots[1].FullName, [StringComparison]::Ordinal))
        foreach ($snapshot in $snapshots) {
            Assert-True (Test-Path -LiteralPath (Join-Path $snapshot.FullName 'rollback.ps1'))
            Assert-Equal @(Get-ChildItem -LiteralPath $snapshot.FullName -Directory | Where-Object { $_.Name -like 'install-*' }).Count 0
        }
    }

    It 'rejects a BackupRoot that overlaps the target skill without writing' {
        $layout = New-InstallLayout 'overlapping-backup-root'
        New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
        $sentinel = Join-Path $layout.Skill 'sentinel.txt'
        [IO.File]::WriteAllText($sentinel, 'keep')
        $overlappingBackup = Join-Path $layout.Skill 'backups'

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $overlappingBackup -AddOnboardingRules
        } catch {
            $threw = $true
        }

        Assert-True $threw
        Assert-Equal ([IO.File]::ReadAllText($sentinel)) 'keep'
        Assert-False (Test-Path -LiteralPath $overlappingBackup)
        Assert-False (Test-Path -LiteralPath $layout.Global)
    }

    It 'rejects a BackupRoot inside an auto-discovered skills root' {
        $layout = New-InstallLayout 'auto-discovered-backup-root'
        $autoDiscoveredBackup = Join-TestPath $layout.Config @('skills', 'backups')

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $autoDiscoveredBackup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('overlaps repository or target path'))
        Assert-False (Test-Path -LiteralPath $autoDiscoveredBackup)
        Assert-False (Test-Path -LiteralPath $layout.Skill)
        Assert-False (Test-Path -LiteralPath $layout.Global)
    }

    It 'rejects mutation targets inside the source repository during preflight' {
        $layout = New-InstallLayout 'source-overlap'
        $configInsideRepository = Join-Path $repoRoot ('installer-target-' + [guid]::NewGuid().ToString('N'))

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $configInsideRepository -BackupRoot $layout.Backup `
                -AddOnboardingRules -WhatIf
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('overlaps source repository'))
        Assert-False (Test-Path -LiteralPath $configInsideRepository)
        Assert-False (Test-Path -LiteralPath $layout.Backup)
    }

    It 'rejects overlapping mutation paths for multiple agent targets' {
        $layout = New-InstallLayout 'overlapping-agent-targets'
        $sharedRoot = Join-Path $layout.Root 'shared-config'
        $claudeRoot = Join-Path $layout.Root 'claude-config'

        $threw = $false
        try {
            $null = & $installer -Target all -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $sharedRoot -ClaudeConfigDir $claudeRoot -ZcodeHome $sharedRoot `
                -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('overlapping mutation paths'))
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-False (Test-Path -LiteralPath $sharedRoot)
        Assert-False (Test-Path -LiteralPath $claudeRoot)
    }

    It 'reserves shared global paths even when one agent plan is unchanged' {
        $layout = New-InstallLayout 'unchanged-overlapping-agent-targets'
        $sharedRoot = Join-Path $layout.Root 'shared-config'
        $claudeRoot = Join-Path $layout.Root 'claude-config'
        $firstBackup = Join-Path $layout.Root 'first-backups'

        $null = & $installer -Target zcode -UserProfile $layout.Profile -AllowCustomProfile `
            -ZcodeHome $sharedRoot -BackupRoot $firstBackup -AddOnboardingRules
        $sharedGlobal = Join-Path $sharedRoot 'AGENTS.md'
        $original = [IO.File]::ReadAllText($sharedGlobal)

        $threw = $false
        try {
            $null = & $installer -Target all -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $sharedRoot -ClaudeConfigDir $claudeRoot -ZcodeHome $sharedRoot `
                -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('overlapping mutation paths'))
        Assert-Equal ([IO.File]::ReadAllText($sharedGlobal)) $original
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-False (Test-Path -LiteralPath $claudeRoot)
    }

    It 'rejects Windows device-namespace aliases before overlap checks' {
        if ([IO.Path]::DirectorySeparatorChar -ne [char]'\') {
            return
        }

        $layout = New-InstallLayout 'device-namespace-alias'
        $sharedRoot = Join-Path $layout.Root 'shared-config'
        $claudeRoot = Join-Path $layout.Root 'claude-config'
        $deviceAlias = '\\?\' + $sharedRoot

        $threw = $false
        try {
            $null = & $installer -Target all -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $sharedRoot -ClaudeConfigDir $claudeRoot -ZcodeHome $deviceAlias `
                -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('device-namespace paths are not supported'))
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-False (Test-Path -LiteralPath $sharedRoot)
        Assert-False (Test-Path -LiteralPath $claudeRoot)
    }

    It 'rejects Windows UNC aliases before overlap checks' {
        if ([IO.Path]::DirectorySeparatorChar -ne [char]'\') {
            return
        }

        $layout = New-InstallLayout 'unc-alias'
        $sharedRoot = Join-Path $layout.Root 'shared-config'
        $claudeRoot = Join-Path $layout.Root 'claude-config'
        $drive = [IO.Path]::GetPathRoot($sharedRoot).Substring(0, 1)
        $relative = $sharedRoot.Substring([IO.Path]::GetPathRoot($sharedRoot).Length)
        $uncAlias = '\\localhost\' + $drive + '$\' + $relative

        $threw = $false
        try {
            $null = & $installer -Target all -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $sharedRoot -ClaudeConfigDir $claudeRoot -ZcodeHome $uncAlias `
                -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('UNC paths are not supported'))
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-False (Test-Path -LiteralPath $sharedRoot)
        Assert-False (Test-Path -LiteralPath $claudeRoot)
    }

    It 'ignores H2 headings inside fenced code when installing managed rules' {
        $layout = New-InstallLayout 'fenced-heading'
        New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null
        $original = @(
            'USER_TEXT',
            '```markdown',
            '## Tool Onboarding Gate',
            'example only',
            '```',
            ''
        ) -join "`n"
        [IO.File]::WriteAllText($layout.Global, $original)

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

        $updated = [IO.File]::ReadAllText($layout.Global)
        Assert-True ($updated.Contains($original.TrimEnd("`r", "`n")))
        Assert-Equal ([regex]::Matches(
            $updated,
            [regex]::Escape('<!-- agent-tool-routing-skill:onboarding:start -->')
        ).Count) 1
        Assert-True ($updated.Contains('## Tool Onboarding Gate'))
    }

    It 'rejects list-container fenced code as ambiguous before writing' {
        $layout = New-InstallLayout 'container-fenced-heading'
        New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null
        $original = @(
            '- Example only:',
            '  ```markdown',
            '  ## Tool Onboarding Gate',
            '  example only',
            '  ```',
            ''
        ) -join "`n"
        [IO.File]::WriteAllText($layout.Global, $original)

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('Indented or container Markdown fences'))
        Assert-Equal ([IO.File]::ReadAllText($layout.Global)) $original
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-False (Test-Path -LiteralPath $layout.Skill)
    }

    It 'rejects an indented target H2 as an ambiguous Markdown container' {
        $layout = New-InstallLayout 'ambiguous-indented-h2'
        New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null
        $original = "- Example only:`n  ## Tool Onboarding Gate`n  not a live top-level rule`n"
        [IO.File]::WriteAllText($layout.Global, $original)

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('indented and may belong to a Markdown container'))
        Assert-Equal ([IO.File]::ReadAllText($layout.Global)) $original
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-False (Test-Path -LiteralPath $layout.Skill)
    }

    It 'recognizes a closing-ATX unmanaged H2 section' {
        $layout = New-InstallLayout 'unmanaged-h2-closing-atx'
        New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null
        $original = "## Tool Onboarding Gate ##`nuser-owned section`n"
        [IO.File]::WriteAllText($layout.Global, $original)

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

        Assert-Equal ([IO.File]::ReadAllText($layout.Global)) $original
        Assert-True (Test-Path -LiteralPath $layout.Skill)
    }

    It 'rejects managed markers inside fenced code without writing' {
        $layout = New-InstallLayout 'fenced-marker'
        New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null
        $original = @(
            '```markdown',
            '<!-- agent-tool-routing-skill:onboarding:start -->',
            '## Tool Onboarding Gate',
            'example only',
            '<!-- agent-tool-routing-skill:onboarding:end -->',
            '```',
            ''
        ) -join "`n"
        [IO.File]::WriteAllText($layout.Global, $original)

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('fenced code'))
        Assert-Equal ([IO.File]::ReadAllText($layout.Global)) $original
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-False (Test-Path -LiteralPath $layout.Skill)
    }

    It 'rejects indented managed markers in Markdown container examples' {
        $layout = New-InstallLayout 'container-fenced-marker'
        New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null
        $original = @(
            '- ```markdown',
            '  <!-- agent-tool-routing-skill:onboarding:start -->',
            '  ## Tool Onboarding Gate',
            '  example only',
            '  <!-- agent-tool-routing-skill:onboarding:end -->',
            '  ```',
            ''
        ) -join "`n"
        [IO.File]::WriteAllText($layout.Global, $original)

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('Indented or container Markdown fences'))
        Assert-Equal ([IO.File]::ReadAllText($layout.Global)) $original
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-False (Test-Path -LiteralPath $layout.Skill)
    }

    It 'performs no writes in WhatIf mode' {
        $layout = New-InstallLayout 'what-if'

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules -WhatIf

        Assert-False (Test-Path -LiteralPath $layout.Skill)
        Assert-False (Test-Path -LiteralPath $layout.Global)
        Assert-False (Test-Path -LiteralPath $layout.Backup)
    }

    It 'uses explicit custom config roots for all agents' {
        $layout = New-InstallLayout 'custom-roots'
        $codex = Join-TestPath $layout.Root @('outside', 'codex')
        $claude = Join-TestPath $layout.Root @('outside', 'claude')
        $zcode = Join-TestPath $layout.Root @('outside', 'zcode')

        $null = & $installer -Target all -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $codex -ClaudeConfigDir $claude -ZcodeHome $zcode `
            -BackupRoot $layout.Backup -AddOnboardingRules

        Assert-True (Test-Path -LiteralPath (Join-TestPath $codex @('skills', 'tool-use-architecture', 'SKILL.md')))
        Assert-Equal ([IO.File]::ReadAllText((Join-TestPath $codex @('skills', 'tool-use-architecture', 'VERSION'))).Trim()) $projectVersion
        Assert-True (Test-Path -LiteralPath (Join-Path $codex 'AGENTS.md'))
        Assert-True (Test-Path -LiteralPath (Join-TestPath $claude @('skills', 'tool-routing-architecture', 'SKILL.md')))
        Assert-Equal ([IO.File]::ReadAllText((Join-TestPath $claude @('skills', 'tool-routing-architecture', 'VERSION'))).Trim()) $projectVersion
        Assert-True (Test-Path -LiteralPath (Join-Path $claude 'CLAUDE.md'))
        Assert-True (Test-Path -LiteralPath (Join-TestPath $zcode @('skills', 'tool-routing-architecture', 'SKILL.md')))
        Assert-Equal ([IO.File]::ReadAllText((Join-TestPath $zcode @('skills', 'tool-routing-architecture', 'VERSION'))).Trim()) $projectVersion
        Assert-True (Test-Path -LiteralPath (Join-Path $zcode 'AGENTS.md'))
    }

    It 'uses environment config roots before profile fallbacks' {
        $layout = New-InstallLayout 'environment-root'
        $environmentRoot = Join-Path $layout.Root 'env-codex'
        $oldValue = $env:CODEX_HOME
        try {
            $env:CODEX_HOME = $environmentRoot
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -BackupRoot $layout.Backup -AddOnboardingRules
        } finally {
            $env:CODEX_HOME = $oldValue
        }

        Assert-True (Test-Path -LiteralPath (Join-TestPath $environmentRoot @('skills', 'tool-use-architecture', 'SKILL.md')))
        Assert-True (Test-Path -LiteralPath (Join-Path $environmentRoot 'AGENTS.md'))
    }

    It 'uses the profile fallback when the environment config root is unset' {
        $layout = New-InstallLayout 'profile-fallback'
        $fallbackRoot = Join-Path $layout.Profile '.codex'
        $oldValue = $env:CODEX_HOME
        try {
            Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -BackupRoot $layout.Backup -AddOnboardingRules
        } finally {
            $env:CODEX_HOME = $oldValue
        }

        Assert-True (Test-Path -LiteralPath (Join-TestPath $fallbackRoot @('skills', 'tool-use-architecture', 'SKILL.md')))
        Assert-True (Test-Path -LiteralPath (Join-Path $fallbackRoot 'AGENTS.md'))
    }

    It 'rejects direct and chained broken POSIX symlinks before writing' {
        if ($script:IsWindowsTest) {
            return
        }

        foreach ($caseName in @('direct', 'chained')) {
            $layout = New-InstallLayout ('posix-broken-symlink-' + $caseName)
            $missingTarget = Join-Path $layout.Root 'missing-config'
            $intermediateLink = $null
            $linkRoot = Join-Path $layout.Root 'broken-config'
            if ($caseName -eq 'chained') {
                $intermediateLink = Join-Path $layout.Root 'intermediate-link'
                New-Item -ItemType SymbolicLink -Path $intermediateLink -Target $missingTarget | Out-Null
                New-Item -ItemType SymbolicLink -Path $linkRoot -Target $intermediateLink | Out-Null
            } else {
                New-Item -ItemType SymbolicLink -Path $linkRoot -Target $missingTarget | Out-Null
            }

            try {
                $threw = $false
                try {
                    $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                        -CodexHome $linkRoot -BackupRoot $layout.Backup -AddOnboardingRules `
                        -AllowReparsePoints
                } catch {
                    $threw = $true
                    $errorMessage = $_.Exception.Message
                }

                Assert-True $threw
                Assert-True ($errorMessage.Contains('Cannot resolve symbolic link'))
                Assert-False (Test-Path -LiteralPath $layout.Backup)
                Assert-False (Test-Path -LiteralPath $missingTarget)
            } finally {
                [System.IO.File]::Delete($linkRoot)
                if ($null -ne $intermediateLink) {
                    [System.IO.File]::Delete($intermediateLink)
                }
            }
        }
    }

    It 'rejects a POSIX symlink alias that overlaps another agent target' {
        if ($script:IsWindowsTest) {
            return
        }

        $layout = New-InstallLayout 'posix-overlap-alias'
        $realRoot = Join-Path $layout.Root 'real-config'
        $linkRoot = Join-Path $layout.Root 'linked-config'
        $claudeRoot = Join-Path $layout.Root 'claude-config'
        New-Item -ItemType Directory -Path $realRoot -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path $linkRoot -Target $realRoot | Out-Null

        try {
            $threw = $false
            try {
                $null = & $installer -Target all -UserProfile $layout.Profile -AllowCustomProfile `
                    -CodexHome $realRoot -ClaudeConfigDir $claudeRoot -ZcodeHome $linkRoot `
                    -BackupRoot $layout.Backup -AddOnboardingRules -AllowReparsePoints
            } catch {
                $threw = $true
                $errorMessage = $_.Exception.Message
            }

            Assert-True $threw
            Assert-True ($errorMessage.Contains('overlapping mutation paths'))
            Assert-False (Test-Path -LiteralPath $layout.Backup)
            Assert-False (Test-Path -LiteralPath (Join-Path $realRoot 'AGENTS.md'))
        } finally {
            if ($null -ne (Get-Item -LiteralPath $linkRoot -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $linkRoot -Force
            }
        }
    }

    It 'rejects a nested POSIX symlink even when path symlinks are allowed' {
        if ($script:IsWindowsTest) {
            return
        }

        $layout = New-InstallLayout 'posix-nested-symlink'
        New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
        $outside = Join-Path $layout.Root 'outside-data'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        $outsideSentinel = Join-Path $outside 'sentinel.txt'
        [IO.File]::WriteAllText($outsideSentinel, 'outside-secret')
        $nestedLink = Join-Path $layout.Skill 'nested-link'
        New-Item -ItemType SymbolicLink -Path $nestedLink -Target $outside | Out-Null

        try {
            foreach ($allow in @($false, $true)) {
                $arguments = @{
                    Target = 'codex'
                    UserProfile = $layout.Profile
                    AllowCustomProfile = $true
                    CodexHome = $layout.Config
                    BackupRoot = $layout.Backup
                    AddOnboardingRules = $true
                }
                if ($allow) {
                    $arguments.AllowReparsePoints = $true
                }

                $threw = $false
                try {
                    $null = & $installer @arguments
                } catch {
                    $threw = $true
                    $errorMessage = $_.Exception.Message
                }

                Assert-True $threw
                Assert-True ($errorMessage.Contains('nested reparse point'))
                Assert-Equal ([IO.File]::ReadAllText($outsideSentinel)) 'outside-secret'
                Assert-False (Test-Path -LiteralPath $layout.Backup)
            }
        } finally {
            if ($null -ne (Get-Item -LiteralPath $nestedLink -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $nestedLink -Force
            }
        }
    }

    It 'rejects case-only target aliases on macOS' {
        if (-not $script:IsMacOSTest) {
            return
        }

        $layout = New-InstallLayout 'macos-case-alias'
        $codexRoot = Join-Path $layout.Root 'AgentConfig'
        $zcodeRoot = Join-Path $layout.Root 'agentconfig'
        $claudeRoot = Join-Path $layout.Root 'claude-config'
        $threw = $false
        try {
            $null = & $installer -Target all -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $codexRoot -ClaudeConfigDir $claudeRoot -ZcodeHome $zcodeRoot `
                -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
        }

        Assert-True $threw
        Assert-False (Test-Path -LiteralPath $layout.Backup)
    }

    It 'allows case-distinct target roots on Linux' {
        if (-not $script:IsLinuxTest) {
            return
        }

        $layout = New-InstallLayout 'linux-case-distinct'
        $codexRoot = Join-Path $layout.Root 'AgentConfig'
        $zcodeRoot = Join-Path $layout.Root 'agentconfig'
        $claudeRoot = Join-Path $layout.Root 'claude-config'

        $null = & $installer -Target all -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $codexRoot -ClaudeConfigDir $claudeRoot -ZcodeHome $zcodeRoot `
            -BackupRoot $layout.Backup -AddOnboardingRules

        Assert-True (Test-Path -LiteralPath (Join-Path $codexRoot 'AGENTS.md'))
        Assert-True (Test-Path -LiteralPath (Join-Path $zcodeRoot 'AGENTS.md'))
    }

    It 'automatically rolls back earlier targets when a later target write fails' {
        $layout = New-InstallLayout 'automatic-rollback'
        $codexRoot = Join-Path $layout.Root 'codex-config'
        $claudeRoot = Join-Path $layout.Root 'claude-config'
        $zcodeRoot = Join-Path $layout.Root 'zcode-config'
        $codexSkill = Join-TestPath $codexRoot @('skills', 'tool-use-architecture')
        $codexGlobal = Join-Path $codexRoot 'AGENTS.md'
        New-Item -ItemType Directory -Path $codexSkill -Force | Out-Null
        $sentinel = Join-Path $codexSkill 'sentinel.txt'
        [IO.File]::WriteAllText($sentinel, 'original-skill')
        [IO.File]::WriteAllText($codexGlobal, 'original-global')

        New-Item -ItemType Directory -Path $claudeRoot -Force | Out-Null
        $blockingSkillsFile = Join-Path $claudeRoot 'skills'
        [IO.File]::WriteAllText($blockingSkillsFile, 'not-a-directory')

        $threw = $false
        try {
            $null = & $installer -Target all -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $codexRoot -ClaudeConfigDir $claudeRoot -ZcodeHome $zcodeRoot `
                -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
        }

        Assert-True $threw
        Assert-Equal ([IO.File]::ReadAllText($sentinel)) 'original-skill'
        Assert-Equal ([IO.File]::ReadAllText($codexGlobal)) 'original-global'
        Assert-Equal ([IO.File]::ReadAllText($blockingSkillsFile)) 'not-a-directory'
        Assert-False (Test-Path -LiteralPath (Join-Path $zcodeRoot 'AGENTS.md'))
        $snapshots = @(Get-SnapshotDirectories $layout.Backup)
        Assert-Equal $snapshots.Count 1
        Assert-True (Test-Path -LiteralPath (Join-Path $snapshots[0].FullName 'rollback.ps1'))
    }

    It 'rejects a nested junction before backup even when path reparse is allowed' {
        if ([IO.Path]::DirectorySeparatorChar -ne [char]'\') {
            return
        }

        $layout = New-InstallLayout 'nested-junction-rejection'
        New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
        $outside = Join-Path $layout.Root 'outside-data'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        $outsideSentinel = Join-Path $outside 'sentinel.txt'
        [IO.File]::WriteAllText($outsideSentinel, 'outside-secret')
        $nestedJunction = Join-Path $layout.Skill 'nested-link'
        New-Item -ItemType Junction -Path $nestedJunction -Target $outside | Out-Null

        try {
            foreach ($allow in @($false, $true)) {
                $arguments = @{
                    Target = 'codex'
                    UserProfile = $layout.Profile
                    AllowCustomProfile = $true
                    CodexHome = $layout.Config
                    BackupRoot = $layout.Backup
                    AddOnboardingRules = $true
                }
                if ($allow) {
                    $arguments.AllowReparsePoints = $true
                }

                $threw = $false
                try {
                    $null = & $installer @arguments
                } catch {
                    $threw = $true
                    $errorMessage = $_.Exception.Message
                }

                Assert-True $threw
                Assert-True ($errorMessage.Contains('nested reparse point'))
                Assert-Equal ([IO.File]::ReadAllText($outsideSentinel)) 'outside-secret'
                Assert-False (Test-Path -LiteralPath $layout.Backup)
                Assert-False (Test-Path -LiteralPath $layout.Global)
            }
        } finally {
            if (Test-Path -LiteralPath $nestedJunction) {
                [IO.Directory]::Delete($nestedJunction)
            }
        }
    }

    It 'rejects an existing junction ancestor by default' {
        if ([IO.Path]::DirectorySeparatorChar -ne [char]'\') {
            return
        }

        $layout = New-InstallLayout 'junction-rejection'
        $realRoot = Join-Path $layout.Root 'real-config'
        $junctionRoot = Join-Path $layout.Root 'junction-config'
        New-Item -ItemType Directory -Path $realRoot -Force | Out-Null
        New-Item -ItemType Junction -Path $junctionRoot -Target $realRoot | Out-Null
        $sentinel = Join-Path $realRoot 'sentinel.txt'
        [IO.File]::WriteAllText($sentinel, 'keep')

        try {
            $threw = $false
            try {
                $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                    -CodexHome $junctionRoot -BackupRoot $layout.Backup -AddOnboardingRules
            } catch {
                $threw = $true
            }

            Assert-True $threw
            Assert-Equal ([IO.File]::ReadAllText($sentinel)) 'keep'
            Assert-False (Test-Path -LiteralPath $layout.Backup)
            Assert-False (Test-Path -LiteralPath (Join-Path $realRoot 'AGENTS.md'))
        } finally {
            if (Test-Path -LiteralPath $junctionRoot) {
                [IO.Directory]::Delete($junctionRoot)
            }
        }
    }
}
