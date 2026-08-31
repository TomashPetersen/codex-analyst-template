[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Destination,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')]
    [string]$SourceTag,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?$')]
    [string]$TemplateRepositoryUrl
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
$manifestMaxBytes = 1MB
$payloadFileMaxBytes = 8MB
$platformModulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Platform.psm1'
Import-Module $platformModulePath -Force
$nullDevice = Get-ModelProjectNullDevice

Assert-ModelProjectInputText -Value $Destination -Field Destination -MaxLength 1024
Assert-ModelProjectInputText -Value $SourceTag -Field SourceTag -MaxLength 40 -Pattern '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
Assert-ModelProjectInputText -Value $TemplateRepositoryUrl -Field TemplateRepositoryUrl -MaxLength 300 -Pattern '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?$'

function Assert-NoReparseChain {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    Assert-ModelProjectNoLinkInFullChain -Path $AbsolutePath
}

function Assert-LocalDestination {
    param([Parameter(Mandatory = $true)][string]$RawDestination)

    if ($RawDestination.StartsWith('\\') -or $RawDestination.StartsWith('//')) {
        throw 'UNC, device и protocol-relative destination запрещены.'
    }
    $full = [System.IO.Path]::GetFullPath($RawDestination)
    $pathRoot = [System.IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($pathRoot) -or $pathRoot.StartsWith('\\')) {
        throw 'Destination должен находиться на локальном файловом диске.'
    }
    $driveInfo = [System.IO.DriveInfo]::new($pathRoot)
    if ($driveInfo.DriveType -eq [System.IO.DriveType]::Network) {
        throw 'Destination на сетевом диске запрещен.'
    }
}

function Test-ManifestRelativePath {
    param([AllowEmptyString()][string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        $RelativePath.Contains('\') -or
        $RelativePath.StartsWith('/') -or
        $RelativePath.EndsWith('/') -or
        $RelativePath -match '^[A-Za-z]:' -or
        $RelativePath.IndexOfAny([char[]]'*?[]:<>|"') -ge 0) {
        return $false
    }
    foreach ($segment in ($RelativePath -split '/')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -in @('.', '..') -or
            $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|CLOCK\$|CONIN\$|CONOUT\$|COM[1-9]|LPT[1-9])(?:\..*)?$') {
            return $false
        }
    }
    return $true
}

function Get-GitHubRepositoryIdentity {
    param([AllowEmptyString()][string]$RemoteUrl)

    if ([string]::IsNullOrWhiteSpace($RemoteUrl) -or $RemoteUrl -match '[\r\n\x00]') { return $null }
    $match = [regex]::Match(
        $RemoteUrl.Trim(),
        '^(?:https://github\.com/|git@github\.com:)(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)$'
    )
    if (-not $match.Success) { return $null }
    $repository = $match.Groups['repo'].Value
    if ($repository.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
        $repository = $repository.Substring(0, $repository.Length - 4)
    }
    if ([string]::IsNullOrWhiteSpace($repository)) { return $null }
    return ('github.com/{0}/{1}' -f $match.Groups['owner'].Value, $repository).ToLowerInvariant()
}

function Read-BoundedUtf8File {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][long]$MaxBytes,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $absolutePath = [System.IO.Path]::GetFullPath($LiteralPath)
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        throw "Файл не найден: $Label"
    }
    Assert-NoReparseChain $absolutePath
    $item = Get-Item -LiteralPath $absolutePath -Force
    if ([long]$item.Length -gt $MaxBytes) { throw "Файл превышает лимит: $Label" }
    try { return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($absolutePath)).TrimStart([char]0xFEFF) }
    catch { throw "Файл содержит невалидный UTF-8: $Label" }
}

function Get-BoundedFileSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $absolutePath = [System.IO.Path]::GetFullPath($LiteralPath)
    Assert-NoReparseChain $absolutePath
    $item = Get-Item -LiteralPath $absolutePath -Force
    if (-not $item.PSIsContainer -and [long]$item.Length -le $payloadFileMaxBytes) {
        $stream = $null
        $sha256 = $null
        try {
            $stream = [System.IO.File]::OpenRead($absolutePath)
            $sha256 = [System.Security.Cryptography.SHA256]::Create()
            $hash = $sha256.ComputeHash($stream)
            return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
        }
        finally {
            if ($null -ne $sha256) { $sha256.Dispose() }
            if ($null -ne $stream) { $stream.Dispose() }
        }
    }
    throw "Файл невозможно безопасно хешировать: $Label"
}

function Get-GitBlobObjectId {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$ObjectFormat,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $absolutePath = [System.IO.Path]::GetFullPath($LiteralPath)
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        throw "Файл для blob attestation не найден: $Label"
    }
    Assert-NoReparseChain $absolutePath
    $item = Get-Item -LiteralPath $absolutePath -Force
    if ([long]$item.Length -gt $payloadFileMaxBytes) {
        throw "Файл для blob attestation превышает лимит: $Label"
    }
    $bytes = [System.IO.File]::ReadAllBytes($absolutePath)
    $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($bytes.LongLength)`0")
    $algorithm = if ($ObjectFormat -ceq 'sha1') {
        [System.Security.Cryptography.SHA1]::Create()
    }
    elseif ($ObjectFormat -ceq 'sha256') {
        [System.Security.Cryptography.SHA256]::Create()
    }
    else {
        throw 'Git object format не поддерживается.'
    }
    try {
        $null = $algorithm.TransformBlock($header, 0, $header.Length, $header, 0)
        $null = $algorithm.TransformFinalBlock($bytes, 0, $bytes.Length)
        return ([System.BitConverter]::ToString($algorithm.Hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function Assert-FileMatchesCommitBlob {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Commit,
        [Parameter(Mandatory = $true)][string]$ObjectFormat
    )

    $objectResult = Invoke-SourceGit @('rev-parse', '--verify', "${Commit}:$RelativePath")
    $objectLines = @($objectResult.Output)
    $expectedPattern = if ($ObjectFormat -ceq 'sha1') { '^[0-9a-f]{40}$' } else { '^[0-9a-f]{64}$' }
    if ($objectResult.ExitCode -ne 0 -or $objectLines.Count -ne 1 -or
        [string]$objectLines[0] -cnotmatch $expectedPattern) {
        throw "Manifest file отсутствует как blob в tagged source commit: $RelativePath"
    }
    $actualObjectId = Get-GitBlobObjectId -LiteralPath $LiteralPath -ObjectFormat $ObjectFormat -Label $RelativePath
    if ($actualObjectId -cne [string]$objectLines[0]) {
        throw "Manifest file не совпадает с blob tagged source commit: $RelativePath"
    }
}

function Get-TrustedApplication {
    param(
        [Parameter(Mandatory = $true)][string[]]$Names,
        [Parameter(Mandatory = $true)][string[]]$AllowedLeaves
    )

    return (Get-ModelProjectTrustedApplication -Names $Names -AllowedLeaves $AllowedLeaves -ControlledRoots @($sourceRoot))
}

function Invoke-SanitizedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$GitEnvironment
    )

    $result = Invoke-ModelProjectProcess -Executable $Executable -Arguments $Arguments -GitEnvironment:$GitEnvironment
    if ($result.LimitExceeded) { throw 'Subprocess output превысил лимит.' }
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Output = @($result.Output) }
}

function Invoke-SourceGit {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    return Invoke-RepositoryGit -RepositoryRoot $sourceRoot -Arguments $Arguments
}

function Invoke-RepositoryGit {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    return Invoke-SanitizedProcess -Executable $gitExe -GitEnvironment -Arguments (@(
        '--no-replace-objects',
        '-c', "safe.directory=$RepositoryRoot",
        '-c', 'core.fsmonitor=false',
        '-c', "core.hooksPath=$nullDevice",
        '-c', 'core.quotePath=false',
        '-C', $RepositoryRoot
    ) + $Arguments)
}

function Remove-DirectoryTreeWithoutFollowingReparse {
    param([Parameter(Mandatory = $true)][string]$DirectoryPath)

    foreach ($entry in [System.IO.Directory]::EnumerateFileSystemEntries($DirectoryPath)) {
        $attributes = [System.IO.File]::GetAttributes($entry)
        $isDirectory = ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0
        $isReparse = ($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        if ($isReparse) {
            if ($isDirectory) { [System.IO.Directory]::Delete($entry, $false) }
            else { [System.IO.File]::Delete($entry) }
        }
        elseif ($isDirectory) { Remove-DirectoryTreeWithoutFollowingReparse $entry }
        else { [System.IO.File]::SetAttributes($entry, [System.IO.FileAttributes]::Normal); [System.IO.File]::Delete($entry) }
    }
    [System.IO.Directory]::Delete($DirectoryPath, $false)
}

function Assert-DirectoryTreeNoReparse {
    param([Parameter(Mandatory = $true)][string]$DirectoryPath)

    Assert-NoReparseChain $DirectoryPath
    foreach ($entry in [System.IO.Directory]::EnumerateFileSystemEntries($DirectoryPath)) {
        $attributes = [System.IO.File]::GetAttributes($entry)
        if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Consumer staging содержит reparse point.'
        }
        if (($attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
            Assert-DirectoryTreeNoReparse $entry
        }
    }
}

function Remove-ExactStagingDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$StagingDirectory,
        [Parameter(Mandatory = $true)][string]$ExpectedParent
    )

    $fullStaging = [System.IO.Path]::GetFullPath($StagingDirectory).TrimEnd([char[]]'\/')
    $fullParent = [System.IO.Path]::GetFullPath($ExpectedParent).TrimEnd([char[]]'\/')
    $comparison = Get-ModelProjectPathComparison -Path $fullParent
    if (-not ([System.IO.Path]::GetDirectoryName($fullStaging)).Equals($fullParent, $comparison) -or
        [System.IO.Path]::GetFileName($fullStaging) -notmatch '^\.codex-github-template-[0-9a-f]{32}$') {
        throw 'Отказ от cleanup неожиданного staging path.'
    }
    Assert-NoReparseChain $fullParent
    if (-not (Test-Path -LiteralPath $fullStaging)) { return }
    $attributes = [System.IO.File]::GetAttributes($fullStaging)
    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        [System.IO.Directory]::Delete($fullStaging, $false)
        return
    }
    Assert-NoReparseChain $fullStaging
    Remove-DirectoryTreeWithoutFollowingReparse $fullStaging
}

function Remove-ExactSnapshotWorktree {
    param(
        [Parameter(Mandatory = $true)][string]$SnapshotDirectory,
        [Parameter(Mandatory = $true)][string]$ExpectedParent
    )

    $fullSnapshot = [System.IO.Path]::GetFullPath($SnapshotDirectory).TrimEnd([char[]]'\/')
    $fullParent = [System.IO.Path]::GetFullPath($ExpectedParent).TrimEnd([char[]]'\/')
    $comparison = Get-ModelProjectPathComparison -Path $fullParent
    if (-not ([System.IO.Path]::GetDirectoryName($fullSnapshot)).Equals($fullParent, $comparison) -or
        [System.IO.Path]::GetFileName($fullSnapshot) -notmatch '^\.codex-github-template-snapshot-[0-9a-f]{32}$') {
        throw 'Отказ от cleanup неожиданного snapshot path.'
    }
    Assert-NoReparseChain $fullParent
    $removeResult = Invoke-SourceGit @('worktree', 'remove', '--force', $fullSnapshot)
    if ($removeResult.ExitCode -ne 0 -and (Test-Path -LiteralPath $fullSnapshot)) {
        $attributes = [System.IO.File]::GetAttributes($fullSnapshot)
        if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            [System.IO.Directory]::Delete($fullSnapshot, $false)
        }
        else {
            Assert-NoReparseChain $fullSnapshot
            Remove-DirectoryTreeWithoutFollowingReparse $fullSnapshot
        }
    }
    $worktreeList = Invoke-SourceGit @('worktree', 'list', '--porcelain')
    $registeredPaths = @($worktreeList.Output | Where-Object { [string]$_ -cmatch '^worktree ' } | ForEach-Object {
        [System.IO.Path]::GetFullPath(([string]$_).Substring(9)).TrimEnd([char[]]'\/')
    })
    if ($worktreeList.ExitCode -ne 0 -or (Test-Path -LiteralPath $fullSnapshot) -or
        @($registeredPaths | Where-Object { $_.Equals($fullSnapshot, $comparison) }).Count -ne 0) {
        throw 'Не удалось безопасно удалить detached source snapshot.'
    }
}

$sourceRootCandidate = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd([char[]]'\/')
Assert-NoReparseChain $sourceRootCandidate
$sourceRoot = (Resolve-Path -LiteralPath $sourceRootCandidate).Path.TrimEnd([char[]]'\/')
Assert-LocalDestination $Destination
$destinationPath = [System.IO.Path]::GetFullPath($Destination).TrimEnd([char[]]'\/')
if (Test-ModelProjectPathWithinRoot -Root $sourceRoot -Path $destinationPath -AllowEqual) {
    throw 'Consumer payload нельзя строить внутри source template.'
}
if (Test-Path -LiteralPath $destinationPath) { throw 'Consumer destination уже существует.' }
$parent = Split-Path -Parent $destinationPath
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Родительская папка destination не существует.' }
Assert-NoReparseChain $parent

$gitExe = Get-TrustedApplication -Names @('git', 'git.exe') -AllowedLeaves @('git', 'git.exe')
$powershellExe = Get-ModelProjectPowerShellHost -ControlledRoots @($sourceRoot, $destinationPath)

$gitMarker = Join-Path $sourceRoot '.git'
if (-not (Test-Path -LiteralPath $gitMarker)) { throw 'Source repository не содержит .git marker.' }
Assert-NoReparseChain $gitMarker
$repoPrefixResult = Invoke-SourceGit @('rev-parse', '--show-prefix')
$repoPrefixLines = @($repoPrefixResult.Output)
if ($repoPrefixResult.ExitCode -ne 0 -or $repoPrefixLines.Count -ne 0) {
    throw 'Builder должен запускаться из корня source repository.'
}
$branchResult = Invoke-SourceGit @('symbolic-ref', '--quiet', 'HEAD')
$branchLines = @($branchResult.Output)
if ($branchResult.ExitCode -ne 0 -or $branchLines.Count -ne 1 -or [string]$branchLines[0] -cne 'refs/heads/source') {
    throw 'Consumer payload разрешено собирать только из ветки source.'
}
$headResult = Invoke-SourceGit @('rev-parse', '--verify', 'HEAD^{commit}')
$tagResult = Invoke-SourceGit @('rev-parse', '--verify', "$SourceTag^{commit}")
$headLines = @($headResult.Output)
$tagLines = @($tagResult.Output)
if ($headResult.ExitCode -ne 0) {
    throw 'Source HEAD не прошел exact commit gate: git-exit.'
}
if ($headLines.Count -ne 1) {
    throw "Source HEAD не прошел exact commit gate: output-count-$($headLines.Count)."
}
if ([string]$headLines[0] -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
    throw "Source HEAD не прошел exact commit gate: invalid-hash-length-$(([string]$headLines[0]).Length)."
}
if ($tagResult.ExitCode -ne 0) {
    throw 'Source tag не прошел exact commit gate: git-exit.'
}
if ($tagLines.Count -ne 1) {
    throw "Source tag не прошел exact commit gate: output-count-$($tagLines.Count)."
}
if ([string]$tagLines[0] -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
    throw "Source tag не прошел exact commit gate: invalid-hash-length-$(([string]$tagLines[0]).Length)."
}
if ([string]$headLines[0] -cne [string]$tagLines[0]) {
    throw 'Source tag не указывает на текущий HEAD.'
}
$sourceCommit = [string]$headLines[0]
$gitObjectFormat = if ($sourceCommit.Length -eq 40) { 'sha1' } else { 'sha256' }

$originResult = Invoke-SourceGit @('remote', 'get-url', 'origin')
$originLines = @($originResult.Output)
if ($originResult.ExitCode -ne 0 -or $originLines.Count -ne 1) {
    throw 'Source repository должен иметь ровно один читаемый origin URL.'
}
$originIdentity = Get-GitHubRepositoryIdentity -RemoteUrl ([string]$originLines[0])
$declaredTemplateIdentity = Get-GitHubRepositoryIdentity -RemoteUrl $TemplateRepositoryUrl
if ($null -eq $originIdentity -or $null -eq $declaredTemplateIdentity -or
    $originIdentity -cne $declaredTemplateIdentity) {
    throw 'TemplateRepositoryUrl не совпадает с GitHub identity source origin.'
}

$trackedDiff = Invoke-SourceGit @('diff', '--quiet', 'HEAD', '--')
$cachedDiff = Invoke-SourceGit @('diff', '--cached', '--quiet', '--')
if ($trackedDiff.ExitCode -ne 0 -or $cachedDiff.ExitCode -ne 0) {
    throw 'Source tracked worktree должен быть clean относительно release tag.'
}
$untracked = Invoke-SourceGit @('ls-files', '--others', '--exclude-standard')
if ($untracked.ExitCode -ne 0) { throw 'Не удалось проверить source untracked inventory.' }
$initialUntracked = @($untracked.Output | ForEach-Object { ([string]$_).Replace('\', '/') } | Sort-Object)
foreach ($relative in $initialUntracked) {
    if (-not ($relative.StartsWith('.codex/', [System.StringComparison]::Ordinal) -or
        $relative.StartsWith('.agents/skills/bulletproof/', [System.StringComparison]::Ordinal) -or
        $relative.StartsWith('.agents/skills/frontend-design/', [System.StringComparison]::Ordinal))) {
        throw 'Source содержит untracked path вне разрешенных owner overlays.'
    }
}

do {
    $snapshotPath = Join-Path $parent ".codex-github-template-snapshot-$([guid]::NewGuid().ToString('N'))"
} while (Test-Path -LiteralPath $snapshotPath)
do {
    $stagingPath = Join-Path $parent ".codex-github-template-$([guid]::NewGuid().ToString('N'))"
} while (Test-Path -LiteralPath $stagingPath)
$snapshotCreated = $false
$snapshotRemoved = $false
$stagingCreated = $false
$stagingMoved = $false
try {
    $snapshotCreated = $true
    $snapshotAdd = Invoke-SourceGit @('worktree', 'add', '--detach', $snapshotPath, $sourceCommit)
    if ($snapshotAdd.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $snapshotPath -PathType Container)) {
        throw 'Не удалось materialize detached source snapshot.'
    }
    Assert-NoReparseChain $snapshotPath
    $snapshotHead = Invoke-RepositoryGit -RepositoryRoot $snapshotPath -Arguments @('rev-parse', '--verify', 'HEAD^{commit}')
    $snapshotHeadLines = @($snapshotHead.Output)
    $snapshotBranch = Invoke-RepositoryGit -RepositoryRoot $snapshotPath -Arguments @('symbolic-ref', '--quiet', 'HEAD')
    if ($snapshotHead.ExitCode -ne 0 -or $snapshotHeadLines.Count -ne 1 -or
        [string]$snapshotHeadLines[0] -cne $sourceCommit -or
        $snapshotBranch.ExitCode -eq 0 -or @($snapshotBranch.Output).Count -ne 0) {
        throw 'Detached source snapshot не совпадает с captured source commit.'
    }

    $manifestPath = Join-Path $snapshotPath '.template-manifest.json'
    Assert-FileMatchesCommitBlob `
        -LiteralPath $manifestPath `
        -RelativePath '.template-manifest.json' `
        -Commit $sourceCommit `
        -ObjectFormat $gitObjectFormat
    $manifestText = Read-BoundedUtf8File -LiteralPath $manifestPath -MaxBytes $manifestMaxBytes -Label '.template-manifest.json'
    try { $manifest = $manifestText | ConvertFrom-Json }
    catch { throw '.template-manifest.json содержит невалидный JSON.' }
    $version = [string]$manifest.template_version
    if ($SourceTag -cne "v$version") { throw 'Source tag не совпадает с manifest template_version.' }
    $portableFiles = @($manifest.portable_files | ForEach-Object { [string]$_ })
    $portableEmptyDirectories = @($manifest.portable_empty_directories | ForEach-Object { [string]$_ })
    $sourceOnlyPaths = @($manifest.source_only_paths | ForEach-Object { [string]$_ })
    if ($portableFiles -cnotcontains 'TEMPLATE-DISTRIBUTION.json') { throw 'Portable manifest не содержит descriptor.' }
    $derivedPortableFiles = @(
        'PROJECT.md',
        'plans/INDEX.md',
        'mastery/local/INDEX.md',
        'TEMPLATE-DISTRIBUTION.json'
    )
    foreach ($derivedFile in $derivedPortableFiles) {
        if (@($portableFiles | Where-Object { $_ -ceq $derivedFile }).Count -ne 1) {
            throw "Portable manifest должен содержать derived file ровно один раз: $derivedFile"
        }
    }
    $derivedHashes = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::Ordinal)
    foreach ($relativePath in ($portableFiles + $portableEmptyDirectories + $sourceOnlyPaths)) {
        if (-not (Test-ManifestRelativePath $relativePath)) { throw 'Manifest содержит небезопасный portable path.' }
    }
    $manifestFiles = @($portableFiles + $sourceOnlyPaths | Sort-Object -Unique)
    foreach ($relativeFile in $manifestFiles) {
        Assert-FileMatchesCommitBlob `
            -LiteralPath (Join-Path $snapshotPath $relativeFile) `
            -RelativePath $relativeFile `
            -Commit $sourceCommit `
            -ObjectFormat $gitObjectFormat
        $indexResult = Invoke-SourceGit @('ls-files', '-v', '--', $relativeFile)
        $indexLines = @($indexResult.Output)
        if ($indexResult.ExitCode -ne 0 -or $indexLines.Count -ne 1 -or
            [string]$indexLines[0] -cne "H $relativeFile") {
            throw 'Manifest file не имеет обычного tracked index state.'
        }
    }

    New-Item -ItemType Directory -Path $stagingPath | Out-Null
    $stagingCreated = $true
    Assert-NoReparseChain $stagingPath
    foreach ($relativeFile in $portableFiles) {
        $source = Join-Path $snapshotPath $relativeFile
        $target = Join-Path $stagingPath $relativeFile
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Portable file отсутствует: $relativeFile" }
        Assert-NoReparseChain $source
        $targetParent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }
        Assert-NoReparseChain $targetParent
        Copy-Item -LiteralPath $source -Destination $target
        Assert-FileMatchesCommitBlob `
            -LiteralPath $target `
            -RelativePath $relativeFile `
            -Commit $sourceCommit `
            -ObjectFormat $gitObjectFormat
    }
    foreach ($relativeDirectory in $portableEmptyDirectories) {
        $targetDirectory = Join-Path $stagingPath $relativeDirectory
        if (-not (Test-Path -LiteralPath $targetDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
        if (@(Get-ChildItem -LiteralPath $targetDirectory -Force).Count -ne 0) {
            throw "Portable empty directory заполнен: $relativeDirectory"
        }
    }

    $sourceVerifier = Join-Path $snapshotPath 'scripts/verify-structure.ps1'
    $sourceVerify = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $sourceVerifier,
        '-Root', $snapshotPath, '-Mode', 'TemplateSource'
    )
    foreach ($line in $sourceVerify.Output) { Write-Host ([string]$line) }
    if ($sourceVerify.ExitCode -ne 0) { throw 'Source snapshot не прошел TemplateSource gate.' }

    $snapshotTracked = Invoke-RepositoryGit -RepositoryRoot $snapshotPath -Arguments @('diff', '--quiet', 'HEAD', '--')
    $snapshotCached = Invoke-RepositoryGit -RepositoryRoot $snapshotPath -Arguments @('diff', '--cached', '--quiet', '--')
    $snapshotUntracked = Invoke-RepositoryGit -RepositoryRoot $snapshotPath -Arguments @('ls-files', '--others', '--exclude-standard')
    $snapshotHeadAfterVerify = Invoke-RepositoryGit -RepositoryRoot $snapshotPath -Arguments @('rev-parse', '--verify', 'HEAD^{commit}')
    if ($snapshotTracked.ExitCode -ne 0 -or $snapshotCached.ExitCode -ne 0 -or
        $snapshotUntracked.ExitCode -ne 0 -or @($snapshotUntracked.Output).Count -ne 0 -or
        $snapshotHeadAfterVerify.ExitCode -ne 0 -or @($snapshotHeadAfterVerify.Output).Count -ne 1 -or
        [string]@($snapshotHeadAfterVerify.Output)[0] -cne $sourceCommit) {
        throw 'Detached source snapshot изменился во время TemplateSource gate.'
    }
    $projectPath = Join-Path $stagingPath 'PROJECT.md'
    $projectText = Read-BoundedUtf8File -LiteralPath $projectPath -MaxBytes 512KB -Label 'PROJECT.md'
    if (-not $projectText.Contains('repository_kind: template-source')) {
        throw 'Source PROJECT.md не содержит template-source marker.'
    }
    $projectText = $projectText.Replace('repository_kind: template-source', 'repository_kind: distribution-template')
    [System.IO.File]::WriteAllText($projectPath, $projectText, $utf8NoBom)
    $derivedHashes['PROJECT.md'] = Get-BoundedFileSha256 -LiteralPath $projectPath -Label 'PROJECT.md'

    $planIndexer = Join-Path $snapshotPath 'scripts/update-plan-index.ps1'
    if (-not (Test-Path -LiteralPath $planIndexer -PathType Leaf)) { throw 'Source snapshot не содержит plan indexer.' }
    Assert-NoReparseChain $planIndexer
    $planIndexResult = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $planIndexer,
        '-Root', $stagingPath, '-Mode', 'Write'
    )
    foreach ($line in $planIndexResult.Output) { Write-Host ([string]$line) }
    if ($planIndexResult.ExitCode -ne 0) { throw 'Не удалось пересобрать consumer plans/INDEX.md.' }
    $derivedHashes['plans/INDEX.md'] = Get-BoundedFileSha256 `
        -LiteralPath (Join-Path $stagingPath 'plans/INDEX.md') `
        -Label 'plans/INDEX.md'

    $masteryIndexer = Join-Path $snapshotPath 'scripts/update-mastery-index.ps1'
    if (-not (Test-Path -LiteralPath $masteryIndexer -PathType Leaf)) { throw 'Source snapshot не содержит mastery indexer.' }
    Assert-NoReparseChain $masteryIndexer
    $masteryIndexResult = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $masteryIndexer,
        '-Root', $stagingPath, '-Mode', 'Write'
    )
    foreach ($line in $masteryIndexResult.Output) { Write-Host ([string]$line) }
    if ($masteryIndexResult.ExitCode -ne 0) { throw 'Не удалось пересобрать consumer mastery/local/INDEX.md.' }
    $derivedHashes['mastery/local/INDEX.md'] = Get-BoundedFileSha256 `
        -LiteralPath (Join-Path $stagingPath 'mastery/local/INDEX.md') `
        -Label 'mastery/local/INDEX.md'

    $commitDate = Invoke-SourceGit @('show', '-s', '--format=%cI', $sourceCommit)
    $commitDateLines = @($commitDate.Output)
    if ($commitDate.ExitCode -ne 0 -or $commitDateLines.Count -ne 1) { throw 'Не удалось получить release commit timestamp.' }
    $payloadHashes = [System.Collections.Generic.List[object]]::new()
    foreach ($relativeFile in @($portableFiles | Where-Object { $_ -cne 'TEMPLATE-DISTRIBUTION.json' } | Sort-Object)) {
        $payloadHashes.Add([ordered]@{
            path = $relativeFile
            sha256 = Get-BoundedFileSha256 -LiteralPath (Join-Path $stagingPath $relativeFile) -Label $relativeFile
        })
    }
    $descriptor = [ordered]@{
        schema_version = 1
        distribution_kind = 'github-template'
        template_version = $version
        source_tag = $SourceTag
        source_commit = $sourceCommit
        template_repository_url = $TemplateRepositoryUrl
        built_at = [string]$commitDateLines[0]
        payload_sha256 = $payloadHashes.ToArray()
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $stagingPath 'TEMPLATE-DISTRIBUTION.json'),
        (($descriptor | ConvertTo-Json -Depth 6) + "`n"),
        $utf8NoBom
    )
    $derivedHashes['TEMPLATE-DISTRIBUTION.json'] = Get-BoundedFileSha256 `
        -LiteralPath (Join-Path $stagingPath 'TEMPLATE-DISTRIBUTION.json') `
        -Label 'TEMPLATE-DISTRIBUTION.json'

    $actualFiles = @(Get-ChildItem -LiteralPath $stagingPath -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($stagingPath.Length + 1).Replace('\', '/')
    })
    $missing = @($portableFiles | Where-Object { $actualFiles -cnotcontains $_ })
    $extra = @($actualFiles | Where-Object { $portableFiles -cnotcontains $_ })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) { throw 'Consumer payload inventory не совпадает с portable manifest.' }
    if (Test-Path -LiteralPath (Join-Path $stagingPath '.git')) { throw 'Consumer payload неожиданно содержит .git.' }

    $distributionVerifier = Join-Path $snapshotPath 'scripts/verify-structure.ps1'
    $distributionVerify = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $distributionVerifier,
        '-Root', $stagingPath, '-Mode', 'DistributionTemplate'
    )
    foreach ($line in $distributionVerify.Output) { Write-Host ([string]$line) }
    if ($distributionVerify.ExitCode -ne 0) { throw 'Consumer payload не прошел DistributionTemplate gate.' }

    foreach ($relativeFile in $portableFiles) {
        $stagedFile = Join-Path $stagingPath $relativeFile
        if ($derivedHashes.ContainsKey($relativeFile)) {
            $actualDerivedHash = Get-BoundedFileSha256 -LiteralPath $stagedFile -Label $relativeFile
            if ($actualDerivedHash -cne $derivedHashes[$relativeFile]) {
                throw "Derived consumer file изменился после materialization: $relativeFile"
            }
        }
        else {
            Assert-FileMatchesCommitBlob `
                -LiteralPath $stagedFile `
                -RelativePath $relativeFile `
                -Commit $sourceCommit `
                -ObjectFormat $gitObjectFormat
        }
    }

    Assert-DirectoryTreeNoReparse $stagingPath
    $finalActualFiles = @(Get-ChildItem -LiteralPath $stagingPath -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($stagingPath.Length + 1).Replace('\', '/')
    })
    $finalMissing = @($portableFiles | Where-Object { $finalActualFiles -cnotcontains $_ })
    $finalExtra = @($finalActualFiles | Where-Object { $portableFiles -cnotcontains $_ })
    if ($finalMissing.Count -gt 0 -or $finalExtra.Count -gt 0 -or
        (Test-Path -LiteralPath (Join-Path $stagingPath '.git'))) {
        throw 'Consumer payload inventory изменился после DistributionTemplate gate.'
    }
    foreach ($relativeDirectory in $portableEmptyDirectories) {
        $finalEmptyDirectory = Join-Path $stagingPath $relativeDirectory
        if (-not (Test-Path -LiteralPath $finalEmptyDirectory -PathType Container) -or
            @(Get-ChildItem -LiteralPath $finalEmptyDirectory -Force).Count -ne 0) {
            throw "Portable empty directory изменился после DistributionTemplate gate: $relativeDirectory"
        }
    }

    $snapshotTrackedFinal = Invoke-RepositoryGit -RepositoryRoot $snapshotPath -Arguments @('diff', '--quiet', 'HEAD', '--')
    $snapshotCachedFinal = Invoke-RepositoryGit -RepositoryRoot $snapshotPath -Arguments @('diff', '--cached', '--quiet', '--')
    $snapshotUntrackedFinal = Invoke-RepositoryGit -RepositoryRoot $snapshotPath -Arguments @('ls-files', '--others', '--exclude-standard')
    $snapshotHeadFinal = Invoke-RepositoryGit -RepositoryRoot $snapshotPath -Arguments @('rev-parse', '--verify', 'HEAD^{commit}')
    $snapshotBranchFinal = Invoke-RepositoryGit -RepositoryRoot $snapshotPath -Arguments @('symbolic-ref', '--quiet', 'HEAD')
    if ($snapshotTrackedFinal.ExitCode -ne 0 -or $snapshotCachedFinal.ExitCode -ne 0 -or
        $snapshotUntrackedFinal.ExitCode -ne 0 -or @($snapshotUntrackedFinal.Output).Count -ne 0 -or
        $snapshotHeadFinal.ExitCode -ne 0 -or @($snapshotHeadFinal.Output).Count -ne 1 -or
        [string]@($snapshotHeadFinal.Output)[0] -cne $sourceCommit -or
        $snapshotBranchFinal.ExitCode -eq 0 -or @($snapshotBranchFinal.Output).Count -ne 0) {
        throw 'Detached source snapshot изменился во время consumer materialization.'
    }
    Remove-ExactSnapshotWorktree -SnapshotDirectory $snapshotPath -ExpectedParent $parent
    $snapshotRemoved = $true

    foreach ($relativeFile in $manifestFiles) {
        $finalIndexResult = Invoke-SourceGit @('ls-files', '-v', '--', $relativeFile)
        $finalIndexLines = @($finalIndexResult.Output)
        if ($finalIndexResult.ExitCode -ne 0 -or $finalIndexLines.Count -ne 1 -or
            [string]$finalIndexLines[0] -cne "H $relativeFile") {
            throw 'Source index state изменился во время build.'
        }
    }

    $finalBranch = Invoke-SourceGit @('symbolic-ref', '--quiet', 'HEAD')
    $finalHead = Invoke-SourceGit @('rev-parse', '--verify', 'HEAD^{commit}')
    $finalTag = Invoke-SourceGit @('rev-parse', '--verify', "$SourceTag^{commit}")
    $finalTracked = Invoke-SourceGit @('diff', '--quiet', 'HEAD', '--')
    $finalCached = Invoke-SourceGit @('diff', '--cached', '--quiet', '--')
    $finalUntrackedResult = Invoke-SourceGit @('ls-files', '--others', '--exclude-standard')
    $finalUntracked = @($finalUntrackedResult.Output | ForEach-Object { ([string]$_).Replace('\', '/') } | Sort-Object)
    if ($finalBranch.ExitCode -ne 0 -or @($finalBranch.Output).Count -ne 1 -or
        [string]@($finalBranch.Output)[0] -cne 'refs/heads/source' -or
        $finalHead.ExitCode -ne 0 -or @($finalHead.Output).Count -ne 1 -or
        [string]@($finalHead.Output)[0] -cne $sourceCommit -or
        $finalTag.ExitCode -ne 0 -or @($finalTag.Output).Count -ne 1 -or
        [string]@($finalTag.Output)[0] -cne $sourceCommit -or
        $finalTracked.ExitCode -ne 0 -or $finalCached.ExitCode -ne 0 -or
        $finalUntrackedResult.ExitCode -ne 0 -or
        [string]::Join("`n", $finalUntracked) -cne [string]::Join("`n", $initialUntracked)) {
        throw 'Source HEAD, tag или worktree изменились во время build.'
    }

    Assert-NoReparseChain $parent
    Assert-NoReparseChain $stagingPath
    if (Test-Path -LiteralPath $destinationPath) { throw 'Final destination появился во время build.' }
    [System.IO.Directory]::Move($stagingPath, $destinationPath)
    $stagingMoved = $true
}
catch {
    $originalFailure = $_
    $cleanupFailed = $false
    if ($stagingCreated -and -not $stagingMoved) {
        try { Remove-ExactStagingDirectory -StagingDirectory $stagingPath -ExpectedParent $parent }
        catch { $cleanupFailed = $true }
    }
    if ($snapshotCreated -and -not $snapshotRemoved) {
        try { Remove-ExactSnapshotWorktree -SnapshotDirectory $snapshotPath -ExpectedParent $parent }
        catch { $cleanupFailed = $true }
    }
    if ($cleanupFailed) {
        throw 'Consumer build завершился ошибкой и exact temporary cleanup также не прошел.'
    }
    throw $originalFailure
}

Write-Host "GitHub consumer payload $SourceTag создан: $destinationPath"
