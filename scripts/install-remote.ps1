[CmdletBinding()]
param(
    [ValidateSet('all', 'codex', 'claude', 'zcode')]
    [string]$Target = 'all',

    [switch]$SkipOnboardingRules,

    [switch]$AddRuntimeRules,

    [switch]$InitializeRouting,

    [string]$BackupRoot,

    [string]$UserProfile = [Environment]::GetFolderPath('UserProfile'),

    [switch]$AllowCustomProfile,

    [string]$CodexHome,

    [string]$ClaudeConfigDir,

    [string]$ZcodeHome,

    [switch]$AllowReparsePoints,

    [switch]$WhatIf,

    # A verified local repository is useful for offline installs and CI.
    [string]$SourceRoot,

    [string]$StagingParent = [IO.Path]::GetTempPath()
)

$ErrorActionPreference = 'Stop'
if ($InitializeRouting -and $SkipOnboardingRules) {
    throw '-InitializeRouting requires onboarding rules; remove -SkipOnboardingRules.'
}
$ReleaseVersion = '0.2.1'
$Repository = 'wmqfl861/agent-tool-routing-skill'
$ManifestRelativePath = 'scripts/install-manifest.json'
$ManifestSha256 = 'a5243dfee082067fb909fee3dbc53ace7c345ef377411cbffc1c9022fda5e290'
$RequiredPayloadPaths = @(
    'VERSION',
    'SKILL.md',
    'agents/openai.yaml',
    'examples/AGENTS.md.snippet',
    'examples/CLAUDE.md.snippet',
    'examples/category-skill.example.md',
    'examples/tool-index.SKILL.md',
    'examples/tool-specific-skill.example.md',
    'references/authoring.md',
    'references/initial-index.md',
    'references/lifecycle.md',
    'references/managed-inventory.md',
    'references/route-tests.md',
    'references/runtime-adapters.md',
    'scripts/install.ps1'
)
$MaximumManifestBytes = 131072
$MaximumPayloadBytes = 5242880
$DownloadTimeoutSeconds = 60
$DirectorySeparator = [IO.Path]::DirectorySeparatorChar
$IsWindowsPlatform = $DirectorySeparator -eq [char]'\'
$IsMacOSPlatform = (-not $IsWindowsPlatform) -and
    [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::OSX
    )
$PathComparison = if ($IsWindowsPlatform -or $IsMacOSPlatform) {
    [StringComparison]::OrdinalIgnoreCase
} else {
    [StringComparison]::Ordinal
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    while (($full.Length -gt $root.Length) -and
        (($full[$full.Length - 1] -eq [IO.Path]::DirectorySeparatorChar) -or
            ($full[$full.Length - 1] -eq [IO.Path]::AltDirectorySeparatorChar))) {
        $full = $full.Substring(0, $full.Length - 1)
    }
    return $full
}

function Get-ChildPathPrefix {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = Get-NormalizedFullPath -Path $Path
    if ($full[$full.Length - 1] -eq [IO.Path]::DirectorySeparatorChar) {
        return $full
    }
    return $full + [IO.Path]::DirectorySeparatorChar
}

function Get-ContainedPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains('\')) {
        throw "Manifest contains an unsafe relative path: '$RelativePath'."
    }
    $segments = @($RelativePath.Split('/'))
    if (($segments.Count -eq 0) -or
        @($segments | Where-Object {
            [string]::IsNullOrWhiteSpace($_) -or
            ($_ -eq '.') -or
            ($_ -eq '..') -or
            ($_ -notmatch '^[A-Za-z0-9._-]+$')
        }).Count -gt 0) {
        throw "Manifest contains an unsafe relative path: '$RelativePath'."
    }

    $candidate = $Root
    foreach ($segment in $segments) {
        $candidate = Join-Path $candidate $segment
    }
    $rootFull = Get-NormalizedFullPath -Path $Root
    $candidateFull = [IO.Path]::GetFullPath($candidate)
    $prefix = Get-ChildPathPrefix -Path $rootFull
    if (-not $candidateFull.StartsWith($prefix, $PathComparison)) {
        throw "Manifest path '$RelativePath' escapes staging root '$rootFull'."
    }
    return $candidateFull
}

function Assert-OrdinaryFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $linkType = $item.PSObject.Properties['LinkType']
    $isLink = (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
        (($null -ne $linkType) -and (-not [string]::IsNullOrEmpty([string]$linkType.Value)))
    if ($isLink -or $item.PSIsContainer) {
        throw "$Purpose must be an ordinary file: '$Path'."
    }
}

function Assert-OrdinaryDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $linkType = $item.PSObject.Properties['LinkType']
    $isLink = (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
        (($null -ne $linkType) -and (-not [string]::IsNullOrEmpty([string]$linkType.Value)))
    if ($isLink -or (-not $item.PSIsContainer)) {
        throw "$Purpose must be an ordinary directory: '$Path'."
    }
}

function Invoke-VerifiedDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][long]$MaximumBytes
    )

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $cancellation = $null
        $handler = $null
        $client = $null
        $response = $null
        try {
            $cancellation = New-Object System.Threading.CancellationTokenSource
            $cancellation.CancelAfter([TimeSpan]::FromSeconds($DownloadTimeoutSeconds))
            $handler = New-Object System.Net.Http.HttpClientHandler
            $handler.AllowAutoRedirect = $false
            $client = New-Object System.Net.Http.HttpClient -ArgumentList $handler
            $client.Timeout = [TimeSpan]::FromSeconds($DownloadTimeoutSeconds)
            $client.MaxResponseContentBufferSize = [Math]::Max([long]1, $MaximumBytes)
            $response = $client.GetAsync(
                $Uri,
                [System.Net.Http.HttpCompletionOption]::ResponseContentRead,
                $cancellation.Token
            ).GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) {
                throw "Download failed with HTTP status $([int]$response.StatusCode): '$Uri'."
            }
            $contentLength = $response.Content.Headers.ContentLength
            if (($null -ne $contentLength) -and ([long]$contentLength -gt $MaximumBytes)) {
                throw "Download exceeds $MaximumBytes bytes: '$Uri'."
            }
            $content = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            if ($content.LongLength -gt $MaximumBytes) {
                throw "Download exceeds $MaximumBytes bytes: '$Uri'."
            }
            [IO.File]::WriteAllBytes($Destination, $content)
            return
        } catch {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
            if ($attempt -eq 3) {
                throw
            }
            Start-Sleep -Milliseconds (200 * $attempt)
        } finally {
            if ($null -ne $response) {
                $response.Dispose()
            }
            if ($null -ne $client) {
                $client.Dispose()
            } elseif ($null -ne $handler) {
                $handler.Dispose()
            }
            if ($null -ne $cancellation) {
                $cancellation.Dispose()
            }
        }
    }
}

function ConvertTo-RawUri {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUri,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $escaped = @($RelativePath.Split('/') | ForEach-Object { [Uri]::EscapeDataString($_) })
    return $BaseUri.TrimEnd('/') + '/' + ($escaped -join '/')
}

function Remove-VerifiedStagingDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $pathFull = [IO.Path]::GetFullPath($Path)
    $parentFull = Get-NormalizedFullPath -Path $Parent
    $prefix = Get-ChildPathPrefix -Path $parentFull
    if ((Split-Path -Leaf $pathFull) -notlike 'agent-tool-routing-*' -or
        -not $pathFull.StartsWith($prefix, $PathComparison)) {
        throw "Refusing to remove unverified staging path '$pathFull'."
    }
    Assert-OrdinaryDirectory -Path $parentFull -Purpose 'Staging parent cleanup'
    Assert-OrdinaryDirectory -Path $pathFull -Purpose 'Remote installer staging cleanup'
    Remove-Item -LiteralPath $pathFull -Recurse -Force -ErrorAction Stop
}

if ((-not $IsWindowsPlatform) -and
    ($PSVersionTable.PSVersion -lt [version]'7.2')) {
    throw "PowerShell 7.2 or later is required on Linux and macOS. Found $($PSVersionTable.PSVersion)."
}
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
if ($ManifestSha256 -notmatch '^[0-9a-f]{64}$') {
    throw 'Remote installer manifest hash is not configured.'
}

$stagingParentFull = Get-NormalizedFullPath -Path $StagingParent
if (-not (Test-Path -LiteralPath $stagingParentFull -PathType Container)) {
    throw "Staging parent must already exist as a directory: '$stagingParentFull'."
}
Assert-OrdinaryDirectory -Path $stagingParentFull -Purpose 'Staging parent'
$workRoot = Join-Path $stagingParentFull ('agent-tool-routing-' + [guid]::NewGuid().ToString('N'))
$workRootFull = [IO.Path]::GetFullPath($workRoot)
$workPrefix = Get-ChildPathPrefix -Path $stagingParentFull
if (-not $workRootFull.StartsWith($workPrefix, $PathComparison)) {
    throw "Computed staging path '$workRootFull' escapes '$stagingParentFull'."
}
New-Item -ItemType Directory -Path $workRootFull | Out-Null
Assert-OrdinaryDirectory -Path $workRootFull -Purpose 'Remote installer staging'

try {
    $manifestPath = Join-Path $workRootFull 'install-manifest.json'
    if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
        $rawBaseUri = "https://raw.githubusercontent.com/$Repository/v$ReleaseVersion"
        Invoke-VerifiedDownload -Uri (ConvertTo-RawUri $rawBaseUri $ManifestRelativePath) `
            -Destination $manifestPath -MaximumBytes $MaximumManifestBytes
    } else {
        $sourceRootFull = [IO.Path]::GetFullPath($SourceRoot)
        $sourceManifest = Get-ContainedPath -Root $sourceRootFull -RelativePath $ManifestRelativePath
        Assert-OrdinaryFile -Path $sourceManifest -Purpose 'Local install manifest'
        Copy-Item -LiteralPath $sourceManifest -Destination $manifestPath -Force
        $rawBaseUri = $null
    }

    if ((Get-Item -LiteralPath $manifestPath -Force).Length -gt $MaximumManifestBytes) {
        throw "Install manifest exceeds $MaximumManifestBytes bytes."
    }
    if ((Get-Sha256 $manifestPath) -ne $ManifestSha256) {
        throw 'Install manifest SHA-256 verification failed.'
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $topLevelProperties = @($manifest.PSObject.Properties.Name)
    $expectedTopLevelProperties = @('schema_version', 'repository', 'version', 'files')
    if (($topLevelProperties.Count -ne $expectedTopLevelProperties.Count) -or
        @($topLevelProperties | Where-Object { $_ -notin $expectedTopLevelProperties }).Count -gt 0 -or
        (($manifest.schema_version -isnot [int]) -and
            ($manifest.schema_version -isnot [long])) -or
        ($manifest.schema_version -ne 1) -or
        ($manifest.repository -ne $Repository) -or
        ($manifest.version -ne $ReleaseVersion) -or
        ($null -eq $manifest.files) -or
        (@($manifest.files).Count -eq 0)) {
        throw 'Install manifest metadata is invalid or does not match this bootstrap release.'
    }

    $repoRoot = Join-Path $workRootFull 'repository'
    New-Item -ItemType Directory -Path $repoRoot | Out-Null
    if (@($manifest.files).Count -ne $RequiredPayloadPaths.Count) {
        throw 'Install manifest does not contain the exact required payload set.'
    }
    $required = New-Object 'System.Collections.Generic.HashSet[string]' `
        ([StringComparer]::OrdinalIgnoreCase)
    foreach ($requiredPath in $RequiredPayloadPaths) {
        [void]$required.Add($requiredPath)
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' `
        ([StringComparer]::OrdinalIgnoreCase)
    [long]$totalPayloadBytes = 0
    foreach ($entry in @($manifest.files)) {
        $entryPropertyNames = @($entry.PSObject.Properties.Name)
        $expectedEntryProperties = @('path', 'sha256', 'size')
        if (($entryPropertyNames.Count -ne $expectedEntryProperties.Count) -or
            @($entryPropertyNames | Where-Object { $_ -notin $expectedEntryProperties }).Count -gt 0) {
            throw 'Install manifest entry contains unexpected properties.'
        }
        foreach ($propertyName in $expectedEntryProperties) {
            if ($null -eq $entry.PSObject.Properties[$propertyName]) {
                throw "Install manifest entry is missing '$propertyName'."
            }
        }
        $relativePath = [string]$entry.path
        $expectedHash = ([string]$entry.sha256).ToLowerInvariant()
        $expectedSize = [long]$entry.size
        if (-not $seen.Add($relativePath)) {
            throw "Install manifest contains duplicate path '$relativePath'."
        }
        if (-not $required.Contains($relativePath)) {
            throw "Install manifest contains unexpected path '$relativePath'."
        }
        if (($entry.size -isnot [int]) -and ($entry.size -isnot [long])) {
            throw "Install manifest size must be an integer: '$relativePath'."
        }
        if (($expectedHash -notmatch '^[0-9a-f]{64}$') -or ($expectedSize -lt 0)) {
            throw "Install manifest entry is invalid: '$relativePath'."
        }
        $totalPayloadBytes += $expectedSize
        if ($totalPayloadBytes -gt $MaximumPayloadBytes) {
            throw "Install payload exceeds $MaximumPayloadBytes bytes."
        }

        $destination = Get-ContainedPath -Root $repoRoot -RelativePath $relativePath
        $destinationParent = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
            Invoke-VerifiedDownload -Uri (ConvertTo-RawUri $rawBaseUri $relativePath) `
                -Destination $destination -MaximumBytes $expectedSize
        } else {
            $source = Get-ContainedPath -Root $sourceRootFull -RelativePath $relativePath
            Assert-OrdinaryFile -Path $source -Purpose "Local payload '$relativePath'"
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }

        $actualSize = (Get-Item -LiteralPath $destination -Force).Length
        if (($actualSize -ne $expectedSize) -or ((Get-Sha256 $destination) -ne $expectedHash)) {
            throw "Payload verification failed for '$relativePath'."
        }
    }
    foreach ($requiredPath in $RequiredPayloadPaths) {
        if (-not $seen.Contains($requiredPath)) {
            throw "Install manifest is missing required path '$requiredPath'."
        }
    }

    $downloadedVersion = [IO.File]::ReadAllText((Join-Path $repoRoot 'VERSION')).Trim()
    if ($downloadedVersion -ne $ReleaseVersion) {
        throw "Downloaded VERSION '$downloadedVersion' does not match '$ReleaseVersion'."
    }
    $installer = Join-Path $repoRoot 'scripts/install.ps1'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        throw "Verified payload does not contain installer: '$installer'."
    }

    $installerArguments = @{
        Target = $Target
        UserProfile = $UserProfile
    }
    if (-not $SkipOnboardingRules) {
        $installerArguments.Add('AddOnboardingRules', $true)
    }
    if ($AddRuntimeRules) {
        $installerArguments.Add('AddRuntimeRules', $true)
    }
    if ($InitializeRouting) {
        $installerArguments.Add('InitializeRouting', $true)
    }
    if (-not [string]::IsNullOrWhiteSpace($BackupRoot)) {
        $installerArguments.Add('BackupRoot', $BackupRoot)
    }
    if ($AllowCustomProfile) {
        $installerArguments.Add('AllowCustomProfile', $true)
    }
    if (-not [string]::IsNullOrWhiteSpace($CodexHome)) {
        $installerArguments.Add('CodexHome', $CodexHome)
    }
    if (-not [string]::IsNullOrWhiteSpace($ClaudeConfigDir)) {
        $installerArguments.Add('ClaudeConfigDir', $ClaudeConfigDir)
    }
    if (-not [string]::IsNullOrWhiteSpace($ZcodeHome)) {
        $installerArguments.Add('ZcodeHome', $ZcodeHome)
    }
    if ($AllowReparsePoints) {
        $installerArguments.Add('AllowReparsePoints', $true)
    }
    if ($WhatIf) {
        $installerArguments.Add('WhatIf', $true)
    }

    & $installer @installerArguments
} finally {
    try {
        Remove-VerifiedStagingDirectory -Path $workRootFull -Parent $stagingParentFull
    } catch {
        Write-Warning "Could not remove verified staging directory '$workRootFull': $($_.Exception.Message)"
    }
}
