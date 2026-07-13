[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('all', 'codex', 'claude', 'zcode')]
    [string]$Target = 'all',

    [switch]$AddGlobalRules,

    [switch]$AddOnboardingRules,

    [switch]$AddRuntimeRules,

    [switch]$InitializeRouting,

    # This is a parent directory. Each invocation creates a unique install-* snapshot below it.
    [string]$BackupRoot,

    [string]$UserProfile = [Environment]::GetFolderPath('UserProfile'),

    [switch]$AllowCustomProfile,

    [string]$CodexHome,

    [string]$ClaudeConfigDir,

    [string]$ZcodeHome,

    [switch]$AllowReparsePoints
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$VersionSource = Join-Path $RepoRoot 'VERSION'
$SkillSource = Join-Path $RepoRoot 'SKILL.md'
$AgentsSource = Join-Path $RepoRoot 'agents'
$ReferencesSource = Join-Path $RepoRoot 'references'
$RequiredReferenceFiles = @(
    'lifecycle.md',
    'authoring.md',
    'initial-index.md',
    'runtime-adapters.md',
    'route-tests.md'
)
$ExamplesSource = Join-Path $RepoRoot 'examples'
$RequiredExampleFiles = @(
    'AGENTS.md.snippet',
    'CLAUDE.md.snippet',
    'tool-index.SKILL.md',
    'category-skill.example.md',
    'tool-specific-skill.example.md'
)
$MaximumIndexRequestBytes = 131072
$DirectorySeparator = [System.IO.Path]::DirectorySeparatorChar
$IsWindowsPlatform = $DirectorySeparator -eq [char]'\'
$IsMacOSPlatform = (-not $IsWindowsPlatform) -and
    [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::OSX
    )
if ((-not $IsWindowsPlatform) -and ($PSVersionTable.PSVersion -lt [version]'7.2')) {
    throw "PowerShell 7.2 or later is required on Linux and macOS. Found $($PSVersionTable.PSVersion)."
}
$PathComparison = if ($IsWindowsPlatform -or $IsMacOSPlatform) {
    [System.StringComparison]::OrdinalIgnoreCase
} else {
    [System.StringComparison]::Ordinal
}

$LegacyStart = '<!-- agent-tool-routing-skill:start -->'
$LegacyEnd = '<!-- agent-tool-routing-skill:end -->'
$RuntimeStart = '<!-- agent-tool-routing-skill:runtime:start -->'
$RuntimeEnd = '<!-- agent-tool-routing-skill:runtime:end -->'
$OnboardingStart = '<!-- agent-tool-routing-skill:onboarding:start -->'
$OnboardingEnd = '<!-- agent-tool-routing-skill:onboarding:end -->'

function Test-IsFileSystemLink {
    param([Parameter(Mandatory = $true)][object]$Item)

    $linkTargetProperty = $Item.PSObject.Properties['LinkTarget']
    if (($null -ne $linkTargetProperty) -and
        (-not [string]::IsNullOrEmpty([string]$linkTargetProperty.Value))) {
        return $true
    }
    if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return $true
    }
    $linkTypeProperty = $Item.PSObject.Properties['LinkType']
    return ($null -ne $linkTypeProperty) -and
        (-not [string]::IsNullOrEmpty([string]$linkTypeProperty.Value))
}

function Get-FileSystemItemIncludingBrokenLink {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (($null -ne $item) -or $IsWindowsPlatform) {
        return $item
    }

    # The PowerShell provider returns no item for a dangling POSIX symlink.
    # FileInfo.LinkTarget uses lstat/readlink semantics and can still identify it.
    try {
        $linkItem = [System.IO.FileInfo]::new([System.IO.Path]::GetFullPath($Path))
        if (-not [string]::IsNullOrEmpty($linkItem.LinkTarget)) {
            return $linkItem
        }
    } catch {
        throw "Cannot inspect path '$Path' while checking for symbolic links. $($_.Exception.Message)"
    }

    return $null
}

function Get-FinalExistingPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not $IsWindowsPlatform) {
        $full = [System.IO.Path]::GetFullPath($Path)
        $root = [System.IO.Path]::GetPathRoot($full)
        $current = $root
        $relative = $full.Substring($root.Length)
        $segments = @($relative.Split(
            [char[]]@($DirectorySeparator),
            [System.StringSplitOptions]::RemoveEmptyEntries
        ))

        foreach ($segment in $segments) {
            $next = Join-Path $current $segment
            $item = Get-FileSystemItemIncludingBrokenLink -Path $next
            if ($null -eq $item) {
                throw "Path component '$next' disappeared while validating path '$Path'."
            }
            if (Test-IsFileSystemLink -Item $item) {
                try {
                    $resolved = $item.ResolveLinkTarget($true)
                } catch {
                    throw "Cannot resolve symbolic link '$next' while validating path '$Path'. $($_.Exception.Message)"
                }
                if (($null -eq $resolved) -or (-not $resolved.Exists)) {
                    throw "Cannot resolve symbolic link '$next' while validating path '$Path'."
                }
                $current = $resolved.FullName
            } else {
                $current = $item.FullName
            }
        }
        return [System.IO.Path]::GetFullPath($current)
    }

    if (-not ('AgentToolRouting.NativePath' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace AgentToolRouting {
    public static class NativePath {
        private const uint FileFlagBackupSemantics = 0x02000000;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string fileName,
            uint desiredAccess,
            FileShare shareMode,
            IntPtr securityAttributes,
            FileMode creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandle(
            SafeFileHandle file,
            StringBuilder path,
            uint pathLength,
            uint flags);

        public static string GetFinalPath(string path) {
            using (SafeFileHandle handle = CreateFile(
                path,
                0,
                FileShare.ReadWrite | FileShare.Delete,
                IntPtr.Zero,
                FileMode.Open,
                FileFlagBackupSemantics,
                IntPtr.Zero)) {
                if (handle.IsInvalid) {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }

                var buffer = new StringBuilder(512);
                uint length = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0);
                if (length == 0) {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
                if (length >= buffer.Capacity) {
                    buffer = new StringBuilder((int)length + 1);
                    length = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0);
                    if (length == 0 || length >= buffer.Capacity) {
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                    }
                }

                string result = buffer.ToString();
                if (result.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) {
                    return @"\\" + result.Substring(8);
                }
                if (result.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase) &&
                    result.Length >= 6 && result[5] == ':') {
                    return result.Substring(4);
                }
                return result;
            }
        }
    }
}
'@
    }
    $resolved = [AgentToolRouting.NativePath]::GetFinalPath($Path)
    if ($resolved.StartsWith('\\', [System.StringComparison]::Ordinal)) {
        throw "Network-backed Windows paths are not supported: '$Path'. Use a local drive path."
    }
    return $resolved
}

function Normalize-RootPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($IsWindowsPlatform) {
        $namespacePath = $Path.Replace('/', '\')
        foreach ($prefix in @('\\?\', '\\.\', '\??\', '\\??\')) {
            if ($namespacePath.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
                throw "Windows device-namespace paths are not supported: '$Path'. Use a local drive path."
            }
        }
        if ($namespacePath.StartsWith('\\', [System.StringComparison]::Ordinal)) {
            throw "UNC paths are not supported: '$Path'. Use a local drive path."
        }
    }

    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    while (($full.Length -gt $root.Length) -and
        (($full[$full.Length - 1] -eq [char]'\') -or ($full[$full.Length - 1] -eq [char]'/'))) {
        $full = $full.Substring(0, $full.Length - 1)
    }

    return $full
}

function Get-ComparisonPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = Normalize-RootPath -Path $Path
    # Expand aliases such as Windows 8.3 names from the nearest existing
    # ancestor, then append any not-yet-created path segments. Keep this path
    # comparison-only so reparse checks still inspect the caller's actual path.
    $remaining = New-Object System.Collections.Generic.Stack[string]
    $candidate = $full
    $candidateItem = Get-FileSystemItemIncludingBrokenLink -Path $candidate
    while ($null -eq $candidateItem) {
        $leaf = [System.IO.Path]::GetFileName($candidate)
        $parent = [System.IO.Path]::GetDirectoryName($candidate)
        if ([string]::IsNullOrEmpty($leaf) -or [string]::IsNullOrEmpty($parent) -or
            [string]::Equals($parent, $candidate, $PathComparison)) {
            break
        }
        $remaining.Push($leaf)
        $candidate = $parent
        $candidateItem = Get-FileSystemItemIncludingBrokenLink -Path $candidate
    }
    if ($null -ne $candidateItem) {
        $canonical = Get-FinalExistingPath -Path $candidate
        while ($remaining.Count -gt 0) {
            $canonical = Join-Path $canonical $remaining.Pop()
        }
        $full = [System.IO.Path]::GetFullPath($canonical)
    }
    return $full
}

function Get-AgentInstallMutexName {
    param([Parameter(Mandatory = $true)][string]$ConfigRoot)

    $comparisonRoot = Get-ComparisonPath -Path $ConfigRoot
    if ($IsWindowsPlatform -or $IsMacOSPlatform) {
        $comparisonRoot = $comparisonRoot.ToUpperInvariant()
    }

    $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash($utf8.GetBytes($comparisonRoot))
    } finally {
        $sha256.Dispose()
    }
    $hex = ([BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
    $prefix = if ($IsWindowsPlatform) {
        'Global\AgentToolRoutingSkill.Install.'
    } else {
        'AgentToolRoutingSkill.Install.'
    }
    return $prefix + $hex
}

function Exit-AgentInstallLocks {
    param([AllowEmptyCollection()][object[]]$Locks)

    for ($index = $Locks.Count - 1; $index -ge 0; $index--) {
        $entry = $Locks[$index]
        if ($entry.Acquired) {
            try {
                $entry.Mutex.ReleaseMutex()
            } catch {
                Write-Warning "Could not release install lock '$($entry.Name)' for '$($entry.ConfigRoot)'. $($_.Exception.Message)"
            }
        }
        try {
            $entry.Mutex.Dispose()
        } catch {
            Write-Warning "Could not dispose install lock '$($entry.Name)' for '$($entry.ConfigRoot)'. $($_.Exception.Message)"
        }
    }
}

function Enter-AgentInstallLocks {
    param([Parameter(Mandatory = $true)][object[]]$Configs)

    $entriesByName = New-Object 'System.Collections.Generic.Dictionary[string,object]' `
        ([System.StringComparer]::Ordinal)
    foreach ($config in $Configs) {
        $name = Get-AgentInstallMutexName -ConfigRoot $config.ConfigRoot
        if (-not $entriesByName.ContainsKey($name)) {
            $entriesByName.Add($name, [pscustomobject]@{
                Name = $name
                ConfigRoot = Get-ComparisonPath -Path $config.ConfigRoot
                Mutex = $null
                Acquired = $false
            })
        }
    }

    $locks = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($name in @($entriesByName.Keys | Sort-Object)) {
            $entry = $entriesByName[$name]
            try {
                $entry.Mutex = New-Object System.Threading.Mutex -ArgumentList $false, $entry.Name
                try {
                    $entry.Acquired = $entry.Mutex.WaitOne(0)
                } catch [System.Threading.AbandonedMutexException] {
                    # WaitOne grants ownership when it reports an abandoned mutex.
                    $entry.Acquired = $true
                    Write-Warning "Recovered abandoned install lock for '$($entry.ConfigRoot)'. The installer will inspect any retained transaction journal before planning changes."
                }
            } catch {
                if ($null -ne $entry.Mutex) {
                    $entry.Mutex.Dispose()
                }
                throw "Could not acquire the install lock for '$($entry.ConfigRoot)'. $($_.Exception.Message)"
            }

            if (-not $entry.Acquired) {
                $entry.Mutex.Dispose()
                throw "Another agent-tool-routing-skill installation is already active for '$($entry.ConfigRoot)'. No target or backup files were written; wait for that installation to finish and retry."
            }
            $locks.Add($entry)
        }
    } catch {
        Exit-AgentInstallLocks -Locks $locks.ToArray()
        throw
    }

    return ,$locks.ToArray()
}

function Join-PathSegments {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Segments
    )

    $result = $Root
    foreach ($segment in $Segments) {
        $result = Join-Path $result $segment
    }
    return $result
}

function Test-PathContained {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Child
    )

    $parentFull = Get-ComparisonPath -Path $Parent
    $childFull = Get-ComparisonPath -Path $Child
    if ([string]::Equals($parentFull, $childFull, $PathComparison)) {
        return $true
    }

    $prefix = $parentFull
    if (-not ($prefix.EndsWith([string][char]'\') -or $prefix.EndsWith([string][char]'/'))) {
        $prefix += $DirectorySeparator
    }
    return $childFull.StartsWith($prefix, $PathComparison)
}

function Test-PathsOverlap {
    param(
        [Parameter(Mandatory = $true)][string]$First,
        [Parameter(Mandatory = $true)][string]$Second
    )

    return (Test-PathContained -Parent $First -Child $Second) -or
        (Test-PathContained -Parent $Second -Child $First)
}

function Assert-NoExistingReparsePoint {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    if ($AllowReparsePoints) {
        return
    }

    $candidate = Normalize-RootPath -Path $Path
    while ($candidate) {
        $item = Get-FileSystemItemIncludingBrokenLink -Path $candidate
        if ($null -ne $item) {
            if (Test-IsFileSystemLink -Item $item) {
                throw "Refusing $Purpose through existing reparse point '$candidate'. Use -AllowReparsePoints only after verifying the destination."
            }
        }

        $parent = Split-Path -Parent $candidate
        if ([string]::IsNullOrEmpty($parent) -or [string]::Equals($parent, $candidate, $PathComparison)) {
            break
        }
        $candidate = $parent
    }
}

function Assert-NoReparsePointTree {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    Assert-NoExistingReparsePoint -Path $Path -Purpose $Purpose
    $rootItem = Get-FileSystemItemIncludingBrokenLink -Path $Path
    if ($null -eq $rootItem) {
        return
    }

    if (Test-IsFileSystemLink -Item $rootItem) {
        throw "Refusing recursive $Purpose because its tree root '$($rootItem.FullName)' is a reparse point. Recursively copied trees must not contain reparse points."
    }
    if (-not $rootItem.PSIsContainer) {
        return
    }

    # Walk one directory level at a time so a reparse-point child is rejected
    # before recursive enumeration can follow it outside the reviewed tree.
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($rootItem.FullName)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($child in @(Get-ChildItem -LiteralPath $current -Force)) {
            if (Test-IsFileSystemLink -Item $child) {
                throw "Refusing recursive $Purpose through nested reparse point '$($child.FullName)'. Recursively copied trees must not contain reparse points."
            }
            if ($child.PSIsContainer) {
                $pending.Push($child.FullName)
            }
        }
    }
}

function Get-ConfiguredRoot {
    param(
        [string]$ExplicitValue,
        [Parameter(Mandatory = $true)][string]$EnvironmentName,
        [Parameter(Mandatory = $true)][string]$Fallback
    )

    $value = $ExplicitValue
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = [Environment]::GetEnvironmentVariable($EnvironmentName)
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = $Fallback
    }
    return Normalize-RootPath -Path $value
}

function Get-TextFileInfo {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            Exists = $false
            Text = ''
            Encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
            EmitBom = $false
        }
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $offset = 0
    $emitBom = $false
    $encoding = $null

    if (($bytes.Length -ge 4) -and $bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF) {
        $encoding = New-Object System.Text.UTF32Encoding -ArgumentList $true, $true
        $offset = 4
        $emitBom = $true
    } elseif (($bytes.Length -ge 4) -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) {
        $encoding = New-Object System.Text.UTF32Encoding -ArgumentList $false, $true
        $offset = 4
        $emitBom = $true
    } elseif (($bytes.Length -ge 3) -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $true, $true
        $offset = 3
        $emitBom = $true
    } elseif (($bytes.Length -ge 2) -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $encoding = New-Object System.Text.UnicodeEncoding -ArgumentList $true, $true
        $offset = 2
        $emitBom = $true
    } elseif (($bytes.Length -ge 2) -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $encoding = New-Object System.Text.UnicodeEncoding -ArgumentList $false, $true
        $offset = 2
        $emitBom = $true
    } else {
        $strictUtf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
        try {
            [void]$strictUtf8.GetString($bytes)
            $encoding = $strictUtf8
        } catch [System.Text.DecoderFallbackException] {
            throw "Unsupported text encoding in '$Path'. Use UTF-8, UTF-8 with BOM, UTF-16 LE/BE, or UTF-32 LE/BE."
        }
    }

    $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    return [pscustomobject]@{
        Exists = $true
        Text = $text
        Encoding = $encoding
        EmitBom = $emitBom
    }
}

function Write-TextFileAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][System.Text.Encoding]$Encoding,
        [Parameter(Mandatory = $true)][bool]$EmitBom
    )

    $parent = Split-Path -Parent $Path
    $parentCreated = $false
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        $parentCreated = $true
    }
    Assert-NoExistingReparsePoint -Path $Path -Purpose 'new UTF-8 state file creation'
    if ($parentCreated -and (-not $IsWindowsPlatform)) {
        [IO.File]::SetUnixFileMode(
            $parent,
            [IO.UnixFileMode]::UserRead -bor
                [IO.UnixFileMode]::UserWrite -bor
                [IO.UnixFileMode]::UserExecute
        )
    }

    $name = [System.IO.Path]::GetFileName($Path)
    $temporaryPath = Join-Path $parent ('.{0}.{1}.tmp' -f $name, [guid]::NewGuid().ToString('N'))
    $replaceBackupPath = Join-Path $parent ('.{0}.{1}.replace-backup' -f $name, [guid]::NewGuid().ToString('N'))
    $hasUnixMode = $false
    $unixMode = $null
    if ((-not $IsWindowsPlatform) -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
        $unixMode = [System.IO.File]::GetUnixFileMode($Path)
        $hasUnixMode = $true
    }
    try {
        $body = $Encoding.GetBytes($Content)
        $preamble = if ($EmitBom) { $Encoding.GetPreamble() } else { New-Object byte[] 0 }
        $output = New-Object byte[] ($preamble.Length + $body.Length)
        if ($preamble.Length -gt 0) {
            [System.Array]::Copy($preamble, 0, $output, 0, $preamble.Length)
        }
        if ($body.Length -gt 0) {
            [System.Array]::Copy($body, 0, $output, $preamble.Length, $body.Length)
        }
        [System.IO.File]::WriteAllBytes($temporaryPath, $output)
        if ($hasUnixMode) {
            [System.IO.File]::SetUnixFileMode($temporaryPath, $unixMode)
        }

        if (Test-Path -LiteralPath $Path) {
            if ($IsWindowsPlatform) {
                [System.IO.File]::Replace($temporaryPath, $Path, $replaceBackupPath)
            } else {
                [System.IO.File]::Move($temporaryPath, $Path, $true)
            }
        } else {
            [System.IO.File]::Move($temporaryPath, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
        if (Test-Path -LiteralPath $replaceBackupPath) {
            Remove-Item -LiteralPath $replaceBackupPath -Force
        }
    }
}

function Write-Utf8NoBomFileAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Content
    )

    $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
    Write-TextFileAtomic -Path $Path -Content $Content -Encoding $utf8 -EmitBom $false
}

function Write-Utf8BomFileAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Content
    )

    $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $true
    Write-TextFileAtomic -Path $Path -Content $Content -Encoding $utf8 -EmitBom $true
}

function Get-NewLine {
    param([AllowEmptyString()][string]$Content)

    $match = [regex]::Match($Content, '\r\n|\n|\r')
    if ($match.Success) {
        return $match.Value
    }
    return [Environment]::NewLine
}

function Convert-NewLines {
    param(
        [AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][string]$NewLine
    )

    return [regex]::Replace($Content, '\r\n|\r|\n', [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return $NewLine
    })
}

function Convert-CodexCompatibilityText {
    param([AllowEmptyString()][string]$Content)

    $updated = [regex]::Replace(
        $Content,
        '(?m)^name:\s*tool-routing-architecture\s*$',
        'name: tool-use-architecture'
    )
    $updated = $updated.Replace('$tool-routing-architecture', '$tool-use-architecture')
    $updated = $updated.Replace('`tool-routing-architecture`', '`tool-use-architecture`')
    $updated = $updated.Replace(
        'skills/tool-routing-architecture/',
        'skills/tool-use-architecture/'
    )
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

function Get-MarkdownFenceIntervals {
    param([AllowEmptyString()][string]$Content)

    $intervals = New-Object System.Collections.Generic.List[object]
    $openStart = -1
    $openCharacter = [char]0
    $openLength = 0
    $lineMatches = [regex]::Matches($Content, '(?m)^.*(?:\r\n|\n|\r|\z)')

    foreach ($lineMatch in $lineMatches) {
        $line = $lineMatch.Value.TrimEnd("`r", "`n")
        if ($openStart -lt 0) {
            $opening = [regex]::Match(
                $line,
                '^(?<fence>`{3,}|~{3,})(?<info>.*)$'
            )
            if (-not $opening.Success) {
                continue
            }

            $fence = $opening.Groups['fence'].Value
            $candidateCharacter = $fence[0]
            if (($candidateCharacter -eq [char]'`') -and $opening.Groups['info'].Value.Contains('`')) {
                continue
            }
            $openStart = $lineMatch.Index
            $openCharacter = $candidateCharacter
            $openLength = $fence.Length
            continue
        }

        $closingPattern = '^' + [regex]::Escape([string]$openCharacter) +
            '{' + $openLength + ',}[ \t]*$'
        if ([regex]::IsMatch($line, $closingPattern)) {
            $intervals.Add([pscustomobject]@{
                StartIndex = $openStart
                EndIndex = $lineMatch.Index + $lineMatch.Length
            })
            $openStart = -1
            $openCharacter = [char]0
            $openLength = 0
        }
    }

    if ($openStart -ge 0) {
        $intervals.Add([pscustomobject]@{
            StartIndex = $openStart
            EndIndex = $Content.Length
        })
    }
    return $intervals.ToArray()
}

function Assert-NoAmbiguousMarkdownContainerFence {
    param(
        [AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $indentedFencePattern = '(?m)^[ \t]+(?:`{3,}|~{3,})'
    $containerFencePattern = '(?m)^[ ]{0,3}(?:(?:>[ \t]?)|(?:(?:[-+*]|\d{1,9}[.)])[ \t]+))+' +
        '[ ]{0,3}(?:`{3,}|~{3,})'
    if ([regex]::IsMatch($Content, $indentedFencePattern) -or
        [regex]::IsMatch($Content, $containerFencePattern)) {
        throw "Indented or container Markdown fences in '$Path' are ambiguous for managed-rule installation. Put both fence delimiters in column 1 before installing rules."
    }
}

function Test-IndexInIntervals {
    param(
        [Parameter(Mandatory = $true)][int]$Index,
        [AllowEmptyCollection()][object[]]$Intervals
    )

    foreach ($interval in @($Intervals)) {
        if (($Index -ge $interval.StartIndex) -and ($Index -lt $interval.EndIndex)) {
            return $true
        }
    }
    return $false
}

function Get-MarkdownH2Matches {
    param([AllowEmptyString()][string]$Content)

    $fences = @(Get-MarkdownFenceIntervals -Content $Content)
    $headingMatches = [regex]::Matches($Content, '(?m)^(?<indent>[ ]{0,3})##[ \t]+(?<heading>[^\r\n]+?)[ \t]*\r?$')
    $outside = New-Object System.Collections.Generic.List[object]
    foreach ($match in $headingMatches) {
        if (-not (Test-IndexInIntervals -Index $match.Index -Intervals $fences)) {
            $outside.Add($match)
        }
    }
    return $outside.ToArray()
}

function Get-MarkdownH2Name {
    param([Parameter(Mandatory = $true)][object]$Match)

    $name = $Match.Groups['heading'].Value.Trim()
    return [regex]::Replace($name, '[ \t]+#+[ \t]*$', '').TrimEnd()
}

function Get-H2Section {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Heading,
        [Parameter(Mandatory = $true)][string]$SourceDescription
    )

    $allHeadings = @(Get-MarkdownH2Matches -Content $Content)
    $sectionMatches = @($allHeadings | Where-Object {
        [string]::Equals((Get-MarkdownH2Name -Match $_), $Heading, [StringComparison]::Ordinal)
    })
    if ($sectionMatches.Count -ne 1) {
        throw "Expected exactly one '## $Heading' section in $SourceDescription; found $($sectionMatches.Count)."
    }
    if ($sectionMatches[0].Groups['indent'].Value.Length -gt 0) {
        throw "The '## $Heading' section in $SourceDescription is indented and may belong to a Markdown container. Put managed H2 sections in column 1."
    }

    $startIndex = $sectionMatches[0].Index
    $nextHeading = @($allHeadings | Where-Object { $_.Index -gt $startIndex } | Select-Object -First 1)
    $endIndex = if ($nextHeading.Count -gt 0) { $nextHeading[0].Index } else { $Content.Length }
    return $Content.Substring($startIndex, $endIndex - $startIndex).TrimEnd("`r", "`n")
}

function Get-ExactMarkerMatches {
    param(
        [AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][string]$Marker,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rawCount = ([regex]::Matches($Content, [regex]::Escape($Marker))).Count
    $linePattern = '(?m)^' + [regex]::Escape($Marker) + '[ \t]*(?=\r?$)'
    $lineMatches = [regex]::Matches($Content, $linePattern)
    if ($rawCount -ne $lineMatches.Count) {
        throw "Managed marker '$Marker' in '$Path' must appear unindented on its own line."
    }

    $fences = @(Get-MarkdownFenceIntervals -Content $Content)
    foreach ($lineMatch in $lineMatches) {
        if (Test-IndexInIntervals -Index $lineMatch.Index -Intervals $fences) {
            throw "Managed marker '$Marker' in '$Path' must not appear inside Markdown fenced code."
        }
    }
    return $lineMatches
}

function Assert-ManagedMarkers {
    param(
        [AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $definitions = @(
        [pscustomobject]@{ Name = 'legacy'; Start = $LegacyStart; End = $LegacyEnd },
        [pscustomobject]@{ Name = 'runtime'; Start = $RuntimeStart; End = $RuntimeEnd },
        [pscustomobject]@{ Name = 'onboarding'; Start = $OnboardingStart; End = $OnboardingEnd }
    )
    $intervals = New-Object System.Collections.Generic.List[object]

    foreach ($definition in $definitions) {
        $starts = Get-ExactMarkerMatches -Content $Content -Marker $definition.Start -Path $Path
        $ends = Get-ExactMarkerMatches -Content $Content -Marker $definition.End -Path $Path
        if (($starts.Count -gt 1) -or ($ends.Count -gt 1)) {
            throw "Duplicate $($definition.Name) managed markers in '$Path'. Expected at most one start/end pair."
        }
        if ($starts.Count -ne $ends.Count) {
            throw "Unbalanced $($definition.Name) managed markers in '$Path'."
        }
        if ($starts.Count -eq 1) {
            if ($starts[0].Index -ge $ends[0].Index) {
                throw "Out-of-order $($definition.Name) managed markers in '$Path'."
            }
            $intervals.Add([pscustomobject]@{
                Name = $definition.Name
                StartIndex = $starts[0].Index
                StartContentIndex = $starts[0].Index + $starts[0].Length
                EndIndex = $ends[0].Index
                EndContentIndex = $ends[0].Index + $ends[0].Length
            })
        }
    }

    $legacy = @($intervals | Where-Object { $_.Name -eq 'legacy' })
    $newMarkers = @($intervals | Where-Object { $_.Name -ne 'legacy' })
    if (($legacy.Count -gt 0) -and ($newMarkers.Count -gt 0)) {
        throw "Legacy and section-specific managed markers cannot coexist in '$Path'."
    }

    $ordered = @($intervals | Sort-Object StartIndex)
    for ($index = 1; $index -lt $ordered.Count; $index++) {
        if ($ordered[$index].StartIndex -lt $ordered[$index - 1].EndContentIndex) {
            throw "Overlapping managed marker blocks in '$Path'."
        }
    }

    return $intervals.ToArray()
}

function Get-MarkerInterval {
    param(
        [object[]]$Intervals,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return @($Intervals | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
}

function New-ManagedBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$End,
        [Parameter(Mandatory = $true)][string]$NewLine
    )

    $normalized = Convert-NewLines -Content $Section.Trim() -NewLine $NewLine
    return $Start + $NewLine + $normalized + $NewLine + $End
}

function Replace-Interval {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][object]$Interval,
        [Parameter(Mandatory = $true)][string]$Replacement
    )

    return $Content.Substring(0, $Interval.StartIndex) + $Replacement +
        $Content.Substring($Interval.EndContentIndex)
}

function Add-ManagedBlock {
    param(
        [AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][string]$Block,
        [Parameter(Mandatory = $true)][string]$NewLine
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return $Block + $NewLine
    }
    return $Content.TrimEnd("`r", "`n") + $NewLine + $NewLine + $Block + $NewLine
}

function Test-UnmanagedSection {
    param(
        [AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][string]$Heading
    )

    $headings = @(Get-MarkdownH2Matches -Content $Content)
    $sectionMatches = @($headings | Where-Object {
        [string]::Equals((Get-MarkdownH2Name -Match $_), $Heading, [StringComparison]::Ordinal)
    })
    $indented = @($sectionMatches | Where-Object { $_.Groups['indent'].Value.Length -gt 0 })
    if ($indented.Count -gt 0) {
        throw "The '## $Heading' section is indented and may belong to a Markdown container. Put unmanaged live H2 sections in column 1 before installing rules."
    }
    return $sectionMatches.Count -gt 0
}

function New-GlobalFilePlan {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][bool]$WantRuntime,
        [Parameter(Mandatory = $true)][bool]$WantOnboarding
    )

    $fileInfo = Get-TextFileInfo -Path $Config.GlobalFile
    $existing = $fileInfo.Text
    Assert-NoAmbiguousMarkdownContainerFence -Content $existing -Path $Config.GlobalFile
    $intervals = @(Assert-ManagedMarkers -Content $existing -Path $Config.GlobalFile)
    $newLine = Get-NewLine -Content $existing

    $snippetInfo = Get-TextFileInfo -Path $Config.Snippet
    $snippet = $snippetInfo.Text
    if ($Config.Name -eq 'codex') {
        $snippet = Convert-CodexCompatibilityText -Content $snippet
    }
    $runtimeSection = Get-H2Section -Content $snippet -Heading 'Tool Directory Routing' -SourceDescription $Config.Snippet
    $onboardingSection = Get-H2Section -Content $snippet -Heading 'Tool Onboarding Gate' -SourceDescription $Config.Snippet
    $runtimeBlock = New-ManagedBlock -Start $RuntimeStart -Section $runtimeSection -End $RuntimeEnd -NewLine $newLine
    $onboardingBlock = New-ManagedBlock -Start $OnboardingStart -Section $onboardingSection -End $OnboardingEnd -NewLine $newLine
    $updated = $existing
    $statuses = New-Object System.Collections.Generic.List[string]
    $writesRuntime = $false
    $writesOnboarding = $false

    $legacy = Get-MarkerInterval -Intervals $intervals -Name 'legacy'
    if ($legacy) {
        $legacyContent = $existing.Substring($legacy.StartContentIndex, $legacy.EndIndex - $legacy.StartContentIndex)
        $preservedRuntime = Get-H2Section -Content $legacyContent -Heading 'Tool Directory Routing' -SourceDescription "legacy managed block in $($Config.GlobalFile)"
        $preservedOnboarding = Get-H2Section -Content $legacyContent -Heading 'Tool Onboarding Gate' -SourceDescription "legacy managed block in $($Config.GlobalFile)"
        if (-not $WantRuntime) {
            $runtimeBlock = New-ManagedBlock -Start $RuntimeStart -Section $preservedRuntime -End $RuntimeEnd -NewLine $newLine
        }
        if (-not $WantOnboarding) {
            $onboardingBlock = New-ManagedBlock -Start $OnboardingStart -Section $preservedOnboarding -End $OnboardingEnd -NewLine $newLine
        }
        $replacement = $runtimeBlock + $newLine + $newLine + $onboardingBlock
        $updated = Replace-Interval -Content $existing -Interval $legacy -Replacement $replacement
        $writesRuntime = $true
        $writesOnboarding = [bool]$WantOnboarding
        $statuses.Add('migrated legacy managed block')
    } else {
        if ($WantRuntime) {
            $runtime = Get-MarkerInterval -Intervals $intervals -Name 'runtime'
            if ($runtime) {
                $updated = Replace-Interval -Content $updated -Interval $runtime -Replacement $runtimeBlock
                $statuses.Add('runtime installed or updated')
                $writesRuntime = $true
            } elseif (Test-UnmanagedSection -Content $updated -Heading 'Tool Directory Routing') {
                $statuses.Add('runtime unmarked; left unchanged')
            } else {
                $updated = Add-ManagedBlock -Content $updated -Block $runtimeBlock -NewLine $newLine
                $statuses.Add('runtime installed or updated')
                $writesRuntime = $true
            }
        }

        # Re-read marker positions if the runtime replacement changed string length.
        $intervals = @(Assert-ManagedMarkers -Content $updated -Path $Config.GlobalFile)
        if ($WantOnboarding) {
            $onboarding = Get-MarkerInterval -Intervals $intervals -Name 'onboarding'
            if ($onboarding) {
                $updated = Replace-Interval -Content $updated -Interval $onboarding -Replacement $onboardingBlock
                $statuses.Add('onboarding installed or updated')
                $writesOnboarding = $true
            } elseif (Test-UnmanagedSection -Content $updated -Heading 'Tool Onboarding Gate') {
                $statuses.Add('onboarding unmarked; left unchanged')
            } else {
                $updated = Add-ManagedBlock -Content $updated -Block $onboardingBlock -NewLine $newLine
                $statuses.Add('onboarding installed or updated')
                $writesOnboarding = $true
            }
        }
    }

    [void](Assert-ManagedMarkers -Content $updated -Path $Config.GlobalFile)
    return [pscustomobject]@{
        FileInfo = $fileInfo
        UpdatedText = $updated
        Changed = -not [string]::Equals($existing, $updated, [System.StringComparison]::Ordinal)
        WritesRuntime = $writesRuntime
        WritesOnboarding = $writesOnboarding
        Status = if ($statuses.Count -eq 0) { 'not requested' } else { $statuses.ToArray() -join '; ' }
    }
}

function Get-AgentConfig {
    param([Parameter(Mandatory = $true)][string]$Agent)

    switch ($Agent) {
        'codex' {
            $root = $script:CodexHomeFull
            return [pscustomobject]@{
                Name = 'codex'
                SkillName = 'tool-use-architecture'
                ConfigRoot = $root
                SkillRoot = Join-Path $root 'skills'
                SkillDir = Join-PathSegments -Root $root -Segments @('skills', 'tool-use-architecture')
                RuntimeDependency = Join-PathSegments -Root $root -Segments @('skills', 'tool-index', 'SKILL.md')
                GlobalFile = Join-Path $root 'AGENTS.md'
                Snippet = Join-Path $ExamplesSource 'AGENTS.md.snippet'
                IndexRequest = Join-PathSegments -Root $root -Segments @('tool-routing-state', 'initial-index.json')
            }
        }
        'claude' {
            $root = $script:ClaudeConfigDirFull
            return [pscustomobject]@{
                Name = 'claude'
                SkillName = 'tool-routing-architecture'
                ConfigRoot = $root
                SkillRoot = Join-Path $root 'skills'
                SkillDir = Join-PathSegments -Root $root -Segments @('skills', 'tool-routing-architecture')
                RuntimeDependency = Join-PathSegments -Root $root -Segments @('skills', 'tool-index', 'SKILL.md')
                GlobalFile = Join-Path $root 'CLAUDE.md'
                Snippet = Join-Path $ExamplesSource 'CLAUDE.md.snippet'
                IndexRequest = Join-PathSegments -Root $root -Segments @('tool-routing-state', 'initial-index.json')
            }
        }
        'zcode' {
            $root = $script:ZcodeHomeFull
            return [pscustomobject]@{
                Name = 'zcode'
                SkillName = 'tool-routing-architecture'
                ConfigRoot = $root
                SkillRoot = Join-Path $root 'skills'
                SkillDir = Join-PathSegments -Root $root -Segments @('skills', 'tool-routing-architecture')
                RuntimeDependency = Join-PathSegments -Root $root -Segments @('skills', 'tool-index', 'SKILL.md')
                GlobalFile = Join-Path $root 'AGENTS.md'
                Snippet = Join-Path $ExamplesSource 'AGENTS.md.snippet'
                IndexRequest = Join-PathSegments -Root $root -Segments @('tool-routing-state', 'initial-index.json')
            }
        }
        default { throw "Unknown agent target: $Agent" }
    }
}

function Get-ExistingInitialIndexRequest {
    param([Parameter(Mandatory = $true)][object]$Config)

    if (-not (Test-Path -LiteralPath $Config.IndexRequest)) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $Config.IndexRequest -PathType Leaf)) {
        throw "Initial routing request must be an ordinary file: $($Config.IndexRequest)"
    }

    $bytes = [IO.File]::ReadAllBytes($Config.IndexRequest)
    if ($bytes.Length -gt $MaximumIndexRequestBytes) {
        throw "Initial routing request exceeds $MaximumIndexRequestBytes bytes: $($Config.IndexRequest)"
    }
    $strictUtf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
    try {
        $requestText = $strictUtf8.GetString($bytes)
        if ($requestText.Length -gt 0 -and $requestText[0] -eq [char]0xFEFF) {
            throw 'BOM is not allowed.'
        }
        $request = $requestText | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Initial routing request must be UTF-8 JSON without BOM: $($Config.IndexRequest)"
    }

    $allowedStatuses = @(
        'pending',
        'inventory',
        'classifying',
        'sourcing',
        'planning',
        'applying',
        'validating',
        'blocked',
        'needs-input',
        'failed'
    )
    $allowedRuntimeModes = @('auto-discovery', 'strict-progressive')
    $requiredProperties = @(
        'schema_version',
        'request_id',
        'status',
        'target_agent',
        'project_version',
        'runtime_mode',
        'scope',
        'completed_phases',
        'unresolved_a_tools'
    )
    $missingProperty = @($requiredProperties | Where-Object {
        $null -eq $request.PSObject.Properties[$_]
    }).Count -gt 0
    $completedPhasesAreStrings = ($request.completed_phases -is [Collections.IList]) -and
        (@($request.completed_phases | Where-Object { $_ -isnot [string] }).Count -eq 0)
    $unresolvedToolsAreStrings = ($request.unresolved_a_tools -is [Collections.IList]) -and
        (@($request.unresolved_a_tools | Where-Object { $_ -isnot [string] }).Count -eq 0)
    if ($missingProperty -or
        ($request.schema_version -ne 1) -or
        ([string]$request.target_agent -ne $Config.Name) -or
        ([string]$request.scope -ne 'registered-capabilities') -or
        ([string]$request.request_id -notmatch '^[0-9a-f]{32}$') -or
        ([string]$request.project_version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') -or
        ($allowedRuntimeModes -notcontains [string]$request.runtime_mode) -or
        ($allowedStatuses -notcontains [string]$request.status) -or
        (-not $completedPhasesAreStrings) -or
        (-not $unresolvedToolsAreStrings)) {
        throw "Initial routing request metadata is invalid or belongs to another Agent: $($Config.IndexRequest)"
    }

    return [Convert]::ToBase64String($bytes)
}

function New-InitialIndexRequestText {
    param([Parameter(Mandatory = $true)][object]$Config)

    $request = [ordered]@{
        schema_version = 1
        request_id = [guid]::NewGuid().ToString('N')
        status = 'pending'
        target_agent = $Config.Name
        project_version = $ProjectVersion
        runtime_mode = 'auto-discovery'
        scope = 'registered-capabilities'
        requested_at_utc = [DateTime]::UtcNow.ToString('o')
        phase = 'pending'
        completed_phases = @()
        unresolved_a_tools = @()
    }
    return ($request | ConvertTo-Json -Depth 4).Replace("`r`n", "`n") + "`n"
}

function Write-NewUtf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
    $bytes = $utf8.GetBytes($Content)
    $created = $false
    try {
        $stream = [IO.File]::Open(
            $Path,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )
        $created = $true
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally {
            $stream.Dispose()
        }
        if (-not $IsWindowsPlatform) {
            [IO.File]::SetUnixFileMode(
                $Path,
                [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite
            )
        }
    } catch {
        if ($created -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Quote-PowerShellLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Add-BackupAndRollback {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label,
        [AllowEmptyCollection()][System.Collections.Generic.List[string]]$PreflightCommands,
        [AllowEmptyCollection()][System.Collections.Generic.List[string]]$Commands,
        [Parameter(Mandatory = $true)][string]$SnapshotRoot
    )

    $backupPath = Join-Path $SnapshotRoot $Label
    $quotedPath = Quote-PowerShellLiteral -Value $Path
    if (Test-Path -LiteralPath $Path) {
        Copy-Item -LiteralPath $Path -Destination $backupPath -Recurse -Force
        $quotedBackup = Quote-PowerShellLiteral -Value $backupPath
        $quotedMissingMessage = Quote-PowerShellLiteral -Value "Rollback backup is missing: $backupPath"
        $PreflightCommands.Add("if (-not (Test-Path -LiteralPath $quotedBackup)) { throw $quotedMissingMessage }")
        $unixModeArgument = ''
        if ((-not $IsWindowsPlatform) -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            $unixModeValue = [int][System.IO.File]::GetUnixFileMode($Path)
            $unixModeArgument = " -UnixModeValue $unixModeValue"
        }
        $Commands.Add("if (Test-AgentToolRoutingRollbackSelected -Path $quotedPath -OnlyPaths `$OnlyPath) { Restore-AgentToolRoutingPath -Path $quotedPath -BackupPath $quotedBackup$unixModeArgument }")
    } else {
        $Commands.Add("if ((Test-AgentToolRoutingRollbackSelected -Path $quotedPath -OnlyPaths `$OnlyPath) -and (Test-Path -LiteralPath $quotedPath)) { Remove-Item -LiteralPath $quotedPath -Recurse -Force }")
    }
}

function Stage-AgentSkill {
    param(
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][string]$StageRoot
    )

    $stageDir = Join-Path $StageRoot $Config.Name
    New-Item -ItemType Directory -Path $stageDir | Out-Null
    Copy-Item -LiteralPath $VersionSource -Destination (Join-Path $stageDir 'VERSION') -Force
    Copy-Item -LiteralPath $SkillSource -Destination (Join-Path $stageDir 'SKILL.md') -Force
    Copy-Item -LiteralPath $AgentsSource -Destination (Join-Path $stageDir 'agents') -Recurse -Force
    if (Test-Path -LiteralPath $ReferencesSource -PathType Container) {
        Copy-Item -LiteralPath $ReferencesSource -Destination (Join-Path $stageDir 'references') -Recurse -Force
    }
    if (Test-Path -LiteralPath $ExamplesSource -PathType Container) {
        Copy-Item -LiteralPath $ExamplesSource -Destination (Join-Path $stageDir 'examples') -Recurse -Force
    }

    foreach ($referenceFile in $RequiredReferenceFiles) {
        $stagedReference = Join-PathSegments -Root $stageDir -Segments @('references', $referenceFile)
        if (-not (Test-Path -LiteralPath $stagedReference -PathType Leaf)) {
            throw "Staged skill for $($Config.Name) is missing required reference: $stagedReference"
        }
    }

    foreach ($exampleFile in $RequiredExampleFiles) {
        $stagedExample = Join-PathSegments -Root $stageDir -Segments @('examples', $exampleFile)
        if (-not (Test-Path -LiteralPath $stagedExample -PathType Leaf)) {
            throw "Staged skill for $($Config.Name) is missing required example: $stagedExample"
        }
    }

    if ($Config.Name -eq 'codex') {
        $files = @(
            (Join-Path $stageDir 'SKILL.md'),
            (Join-PathSegments -Root $stageDir -Segments @('agents', 'openai.yaml')),
            (Join-PathSegments -Root $stageDir -Segments @('examples', 'AGENTS.md.snippet')),
            (Join-PathSegments -Root $stageDir -Segments @('examples', 'CLAUDE.md.snippet'))
        )
        foreach ($file in $files) {
            if (Test-Path -LiteralPath $file) {
                $info = Get-TextFileInfo -Path $file
                $converted = Convert-CodexCompatibilityText -Content $info.Text
                Write-Utf8NoBomFileAtomic -Path $file -Content $converted
            }
        }
    }

    $skillPath = Join-Path $stageDir 'SKILL.md'
    $skillInfo = Get-TextFileInfo -Path $skillPath
    $frontmatterMatch = [regex]::Match($skillInfo.Text, '(?s)\A---[ \t]*\r?\n(?<body>.*?)\r?\n---(?:[ \t]*\r?\n|\z)')
    if (-not $frontmatterMatch.Success) {
        throw "No YAML frontmatter found in staged SKILL.md for $($Config.Name): $skillPath"
    }
    $nameMatch = [regex]::Match($frontmatterMatch.Groups['body'].Value, '(?m)^name:\s*(.+?)\s*$')
    if (-not $nameMatch.Success) {
        throw "No 'name:' field found in staged SKILL.md for $($Config.Name): $skillPath"
    }
    $installedName = $nameMatch.Groups[1].Value.Trim()
    if ($installedName -ne $Config.SkillName) {
        throw "Staged skill name mismatch for $($Config.Name): expected $($Config.SkillName), got $installedName"
    }
    $stagedVersion = [System.IO.File]::ReadAllText((Join-Path $stageDir 'VERSION')).Trim()
    if (-not [string]::Equals($stagedVersion, $ProjectVersion, [StringComparison]::Ordinal)) {
        throw "Staged skill version mismatch for $($Config.Name): expected $ProjectVersion, got $stagedVersion"
    }
    return $stageDir
}

function Get-FileSha256Base64 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    )
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToBase64String($sha256.ComputeHash($stream))
    } finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

function Get-VerifiedDirectoryManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    Assert-NoReparsePointTree -Path $Root -Purpose $Purpose
    $rootItem = Get-FileSystemItemIncludingBrokenLink -Path $Root
    if (($null -eq $rootItem) -or (-not $rootItem.PSIsContainer)) {
        throw "Expected an ordinary directory for ${Purpose}: $Root"
    }

    $manifest = New-Object 'System.Collections.Generic.Dictionary[string,object]' `
        ([System.StringComparer]::Ordinal)
    $pending = New-Object System.Collections.Generic.Stack[object]
    $pending.Push([pscustomobject]@{
        FullPath = $rootItem.FullName
        RelativePath = ''
    })

    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($child in @(Get-ChildItem -LiteralPath $current.FullPath -Force -ErrorAction Stop)) {
            if (Test-IsFileSystemLink -Item $child) {
                throw "Refusing $Purpose through reparse point '$($child.FullName)'."
            }

            $relativePath = if ([string]::IsNullOrEmpty($current.RelativePath)) {
                $child.Name
            } else {
                $current.RelativePath + '/' + $child.Name
            }
            if ($manifest.ContainsKey($relativePath)) {
                throw "Duplicate relative path while validating ${Purpose}: $relativePath"
            }

            if ($child.PSIsContainer) {
                $manifest.Add($relativePath, [pscustomobject]@{
                    Kind = 'directory'
                    Length = [int64]0
                    Digest = ''
                })
                $pending.Push([pscustomobject]@{
                    FullPath = $child.FullName
                    RelativePath = $relativePath
                })
            } elseif ($child -is [System.IO.FileInfo]) {
                $manifest.Add($relativePath, [pscustomobject]@{
                    Kind = 'file'
                    Length = [int64]$child.Length
                    Digest = Get-FileSha256Base64 -Path $child.FullName
                })
            } else {
                throw "Refusing non-file entry '$($child.FullName)' while validating $Purpose."
            }
        }
    }

    return ,$manifest
}

function Assert-DirectoryCopyMatches {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Copy
    )

    $sourceManifest = Get-VerifiedDirectoryManifest -Root $Source -Purpose 'staged skill copy source'
    $copyManifest = Get-VerifiedDirectoryManifest -Root $Copy -Purpose 'incoming skill copy verification'
    if ($sourceManifest.Count -ne $copyManifest.Count) {
        throw "Incoming skill copy entry count mismatch: expected $($sourceManifest.Count), got $($copyManifest.Count)."
    }

    foreach ($relativePath in $sourceManifest.Keys) {
        if (-not $copyManifest.ContainsKey($relativePath)) {
            throw "Incoming skill copy is missing '$relativePath'."
        }
        $expected = $sourceManifest[$relativePath]
        $actual = $copyManifest[$relativePath]
        if (-not [string]::Equals($expected.Kind, $actual.Kind, [StringComparison]::Ordinal)) {
            throw "Incoming skill copy type mismatch for '$relativePath': expected $($expected.Kind), got $($actual.Kind)."
        }
        if (($expected.Kind -eq 'file') -and
            (($expected.Length -ne $actual.Length) -or
                (-not [string]::Equals($expected.Digest, $actual.Digest, [StringComparison]::Ordinal)))) {
            throw "Incoming skill copy content mismatch for '$relativePath'."
        }
    }
}

function Convert-BytesToLowerHex {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return ([BitConverter]::ToString($Bytes)).Replace('-', '').ToLowerInvariant()
}

function Convert-LowerHexToBytes {
    param([Parameter(Mandatory = $true)][string]$Hex)

    if (($Hex.Length % 2) -ne 0 -or ($Hex -notmatch '^[0-9a-f]*$')) {
        throw 'Expected lowercase hexadecimal text with an even length.'
    }
    $bytes = New-Object byte[] ($Hex.Length / 2)
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        $bytes[$index] = [Convert]::ToByte($Hex.Substring($index * 2, 2), 16)
    }
    return ,$bytes
}

function Write-UInt32BigEndian {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)][uint32]$Value
    )

    $bytes = New-Object byte[] 4
    for ($index = 3; $index -ge 0; $index--) {
        $bytes[$index] = [byte]($Value -band 0xff)
        $Value = $Value -shr 8
    }
    $Stream.Write($bytes, 0, $bytes.Length)
}

function Write-UInt64BigEndian {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)][uint64]$Value
    )

    $bytes = New-Object byte[] 8
    for ($index = 7; $index -ge 0; $index--) {
        $bytes[$index] = [byte]($Value -band 0xff)
        $Value = $Value -shr 8
    }
    $Stream.Write($bytes, 0, $bytes.Length)
}

function Get-CanonicalPreparedTreeSha256 {
    param([Parameter(Mandatory = $true)][object[]]$Entries)

    # Entries are ordinal-path sorted. Each record is kind, big-endian UTF-8
    # path length/path, big-endian length, and raw SHA-256 bytes for files.
    $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
    $stream = New-Object System.IO.MemoryStream
    try {
        $magic = $utf8.GetBytes("ATRS-TREE-V1`0")
        $stream.Write($magic, 0, $magic.Length)
        foreach ($entry in $Entries) {
            $kindByte = if ($entry.Kind -eq 'directory') { [byte]0x44 } else { [byte]0x46 }
            $stream.WriteByte($kindByte)
            $pathBytes = $utf8.GetBytes([string]$entry.Path)
            if ($pathBytes.Length -gt [uint32]::MaxValue) {
                throw "Prepared tree path is too long to canonicalize: $($entry.Path)"
            }
            Write-UInt32BigEndian -Stream $stream -Value ([uint32]$pathBytes.Length)
            $stream.Write($pathBytes, 0, $pathBytes.Length)
            Write-UInt64BigEndian -Stream $stream -Value ([uint64]$entry.Length)
            if ($entry.Kind -eq 'file') {
                $digestBytes = Convert-LowerHexToBytes -Hex ([string]$entry.Sha256)
                if ($digestBytes.Length -ne 32) {
                    throw "Prepared tree file digest must be 32 bytes: $($entry.Path)"
                }
                $stream.WriteByte([byte]32)
                $stream.Write($digestBytes, 0, $digestBytes.Length)
            } else {
                $stream.WriteByte([byte]0)
            }
        }
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $stream.Position = 0
            return Convert-BytesToLowerHex -Bytes $sha256.ComputeHash($stream)
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Get-PreparedTreeDescriptor {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    $manifest = Get-VerifiedDirectoryManifest -Root $Root -Purpose $Purpose
    [string[]]$paths = @($manifest.Keys)
    [Array]::Sort($paths, [System.StringComparer]::Ordinal)
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($path in $paths) {
        $sourceEntry = $manifest[$path]
        $sha256 = if ($sourceEntry.Kind -eq 'file') {
            Convert-BytesToLowerHex -Bytes ([Convert]::FromBase64String($sourceEntry.Digest))
        } else {
            ''
        }
        $entries.Add([pscustomobject][ordered]@{
            Path = $path
            Kind = [string]$sourceEntry.Kind
            Length = [int64]$sourceEntry.Length
            Sha256 = $sha256
        })
    }
    $entryArray = @($entries.ToArray())
    return [pscustomobject]@{
        Entries = $entryArray
        TreeSha256 = Get-CanonicalPreparedTreeSha256 -Entries $entryArray
    }
}

function Write-PreparedTreeManifest {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)][string]$IncomingRoot
    )

    $descriptor = Get-PreparedTreeDescriptor -Root $IncomingRoot `
        -Purpose 'prepared incoming skill tree'
    $document = [ordered]@{
        schema_version = 1
        algorithm = 'sha256'
        canonicalization = 'atrs-tree-v1'
        tree_sha256 = $descriptor.TreeSha256
        entries = @($descriptor.Entries | ForEach-Object {
            [ordered]@{
                path = $_.Path
                kind = $_.Kind
                length = $_.Length
                sha256 = $_.Sha256
            }
        })
    }
    $text = ($document | ConvertTo-Json -Depth 5).Replace("`r`n", "`n") + "`n"
    Write-NewUtf8NoBomFile -Path (Join-Path $TransactionRoot 'prepared-tree.json') `
        -Content $text
    return $descriptor
}

function Read-StrictTransactionJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int64]$MaximumBytes,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    Assert-NoExistingReparsePoint -Path $Path -Purpose $Purpose
    $item = Get-FileSystemItemIncludingBrokenLink -Path $Path
    if (($null -eq $item) -or $item.PSIsContainer -or (Test-IsFileSystemLink -Item $item)) {
        throw "${Purpose} is missing or is not an ordinary file: $Path"
    }
    if ($item.Length -gt $MaximumBytes) {
        throw "${Purpose} exceeds $MaximumBytes bytes: $Path"
    }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $strictUtf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false, $true
        $text = $strictUtf8.GetString($bytes)
        if (($text.Length -gt 0) -and ($text[0] -eq [char]0xFEFF)) {
            throw 'BOM is not allowed.'
        }
        return $text | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "${Purpose} must be UTF-8 JSON without BOM: $Path. $($_.Exception.Message)"
    }
}

function Read-PreparedTreeManifest {
    param([Parameter(Mandatory = $true)][string]$TransactionRoot)

    $path = Join-Path $TransactionRoot 'prepared-tree.json'
    if ($null -eq (Get-FileSystemItemIncludingBrokenLink -Path $path)) {
        return $null
    }
    $document = Read-StrictTransactionJson -Path $path -MaximumBytes 4194304 `
        -Purpose 'prepared tree manifest'
    $requiredProperties = @(
        'schema_version', 'algorithm', 'canonicalization', 'tree_sha256', 'entries'
    )
    $hasRequiredProperties = $true
    foreach ($propertyName in $requiredProperties) {
        if ($null -eq $document.PSObject.Properties[$propertyName]) {
            $hasRequiredProperties = $false
            break
        }
    }
    if ((-not $hasRequiredProperties) -or
        ($document.schema_version -ne 1) -or
        (-not [string]::Equals([string]$document.algorithm, 'sha256', [StringComparison]::Ordinal)) -or
        (-not [string]::Equals([string]$document.canonicalization, 'atrs-tree-v1', [StringComparison]::Ordinal)) -or
        ([string]$document.tree_sha256 -notmatch '^[0-9a-f]{64}$') -or
        (-not ($document.entries -is [System.Array]))) {
        throw "Prepared tree manifest metadata is invalid: $path"
    }

    $rawEntries = @($document.entries)
    if ($rawEntries.Count -gt 100000) {
        throw "Prepared tree manifest has too many entries: $path"
    }
    $entries = New-Object System.Collections.Generic.List[object]
    $previousPath = $null
    foreach ($rawEntry in $rawEntries) {
        $entryPath = [string]$rawEntry.path
        $kind = [string]$rawEntry.kind
        $lengthValue = $rawEntry.length
        $sha256 = [string]$rawEntry.sha256
        $segments = @($entryPath.Split('/'))
        $hasUnsafeSegment = $false
        foreach ($segment in $segments) {
            if ([string]::IsNullOrEmpty($segment) -or ($segment -eq '.') -or ($segment -eq '..')) {
                $hasUnsafeSegment = $true
                break
            }
        }
        $lengthIsInteger = ($lengthValue -is [int]) -or ($lengthValue -is [long]) -or
            ($lengthValue -is [uint32]) -or ($lengthValue -is [uint64])
        if ([string]::IsNullOrEmpty($entryPath) -or $entryPath.StartsWith('/') -or
            $hasUnsafeSegment -or (-not $lengthIsInteger) -or ([int64]$lengthValue -lt 0) -or
            (($kind -ne 'file') -and ($kind -ne 'directory')) -or
            (($kind -eq 'file') -and ($sha256 -notmatch '^[0-9a-f]{64}$')) -or
            (($kind -eq 'directory') -and (([int64]$lengthValue -ne 0) -or ($sha256 -ne ''))) -or
            (($null -ne $previousPath) -and
                ([System.StringComparer]::Ordinal.Compare($previousPath, $entryPath) -ge 0))) {
            throw "Prepared tree manifest contains an invalid or unsorted entry: $path"
        }
        $entries.Add([pscustomobject]@{
            Path = $entryPath
            Kind = $kind
            Length = [int64]$lengthValue
            Sha256 = $sha256
        })
        $previousPath = $entryPath
    }
    $entryArray = @($entries.ToArray())
    $computed = Get-CanonicalPreparedTreeSha256 -Entries $entryArray
    if (-not [string]::Equals(
            $computed,
            [string]$document.tree_sha256,
            [StringComparison]::Ordinal)) {
        throw "Prepared tree manifest digest does not match its entries: $path"
    }
    return [pscustomobject]@{
        Path = $path
        Entries = $entryArray
        TreeSha256 = $computed
    }
}

function Assert-PreparedTreeMatches {
    param(
        [Parameter(Mandatory = $true)][object]$Expected,
        [Parameter(Mandatory = $true)][string]$ActualRoot,
        [Parameter(Mandatory = $true)][string]$TransactionRoot
    )

    $actual = Get-PreparedTreeDescriptor -Root $ActualRoot `
        -Purpose 'retained committed live skill verification'
    $matches = [string]::Equals(
        $actual.TreeSha256,
        $Expected.TreeSha256,
        [StringComparison]::Ordinal
    ) -and ($actual.Entries.Count -eq $Expected.Entries.Count)
    if ($matches) {
        for ($index = 0; $index -lt $actual.Entries.Count; $index++) {
            $a = $actual.Entries[$index]
            $e = $Expected.Entries[$index]
            if ((-not [string]::Equals($a.Path, $e.Path, [StringComparison]::Ordinal)) -or
                (-not [string]::Equals($a.Kind, $e.Kind, [StringComparison]::Ordinal)) -or
                ($a.Length -ne $e.Length) -or
                (-not [string]::Equals($a.Sha256, $e.Sha256, [StringComparison]::Ordinal))) {
                $matches = $false
                break
            }
        }
    }
    if (-not $matches) {
        throw "Retained transaction live skill does not match the prepared incoming tree. Recovery stopped without deleting previous data. Live: '$ActualRoot'; previous: '$(Join-Path $TransactionRoot 'previous')'; journal: '$TransactionRoot'."
    }
}

function Set-PrivateDirectoryMode {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not $IsWindowsPlatform) {
        [System.IO.File]::SetUnixFileMode(
            $Path,
            [System.IO.UnixFileMode]::UserRead -bor
                [System.IO.UnixFileMode]::UserWrite -bor
                [System.IO.UnixFileMode]::UserExecute
        )
    }
}

function Get-SkillTransactionContainerPath {
    param([Parameter(Mandatory = $true)][string]$SkillRoot)
    return Join-Path $SkillRoot '.agent-tool-routing-transactions'
}

function Remove-EmptySkillTransactionContainer {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-FileSystemItemIncludingBrokenLink -Path $Path
    if ($null -eq $item) {
        return
    }
    if ((Test-IsFileSystemLink -Item $item) -or (-not $item.PSIsContainer)) {
        throw "Skill transaction container is not an ordinary directory: $Path"
    }
    if (@(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop).Count -eq 0) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
}

function Read-SkillTransactionJournal {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedDestinationLeaf
    )

    $journalPath = Join-Path $TransactionRoot 'transaction.json'
    $journal = Read-StrictTransactionJson -Path $journalPath -MaximumBytes 16384 `
        -Purpose 'skill transaction journal'

    $transactionId = [string]$journal.transaction_id
    $destinationLeaf = [string]$journal.destination_leaf
    $transactionDirectoryName = [System.IO.Path]::GetFileName($TransactionRoot)
    $requiredProperties = @(
        'schema_version', 'transaction_id', 'destination_leaf',
        'had_destination', 'created_at_utc'
    )
    $hasRequiredProperties = $true
    foreach ($propertyName in $requiredProperties) {
        if ($null -eq $journal.PSObject.Properties[$propertyName]) {
            $hasRequiredProperties = $false
            break
        }
    }
    if ((-not $hasRequiredProperties) -or
        ($journal.schema_version -ne 1) -or
        ($transactionId -notmatch '^txn-[0-9a-f]{32}$') -or
        (-not [string]::Equals($transactionId, $transactionDirectoryName, [StringComparison]::Ordinal)) -or
        (-not ($journal.had_destination -is [bool])) -or
        [string]::IsNullOrWhiteSpace([string]$journal.created_at_utc) -or
        (-not [string]::Equals($destinationLeaf, $ExpectedDestinationLeaf, $PathComparison)) -or
        (-not [string]::Equals([System.IO.Path]::GetFileName($destinationLeaf), $destinationLeaf, [StringComparison]::Ordinal)) -or
        ($destinationLeaf -eq '.') -or ($destinationLeaf -eq '..')) {
        throw "Skill transaction journal metadata is invalid or targets another skill: $journalPath"
    }
    return $journal
}

function Read-SkillTransactionPhases {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)][object]$Journal,
        [AllowNull()][object]$PreparedTree
    )

    $phaseFiles = [ordered]@{
        'incoming-prepared' = 'phase-20-incoming-prepared.json'
        'live-displaced' = 'phase-30-live-displaced.json'
        'live-committed' = 'phase-40-live-committed.json'
    }
    $knownNames = New-Object 'System.Collections.Generic.HashSet[string]' `
        ([System.StringComparer]::Ordinal)
    foreach ($name in $phaseFiles.Values) {
        [void]$knownNames.Add($name)
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $TransactionRoot -Force -ErrorAction Stop)) {
        if ($item.Name.StartsWith('phase-', [StringComparison]::Ordinal) -and
            (-not $knownNames.Contains($item.Name))) {
            throw "Retained skill transaction has an unknown phase marker: $($item.FullName)"
        }
    }

    $present = New-Object 'System.Collections.Generic.HashSet[string]' `
        ([System.StringComparer]::Ordinal)
    foreach ($phase in $phaseFiles.Keys) {
        $path = Join-Path $TransactionRoot $phaseFiles[$phase]
        if ($null -eq (Get-FileSystemItemIncludingBrokenLink -Path $path)) {
            continue
        }
        if ($null -eq $PreparedTree) {
            throw "Phase marker exists without a prepared tree manifest: $path"
        }
        $marker = Read-StrictTransactionJson -Path $path -MaximumBytes 16384 `
            -Purpose "skill transaction phase '$phase'"
        $requiredProperties = @(
            'schema_version', 'transaction_id', 'phase',
            'prepared_tree_sha256', 'recorded_at_utc'
        )
        $hasRequiredProperties = $true
        foreach ($propertyName in $requiredProperties) {
            if ($null -eq $marker.PSObject.Properties[$propertyName]) {
                $hasRequiredProperties = $false
                break
            }
        }
        $timestampValue = $marker.recorded_at_utc
        if ($timestampValue -is [DateTime]) {
            $timestampIsValid = $timestampValue.Kind -eq [DateTimeKind]::Utc
        } elseif ($timestampValue -is [DateTimeOffset]) {
            $timestampIsValid = $true
        } else {
            $parsedTimestamp = [DateTimeOffset]::MinValue
            $timestampIsValid = [DateTimeOffset]::TryParseExact(
                [string]$timestampValue,
                'o',
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind,
                [ref]$parsedTimestamp
            )
        }
        if ((-not $hasRequiredProperties) -or
            ($marker.schema_version -ne 1) -or
            (-not [string]::Equals([string]$marker.transaction_id, [string]$Journal.transaction_id, [StringComparison]::Ordinal)) -or
            (-not [string]::Equals([string]$marker.phase, $phase, [StringComparison]::Ordinal)) -or
            (-not [string]::Equals([string]$marker.prepared_tree_sha256, $PreparedTree.TreeSha256, [StringComparison]::Ordinal)) -or
            (-not $timestampIsValid)) {
            throw "Skill transaction phase marker metadata is invalid: $path"
        }
        [void]$present.Add($phase)
    }

    if (($present.Contains('live-displaced') -and
            (-not $present.Contains('incoming-prepared'))) -or
        ($present.Contains('live-committed') -and
            (-not $present.Contains('incoming-prepared'))) -or
        ([bool]$Journal.had_destination -and
            $present.Contains('live-committed') -and
            (-not $present.Contains('live-displaced'))) -or
        ((-not [bool]$Journal.had_destination) -and
            $present.Contains('live-displaced'))) {
        throw "Skill transaction phase marker sequence is invalid: $TransactionRoot"
    }
    return ,$present
}

function Assert-OrdinaryTransactionDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Purpose
    )

    $item = Get-FileSystemItemIncludingBrokenLink -Path $Path
    if ($null -eq $item) {
        return $false
    }
    if ((Test-IsFileSystemLink -Item $item) -or (-not $item.PSIsContainer)) {
        throw "Expected an ordinary directory for ${Purpose}: $Path"
    }
    Assert-NoReparsePointTree -Path $Path -Purpose $Purpose
    return $true
}

function Recover-SkillTransactions {
    param([Parameter(Mandatory = $true)][string]$Destination)

    $destinationFull = Normalize-RootPath -Path $Destination
    $skillRoot = Split-Path -Parent $destinationFull
    $destinationLeaf = [System.IO.Path]::GetFileName($destinationFull)
    if ([string]::IsNullOrEmpty($skillRoot) -or [string]::IsNullOrEmpty($destinationLeaf)) {
        throw "Skill destination must have a parent directory and leaf name: $Destination"
    }
    if (-not (Test-Path -LiteralPath $skillRoot -PathType Container)) {
        return
    }

    $container = Get-SkillTransactionContainerPath -SkillRoot $skillRoot
    $containerItem = Get-FileSystemItemIncludingBrokenLink -Path $container
    if ($null -eq $containerItem) {
        return
    }
    if ((Test-IsFileSystemLink -Item $containerItem) -or (-not $containerItem.PSIsContainer)) {
        throw "Skill transaction container is not an ordinary directory: $container"
    }
    Assert-NoReparsePointTree -Path $container -Purpose 'retained skill transaction recovery'

    foreach ($transactionItem in @(Get-ChildItem -LiteralPath $container -Force -ErrorAction Stop | Sort-Object Name)) {
        if ((Test-IsFileSystemLink -Item $transactionItem) -or (-not $transactionItem.PSIsContainer)) {
            throw "Unexpected direct entry in skill transaction container '$container': $($transactionItem.FullName). No transaction was recovered."
        }
        $transactionRoot = $transactionItem.FullName
        $entries = @(Get-ChildItem -LiteralPath $transactionRoot -Force -ErrorAction Stop)
        $journalPath = Join-Path $transactionRoot 'transaction.json'
        if (-not (Test-Path -LiteralPath $journalPath -PathType Leaf)) {
            if ($entries.Count -eq 0) {
                Remove-Item -LiteralPath $transactionRoot -Force -ErrorAction Stop
                continue
            }
            throw "Retained skill transaction has data but no journal: $transactionRoot. Inspect it manually before retrying."
        }

        $journal = Read-SkillTransactionJournal -TransactionRoot $transactionRoot `
            -ExpectedDestinationLeaf $destinationLeaf
        $preparedTree = Read-PreparedTreeManifest -TransactionRoot $transactionRoot
        $phases = Read-SkillTransactionPhases -TransactionRoot $transactionRoot `
            -Journal $journal -PreparedTree $preparedTree
        $incomingPath = Join-Path $transactionRoot 'incoming'
        $previousPath = Join-Path $transactionRoot 'previous'
        $hasLive = Assert-OrdinaryTransactionDirectory -Path $destinationFull `
            -Purpose 'retained transaction live skill'
        $hasIncoming = Assert-OrdinaryTransactionDirectory -Path $incomingPath `
            -Purpose 'retained transaction incoming skill'
        $hasPrevious = Assert-OrdinaryTransactionDirectory -Path $previousPath `
            -Purpose 'retained transaction previous skill'
        $verifiedCommittedLive = $false

        if ($hasPrevious) {
            if (-not [bool]$journal.had_destination) {
                throw "Retained transaction '$transactionRoot' contains unexpected previous data. Inspect it manually before retrying."
            }
            if (($null -eq $preparedTree) -or
                (-not $phases.Contains('incoming-prepared'))) {
                throw "Retained transaction '$transactionRoot' moved previous data without a valid prepared-tree manifest and incoming-prepared phase. Recovery stopped without changing live or previous data."
            }
            if (-not $hasLive) {
                Move-Item -LiteralPath $previousPath -Destination $destinationFull -ErrorAction Stop
                $hasLive = $true
                $hasPrevious = $false
                Write-Warning "Recovered the previous skill at '$destinationFull' from interrupted transaction '$transactionRoot'."
            } elseif ($hasIncoming) {
                throw "Retained transaction '$transactionRoot' has live, previous, and incoming skill directories. Recovery is ambiguous; inspect these paths manually before retrying."
            } else {
                Assert-PreparedTreeMatches -Expected $preparedTree `
                    -ActualRoot $destinationFull -TransactionRoot $transactionRoot
                $verifiedCommittedLive = $true
                Remove-Item -LiteralPath $previousPath -Recurse -Force -ErrorAction Stop
                $hasPrevious = $false
                Write-Warning "Finalized the committed skill at '$destinationFull' from interrupted transaction '$transactionRoot'."
            }
        }

        if ((-not $hasLive) -and [bool]$journal.had_destination) {
            throw "Retained transaction '$transactionRoot' records a previous skill, but both live and previous directories are missing. Recovery stopped to avoid data loss."
        }
        $shouldVerifyCommittedLive = $phases.Contains('live-committed') -or
            ((-not [bool]$journal.had_destination) -and
                $phases.Contains('incoming-prepared'))
        if ((-not $verifiedCommittedLive) -and $hasLive -and (-not $hasIncoming) -and
            $shouldVerifyCommittedLive) {
            Assert-PreparedTreeMatches -Expected $preparedTree `
                -ActualRoot $destinationFull -TransactionRoot $transactionRoot
        }

        Assert-NoReparsePointTree -Path $transactionRoot -Purpose 'recovered skill transaction cleanup'
        Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction Stop
    }

    Remove-EmptySkillTransactionContainer -Path $container
}

function New-SkillTransaction {
    param(
        [Parameter(Mandatory = $true)][string]$SkillRoot,
        [Parameter(Mandatory = $true)][string]$DestinationLeaf,
        [Parameter(Mandatory = $true)][bool]$HadDestination
    )

    $container = Get-SkillTransactionContainerPath -SkillRoot $SkillRoot
    $containerItem = Get-FileSystemItemIncludingBrokenLink -Path $container
    if ($null -eq $containerItem) {
        New-Item -ItemType Directory -Path $container -ErrorAction Stop | Out-Null
        Set-PrivateDirectoryMode -Path $container
    } elseif ((Test-IsFileSystemLink -Item $containerItem) -or (-not $containerItem.PSIsContainer)) {
        throw "Skill transaction container is not an ordinary directory: $container"
    }
    Assert-NoReparsePointTree -Path $container -Purpose 'skill transaction creation'

    for ($attempt = 0; $attempt -lt 16; $attempt++) {
        $transactionId = 'txn-' + [guid]::NewGuid().ToString('N')
        $transactionRoot = Join-Path $container $transactionId
        try {
            New-Item -ItemType Directory -Path $transactionRoot -ErrorAction Stop | Out-Null
        } catch {
            if ($null -ne (Get-FileSystemItemIncludingBrokenLink -Path $transactionRoot)) {
                continue
            }
            throw "Could not create skill transaction directory '$transactionRoot'. $($_.Exception.Message)"
        }

        try {
            Set-PrivateDirectoryMode -Path $transactionRoot
            $journal = [ordered]@{
                schema_version = 1
                transaction_id = $transactionId
                destination_leaf = $DestinationLeaf
                had_destination = $HadDestination
                created_at_utc = [DateTime]::UtcNow.ToString('o')
            }
            $journalText = ($journal | ConvertTo-Json).Replace("`r`n", "`n") + "`n"
            Write-NewUtf8NoBomFile -Path (Join-Path $transactionRoot 'transaction.json') `
                -Content $journalText
            return [pscustomobject]@{
                Id = $transactionId
                Container = $container
                Root = $transactionRoot
                Incoming = Join-Path $transactionRoot 'incoming'
                Previous = Join-Path $transactionRoot 'previous'
            }
        } catch {
            $transactionError = $_
            try {
                if ($null -ne (Get-FileSystemItemIncludingBrokenLink -Path $transactionRoot)) {
                    Assert-NoReparsePointTree -Path $transactionRoot -Purpose 'failed skill transaction creation cleanup'
                    Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction Stop
                }
                Remove-EmptySkillTransactionContainer -Path $container
            } catch {
                throw "Could not initialize skill transaction '$transactionRoot' ('$($transactionError.Exception.Message)') and could not clean it up ('$($_.Exception.Message)'). Inspect the retained transaction before retrying."
            }
            throw "Could not initialize skill transaction '$transactionRoot'. $($transactionError.Exception.Message)"
        }
    }

    throw "Could not reserve a unique skill transaction below '$container' after 16 attempts."
}

function Add-SkillTransactionPhase {
    param(
        [Parameter(Mandatory = $true)][string]$TransactionRoot,
        [Parameter(Mandatory = $true)][string]$TransactionId,
        [Parameter(Mandatory = $true)][string]$PreparedTreeSha256,
        [ValidateSet('incoming-prepared', 'live-displaced', 'live-committed')]
        [Parameter(Mandatory = $true)][string]$Phase
    )

    $phaseOrder = @{
        'incoming-prepared' = '20'
        'live-displaced' = '30'
        'live-committed' = '40'
    }
    if (($TransactionId -notmatch '^txn-[0-9a-f]{32}$') -or
        ($PreparedTreeSha256 -notmatch '^[0-9a-f]{64}$')) {
        throw 'Cannot write a transaction phase marker with invalid identity metadata.'
    }
    $document = [ordered]@{
        schema_version = 1
        transaction_id = $TransactionId
        phase = $Phase
        prepared_tree_sha256 = $PreparedTreeSha256
        recorded_at_utc = [DateTime]::UtcNow.ToString('o')
    }
    $path = Join-Path $TransactionRoot ("phase-$($phaseOrder[$Phase])-$Phase.json")
    $text = ($document | ConvertTo-Json).Replace("`r`n", "`n") + "`n"
    Write-NewUtf8NoBomFile -Path $path -Content $text
}

function Remove-SkillTransaction {
    param([Parameter(Mandatory = $true)][object]$Transaction)

    if ($null -ne (Get-FileSystemItemIncludingBrokenLink -Path $Transaction.Root)) {
        Assert-NoReparsePointTree -Path $Transaction.Root -Purpose 'skill transaction cleanup'
        Remove-Item -LiteralPath $Transaction.Root -Recurse -Force -ErrorAction Stop
    }
    Remove-EmptySkillTransactionContainer -Path $Transaction.Container
}

function Install-StagedSkill {
    param(
        [Parameter(Mandatory = $true)][string]$StageDir,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $stageFull = Normalize-RootPath -Path $StageDir
    $destinationFull = Normalize-RootPath -Path $Destination
    $parent = Split-Path -Parent $destinationFull
    $destinationLeaf = [System.IO.Path]::GetFileName($destinationFull)
    if ([string]::IsNullOrEmpty($parent) -or [string]::IsNullOrEmpty($destinationLeaf)) {
        throw "Skill destination must have a parent directory and leaf name: $Destination"
    }
    if (-not (Test-Path -LiteralPath $stageFull -PathType Container)) {
        throw "Staged skill directory is missing: $stageFull"
    }
    Assert-NoReparsePointTree -Path $stageFull -Purpose 'staged skill installation source'

    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        throw "Skill destination parent is not a directory: $parent"
    }
    Assert-NoExistingReparsePoint -Path $parent -Purpose 'skill transaction swap'
    # Recheck at the swap boundary. The outer preflight recovers before backup;
    # this second pass catches out-of-band changes that do not honor our Mutex.
    Recover-SkillTransactions -Destination $destinationFull

    $destinationItem = Get-FileSystemItemIncludingBrokenLink -Path $destinationFull
    $hadDestination = $null -ne $destinationItem
    if ($hadDestination) {
        if (-not $destinationItem.PSIsContainer) {
            throw "Existing skill destination is not a directory: $destinationFull"
        }
        Assert-NoReparsePointTree -Path $destinationFull -Purpose 'existing skill displacement'
    }

    $transaction = New-SkillTransaction -SkillRoot $parent `
        -DestinationLeaf $destinationLeaf -HadDestination $hadDestination
    $incomingPath = $transaction.Incoming
    $previousPath = $transaction.Previous
    $mutationState = 'unchanged'
    $operationSucceeded = $false
    $failureMessage = $null
    try {
        New-Item -ItemType Directory -Path $incomingPath -ErrorAction Stop | Out-Null
        Set-PrivateDirectoryMode -Path $incomingPath
        try {
            foreach ($child in @(Get-ChildItem -LiteralPath $stageFull -Force -ErrorAction Stop)) {
                Copy-Item -LiteralPath $child.FullName -Destination $incomingPath `
                    -Recurse -Force -ErrorAction Stop
            }
            Assert-DirectoryCopyMatches -Source $stageFull -Copy $incomingPath
            $preparedTree = Write-PreparedTreeManifest `
                -TransactionRoot $transaction.Root -IncomingRoot $incomingPath
            Add-SkillTransactionPhase -TransactionRoot $transaction.Root `
                -TransactionId $transaction.Id `
                -PreparedTreeSha256 $preparedTree.TreeSha256 -Phase 'incoming-prepared'
        } catch {
            throw "Could not prepare a complete incoming skill copy at '$incomingPath'. The live destination was not changed. $($_.Exception.Message)"
        }

        # Recheck the transaction boundary immediately before moving live data.
        Assert-NoExistingReparsePoint -Path $parent -Purpose 'skill transaction commit'
        Assert-NoReparsePointTree -Path $transaction.Root -Purpose 'incoming skill transaction commit'
        $currentDestination = Get-FileSystemItemIncludingBrokenLink -Path $destinationFull
        if ($hadDestination) {
            if (($null -eq $currentDestination) -or (-not $currentDestination.PSIsContainer)) {
                throw "Existing skill destination changed before transaction commit: $destinationFull"
            }
            Assert-NoReparsePointTree -Path $destinationFull -Purpose 'existing skill transaction commit'
            Move-Item -LiteralPath $destinationFull -Destination $previousPath -ErrorAction Stop
            $mutationState = 'displaced'
            Add-SkillTransactionPhase -TransactionRoot $transaction.Root `
                -TransactionId $transaction.Id `
                -PreparedTreeSha256 $preparedTree.TreeSha256 -Phase 'live-displaced'
        } elseif ($null -ne $currentDestination) {
            throw "Skill destination appeared before transaction commit: $destinationFull"
        }

        Move-Item -LiteralPath $incomingPath -Destination $destinationFull -ErrorAction Stop
        $mutationState = 'committed'
        Add-SkillTransactionPhase -TransactionRoot $transaction.Root `
            -TransactionId $transaction.Id `
            -PreparedTreeSha256 $preparedTree.TreeSha256 -Phase 'live-committed'
        $operationSucceeded = $true

        if ($null -ne (Get-FileSystemItemIncludingBrokenLink -Path $previousPath)) {
            try {
                Assert-NoReparsePointTree -Path $previousPath -Purpose 'previous skill cleanup'
                Remove-Item -LiteralPath $previousPath -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Warning "Installed '$destinationFull' but retained recovery transaction '$($transaction.Root)' because previous skill data could not be removed. A later installer run will retry recovery. $($_.Exception.Message)"
                return [pscustomobject]@{ MutationState = $mutationState; Destination = $destinationFull }
            }
        }

        try {
            Remove-SkillTransaction -Transaction $transaction
        } catch {
            Write-Warning "Installed '$destinationFull' but could not remove completed transaction '$($transaction.Root)'. A later installer run will retry cleanup. $($_.Exception.Message)"
        }
    } catch {
        $failureMessage = $_.Exception.Message
    }

    if (-not $operationSucceeded) {
        try {
            $liveItem = Get-FileSystemItemIncludingBrokenLink -Path $destinationFull
            $previousItem = Get-FileSystemItemIncludingBrokenLink -Path $previousPath
            $incomingItem = Get-FileSystemItemIncludingBrokenLink -Path $incomingPath

            if (($mutationState -eq 'unchanged') -and
                ($null -eq $liveItem) -and ($null -ne $previousItem)) {
                $mutationState = 'displaced'
            }

            if ($mutationState -eq 'displaced') {
                if (($null -eq $liveItem) -and ($null -ne $previousItem)) {
                    Assert-OrdinaryTransactionDirectory -Path $previousPath `
                        -Purpose 'failed transaction previous skill restoration' | Out-Null
                    Move-Item -LiteralPath $previousPath -Destination $destinationFull -ErrorAction Stop
                    $mutationState = 'restored-exact'
                } else {
                    $mutationState = 'indeterminate'
                }
            } elseif ($mutationState -eq 'committed') {
                if ($null -ne $liveItem) {
                    Assert-OrdinaryTransactionDirectory -Path $destinationFull `
                        -Purpose 'failed committed skill restoration' | Out-Null
                    if ($null -ne $incomingItem) {
                        $mutationState = 'indeterminate'
                    } else {
                        Move-Item -LiteralPath $destinationFull -Destination $incomingPath -ErrorAction Stop
                        if ($hadDestination) {
                            if ($null -eq $previousItem) {
                                $mutationState = 'indeterminate'
                            } else {
                                Move-Item -LiteralPath $previousPath -Destination $destinationFull -ErrorAction Stop
                                $mutationState = 'restored-exact'
                            }
                        } else {
                            $mutationState = 'restored-exact'
                        }
                    }
                } else {
                    $mutationState = 'indeterminate'
                }
            } elseif ($mutationState -eq 'unchanged') {
                $expectedLive = $hadDestination
                $actualLive = $null -ne $liveItem
                if (($expectedLive -ne $actualLive) -or ($null -ne $previousItem)) {
                    $mutationState = 'indeterminate'
                }
            }

            if (($mutationState -eq 'unchanged') -or ($mutationState -eq 'restored-exact')) {
                Remove-SkillTransaction -Transaction $transaction
            }
        } catch {
            $mutationState = 'indeterminate'
            $failureMessage += " Automatic exact restoration or transaction cleanup also failed: $($_.Exception.Message). Retained transaction: '$($transaction.Root)'."
        }

        if ($mutationState -eq 'restored-exact') {
            if ($hadDestination) {
                $failureMessage += " The previous skill was restored exactly at '$destinationFull'; automatic snapshot rollback will not replace it."
            } else {
                $failureMessage += " The original absent state was restored exactly at '$destinationFull'; automatic snapshot rollback will not rewrite it."
            }
        }

        $failure = New-Object System.InvalidOperationException -ArgumentList $failureMessage
        $failure.Data['AgentToolRoutingSkillMutationState'] = $mutationState
        $failure.Data['AgentToolRoutingSkillDestination'] = $destinationFull
        throw $failure
    }

    return [pscustomobject]@{ MutationState = $mutationState; Destination = $destinationFull }
}

function Remove-StagingDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        if (-not (Test-Path -LiteralPath $Path)) {
            return
        }
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force
            return
        } catch {
            if ($attempt -lt 3) {
                Start-Sleep -Milliseconds (50 * [math]::Pow(2, $attempt))
            } else {
                Write-Warning "Could not remove staging directory '$Path' after installation. It remains inside the backup snapshot and can be removed later. $($_.Exception.Message)"
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $VersionSource -PathType Leaf)) {
    throw "Missing VERSION at repository root: $VersionSource"
}
$ProjectVersion = [System.IO.File]::ReadAllText($VersionSource).Trim()
if ($ProjectVersion -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
    throw "VERSION must contain one semantic version without a leading 'v': $VersionSource"
}
if (-not (Test-Path -LiteralPath $SkillSource -PathType Leaf)) {
    throw "Missing SKILL.md at repository root: $SkillSource"
}
if (-not (Test-Path -LiteralPath $AgentsSource -PathType Container)) {
    throw "Missing agents directory at repository root: $AgentsSource"
}
if (-not (Test-Path -LiteralPath $ReferencesSource -PathType Container)) {
    throw "Missing references directory at repository root: $ReferencesSource"
}
if (-not (Test-Path -LiteralPath $ExamplesSource -PathType Container)) {
    throw "Missing examples directory at repository root: $ExamplesSource"
}
foreach ($referenceFile in $RequiredReferenceFiles) {
    $referencePath = Join-Path $ReferencesSource $referenceFile
    if (-not (Test-Path -LiteralPath $referencePath -PathType Leaf)) {
        throw "Missing required skill reference: $referencePath"
    }
}
foreach ($exampleFile in $RequiredExampleFiles) {
    $examplePath = Join-Path $ExamplesSource $exampleFile
    if (-not (Test-Path -LiteralPath $examplePath -PathType Leaf)) {
        throw "Missing required skill example: $examplePath"
    }
}
Assert-NoExistingReparsePoint -Path $VersionSource -Purpose 'source version staging'
Assert-NoExistingReparsePoint -Path $SkillSource -Purpose 'source skill staging'
Assert-NoReparsePointTree -Path $AgentsSource -Purpose 'source agents staging'
Assert-NoReparsePointTree -Path $ReferencesSource -Purpose 'source references staging'
Assert-NoReparsePointTree -Path $ExamplesSource -Purpose 'source examples staging'

$UserProfileFull = Normalize-RootPath -Path $UserProfile
$OsUserProfileFull = Normalize-RootPath -Path ([Environment]::GetFolderPath('UserProfile'))
if (-not [string]::Equals($UserProfileFull, $OsUserProfileFull, $PathComparison)) {
    if (-not $AllowCustomProfile) {
        throw "Refusing custom -UserProfile '$UserProfileFull' without -AllowCustomProfile."
    }
    Write-Warning "Using custom profile root for installation defaults: $UserProfileFull"
}

$CodexHomeFull = Get-ConfiguredRoot -ExplicitValue $CodexHome -EnvironmentName 'CODEX_HOME' -Fallback (Join-Path $UserProfileFull '.codex')
$ClaudeConfigDirFull = Get-ConfiguredRoot -ExplicitValue $ClaudeConfigDir -EnvironmentName 'CLAUDE_CONFIG_DIR' -Fallback (Join-Path $UserProfileFull '.claude')
$ZcodeHomeFull = Get-ConfiguredRoot -ExplicitValue $ZcodeHome -EnvironmentName 'ZCODE_HOME' -Fallback (Join-Path $UserProfileFull '.zcode')
$initializeRoutingRequested = [bool]$InitializeRouting
$wantRuntime = [bool]($AddRuntimeRules -or $AddGlobalRules)
$wantOnboarding = [bool]($AddOnboardingRules -or $AddGlobalRules -or $initializeRoutingRequested)
$targetNames = if ($Target -eq 'all') { @('codex', 'claude', 'zcode') } else { @($Target) }
$configs = @($targetNames | ForEach-Object { Get-AgentConfig -Agent $_ })
$plans = New-Object System.Collections.Generic.List[object]
$agentInstallLocks = @(Enter-AgentInstallLocks -Configs $configs)
try {
    # Reject source-target aliasing even in WhatIf mode. This check is read-only
    # and runs under the same config-root lock as the remaining preflight.
    foreach ($config in $configs) {
        foreach ($targetPath in @($config.SkillDir, $config.GlobalFile, $config.IndexRequest)) {
            if (Test-PathsOverlap -First $RepoRoot -Second $targetPath) {
                throw "Refusing $($config.Name) target '$targetPath' because it overlaps source repository '$RepoRoot'. Choose an agent config root outside this checkout."
            }
        }
    }

    $operationDescription = "Install tool-routing architecture for $($targetNames -join ', ')"
    if (-not $PSCmdlet.ShouldProcess(($configs.ConfigRoot -join ', '), $operationDescription)) {
        return
    }

# Hold every config-root lock while recovering retained transactions, planning,
# installing, and performing any automatic rollback.
foreach ($config in $configs) {
    foreach ($targetPath in @($config.SkillDir, $config.GlobalFile, $config.RuntimeDependency, $config.IndexRequest)) {
        if (-not (Test-PathContained -Parent $config.ConfigRoot -Child $targetPath)) {
            throw "Computed target '$targetPath' escapes config root '$($config.ConfigRoot)'."
        }
    }
    Assert-NoExistingReparsePoint -Path $config.ConfigRoot -Purpose "$($config.Name) config access"
    Recover-SkillTransactions -Destination $config.SkillDir
    Assert-NoReparsePointTree -Path $config.SkillDir -Purpose "$($config.Name) skill installation"
    Assert-NoExistingReparsePoint -Path $config.IndexRequest -Purpose "$($config.Name) initial routing state"
    $existingIndexRequest = Get-ExistingInitialIndexRequest -Config $config
    $config | Add-Member -NotePropertyName ExistingIndexRequestBase64 -NotePropertyValue $existingIndexRequest
    $newIndexRequestText = if ($initializeRoutingRequested -and
        [string]::IsNullOrWhiteSpace($existingIndexRequest)) {
        New-InitialIndexRequestText -Config $config
    } else {
        $null
    }
    $config | Add-Member -NotePropertyName NewIndexRequestText -NotePropertyValue $newIndexRequestText
    if ($wantRuntime -or $wantOnboarding) {
        Assert-NoExistingReparsePoint -Path $config.GlobalFile -Purpose "$($config.Name) global rule installation"
        if (-not (Test-Path -LiteralPath $config.Snippet -PathType Leaf)) {
            throw "Missing global instruction snippet: $($config.Snippet)"
        }
        $globalPlan = New-GlobalFilePlan -Config $config -WantRuntime $wantRuntime -WantOnboarding $wantOnboarding
        if ($globalPlan.WritesRuntime -and -not (Test-Path -LiteralPath $config.RuntimeDependency -PathType Leaf)) {
            throw "Runtime routing for $($config.Name) requires tool-index at '$($config.RuntimeDependency)'. The planned rules may come from an explicit runtime request or preserved legacy managed content. Install tool-index before continuing."
        }
        if ($initializeRoutingRequested -and -not $globalPlan.WritesOnboarding) {
            throw "Initial routing for $($config.Name) requires a managed Tool Onboarding Gate. Remove or mark the existing unmanaged section before retrying."
        }
    } else {
        $globalPlan = [pscustomobject]@{
            FileInfo = $null
            UpdatedText = $null
            Changed = $false
            WritesRuntime = $false
            WritesOnboarding = $false
            Status = 'not requested'
        }
    }
    $plans.Add([pscustomobject]@{ Config = $config; Global = $globalPlan; StageDir = $null })
}

$mutationTargets = New-Object System.Collections.Generic.List[object]
foreach ($plan in $plans) {
    $mutationTargets.Add([pscustomobject]@{
        Agent = $plan.Config.Name
        Kind = 'skill directory'
        Path = $plan.Config.SkillDir
    })
    if ($wantRuntime -or $wantOnboarding) {
        $mutationTargets.Add([pscustomobject]@{
            Agent = $plan.Config.Name
            Kind = 'global instructions'
            Path = $plan.Config.GlobalFile
        })
    }
    if (-not [string]::IsNullOrWhiteSpace($plan.Config.NewIndexRequestText)) {
        $mutationTargets.Add([pscustomobject]@{
            Agent = $plan.Config.Name
            Kind = 'initial routing request'
            Path = $plan.Config.IndexRequest
        })
    }
}
foreach ($mutationTarget in $mutationTargets) {
    if (Test-PathsOverlap -First $RepoRoot -Second $mutationTarget.Path) {
        throw "Refusing $($mutationTarget.Agent) $($mutationTarget.Kind) '$($mutationTarget.Path)' because it overlaps source repository '$RepoRoot'. Choose an agent config root outside this checkout."
    }
}
for ($firstIndex = 0; $firstIndex -lt $mutationTargets.Count; $firstIndex++) {
    for ($secondIndex = $firstIndex + 1; $secondIndex -lt $mutationTargets.Count; $secondIndex++) {
        $firstTarget = $mutationTargets[$firstIndex]
        $secondTarget = $mutationTargets[$secondIndex]
        if (Test-PathsOverlap -First $firstTarget.Path -Second $secondTarget.Path) {
            throw "Refusing overlapping mutation paths for $($firstTarget.Agent) $($firstTarget.Kind) '$($firstTarget.Path)' and $($secondTarget.Agent) $($secondTarget.Kind) '$($secondTarget.Path)'. Use distinct agent config roots."
        }
    }
}

$backupParent = if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
    Join-Path $UserProfileFull 'agent-tool-routing-backups'
} else {
    $BackupRoot
}
$backupParent = Normalize-RootPath -Path $backupParent
if ((Test-Path -LiteralPath $backupParent) -and -not (Test-Path -LiteralPath $backupParent -PathType Container)) {
    throw "BackupRoot must be a directory parent: $backupParent"
}
Assert-NoExistingReparsePoint -Path $backupParent -Purpose 'backup creation'

$overlapCandidates = New-Object System.Collections.Generic.List[string]
$overlapCandidates.Add($RepoRoot)
foreach ($plan in $plans) {
    $overlapCandidates.Add($plan.Config.SkillRoot)
    $overlapCandidates.Add($plan.Config.SkillDir)
    $overlapCandidates.Add($plan.Config.GlobalFile)
    $overlapCandidates.Add($plan.Config.IndexRequest)
}
foreach ($candidate in $overlapCandidates) {
    if (Test-PathsOverlap -First $backupParent -Second $candidate) {
        throw "BackupRoot parent '$backupParent' overlaps repository or target path '$candidate'."
    }
}

if (-not (Test-Path -LiteralPath $backupParent)) {
    New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
}
$snapshotName = 'install-{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), ([guid]::NewGuid().ToString('N').Substring(0, 12))
$snapshotRoot = Join-Path $backupParent $snapshotName
if (Test-Path -LiteralPath $snapshotRoot) {
    $entries = @(Get-ChildItem -LiteralPath $snapshotRoot -Force)
    if ($entries.Count -gt 0) {
        throw "Refusing to reuse non-empty backup snapshot: $snapshotRoot"
    }
    throw "Refusing to reuse existing backup snapshot: $snapshotRoot"
}
New-Item -ItemType Directory -Path $snapshotRoot | Out-Null
$stageRoot = Join-Path $snapshotRoot 'stage'
New-Item -ItemType Directory -Path $stageRoot | Out-Null

foreach ($plan in $plans) {
    $plan.StageDir = Stage-AgentSkill -Config $plan.Config -StageRoot $stageRoot
}

$rollbackPreflightCommands = New-Object System.Collections.Generic.List[string]
$rollbackCommands = New-Object System.Collections.Generic.List[string]
foreach ($plan in $plans) {
    Add-BackupAndRollback -Path $plan.Config.SkillDir -Label "$($plan.Config.Name)-skill" `
        -PreflightCommands $rollbackPreflightCommands -Commands $rollbackCommands `
        -SnapshotRoot $snapshotRoot
    if ($plan.Global.Changed) {
        Add-BackupAndRollback -Path $plan.Config.GlobalFile -Label "$($plan.Config.Name)-global" `
            -PreflightCommands $rollbackPreflightCommands -Commands $rollbackCommands `
            -SnapshotRoot $snapshotRoot
    }
    if (-not [string]::IsNullOrWhiteSpace($plan.Config.NewIndexRequestText)) {
        $requestBytes = (New-Object Text.UTF8Encoding($false)).GetBytes(
            $plan.Config.NewIndexRequestText
        )
        $requestBase64 = [Convert]::ToBase64String($requestBytes)
        $requestMetadata = $plan.Config.NewIndexRequestText | ConvertFrom-Json
        $quotedRequestPath = Quote-PowerShellLiteral -Value $plan.Config.IndexRequest
        $quotedRequestBase64 = Quote-PowerShellLiteral -Value $requestBase64
        $quotedRequestId = Quote-PowerShellLiteral -Value ([string]$requestMetadata.request_id)
        $rollbackCommands.Add(
            "Remove-UnchangedAgentToolRoutingRequest -Path $quotedRequestPath -ExpectedContentBase64 $quotedRequestBase64 -ExpectedRequestId $quotedRequestId"
        )
    }
}

$rollbackPath = Join-Path $snapshotRoot 'rollback.ps1'
$rollbackHelper = @'
function Test-AgentToolRoutingRollbackSelected {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyCollection()][string[]]$OnlyPaths
    )

    if ($OnlyPaths.Count -eq 0) {
        return $true
    }
    $comparison = if (([IO.Path]::DirectorySeparatorChar -eq [char]'\') -or
        [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::OSX
        )) {
        [StringComparison]::OrdinalIgnoreCase
    } else {
        [StringComparison]::Ordinal
    }
    $full = [IO.Path]::GetFullPath($Path)
    foreach ($candidate in $OnlyPaths) {
        if ([string]::Equals($full, [IO.Path]::GetFullPath($candidate), $comparison)) {
            return $true
        }
    }
    return $false
}

function Restore-AgentToolRoutingPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Nullable[int]]$UnixModeValue = $null
    )

    if (-not (Test-Path -LiteralPath $BackupPath)) {
        throw "Rollback backup is missing: $BackupPath"
    }

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $leaf = [System.IO.Path]::GetFileName($Path)
    $token = [guid]::NewGuid().ToString('N')
    $restorePath = Join-Path $parent ('.{0}.{1}.restore' -f $leaf, $token)
    $displacedPath = Join-Path $parent ('.{0}.{1}.failed-install' -f $leaf, $token)
    $hadCurrent = $false

    try {
        Copy-Item -LiteralPath $BackupPath -Destination $restorePath -Recurse -Force
        if (($null -ne $UnixModeValue) -and
            (Test-Path -LiteralPath $restorePath -PathType Leaf)) {
            [System.IO.File]::SetUnixFileMode(
                $restorePath,
                [System.IO.UnixFileMode][int]$UnixModeValue
            )
        }

        $hadCurrent = Test-Path -LiteralPath $Path
        if ($hadCurrent) {
            Move-Item -LiteralPath $Path -Destination $displacedPath
        }

        try {
            Move-Item -LiteralPath $restorePath -Destination $Path
        } catch {
            $restoreError = $_
            if ($hadCurrent -and
                (Test-Path -LiteralPath $displacedPath) -and
                (-not (Test-Path -LiteralPath $Path))) {
                try {
                    Move-Item -LiteralPath $displacedPath -Destination $Path
                } catch {
                    $recoveryError = $_
                    throw "Rollback could not install the staged backup for '$Path' ('$($restoreError.Exception.Message)') and could not restore the displaced live target from '$displacedPath' ('$($recoveryError.Exception.Message)'). Live data remains at '$displacedPath'."
                }
            }
            throw $restoreError
        }

        if ($hadCurrent -and (Test-Path -LiteralPath $displacedPath)) {
            try {
                Remove-Item -LiteralPath $displacedPath -Recurse -Force
            } catch {
                Write-Warning "Rollback restored '$Path' but could not remove displaced data '$displacedPath'. $($_.Exception.Message)"
            }
        }
    } finally {
        if (Test-Path -LiteralPath $restorePath) {
            try {
                Remove-Item -LiteralPath $restorePath -Recurse -Force
            } catch {
                Write-Warning "Could not remove incomplete rollback staging path '$restorePath'. $($_.Exception.Message)"
            }
        }
    }
}

function Remove-UnchangedAgentToolRoutingRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedContentBase64,
        [Parameter(Mandatory = $true)][string]$ExpectedRequestId
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $isReparsePoint = ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
        if ($item.PSIsContainer -or $isReparsePoint) {
            Write-Warning "Initial routing request is not an ordinary file and was preserved for manual review: $Path"
            return
        }
        if ($item.Length -gt 131072) {
            Write-Warning "Initial routing request exceeds 131072 bytes and was preserved for manual review: $Path"
            return
        }

        $currentBytes = [IO.File]::ReadAllBytes($Path)
        $currentBase64 = [Convert]::ToBase64String($currentBytes)
        $requestId = $null
        try {
            $strictUtf8 = New-Object Text.UTF8Encoding -ArgumentList $false, $true
            $currentText = $strictUtf8.GetString($currentBytes)
            $request = $currentText | ConvertFrom-Json -ErrorAction Stop
            $requestId = [string]$request.request_id
        } catch {
            Write-Warning "Initial routing request is no longer valid UTF-8 JSON and was preserved for manual review: $Path"
            return
        }

        $contentMatches = [string]::Equals(
            $currentBase64,
            $ExpectedContentBase64,
            [StringComparison]::Ordinal
        )
        $requestIdMatches = [string]::Equals(
            $requestId,
            $ExpectedRequestId,
            [StringComparison]::Ordinal
        )
        if (-not ($contentMatches -and $requestIdMatches)) {
            Write-Warning "Initial routing request changed after installation and was preserved for manual review: $Path"
            return
        }

        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        Write-Warning "Could not safely clean initial routing request '$Path'; it was preserved for manual review. $($_.Exception.Message)"
    }
}
'@
$rollbackHelperLines = @([regex]::Split($rollbackHelper.Trim(), '\r\n|\n|\r'))
$rollbackLines = @(
    '[CmdletBinding()]',
    'param([string[]]$OnlyPath = @())',
    '$ErrorActionPreference = ''Stop''',
    '# Generated rollback for agent-tool-routing-skill installation.'
) + $rollbackHelperLines + @('') + $rollbackPreflightCommands.ToArray() + @('') +
    $rollbackCommands.ToArray() + @("Write-Output 'Rollback complete.'", '')
Write-Utf8BomFileAtomic -Path $rollbackPath -Content ($rollbackLines -join "`r`n")

$results = New-Object System.Collections.Generic.List[object]
$automaticRollbackPaths = New-Object System.Collections.Generic.List[string]
$createdIndexRequests = New-Object System.Collections.Generic.List[object]
try {
    foreach ($plan in $plans) {
        try {
            $skillInstallResult = Install-StagedSkill -StageDir $plan.StageDir `
                -Destination $plan.Config.SkillDir
            $automaticRollbackPaths.Add($plan.Config.SkillDir)
        } catch {
            $skillInstallError = $_
            $mutationState = [string]$skillInstallError.Exception.Data[
                'AgentToolRoutingSkillMutationState'
            ]
            if ((-not [string]::IsNullOrEmpty($mutationState)) -and
                ($mutationState -ne 'unchanged') -and
                ($mutationState -ne 'restored-exact')) {
                $automaticRollbackPaths.Add($plan.Config.SkillDir)
            }
            throw
        }
        if ($plan.Global.Changed) {
            # A failing atomic write can be ambiguous, so select this path before writing.
            $automaticRollbackPaths.Add($plan.Config.GlobalFile)
            Write-TextFileAtomic -Path $plan.Config.GlobalFile -Content $plan.Global.UpdatedText `
                -Encoding $plan.Global.FileInfo.Encoding -EmitBom $plan.Global.FileInfo.EmitBom
        }
        $results.Add([pscustomobject]@{
            Agent = $plan.Config.Name
            Version = $ProjectVersion
            Skill = $plan.Config.SkillName
            SkillDir = $plan.Config.SkillDir
            GlobalFile = $plan.Config.GlobalFile
            GlobalRules = $plan.Global.Status
        })
    }
    foreach ($plan in $plans) {
        if (-not [string]::IsNullOrWhiteSpace($plan.Config.NewIndexRequestText)) {
            Assert-NoExistingReparsePoint -Path $plan.Config.IndexRequest `
                -Purpose "$($plan.Config.Name) initial routing state creation"
            Write-NewUtf8NoBomFile -Path $plan.Config.IndexRequest `
                -Content $plan.Config.NewIndexRequestText
            $createdIndexRequests.Add([pscustomobject]@{
                Path = $plan.Config.IndexRequest
                ContentBase64 = [Convert]::ToBase64String(
                    (New-Object Text.UTF8Encoding($false)).GetBytes($plan.Config.NewIndexRequestText)
                )
            })
        }
    }
} catch {
    $installError = $_
    foreach ($createdRequest in $createdIndexRequests) {
        try {
            if (Test-Path -LiteralPath $createdRequest.Path -PathType Leaf) {
                $currentBytes = [IO.File]::ReadAllBytes($createdRequest.Path)
                $currentBase64 = [Convert]::ToBase64String($currentBytes)
                if ([string]::Equals(
                        $currentBase64,
                        $createdRequest.ContentBase64,
                        [StringComparison]::Ordinal)) {
                    Remove-Item -LiteralPath $createdRequest.Path -Force
                } else {
                    Write-Warning "Initial routing request changed before rollback cleanup and was preserved: $($createdRequest.Path)"
                }
            }
        } catch {
            Write-Warning "Could not clean initial routing request '$($createdRequest.Path)' before core rollback: $($_.Exception.Message)"
        }
    }
    if ($automaticRollbackPaths.Count -gt 0) {
        try {
            & $rollbackPath -OnlyPath $automaticRollbackPaths.ToArray() | Out-Null
            Write-Warning "Installation failed and target changes were rolled back. Snapshot: $snapshotRoot"
        } catch {
            throw "Installation failed ('$($installError.Exception.Message)') and automatic rollback also failed ('$($_.Exception.Message)'). Run '$rollbackPath' after resolving the rollback error."
        }
    }
    throw $installError
}

Remove-StagingDirectory -Path $stageRoot

Write-Output "Installed agent tool-routing skill v$ProjectVersion."
Write-Output "Backup: $snapshotRoot"
Write-Output "Rollback: $rollbackPath"
$results | Format-Table -AutoSize

if ($initializeRoutingRequested) {
    foreach ($plan in $plans) {
        Write-Output "Initial routing request: $($plan.Config.IndexRequest)"
        Write-Output "If an Agent invoked this installer, it should process the request before returning to ordinary work. Otherwise the target Agent will process it in its next fresh session."
    }
}
} finally {
    Exit-AgentInstallLocks -Locks $agentInstallLocks
}
