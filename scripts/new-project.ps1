[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Destination,

    [ValidateNotNullOrEmpty()]
    [string]$ProjectName = 'Аналитический проект',

    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string]$ProjectSlug = 'analyst-workspace',

    [ValidateNotNullOrEmpty()]
    [string]$Description = 'Рабочее пространство для системного и бизнес-анализа.',

    [ValidateNotNullOrEmpty()]
    [string]$Owner = 'project-owner'
)

$ErrorActionPreference = 'Stop'
$manifestMaxBytes = 1MB
$descriptorMaxBytes = 8MB
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
$platformModulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Platform.psm1'
Import-Module $platformModulePath -Force
$nullDevice = Get-ModelProjectNullDevice

Assert-ModelProjectInputText -Value $Destination -Field Destination -MaxLength 1024
Assert-ModelProjectInputText -Value $ProjectName -Field ProjectName -MaxLength 120 -Pattern '^[\p{L}\p{N}][\p{L}\p{N} .,:;!?()_+&/\-]{0,119}$'
Assert-ModelProjectInputText -Value $ProjectSlug -Field ProjectSlug -MaxLength 63 -Pattern '^[a-z0-9][a-z0-9-]*$'
Assert-ModelProjectInputText -Value $Description -Field Description -MaxLength 500 -Pattern '^[\p{L}\p{N}][\p{L}\p{N} .,:;!?()_+&%/''"\-]{0,499}$'
Assert-ModelProjectInputText -Value $Owner -Field Owner -MaxLength 80 -Pattern '^[\p{L}\p{N}][\p{L}\p{N} ._+\-]{0,79}$'

function Assert-ManifestRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        $RelativePath.Contains('\') -or
        $RelativePath.StartsWith('/') -or
        $RelativePath.EndsWith('/') -or
        $RelativePath -match '^[A-Za-z]:' -or
        $RelativePath.IndexOfAny([char[]]'*?[]:<>|"') -ge 0) {
        throw ".template-manifest.json $FieldName содержит небезопасный путь: $RelativePath"
    }
    foreach ($segment in ($RelativePath -split '/')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.' -or $segment -eq '..' -or
            $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|CLOCK\$|CONIN\$|CONOUT\$|COM[1-9]|LPT[1-9])(?:\..*)?$') {
            throw ".template-manifest.json $FieldName содержит небезопасный Windows path segment: $RelativePath"
        }
    }
}

function Assert-UniquePaths {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Paths,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    $seen = @{}
    foreach ($relativePath in $Paths) {
        Assert-ManifestRelativePath -RelativePath $relativePath -FieldName $FieldName
        $key = $relativePath.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            throw ".template-manifest.json $FieldName содержит дубликат: $relativePath"
        }
        $seen[$key] = $true
    }
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

function Assert-LocalDestination {
    param([Parameter(Mandatory = $true)][string]$RawDestination)

    if ($RawDestination.StartsWith('\\') -or $RawDestination.StartsWith('//')) {
        throw 'UNC, device и protocol-relative destination запрещены.'
    }
    $full = [System.IO.Path]::GetFullPath($RawDestination)
    $pathRoot = [System.IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($pathRoot) -or $pathRoot.StartsWith('\\') -or $pathRoot.StartsWith('//')) {
        throw 'Destination должен находиться на локальном файловом диске.'
    }

    try {
        $driveInfo = [System.IO.DriveInfo]::new($pathRoot)
        if ($driveInfo.DriveType -eq [System.IO.DriveType]::Network) {
            throw 'Destination на сетевом диске запрещен.'
        }
    }
    catch [System.ArgumentException] {
        throw "Не удалось определить локальный диск destination: $pathRoot"
    }

    if (Test-ModelProjectIsWindows) {
        $driveName = $pathRoot.TrimEnd([char[]]'\/').TrimEnd(':')
        $psDrive = Get-PSDrive -Name $driveName -PSProvider FileSystem -ErrorAction SilentlyContinue
        if ($null -ne $psDrive -and -not [string]::IsNullOrWhiteSpace([string]$psDrive.DisplayRoot) -and
            ([string]$psDrive.DisplayRoot).StartsWith('\\')) {
            throw 'Destination на mapped network drive запрещен.'
        }
    }
}

function Copy-PortableFile {
    param(
        [Parameter(Mandatory = $true)][string]$RelativeFile,
        [Parameter(Mandatory = $true)][string]$TargetRoot
    )

    $source = Join-Path $sourceRoot $RelativeFile
    $target = Join-Path $TargetRoot $RelativeFile
    $targetParent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
        New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
    }
    Assert-NoReparseChain $source
    Assert-NoReparseChain $targetParent
    Copy-Item -LiteralPath $source -Destination $target
    Assert-NoReparseChain $target
}

function Assert-PortableDestination {
    param(
        [Parameter(Mandatory = $true)][string]$BaseRoot,
        [Parameter(Mandatory = $true)][string[]]$PortableFiles,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$PortableEmptyDirectories
    )

    $actualFiles = @(Get-ChildItem -LiteralPath $BaseRoot -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($BaseRoot.Length + 1).Replace('\', '/')
    })
    $missingFiles = @($PortableFiles | Where-Object { $actualFiles -cnotcontains $_ })
    $extraFiles = @($actualFiles | Where-Object { $PortableFiles -cnotcontains $_ })
    if ($missingFiles.Count -gt 0 -or $extraFiles.Count -gt 0) {
        throw "Копия не совпадает с portable_files. Missing: $($missingFiles -join ', '); extra: $($extraFiles -join ', ')"
    }
    foreach ($relativeDirectory in $PortableEmptyDirectories) {
        $absoluteDirectory = Join-Path $BaseRoot $relativeDirectory
        if (-not (Test-Path -LiteralPath $absoluteDirectory -PathType Container)) {
            throw "Копия не содержит portable empty directory: $relativeDirectory"
        }
        if (@(Get-ChildItem -LiteralPath $absoluteDirectory -Force).Count -ne 0) {
            throw "Portable empty directory неожиданно заполнен до инициализации: $relativeDirectory"
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
            if ($isDirectory) {
                [System.IO.Directory]::Delete($entry, $false)
            }
            else {
                [System.IO.File]::Delete($entry)
            }
        }
        elseif ($isDirectory) {
            Remove-DirectoryTreeWithoutFollowingReparse $entry
        }
        else {
            [System.IO.File]::SetAttributes($entry, [System.IO.FileAttributes]::Normal)
            [System.IO.File]::Delete($entry)
        }
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
    $actualParent = [System.IO.Path]::GetDirectoryName($fullStaging)
    $leaf = [System.IO.Path]::GetFileName($fullStaging)
    $comparison = Get-ModelProjectPathComparison -Path $fullParent
    if (-not $actualParent.Equals($fullParent, $comparison) -or
        $leaf -notmatch '^\.codex-new-project-[0-9a-f]{32}$') {
        throw "Отказ от cleanup неожиданного staging path: $fullStaging"
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
$manifestPath = Join-Path $sourceRoot '.template-manifest.json'
$descriptorPath = Join-Path $sourceRoot 'TEMPLATE-DISTRIBUTION.json'

Assert-LocalDestination $Destination
$destinationPath = [System.IO.Path]::GetFullPath($Destination).TrimEnd([char[]]'\/')
if (Test-ModelProjectPathWithinRoot -Root $sourceRoot -Path $destinationPath -AllowEqual) {
    throw 'Новый проект нельзя создавать внутри исходного шаблона.'
}
if (Test-Path -LiteralPath $destinationPath) {
    throw "Целевая папка уже существует: $destinationPath"
}

$parent = Split-Path -Parent $destinationPath
if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
    throw "Родительская папка не существует: $parent"
}
Assert-NoReparseChain $parent
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw '.template-manifest.json не найден.'
}
Assert-NoReparseChain $manifestPath
if (-not (Test-Path -LiteralPath $descriptorPath -PathType Leaf)) {
    throw 'TEMPLATE-DISTRIBUTION.json не найден.'
}
Assert-NoReparseChain $descriptorPath

$manifestText = Read-BoundedUtf8File -LiteralPath $manifestPath -MaxBytes $manifestMaxBytes -Label '.template-manifest.json'
try {
    $manifest = $manifestText | ConvertFrom-Json
}
catch {
    throw '.template-manifest.json содержит невалидный JSON; parser details скрыты.'
}

$descriptorText = Read-BoundedUtf8File `
    -LiteralPath $descriptorPath `
    -MaxBytes $descriptorMaxBytes `
    -Label 'TEMPLATE-DISTRIBUTION.json'
try {
    $descriptor = $descriptorText | ConvertFrom-Json
}
catch {
    throw 'TEMPLATE-DISTRIBUTION.json содержит невалидный JSON; parser details скрыты.'
}
if ($descriptor.PSObject.Properties.Name -cnotcontains 'distribution_kind' -or
    $descriptor.distribution_kind -isnot [string]) {
    throw 'TEMPLATE-DISTRIBUTION.json не содержит строковый distribution_kind.'
}
$sourceVerifyMode = if ([string]$descriptor.distribution_kind -ceq 'source-placeholder') {
    'TemplateSource'
}
elseif ([string]$descriptor.distribution_kind -ceq 'github-template') {
    'DistributionTemplate'
}
else {
    throw 'new-project.ps1 принимает только source-placeholder или github-template source.'
}

$requiredProperties = @(
    'schema_version',
    'template_version',
    'portable_files',
    'portable_empty_directories',
    'initialization_renames',
    'source_only_paths',
    'generated_forbidden_paths',
    'generated_extension_zones',
    'mastery_baseline'
)
foreach ($propertyName in $requiredProperties) {
    if ($manifest.PSObject.Properties.Name -cnotcontains $propertyName) {
        throw ".template-manifest.json: отсутствует поле $propertyName"
    }
}
if ([int]$manifest.schema_version -ne 1) {
    throw "Неподдерживаемая schema_version: $($manifest.schema_version)"
}
$semVerPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(?:(?:0|[1-9][0-9]*)|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:(?:0|[1-9][0-9]*)|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$'
if ($manifest.template_version -isnot [string] -or
    $manifest.template_version.Length -gt 128 -or
    $manifest.template_version -cnotmatch $semVerPattern) {
    throw '.template-manifest.json template_version должен быть SemVer scalar длиной не более 128 символов.'
}

$portableFiles = @($manifest.portable_files | ForEach-Object { [string]$_ })
$portableEmptyDirectories = @($manifest.portable_empty_directories | ForEach-Object { [string]$_ })
$initializationRenames = @($manifest.initialization_renames)
$sourceOnlyPaths = @($manifest.source_only_paths | ForEach-Object { [string]$_ })
$generatedForbiddenPaths = @($manifest.generated_forbidden_paths | ForEach-Object { [string]$_ })
$generatedExtensionZones = @($manifest.generated_extension_zones | ForEach-Object { [string]$_ })

Assert-UniquePaths -Paths $portableFiles -FieldName 'portable_files'
Assert-UniquePaths -Paths $portableEmptyDirectories -FieldName 'portable_empty_directories'
Assert-UniquePaths -Paths $sourceOnlyPaths -FieldName 'source_only_paths'
Assert-UniquePaths -Paths $generatedForbiddenPaths -FieldName 'generated_forbidden_paths'
Assert-UniquePaths -Paths $generatedExtensionZones -FieldName 'generated_extension_zones'

if ($portableFiles -cnotcontains '.template-manifest.json') {
    throw 'portable_files должен включать .template-manifest.json.'
}
$renameFromPaths = [System.Collections.Generic.List[string]]::new()
$renameToPaths = [System.Collections.Generic.List[string]]::new()
foreach ($rename in $initializationRenames) {
    if ($null -eq $rename -or
        $rename.PSObject.Properties.Name -cnotcontains 'from' -or
        $rename.PSObject.Properties.Name -cnotcontains 'to') {
        throw 'initialization_renames: каждая запись должна содержать from и to.'
    }
    $from = [string]$rename.from
    $to = [string]$rename.to
    Assert-ManifestRelativePath -RelativePath $from -FieldName 'initialization_renames.from'
    Assert-ManifestRelativePath -RelativePath $to -FieldName 'initialization_renames.to'
    if ($portableFiles -cnotcontains $from) {
        throw "initialization_renames.from отсутствует в portable_files: $from"
    }
    if ($portableFiles -ccontains $to -or $sourceOnlyPaths -ccontains $to) {
        throw "initialization_renames.to конфликтует с manifest inventory: $to"
    }
    if ($generatedForbiddenPaths -cnotcontains $from -or $generatedForbiddenPaths -ccontains $to) {
        throw "initialization_renames не согласован с generated_forbidden_paths: $from -> $to"
    }
    $renameFromPaths.Add($from)
    $renameToPaths.Add($to)
}
Assert-UniquePaths -Paths $renameFromPaths.ToArray() -FieldName 'initialization_renames.from'
Assert-UniquePaths -Paths $renameToPaths.ToArray() -FieldName 'initialization_renames.to'
foreach ($sourceOnlyPath in $sourceOnlyPaths) {
    if ($portableFiles -ccontains $sourceOnlyPath) {
        throw "Путь одновременно portable и source-only: $sourceOnlyPath"
    }
}

foreach ($relativeFile in $portableFiles) {
    $source = Join-Path $sourceRoot $relativeFile
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Отсутствует portable file: $relativeFile"
    }
    Assert-NoReparseChain $source
}
foreach ($relativeDirectory in $portableEmptyDirectories) {
    $sourceDirectory = Join-Path $sourceRoot $relativeDirectory
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        throw "Отсутствует portable empty directory: $relativeDirectory"
    }
    Assert-NoReparseChain $sourceDirectory
    if (@(Get-ChildItem -LiteralPath $sourceDirectory -Force).Count -ne 0) {
        throw "Portable empty directory должен быть пустым в шаблоне: $relativeDirectory"
    }
}

$verifier = Join-Path $PSScriptRoot 'verify-structure.ps1'
if (-not (Test-Path -LiteralPath $verifier -PathType Leaf)) {
    throw 'Доверенный verify-structure.ps1 не найден.'
}
Assert-NoReparseChain $verifier
$powershellExe = Get-TrustedCurrentPowerShellHost -ControlledRoots @($sourceRoot, $destinationPath)
# Fail-fast: initialize-project.ps1 понадобится Git после копирования. Разрешаем
# executable до создания staging, затем initializer повторно валидирует его сам.
$null = Get-TrustedGitExecutable -ControlledRoots @($sourceRoot, $destinationPath)
$sourceVerifyResult = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifier,
    '-Root', $sourceRoot, '-Mode', $sourceVerifyMode
)
foreach ($line in $sourceVerifyResult.Output) { Write-Host ([string]$line) }
if ($sourceVerifyResult.ExitCode -ne 0) {
    throw "Исходный шаблон не прошел проверку $sourceVerifyMode. Копирование остановлено до создания staging."
}

do {
    $stagingLeaf = ".codex-new-project-$([guid]::NewGuid().ToString('N'))"
    $stagingPath = Join-Path $parent $stagingLeaf
} while (Test-Path -LiteralPath $stagingPath)

$stagingMoved = $false
try {
    New-Item -ItemType Directory -Path $stagingPath | Out-Null
    Assert-NoReparseChain $stagingPath

    foreach ($relativeFile in $portableFiles) {
        Copy-PortableFile -RelativeFile $relativeFile -TargetRoot $stagingPath
    }
    foreach ($relativeDirectory in $portableEmptyDirectories) {
        $stagingDirectory = Join-Path $stagingPath $relativeDirectory
        if (-not (Test-Path -LiteralPath $stagingDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
        }
        Assert-NoReparseChain $stagingDirectory
    }
    Assert-PortableDestination -BaseRoot $stagingPath -PortableFiles $portableFiles -PortableEmptyDirectories $portableEmptyDirectories

    if (Test-Path -LiteralPath (Join-Path $stagingPath '.git')) {
        throw 'Staging неожиданно получил .git исходного шаблона.'
    }
    foreach ($forbiddenPath in $generatedForbiddenPaths) {
        if ($renameFromPaths -ccontains $forbiddenPath) { continue }
        if (Test-Path -LiteralPath (Join-Path $stagingPath $forbiddenPath)) {
            throw "Staging неожиданно получил generated forbidden path: $forbiddenPath"
        }
    }

    $initializer = Join-Path $stagingPath 'scripts/initialize-project.ps1'
    if (-not (Test-Path -LiteralPath $initializer -PathType Leaf)) {
        throw "Staging создан, но инициализатор не найден: $initializer"
    }
    Assert-NoReparseChain $initializer
    $initializeResult = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $initializer,
        '-ProjectName', $ProjectName,
        '-ProjectSlug', $ProjectSlug,
        '-Description', $Description,
        '-Owner', $Owner,
        '-InitializeGit'
    )
    foreach ($line in $initializeResult.Output) { Write-Host ([string]$line) }
    if ($initializeResult.ExitCode -ne 0) {
        throw 'Staging initializer завершился с ошибкой.'
    }

    $generatedVerifyResult = Invoke-SanitizedProcess -Executable $powershellExe -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifier,
        '-Root', $stagingPath, '-Mode', 'GeneratedProject'
    )
    foreach ($line in $generatedVerifyResult.Output) { Write-Host ([string]$line) }
    if ($generatedVerifyResult.ExitCode -ne 0) {
        throw 'Staging не прошел доверенную проверку GeneratedProject.'
    }

    Assert-NoReparseChain $parent
    Assert-NoReparseChain $stagingPath
    if (Test-Path -LiteralPath $destinationPath) {
        throw "Final destination появился во время сборки: $destinationPath"
    }
    [System.IO.Directory]::Move($stagingPath, $destinationPath)
    $stagingMoved = $true
}
catch {
    $originalFailure = $_
    if (-not $stagingMoved) {
        try {
            Remove-ExactStagingDirectory -StagingDirectory $stagingPath -ExpectedParent $parent
        }
        catch {
            throw "Создание проекта завершилось ошибкой: $($originalFailure.Exception.Message). Дополнительно не удалось безопасно очистить staging: $($_.Exception.Message)"
        }
    }
    throw $originalFailure
}

Write-Host "Новый проект создан атомарным rename: $destinationPath"
