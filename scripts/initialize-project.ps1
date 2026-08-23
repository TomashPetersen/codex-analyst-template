[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string]$ProjectSlug,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Description,

    [ValidateNotNullOrEmpty()]
    [string]$Owner = 'project-owner',

    [switch]$InitializeGit,

    [switch]$FromGitHubTemplate
)

$script:initializeFailureCode = 'initialization-rejected'
trap {
    $safeCode = if ($script:initializeFailureCode -cin @(
        'initialization-rejected',
        'initialization-rolled-back',
        'initialization-rollback-incomplete'
    )) {
        $script:initializeFailureCode
    }
    else {
        'initialization-rejected'
    }
    try { [Console]::Error.WriteLine("ERROR: $safeCode") }
    catch { }
    exit 1
}

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$platformModulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Platform.psm1'
Import-Module $platformModulePath -Force
$nullDevice = Get-ModelProjectNullDevice
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

Assert-ModelProjectInputText -Value $ProjectName -Field ProjectName -MaxLength 120 -Pattern '^[\p{L}\p{N}][\p{L}\p{N} .,:;!?()_+&/\-]{0,119}$'
Assert-ModelProjectInputText -Value $ProjectSlug -Field ProjectSlug -MaxLength 63 -Pattern '^[a-z0-9][a-z0-9-]*$'
Assert-ModelProjectInputText -Value $Description -Field Description -MaxLength 500 -Pattern '^[\p{L}\p{N}][\p{L}\p{N} .,:;!?()_+&%/''"\-]{0,499}$'
Assert-ModelProjectInputText -Value $Owner -Field Owner -MaxLength 80 -Pattern '^[\p{L}\p{N}][\p{L}\p{N} ._+\-]{0,79}$'
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
$manifestMaxBytes = 1MB
$projectMaxBytes = 512KB
$readmeMaxBytes = 2MB
$descriptorMaxBytes = 8MB
$licenseMaxBytes = 2MB
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

if (($InitializeGit -and $FromGitHubTemplate) -or (-not $InitializeGit -and -not $FromGitHubTemplate)) {
    throw 'Укажите ровно один режим: -InitializeGit или -FromGitHubTemplate.'
}

function Assert-NoReparseChain {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    Assert-ModelProjectNoLinkInFullChain -Path $AbsolutePath
}

function Test-PathWithinControlledRoot {
    param(
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [Parameter(Mandatory = $true)][string]$ControlledRoot
    )

    return (Test-ModelProjectPathWithinRoot -Root $ControlledRoot -Path $CandidatePath -AllowEqual)
}

function Get-TrustedGitExecutable {
    param([Parameter(Mandatory = $true)][string[]]$ControlledRoots)

    return (Get-ModelProjectGitExecutable -ControlledRoots $ControlledRoots)
}

function Get-TrustedCurrentPowerShellHost {
    param([Parameter(Mandatory = $true)][string[]]$ControlledRoots)

    return (Get-ModelProjectPowerShellHost -ControlledRoots $ControlledRoots)
}

function Invoke-SanitizedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $isGit = [System.IO.Path]::GetFileName($Executable) -cin @('git', 'git.exe')
    $result = Invoke-ModelProjectProcess -Executable $Executable -Arguments $Arguments -GitEnvironment:$isGit
    if ($result.LimitExceeded) { throw 'Дочерний процесс превысил лимит вывода.' }
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Output = @($result.Output) }
}

function Read-BoundedUtf8File {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][long]$MaxBytes,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($MaxBytes -le 0) {
        throw "Некорректный лимит чтения для ${Label}: $MaxBytes"
    }

    $absolutePath = [System.IO.Path]::GetFullPath($LiteralPath)
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        throw "Файл для чтения не найден: ${Label}: $absolutePath"
    }

    Assert-NoReparseChain $absolutePath
    $item = Get-Item -LiteralPath $absolutePath -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Файл является reparse point: ${Label}: $absolutePath"
    }
    if ([long]$item.Length -gt $MaxBytes) {
        throw "Файл превышает лимит $MaxBytes байт: ${Label}: $($item.Length)"
    }

    Assert-NoReparseChain $absolutePath
    $stream = $null
    $memory = $null
    try {
        $stream = [System.IO.FileStream]::new(
            $absolutePath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        if ($stream.Length -gt $MaxBytes) {
            throw "Файл превышает лимит $MaxBytes байт после открытия: ${Label}: $($stream.Length)"
        }

        $memory = [System.IO.MemoryStream]::new()
        $buffer = New-Object byte[] 65536
        [long]$totalRead = 0
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $totalRead += $read
            if ($totalRead -gt $MaxBytes) {
                throw "Файл превысил лимит $MaxBytes байт во время чтения: $Label"
            }
            $memory.Write($buffer, 0, $read)
        }
        $bytes = $memory.ToArray()
    }
    finally {
        if ($null -ne $memory) { $memory.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }

    try {
        $text = $strictUtf8.GetString($bytes)
    }
    catch {
        throw "Файл содержит невалидный UTF-8: ${Label}: $($_.Exception.Message)"
    }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
        $text = $text.Substring(1)
    }
    return $text
}

function Get-BoundedFileSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][long]$MaxBytes,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $absolutePath = [System.IO.Path]::GetFullPath($LiteralPath)
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        throw "Файл для хеширования не найден: $Label"
    }
    Assert-NoReparseChain $absolutePath
    $item = Get-Item -LiteralPath $absolutePath -Force
    if ([long]$item.Length -gt $MaxBytes) {
        throw "Файл превышает лимит хеширования: $Label"
    }
    $stream = $null
    $sha256 = $null
    try {
        $stream = [System.IO.FileStream]::new(
            $absolutePath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        if ($stream.Length -gt $MaxBytes) {
            throw "Файл превышает лимит хеширования после открытия: $Label"
        }
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hash = $sha256.ComputeHash($stream)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha256) { $sha256.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-TextSha256 {
    param([AllowEmptyString()][Parameter(Mandatory = $true)][string]$Text)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $utf8NoBom.GetBytes($Text)
        $hash = $sha256.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
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

function Get-PayloadHashEntries {
    param([Parameter(Mandatory = $true)][string[]]$PortableFiles)

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($relativePath in @($PortableFiles | Where-Object { $_ -cne 'TEMPLATE-DISTRIBUTION.json' } | Sort-Object)) {
        if (-not (Test-ManifestRelativePath $relativePath)) {
            throw 'Manifest содержит небезопасный portable path.'
        }
        $absolutePath = Join-Path $repoRoot $relativePath
        $entries.Add([ordered]@{
            path = $relativePath
            sha256 = Get-BoundedFileSha256 -LiteralPath $absolutePath -MaxBytes $descriptorMaxBytes -Label $relativePath
        })
    }
    return $entries.ToArray()
}

function ConvertTo-DescriptorJson {
    param([Parameter(Mandatory = $true)]$Descriptor)

    return (($Descriptor | ConvertTo-Json -Depth 6) + "`n")
}

function Assert-DescriptorShape {
    param(
        [Parameter(Mandatory = $true)]$Descriptor,
        [Parameter(Mandatory = $true)][string]$ExpectedKind,
        [Parameter(Mandatory = $true)][string]$TemplateVersion,
        [Parameter(Mandatory = $true)][string[]]$PortableFiles
    )

    $required = @(
        'schema_version', 'distribution_kind', 'template_version', 'source_tag',
        'source_commit', 'template_repository_url', 'built_at', 'payload_sha256'
    )
    foreach ($propertyName in $required) {
        if ($Descriptor.PSObject.Properties.Name -cnotcontains $propertyName) {
            throw "TEMPLATE-DISTRIBUTION.json: отсутствует поле $propertyName"
        }
    }
    if ([int]$Descriptor.schema_version -ne 1 -or
        [string]$Descriptor.distribution_kind -cne $ExpectedKind -or
        [string]$Descriptor.template_version -cne $TemplateVersion) {
        throw 'TEMPLATE-DISTRIBUTION.json не соответствует ожидаемому release contract.'
    }

    if ($ExpectedKind -ceq 'source-placeholder') {
        if ($null -ne $Descriptor.source_tag -or $null -ne $Descriptor.source_commit -or
            $null -ne $Descriptor.template_repository_url -or $null -ne $Descriptor.built_at -or
            @($Descriptor.payload_sha256).Count -ne 0) {
            throw 'Source placeholder descriptor содержит release values.'
        }
        return
    }

    if ([string]$Descriptor.source_tag -cne "v$TemplateVersion" -or
        [string]$Descriptor.source_commit -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' -or
        [string]$Descriptor.template_repository_url -cnotmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?$') {
        throw 'GitHub distribution descriptor содержит некорректный tag, commit или repository URL.'
    }
    $builtAt = [datetimeoffset]::MinValue
    $builtAtValid = $Descriptor.built_at -is [datetime] -or
        $Descriptor.built_at -is [datetimeoffset] -or
        [datetimeoffset]::TryParse([string]$Descriptor.built_at, [ref]$builtAt)
    if (-not $builtAtValid) {
        throw 'GitHub distribution descriptor содержит некорректный built_at.'
    }

    $expectedPaths = @($PortableFiles | Where-Object { $_ -cne 'TEMPLATE-DISTRIBUTION.json' } | Sort-Object)
    $entries = @($Descriptor.payload_sha256)
    if ($entries.Count -ne $expectedPaths.Count) {
        throw 'GitHub distribution descriptor содержит неполный payload inventory.'
    }
    $seen = @{}
    foreach ($entry in $entries) {
        if ($null -eq $entry -or
            $entry.PSObject.Properties.Name -cnotcontains 'path' -or
            $entry.PSObject.Properties.Name -cnotcontains 'sha256') {
            throw 'GitHub distribution descriptor содержит некорректную hash entry.'
        }
        $relativePath = [string]$entry.path
        $expectedHash = ([string]$entry.sha256).ToLowerInvariant()
        if (-not (Test-ManifestRelativePath $relativePath) -or
            $expectedPaths -cnotcontains $relativePath -or
            $expectedHash -notmatch '^[0-9a-f]{64}$' -or
            $seen.ContainsKey($relativePath.ToLowerInvariant())) {
            throw 'GitHub distribution descriptor содержит небезопасную или дублирующуюся hash entry.'
        }
        $seen[$relativePath.ToLowerInvariant()] = $true
        $actualHash = Get-BoundedFileSha256 `
            -LiteralPath (Join-Path $repoRoot $relativePath) `
            -MaxBytes $descriptorMaxBytes `
            -Label $relativePath
        if ($actualHash -cne $expectedHash) {
            throw "GitHub distribution payload drift: $relativePath"
        }
    }
    foreach ($expectedPath in $expectedPaths) {
        if (-not $seen.ContainsKey($expectedPath.ToLowerInvariant())) {
            throw 'GitHub distribution descriptor не покрывает portable payload.'
        }
    }
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

function Invoke-RepositoryGit {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $result = Invoke-SanitizedProcess -Executable $gitExe -Arguments (@(
        '-c', "safe.directory=$repoRoot",
        '-c', 'core.fsmonitor=false',
        '-c', "core.hooksPath=$nullDevice",
        '-c', 'core.quotePath=false',
        '-C', $repoRoot
    ) + $Arguments)
    $characters = [long]0
    $resultLines = @($result.Output)
    foreach ($line in $resultLines) { $characters += ([string]$line).Length }
    if ($resultLines.Count -gt 100000 -or $characters -gt 8MB) {
        throw 'Git output превысил безопасный лимит.'
    }
    return $result
}

function Assert-GitHubTemplateRepository {
    param([Parameter(Mandatory = $true)]$Descriptor)

    $topLevel = Invoke-RepositoryGit -Arguments @('rev-parse', '--show-toplevel')
    $topLevelLines = @($topLevel.Output)
    if ($topLevel.ExitCode -ne 0 -or $topLevelLines.Count -ne 1) {
        throw 'Existing Git repository не прошел root gate.'
    }
    try { $reportedRoot = [System.IO.Path]::GetFullPath([string]$topLevelLines[0]).TrimEnd([char[]]'\/') }
    catch { throw 'Existing Git repository вернул некорректный root.' }
    if (-not $reportedRoot.Equals($repoRoot, $script:repoPathComparison)) {
        throw 'Инициализация разрешена только в корне existing Git repository.'
    }

    $head = Invoke-RepositoryGit -Arguments @('rev-parse', '--verify', '--quiet', 'HEAD^{commit}')
    $headLines = @($head.Output)
    if ($head.ExitCode -ne 0 -or $headLines.Count -ne 1 -or
        [string]$headLines[0] -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        throw 'GitHub Template repository не содержит trusted HEAD.'
    }
    $status = Invoke-RepositoryGit -Arguments @('status', '--porcelain=v1', '--untracked-files=all')
    if ($status.ExitCode -ne 0 -or @($status.Output).Count -ne 0) {
        throw 'GitHub Template setup требует clean worktree.'
    }

    $fetchSpecs = Invoke-RepositoryGit -Arguments @('config', '--get-all', 'remote.origin.fetch')
    if ($fetchSpecs.ExitCode -ne 0 -or
        -not (@($fetchSpecs.Output) -ccontains '+refs/heads/*:refs/remotes/origin/*')) {
        throw 'GitHub Template setup требует обычный clone со всеми remote branches. Не используйте --single-branch.'
    }

    $refs = Invoke-RepositoryGit -Arguments @('for-each-ref', '--format=%(refname)', 'refs/heads', 'refs/remotes')
    if ($refs.ExitCode -ne 0) { throw 'Не удалось проверить Git refs.' }
    foreach ($ref in @($refs.Output)) {
        if ([string]$ref -cmatch '^refs/(?:heads|remotes/[^/]+)/source$') {
            throw 'Обнаружен source branch/ref. Создайте repository без Include all branches.'
        }
    }

    $origin = Invoke-RepositoryGit -Arguments @('remote', 'get-url', 'origin')
    $originLines = @($origin.Output)
    if ($origin.ExitCode -ne 0 -or $originLines.Count -ne 1) {
        throw 'GitHub Template setup требует ровно один читаемый origin URL.'
    }
    $currentIdentity = Get-GitHubRepositoryIdentity -RemoteUrl ([string]$originLines[0])
    $templateIdentity = Get-GitHubRepositoryIdentity -RemoteUrl ([string]$Descriptor.template_repository_url)
    if ($null -eq $currentIdentity -or $null -eq $templateIdentity) {
        throw 'Поддерживаются только HTTPS или SSH remotes GitHub без credentials.'
    }
    if ($currentIdentity -ceq $templateIdentity) {
        throw 'Прямой clone канонического template repository нельзя инициализировать как продукт.'
    }
}

function Write-AtomicUtf8File {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [AllowEmptyString()]
        [Parameter(Mandatory = $true)][string]$Content
    )

    $fullTarget = [System.IO.Path]::GetFullPath($TargetPath)
    if (-not $fullTarget.StartsWith($repoRoot + [System.IO.Path]::DirectorySeparatorChar, $script:repoPathComparison)) {
        throw "Atomic write выходит за корень проекта: $fullTarget"
    }
    $targetParent = [System.IO.Path]::GetDirectoryName($fullTarget)
    Assert-NoReparseChain $repoRoot
    Assert-NoReparseChain $targetParent
    if (Test-Path -LiteralPath $fullTarget) {
        Assert-NoReparseChain $fullTarget
        if (-not (Test-Path -LiteralPath $fullTarget -PathType Leaf)) {
            throw "Atomic write target не является файлом: $fullTarget"
        }
    }

    $operationId = [guid]::NewGuid().ToString('N')
    $temporaryLeaf = ".codex-init-$operationId.tmp"
    $temporaryPath = Join-Path $targetParent $temporaryLeaf
    $backupLeaf = ".codex-init-$operationId.bak"
    $backupPath = Join-Path $targetParent $backupLeaf
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $Content, $utf8NoBom)
        Assert-NoReparseChain $temporaryPath
        if (Test-Path -LiteralPath $fullTarget -PathType Leaf) {
            [System.IO.File]::Replace($temporaryPath, $fullTarget, $backupPath, $true)
            [System.IO.File]::Delete($backupPath)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $fullTarget)
        }
        Assert-NoReparseChain $fullTarget
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            $actualParent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($temporaryPath))
            $actualLeaf = [System.IO.Path]::GetFileName($temporaryPath)
            if ($actualParent.Equals($targetParent, $script:repoPathComparison) -and
                $actualLeaf -match '^\.codex-init-[0-9a-f]{32}\.tmp$') {
                [System.IO.File]::Delete($temporaryPath)
            }
        }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            $actualBackupParent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($backupPath))
            $actualBackupLeaf = [System.IO.Path]::GetFileName($backupPath)
            if ($actualBackupParent.Equals($targetParent, $script:repoPathComparison) -and
                $actualBackupLeaf -match '^\.codex-init-[0-9a-f]{32}\.bak$') {
                [System.IO.File]::Delete($backupPath)
            }
        }
    }
}

function Read-BoundedFileBytes {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][long]$MaxBytes,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $absolutePath = [System.IO.Path]::GetFullPath($LiteralPath)
    Assert-NoReparseChain $absolutePath
    $item = Get-Item -LiteralPath $absolutePath -Force
    if (-not $item.PSIsContainer -and [long]$item.Length -le $MaxBytes) {
        Assert-NoReparseChain $absolutePath
        return [System.IO.File]::ReadAllBytes($absolutePath)
    }
    throw "Файл невозможно безопасно сохранить для rollback: $Label"
}

function Write-AtomicBytesFile {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $fullTarget = [System.IO.Path]::GetFullPath($TargetPath)
    if (-not $fullTarget.StartsWith($repoRoot + [System.IO.Path]::DirectorySeparatorChar, $script:repoPathComparison)) {
        throw 'Rollback write выходит за корень проекта.'
    }
    $targetParent = [System.IO.Path]::GetDirectoryName($fullTarget)
    Assert-NoReparseChain $repoRoot
    Assert-NoReparseChain $targetParent
    if (Test-Path -LiteralPath $fullTarget) {
        Assert-NoReparseChain $fullTarget
        if (-not (Test-Path -LiteralPath $fullTarget -PathType Leaf)) {
            throw 'Rollback target не является обычным файлом.'
        }
    }

    $operationId = [guid]::NewGuid().ToString('N')
    $temporaryPath = Join-Path $targetParent ".codex-rollback-$operationId.tmp"
    $backupPath = Join-Path $targetParent ".codex-rollback-$operationId.bak"
    try {
        [System.IO.File]::WriteAllBytes($temporaryPath, $Bytes)
        Assert-NoReparseChain $temporaryPath
        if (Test-Path -LiteralPath $fullTarget -PathType Leaf) {
            [System.IO.File]::Replace($temporaryPath, $fullTarget, $backupPath, $true)
            [System.IO.File]::Delete($backupPath)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $fullTarget)
        }
        Assert-NoReparseChain $fullTarget
    }
    finally {
        foreach ($cleanupPath in @($temporaryPath, $backupPath)) {
            if (-not (Test-Path -LiteralPath $cleanupPath -PathType Leaf)) { continue }
            $cleanupParent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($cleanupPath))
            $cleanupLeaf = [System.IO.Path]::GetFileName($cleanupPath)
            if ($cleanupParent.Equals($targetParent, $script:repoPathComparison) -and
                $cleanupLeaf -match '^\.codex-rollback-[0-9a-f]{32}\.(?:tmp|bak)$') {
                [System.IO.File]::Delete($cleanupPath)
            }
        }
    }
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
        elseif ($isDirectory) {
            Remove-DirectoryTreeWithoutFollowingReparse -DirectoryPath $entry
        }
        else {
            [System.IO.File]::SetAttributes($entry, [System.IO.FileAttributes]::Normal)
            [System.IO.File]::Delete($entry)
        }
    }
    [System.IO.Directory]::Delete($DirectoryPath, $false)
}

function Remove-ExactInitializationArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$ExpectedLeaf,
        [switch]$AllowDirectoryTree
    )

    $fullTarget = [System.IO.Path]::GetFullPath($TargetPath).TrimEnd([char[]]'\/')
    $expectedTarget = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $ExpectedLeaf)).TrimEnd([char[]]'\/')
    if (-not $fullTarget.Equals($expectedTarget, $script:repoPathComparison) -or
        [System.IO.Path]::GetFileName($fullTarget) -cne $ExpectedLeaf -or
        -not ([System.IO.Path]::GetDirectoryName($fullTarget)).Equals($repoRoot, $script:repoPathComparison)) {
        throw 'Отказ от rollback неожиданного пути.'
    }
    Assert-NoReparseChain $repoRoot
    if (-not (Test-Path -LiteralPath $fullTarget)) { return }

    $attributes = [System.IO.File]::GetAttributes($fullTarget)
    $isDirectory = ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0
    $isReparse = ($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    if ($isReparse) {
        if ($isDirectory) { [System.IO.Directory]::Delete($fullTarget, $false) }
        else { [System.IO.File]::Delete($fullTarget) }
        return
    }
    if ($isDirectory) {
        if (-not $AllowDirectoryTree) { throw 'Rollback artifact неожиданно является каталогом.' }
        Remove-DirectoryTreeWithoutFollowingReparse -DirectoryPath $fullTarget
        return
    }
    [System.IO.File]::Delete($fullTarget)
}

$repoRootCandidate = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd([char[]]'\/')
Assert-NoReparseChain $repoRootCandidate
$repoRoot = (Resolve-Path -LiteralPath $repoRootCandidate).Path.TrimEnd([char[]]'\/')
$script:repoPathComparison = Get-ModelProjectPathComparison -Path $repoRoot
$projectPath = Join-Path $repoRoot 'PROJECT.md'
$manifestPath = Join-Path $repoRoot '.template-manifest.json'
$readmePath = Join-Path $repoRoot 'README.md'
$descriptorPath = Join-Path $repoRoot 'TEMPLATE-DISTRIBUTION.json'
$originPath = Join-Path $repoRoot 'TEMPLATE-ORIGIN.md'
$templateLicenseSourcePath = Join-Path $repoRoot 'LICENSE'
$templateNoticesSourcePath = Join-Path $repoRoot 'THIRD-PARTY-NOTICES.md'
$templateLicenseTargetPath = Join-Path $repoRoot 'TEMPLATE-LICENSE.md'
$templateNoticesTargetPath = Join-Path $repoRoot 'TEMPLATE-THIRD-PARTY-NOTICES.md'

foreach ($requiredInput in @(
    $projectPath, $manifestPath, $readmePath, $descriptorPath,
    $templateLicenseSourcePath, $templateNoticesSourcePath
)) {
    if (-not (Test-Path -LiteralPath $requiredInput -PathType Leaf)) {
        throw "Обязательный файл инициализации не найден: $requiredInput"
    }
    Assert-NoReparseChain $requiredInput
}
Assert-NoReparseChain $originPath
if (Test-Path -LiteralPath $originPath) {
    throw 'TEMPLATE-ORIGIN.md уже существует, повторная инициализация запрещена.'
}
foreach ($generatedLicensePath in @($templateLicenseTargetPath, $templateNoticesTargetPath)) {
    Assert-NoReparseChain $generatedLicensePath
    if (Test-Path -LiteralPath $generatedLicensePath) {
        throw 'Template license target уже существует, повторная инициализация запрещена.'
    }
}
if ($InitializeGit -and (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
    throw 'В копии уже есть .git. Инициализацию нужно выполнять только для чистой переносимой копии.'
}
if ($FromGitHubTemplate -and -not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
    throw 'GitHub Template setup требует существующий .git.'
}

$manifestText = Read-BoundedUtf8File -LiteralPath $manifestPath -MaxBytes $manifestMaxBytes -Label '.template-manifest.json'
try {
    $manifest = $manifestText | ConvertFrom-Json
}
catch {
    throw '.template-manifest.json содержит невалидный JSON; parser details скрыты.'
}
if ($manifest.PSObject.Properties.Name -cnotcontains 'template_version') {
    throw '.template-manifest.json не содержит template_version.'
}
foreach ($manifestProperty in @('portable_files', 'initialization_renames', 'generated_forbidden_paths')) {
    if ($manifest.PSObject.Properties.Name -cnotcontains $manifestProperty) {
        throw ".template-manifest.json не содержит $manifestProperty."
    }
}
$semVerPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(?:(?:0|[1-9][0-9]*)|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:(?:0|[1-9][0-9]*)|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$'
if ($manifest.template_version -isnot [string] -or
    $manifest.template_version.Length -gt 128 -or
    $manifest.template_version -cnotmatch $semVerPattern) {
    throw '.template-manifest.json template_version должен быть SemVer scalar длиной не более 128 символов.'
}
$version = [string]$manifest.template_version
$portableFiles = @($manifest.portable_files | ForEach-Object { [string]$_ })
$initializationRenames = @($manifest.initialization_renames)
$generatedForbiddenPaths = @($manifest.generated_forbidden_paths | ForEach-Object { [string]$_ })
$expectedRenamePairs = @(
    'LICENSE->TEMPLATE-LICENSE.md',
    'THIRD-PARTY-NOTICES.md->TEMPLATE-THIRD-PARTY-NOTICES.md'
)
$actualRenamePairs = @($initializationRenames | ForEach-Object { '{0}->{1}' -f [string]$_.from, [string]$_.to } | Sort-Object)
if ($actualRenamePairs.Count -ne $expectedRenamePairs.Count -or
    (Compare-Object -ReferenceObject ($expectedRenamePairs | Sort-Object) -DifferenceObject $actualRenamePairs).Count -ne 0) {
    throw '.template-manifest.json initialization_renames не соответствует license boundary.'
}
foreach ($rename in $initializationRenames) {
    $from = [string]$rename.from
    $to = [string]$rename.to
    if (-not (Test-ManifestRelativePath $from) -or -not (Test-ManifestRelativePath $to) -or
        $portableFiles -cnotcontains $from -or $portableFiles -ccontains $to -or
        $generatedForbiddenPaths -cnotcontains $from -or $generatedForbiddenPaths -ccontains $to) {
        throw '.template-manifest.json initialization_renames содержит некорректный path contract.'
    }
}

$verifier = Join-Path $PSScriptRoot 'verify-structure.ps1'
if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) {
    throw "verify-structure.ps1 не найден рядом с инициализатором: $verifier"
}
Assert-NoReparseChain $verifier
$powershellExe = Get-TrustedCurrentPowerShellHost -ControlledRoots @($repoRoot)
$gitExe = Get-TrustedGitExecutable -ControlledRoots @($repoRoot)

$descriptorText = Read-BoundedUtf8File `
    -LiteralPath $descriptorPath `
    -MaxBytes $descriptorMaxBytes `
    -Label 'TEMPLATE-DISTRIBUTION.json'
try { $descriptor = $descriptorText | ConvertFrom-Json }
catch { throw 'TEMPLATE-DISTRIBUTION.json содержит невалидный JSON; parser details скрыты.' }

$writeDescriptorDuringInitialization = $false
$initializationSourceKind = ''
if ($InitializeGit) {
    if ($descriptor.PSObject.Properties.Name -cnotcontains 'distribution_kind' -or
        $descriptor.distribution_kind -isnot [string]) {
        throw 'Independent initialization требует строковый distribution_kind.'
    }
    if ([string]$descriptor.distribution_kind -ceq 'source-placeholder') {
        Assert-DescriptorShape `
            -Descriptor $descriptor `
            -ExpectedKind 'source-placeholder' `
            -TemplateVersion $version `
            -PortableFiles $portableFiles
        $descriptor = [ordered]@{
            schema_version = 1
            distribution_kind = 'local-copy'
            template_version = $version
            source_tag = $null
            source_commit = $null
            template_repository_url = $null
            built_at = (Get-Date).ToUniversalTime().ToString('o')
            payload_sha256 = @(Get-PayloadHashEntries -PortableFiles $portableFiles)
        }
        $descriptorText = ConvertTo-DescriptorJson -Descriptor $descriptor
        $writeDescriptorDuringInitialization = $true
        $initializationSourceKind = 'template-source'
    }
    elseif ([string]$descriptor.distribution_kind -ceq 'github-template') {
        Assert-DescriptorShape `
            -Descriptor $descriptor `
            -ExpectedKind 'github-template' `
            -TemplateVersion $version `
            -PortableFiles $portableFiles
        $initializationSourceKind = 'distribution-template'
    }
    else {
        throw 'Independent initialization принимает только source-placeholder или github-template payload.'
    }
}
else {
    Assert-DescriptorShape `
        -Descriptor $descriptor `
        -ExpectedKind 'github-template' `
        -TemplateVersion $version `
        -PortableFiles $portableFiles
    Assert-GitHubTemplateRepository -Descriptor $descriptor
    $initializationSourceKind = 'distribution-template'
}
$descriptorDigest = Get-TextSha256 -Text $descriptorText

$project = Read-BoundedUtf8File -LiteralPath $projectPath -MaxBytes $projectMaxBytes -Label 'PROJECT.md'
$expectedRepositoryKind = $initializationSourceKind
$requiredTemplateFragments = @(
    "repository_kind: $expectedRepositoryKind",
    'project_status: template',
    'project_id: "{{PROJECT_SLUG}}"',
    'knowledge_contract_version: 1',
    'knowledge_capture_mode: disabled',
    '{{PROJECT_NAME}}',
    '{{PROJECT_DESCRIPTION}}',
    '{{OWNER}}'
)
foreach ($requiredFragment in $requiredTemplateFragments) {
    if (-not $project.Contains($requiredFragment)) {
        throw "PROJECT.md не соответствует инициализируемому шаблону: отсутствует $requiredFragment"
    }
}

$projectId = [guid]::NewGuid().ToString('D')
$project = $project.Replace("repository_kind: $expectedRepositoryKind", 'repository_kind: generated-project')
$project = $project.Replace('project_status: template', 'project_status: initialized')
$project = $project.Replace('project_id: "{{PROJECT_SLUG}}"', "project_id: `"$projectId`"")
$project = $project.Replace('knowledge_capture_mode: disabled', 'knowledge_capture_mode: report-only')
$project = $project.Replace('{{PROJECT_NAME}}', $ProjectName)
$project = $project.Replace('{{PROJECT_SLUG}}', $ProjectSlug)
$project = $project.Replace('{{PROJECT_DESCRIPTION}}', $Description)
$project = $project.Replace('{{OWNER}}', $Owner)

$readmeTemplate = Read-BoundedUtf8File -LiteralPath $readmePath -MaxBytes $readmeMaxBytes -Label 'README.md'
$sourceHeading = '# Codex Analyst Template'
if (-not $readmeTemplate.StartsWith($sourceHeading, [System.StringComparison]::Ordinal)) {
    throw 'README.md не содержит ожидаемый source heading.'
}
$usageHeading = '## Первый рабочий цикл'
$usageHeadingIndex = $readmeTemplate.IndexOf($usageHeading, [System.StringComparison]::Ordinal)
if ($usageHeadingIndex -lt 0) {
    throw 'README.md не содержит ожидаемый usage section.'
}
$readme = "# $ProjectName`n`n$Description`n`n" + $readmeTemplate.Substring($usageHeadingIndex)
$readme = $readme.Replace('(LICENSE)', '(TEMPLATE-LICENSE.md)')
$readme = $readme.Replace('(THIRD-PARTY-NOTICES.md)', '(TEMPLATE-THIRD-PARTY-NOTICES.md)')

$sourceTagDisplay = if ($null -eq $descriptor.source_tag) { 'не применимо' } else { [string]$descriptor.source_tag }
$sourceCommitDisplay = if ($null -eq $descriptor.source_commit) { 'не применимо' } else { [string]$descriptor.source_commit }
$repositoryDisplay = if ($null -eq $descriptor.template_repository_url) { 'local source copy' } else { [string]$descriptor.template_repository_url }

$origin = @"
# Происхождение проекта

- Версия шаблона: $version
- Канал распространения: $([string]$descriptor.distribution_kind)
- Source tag: $sourceTagDisplay
- Source commit: $sourceCommitDisplay
- Template repository: $repositoryDisplay
- SHA-256 дескриптора: $descriptorDigest
- Project ID: $projectId
- Инициализирован: $(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')
- Начальный режим: initialized + report-only

Старые проекты не мигрируются автоматически. Изменения новых версий шаблона применяются отдельным решением.
"@

$originalProjectBytes = Read-BoundedFileBytes -LiteralPath $projectPath -MaxBytes $projectMaxBytes -Label 'PROJECT.md'
$originalReadmeBytes = Read-BoundedFileBytes -LiteralPath $readmePath -MaxBytes $readmeMaxBytes -Label 'README.md'
$originalDescriptorBytes = Read-BoundedFileBytes -LiteralPath $descriptorPath -MaxBytes $descriptorMaxBytes -Label 'TEMPLATE-DISTRIBUTION.json'
$originalLicenseBytes = Read-BoundedFileBytes -LiteralPath $templateLicenseSourcePath -MaxBytes $licenseMaxBytes -Label 'LICENSE'
$originalNoticesBytes = Read-BoundedFileBytes -LiteralPath $templateNoticesSourcePath -MaxBytes $licenseMaxBytes -Label 'THIRD-PARTY-NOTICES.md'
$planIndexer = Join-Path $repoRoot 'scripts/update-plan-index.ps1'
$planIndexPath = Join-Path $repoRoot 'plans/INDEX.md'
foreach ($planInput in @($planIndexer, $planIndexPath)) {
    if (-not (Test-Path -LiteralPath $planInput -PathType Leaf)) { throw "Обязательный Plan v2 файл не найден: $planInput" }
    Assert-NoReparseChain $planInput
}
$originalPlanIndexBytes = Read-BoundedFileBytes -LiteralPath $planIndexPath -MaxBytes 2MB -Label 'plans/INDEX.md'
$masteryIndexer = Join-Path $repoRoot 'scripts/update-mastery-index.ps1'
$masteryIndexPath = Join-Path $repoRoot 'mastery/local/INDEX.md'
foreach ($masteryInput in @($masteryIndexer, $masteryIndexPath)) {
    if (-not (Test-Path -LiteralPath $masteryInput -PathType Leaf)) { throw "Обязательный Mastery v2 файл не найден: $masteryInput" }
    Assert-NoReparseChain $masteryInput
}
$originalMasteryIndexBytes = Read-BoundedFileBytes -LiteralPath $masteryIndexPath -MaxBytes 2MB -Label 'mastery/local/INDEX.md'
$gitMetadataPath = Join-Path $repoRoot '.git'
$gitMetadataAbsentBeforeMutation = -not (Test-Path -LiteralPath $gitMetadataPath)
$publicationBegan = $false

try {
    $publicationBegan = $true
    Write-AtomicUtf8File -TargetPath $projectPath -Content $project
    Write-AtomicUtf8File -TargetPath $readmePath -Content ($readme.Trim() + "`n")
    if ($writeDescriptorDuringInitialization) {
        Write-AtomicUtf8File -TargetPath $descriptorPath -Content $descriptorText
    }
    Write-AtomicUtf8File -TargetPath $originPath -Content ($origin.Trim() + "`n")
    Write-AtomicBytesFile -TargetPath $templateLicenseTargetPath -Bytes $originalLicenseBytes
    Write-AtomicBytesFile -TargetPath $templateNoticesTargetPath -Bytes $originalNoticesBytes
    Remove-ExactInitializationArtifact -TargetPath $templateLicenseSourcePath -ExpectedLeaf 'LICENSE'
    Remove-ExactInitializationArtifact -TargetPath $templateNoticesSourcePath -ExpectedLeaf 'THIRD-PARTY-NOTICES.md'

    if ($InitializeGit) {
        Assert-NoReparseChain $repoRoot
        $gitResult = Invoke-SanitizedProcess -Executable $gitExe -Arguments @(
            '-c', "safe.directory=$repoRoot",
            '-c', 'core.fsmonitor=false',
            '-c', "core.hooksPath=$nullDevice",
            '-c', 'core.quotePath=false',
            '-C', $repoRoot,
            'init', '-b', 'main'
        )
        if ($gitResult.ExitCode -ne 0) {
            throw 'git init завершился с ошибкой.'
        }
    }

    $planIndexResult = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $planIndexer,
        '-Root', $repoRoot, '-Mode', 'Write'
    )
    if ($planIndexResult.ExitCode -ne 0) { throw 'Не удалось пересобрать plans/INDEX.md после инициализации.' }

    $masteryIndexResult = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $masteryIndexer,
        '-Root', $repoRoot, '-Mode', 'Write'
    )
    if ($masteryIndexResult.ExitCode -ne 0) { throw 'Не удалось пересобрать mastery/local/INDEX.md после инициализации.' }

    Assert-NoReparseChain $repoRoot
    $verifyResult = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifier,
        '-Root', $repoRoot, '-Mode', 'GeneratedProject'
    )
    if ($verifyResult.ExitCode -ne 0) {
        foreach ($line in $verifyResult.Output) { Write-Host ([string]$line) }
        throw 'Инициализация не прошла проверку GeneratedProject.'
    }
    foreach ($line in $planIndexResult.Output) { Write-Host ([string]$line) }
    foreach ($line in $masteryIndexResult.Output) { Write-Host ([string]$line) }
    foreach ($line in $verifyResult.Output) { Write-Host ([string]$line) }
}
catch {
    $originalFailure = $_
    $rollbackFailures = [System.Collections.Generic.List[string]]::new()
    try { Write-AtomicBytesFile -TargetPath $projectPath -Bytes $originalProjectBytes }
    catch { $rollbackFailures.Add('PROJECT.md') }
    try { Write-AtomicBytesFile -TargetPath $readmePath -Bytes $originalReadmeBytes }
    catch { $rollbackFailures.Add('README.md') }
    try { Write-AtomicBytesFile -TargetPath $descriptorPath -Bytes $originalDescriptorBytes }
    catch { $rollbackFailures.Add('TEMPLATE-DISTRIBUTION.json') }
    try { Write-AtomicBytesFile -TargetPath $planIndexPath -Bytes $originalPlanIndexBytes }
    catch { $rollbackFailures.Add('plans/INDEX.md') }
    try { Write-AtomicBytesFile -TargetPath $masteryIndexPath -Bytes $originalMasteryIndexBytes }
    catch { $rollbackFailures.Add('mastery/local/INDEX.md') }
    try { Write-AtomicBytesFile -TargetPath $templateLicenseSourcePath -Bytes $originalLicenseBytes }
    catch { $rollbackFailures.Add('LICENSE') }
    try { Write-AtomicBytesFile -TargetPath $templateNoticesSourcePath -Bytes $originalNoticesBytes }
    catch { $rollbackFailures.Add('THIRD-PARTY-NOTICES.md') }
    try { Remove-ExactInitializationArtifact -TargetPath $originPath -ExpectedLeaf 'TEMPLATE-ORIGIN.md' }
    catch { $rollbackFailures.Add('TEMPLATE-ORIGIN.md') }
    try { Remove-ExactInitializationArtifact -TargetPath $templateLicenseTargetPath -ExpectedLeaf 'TEMPLATE-LICENSE.md' }
    catch { $rollbackFailures.Add('TEMPLATE-LICENSE.md') }
    try { Remove-ExactInitializationArtifact -TargetPath $templateNoticesTargetPath -ExpectedLeaf 'TEMPLATE-THIRD-PARTY-NOTICES.md' }
    catch { $rollbackFailures.Add('TEMPLATE-THIRD-PARTY-NOTICES.md') }
    if ($InitializeGit -and $gitMetadataAbsentBeforeMutation) {
        try { Remove-ExactInitializationArtifact -TargetPath $gitMetadataPath -ExpectedLeaf '.git' -AllowDirectoryTree }
        catch { $rollbackFailures.Add('.git') }
    }
    if ($rollbackFailures.Count -gt 0) {
        $script:initializeFailureCode = 'initialization-rollback-incomplete'
        throw 'initialization-rollback-incomplete'
    }
    $script:initializeFailureCode = if ($publicationBegan) { 'initialization-rolled-back' } else { 'initialization-rejected' }
    throw $originalFailure
}

Write-Host "Проект '$ProjectName' инициализирован в '$repoRoot' как initialized + report-only. Project ID: $projectId"
