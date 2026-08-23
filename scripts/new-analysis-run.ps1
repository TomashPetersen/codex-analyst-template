[CmdletBinding()]
param(
    [string]$Root = '',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Slug,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TaskRef
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$assetFileMaxBytes = 1MB
$assetCorpusMaxBytes = 8MB
$renderedFileMaxBytes = 2MB
$maximumCollisionAttempts = 10
$runFiles = @(
    'brief.md',
    'sources.md',
    'analysis.md',
    'requirements.md',
    'models.md',
    'traceability.md',
    'review.md',
    'decision.md'
)
$requiredPlaceholders = @('RUN_ID', 'RUN_TITLE', 'TASK_REF', 'CREATED_AT')

[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

function Get-BootstrapReparsePointInFullChain {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    $pathRoot = [System.IO.Path]::GetPathRoot($full)
    $current = $pathRoot
    foreach ($segment in (($full.Substring($pathRoot.Length) -split '[\\/]') | Where-Object { $_ -ne '' })) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { break }
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $current }
    }
    return $null
}

function Test-BootstrapExactPathCase {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    if (-not (Test-Path -LiteralPath $full)) { return $false }
    $parent = [System.IO.Path]::GetDirectoryName($full)
    $leaf = [System.IO.Path]::GetFileName($full)
    $matches = @(
        [System.IO.Directory]::EnumerateFileSystemEntries($parent) |
            Where-Object { [System.IO.Path]::GetFileName($_).Equals($leaf, [System.StringComparison]::OrdinalIgnoreCase) }
    )
    return ($matches.Count -eq 1 -and [System.IO.Path]::GetFileName($matches[0]) -ceq $leaf)
}

function Assert-NoReparseChain {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    if ($null -ne (Get-ModelProjectReparsePointInFullChain -Root $full -Path $full)) {
        throw 'Путь проходит через reparse point.'
    }
}

function Assert-ExactExistingPathCase {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $full = [System.IO.Path]::GetFullPath($AbsolutePath).TrimEnd([char[]]'\/')
    if (-not (Test-ModelProjectExactPathCase -Root $full -Path $full)) {
        throw 'Путь не совпадает с filesystem path по регистру.'
    }
}

function Assert-SafeRootInput {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or
        $Value.IndexOf([char]0) -ge 0 -or
        $Value -match '[\r\n]' -or
        $Value.StartsWith('\\') -or
        $Value.StartsWith('//') -or
        $Value -match '^(?i:file:|\\\\[.?]\\|GLOBALROOT)' -or
        $Value -match '^[A-Za-z]:[^\\/]') {
        throw 'Root должен быть безопасным локальным filesystem path.'
    }

    foreach ($segment in (($Value -replace '/', '\\') -split '\\')) {
        if ($segment -eq '.' -or $segment -eq '..') {
            throw 'Root не должен содержать traversal segments.'
        }
    }
}

function Assert-LocalFilesystemPath {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    $pathRoot = [System.IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($pathRoot) -or
        $pathRoot.StartsWith('\\') -or
        $pathRoot.StartsWith('//')) {
        throw 'Root должен находиться на локальном filesystem drive.'
    }

    try {
        $driveInfo = [System.IO.DriveInfo]::new($pathRoot)
        if ($driveInfo.DriveType -eq [System.IO.DriveType]::Network) {
            throw 'Root на сетевом диске запрещен.'
        }
    }
    catch [System.ArgumentException] {
        throw 'Не удалось подтвердить локальный filesystem drive.'
    }

    $driveName = $pathRoot.TrimEnd([char[]]'\/').TrimEnd(':')
    $psDrive = Get-PSDrive -Name $driveName -PSProvider FileSystem -ErrorAction SilentlyContinue
    if ($null -ne $psDrive -and
        -not [string]::IsNullOrWhiteSpace([string]$psDrive.DisplayRoot) -and
        ([string]$psDrive.DisplayRoot).StartsWith('\\')) {
        throw 'Root на mapped network drive запрещен.'
    }
}

function Test-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [Parameter(Mandatory = $true)][string]$ControlledRoot
    )

    return Test-ModelProjectPathWithinRoot -Root $ControlledRoot -Path $CandidatePath
}

function Read-BoundedUtf8File {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][long]$MaxBytes,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $absolutePath = [System.IO.Path]::GetFullPath($LiteralPath)
    $readRoot = Split-Path -Parent $absolutePath
    try {
        Assert-ExactExistingPathCase $absolutePath
        $text = Read-ModelProjectBoundedUtf8File -Root $readRoot -Path $absolutePath -MaxBytes $MaxBytes
    }
    catch {
        throw "Файл не прошел bounded UTF-8 gate: $Label"
    }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
        $text = $text.Substring(1)
    }
    return $text
}

function Convert-FrontMatterScalar {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$RawValue)

    $value = $RawValue.Trim()
    if ($value.Length -ge 2 -and $value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') {
        $inner = $value.Substring(1, $value.Length - 2)
        if ($inner -match '(?<!\\)\\(?!["\\/bfnrtu])' -or $inner -match '\\u(?![0-9A-Fa-f]{4})') {
            throw 'Некорректная quoted строка во frontmatter.'
        }
        $inner = [regex]::Replace($inner, '\\u(?<hex>[0-9A-Fa-f]{4})', {
            param($match)
            [char][convert]::ToInt32($match.Groups['hex'].Value, 16)
        })
        return $inner.Replace('\"', '"').Replace('\/', '/').Replace('\n', "`n").Replace('\r', "`r").Replace('\t', "`t").Replace('\b', "`b").Replace('\f', "`f").Replace('\\', '\')
    }
    if ($value.Length -ge 2 -and $value[0] -eq "'" -and $value[$value.Length - 1] -eq "'") {
        return $value.Substring(1, $value.Length - 2).Replace("''", "'")
    }
    return $value
}

function Read-SimpleFrontMatterFromText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $lines = @($Text -split '\r?\n')
    if ($lines.Count -lt 3 -or $lines[0] -cne '---') {
        throw "Отсутствует frontmatter: $Label"
    }

    $data = @{}
    $closed = $false
    for ($index = 1; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]
        if ($line -ceq '---') {
            $closed = $true
            break
        }
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line -cnotmatch '^(?<key>[a-z][a-z0-9_]*):[ \t]*(?<value>.*)$') {
            throw "Неподдерживаемая строка frontmatter: $Label"
        }
        $key = [string]$Matches['key']
        if ($data.ContainsKey($key)) {
            throw "Дубликат frontmatter field: $Label"
        }
        $data[$key] = Convert-FrontMatterScalar -RawValue ([string]$Matches['value'])
    }
    if (-not $closed) {
        throw "Frontmatter не закрыт: $Label"
    }
    return $data
}

function Assert-ProjectMode {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $projectPath = Join-Path $RepositoryRoot 'PROJECT.md'
    $projectText = Read-BoundedUtf8File -LiteralPath $projectPath -MaxBytes 1MB -Label 'PROJECT.md'
    $project = Read-SimpleFrontMatterFromText -Text $projectText -Label 'PROJECT.md'
    foreach ($field in @(
        'repository_kind',
        'project_status',
        'project_id',
        'knowledge_contract_version',
        'knowledge_capture_mode'
    )) {
        if (-not $project.ContainsKey($field) -or
            [string]::IsNullOrWhiteSpace([string]$project[$field])) {
            throw "PROJECT.md не содержит обязательное поле: $field"
        }
    }

    $validRunMode =
        ([string]$project.project_status -ceq 'initialized' -and
         [string]$project.knowledge_capture_mode -ceq 'report-only') -or
        ([string]$project.project_status -ceq 'active' -and
         [string]$project.knowledge_capture_mode -cin @('report-only', 'safe-local'))

    if ([string]$project.repository_kind -cne 'generated-project' -or
        [string]$project.knowledge_contract_version -cne '1' -or
        -not $validRunMode) {
        throw 'blocked: repository-mode'
    }
    if ([string]$project.project_id -match '\{\{.+\}\}') {
        throw 'PROJECT.md не инициализирован: project_id содержит placeholder.'
    }
}

function Assert-SafeInputs {
    if ($Slug -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,46}[a-z0-9])?$') {
        throw 'Slug не соответствует closed grammar.'
    }
    if ($TaskRef -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') {
        throw 'TaskRef не соответствует safe stable ref grammar.'
    }
    if ([string]::IsNullOrWhiteSpace($Title) -or
        $Title.Length -gt 200 -or
        $Title.IndexOf([char]0) -ge 0 -or
        $Title -match '[\r\n\x00-\x1F\x7F]' -or
        $Title -match '[{}\[\]<>\\"''`|&*!#%]' -or
        $Title.Trim() -cne $Title) {
        throw 'Title содержит небезопасные символы или имеет недопустимую длину.'
    }
}

function Assert-ExactFlatInventory {
    param(
        [Parameter(Mandatory = $true)][string]$DirectoryPath,
        [Parameter(Mandatory = $true)][string[]]$ExpectedFiles,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container)) {
        throw "Отсутствует обязательный каталог: $Label"
    }
    Assert-NoReparseChain $DirectoryPath
    Assert-ExactExistingPathCase $DirectoryPath

    $entries = @([System.IO.Directory]::EnumerateFileSystemEntries($DirectoryPath))
    if ($entries.Count -ne $ExpectedFiles.Count) {
        throw "Каталог не совпадает с exact inventory: $Label"
    }
    foreach ($entry in $entries) {
        $item = Get-Item -LiteralPath $entry -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $item.PSIsContainer -or
            $item.Name -cnotin $ExpectedFiles) {
            throw "Каталог содержит extra, nested или unsafe entry: $Label"
        }
    }
    foreach ($expected in $ExpectedFiles) {
        if (@($entries | Where-Object { [System.IO.Path]::GetFileName($_) -ceq $expected }).Count -ne 1) {
            throw "Каталог не содержит exact-case файл: $Label"
        }
    }
}

function Read-TrustedRunTemplates {
    param([Parameter(Mandatory = $true)][string]$TemplateRoot)

    Assert-ExactFlatInventory -DirectoryPath $TemplateRoot -ExpectedFiles $runFiles -Label 'run-template'
    $templates = @{}
    $totalBytes = [long]0
    foreach ($fileName in $runFiles) {
        $filePath = Join-Path $TemplateRoot $fileName
        $item = Get-Item -LiteralPath $filePath -Force
        $totalBytes += [long]$item.Length
        if ($totalBytes -gt $assetCorpusMaxBytes) {
            throw 'Run template corpus превышает byte limit.'
        }
        $text = Read-BoundedUtf8File -LiteralPath $filePath -MaxBytes $assetFileMaxBytes -Label "run-template/$fileName"

        $tokens = @([regex]::Matches($text, '\{\{(?<name>[A-Z][A-Z0-9_]*)\}\}') |
            ForEach-Object { [string]$_.Groups['name'].Value } |
            Sort-Object -Unique)
        $unknownTokens = @($tokens | Where-Object { $_ -cnotin $requiredPlaceholders })
        $missingTokens = @($requiredPlaceholders | Where-Object { $_ -cnotin $tokens })
        if ($unknownTokens.Count -gt 0 -or $missingTokens.Count -gt 0) {
            throw "Run template имеет invalid placeholder contract: $fileName"
        }
        $templates[$fileName] = $text
    }
    return $templates
}

function Get-CryptoHexSuffix {
    $bytes = [byte[]]::new(3)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) }
    finally { $rng.Dispose() }
    return ([System.BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}

function Write-NewUtf8File {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $stream = $null
    $writer = $null
    try {
        $stream = [System.IO.FileStream]::new(
            $LiteralPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None,
            4096,
            [System.IO.FileOptions]::WriteThrough
        )
        $writer = [System.IO.StreamWriter]::new($stream, $utf8NoBom)
        $writer.Write($Content)
        $writer.Flush()
        $stream.Flush($true)
    }
    finally {
        if ($null -ne $writer) { $writer.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
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

function Remove-ExactOwnedStagingDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$StagingDirectory,
        [Parameter(Mandatory = $true)][string]$ExpectedParent,
        [Parameter(Mandatory = $true)][string]$ExpectedLeaf
    )

    $fullStaging = [System.IO.Path]::GetFullPath($StagingDirectory).TrimEnd([char[]]'\/')
    $fullParent = [System.IO.Path]::GetFullPath($ExpectedParent).TrimEnd([char[]]'\/')
    $actualParent = [System.IO.Path]::GetDirectoryName($fullStaging)
    $actualLeaf = [System.IO.Path]::GetFileName($fullStaging)
    if (-not $actualParent.Equals($fullParent, [System.StringComparison]::OrdinalIgnoreCase) -or
        $actualLeaf -cne $ExpectedLeaf -or
        $actualLeaf -cnotmatch '^\.analysis-run-staging-[0-9a-f]{32}$') {
        throw 'Отказ от cleanup недоказанного staging path.'
    }
    Assert-NoReparseChain $fullParent
    if (-not (Test-Path -LiteralPath $fullStaging)) { return }

    $attributes = [System.IO.File]::GetAttributes($fullStaging)
    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        [System.IO.Directory]::Delete($fullStaging, $false)
        return
    }
    Remove-DirectoryTreeWithoutFollowingReparse -DirectoryPath $fullStaging
}

function Test-RunNameCollision {
    param(
        [Parameter(Mandatory = $true)][string]$RunsRoot,
        [Parameter(Mandatory = $true)][string]$RunId
    )

    foreach ($entry in [System.IO.Directory]::EnumerateFileSystemEntries($RunsRoot)) {
        if ([System.IO.Path]::GetFileName($entry).Equals($RunId, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

Assert-SafeInputs

$trustedScriptPath = [System.IO.Path]::GetFullPath($PSCommandPath)
$trustedScriptsRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char[]]'\/')
if ([System.IO.Path]::GetFileName($trustedScriptPath) -cne 'new-analysis-run.ps1' -or
    -not [System.IO.Path]::GetDirectoryName($trustedScriptPath).Equals(
        $trustedScriptsRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    throw 'Generator script path не прошел integrity check.'
}
$trustedModulePath = [System.IO.Path]::GetFullPath((Join-Path $trustedScriptsRoot 'lib\ModelProject.Knowledge.psm1'))
$trustedLibRoot = [System.IO.Path]::GetDirectoryName($trustedModulePath)
if (-not (Test-Path -LiteralPath $trustedModulePath -PathType Leaf)) {
    throw 'Trusted knowledge module отсутствует рядом с generator.'
}
if ($null -ne (Get-BootstrapReparsePointInFullChain -AbsolutePath $trustedScriptPath) -or
    $null -ne (Get-BootstrapReparsePointInFullChain -AbsolutePath $trustedModulePath) -or
    -not (Test-BootstrapExactPathCase -AbsolutePath $trustedScriptPath) -or
    -not (Test-BootstrapExactPathCase -AbsolutePath $trustedLibRoot) -or
    -not (Test-BootstrapExactPathCase -AbsolutePath $trustedModulePath)) {
    throw 'Trusted generator path или helper module не прошел bootstrap integrity check.'
}
$trustedModule = Import-Module -Name $trustedModulePath -Scope Local -Force -PassThru -ErrorAction Stop
if ($null -eq $trustedModule -or
    [string]::IsNullOrWhiteSpace([string]$trustedModule.Path) -or
    -not [System.IO.Path]::GetFullPath([string]$trustedModule.Path).Equals($trustedModulePath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Trusted knowledge module не прошел load-origin check.'
}
foreach ($requiredCommand in @(
    'Get-ModelProjectReparsePointInFullChain',
    'Read-ModelProjectBoundedUtf8File',
    'Test-ModelProjectExactPathCase',
    'Test-ModelProjectPathWithinRoot'
)) {
    $command = $trustedModule.ExportedCommands[$requiredCommand]
    if ($null -eq $command -or $command.CommandType -ne [System.Management.Automation.CommandTypes]::Function -or
        $null -eq $command.Module -or
        -not [System.IO.Path]::GetFullPath([string]$command.Module.Path).Equals($trustedModulePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Trusted knowledge module не прошел export-origin check.'
    }
}
Assert-NoReparseChain $trustedScriptPath
Assert-ExactExistingPathCase $trustedScriptPath

$trustedSourceRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $trustedScriptsRoot)).TrimEnd([char[]]'\/')
$trustedTemplateRoot = [System.IO.Path]::GetFullPath((Join-Path $trustedSourceRoot '.agents\skills\it-analysis\assets\run-template'))
if (-not (Test-PathInsideRoot -CandidatePath $trustedTemplateRoot -ControlledRoot $trustedSourceRoot)) {
    throw 'Trusted run-template path вышел за корень package.'
}
Assert-NoReparseChain $trustedTemplateRoot
Assert-ExactExistingPathCase $trustedTemplateRoot
$templates = Read-TrustedRunTemplates -TemplateRoot $trustedTemplateRoot

if ([string]::IsNullOrWhiteSpace($Root)) {
    $rootInput = $trustedSourceRoot
}
else {
    Assert-SafeRootInput -Value $Root
    $rootInput = $Root
}
$rootCandidate = [System.IO.Path]::GetFullPath($rootInput).TrimEnd([char[]]'\/')
Assert-LocalFilesystemPath $rootCandidate
if (-not (Test-Path -LiteralPath $rootCandidate -PathType Container)) {
    throw 'Корень generated project не найден.'
}
Assert-NoReparseChain $rootCandidate
Assert-ExactExistingPathCase $rootCandidate
$rootPath = (Resolve-Path -LiteralPath $rootCandidate).Path.TrimEnd([char[]]'\/')
Assert-NoReparseChain $rootPath
Assert-ExactExistingPathCase $rootPath
Assert-ProjectMode -RepositoryRoot $rootPath

$analysisRoot = Join-Path $rootPath 'analysis'
$runsRoot = Join-Path $analysisRoot 'runs'
foreach ($requiredDirectory in @($analysisRoot, $runsRoot)) {
    if (-not (Test-Path -LiteralPath $requiredDirectory -PathType Container)) {
        throw 'Generated project не содержит обязательный analysis/runs path.'
    }
    if (-not (Test-PathInsideRoot -CandidatePath $requiredDirectory -ControlledRoot $rootPath)) {
        throw 'Analysis path вышел за корень generated project.'
    }
    Assert-NoReparseChain $requiredDirectory
    Assert-ExactExistingPathCase $requiredDirectory
}

$publishedPath = $null
for ($attempt = 1; $attempt -le $maximumCollisionAttempts; $attempt++) {
    Assert-NoReparseChain $runsRoot
    $createdAt = [System.DateTimeOffset]::UtcNow
    $createdAtText = $createdAt.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $runId = 'RUN-{0}-{1}-{2}-{3}' -f `
        $createdAt.ToString('yyyyMMdd'), `
        $createdAt.ToString('HHmmss'), `
        $Slug, `
        (Get-CryptoHexSuffix)
    if (Test-RunNameCollision -RunsRoot $runsRoot -RunId $runId) {
        continue
    }

    $finalPath = Join-Path $runsRoot $runId
    $stagingLeaf = '.analysis-run-staging-{0}' -f [guid]::NewGuid().ToString('N')
    $stagingPath = Join-Path $runsRoot $stagingLeaf
    if (Test-Path -LiteralPath $stagingPath) {
        throw 'Не удалось получить уникальный staging path.'
    }

    $stagingCreated = $false
    $stagingMoved = $false
    $retryCollision = $false
    try {
        $escapedStagingPath = [System.Management.Automation.WildcardPattern]::Escape($stagingPath)
        New-Item -ItemType Directory -Path $escapedStagingPath -ErrorAction Stop | Out-Null
        $stagingCreated = $true
        Assert-NoReparseChain $stagingPath
        Assert-ExactExistingPathCase $stagingPath

        foreach ($fileName in $runFiles) {
            $rendered = [string]$templates[$fileName]
            $rendered = $rendered.Replace('{{RUN_ID}}', $runId)
            $rendered = $rendered.Replace('{{RUN_TITLE}}', $Title)
            $rendered = $rendered.Replace('{{TASK_REF}}', $TaskRef)
            $rendered = $rendered.Replace('{{CREATED_AT}}', $createdAtText)
            if ($rendered -match '\{\{[A-Z][A-Z0-9_]*\}\}') {
                throw "После rendering остался placeholder: $fileName"
            }
            if ($strictUtf8.GetByteCount($rendered) -gt $renderedFileMaxBytes) {
                throw "Rendered run file превышает byte limit: $fileName"
            }

            $frontMatter = Read-SimpleFrontMatterFromText -Text $rendered -Label $fileName
            $expectedCommonFrontMatter = [ordered]@{
                run_id = $runId
                run_asset = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                run_status = 'open'
                title = $Title
                task_ref = $TaskRef
                created_at = $createdAtText
            }
            foreach ($field in $expectedCommonFrontMatter.Keys) {
                if (-not $frontMatter.ContainsKey($field) -or
                    [string]$frontMatter[$field] -cne [string]$expectedCommonFrontMatter[$field]) {
                    throw "Rendered common frontmatter не совпадает с запросом: ${fileName}:$field"
                }
            }

            $targetFile = Join-Path $stagingPath $fileName
            Write-NewUtf8File -LiteralPath $targetFile -Content $rendered
        }

        Assert-ExactFlatInventory -DirectoryPath $stagingPath -ExpectedFiles $runFiles -Label 'rendered analysis run'
        Assert-NoReparseChain $runsRoot
        Assert-NoReparseChain $stagingPath
        if (Test-RunNameCollision -RunsRoot $runsRoot -RunId $runId) {
            $retryCollision = $true
        }
        else {
            try {
                [System.IO.Directory]::Move($stagingPath, $finalPath)
                $stagingMoved = $true
                $publishedPath = $finalPath
            }
            catch [System.IO.IOException] {
                if (Test-RunNameCollision -RunsRoot $runsRoot -RunId $runId) {
                    $retryCollision = $true
                }
                else {
                    throw
                }
            }
        }
    }
    finally {
        if ($stagingCreated -and -not $stagingMoved -and (Test-Path -LiteralPath $stagingPath)) {
            Remove-ExactOwnedStagingDirectory `
                -StagingDirectory $stagingPath `
                -ExpectedParent $runsRoot `
                -ExpectedLeaf $stagingLeaf
        }
    }

    if ($stagingMoved) {
        break
    }
    if (-not $retryCollision) {
        throw 'Analysis run не был опубликован.'
    }
}

if ([string]::IsNullOrWhiteSpace($publishedPath)) {
    throw 'blocked: analysis-run-id-exhausted'
}

Assert-NoReparseChain $publishedPath
Assert-ExactExistingPathCase $publishedPath
Assert-ExactFlatInventory -DirectoryPath $publishedPath -ExpectedFiles $runFiles -Label 'published analysis run'
Write-Host "Analysis run создан атомарно: $publishedPath"
