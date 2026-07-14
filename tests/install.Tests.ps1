BeforeAll {
$here = $PSScriptRoot
$repoRoot = Split-Path -Parent $here
$script:CreatedTestRoots = New-Object System.Collections.Generic.List[string]
$script:CreatedTestProcesses = New-Object System.Collections.Generic.List[object]
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
$remoteInstaller = Join-TestPath $repoRoot @('scripts', 'install-remote.ps1')
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

function New-RemoteSourceFixture {
    param([string]$Name)

    $physicalTestDrive = Get-PhysicalTestPath -Path $TestDrive
    $root = Join-Path $physicalTestDrive $Name
    [void]$script:CreatedTestRoots.Add($root)
    $source = Join-Path $root 'source'
    New-Item -ItemType Directory -Path $source -Force | Out-Null

    $manifestRelative = 'scripts/install-manifest.json'
    $manifestSource = Join-TestPath $repoRoot @('scripts', 'install-manifest.json')
    $manifestDestination = Join-TestPath $source @('scripts', 'install-manifest.json')
    New-Item -ItemType Directory -Path (Split-Path -Parent $manifestDestination) -Force | Out-Null
    Copy-Item -LiteralPath $manifestSource -Destination $manifestDestination -Force
    $manifest = Get-Content -LiteralPath $manifestSource -Raw | ConvertFrom-Json
    foreach ($entry in @($manifest.files)) {
        $segments = @(([string]$entry.path).Split('/'))
        $sourcePath = Join-TestPath $repoRoot $segments
        $destinationPath = Join-TestPath $source $segments
        New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }
    return $source
}

function New-CurrentRemoteFixture {
    param([string]$Name)

    $source = New-RemoteSourceFixture -Name $Name
    $manifestPath = Join-TestPath $source @('scripts', 'install-manifest.json')
    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    $manifest.version = $projectVersion
    foreach ($entry in @($manifest.files)) {
        $payloadPath = Join-TestPath $source @(([string]$entry.path).Split('/'))
        $entry.sha256 = (Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $entry.size = (Get-Item -LiteralPath $payloadPath -Force).Length
    }
    $manifestText = ($manifest | ConvertTo-Json -Depth 5).Replace("`r`n", "`n") + "`n"
    [IO.File]::WriteAllText(
        $manifestPath,
        $manifestText,
        (New-Object Text.UTF8Encoding $false)
    )
    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $bootstrapText = [IO.File]::ReadAllText($remoteInstaller)
    $hashAssignment = [regex]::Match(
        $bootstrapText,
        '(?m)^\$ManifestSha256 = ''[0-9a-f]{64}'''
    )
    Assert-True $hashAssignment.Success 'Remote bootstrap manifest hash assignment was not found.'
    $bootstrapText = $bootstrapText.Replace(
        $hashAssignment.Value,
        ('$ManifestSha256 = ''' + $manifestHash + '''')
    )
    $versionAssignment = [regex]::Match(
        $bootstrapText,
        '(?m)^\$ReleaseVersion = ''[^'']+'''
    )
    Assert-True $versionAssignment.Success 'Remote bootstrap release version assignment was not found.'
    $bootstrapText = $bootstrapText.Replace(
        $versionAssignment.Value,
        ('$ReleaseVersion = ''' + $projectVersion + '''')
    )
    return [pscustomobject]@{
        SourceRoot = $source
        Installer = [scriptblock]::Create($bootstrapText)
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

function Get-SkillTransactionContainer {
    param([string]$SkillPath)

    $parent = Split-Path -Parent $SkillPath
    return Join-Path $parent '.agent-tool-routing-transactions'
}

function Get-TestInstallMutexName {
    param([string]$ConfigRoot)

    $comparisonRoot = [IO.Path]::GetFullPath($ConfigRoot)
    $root = [IO.Path]::GetPathRoot($comparisonRoot)
    while (($comparisonRoot.Length -gt $root.Length) -and
        (($comparisonRoot[$comparisonRoot.Length - 1] -eq [char]'\') -or
            ($comparisonRoot[$comparisonRoot.Length - 1] -eq [char]'/'))) {
        $comparisonRoot = $comparisonRoot.Substring(0, $comparisonRoot.Length - 1)
    }
    if ($script:IsWindowsTest -or $script:IsMacOSTest) {
        $comparisonRoot = $comparisonRoot.ToUpperInvariant()
    }
    $utf8 = New-Object Text.UTF8Encoding -ArgumentList $false
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash($utf8.GetBytes($comparisonRoot))
    } finally {
        $sha256.Dispose()
    }
    $hex = ([BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
    $prefix = if ($script:IsWindowsTest) {
        'Global\AgentToolRoutingSkill.Install.'
    } else {
        'AgentToolRoutingSkill.Install.'
    }
    return $prefix + $hex
}

function Start-TestMutexHolder {
    param(
        [string]$Root,
        [string]$MutexName
    )

    $holderScript = Join-Path $Root 'hold-install-mutex.ps1'
    $readyPath = Join-Path $Root 'mutex-ready'
    $holderText = @'
param([string]$MutexName, [string]$ReadyPath)
$ErrorActionPreference = 'Stop'
$mutex = New-Object System.Threading.Mutex -ArgumentList $false, $MutexName
$acquired = $false
try {
    $acquired = $mutex.WaitOne(0)
    if (-not $acquired) { exit 2 }
    [IO.File]::WriteAllText($ReadyPath, 'ready')
    while ($true) { Start-Sleep -Seconds 1 }
} finally {
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
'@
    [IO.File]::WriteAllText($holderScript, $holderText, (New-Object Text.UTF8Encoding $false))
    $executable = (Get-Process -Id $PID).Path
    $arguments = @('-NoLogo', '-NoProfile', '-File', $holderScript, $MutexName, $readyPath)
    if ($script:IsWindowsTest) {
        $process = Start-Process -FilePath $executable -ArgumentList $arguments `
            -PassThru -WindowStyle Hidden
    } else {
        $process = Start-Process -FilePath $executable -ArgumentList $arguments -PassThru
    }
    [void]$script:CreatedTestProcesses.Add($process)

    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        if (Test-Path -LiteralPath $readyPath -PathType Leaf) {
            return $process
        }
        if ($process.HasExited) {
            throw "Mutex holder exited before acquiring the test lock (exit $($process.ExitCode))."
        }
        Start-Sleep -Milliseconds 50
        $process.Refresh()
    }
    throw 'Timed out waiting for the mutex holder process.'
}

function Invoke-InstallerInFreshProcess {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $executable = (Get-Process -Id $PID).Path
    $quote = {
        param([string]$Value)
        return "'" + $Value.Replace("'", "''") + "'"
    }
    $commandParts = @('&', (& $quote $installer)) + @(
        $Arguments | ForEach-Object {
            $argument = [string]$_
            if ($argument -match '^-[A-Za-z][A-Za-z0-9]*$') {
                $argument
            } else {
                & $quote $argument
            }
        }
    )
    $childCommand = 'try { ' + ($commandParts -join ' ') +
        ' } catch { [Console]::Error.WriteLine([string]$_.Exception.Message); exit 1 }'
    $encoded = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($childCommand)
    )
    $stdoutPath = Join-Path ([IO.Path]::GetTempPath()) `
        ('agent-routing-child-' + [guid]::NewGuid().ToString('N') + '.stdout')
    $stderrPath = Join-Path ([IO.Path]::GetTempPath()) `
        ('agent-routing-child-' + [guid]::NewGuid().ToString('N') + '.stderr')
    try {
        $start = @{
            FilePath = $executable
            ArgumentList = @('-NoLogo', '-NoProfile', '-EncodedCommand', $encoded)
            PassThru = $true
            Wait = $true
            RedirectStandardOutput = $stdoutPath
            RedirectStandardError = $stderrPath
        }
        if ($script:IsWindowsTest) {
            $start.WindowStyle = 'Hidden'
        }
        $process = Start-Process @start
        $stdout = if (Test-Path -LiteralPath $stdoutPath) {
            Get-Content -LiteralPath $stdoutPath -Raw
        } else { '' }
        $stderr = if (Test-Path -LiteralPath $stderrPath) {
            Get-Content -LiteralPath $stderrPath -Raw
        } else { '' }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = ([string]$stdout) + ([string]$stderr)
        }
    } finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force `
            -ErrorAction SilentlyContinue
    }
}

function New-ToolIndexDependency {
    param([string]$ConfigRoot)

    $path = Join-TestPath $ConfigRoot @('skills', 'tool-index', 'SKILL.md')
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, "---`nname: tool-index`n---`n")
    return $path
}

function Assert-PendingInitialIndexState {
    param(
        [string]$ConfigRoot,
        [string]$TargetAgent
    )

    $statePath = Join-TestPath $ConfigRoot @('tool-routing-state', 'initial-index.json')
    Assert-True (Test-Path -LiteralPath $statePath -PathType Leaf)
    $state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    Assert-True (($state.schema_version -is [int]) -or ($state.schema_version -is [long]))
    Assert-True ($state.target_agent -is [string])
    Assert-True ($state.target_config_root -is [string])
    Assert-True ($state.mutation_scope -is [string])
    Assert-Equal ([int]$state.schema_version) 2
    Assert-Equal ([string]$state.status) 'pending'
    Assert-Equal ([string]$state.target_agent) $TargetAgent
    Assert-Equal ([IO.Path]::GetFullPath([string]$state.target_config_root)) `
        ([IO.Path]::GetFullPath($ConfigRoot))
    Assert-Equal ([string]$state.mutation_scope) 'target-agent-config-only'
    Assert-Equal ([string]$state.project_version) $projectVersion
    Assert-Equal ([string]$state.runtime_mode) 'auto-discovery'
    Assert-Equal ([string]$state.scope) 'registered-capabilities'
}
}

Describe 'scripts/install.ps1' {
    BeforeEach {
        $script:CreatedTestRoots.Clear()
        $script:CreatedTestProcesses.Clear()
    }

    AfterEach {
        foreach ($process in @($script:CreatedTestProcesses.ToArray())) {
            try {
                if (-not $process.HasExited) {
                    Stop-Process -Id $process.Id -Force -ErrorAction Stop
                    $process.WaitForExit(5000) | Out-Null
                }
            } catch {
                Write-Warning "Could not stop test helper process $($process.Id): $($_.Exception.Message)"
            } finally {
                $process.Dispose()
            }
        }
        $script:CreatedTestProcesses.Clear()
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

    It 'rejects a missing target before writing config or backup data' {
        $layout = New-InstallLayout 'missing-target'
        $threw = $false

        try {
            $null = & $installer -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('-Target is required'))
        Assert-False (Test-Path -LiteralPath $layout.Config)
        Assert-False (Test-Path -LiteralPath $layout.Backup)
    }

    It 'installs Codex onboarding without resolving unrelated agent roots' {
        $layout = New-InstallLayout 'clean-onboarding'
        $invalidUnrelatedRoot = "invalid$([char]0)root"

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -ClaudeConfigDir $invalidUnrelatedRoot `
            -ZcodeHome $invalidUnrelatedRoot -BackupRoot $layout.Backup -AddOnboardingRules

        Assert-True (Test-Path -LiteralPath $layout.Skill)
        Assert-True (Test-Path -LiteralPath $layout.Global)
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $layout.Skill 'VERSION')).Trim()) $projectVersion
        $global = [IO.File]::ReadAllText($layout.Global)
        Assert-True ($global.Contains('<!-- agent-tool-routing-skill:onboarding:start -->'))
        Assert-False ($global.Contains('<!-- agent-tool-routing-skill:runtime:start -->'))
        Assert-True ($global.Contains('This opt-in gate delegates only'))
        Assert-True ($global.Contains('must not replace the current task'))
        Assert-False (Test-Path -LiteralPath (
            Join-TestPath $layout.Config @('tool-routing-state', 'initial-index.json')
        ))

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

    It 'rejects a concurrent installer before writing targets or backups' {
        $layout = New-InstallLayout 'single-writer-lock'
        $mutexName = Get-TestInstallMutexName -ConfigRoot $layout.Config
        $null = Start-TestMutexHolder -Root $layout.Root -MutexName $mutexName

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('installation is already active')) `
            "Unexpected installer error: $errorMessage"
        Assert-False (Test-Path -LiteralPath $layout.Config)
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-Equal @(Get-SnapshotDirectories $layout.Backup).Count 0
    }

    It 'replaces an existing skill through a journaled transaction and rollback restores it' {
        $layout = New-InstallLayout 'transaction-swap-success'
        New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
        $sentinel = Join-Path $layout.Skill 'sentinel.txt'
        [IO.File]::WriteAllText($sentinel, 'original-skill')

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

        Assert-False (Test-Path -LiteralPath $sentinel)
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $layout.Skill 'VERSION')).Trim()) $projectVersion
        Assert-False (Test-Path -LiteralPath (Get-SkillTransactionContainer -SkillPath $layout.Skill))
        $snapshot = @(Get-SnapshotDirectories $layout.Backup)[0]
        $rollback = Join-Path $snapshot.FullName 'rollback.ps1'

        $null = & $rollback

        Assert-Equal ([IO.File]::ReadAllText($sentinel)) 'original-skill'
        Assert-False (Test-Path -LiteralPath (Join-Path $layout.Skill 'VERSION'))
        Assert-False (Test-Path -LiteralPath (Get-SkillTransactionContainer -SkillPath $layout.Skill))
    }

    It 'recovers a journaled live-to-previous crash before taking the new backup' {
        $layout = New-InstallLayout 'transaction-crash-recovery'
        New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
        $sentinel = Join-Path $layout.Skill 'sentinel.txt'
        [IO.File]::WriteAllText($sentinel, 'pre-crash-skill')
        Mock Remove-Item { throw 'simulated previous cleanup interruption' } -ParameterFilter {
            (-not [string]::IsNullOrEmpty([string]$LiteralPath)) -and
                ([IO.Path]::GetFileName([string]$LiteralPath) -eq 'previous')
        }

        $firstBackup = Join-Path $layout.Root 'first-backup'
        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $firstBackup
        $container = Get-SkillTransactionContainer -SkillPath $layout.Skill
        $transactions = @(Get-ChildItem -LiteralPath $container -Directory)
        Assert-Equal $transactions.Count 1
        $transactionRoot = $transactions[0].FullName
        $incoming = Join-Path $transactionRoot 'incoming'
        $previous = Join-Path $transactionRoot 'previous'
        Assert-True (Test-Path -LiteralPath (Join-Path $transactionRoot 'prepared-tree.json'))
        Assert-True (Test-Path -LiteralPath (Join-Path $transactionRoot 'phase-20-incoming-prepared.json'))
        Assert-True (Test-Path -LiteralPath (Join-Path $transactionRoot 'phase-30-live-displaced.json'))
        $committedPhase = Join-Path $transactionRoot 'phase-40-live-committed.json'
        Assert-True (Test-Path -LiteralPath $committedPhase)
        # Reconstruct the exact state after live -> previous and before
        # incoming -> live: phase 20/30, previous + incoming, and no live.
        [IO.File]::Delete($committedPhase)
        Move-Item -LiteralPath $layout.Skill -Destination $incoming

        Assert-False (Test-Path -LiteralPath (Join-Path $container 'SKILL.md'))
        Assert-True (Test-Path -LiteralPath (Join-Path $incoming 'SKILL.md'))
        Assert-False (Test-Path -LiteralPath $layout.Skill)
        Assert-False (Test-Path -LiteralPath $committedPhase)

        $recoveryBackup = Join-Path $layout.Root 'recovery-backup'
        $recovery = Invoke-InstallerInFreshProcess -Arguments @(
            '-Target', 'codex',
            '-UserProfile', $layout.Profile,
            '-AllowCustomProfile',
            '-CodexHome', $layout.Config,
            '-BackupRoot', $recoveryBackup
        )

        Assert-Equal $recovery.ExitCode 0 $recovery.Output
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $layout.Skill 'VERSION')).Trim()) $projectVersion
        Assert-False (Test-Path -LiteralPath $container)
        $snapshot = @(Get-SnapshotDirectories $recoveryBackup)[0]
        $rollback = Join-Path $snapshot.FullName 'rollback.ps1'

        $null = & $rollback

        Assert-Equal ([IO.File]::ReadAllText($sentinel)) 'pre-crash-skill'
        Assert-False (Test-Path -LiteralPath (Join-Path $layout.Skill 'VERSION'))
    }

    It 'refuses to delete previous data when a retained committed live tree was modified' {
        $layout = New-InstallLayout 'transaction-tampered-live'
        New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
        $oldSentinel = Join-Path $layout.Skill 'old-sentinel.txt'
        [IO.File]::WriteAllText($oldSentinel, 'old-skill')
        Mock Remove-Item { throw 'simulated previous cleanup interruption' } -ParameterFilter {
            (-not [string]::IsNullOrEmpty([string]$LiteralPath)) -and
                ([IO.Path]::GetFileName([string]$LiteralPath) -eq 'previous')
        }

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot (Join-Path $layout.Root 'first-backup')
        $container = Get-SkillTransactionContainer -SkillPath $layout.Skill
        $transactionRoot = @(Get-ChildItem -LiteralPath $container -Directory)[0].FullName
        $previous = Join-Path $transactionRoot 'previous'
        $liveSkillFile = Join-Path $layout.Skill 'SKILL.md'
        [IO.File]::AppendAllText($liveSkillFile, "`npost-crash modification`n")
        $tamperedBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($liveSkillFile))
        $recoveryBackup = Join-Path $layout.Root 'recovery-backup'

        $recovery = Invoke-InstallerInFreshProcess -Arguments @(
            '-Target', 'codex',
            '-UserProfile', $layout.Profile,
            '-AllowCustomProfile',
            '-CodexHome', $layout.Config,
            '-BackupRoot', $recoveryBackup
        )
        $errorMessage = $recovery.Output

        Assert-True ($recovery.ExitCode -ne 0)
        Assert-True ($errorMessage.Contains('does not match the prepared incoming tree')) `
            "Unexpected installer error: $errorMessage"
        Assert-False (Test-Path -LiteralPath $recoveryBackup)
        Assert-True (Test-Path -LiteralPath $previous)
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $previous 'old-sentinel.txt'))) 'old-skill'
        Assert-True (Test-Path -LiteralPath (Join-Path $transactionRoot 'transaction.json'))
        Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($liveSkillFile))) $tamperedBytes
    }

    It 'finalizes retained committed data only when live matches the prepared tree' {
        $layout = New-InstallLayout 'transaction-matching-live'
        New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
        $oldSentinel = Join-Path $layout.Skill 'old-sentinel.txt'
        [IO.File]::WriteAllText($oldSentinel, 'old-skill')
        Mock Remove-Item { throw 'simulated previous cleanup interruption' } -ParameterFilter {
            (-not [string]::IsNullOrEmpty([string]$LiteralPath)) -and
                ([IO.Path]::GetFileName([string]$LiteralPath) -eq 'previous')
        }

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot (Join-Path $layout.Root 'first-backup')
        $container = Get-SkillTransactionContainer -SkillPath $layout.Skill
        Assert-True (Test-Path -LiteralPath $container)
        $recoveryBackup = Join-Path $layout.Root 'recovery-backup'

        $recovery = Invoke-InstallerInFreshProcess -Arguments @(
            '-Target', 'codex',
            '-UserProfile', $layout.Profile,
            '-AllowCustomProfile',
            '-CodexHome', $layout.Config,
            '-BackupRoot', $recoveryBackup
        )

        Assert-Equal $recovery.ExitCode 0 $recovery.Output
        Assert-False (Test-Path -LiteralPath $container)
        $snapshot = @(Get-SnapshotDirectories $recoveryBackup)[0]
        $null = & (Join-Path $snapshot.FullName 'rollback.ps1')
        Assert-False (Test-Path -LiteralPath $oldSentinel)
        Assert-Equal ([IO.File]::ReadAllText((Join-Path $layout.Skill 'VERSION')).Trim()) $projectVersion
    }

    It 'rejects timestamp-only phase markers before recovery writes or backups' {
        $layout = New-InstallLayout 'transaction-invalid-phase-marker'
        New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $layout.Skill 'old-sentinel.txt'), 'old-skill')
        Mock Remove-Item { throw 'simulated previous cleanup interruption' } -ParameterFilter {
            (-not [string]::IsNullOrEmpty([string]$LiteralPath)) -and
                ([IO.Path]::GetFileName([string]$LiteralPath) -eq 'previous')
        }

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot (Join-Path $layout.Root 'first-backup')
        $container = Get-SkillTransactionContainer -SkillPath $layout.Skill
        $transactionRoot = @(Get-ChildItem -LiteralPath $container -Directory)[0].FullName
        $previous = Join-Path $transactionRoot 'previous'
        $phasePath = Join-Path $transactionRoot 'phase-40-live-committed.json'
        [IO.File]::WriteAllText(
            $phasePath,
            ('{"recorded_at_utc":"' + [DateTime]::UtcNow.ToString('o') + '"}' + "`n"),
            (New-Object Text.UTF8Encoding $false)
        )
        $recoveryBackup = Join-Path $layout.Root 'recovery-backup'

        $recovery = Invoke-InstallerInFreshProcess -Arguments @(
            '-Target', 'codex',
            '-UserProfile', $layout.Profile,
            '-AllowCustomProfile',
            '-CodexHome', $layout.Config,
            '-BackupRoot', $recoveryBackup
        )
        $errorMessage = $recovery.Output

        Assert-True ($recovery.ExitCode -ne 0)
        Assert-True ($errorMessage.Contains('phase marker metadata is invalid')) `
            "Unexpected installer error: $errorMessage"
        Assert-False (Test-Path -LiteralPath $recoveryBackup)
        Assert-True (Test-Path -LiteralPath $previous)
        Assert-True (Test-Path -LiteralPath (Join-Path $transactionRoot 'transaction.json'))
    }

    It 'rejects top-level JSON arrays in retained transaction metadata' {
        $layout = New-InstallLayout 'transaction-array-root'
        New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $layout.Skill 'old-sentinel.txt'), 'old-skill')
        Mock Remove-Item { throw 'simulated previous cleanup interruption' } -ParameterFilter {
            (-not [string]::IsNullOrEmpty([string]$LiteralPath)) -and
                ([IO.Path]::GetFileName([string]$LiteralPath) -eq 'previous')
        }

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot (Join-Path $layout.Root 'first-backup')
        $container = Get-SkillTransactionContainer -SkillPath $layout.Skill
        $transactionRoot = @(Get-ChildItem -LiteralPath $container -Directory)[0].FullName
        $previous = Join-Path $transactionRoot 'previous'
        $journalPath = Join-Path $transactionRoot 'transaction.json'
        $journalText = [IO.File]::ReadAllText($journalPath).Trim()
        [IO.File]::WriteAllText(
            $journalPath,
            "[`n$journalText`n]`n",
            (New-Object Text.UTF8Encoding $false)
        )
        $journalBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($journalPath))
        $liveSkillPath = Join-Path $layout.Skill 'SKILL.md'
        $liveBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($liveSkillPath))
        $recoveryBackup = Join-Path $layout.Root 'recovery-backup'

        $recovery = Invoke-InstallerInFreshProcess -Arguments @(
            '-Target', 'codex',
            '-UserProfile', $layout.Profile,
            '-AllowCustomProfile',
            '-CodexHome', $layout.Config,
            '-BackupRoot', $recoveryBackup
        )

        Assert-True ($recovery.ExitCode -ne 0)
        Assert-True ($recovery.Output.Contains('JSON root must be an object')) `
            "Unexpected installer error: $($recovery.Output)"
        Assert-False (Test-Path -LiteralPath $recoveryBackup)
        Assert-True (Test-Path -LiteralPath $previous -PathType Container)
        Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($journalPath))) `
            $journalBefore
        Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($liveSkillPath))) `
            $liveBefore
    }

    It 'keeps the existing skill and cleans the non-discoverable transaction when incoming copy fails' {
        $layout = New-InstallLayout 'transaction-copy-failure'
        New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
        $sentinel = Join-Path $layout.Skill 'sentinel.txt'
        [IO.File]::WriteAllText($sentinel, 'original-skill')
        $expectedTransactionContainer = Get-SkillTransactionContainer -SkillPath $layout.Skill
        Mock Copy-Item {
            $transactionRoot = Split-Path -Parent ([string]$Destination)
            $observedTransactionContainer = Split-Path -Parent $transactionRoot
            Assert-False (Test-Path -LiteralPath (
                Join-Path $observedTransactionContainer 'SKILL.md'
            ))
            Assert-True (Test-Path -LiteralPath (Join-Path $transactionRoot 'transaction.json'))
            throw 'simulated incoming copy failure'
        } -ParameterFilter {
            (-not [string]::IsNullOrEmpty([string]$Destination)) -and
                ([IO.Path]::GetFileName([string]$Destination) -eq 'incoming') -and
                ([IO.Path]::GetFileName((Split-Path -Parent ([string]$Destination))) -like 'txn-*')
        }

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('Could not prepare a complete incoming skill copy')) `
            "Unexpected installer error: $errorMessage"
        Assert-Equal ([IO.File]::ReadAllText($sentinel)) 'original-skill'
        Assert-False (Test-Path -LiteralPath $expectedTransactionContainer)
    }

    It 'restores the existing skill exactly when the incoming transaction commit fails' {
        $layout = New-InstallLayout 'transaction-commit-failure'
        New-Item -ItemType Directory -Path $layout.Skill -Force | Out-Null
        $sentinel = Join-Path $layout.Skill 'sentinel.txt'
        [IO.File]::WriteAllText($sentinel, 'original-skill')
        Mock Move-Item { throw 'simulated incoming commit failure' } -ParameterFilter {
            (-not [string]::IsNullOrEmpty([string]$LiteralPath)) -and
                ([IO.Path]::GetFileName([string]$LiteralPath) -eq 'incoming') -and
                ([string]::Equals(
                    [IO.Path]::GetFullPath([string]$Destination),
                    [IO.Path]::GetFullPath($layout.Skill),
                    [StringComparison]::OrdinalIgnoreCase
                ))
        }

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('previous skill was restored exactly')) `
            "Unexpected installer error: $errorMessage"
        Assert-False ($errorMessage.Contains('automatic rollback also failed'))
        Assert-Equal ([IO.File]::ReadAllText($sentinel)) 'original-skill'
        Assert-False (Test-Path -LiteralPath (Get-SkillTransactionContainer -SkillPath $layout.Skill))
    }

    It 'initializes pending routing state without activating runtime routing' {
        $layout = New-InstallLayout 'initialize-routing'

        $output = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup `
            -InitializeRouting | Out-String

        Assert-PendingInitialIndexState -ConfigRoot $layout.Config -TargetAgent 'codex'
        Assert-True ($output.Contains('must not interrupt or take priority over ordinary work'))
        Assert-True ($output.Contains('current user explicitly asks to initialize or resume routing'))
        Assert-False ($output.Contains('Starting the codex'))
        Assert-False (Test-Path -LiteralPath (Join-Path $layout.Skill 'state'))
        Assert-False (Test-Path -LiteralPath $layout.Global)
        Assert-False (Test-Path -LiteralPath (
            Join-TestPath $layout.Config @('skills', 'tool-index')
        ))
    }

    It 'removes an unchanged installer-created request during rollback' {
        $layout = New-InstallLayout 'rollback-initial-index'

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -InitializeRouting

        $statePath = Join-TestPath $layout.Config @('tool-routing-state', 'initial-index.json')
        Assert-True (Test-Path -LiteralPath $statePath -PathType Leaf)
        $snapshot = @(Get-SnapshotDirectories $layout.Backup)[0]
        $rollback = Join-Path $snapshot.FullName 'rollback.ps1'

        $null = & $rollback

        Assert-False (Test-Path -LiteralPath $statePath)
        Assert-False (Test-Path -LiteralPath $layout.Skill)
        Assert-False (Test-Path -LiteralPath $layout.Global)
    }

    It 'preserves a progressed initial-index request during rollback' {
        $layout = New-InstallLayout 'rollback-progressed-initial-index'

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -InitializeRouting

        $statePath = Join-TestPath $layout.Config @('tool-routing-state', 'initial-index.json')
        $request = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
        $request.status = 'inventory'
        $request.phase = 'inventory'
        $progressedText = ($request | ConvertTo-Json -Depth 4) + "`n"
        [IO.File]::WriteAllText($statePath, $progressedText, (New-Object Text.UTF8Encoding $false))
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath))
        $snapshot = @(Get-SnapshotDirectories $layout.Backup)[0]
        $rollback = Join-Path $snapshot.FullName 'rollback.ps1'

        $output = & $rollback 3>&1 | Out-String

        Assert-True (Test-Path -LiteralPath $statePath -PathType Leaf)
        $after = [Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath))
        Assert-Equal $after $before
        Assert-True ($output.Contains('changed after installation'))
        Assert-False (Test-Path -LiteralPath $layout.Skill)
        Assert-False (Test-Path -LiteralPath $layout.Global)
    }

    It 'initializes without requiring or changing an onboarding gate' {
        $layout = New-InstallLayout 'unmanaged-onboarding-initialization'
        New-Item -ItemType Directory -Path $layout.Config -Force | Out-Null
        $originalGlobal = "## Tool Onboarding Gate`n`nCustom unmanaged instructions.`n"
        [IO.File]::WriteAllText(
            $layout.Global,
            $originalGlobal
        )

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -InitializeRouting

        Assert-True (Test-Path -LiteralPath $layout.Skill)
        Assert-PendingInitialIndexState -ConfigRoot $layout.Config -TargetAgent 'codex'
        Assert-Equal ([IO.File]::ReadAllText($layout.Global)) $originalGlobal
    }

    It 'preserves a resumable initial-index request across architecture refresh' {
        $layout = New-InstallLayout 'preserve-initial-index'
        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -InitializeRouting

        $statePath = Join-TestPath $layout.Config @('tool-routing-state', 'initial-index.json')
        $request = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
        $request.status = 'blocked'
        $request.phase = 'sourcing'
        $request.unresolved_a_tools = @('missing-a-guide')
        $stateText = ($request | ConvertTo-Json -Depth 4) + "`n"
        [IO.File]::WriteAllText($statePath, $stateText, (New-Object Text.UTF8Encoding $false))
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath))

        $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

        $after = [Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath))
        Assert-Equal $after $before
        $preserved = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
        Assert-Equal ([string]$preserved.request_id) ([string]$request.request_id)
        Assert-Equal ([string]$preserved.status) 'blocked'
        Assert-Equal ([string]$preserved.unresolved_a_tools[0]) 'missing-a-guide'
    }

    It 'rejects non-array and non-string initial-index list fields before writes' {
        $cases = @(
            [pscustomobject]@{ Name = 'completed-null'; Field = 'completed_phases'; Value = $null },
            [pscustomobject]@{ Name = 'completed-number'; Field = 'completed_phases'; Value = 1 },
            [pscustomobject]@{ Name = 'completed-object'; Field = 'completed_phases'; Value = [pscustomobject]@{ phase = 'inventory' } },
            [pscustomobject]@{ Name = 'completed-mixed'; Field = 'completed_phases'; Value = @('inventory', 1) },
            [pscustomobject]@{ Name = 'unresolved-null'; Field = 'unresolved_a_tools'; Value = $null },
            [pscustomobject]@{ Name = 'unresolved-number'; Field = 'unresolved_a_tools'; Value = 1 },
            [pscustomobject]@{ Name = 'unresolved-object'; Field = 'unresolved_a_tools'; Value = [pscustomobject]@{ tool = 'example' } },
            [pscustomobject]@{ Name = 'unresolved-mixed'; Field = 'unresolved_a_tools'; Value = @('example', 1) }
        )

        foreach ($case in $cases) {
            $layout = New-InstallLayout ("invalid-index-list-" + $case.Name)
            $statePath = Join-TestPath $layout.Config @('tool-routing-state', 'initial-index.json')
            New-Item -ItemType Directory -Path (Split-Path -Parent $statePath) -Force | Out-Null
            $request = [ordered]@{
                schema_version = 2
                request_id = [guid]::NewGuid().ToString('N')
                status = 'pending'
                target_agent = 'codex'
                target_config_root = $layout.Config
                mutation_scope = 'target-agent-config-only'
                project_version = $projectVersion
                runtime_mode = 'auto-discovery'
                scope = 'registered-capabilities'
                completed_phases = @()
                unresolved_a_tools = @()
            }
            $request[$case.Field] = $case.Value
            $stateText = ($request | ConvertTo-Json -Depth 4) + "`n"
            [IO.File]::WriteAllText($statePath, $stateText, (New-Object Text.UTF8Encoding $false))

            $threw = $false
            try {
                $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                    -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules
            } catch {
                $threw = $true
                $errorMessage = $_.Exception.Message
            }

            Assert-True $threw
            Assert-True ($errorMessage.Contains('metadata is invalid'))
            Assert-False (Test-Path -LiteralPath $layout.Backup)
            Assert-False (Test-Path -LiteralPath $layout.Skill)
            Assert-False (Test-Path -LiteralPath $layout.Global)
        }
    }

    It 'rejects legacy or cross-config initial-index state before writes' {
        $cases = @(
            [pscustomobject]@{
                Name = 'legacy-v1'
                SchemaVersion = 1
                ConfigRootKind = 'current'
                MutationScope = 'target-agent-config-only'
            },
            [pscustomobject]@{
                Name = 'cross-config'
                SchemaVersion = 2
                ConfigRootKind = 'other'
                MutationScope = 'target-agent-config-only'
            },
            [pscustomobject]@{
                Name = 'cross-scope'
                SchemaVersion = 2
                ConfigRootKind = 'current'
                MutationScope = 'all-agent-configs'
            },
            [pscustomobject]@{
                Name = 'config-root-array'
                SchemaVersion = 2
                ConfigRootKind = 'array'
                MutationScope = 'target-agent-config-only'
            },
            [pscustomobject]@{
                Name = 'top-level-array'
                SchemaVersion = 2
                ConfigRootKind = 'current'
                MutationScope = 'target-agent-config-only'
                TopLevelArray = $true
            },
            [pscustomobject]@{
                Name = 'mutation-scope-array'
                SchemaVersion = 2
                ConfigRootKind = 'current'
                MutationScope = @('target-agent-config-only')
            },
            [pscustomobject]@{
                Name = 'schema-string'
                SchemaVersion = '2'
                ConfigRootKind = 'current'
                MutationScope = 'target-agent-config-only'
            },
            [pscustomobject]@{
                Name = 'status-array'
                SchemaVersion = 2
                ConfigRootKind = 'current'
                MutationScope = 'target-agent-config-only'
                ScalarField = 'status'
            },
            [pscustomobject]@{
                Name = 'target-agent-array'
                SchemaVersion = 2
                ConfigRootKind = 'current'
                MutationScope = 'target-agent-config-only'
                ScalarField = 'target_agent'
            },
            [pscustomobject]@{
                Name = 'request-id-array'
                SchemaVersion = 2
                ConfigRootKind = 'current'
                MutationScope = 'target-agent-config-only'
                ScalarField = 'request_id'
            },
            [pscustomobject]@{
                Name = 'project-version-array'
                SchemaVersion = 2
                ConfigRootKind = 'current'
                MutationScope = 'target-agent-config-only'
                ScalarField = 'project_version'
            },
            [pscustomobject]@{
                Name = 'runtime-mode-array'
                SchemaVersion = 2
                ConfigRootKind = 'current'
                MutationScope = 'target-agent-config-only'
                ScalarField = 'runtime_mode'
            },
            [pscustomobject]@{
                Name = 'scope-array'
                SchemaVersion = 2
                ConfigRootKind = 'current'
                MutationScope = 'target-agent-config-only'
                ScalarField = 'scope'
            }
        )

        foreach ($case in $cases) {
            $layout = New-InstallLayout ("invalid-index-scope-" + $case.Name)
            $statePath = Join-TestPath $layout.Config @('tool-routing-state', 'initial-index.json')
            New-Item -ItemType Directory -Path (Split-Path -Parent $statePath) -Force | Out-Null
            $targetConfigRoot = switch ($case.ConfigRootKind) {
                'current' { $layout.Config }
                'other' { Join-Path $layout.Root 'other-config' }
                'array' { ,@($layout.Config) }
                default { throw "Unknown test config-root kind: $($case.ConfigRootKind)" }
            }
            $request = [ordered]@{
                schema_version = $case.SchemaVersion
                request_id = [guid]::NewGuid().ToString('N')
                status = 'pending'
                target_agent = 'codex'
                target_config_root = $targetConfigRoot
                mutation_scope = $case.MutationScope
                project_version = $projectVersion
                runtime_mode = 'auto-discovery'
                scope = 'registered-capabilities'
                completed_phases = @()
                unresolved_a_tools = @()
            }
            if ($null -ne $case.PSObject.Properties['ScalarField']) {
                $field = [string]$case.ScalarField
                $request[$field] = ,@($request[$field])
            }
            $requestJson = $request | ConvertTo-Json -Depth 4
            $stateText = if ($null -ne $case.PSObject.Properties['TopLevelArray']) {
                "[`n$requestJson`n]`n"
            } else {
                $requestJson + "`n"
            }
            [IO.File]::WriteAllText(
                $statePath,
                $stateText,
                (New-Object Text.UTF8Encoding $false)
            )
            $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath))

            $threw = $false
            try {
                $null = & $installer -Target codex -UserProfile $layout.Profile -AllowCustomProfile `
                    -CodexHome $layout.Config -BackupRoot $layout.Backup
            } catch {
                $threw = $true
                $errorMessage = $_.Exception.Message
            }

            Assert-True $threw
            Assert-True ($errorMessage.Contains('metadata is invalid'))
            Assert-False (Test-Path -LiteralPath $layout.Backup)
            Assert-False (Test-Path -LiteralPath $layout.Skill)
            Assert-False (Test-Path -LiteralPath $layout.Global)
            Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($statePath))) $before
        }

        $multi = New-InstallLayout 'invalid-index-multi-target'
        $codexRoot = Join-Path $multi.Root 'codex-config'
        $claudeRoot = Join-Path $multi.Root 'claude-config'
        $zcodeRoot = Join-Path $multi.Root 'zcode-config'
        $codexSkill = Join-TestPath $codexRoot @('skills', 'tool-use-architecture')
        $transactionContainer = Get-SkillTransactionContainer -SkillPath $codexSkill
        $retainedTransaction = Join-Path $transactionContainer `
            ('txn-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $retainedTransaction -Force | Out-Null

        $claudeState = Join-TestPath $claudeRoot @('tool-routing-state', 'initial-index.json')
        New-Item -ItemType Directory -Path (Split-Path -Parent $claudeState) -Force | Out-Null
        $legacyRequest = [ordered]@{
            schema_version = 1
            request_id = [guid]::NewGuid().ToString('N')
            status = 'pending'
            target_agent = 'claude'
            project_version = $projectVersion
            runtime_mode = 'auto-discovery'
            scope = 'registered-capabilities'
            completed_phases = @()
            unresolved_a_tools = @()
        }
        [IO.File]::WriteAllText(
            $claudeState,
            (($legacyRequest | ConvertTo-Json -Depth 4) + "`n"),
            (New-Object Text.UTF8Encoding $false)
        )
        $legacyBefore = [Convert]::ToBase64String([IO.File]::ReadAllBytes($claudeState))

        $threw = $false
        try {
            $null = & $installer -Target all -UserProfile $multi.Profile -AllowCustomProfile `
                -CodexHome $codexRoot -ClaudeConfigDir $claudeRoot -ZcodeHome $zcodeRoot `
                -BackupRoot $multi.Backup
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('metadata is invalid'))
        Assert-True (Test-Path -LiteralPath $retainedTransaction -PathType Container)
        Assert-Equal ([Convert]::ToBase64String([IO.File]::ReadAllBytes($claudeState))) `
            $legacyBefore
        Assert-False (Test-Path -LiteralPath $multi.Backup)
        Assert-False (Test-Path -LiteralPath $codexSkill)
        Assert-False (Test-Path -LiteralPath (Join-Path $codexRoot 'AGENTS.md'))
        Assert-False (Test-Path -LiteralPath (
            Join-TestPath $claudeRoot @('skills', 'tool-routing-architecture')
        ))
        Assert-False (Test-Path -LiteralPath (Join-Path $claudeRoot 'CLAUDE.md'))
        Assert-False (Test-Path -LiteralPath $zcodeRoot)
    }

    It 'preflights every target and retained transaction before recovery writes' {
        $multi = New-InstallLayout 'recovery-preflight-all-targets'
        $codexRoot = Join-Path $multi.Root 'codex-config'
        $claudeRoot = Join-Path $multi.Root 'claude-config'
        $zcodeRoot = Join-Path $multi.Root 'zcode-config'
        $null = New-ToolIndexDependency $codexRoot
        $codexSkill = Join-TestPath $codexRoot @('skills', 'tool-use-architecture')
        $transactionContainer = Get-SkillTransactionContainer -SkillPath $codexSkill
        $retainedTransaction = Join-Path $transactionContainer `
            ('txn-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $retainedTransaction -Force | Out-Null

        $threw = $false
        try {
            $null = & $installer -Target all -UserProfile $multi.Profile -AllowCustomProfile `
                -CodexHome $codexRoot -ClaudeConfigDir $claudeRoot -ZcodeHome $zcodeRoot `
                -BackupRoot $multi.Backup -AddRuntimeRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('requires tool-index'))
        Assert-True (Test-Path -LiteralPath $retainedTransaction -PathType Container)
        Assert-False (Test-Path -LiteralPath $multi.Backup)
        Assert-False (Test-Path -LiteralPath $codexSkill)
        Assert-False (Test-Path -LiteralPath (Join-Path $codexRoot 'AGENTS.md'))
        Assert-False (Test-Path -LiteralPath $zcodeRoot)

        $multiple = New-InstallLayout 'multiple-retained-transactions'
        $container = Get-SkillTransactionContainer -SkillPath $multiple.Skill
        $first = Join-Path $container ('txn-' + [guid]::NewGuid().ToString('N'))
        $second = Join-Path $container ('txn-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $first -Force | Out-Null
        New-Item -ItemType Directory -Path $second -Force | Out-Null

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $multiple.Profile `
                -AllowCustomProfile -CodexHome $multiple.Config `
                -BackupRoot $multiple.Backup
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('Multiple retained skill transactions'))
        Assert-True (Test-Path -LiteralPath $first -PathType Container)
        Assert-True (Test-Path -LiteralPath $second -PathType Container)
        Assert-False (Test-Path -LiteralPath $multiple.Backup)
        Assert-False (Test-Path -LiteralPath $multiple.Skill)

        $crossTarget = New-InstallLayout 'cross-target-retained-preflight'
        $crossCodexRoot = Join-Path $crossTarget.Root 'codex-config'
        $crossClaudeRoot = Join-Path $crossTarget.Root 'claude-config'
        $crossZcodeRoot = Join-Path $crossTarget.Root 'zcode-config'
        $crossCodexSkill = Join-TestPath $crossCodexRoot @('skills', 'tool-use-architecture')
        $crossClaudeSkill = Join-TestPath $crossClaudeRoot @(
            'skills', 'tool-routing-architecture'
        )
        $codexContainer = Get-SkillTransactionContainer -SkillPath $crossCodexSkill
        $claudeContainer = Get-SkillTransactionContainer -SkillPath $crossClaudeSkill
        $codexTransaction = Join-Path $codexContainer `
            ('txn-' + [guid]::NewGuid().ToString('N'))
        $claudeTransaction = Join-Path $claudeContainer `
            ('txn-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $codexTransaction -Force | Out-Null
        New-Item -ItemType Directory -Path $claudeTransaction -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $claudeTransaction 'unexpected.txt'), 'keep')

        $threw = $false
        try {
            $null = & $installer -Target all -UserProfile $crossTarget.Profile `
                -AllowCustomProfile -CodexHome $crossCodexRoot `
                -ClaudeConfigDir $crossClaudeRoot -ZcodeHome $crossZcodeRoot `
                -BackupRoot $crossTarget.Backup
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('has data but no journal'))
        Assert-True (Test-Path -LiteralPath $codexTransaction -PathType Container)
        Assert-True (Test-Path -LiteralPath $claudeTransaction -PathType Container)
        Assert-False (Test-Path -LiteralPath $crossTarget.Backup)
        Assert-False (Test-Path -LiteralPath $crossCodexSkill)
        Assert-False (Test-Path -LiteralPath $crossClaudeSkill)
        Assert-False (Test-Path -LiteralPath $crossZcodeRoot)
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

    It 'rejects AddGlobalRules before target or backup writes' {
        $layout = New-InstallLayout 'legacy-switch'

        $threw = $false
        try {
            $null = & $installer -Target codex -UserProfile $layout.Profile `
                -AllowCustomProfile -CodexHome $layout.Config `
                -BackupRoot $layout.Backup -AddGlobalRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('-AddGlobalRules is no longer accepted'))
        Assert-False (Test-Path -LiteralPath $layout.Config)
        Assert-False (Test-Path -LiteralPath $layout.Backup)
    }

    It 'migrates a legacy managed block without losing surrounding user text' {
        $layout = New-InstallLayout 'legacy-marker-migration'
        $null = New-ToolIndexDependency $layout.Config
        New-Item -ItemType Directory -Path (Split-Path -Parent $layout.Global) -Force | Out-Null

        $snippetPath = Join-TestPath $repoRoot @('examples', 'AGENTS.md.snippet')
        $legacySnippet = [IO.File]::ReadAllText($snippetPath)
        $legacySnippet = $legacySnippet.Replace('`tool-routing-architecture`', '`tool-use-architecture`')
        $legacySnippet = $legacySnippet.Replace(
            'This installation uses `auto-discovery`;',
            "LEGACY_RUNTIME_SENTINEL`n`nThis installation uses `auto-discovery`;"
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

Describe 'scripts/install-remote.ps1' {
    BeforeEach {
        $script:CreatedTestRoots.Clear()
    }

    AfterEach {
        foreach ($root in @($script:CreatedTestRoots.ToArray())) {
            Remove-TestDirectory -Path $root
        }
        $script:CreatedTestRoots.Clear()
    }

    It 'rejects a missing target before staging or target writes' {
        $layout = New-InstallLayout 'remote-missing-target'
        $threw = $false

        try {
            $null = & $remoteInstaller -SourceRoot $repoRoot `
                -StagingParent $layout.Root -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('-Target is required'))
        Assert-False (Test-Path -LiteralPath $layout.Config)
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-Equal @(Get-ChildItem -LiteralPath $layout.Root -Directory | Where-Object {
            $_.Name -like 'agent-tool-routing-*'
        }).Count 0
    }

    It 'installs only the verified Codex payload without global rules by default' {
        $fixture = New-CurrentRemoteFixture 'remote-codex-source'
        $bootstrap = $fixture.Installer
        $layout = New-InstallLayout 'remote-codex'
        $claudeRoot = Join-Path $layout.Root 'claude-config'
        $zcodeRoot = Join-Path $layout.Root 'zcode-config'

        $null = & $bootstrap -Target codex -SourceRoot $fixture.SourceRoot `
            -StagingParent $layout.Root -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -ClaudeConfigDir $claudeRoot -ZcodeHome $zcodeRoot `
            -BackupRoot $layout.Backup

        Assert-Equal ([IO.File]::ReadAllText((Join-Path $layout.Skill 'VERSION')).Trim()) `
            $projectVersion
        Assert-False (Test-Path -LiteralPath $layout.Global)
        Assert-False (Test-Path -LiteralPath $claudeRoot)
        Assert-False (Test-Path -LiteralPath $zcodeRoot)
        Assert-Equal @(Get-ChildItem -LiteralPath $layout.Root -Directory | Where-Object {
            $_.Name -like 'agent-tool-routing-*'
        }).Count 0
    }

    It 'writes onboarding only when explicitly requested and rejects conflicting switches' {
        $fixture = New-CurrentRemoteFixture 'remote-onboarding-source'
        $bootstrap = $fixture.Installer
        $layout = New-InstallLayout 'remote-onboarding'

        $null = & $bootstrap -Target codex -SourceRoot $fixture.SourceRoot `
            -StagingParent $layout.Root -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $layout.Config -BackupRoot $layout.Backup -AddOnboardingRules

        Assert-True ([IO.File]::ReadAllText($layout.Global).Contains('Tool Onboarding Gate'))

        $conflict = New-InstallLayout 'remote-onboarding-conflict'
        $threw = $false
        try {
            $null = & $bootstrap -Target codex -SourceRoot $fixture.SourceRoot `
                -StagingParent $conflict.Root -UserProfile $conflict.Profile -AllowCustomProfile `
                -CodexHome $conflict.Config -BackupRoot $conflict.Backup `
                -AddOnboardingRules -SkipOnboardingRules
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('cannot be combined'))
        Assert-False (Test-Path -LiteralPath $conflict.Config)
        Assert-False (Test-Path -LiteralPath $conflict.Backup)
    }

    It 'queues routing initialization for all targets' {
        $fixture = New-CurrentRemoteFixture 'remote-initialize-routing-source'
        $bootstrap = $fixture.Installer
        $layout = New-InstallLayout 'remote-initialize-routing'
        $codexRoot = Join-Path $layout.Root 'codex-config'
        $claudeRoot = Join-Path $layout.Root 'claude-config'
        $zcodeRoot = Join-Path $layout.Root 'zcode-config'

        $output = & $bootstrap -Target all -SourceRoot $fixture.SourceRoot `
            -StagingParent $layout.Root -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome $codexRoot -ClaudeConfigDir $claudeRoot -ZcodeHome $zcodeRoot `
            -BackupRoot $layout.Backup -InitializeRouting | Out-String

        $targets = @(
            [pscustomobject]@{
                Name = 'codex'
                Root = $codexRoot
                Skill = Join-TestPath $codexRoot @('skills', 'tool-use-architecture')
                Global = Join-Path $codexRoot 'AGENTS.md'
            },
            [pscustomobject]@{
                Name = 'claude'
                Root = $claudeRoot
                Skill = Join-TestPath $claudeRoot @('skills', 'tool-routing-architecture')
                Global = Join-Path $claudeRoot 'CLAUDE.md'
            },
            [pscustomobject]@{
                Name = 'zcode'
                Root = $zcodeRoot
                Skill = Join-TestPath $zcodeRoot @('skills', 'tool-routing-architecture')
                Global = Join-Path $zcodeRoot 'AGENTS.md'
            }
        )
        foreach ($target in $targets) {
            Assert-True (Test-Path -LiteralPath $target.Skill)
            Assert-PendingInitialIndexState -ConfigRoot $target.Root -TargetAgent $target.Name
            Assert-False (Test-Path -LiteralPath $target.Global)
            Assert-False (Test-Path -LiteralPath (
                Join-TestPath $target.Root @('skills', 'tool-index')
            ))
        }
        Assert-True ($output.Contains('must not interrupt or take priority over ordinary work'))
    }

    It 'forwards Claude Code and zcode targets without installing other agents' {
        $fixture = New-CurrentRemoteFixture 'remote-forward-source'
        $bootstrap = $fixture.Installer
        foreach ($agent in @('claude', 'zcode')) {
            $layout = New-InstallLayout ("remote-$agent")
            $codexRoot = Join-Path $layout.Root 'codex-config'
            $claudeRoot = Join-Path $layout.Root 'claude-config'
            $zcodeRoot = Join-Path $layout.Root 'zcode-config'
            $arguments = @{
                Target = $agent
                SourceRoot = $fixture.SourceRoot
                StagingParent = $layout.Root
                UserProfile = $layout.Profile
                AllowCustomProfile = $true
                BackupRoot = $layout.Backup
                CodexHome = $codexRoot
                ClaudeConfigDir = $claudeRoot
                ZcodeHome = $zcodeRoot
            }
            if ($agent -eq 'claude') {
                $config = $claudeRoot
                $unselectedRoots = @($codexRoot, $zcodeRoot)
                $globalFile = Join-Path $claudeRoot 'CLAUDE.md'
            } else {
                $config = $zcodeRoot
                $unselectedRoots = @($codexRoot, $claudeRoot)
                $globalFile = Join-Path $zcodeRoot 'AGENTS.md'
            }

            $null = & $bootstrap @arguments

            $skill = Join-TestPath $config @('skills', 'tool-routing-architecture')
            Assert-Equal ([IO.File]::ReadAllText((Join-Path $skill 'VERSION')).Trim()) `
                $projectVersion
            Assert-False (Test-Path -LiteralPath $globalFile)
            Assert-False (Test-Path -LiteralPath (Join-Path $config 'skills/tool-use-architecture'))
            foreach ($unselectedRoot in $unselectedRoots) {
                Assert-False (Test-Path -LiteralPath $unselectedRoot)
            }
        }
    }

    It 'performs verification but no target writes in remote WhatIf mode' {
        $fixture = New-CurrentRemoteFixture 'remote-what-if-source'
        $bootstrap = $fixture.Installer
        $layout = New-InstallLayout 'remote-what-if'

        $null = & $bootstrap -Target all -SourceRoot $fixture.SourceRoot `
            -StagingParent $layout.Root -UserProfile $layout.Profile -AllowCustomProfile `
            -CodexHome (Join-Path $layout.Root 'codex') `
            -ClaudeConfigDir (Join-Path $layout.Root 'claude') `
            -ZcodeHome (Join-Path $layout.Root 'zcode') `
            -BackupRoot $layout.Backup -WhatIf

        Assert-False (Test-Path -LiteralPath (Join-Path $layout.Root 'codex'))
        Assert-False (Test-Path -LiteralPath (Join-Path $layout.Root 'claude'))
        Assert-False (Test-Path -LiteralPath (Join-Path $layout.Root 'zcode'))
        Assert-Equal @(Get-ChildItem -LiteralPath $layout.Root -Directory | Where-Object {
            $_.Name -like 'agent-tool-routing-*'
        }).Count 0
    }

    It 'rejects a modified payload before creating any target or backup' {
        $fixture = New-CurrentRemoteFixture 'remote-payload-tamper'
        $bootstrap = $fixture.Installer
        $source = $fixture.SourceRoot
        $layout = New-InstallLayout 'remote-payload-target'
        [IO.File]::AppendAllText((Join-Path $source 'SKILL.md'), "`ntampered`n")
        $threw = $false
        $errorMessage = $null

        try {
            $null = & $bootstrap -Target codex -SourceRoot $source `
                -StagingParent $layout.Root -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains("Payload verification failed for 'SKILL.md'"))
        Assert-False (Test-Path -LiteralPath $layout.Config)
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-Equal @(Get-ChildItem -LiteralPath $layout.Root -Directory | Where-Object {
            $_.Name -like 'agent-tool-routing-*'
        }).Count 0
    }

    It 'rejects a modified manifest before reading payload files' {
        $fixture = New-CurrentRemoteFixture 'remote-manifest-tamper'
        $bootstrap = $fixture.Installer
        $source = $fixture.SourceRoot
        $layout = New-InstallLayout 'remote-manifest-target'
        [IO.File]::AppendAllText(
            (Join-TestPath $source @('scripts', 'install-manifest.json')),
            " `n"
        )
        $threw = $false
        $errorMessage = $null

        try {
            $null = & $bootstrap -Target codex -SourceRoot $source `
                -StagingParent $layout.Root -UserProfile $layout.Profile -AllowCustomProfile `
                -CodexHome $layout.Config -BackupRoot $layout.Backup
        } catch {
            $threw = $true
            $errorMessage = $_.Exception.Message
        }

        Assert-True $threw
        Assert-True ($errorMessage.Contains('Install manifest SHA-256 verification failed'))
        Assert-False (Test-Path -LiteralPath $layout.Config)
        Assert-False (Test-Path -LiteralPath $layout.Backup)
        Assert-Equal @(Get-ChildItem -LiteralPath $layout.Root -Directory | Where-Object {
            $_.Name -like 'agent-tool-routing-*'
        }).Count 0
    }
}
