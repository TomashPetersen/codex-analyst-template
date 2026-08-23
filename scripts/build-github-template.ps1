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

    return Invoke-SanitizedProcess -Executable $gitExe -GitEnvironment -Arguments (@(
        '-c', "safe.directory=$sourceRoot",
        '-c', 'core.fsmonitor=false',
        '-c', "core.hooksPath=$nullDevice",
        '-c', 'core.quotePath=false',
        '-C', $sourceRoot
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
foreach ($path in @($untracked.Output)) {
    $relative = ([string]$path).Replace('\', '/')
    if (-not ($relative.StartsWith('.codex/', [System.StringComparison]::Ordinal) -or
        $relative.StartsWith('.agents/skills/bulletproof/', [System.StringComparison]::Ordinal) -or
        $relative.StartsWith('.agents/skills/frontend-design/', [System.StringComparison]::Ordinal))) {
        throw 'Source содержит untracked path вне разрешенных owner overlays.'
    }
}

$manifestPath = Join-Path $sourceRoot '.template-manifest.json'
$manifestText = Read-BoundedUtf8File -LiteralPath $manifestPath -MaxBytes $manifestMaxBytes -Label '.template-manifest.json'
try { $manifest = $manifestText | ConvertFrom-Json }
catch { throw '.template-manifest.json содержит невалидный JSON.' }
$version = [string]$manifest.template_version
if ($SourceTag -cne "v$version") { throw 'Source tag не совпадает с manifest template_version.' }
$portableFiles = @($manifest.portable_files | ForEach-Object { [string]$_ })
$portableEmptyDirectories = @($manifest.portable_empty_directories | ForEach-Object { [string]$_ })
$sourceOnlyPaths = @($manifest.source_only_paths | ForEach-Object { [string]$_ })
if ($portableFiles -cnotcontains 'TEMPLATE-DISTRIBUTION.json') { throw 'Portable manifest не содержит descriptor.' }
foreach ($relativePath in ($portableFiles + $portableEmptyDirectories + $sourceOnlyPaths)) {
    if (-not (Test-ManifestRelativePath $relativePath)) { throw 'Manifest содержит небезопасный portable path.' }
}
foreach ($relativeFile in @($portableFiles + $sourceOnlyPaths | Sort-Object -Unique)) {
    $treeResult = Invoke-SourceGit @('ls-tree', '--name-only', '--full-tree', $sourceCommit, '--', $relativeFile)
    $treeLines = @($treeResult.Output)
    if ($treeResult.ExitCode -ne 0 -or $treeLines.Count -ne 1 -or [string]$treeLines[0] -cne $relativeFile) {
        throw 'Manifest file отсутствует в tagged source commit.'
    }
    $indexResult = Invoke-SourceGit @('ls-files', '-v', '--', $relativeFile)
    $indexLines = @($indexResult.Output)
    if ($indexResult.ExitCode -ne 0 -or $indexLines.Count -ne 1 -or
        [string]$indexLines[0] -cne "H $relativeFile") {
        throw 'Manifest file не имеет обычного tracked index state.'
    }
}

$verifier = Join-Path $PSScriptRoot 'verify-structure.ps1'
$sourceVerify = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifier,
    '-Root', $sourceRoot, '-Mode', 'TemplateSource'
)
foreach ($line in $sourceVerify.Output) { Write-Host ([string]$line) }
if ($sourceVerify.ExitCode -ne 0) { throw 'Source template не прошел TemplateSource gate.' }

do {
    $stagingPath = Join-Path $parent ".codex-github-template-$([guid]::NewGuid().ToString('N'))"
} while (Test-Path -LiteralPath $stagingPath)
$stagingMoved = $false
try {
    New-Item -ItemType Directory -Path $stagingPath | Out-Null
    Assert-NoReparseChain $stagingPath
    foreach ($relativeFile in $portableFiles) {
        $source = Join-Path $sourceRoot $relativeFile
        $target = Join-Path $stagingPath $relativeFile
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Portable file отсутствует: $relativeFile" }
        Assert-NoReparseChain $source
        $targetParent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }
        Assert-NoReparseChain $targetParent
        Copy-Item -LiteralPath $source -Destination $target
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

    $projectPath = Join-Path $stagingPath 'PROJECT.md'
    $projectText = Read-BoundedUtf8File -LiteralPath $projectPath -MaxBytes 512KB -Label 'PROJECT.md'
    if (-not $projectText.Contains('repository_kind: template-source')) {
        throw 'Source PROJECT.md не содержит template-source marker.'
    }
    $projectText = $projectText.Replace('repository_kind: template-source', 'repository_kind: distribution-template')
    [System.IO.File]::WriteAllText($projectPath, $projectText, $utf8NoBom)

    $planIndexer = Join-Path $stagingPath 'scripts/update-plan-index.ps1'
    if (-not (Test-Path -LiteralPath $planIndexer -PathType Leaf)) { throw 'Consumer payload не содержит plan indexer.' }
    Assert-NoReparseChain $planIndexer
    $planIndexResult = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $planIndexer,
        '-Root', $stagingPath, '-Mode', 'Write'
    )
    foreach ($line in $planIndexResult.Output) { Write-Host ([string]$line) }
    if ($planIndexResult.ExitCode -ne 0) { throw 'Не удалось пересобрать consumer plans/INDEX.md.' }

    $masteryIndexer = Join-Path $stagingPath 'scripts/update-mastery-index.ps1'
    if (-not (Test-Path -LiteralPath $masteryIndexer -PathType Leaf)) { throw 'Consumer payload не содержит mastery indexer.' }
    Assert-NoReparseChain $masteryIndexer
    $masteryIndexResult = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $masteryIndexer,
        '-Root', $stagingPath, '-Mode', 'Write'
    )
    foreach ($line in $masteryIndexResult.Output) { Write-Host ([string]$line) }
    if ($masteryIndexResult.ExitCode -ne 0) { throw 'Не удалось пересобрать consumer mastery/local/INDEX.md.' }

    $commitDate = Invoke-SourceGit @('show', '-s', '--format=%cI', 'HEAD')
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

    $actualFiles = @(Get-ChildItem -LiteralPath $stagingPath -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($stagingPath.Length + 1).Replace('\', '/')
    })
    $missing = @($portableFiles | Where-Object { $actualFiles -cnotcontains $_ })
    $extra = @($actualFiles | Where-Object { $portableFiles -cnotcontains $_ })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) { throw 'Consumer payload inventory не совпадает с portable manifest.' }
    if (Test-Path -LiteralPath (Join-Path $stagingPath '.git')) { throw 'Consumer payload неожиданно содержит .git.' }

    $distributionVerify = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifier,
        '-Root', $stagingPath, '-Mode', 'DistributionTemplate'
    )
    foreach ($line in $distributionVerify.Output) { Write-Host ([string]$line) }
    if ($distributionVerify.ExitCode -ne 0) { throw 'Consumer payload не прошел DistributionTemplate gate.' }

    Assert-NoReparseChain $parent
    Assert-NoReparseChain $stagingPath
    if (Test-Path -LiteralPath $destinationPath) { throw 'Final destination появился во время build.' }
    [System.IO.Directory]::Move($stagingPath, $destinationPath)
    $stagingMoved = $true
}
catch {
    $originalFailure = $_
    if (-not $stagingMoved) {
        try { Remove-ExactStagingDirectory -StagingDirectory $stagingPath -ExpectedParent $parent }
        catch { throw 'Consumer build завершился ошибкой и staging cleanup также не прошел.' }
    }
    throw $originalFailure
}

Write-Host "GitHub consumer payload $SourceTag создан: $destinationPath"
