[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('all', 'codex', 'claude', 'zcode')]
    [string]$Target = 'all',

    [switch]$AddGlobalRules,

    [switch]$AddOnboardingRules,

    [switch]$AddRuntimeRules,

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
$RequiredReferenceFiles = @('lifecycle.md', 'authoring.md', 'runtime-adapters.md', 'route-tests.md')
$ExamplesSource = Join-Path $RepoRoot 'examples'
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

    if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        return $true
    }
    $linkTypeProperty = $Item.PSObject.Properties['LinkType']
    return ($null -ne $linkTypeProperty) -and
        (-not [string]::IsNullOrEmpty([string]$linkTypeProperty.Value))
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
            $item = Get-Item -LiteralPath $next -Force -ErrorAction Stop
            if (Test-IsFileSystemLink -Item $item) {
                try {
                    $resolved = $item.ResolveLinkTarget($true)
                } catch {
                    throw "Cannot resolve symbolic link '$next' while validating path '$Path'. $($_.Exception.Message)"
                }
                if ($null -eq $resolved) {
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
    $candidateItem = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
    while ($null -eq $candidateItem) {
        $leaf = [System.IO.Path]::GetFileName($candidate)
        $parent = [System.IO.Path]::GetDirectoryName($candidate)
        if ([string]::IsNullOrEmpty($leaf) -or [string]::IsNullOrEmpty($parent) -or
            [string]::Equals($parent, $candidate, $PathComparison)) {
            break
        }
        $remaining.Push($leaf)
        $candidate = $parent
        $candidateItem = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
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
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
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
    $rootItem = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
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
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
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
            } elseif (Test-UnmanagedSection -Content $updated -Heading 'Tool Onboarding Gate') {
                $statuses.Add('onboarding unmarked; left unchanged')
            } else {
                $updated = Add-ManagedBlock -Content $updated -Block $onboardingBlock -NewLine $newLine
                $statuses.Add('onboarding installed or updated')
            }
        }
    }

    [void](Assert-ManagedMarkers -Content $updated -Path $Config.GlobalFile)
    return [pscustomobject]@{
        FileInfo = $fileInfo
        UpdatedText = $updated
        Changed = -not [string]::Equals($existing, $updated, [System.StringComparison]::Ordinal)
        WritesRuntime = $writesRuntime
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
            }
        }
        default { throw "Unknown agent target: $Agent" }
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
        $Commands.Add("Restore-AgentToolRoutingPath -Path $quotedPath -BackupPath $quotedBackup$unixModeArgument")
    } else {
        $Commands.Add("if (Test-Path -LiteralPath $quotedPath) { Remove-Item -LiteralPath $quotedPath -Recurse -Force }")
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

    foreach ($referenceFile in $RequiredReferenceFiles) {
        $stagedReference = Join-PathSegments -Root $stageDir -Segments @('references', $referenceFile)
        if (-not (Test-Path -LiteralPath $stagedReference -PathType Leaf)) {
            throw "Staged skill for $($Config.Name) is missing required reference: $stagedReference"
        }
    }

    if ($Config.Name -eq 'codex') {
        $files = @((Join-Path $stageDir 'SKILL.md'), (Join-PathSegments -Root $stageDir -Segments @('agents', 'openai.yaml')))
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

function Install-StagedSkill {
    param(
        [Parameter(Mandatory = $true)][string]$StageDir,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }
    Copy-Item -LiteralPath $StageDir -Destination $Destination -Recurse -Force
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
foreach ($referenceFile in $RequiredReferenceFiles) {
    $referencePath = Join-Path $ReferencesSource $referenceFile
    if (-not (Test-Path -LiteralPath $referencePath -PathType Leaf)) {
        throw "Missing required skill reference: $referencePath"
    }
}
Assert-NoExistingReparsePoint -Path $VersionSource -Purpose 'source version staging'
Assert-NoExistingReparsePoint -Path $SkillSource -Purpose 'source skill staging'
Assert-NoReparsePointTree -Path $AgentsSource -Purpose 'source agents staging'
Assert-NoReparsePointTree -Path $ReferencesSource -Purpose 'source references staging'

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
$wantRuntime = [bool]($AddRuntimeRules -or $AddGlobalRules)
$wantOnboarding = [bool]($AddOnboardingRules -or $AddGlobalRules)
$targetNames = if ($Target -eq 'all') { @('codex', 'claude', 'zcode') } else { @($Target) }
$configs = @($targetNames | ForEach-Object { Get-AgentConfig -Agent $_ })
$plans = New-Object System.Collections.Generic.List[object]

# Complete every read-only validation before creating a snapshot or touching a target.
foreach ($config in $configs) {
    foreach ($targetPath in @($config.SkillDir, $config.GlobalFile, $config.RuntimeDependency)) {
        if (-not (Test-PathContained -Parent $config.ConfigRoot -Child $targetPath)) {
            throw "Computed target '$targetPath' escapes config root '$($config.ConfigRoot)'."
        }
    }
    Assert-NoExistingReparsePoint -Path $config.ConfigRoot -Purpose "$($config.Name) config access"
    Assert-NoReparsePointTree -Path $config.SkillDir -Purpose "$($config.Name) skill installation"
    if ($wantRuntime -or $wantOnboarding) {
        Assert-NoExistingReparsePoint -Path $config.GlobalFile -Purpose "$($config.Name) global rule installation"
        if (-not (Test-Path -LiteralPath $config.Snippet -PathType Leaf)) {
            throw "Missing global instruction snippet: $($config.Snippet)"
        }
        $globalPlan = New-GlobalFilePlan -Config $config -WantRuntime $wantRuntime -WantOnboarding $wantOnboarding
        if ($globalPlan.WritesRuntime -and -not (Test-Path -LiteralPath $config.RuntimeDependency -PathType Leaf)) {
            throw "Runtime routing for $($config.Name) requires tool-index at '$($config.RuntimeDependency)'. The planned rules may come from an explicit runtime request or preserved legacy managed content. Install tool-index before continuing."
        }
    } else {
        $globalPlan = [pscustomobject]@{
            FileInfo = $null
            UpdatedText = $null
            Changed = $false
            WritesRuntime = $false
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
}
foreach ($candidate in $overlapCandidates) {
    if (Test-PathsOverlap -First $backupParent -Second $candidate) {
        throw "BackupRoot parent '$backupParent' overlaps repository or target path '$candidate'."
    }
}

$operationDescription = "Install tool-routing architecture for $($targetNames -join ', ')"
if (-not $PSCmdlet.ShouldProcess(($configs.ConfigRoot -join ', '), $operationDescription)) {
    return
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
}

$rollbackPath = Join-Path $snapshotRoot 'rollback.ps1'
$rollbackHelper = @'
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
'@
$rollbackHelperLines = @([regex]::Split($rollbackHelper.Trim(), '\r\n|\n|\r'))
$rollbackLines = @(
    '$ErrorActionPreference = ''Stop''',
    '# Generated rollback for agent-tool-routing-skill installation.'
) + $rollbackHelperLines + @('') + $rollbackPreflightCommands.ToArray() + @('') +
    $rollbackCommands.ToArray() + @("Write-Output 'Rollback complete.'", '')
Write-Utf8BomFileAtomic -Path $rollbackPath -Content ($rollbackLines -join "`r`n")

$results = New-Object System.Collections.Generic.List[object]
$modificationStarted = $false
try {
    foreach ($plan in $plans) {
        $modificationStarted = $true
        Install-StagedSkill -StageDir $plan.StageDir -Destination $plan.Config.SkillDir
        if ($plan.Global.Changed) {
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
} catch {
    $installError = $_
    if ($modificationStarted) {
        try {
            & $rollbackPath | Out-Null
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
