[CmdletBinding()]
param(
    [string]$Root = '',

    [ValidateSet('Auto', 'TemplateSource', 'DistributionTemplate', 'GeneratedProject')]
    [string]$Mode = 'Auto'
)

trap {
    try {
        [Console]::Error.WriteLine(
            'FAIL [structure]: проверка заблокирована (internal-validation-error); repository data скрыты.'
        )
        if ($VerbosePreference -ceq 'Continue') {
            [Console]::Error.WriteLine("DETAIL [structure]: $([string]$_.Exception.Message)")
        }
    }
    catch {
    }
    exit 1
}

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

function Get-EarlyReparsePoint {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    $pathRoot = [System.IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($pathRoot)) { return $null }
    $current = $pathRoot
    if (Test-Path -LiteralPath $current) {
        $rootItem = Get-Item -LiteralPath $current -Force
        if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $current
        }
    }
    $relative = $full.Substring($pathRoot.Length)
    foreach ($segment in (($relative -split '[\\/]') | Where-Object { $_ -ne '' })) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { break }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $current
        }
    }
    return $null
}

function Test-EarlyExactPathCase {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)
    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    if (-not (Test-Path -LiteralPath $full)) { return $false }
    $parent = [System.IO.Path]::GetDirectoryName($full); $leaf = [System.IO.Path]::GetFileName($full)
    $matches = @([System.IO.Directory]::EnumerateFileSystemEntries($parent) | Where-Object { [System.IO.Path]::GetFileName($_).Equals($leaf, [System.StringComparison]::OrdinalIgnoreCase) })
    return ($matches.Count -eq 1 -and [System.IO.Path]::GetFileName($matches[0]) -ceq $leaf)
}

$trustedStructureScriptsRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char[]]'\/')
$trustedPlatformModulePath = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($trustedStructureScriptsRoot, 'lib', 'ModelProject.Platform.psm1')
)
if (-not (Test-Path -LiteralPath $trustedPlatformModulePath -PathType Leaf) -or
    $null -ne (Get-EarlyReparsePoint $trustedPlatformModulePath) -or
    -not (Test-EarlyExactPathCase $trustedPlatformModulePath)) {
    throw 'Trusted platform helper module failed bootstrap integrity check.'
}
$trustedPlatformModule = Import-Module -Name $trustedPlatformModulePath -Scope Local -Force -PassThru -ErrorAction Stop
$trustedPlatformExportNames = @(
    'Get-ModelProjectNormalizedFullPath', 'Test-ModelProjectIsWindows', 'Test-ModelProjectIsMacOS',
    'Get-ModelProjectNullDevice', 'Get-ModelProjectPathComparison', 'Test-ModelProjectPathWithinRoot',
    'Get-ModelProjectLinkInFullChain', 'Assert-ModelProjectNoLinkInFullChain',
    'Get-ModelProjectTrustedApplication', 'Get-ModelProjectGitExecutable', 'Get-ModelProjectPowerShellHost',
    'Set-ModelProjectSanitizedGitEnvironment', 'Invoke-ModelProjectProcess', 'Assert-ModelProjectInputText',
    'Enter-ModelProjectFileLock', 'Exit-ModelProjectFileLock'
)
if ($null -eq $trustedPlatformModule -or $trustedPlatformModule.ExportedCommands.Count -ne $trustedPlatformExportNames.Count) {
    throw 'Trusted platform helper module export set mismatch.'
}
$trustedPlatformCommands = @{}
foreach ($commandName in $trustedPlatformExportNames) {
    $command = $trustedPlatformModule.ExportedCommands[$commandName]
    if ($null -eq $command -or $command.CommandType -ne [System.Management.Automation.CommandTypes]::Function -or
        $null -eq $command.Module -or
        -not [System.IO.Path]::GetFullPath([string]$command.Module.Path).Equals($trustedPlatformModulePath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Trusted platform helper module export origin mismatch.'
    }
    $trustedPlatformCommands[$commandName] = $command
}
$script:mppGetGitExecutable = $trustedPlatformCommands['Get-ModelProjectGitExecutable']
$script:mppGetPowerShellHost = $trustedPlatformCommands['Get-ModelProjectPowerShellHost']
$script:mppGetNullDevice = $trustedPlatformCommands['Get-ModelProjectNullDevice']
$script:mppSetGitEnvironment = $trustedPlatformCommands['Set-ModelProjectSanitizedGitEnvironment']
$script:mppInvokeProcess = $trustedPlatformCommands['Invoke-ModelProjectProcess']
$script:mppGetPathComparison = $trustedPlatformCommands['Get-ModelProjectPathComparison']
$script:nullDevice = & $script:mppGetNullDevice

$trustedStructureModulePath = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($trustedStructureScriptsRoot, 'lib', 'ModelProject.Knowledge.psm1')
)
if (-not (Test-Path -LiteralPath $trustedStructureModulePath -PathType Leaf) -or
    $null -ne (Get-EarlyReparsePoint $trustedStructureModulePath) -or
    -not (Test-EarlyExactPathCase $trustedStructureModulePath) -or
    -not (Test-EarlyExactPathCase ([System.IO.Path]::GetDirectoryName($trustedStructureModulePath)))) {
    throw 'Trusted structure helper module failed bootstrap integrity check.'
}
$trustedStructureModule = Import-Module -Name $trustedStructureModulePath -Scope Local -Force -PassThru -ErrorAction Stop
$trustedStructureExportNames = @(
    'Test-ModelProjectFrontMatterScalarValue', 'Test-ModelProjectJsonScalar',
    'ConvertFrom-ModelProjectSimpleYamlScalar', 'Read-ModelProjectSimpleFrontMatterDocument',
    'ConvertTo-ModelProjectPercentDecodedText', 'Get-ModelProjectHttpsUrlSafetyFinding',
    'Get-ModelProjectHttpsUrlsFromText', 'Get-ModelProjectSensitiveTextFindings',
    'Remove-ModelProjectCommonMarkContainerPrefixes', 'Test-ModelProjectMarkdownEscaped',
    'Get-ModelProjectMarkdownLinkOpenerIndex', 'Test-ModelProjectInlineMarkdownClosure',
    'Test-ModelProjectPathWithinRoot', 'Get-ModelProjectReparsePointInFullChain',
    'Get-ModelProjectRepositoryRelativePath', 'Test-ModelProjectExactPathCase',
    'Read-ModelProjectBoundedUtf8File', 'ConvertTo-ModelProjectMarkdownAnchor',
    'Test-ModelProjectMarkdownAnchorExists', 'Resolve-ModelProjectSafeReference'
)
if ($null -eq $trustedStructureModule -or $trustedStructureModule.ExportedCommands.Count -ne $trustedStructureExportNames.Count) { throw 'Trusted structure helper module export set mismatch.' }
$trustedStructureCommands = @{}
foreach ($commandName in $trustedStructureExportNames) {
    $command = $trustedStructureModule.ExportedCommands[$commandName]
    if ($null -eq $command -or $command.CommandType -ne [System.Management.Automation.CommandTypes]::Function -or
        $null -eq $command.Module -or -not [System.IO.Path]::GetFullPath([string]$command.Module.Path).Equals($trustedStructureModulePath, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Trusted structure helper module export origin mismatch.' }
    $trustedStructureCommands[$commandName] = $command
}
$script:mpsTestPathWithinRoot = $trustedStructureCommands['Test-ModelProjectPathWithinRoot']
$script:mpsGetReparsePointInFullChain = $trustedStructureCommands['Get-ModelProjectReparsePointInFullChain']
$script:mpsTestExactPathCase = $trustedStructureCommands['Test-ModelProjectExactPathCase']
$script:mpsReadBoundedUtf8File = $trustedStructureCommands['Read-ModelProjectBoundedUtf8File']
$script:mpsConvertMarkdownAnchor = $trustedStructureCommands['ConvertTo-ModelProjectMarkdownAnchor']

$resourceLimits = [ordered]@{
    ProjectBytes = 512KB
    ManifestBytes = 1MB
    DescriptorBytes = 8MB
    MarkdownBytes = 2MB
    CanonicalMarkdownFiles = 2000
    CanonicalCorpusBytes = 32MB
    TrackedFiles = 100000
}
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Convert-ToSafeStructureDiagnostic {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $sensitivePatterns = @(
        '(?i)(?:(?<![A-Za-z0-9])[A-Z]:[\\/]|(?<![A-Za-z0-9])file:/{0,2}|\\\\[A-Za-z0-9_.-]+[\\/]|(?:^|[\s(\x27\x22])/(?:Users|home|tmp|var/tmp)/)',
        '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
        '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
        '(?i)\bBearer\s+[A-Za-z0-9._~+/-]{12,}=*',
        '(?:\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9]{20,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b|\bxox[a-z]-[A-Za-z0-9-]{10,}\b|\bAIza[0-9A-Za-z_-]{35}\b|\b(?:sk|rk)_(?:live|test)_[0-9A-Za-z]{16,}\b|\bsk-[A-Za-z0-9_-]{20,}\b)',
        '\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b',
        '(?i)\b(?:password|passwd|secret|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*[\x22\x27]?[A-Za-z0-9._~+/-]{8,}',
        '(?i)(?:\?|&)(?:[^\s#&=]+)=([^\s#&]*)'
    )
    foreach ($pattern in $sensitivePatterns) {
        if ($Text -match $pattern) {
            return 'Диагностика скрыта: небезопасное значение repository data.'
        }
    }
    return $Text
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

    $reparseBeforeMetadata = Get-EarlyReparsePoint $absolutePath
    if ($null -ne $reparseBeforeMetadata) {
        throw "Файл проходит через reparse point до чтения: ${Label}: $reparseBeforeMetadata"
    }

    $item = Get-Item -LiteralPath $absolutePath -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Файл является reparse point: ${Label}: $absolutePath"
    }
    if ([long]$item.Length -gt $MaxBytes) {
        throw "Файл превышает лимит $MaxBytes байт: ${Label}: $($item.Length)"
    }

    # Повторная проверка непосредственно перед открытием уменьшает окно подмены
    # дочернего пути. Само чтение дополнительно ограничено MaxBytes.
    $reparseBeforeRead = Get-EarlyReparsePoint $absolutePath
    if ($null -ne $reparseBeforeRead) {
        throw "Файл проходит через reparse point непосредственно перед чтением: ${Label}: $reparseBeforeRead"
    }

    try {
        $text = & $script:mpsReadBoundedUtf8File -Root $rootPath -Path $absolutePath -MaxBytes $MaxBytes
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

    if ($MaxBytes -le 0) {
        throw "Некорректный лимит хеширования для ${Label}: $MaxBytes"
    }

    $absolutePath = [System.IO.Path]::GetFullPath($LiteralPath)
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        throw "Файл для хеширования не найден: ${Label}: $absolutePath"
    }

    $reparseBeforeMetadata = Get-EarlyReparsePoint $absolutePath
    if ($null -ne $reparseBeforeMetadata) {
        throw "Файл проходит через reparse point до хеширования: ${Label}: $reparseBeforeMetadata"
    }

    $item = Get-Item -LiteralPath $absolutePath -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Файл для хеширования является reparse point: ${Label}: $absolutePath"
    }
    if ([long]$item.Length -gt $MaxBytes) {
        throw "Файл превышает лимит хеширования $MaxBytes байт: ${Label}: $($item.Length)"
    }

    $reparseBeforeRead = Get-EarlyReparsePoint $absolutePath
    if ($null -ne $reparseBeforeRead) {
        throw "Файл проходит через reparse point непосредственно перед хешированием: ${Label}: $reparseBeforeRead"
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
            throw "Файл превышает лимит хеширования $MaxBytes байт после открытия: ${Label}: $($stream.Length)"
        }

        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $buffer = New-Object byte[] 65536
        [long]$totalRead = 0
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $totalRead += $read
            if ($totalRead -gt $MaxBytes) {
                throw "Файл превысил лимит хеширования $MaxBytes байт во время чтения: $Label"
            }
            [void]$sha256.TransformBlock($buffer, 0, $read, $buffer, 0)
        }
        [void]$sha256.TransformFinalBlock([byte[]]@(), 0, 0)
        return ([System.BitConverter]::ToString($sha256.Hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha256) { $sha256.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

$rootCandidate = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
$earlyRootReparse = Get-EarlyReparsePoint $rootCandidate
if ($null -ne $earlyRootReparse) {
    throw "Root проходит через reparse point до чтения данных: $earlyRootReparse"
}

$rootPath = (Resolve-Path -LiteralPath $rootCandidate).Path.TrimEnd([char[]]'\/')
$issues = [System.Collections.Generic.List[string]]::new()
$projectPath = Join-Path $rootPath 'PROJECT.md'
$manifestPath = Join-Path $rootPath '.template-manifest.json'

if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
    throw 'PROJECT.md не найден, режим проверки определить нельзя.'
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw '.template-manifest.json не найден, portable contract определить нельзя.'
}
$projectText = Read-BoundedUtf8File -LiteralPath $projectPath -MaxBytes $resourceLimits.ProjectBytes -Label 'PROJECT.md'
$manifestText = Read-BoundedUtf8File -LiteralPath $manifestPath -MaxBytes $resourceLimits.ManifestBytes -Label '.template-manifest.json'
try {
    $manifest = $manifestText | ConvertFrom-Json
}
catch {
    throw '.template-manifest.json содержит невалидный JSON; parser details скрыты.'
}

$requiredManifestProperties = @(
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
foreach ($propertyName in $requiredManifestProperties) {
    if ($manifest.PSObject.Properties.Name -cnotcontains $propertyName) {
        throw ".template-manifest.json: отсутствует поле $propertyName"
    }
}
if ($manifest.mastery_baseline.PSObject.Properties.Name -cnotcontains 'bundle_version' -or
    $manifest.mastery_baseline.PSObject.Properties.Name -cnotcontains 'files') {
    throw '.template-manifest.json: mastery_baseline должен содержать bundle_version и files.'
}

function Test-ManifestRelativePath {
    param([AllowEmptyString()][string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $false }
    if ($RelativePath.Contains('\') -or $RelativePath.StartsWith('/') -or
        $RelativePath.EndsWith('/') -or $RelativePath -match '^[A-Za-z]:' -or
        $RelativePath.IndexOfAny([char[]]'*?[]:<>|"') -ge 0) {
        return $false
    }
    foreach ($segment in ($RelativePath -split '/')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq '.' -or $segment -eq '..') {
            return $false
        }
        if ($segment.EndsWith('.') -or $segment.EndsWith(' ')) {
            return $false
        }
        if ($segment -match '^(?i:CON|PRN|AUX|NUL|CLOCK\$|CONIN\$|CONOUT\$|COM[1-9]|LPT[1-9])(?:\..*)?$') {
            return $false
        }
    }
    return $true
}

$portableFiles = @($manifest.portable_files | ForEach-Object { [string]$_ })
$portableEmptyDirectories = @($manifest.portable_empty_directories | ForEach-Object { [string]$_ })
$initializationRenames = @($manifest.initialization_renames)
$sourceOnlyPaths = @($manifest.source_only_paths | ForEach-Object { [string]$_ })
$generatedForbiddenPaths = @($manifest.generated_forbidden_paths | ForEach-Object { [string]$_ })
$generatedExtensionZones = @($manifest.generated_extension_zones | ForEach-Object { [string]$_ })
$masteryBaselineFiles = @($manifest.mastery_baseline.files)

$initializationRenameFrom = [System.Collections.Generic.List[string]]::new()
$initializationRenameTo = [System.Collections.Generic.List[string]]::new()
foreach ($rename in $initializationRenames) {
    if ($null -eq $rename -or
        $rename.PSObject.Properties.Name -cnotcontains 'from' -or
        $rename.PSObject.Properties.Name -cnotcontains 'to') {
        throw 'Manifest initialization_renames: каждая запись должна содержать from и to.'
    }
    $initializationRenameFrom.Add([string]$rename.from)
    $initializationRenameTo.Add([string]$rename.to)
}

$earlyManifestPathLists = @(
    @{ Name = 'portable_files'; Values = $portableFiles },
    @{ Name = 'portable_empty_directories'; Values = $portableEmptyDirectories },
    @{ Name = 'initialization_renames.from'; Values = $initializationRenameFrom.ToArray() },
    @{ Name = 'initialization_renames.to'; Values = $initializationRenameTo.ToArray() },
    @{ Name = 'source_only_paths'; Values = $sourceOnlyPaths },
    @{ Name = 'generated_forbidden_paths'; Values = $generatedForbiddenPaths },
    @{ Name = 'generated_extension_zones'; Values = $generatedExtensionZones }
)
foreach ($pathList in $earlyManifestPathLists) {
    foreach ($relativePath in $pathList.Values) {
        if (-not (Test-ManifestRelativePath $relativePath)) {
            throw "Manifest $($pathList.Name): небезопасный или неканонический путь до файловых операций: $relativePath"
        }
    }
}

function Get-ProjectScalar {
    param([Parameter(Mandatory = $true)][string]$Name)

    $match = [regex]::Match($projectText, "(?m)^$([regex]::Escape($Name)):\s*(?<value>[^\r\n]*)\s*$")
    if (-not $match.Success) { return '' }
    return $match.Groups['value'].Value.Trim().Trim('"').Trim("'")
}

$repositoryKind = Get-ProjectScalar 'repository_kind'
$effectiveMode = if ($Mode -eq 'Auto') {
    if ($repositoryKind -ceq 'template-source') {
        'TemplateSource'
    }
    elseif ($repositoryKind -ceq 'generated-project') {
        'GeneratedProject'
    }
    elseif ($repositoryKind -ceq 'distribution-template') {
        'DistributionTemplate'
    }
    elseif ($projectText.Contains('{{PROJECT_NAME}}')) {
        'TemplateSource'
    }
    else {
        'GeneratedProject'
    }
}
else {
    $Mode
}

$generatedPortableFiles = @($portableFiles | Where-Object { $initializationRenameFrom -cnotcontains $_ })
$generatedPortableFiles += $initializationRenameTo.ToArray()
$commonRequiredLeaves = if ($effectiveMode -eq 'GeneratedProject') {
    @($generatedPortableFiles)
}
else {
    @($portableFiles)
}
if ($effectiveMode -eq 'TemplateSource') {
    $commonRequiredLeaves += $sourceOnlyPaths
}

$requiredContainers = [System.Collections.Generic.List[string]]::new()
foreach ($relativePath in ($commonRequiredLeaves + $portableEmptyDirectories)) {
    $parentPath = [System.IO.Path]::GetDirectoryName($relativePath)
    while (-not [string]::IsNullOrWhiteSpace($parentPath)) {
        $normalizedParent = $parentPath.Replace('\', '/')
        if ($requiredContainers -cnotcontains $normalizedParent) {
            $requiredContainers.Add($normalizedParent)
        }
        $parentPath = [System.IO.Path]::GetDirectoryName($parentPath)
    }
}

function Get-RelativePath {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    if (-not (& $script:mpsTestPathWithinRoot -Root $rootPath -Path $full)) {
        return $null
    }
    $relative = [System.IO.Path]::GetRelativePath($rootPath, $full)
    if ($relative -ceq '.') { return '' }
    return $relative.Replace('\', '/')
}

function Test-PathWithinRoot {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    return (& $script:mpsTestPathWithinRoot -Root $rootPath -Path $AbsolutePath)
}

function Get-ReparsePointInPath {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    try { return (& $script:mpsGetReparsePointInFullChain -Root $rootPath -Path $AbsolutePath) } catch { return $null }
}

function Test-ExactPathCase {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    return (& $script:mpsTestExactPathCase -Root $rootPath -Path $AbsolutePath)
}

function Get-LineNumber {
    param([string]$Text, [int]$Index)
    if ($Index -le 0) { return 1 }
    return ([regex]::Matches($Text.Substring(0, $Index), "`n").Count + 1)
}

function Convert-ToAnchor {
    param([string]$Heading)

    return (& $script:mpsConvertMarkdownAnchor -Heading $Heading)
}

function Get-TrustedGitExecutable {
    try { return (& $script:mppGetGitExecutable -ControlledRoots @($rootPath)) }
    catch { return $null }
}

function Get-TrustedCurrentPowerShellHost {
    try { return (& $script:mppGetPowerShellHost -ControlledRoots @($rootPath)) }
    catch { return $null }
}

function Read-StrictSmallControlFileNoBom {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf) -or
        $null -ne (Get-EarlyReparsePoint $LiteralPath)) {
        return $null
    }
    try {
        $item = Get-Item -LiteralPath $LiteralPath -Force
        if ($item.Length -lt 1 -or $item.Length -gt 4096) { return $null }
        $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
        $text = $strictUtf8.GetString($bytes)
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { return $null }
        return $text
    }
    catch {
        return $null
    }
}

function Test-TrustedGitMetadataMarker {
    $gitMetadataPath = Join-Path $rootPath '.git'
    if (-not (Test-ExactPathCase $gitMetadataPath) -or
        $null -ne (Get-EarlyReparsePoint $gitMetadataPath)) {
        return $false
    }
    if (Test-Path -LiteralPath $gitMetadataPath -PathType Container) {
        return $true
    }
    if (-not (Test-Path -LiteralPath $gitMetadataPath -PathType Leaf)) {
        return $false
    }

    try {
        $markerText = Read-StrictSmallControlFileNoBom -LiteralPath $gitMetadataPath
        if ($null -eq $markerText) { return $false }
        $markerMatch = [regex]::Match($markerText, '\Agitdir:[ \t]+(?<path>[^\r\n]+)\r?\n?\z')
        if (-not $markerMatch.Success) { return $false }
        $gitDirectoryValue = $markerMatch.Groups['path'].Value
        if ([string]::IsNullOrWhiteSpace($gitDirectoryValue) -or
            $gitDirectoryValue -cne $gitDirectoryValue.Trim()) {
            return $false
        }
        $gitDirectoryPath = if ([System.IO.Path]::IsPathRooted($gitDirectoryValue)) {
            [System.IO.Path]::GetFullPath($gitDirectoryValue)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $rootPath $gitDirectoryValue))
        }
        if (-not (Test-Path -LiteralPath $gitDirectoryPath -PathType Container) -or
            $null -ne (Get-EarlyReparsePoint $gitDirectoryPath)) {
            return $false
        }

        # Standard linked worktree admin directories contain a `gitdir`
        # backlink to the worktree's .git marker. It prevents an unrelated
        # external directory from being accepted as repository metadata.
        $backlinkPath = Join-Path $gitDirectoryPath 'gitdir'
        $backlinkText = Read-StrictSmallControlFileNoBom -LiteralPath $backlinkPath
        if ($null -eq $backlinkText) { return $false }
        $backlinkMatch = [regex]::Match($backlinkText, '\A(?<path>[^\r\n]+)\r?\n?\z')
        if (-not $backlinkMatch.Success) { return $false }
        $backlinkValue = $backlinkMatch.Groups['path'].Value
        if ([string]::IsNullOrWhiteSpace($backlinkValue) -or $backlinkValue -cne $backlinkValue.Trim()) {
            return $false
        }
        $backlinkTarget = if ([System.IO.Path]::IsPathRooted($backlinkValue)) {
            [System.IO.Path]::GetFullPath($backlinkValue)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $gitDirectoryPath $backlinkValue))
        }
        $comparison = & $script:mppGetPathComparison -Path $gitMetadataPath
        return (
            $backlinkTarget.Equals([System.IO.Path]::GetFullPath($gitMetadataPath), $comparison) -and
            (Test-Path -LiteralPath $backlinkTarget -PathType Leaf) -and
            $null -eq (Get-EarlyReparsePoint $backlinkTarget)
        )
    }
    catch {
        return $false
    }
}

function Invoke-SanitizedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $isGit = [System.IO.Path]::GetFileName($Executable) -cin @('git', 'git.exe')
    $result = & $script:mppInvokeProcess -Executable $Executable -Arguments $Arguments -GitEnvironment:$isGit
    if ($result.LimitExceeded) { throw 'Дочерний процесс превысил лимит вывода.' }
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Output = @($result.Output) }
}

function Invoke-BoundedGitLsFiles {
    param([Parameter(Mandatory = $true)][string]$GitExecutable)

    $tracked = [System.Collections.Generic.List[string]]::new()
    $failed = $false
    $overflow = $false
    $arguments = @(
        '-c', "safe.directory=$rootPath",
        '-c', 'core.fsmonitor=false',
        '-c', "core.hooksPath=$script:nullDevice",
        '-c', 'core.quotePath=false',
        '-C', $rootPath,
        'ls-files'
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GitExecutable
    foreach ($argument in $arguments) { [void]$startInfo.ArgumentList.Add([string]$argument) }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $utf8NoBom
    $startInfo.StandardErrorEncoding = $utf8NoBom
    $null = $startInfo.EnvironmentVariables
    $environment = $startInfo.Environment
    if ($null -eq $environment) {
        return [pscustomobject]@{ Failed = $true; Overflow = $false; Paths = @() }
    }
    & $script:mppSetGitEnvironment -Environment $environment

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            $failed = $true
        }
        else {
            $stderrTask = $process.StandardError.ReadToEndAsync()
            while (($line = $process.StandardOutput.ReadLine()) -ne $null) {
                if ($tracked.Count -ge $resourceLimits.TrackedFiles) {
                    $overflow = $true
                    try { $process.Kill() } catch { }
                    break
                }
                $tracked.Add([string]$line) | Out-Null
            }
            $process.WaitForExit()
            $null = $stderrTask.Result
            if ($process.ExitCode -ne 0 -and -not $overflow) { $failed = $true }
        }
    }
    catch {
        $failed = $true
    }
    finally {
        $process.Dispose()
    }
    return [pscustomobject]@{ Failed = $failed; Overflow = $overflow; Paths = @($tracked) }
}

$fileAnchorCache = @{}

function Get-FileAnchors {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $absolutePath = [System.IO.Path]::GetFullPath($FilePath)
    if ($fileAnchorCache.ContainsKey($absolutePath)) {
        return ,@($fileAnchorCache[$absolutePath])
    }

    $seen = @{}
    $anchors = [System.Collections.Generic.List[string]]::new()
    $anchorContent = Read-BoundedUtf8File -LiteralPath $absolutePath -MaxBytes $resourceLimits.MarkdownBytes -Label (Get-RelativePath $absolutePath)
    foreach ($line in ($anchorContent -split '\r?\n')) {
        if ($line -notmatch '^#{1,6}\s+(.+?)\s*#*\s*$') { continue }
        $base = Convert-ToAnchor $Matches[1]
        $count = if ($seen.ContainsKey($base)) { [int]$seen[$base] } else { 0 }
        $anchor = if ($count -eq 0) { $base } else { "$base-$count" }
        $seen[$base] = $count + 1
        $anchors.Add($anchor)
    }
    $fileAnchorCache[$absolutePath] = @($anchors)
    return ,@($anchors)
}

function Test-Anchor {
    param([string]$FilePath, [string]$Anchor)

    if ([string]::IsNullOrWhiteSpace($Anchor)) { return $true }
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { return $false }
    if ([System.IO.Path]::GetExtension($FilePath) -ine '.md') { return $false }
    try {
        $wanted = Convert-ToAnchor ([System.Uri]::UnescapeDataString($Anchor))
    }
    catch {
        return $false
    }
    return (Get-FileAnchors $FilePath) -ccontains $wanted
}

function Get-TreeMarkdown {
    param([string]$RelativeDirectory)

    $directory = Join-Path $rootPath $RelativeDirectory
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return @() }
    $directoryReparse = Get-ReparsePointInPath $directory
    if ($null -ne $directoryReparse) {
        throw "Generated extension zone проходит через reparse point до сканирования: $RelativeDirectory"
    }
    return @(Get-ChildItem -LiteralPath $directory -Recurse -File -Filter '*.md' -Force | ForEach-Object FullName)
}

function Test-IsDeclaredPath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)][string[]]$DeclaredFiles,
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)][string[]]$DeclaredDirectories
    )

    if ($DeclaredFiles -ccontains $RelativePath -or $DeclaredDirectories -ccontains $RelativePath) {
        return $true
    }
    $prefix = $RelativePath.TrimEnd('/') + '/'
    if (@($DeclaredFiles | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::Ordinal) }).Count -gt 0) {
        return $true
    }
    if (@($DeclaredDirectories | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::Ordinal) }).Count -gt 0) {
        return $true
    }
    return $false
}

function Test-IsUnderDeclaredPath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string[]]$DeclaredRoots
    )

    foreach ($declaredRoot in $DeclaredRoots) {
        if ($RelativePath -ceq $declaredRoot -or
            $RelativePath.StartsWith($declaredRoot.TrimEnd('/') + '/', [System.StringComparison]::Ordinal)) {
            return $true
        }
    }
    return $false
}

function Test-IsTemplateLinkAllowed {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)][string]$TargetFile
    )

    $sourceRelative = Get-RelativePath $SourceFile
    $targetRelative = Get-RelativePath $TargetFile
    if ($null -eq $sourceRelative -or $null -eq $targetRelative) { return $false }
    if ($effectiveMode -ceq 'TemplateSource' -and $sourceRelative -ceq 'plans/INDEX.md' -and
        $sourceOnlyPaths -ccontains $targetRelative) {
        return $true
    }
    if ($portableFiles -ccontains $sourceRelative) {
        return Test-IsDeclaredPath -RelativePath $targetRelative -DeclaredFiles $portableFiles -DeclaredDirectories $portableEmptyDirectories
    }
    return Test-IsDeclaredPath -RelativePath $targetRelative -DeclaredFiles ($portableFiles + $sourceOnlyPaths) -DeclaredDirectories $portableEmptyDirectories
}

function Test-IsLegacyRetiredHistoryReference {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)][string]$TargetFile
    )

    if ($effectiveMode -cne 'TemplateSource') { return $false }
    $sourceRelative = Get-RelativePath $SourceFile
    $targetRelative = Get-RelativePath $TargetFile
    if ($null -eq $sourceRelative -or $null -eq $targetRelative -or
        $sourceOnlyPaths -cnotcontains $sourceRelative -or
        $sourceRelative -cnotmatch '^(?:docs/decisions|plans|retrospectives)/2026-[^/]+\.md$') {
        return $false
    }
    return $targetRelative -cin @(
        'analysis/CONTRACT.md',
        'mastery/analyst/INDEX.md',
        'scripts/verify-analysis.ps1'
    )
}

function Test-IsTemplateOverlayPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    return $false
}

function Test-HasRequiredFrontmatterField {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    return [regex]::IsMatch($Content, "(?m)^$([regex]::Escape($FieldName)):\s*(?!\s*$).+$")
}

function Test-MasteryLocalRegistry {
    $localRoot = [System.IO.Path]::Combine($rootPath, 'mastery', 'local')
    $indexPath = Join-Path $localRoot 'INDEX.md'
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) { return }

    $indexContent = Read-BoundedUtf8File -LiteralPath $indexPath -MaxBytes $resourceLimits.MarkdownBytes -Label 'mastery/local/INDEX.md'
    $registered = [System.Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($indexContent, '\[[^\]]+\]\((?<target>[^)]+)\)')) {
        $target = $match.Groups['target'].Value.Trim().Trim('<').Trim('>')
        if ($target -match '^(?i:[a-z][a-z0-9+.-]*):' -or $target.StartsWith('//') -or $target.StartsWith('#')) {
            continue
        }
        $targetPath = ($target -split '#', 2)[0]
        try {
            $targetPath = [System.Uri]::UnescapeDataString($targetPath)
            $absoluteTarget = [System.IO.Path]::GetFullPath((Join-Path $localRoot $targetPath))
        }
        catch {
            continue
        }
        if (& $script:mpsTestPathWithinRoot -Root $localRoot -Path $absoluteTarget) {
            $relativeTarget = $absoluteTarget.Substring($rootPath.Length + 1).Replace('\', '/')
            if ($relativeTarget -cne 'mastery/local/INDEX.md' -and
                $relativeTarget -cne 'mastery/local/TEMPLATE.md' -and
                $registered -cnotcontains $relativeTarget) {
                $registered.Add($relativeTarget)
            }
        }
    }

    $extensionFiles = @(Get-ChildItem -LiteralPath $localRoot -Recurse -File -Force | Where-Object {
        $_.FullName -cne $indexPath -and $_.Name -cne 'TEMPLATE.md'
    })
    foreach ($extensionFile in $extensionFiles) {
        $relativeExtension = Get-RelativePath $extensionFile.FullName
        if ($extensionFile.Extension -cne '.md') {
            $issues.Add("mastery/local: допустимы только Markdown-расширения: $relativeExtension")
            continue
        }
        if ($registered -cnotcontains $relativeExtension) {
            $issues.Add("mastery/local: файл не зарегистрирован в INDEX.md: $relativeExtension")
        }
        $extensionContent = Read-BoundedUtf8File -LiteralPath $extensionFile.FullName -MaxBytes $resourceLimits.MarkdownBytes -Label $relativeExtension
        if (-not (Test-HasRequiredFrontmatterField -Content $extensionContent -FieldName 'review_due')) {
            $issues.Add("mastery/local: отсутствует review_due: $relativeExtension")
        }
        if (-not (Test-HasRequiredFrontmatterField -Content $extensionContent -FieldName 'verified_at')) {
            $issues.Add("mastery/local: отсутствует verified_at: $relativeExtension")
        }
        if (-not (Test-HasRequiredFrontmatterField -Content $extensionContent -FieldName 'source_refs') -and
            -not (Test-HasRequiredFrontmatterField -Content $extensionContent -FieldName 'sources')) {
            $issues.Add("mastery/local: отсутствуют source_refs или sources: $relativeExtension")
        }
    }
    foreach ($registeredFile in $registered) {
        if (-not (Test-Path -LiteralPath (Join-Path $rootPath $registeredFile) -PathType Leaf)) {
            $issues.Add("mastery/local: зарегистрирован отсутствующий файл: $registeredFile")
        }
    }
}

if ([int]$manifest.schema_version -ne 1) {
    $issues.Add("Неподдерживаемая schema_version manifest: $($manifest.schema_version)")
}
$semVerPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(?:(?:0|[1-9][0-9]*)|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:(?:0|[1-9][0-9]*)|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$'
if ($manifest.template_version -isnot [string] -or
    $manifest.template_version.Length -gt 128 -or
    $manifest.template_version -cnotmatch $semVerPattern) {
    $issues.Add('Manifest template_version должен быть SemVer scalar длиной не более 128 символов.')
}

$manifestPathLists = @(
    @{ Name = 'portable_files'; Values = $portableFiles },
    @{ Name = 'portable_empty_directories'; Values = $portableEmptyDirectories },
    @{ Name = 'source_only_paths'; Values = $sourceOnlyPaths },
    @{ Name = 'generated_forbidden_paths'; Values = $generatedForbiddenPaths },
    @{ Name = 'generated_extension_zones'; Values = $generatedExtensionZones }
)
foreach ($pathList in $manifestPathLists) {
    $seenPaths = @{}
    foreach ($relativePath in $pathList.Values) {
        if (-not (Test-ManifestRelativePath $relativePath)) {
            $issues.Add("Manifest $($pathList.Name): небезопасный или неканонический путь: $relativePath")
            continue
        }
        $caseKey = $relativePath.ToLowerInvariant()
        if ($seenPaths.ContainsKey($caseKey)) {
            $issues.Add("Manifest $($pathList.Name): дублирующийся путь: $relativePath")
        }
        else {
            $seenPaths[$caseKey] = $true
        }
    }
}
if ($portableFiles -cnotcontains '.template-manifest.json') {
    $issues.Add('Manifest должен включать .template-manifest.json в portable_files.')
}
foreach ($sourceOnlyPath in $sourceOnlyPaths) {
    if ($portableFiles -ccontains $sourceOnlyPath) {
        $issues.Add("Manifest: путь одновременно portable и source-only: $sourceOnlyPath")
    }
}
$expectedInitializationRenames = @(
    'LICENSE->TEMPLATE-LICENSE.md',
    'THIRD-PARTY-NOTICES.md->TEMPLATE-THIRD-PARTY-NOTICES.md'
)
$actualInitializationRenames = @($initializationRenames | ForEach-Object {
    '{0}->{1}' -f [string]$_.from, [string]$_.to
} | Sort-Object)
if ($actualInitializationRenames.Count -ne $expectedInitializationRenames.Count -or
    (Compare-Object -ReferenceObject ($expectedInitializationRenames | Sort-Object) -DifferenceObject $actualInitializationRenames).Count -ne 0) {
    $issues.Add('Manifest initialization_renames не соответствует template license boundary.')
}
foreach ($rename in $initializationRenames) {
    $from = [string]$rename.from
    $to = [string]$rename.to
    if ($portableFiles -cnotcontains $from) {
        $issues.Add("Manifest initialization_renames.from отсутствует в portable_files: $from")
    }
    if ($portableFiles -ccontains $to -or $sourceOnlyPaths -ccontains $to) {
        $issues.Add("Manifest initialization_renames.to конфликтует с declared inventory: $to")
    }
    if ($generatedForbiddenPaths -cnotcontains $from -or $generatedForbiddenPaths -ccontains $to) {
        $issues.Add("Manifest initialization_renames не согласован с generated_forbidden_paths: $from -> $to")
    }
}

$baselineSeen = @{}
foreach ($baselineEntry in $masteryBaselineFiles) {
    if ($baselineEntry.PSObject.Properties.Name -cnotcontains 'path' -or
        $baselineEntry.PSObject.Properties.Name -cnotcontains 'sha256') {
        $issues.Add('Manifest mastery_baseline.files: каждая запись должна иметь path и sha256.')
        continue
    }
    $baselinePath = [string]$baselineEntry.path
    $baselineHash = ([string]$baselineEntry.sha256).ToLowerInvariant()
    if (-not (Test-ManifestRelativePath $baselinePath) -or
        (-not $baselinePath.StartsWith('mastery/researcher/', [System.StringComparison]::Ordinal) -and
            -not $baselinePath.StartsWith('mastery/analyst/', [System.StringComparison]::Ordinal))) {
        $issues.Add("Manifest mastery baseline: недопустимый path: $baselinePath")
        continue
    }
    if ($baselineHash -notmatch '^[0-9a-f]{64}$') {
        $issues.Add("Manifest mastery baseline: невалидный SHA-256 для $baselinePath")
        continue
    }
    $baselineKey = $baselinePath.ToLowerInvariant()
    if ($baselineSeen.ContainsKey($baselineKey)) {
        $issues.Add("Manifest mastery baseline: дублирующийся path: $baselinePath")
        continue
    }
    $baselineSeen[$baselineKey] = $true
    if ($portableFiles -cnotcontains $baselinePath) {
        $issues.Add("Manifest mastery baseline отсутствует в portable_files: $baselinePath")
    }
    $baselineAbsolute = Join-Path $rootPath $baselinePath
    if (Test-Path -LiteralPath $baselineAbsolute -PathType Leaf) {
        $actualHash = Get-BoundedFileSha256 -LiteralPath $baselineAbsolute -MaxBytes $resourceLimits.MarkdownBytes -Label $baselinePath
        if ($actualHash -cne $baselineHash) {
            $issues.Add("Mastery baseline drift: $baselinePath")
        }
    }
}
$portableBaselineProfiles = @($portableFiles | Where-Object {
    ($_.StartsWith('mastery/researcher/', [System.StringComparison]::Ordinal) -or
        $_.StartsWith('mastery/analyst/', [System.StringComparison]::Ordinal)) -and $_ -like '*.md'
})
foreach ($profilePath in $portableBaselineProfiles) {
    if (-not $baselineSeen.ContainsKey($profilePath.ToLowerInvariant())) {
        $issues.Add("Manifest mastery baseline не содержит профиль: $profilePath")
    }
}
if ([string]::IsNullOrWhiteSpace([string]$manifest.mastery_baseline.bundle_version)) {
    $issues.Add('Manifest mastery_baseline.bundle_version не может быть пустым.')
}

foreach ($relative in $commonRequiredLeaves) {
    $absolute = Join-Path $rootPath $relative
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
        $issues.Add("Отсутствует обязательный файл: $relative")
    }
    elseif (-not (Test-ExactPathCase $absolute)) {
        $issues.Add("Неверный регистр обязательного файла: $relative")
    }
    else {
        $reparse = Get-ReparsePointInPath $absolute
        if ($null -ne $reparse) { $issues.Add("Reparse point в обязательном пути: $(Get-RelativePath $reparse)") }
    }
}

foreach ($relative in $requiredContainers) {
    $absolute = Join-Path $rootPath $relative
    if (-not (Test-Path -LiteralPath $absolute -PathType Container)) {
        $issues.Add("Отсутствует обязательный каталог: $relative")
    }
    elseif (-not (Test-ExactPathCase $absolute)) {
        $issues.Add("Неверный регистр обязательного каталога: $relative")
    }
    else {
        $reparse = Get-ReparsePointInPath $absolute
        if ($null -ne $reparse) { $issues.Add("Reparse point в обязательном пути: $(Get-RelativePath $reparse)") }
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

function Test-DistributionDescriptor {
    param([Parameter(Mandatory = $true)][string]$VerificationMode)

    $descriptorPath = Join-Path $rootPath 'TEMPLATE-DISTRIBUTION.json'
    if (-not (Test-Path -LiteralPath $descriptorPath -PathType Leaf)) { return $null }
    $descriptorText = Read-BoundedUtf8File `
        -LiteralPath $descriptorPath `
        -MaxBytes $resourceLimits.DescriptorBytes `
        -Label 'TEMPLATE-DISTRIBUTION.json'
    try { $descriptor = $descriptorText | ConvertFrom-Json }
    catch {
        $issues.Add('TEMPLATE-DISTRIBUTION.json содержит невалидный JSON.')
        return $null
    }
    $requiredProperties = @(
        'schema_version', 'distribution_kind', 'template_version', 'source_tag',
        'source_commit', 'template_repository_url', 'built_at', 'payload_sha256'
    )
    foreach ($propertyName in $requiredProperties) {
        if ($descriptor.PSObject.Properties.Name -cnotcontains $propertyName) {
            $issues.Add("TEMPLATE-DISTRIBUTION.json: отсутствует поле $propertyName")
        }
    }
    if ([int]$descriptor.schema_version -ne 1) {
        $issues.Add('TEMPLATE-DISTRIBUTION.json: schema_version должен быть 1.')
    }
    if ([string]$descriptor.template_version -cne [string]$manifest.template_version) {
        $issues.Add('TEMPLATE-DISTRIBUTION.json: template_version не совпадает с manifest.')
    }

    $kind = [string]$descriptor.distribution_kind
    if ($VerificationMode -ceq 'TemplateSource') {
        if ($kind -cne 'source-placeholder' -or $null -ne $descriptor.source_tag -or
            $null -ne $descriptor.source_commit -or $null -ne $descriptor.template_repository_url -or
            $null -ne $descriptor.built_at -or @($descriptor.payload_sha256).Count -ne 0) {
            $issues.Add('TemplateSource: descriptor должен оставаться пустым source-placeholder.')
        }
        return $descriptor
    }

    if ($VerificationMode -ceq 'DistributionTemplate' -and $kind -cne 'github-template') {
        $issues.Add('DistributionTemplate: distribution_kind должен быть github-template.')
    }
    if ($VerificationMode -ceq 'GeneratedProject' -and $kind -cnotin @('github-template', 'local-copy')) {
        $issues.Add('GeneratedProject: неизвестный distribution_kind.')
    }

    if ($kind -ceq 'github-template') {
        if ([string]$descriptor.source_tag -cne "v$([string]$manifest.template_version)" -or
            [string]$descriptor.source_commit -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' -or
            [string]$descriptor.template_repository_url -cnotmatch '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?$') {
            $issues.Add('GitHub descriptor содержит некорректный tag, commit или repository URL.')
        }
    }
    elseif ($kind -ceq 'local-copy') {
        if ($null -ne $descriptor.source_tag -or $null -ne $descriptor.source_commit -or
            $null -ne $descriptor.template_repository_url) {
            $issues.Add('Local-copy descriptor не должен содержать source Git identity.')
        }
    }
    $builtAt = [datetimeoffset]::MinValue
    $builtAtValid = $descriptor.built_at -is [datetime] -or
        $descriptor.built_at -is [datetimeoffset] -or
        [datetimeoffset]::TryParse([string]$descriptor.built_at, [ref]$builtAt)
    if ($kind -cin @('github-template', 'local-copy') -and -not $builtAtValid) {
        $issues.Add('Distribution descriptor содержит некорректный built_at.')
    }

    $expectedPaths = @($portableFiles | Where-Object { $_ -cne 'TEMPLATE-DISTRIBUTION.json' } | Sort-Object)
    $entries = @($descriptor.payload_sha256)
    if ($kind -cin @('github-template', 'local-copy')) {
        if ($entries.Count -ne $expectedPaths.Count) {
            $issues.Add('Distribution descriptor содержит неполный payload inventory.')
        }
        $seen = @{}
        $actualOrder = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $entries) {
            if ($null -eq $entry -or
                $entry.PSObject.Properties.Name -cnotcontains 'path' -or
                $entry.PSObject.Properties.Name -cnotcontains 'sha256') {
                $issues.Add('Distribution descriptor содержит некорректную hash entry.')
                continue
            }
            $relativePath = [string]$entry.path
            $hash = ([string]$entry.sha256).ToLowerInvariant()
            $actualOrder.Add($relativePath)
            if (-not (Test-ManifestRelativePath $relativePath) -or
                $expectedPaths -cnotcontains $relativePath -or
                $hash -notmatch '^[0-9a-f]{64}$' -or
                $seen.ContainsKey($relativePath.ToLowerInvariant())) {
                $issues.Add('Distribution descriptor содержит небезопасную или дублирующуюся hash entry.')
                continue
            }
            $seen[$relativePath.ToLowerInvariant()] = $true
            if ($VerificationMode -ceq 'DistributionTemplate') {
                $absolutePath = Join-Path $rootPath $relativePath
                if (Test-Path -LiteralPath $absolutePath -PathType Leaf) {
                    $actualHash = Get-BoundedFileSha256 `
                        -LiteralPath $absolutePath `
                        -MaxBytes $resourceLimits.DescriptorBytes `
                        -Label $relativePath
                    if ($actualHash -cne $hash) {
                        $issues.Add("Distribution payload drift: $relativePath")
                    }
                }
            }
        }
        if ($actualOrder.Count -eq $expectedPaths.Count) {
            for ($index = 0; $index -lt $expectedPaths.Count; $index++) {
                if ($actualOrder[$index] -cne $expectedPaths[$index]) {
                    $issues.Add('Distribution descriptor payload_sha256 должен быть отсортирован по path.')
                    break
                }
            }
        }
        foreach ($expectedPath in $expectedPaths) {
            if (-not $seen.ContainsKey($expectedPath.ToLowerInvariant())) {
                $issues.Add("Distribution descriptor не покрывает path: $expectedPath")
            }
        }
    }
    return $descriptor
}

$placeholders = @('{{PROJECT_NAME}}', '{{PROJECT_SLUG}}', '{{PROJECT_DESCRIPTION}}', '{{OWNER}}')
$projectStatus = Get-ProjectScalar 'project_status'
$projectId = Get-ProjectScalar 'project_id'
$knowledgeContractVersion = Get-ProjectScalar 'knowledge_contract_version'
$knowledgeCaptureMode = Get-ProjectScalar 'knowledge_capture_mode'
$distributionDescriptor = Test-DistributionDescriptor -VerificationMode $effectiveMode

if ($knowledgeContractVersion -cne '1') {
    $issues.Add("PROJECT.md: неподдерживаемая knowledge_contract_version: $knowledgeContractVersion")
}

if ($effectiveMode -eq 'TemplateSource') {
    foreach ($placeholder in $placeholders) {
        if (-not $projectText.Contains($placeholder)) { $issues.Add("TemplateSource: отсутствует placeholder $placeholder") }
    }
    if ($repositoryKind -cne 'template-source') { $issues.Add('TemplateSource: repository_kind должен быть template-source.') }
    if ($projectStatus -cne 'template') { $issues.Add('TemplateSource: project_status должен быть template.') }
    if ($knowledgeCaptureMode -cne 'disabled') { $issues.Add('TemplateSource: knowledge_capture_mode должен быть disabled.') }
    if ($projectId -cne '{{PROJECT_SLUG}}') { $issues.Add('TemplateSource: project_id должен содержать {{PROJECT_SLUG}}.') }
    if (Test-Path -LiteralPath (Join-Path $rootPath 'TEMPLATE-ORIGIN.md')) { $issues.Add('TemplateSource: TEMPLATE-ORIGIN.md допустим только в созданном проекте.') }
    foreach ($targetPath in $initializationRenameTo) {
        if (Test-Path -LiteralPath (Join-Path $rootPath $targetPath)) {
            $issues.Add("TemplateSource: initialization target допустим только в generated project: $targetPath")
        }
    }
}
elseif ($effectiveMode -eq 'DistributionTemplate') {
    foreach ($placeholder in $placeholders) {
        if (-not $projectText.Contains($placeholder)) { $issues.Add("DistributionTemplate: отсутствует placeholder $placeholder") }
    }
    if ($repositoryKind -cne 'distribution-template') { $issues.Add('DistributionTemplate: repository_kind должен быть distribution-template.') }
    if ($projectStatus -cne 'template') { $issues.Add('DistributionTemplate: project_status должен быть template.') }
    if ($knowledgeCaptureMode -cne 'disabled') { $issues.Add('DistributionTemplate: knowledge_capture_mode должен быть disabled.') }
    if ($projectId -cne '{{PROJECT_SLUG}}') { $issues.Add('DistributionTemplate: project_id должен содержать {{PROJECT_SLUG}}.') }
    if (Test-Path -LiteralPath (Join-Path $rootPath 'TEMPLATE-ORIGIN.md')) { $issues.Add('DistributionTemplate: TEMPLATE-ORIGIN.md допустим только после setup.') }
    foreach ($targetPath in $initializationRenameTo) {
        if (Test-Path -LiteralPath (Join-Path $rootPath $targetPath)) {
            $issues.Add("DistributionTemplate: initialization target допустим только после setup: $targetPath")
        }
    }
    foreach ($sourceOnlyPath in $sourceOnlyPaths) {
        if (Test-Path -LiteralPath (Join-Path $rootPath $sourceOnlyPath)) {
            $issues.Add("DistributionTemplate: source-only manifest-путь существует: $sourceOnlyPath")
        }
    }
}
else {
    foreach ($placeholder in $placeholders) {
        if ($projectText.Contains($placeholder)) { $issues.Add("GeneratedProject: остался placeholder $placeholder") }
    }
    if ($repositoryKind -cne 'generated-project') { $issues.Add('GeneratedProject: repository_kind должен быть generated-project.') }
    if ($projectStatus -cnotin @('initialized', 'active', 'archived')) {
        $issues.Add("GeneratedProject: недопустимый project_status: $projectStatus")
    }
    elseif ($projectStatus -ceq 'initialized' -and $knowledgeCaptureMode -cne 'report-only') {
        $issues.Add('GeneratedProject initialized: knowledge_capture_mode должен быть report-only.')
    }
    elseif ($projectStatus -ceq 'active' -and $knowledgeCaptureMode -cnotin @('safe-local', 'report-only')) {
        $issues.Add('GeneratedProject active: knowledge_capture_mode должен быть safe-local или report-only.')
    }
    elseif ($projectStatus -ceq 'archived' -and $knowledgeCaptureMode -cne 'disabled') {
        $issues.Add('GeneratedProject archived: knowledge_capture_mode должен быть disabled.')
    }
    if ($projectId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$') {
        $issues.Add('GeneratedProject: project_id должен быть уникальным UUID.')
    }
    $originPath = Join-Path $rootPath 'TEMPLATE-ORIGIN.md'
    if (-not (Test-Path -LiteralPath $originPath -PathType Leaf)) {
        $issues.Add('GeneratedProject: отсутствует TEMPLATE-ORIGIN.md.')
    }
    elseif (-not (Test-ExactPathCase $originPath)) {
        $issues.Add('GeneratedProject: неверный регистр TEMPLATE-ORIGIN.md.')
    }
    elseif ($null -ne $distributionDescriptor) {
        $originText = Read-BoundedUtf8File -LiteralPath $originPath -MaxBytes $resourceLimits.MarkdownBytes -Label 'TEMPLATE-ORIGIN.md'
        $descriptorHash = Get-BoundedFileSha256 `
            -LiteralPath (Join-Path $rootPath 'TEMPLATE-DISTRIBUTION.json') `
            -MaxBytes $resourceLimits.DescriptorBytes `
            -Label 'TEMPLATE-DISTRIBUTION.json'
        if ($originText -cnotmatch "(?m)^- SHA-256 дескриптора: $([regex]::Escape($descriptorHash))\s*$") {
            $issues.Add('GeneratedProject: TEMPLATE-ORIGIN.md не соответствует descriptor digest.')
        }
        if ($originText -cnotmatch "(?m)^- Project ID: $([regex]::Escape($projectId))\s*$") {
            $issues.Add('GeneratedProject: TEMPLATE-ORIGIN.md не соответствует project_id.')
        }
    }
    foreach ($forbiddenPath in $generatedForbiddenPaths) {
        $forbiddenAbsolute = Join-Path $rootPath $forbiddenPath
        if (Test-Path -LiteralPath $forbiddenAbsolute) {
            $issues.Add("GeneratedProject: запрещенный manifest-путь существует: $forbiddenPath")
        }
    }
    foreach ($sourceOnlyPath in $sourceOnlyPaths) {
        $sourceOnlyAbsolute = Join-Path $rootPath $sourceOnlyPath
        if (Test-Path -LiteralPath $sourceOnlyAbsolute) {
            $issues.Add("GeneratedProject: source-only manifest-путь существует: $sourceOnlyPath")
        }
    }
}

$trackedPaths = @{}
if ($effectiveMode -eq 'TemplateSource' -and (Test-Path -LiteralPath (Join-Path $rootPath '.git'))) {
    $trustedToolRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path.TrimEnd([char[]]'\/')
    $comparison = & $script:mppGetPathComparison -Path $trustedToolRoot
    if (-not $rootPath.Equals($trustedToolRoot, $comparison)) {
        $issues.Add('TemplateSource: trusted verifier не запускает Git внутри произвольного -Root. Проверяй внешний template source его собственным доверенным verifier-ом.')
    }
    elseif (-not (Test-TrustedGitMetadataMarker)) {
        $issues.Add('TemplateSource: .git metadata marker не прошел integrity gate.')
    }
    else {
        $gitExecutable = Get-TrustedGitExecutable
        if ($null -eq $gitExecutable) {
            $issues.Add('TemplateSource: доверенный Git executable не найден.')
        }
        else {
            $trackedResult = Invoke-BoundedGitLsFiles -GitExecutable $gitExecutable
        }
        if ($null -eq $gitExecutable) {
            $issues.Add('TemplateSource: не удалось проверить tracked owner overlays через доверенный git ls-files.')
        }
        elseif ($trackedResult.Overflow) {
            $issues.Add("TemplateSource: git ls-files превысил лимит $($resourceLimits.TrackedFiles) путей.")
        }
        elseif ($trackedResult.Failed) {
            $issues.Add('TemplateSource: не удалось проверить tracked owner overlays через доверенный git ls-files.')
        }
        else {
            foreach ($trackedPath in $trackedResult.Paths) {
                $trackedPaths[$trackedPath.Replace('\', '/').ToLowerInvariant()] = $true
            }
        }
    }
}

$templateControlledRoots = @(
    ($portableFiles + $portableEmptyDirectories) |
        Where-Object { $_.Contains('/') } |
        ForEach-Object { ($_ -split '/', 2)[0] } |
        Sort-Object -Unique
)

foreach ($file in (Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force)) {
    $relativeFile = Get-RelativePath $file.FullName
    if ($relativeFile -ceq '.git' -or $relativeFile.StartsWith('.git/', [System.StringComparison]::Ordinal)) {
        continue
    }
    $isExactAllowed = if ($effectiveMode -eq 'GeneratedProject') {
        $generatedPortableFiles -ccontains $relativeFile
    }
    else {
        $portableFiles -ccontains $relativeFile
    }
    if ($effectiveMode -eq 'TemplateSource') {
        $isExactAllowed = $isExactAllowed -or $sourceOnlyPaths -ccontains $relativeFile
        if (-not $isExactAllowed -and (Test-IsTemplateOverlayPath $relativeFile)) {
            if ($trackedPaths.ContainsKey($relativeFile.ToLowerInvariant())) {
                $issues.Add("TemplateSource: Git отслеживает owner overlay вне manifest: $relativeFile")
            }
            continue
        }
        if (-not $isExactAllowed) {
            $issues.Add("TemplateSource: файл отсутствует в portable_files или source_only_paths: $relativeFile")
        }
    }
    elseif ($effectiveMode -eq 'DistributionTemplate') {
        if (-not $isExactAllowed) {
            $issues.Add("DistributionTemplate: файл отсутствует в portable_files: $relativeFile")
        }
    }
    else {
        $isExtension = Test-IsUnderDeclaredPath -RelativePath $relativeFile -DeclaredRoots $generatedExtensionZones
        $relativeParts = @($relativeFile -split '/', 2)
        $isInControlledRoot = $relativeParts.Count -gt 1 -and $templateControlledRoots -ccontains $relativeParts[0]
        if (-not $isExactAllowed -and $relativeFile -cne 'TEMPLATE-ORIGIN.md' -and
            $isInControlledRoot -and -not $isExtension) {
            $issues.Add("GeneratedProject: файл находится вне portable_files и extension zones: $relativeFile")
        }
    }
    if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        $issues.Add("Reparse point в файле: $relativeFile")
    }
}

$allowedTemplateDirectories = @($requiredContainers + $portableEmptyDirectories | Sort-Object -Unique)
foreach ($directory in (Get-ChildItem -LiteralPath $rootPath -Recurse -Directory -Force)) {
    $relativeDirectory = Get-RelativePath $directory.FullName
    if ($relativeDirectory -ceq '.git' -or $relativeDirectory.StartsWith('.git/', [System.StringComparison]::Ordinal)) {
        continue
    }
    if ($effectiveMode -eq 'TemplateSource' -and (Test-IsTemplateOverlayPath $relativeDirectory) -and
        -not (Test-IsDeclaredPath -RelativePath $relativeDirectory -DeclaredFiles @() -DeclaredDirectories $allowedTemplateDirectories)) {
        continue
    }
    $isAllowedDirectory = Test-IsDeclaredPath -RelativePath $relativeDirectory -DeclaredFiles @() -DeclaredDirectories $allowedTemplateDirectories
    if ($effectiveMode -eq 'GeneratedProject') {
        $directoryParts = @($relativeDirectory -split '/', 2)
        $isInControlledRoot = $directoryParts.Count -gt 1 -and $templateControlledRoots -ccontains $directoryParts[0]
        if (-not $isInControlledRoot) {
            $isAllowedDirectory = $true
        }
        else {
            $isAllowedDirectory = $isAllowedDirectory -or
                (Test-IsUnderDeclaredPath -RelativePath $relativeDirectory -DeclaredRoots $generatedExtensionZones) -or
                (Test-IsDeclaredPath -RelativePath $relativeDirectory -DeclaredFiles @() -DeclaredDirectories $generatedExtensionZones)
        }
    }
    if (-not $isAllowedDirectory) {
        $issues.Add("$effectiveMode`: недопустимый каталог вне manifest: $relativeDirectory")
    }
    if (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        $issues.Add("Reparse point в каталоге: $relativeDirectory")
    }
}

$canonicalMarkdown = @()
if ($effectiveMode -eq 'TemplateSource') {
    $canonicalMarkdown = @(($portableFiles + $sourceOnlyPaths) | Where-Object { $_ -like '*.md' } | ForEach-Object {
        Join-Path $rootPath $_
    })
}
elseif ($effectiveMode -eq 'DistributionTemplate') {
    $canonicalMarkdown = @($portableFiles | Where-Object { $_ -like '*.md' } | ForEach-Object {
        Join-Path $rootPath $_
    })
}
else {
    $canonicalMarkdown = @($generatedPortableFiles | Where-Object { $_ -like '*.md' } | ForEach-Object {
        Join-Path $rootPath $_
    })
    $canonicalMarkdown += Join-Path $rootPath 'TEMPLATE-ORIGIN.md'
    foreach ($extensionZone in $generatedExtensionZones) {
        $canonicalMarkdown += Get-TreeMarkdown $extensionZone
    }
}
$canonicalMarkdown = @($canonicalMarkdown | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Sort-Object -Unique)

if ($canonicalMarkdown.Count -gt $resourceLimits.CanonicalMarkdownFiles) {
    throw "Количество канонических Markdown-файлов превышает лимит $($resourceLimits.CanonicalMarkdownFiles): $($canonicalMarkdown.Count)"
}

[long]$canonicalCorpusBytes = 0
foreach ($canonicalPath in $canonicalMarkdown) {
    $canonicalReparse = Get-EarlyReparsePoint $canonicalPath
    if ($null -ne $canonicalReparse) {
        throw "Канонический Markdown проходит через reparse point до чтения: $canonicalReparse"
    }
    $canonicalItem = Get-Item -LiteralPath $canonicalPath -Force
    if ([long]$canonicalItem.Length -gt $resourceLimits.MarkdownBytes) {
        throw "Канонический Markdown превышает лимит $($resourceLimits.MarkdownBytes) байт: $(Get-RelativePath $canonicalPath): $($canonicalItem.Length)"
    }
    $canonicalCorpusBytes += [long]$canonicalItem.Length
    if ($canonicalCorpusBytes -gt $resourceLimits.CanonicalCorpusBytes) {
        throw "Общий объем канонического Markdown превышает лимит $($resourceLimits.CanonicalCorpusBytes) байт: $canonicalCorpusBytes"
    }
}

Test-MasteryLocalRegistry

function Resolve-Wikilink {
    param([string]$SourceFile, [string]$LinkPath)

    if ([string]::IsNullOrWhiteSpace($LinkPath)) { return @($SourceFile) }
    $hasDirectory = $LinkPath.Contains('/') -or $LinkPath.Contains('\')
    $candidate = $LinkPath.Replace('\', '/')
    if ($hasDirectory) {
        $base = Join-Path $rootPath $candidate
        if (-not [System.IO.Path]::HasExtension($base)) { $base += '.md' }
        return @($base)
    }

    $local = Join-Path (Split-Path -Parent $SourceFile) $candidate
    if (-not [System.IO.Path]::HasExtension($local)) { $local += '.md' }
    if (Test-Path -LiteralPath $local -PathType Leaf) { return @($local) }

    $name = if ([System.IO.Path]::HasExtension($candidate)) { $candidate } else { "$candidate.md" }
    return @($canonicalMarkdown | Where-Object { [System.IO.Path]::GetFileName($_) -ieq $name })
}

$absolutePathPatterns = @(
    '(?i)(?<![A-Z0-9])[A-Z]:\\',
    '(?i)(?<![A-Z0-9])[A-Z]:/',
    '(?i)(?<![A-Za-z0-9_])file:',
    '\\\\[A-Za-z0-9_.-]+',
    '(?<![A-Za-z0-9_])~[\\/]',
    '(?i)(?:^|[\s(''"])/(?:Users|home|tmp|var/tmp)/'
)

function Convert-ToReferenceLabel {
    param([Parameter(Mandatory = $true)][string]$Label)

    return ([regex]::Replace($Label.Trim().ToLowerInvariant(), '\s+', ' '))
}

$commonMarkAsciiEntities = @{
    '&excl;' = '!'
    '&quot;' = '"'
    '&num;' = '#'
    '&dollar;' = '$'
    '&percnt;' = '%'
    '&amp;' = '&'
    '&apos;' = "'"
    '&lpar;' = '('
    '&rpar;' = ')'
    '&ast;' = '*'
    '&plus;' = '+'
    '&comma;' = ','
    '&minus;' = '-'
    '&period;' = '.'
    '&sol;' = '/'
    '&colon;' = ':'
    '&semi;' = ';'
    '&lt;' = '<'
    '&equals;' = '='
    '&gt;' = '>'
    '&quest;' = '?'
    '&commat;' = '@'
    '&lsqb;' = '['
    '&bsol;' = '\'
    '&rsqb;' = ']'
    '&Hat;' = '^'
    '&lowbar;' = '_'
    '&grave;' = '`'
    '&lcub;' = '{'
    '&verbar;' = '|'
    '&rcub;' = '}'
    '&tilde;' = '~'
}

function Test-IsCommonMarkEscapable {
    param([Parameter(Mandatory = $true)][char]$Character)

    $code = [int]$Character
    return (($code -ge 0x21 -and $code -le 0x2F) -or
        ($code -ge 0x3A -and $code -le 0x40) -or
        ($code -ge 0x5B -and $code -le 0x60) -or
        ($code -ge 0x7B -and $code -le 0x7E))
}

function Convert-FromCommonMarkDestination {
    param([AllowEmptyString()][Parameter(Mandatory = $true)][string]$RawTarget)

    $builder = New-Object System.Text.StringBuilder
    for ($cursor = 0; $cursor -lt $RawTarget.Length; $cursor++) {
        $character = $RawTarget[$cursor]
        if ($character -eq '\' -and $cursor + 1 -lt $RawTarget.Length -and
            (Test-IsCommonMarkEscapable -Character $RawTarget[$cursor + 1])) {
            [void]$builder.Append($RawTarget[$cursor + 1])
            $cursor++
            continue
        }

        if ($character -eq '&') {
            $entityMatch = [regex]::Match(
                $RawTarget.Substring($cursor),
                '^&(?:#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});'
            )
            if ($entityMatch.Success) {
                $entity = $entityMatch.Value
                $decoded = if ($commonMarkAsciiEntities.ContainsKey($entity)) {
                    $commonMarkAsciiEntities[$entity]
                }
                else {
                    [System.Net.WebUtility]::HtmlDecode($entity)
                }
                if ($decoded -eq $entity -and $entity -notmatch '^&#') {
                    return [pscustomobject]@{
                        Success = $false
                        Value = ''
                        UnsupportedEntity = $entity
                    }
                }
                [void]$builder.Append($decoded)
                $cursor += $entity.Length - 1
                continue
            }
        }

        [void]$builder.Append($character)
    }

    return [pscustomobject]@{
        Success = $true
        Value = $builder.ToString()
        UnsupportedEntity = ''
    }
}

function Test-IsMarkdownEscaped {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$Index
    )

    $backslashes = 0
    for ($cursor = $Index - 1; $cursor -ge 0 -and $Content[$cursor] -eq '\'; $cursor--) {
        $backslashes++
    }
    return (($backslashes % 2) -eq 1)
}

function Get-MarkdownColumnAtIndex {
    param(
        [AllowEmptyString()][Parameter(Mandatory = $true)][string]$LineText,
        [Parameter(Mandatory = $true)][int]$Index
    )

    $column = 0
    $limit = [Math]::Min($Index, $LineText.Length)
    for ($cursor = 0; $cursor -lt $limit; $cursor++) {
        if ($LineText[$cursor] -eq "`t") {
            $column += 4 - ($column % 4)
        }
        else {
            $column++
        }
    }
    return $column
}

function Get-MarkdownFenceOpening {
    param([AllowEmptyString()][Parameter(Mandatory = $true)][string]$LineText)

    $containers = New-Object System.Collections.Generic.List[object]
    $cursor = 0
    while ($cursor -lt $LineText.Length) {
        $tokenStart = $cursor
        $spaces = 0
        while ($cursor -lt $LineText.Length -and $LineText[$cursor] -eq ' ' -and $spaces -lt 3) {
            $cursor++
            $spaces++
        }

        if ($cursor -lt $LineText.Length -and $LineText[$cursor] -eq '>') {
            $cursor++
            if ($cursor -lt $LineText.Length -and ($LineText[$cursor] -eq ' ' -or $LineText[$cursor] -eq "`t")) {
                $cursor++
            }
            $containers.Add([pscustomobject]@{ Kind = 'Quote'; Indent = 0; OrderedStart = -1 })
            continue
        }

        $listMatch = [regex]::Match(
            $LineText.Substring($cursor),
            '^(?:(?<bullet>[*+-])|(?<ordered>[0-9]{1,9})[.)])(?<spacing>[ \t]+)'
        )
        if ($listMatch.Success) {
            $spacingLength = $listMatch.Groups['spacing'].Length
            $markerLength = $listMatch.Length - $spacingLength
            $afterMarker = $cursor + $markerLength
            $spacingColumns = (Get-MarkdownColumnAtIndex -LineText $LineText -Index ($afterMarker + $spacingLength)) -
                (Get-MarkdownColumnAtIndex -LineText $LineText -Index $afterMarker)
            $delimiterSpacingCharacters = if ($spacingColumns -gt 4) { 1 } else { $spacingLength }
            $cursor = $afterMarker + $delimiterSpacingCharacters
            $containers.Add([pscustomobject]@{
                Kind = 'List'
                Indent = Get-MarkdownColumnAtIndex -LineText $LineText -Index $cursor
                LeadingSpaces = $spaces
                OrderedStart = if ($listMatch.Groups['ordered'].Success) {
                    [int64]$listMatch.Groups['ordered'].Value
                }
                else {
                    -1
                }
            })
            continue
        }

        $cursor = $tokenStart
        break
    }

    $indent = 0
    while ($cursor -lt $LineText.Length -and $LineText[$cursor] -eq ' ' -and $indent -lt 3) {
        $cursor++
        $indent++
    }
    $markerMatch = [regex]::Match($LineText.Substring($cursor), '^(?<marker>`{3,}|~{3,})')
    if (-not $markerMatch.Success) { return $null }

    $marker = $markerMatch.Groups['marker'].Value
    $cursor += $markerMatch.Length
    $infoString = $LineText.Substring($cursor)
    if ($marker[0] -eq '`' -and $infoString.Contains('`')) { return $null }

    $leadingQuoteCount = 0
    foreach ($container in $containers) {
        if ($container.Kind -ne 'Quote') { break }
        $leadingQuoteCount++
    }
    $firstList = @($containers | Where-Object { $_.Kind -eq 'List' } | Select-Object -First 1)
    $firstListLeadingSpaces = if ($firstList.Count -gt 0) { $firstList[0].LeadingSpaces } else { -1 }
    $hasNonInterruptingOrdered = ($firstList.Count -gt 0 -and
        $firstList[0].OrderedStart -ge 0 -and $firstList[0].OrderedStart -ne 1)

    return [pscustomobject]@{
        Character = $marker[0]
        Length = $marker.Length
        Containers = $containers.ToArray()
        HasQuote = @($containers | Where-Object { $_.Kind -eq 'Quote' }).Count -gt 0
        LeadingQuoteCount = $leadingQuoteCount
        FirstListLeadingSpaces = $firstListLeadingSpaces
        HasNonInterruptingOrdered = $hasNonInterruptingOrdered
    }
}

function Get-MarkdownFenceRemainder {
    param(
        [AllowEmptyString()]
        [Parameter(Mandatory = $true)][string]$LineText,
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)][object[]]$Containers
    )

    $cursor = 0
    foreach ($container in $Containers) {
        if ($container.Kind -eq 'Quote') {
            $spaces = 0
            while ($cursor -lt $LineText.Length -and $LineText[$cursor] -eq ' ' -and $spaces -lt 3) {
                $cursor++
                $spaces++
            }
            if ($cursor -ge $LineText.Length -or $LineText[$cursor] -ne '>') {
                return [pscustomobject]@{ Valid = $false; Text = '' }
            }
            $cursor++
            if ($cursor -lt $LineText.Length -and ($LineText[$cursor] -eq ' ' -or $LineText[$cursor] -eq "`t")) {
                $cursor++
            }
            continue
        }

        if ($container.Kind -eq 'List') {
            $column = Get-MarkdownColumnAtIndex -LineText $LineText -Index $cursor
            while ($cursor -lt $LineText.Length -and $column -lt $container.Indent -and
                ($LineText[$cursor] -eq ' ' -or $LineText[$cursor] -eq "`t")) {
                if ($LineText[$cursor] -eq "`t") {
                    $column += 4 - ($column % 4)
                }
                else {
                    $column++
                }
                $cursor++
            }
            if ($column -lt $container.Indent) {
                return [pscustomobject]@{ Valid = $false; Text = '' }
            }
        }
    }

    return [pscustomobject]@{
        Valid = $true
        Text = $LineText.Substring($cursor)
    }
}

function Get-MarkdownIndentColumns {
    param([AllowEmptyString()][Parameter(Mandatory = $true)][string]$LineText)

    $columns = 0
    for ($cursor = 0; $cursor -lt $LineText.Length; $cursor++) {
        if ($LineText[$cursor] -eq ' ') {
            $columns++
        }
        elseif ($LineText[$cursor] -eq "`t") {
            $columns += 4 - ($columns % 4)
        }
        else {
            break
        }
    }
    return $columns
}

function Get-MarkdownLeadingQuoteContent {
    param([AllowEmptyString()][Parameter(Mandatory = $true)][string]$LineText)

    $cursor = 0
    $quoteCount = 0
    while ($cursor -lt $LineText.Length) {
        $tokenStart = $cursor
        $spaces = 0
        while ($cursor -lt $LineText.Length -and $LineText[$cursor] -eq ' ' -and $spaces -lt 3) {
            $cursor++
            $spaces++
        }
        if ($cursor -ge $LineText.Length -or $LineText[$cursor] -ne '>') {
            $cursor = $tokenStart
            break
        }
        $cursor++
        if ($cursor -lt $LineText.Length -and ($LineText[$cursor] -eq ' ' -or $LineText[$cursor] -eq "`t")) {
            $cursor++
        }
        $quoteCount++
    }

    return [pscustomobject]@{
        QuoteCount = $quoteCount
        Text = $LineText.Substring($cursor)
    }
}

function Get-MarkdownHtmlBlockOpening {
    param([AllowEmptyString()][Parameter(Mandatory = $true)][string]$LineText)

    # Mask only unindented top-level HTML blocks. Container-aware HTML is left
    # visible to the link checker so that an uncertain parse fails closed.
    if ($LineText.Length -eq 0 -or [char]::IsWhiteSpace($LineText[0]) -or $LineText[0] -eq '>') {
        return $null
    }

    $typeOne = [regex]::Match($LineText, '^<(?<tag>script|pre|style|textarea)(?:[ \t]|>|$)', 'IgnoreCase')
    if ($typeOne.Success) {
        return [pscustomobject]@{
            EndsOnBlank = $false
            EndPattern = '</' + [regex]::Escape($typeOne.Groups['tag'].Value) + '>'
        }
    }
    if ($LineText.StartsWith('<!--', [System.StringComparison]::Ordinal)) {
        return [pscustomobject]@{ EndsOnBlank = $false; EndPattern = '-->' }
    }
    if ($LineText.StartsWith('<?', [System.StringComparison]::Ordinal)) {
        return [pscustomobject]@{ EndsOnBlank = $false; EndPattern = '\?>' }
    }
    if ($LineText -cmatch '^<![A-Z]') {
        return [pscustomobject]@{ EndsOnBlank = $false; EndPattern = '>' }
    }
    if ($LineText.StartsWith('<![CDATA[', [System.StringComparison]::Ordinal)) {
        return [pscustomobject]@{ EndsOnBlank = $false; EndPattern = '\]\]>' }
    }

    $blockTags = 'address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|search|section|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul'
    if ($LineText -match ('^</?(?:' + $blockTags + ')(?:[ \t]|/?>|$)')) {
        return [pscustomobject]@{ EndsOnBlank = $true; EndPattern = '' }
    }
    return $null
}

function Test-MarkdownStartsNewInlineBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$Index
    )

    if ($Index -le 0 -or $Index -ge $Content.Length) { return $false }
    if ($Content[$Index] -eq "`r" -or $Content[$Index] -eq "`n") { return $false }
    if ($Content[$Index - 1] -ne "`r" -and $Content[$Index - 1] -ne "`n") { return $false }

    $lineEnd = $Index
    while ($lineEnd -lt $Content.Length -and $Content[$lineEnd] -ne "`r" -and $Content[$lineEnd] -ne "`n") {
        $lineEnd++
    }
    $lineText = $Content.Substring($Index, $lineEnd - $Index)
    if ([string]::IsNullOrWhiteSpace($lineText)) { return $true }

    return ($lineText -match '^[ ]{0,3}(?:>|#{1,6}(?:[ \t]|$)|(?:[*+-]|0{0,8}1[.)])[ \t]+|`{3,}|~{3,}|<!--|<(?:(?:script|pre|style|textarea)(?:[ \t]|>|$)|\?|!(?-i:[A-Z])|!(?-i:\[CDATA\[))|\[(?:\\[^\r\n]|[^\]\\\r\n])+\]:)' -or
        $lineText -match '^[ ]{0,3}(?:=+|-+|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})[ \t]*$')
}

function Get-MarkdownLinkScanContent {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [switch]$PreserveHtmlBlocks
    )

    if ($Content.Length -eq 0) { return '' }

    $characters = $Content.ToCharArray()
    $masked = New-Object 'bool[]' $Content.Length
    $lineStart = 0
    $inFence = $false
    $fenceCharacter = [char]0
    $fenceLength = 0
    $fenceContainers = @()
    $fenceHasQuote = $false
    $inIndentedCode = $false
    $previousLineParagraph = $false
    $previousParagraphQuoteCount = -1
    $previousParagraphListIndent = 0
    $previousAllowsIndentedCode = $true
    $inHtmlBlock = $false
    $htmlBlockEndsOnBlank = $false
    $htmlBlockEndPattern = ''

    while ($lineStart -lt $Content.Length) {
        $newline = $Content.IndexOf("`n", $lineStart)
        $nextLine = if ($newline -lt 0) { $Content.Length } else { $newline + 1 }
        $lineEnd = if ($newline -lt 0) { $Content.Length } else { $newline }
        if ($lineEnd -gt $lineStart -and $Content[$lineEnd - 1] -eq "`r") { $lineEnd-- }
        $lineText = $Content.Substring($lineStart, $lineEnd - $lineStart)
        $wasParagraph = $previousLineParagraph
        $wasParagraphQuoteCount = $previousParagraphQuoteCount
        $wasParagraphListIndent = $previousParagraphListIndent
        $lineBlank = [string]::IsNullOrWhiteSpace($lineText)
        $quoteIndentContent = Get-MarkdownLeadingQuoteContent -LineText $lineText
        $lineIndented = (Get-MarkdownIndentColumns -LineText $quoteIndentContent.Text) -ge 4
        $maskLine = $false
        $lineHandled = $false
        $closedFenceThisLine = $false
        $closedHtmlThisLine = $false
        $remainder = $null

        if ($inFence) {
            if ($lineBlank -and -not $fenceHasQuote) {
                $maskLine = $true
                $lineHandled = $true
            }
            else {
                $remainder = Get-MarkdownFenceRemainder -LineText $lineText -Containers $fenceContainers
                if ($remainder.Valid) {
                    $maskLine = $true
                    $lineHandled = $true
                }
                else {
                    $inFence = $false
                }
            }
            if ($lineHandled -and $null -ne $remainder) {
                $closingPattern = '^[ ]{0,3}' + [regex]::Escape([string]$fenceCharacter) +
                    '{' + $fenceLength + ',}[ \t]*$'
                if ([regex]::IsMatch($remainder.Text, $closingPattern)) {
                    $inFence = $false
                    $closedFenceThisLine = $true
                }
            }
        }

        if (-not $lineHandled -and $inHtmlBlock) {
            if ($htmlBlockEndsOnBlank -and $lineBlank) {
                $inHtmlBlock = $false
                $closedHtmlThisLine = $true
            }
            else {
                $maskLine = -not $PreserveHtmlBlocks
                $lineHandled = $true
                if (-not $htmlBlockEndsOnBlank -and
                    [regex]::IsMatch($lineText, $htmlBlockEndPattern, 'IgnoreCase')) {
                    $inHtmlBlock = $false
                    $closedHtmlThisLine = $true
                }
            }
        }

        if (-not $lineHandled -and $inIndentedCode) {
            if ($lineBlank -or $lineIndented) {
                $maskLine = $true
                $lineHandled = $true
            }
            else {
                $inIndentedCode = $false
            }
        }

        if (-not $lineHandled) {
            $opening = $null
            $htmlOpening = Get-MarkdownHtmlBlockOpening -LineText $lineText
            if ($null -ne $htmlOpening) {
                $inHtmlBlock = $true
                $htmlBlockEndsOnBlank = $htmlOpening.EndsOnBlank
                $htmlBlockEndPattern = $htmlOpening.EndPattern
                $maskLine = -not $PreserveHtmlBlocks
                if (-not $htmlBlockEndsOnBlank -and
                    [regex]::IsMatch($lineText, $htmlBlockEndPattern, 'IgnoreCase')) {
                    $inHtmlBlock = $false
                    $closedHtmlThisLine = $true
                }
            }
            else {
                $opening = Get-MarkdownFenceOpening -LineText $lineText
                if ($null -ne $opening -and $opening.HasNonInterruptingOrdered -and $wasParagraph -and
                    $opening.LeadingQuoteCount -eq $wasParagraphQuoteCount -and
                    ($wasParagraphListIndent -eq 0 -or
                        $opening.FirstListLeadingSpaces -ge $wasParagraphListIndent)) {
                    $opening = $null
                }
            }
            if ($null -ne $opening) {
                $fenceCharacter = $opening.Character
                $fenceLength = $opening.Length
                $fenceContainers = @($opening.Containers)
                $fenceHasQuote = $opening.HasQuote
                $inFence = $true
                $maskLine = $true
            }
            elseif ($lineIndented -and $previousAllowsIndentedCode) {
                $inIndentedCode = $true
                $maskLine = $true
            }
        }

        if ($maskLine) {
            for ($index = $lineStart; $index -lt $nextLine; $index++) {
                $masked[$index] = $true
            }
        }

        if ($lineBlank -or $maskLine) {
            $previousLineParagraph = $false
            $previousParagraphQuoteCount = -1
            $previousParagraphListIndent = 0
        }
        else {
            $quoteContent = Get-MarkdownLeadingQuoteContent -LineText $lineText
            $contentLine = $quoteContent.Text
            $listLine = [regex]::Match(
                $contentLine,
                '^(?<leading> {0,3})(?:(?<bullet>[*+-])|(?<ordered>[0-9]{1,9})[.)])(?<spacing>[ \t]+)(?<body>.*)$'
            )
            $nonParagraphBlock = $contentLine -match '^[ ]{0,3}(?:#{1,6}(?:[ \t]|$)|<!--|\[(?:\\[^\r\n]|[^\]\\\r\n])+\]:)' -or
                $contentLine -match '^[ ]{0,3}(?:=+|-+|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})[ \t]*$'
            if ($listLine.Success) {
                $continuesParagraph = ($listLine.Groups['ordered'].Success -and
                    [int64]$listLine.Groups['ordered'].Value -ne 1 -and $wasParagraph -and
                    $quoteContent.QuoteCount -eq $wasParagraphQuoteCount -and
                    ($wasParagraphListIndent -eq 0 -or
                        $listLine.Groups['leading'].Length -ge $wasParagraphListIndent))
                if ($continuesParagraph) {
                    $previousLineParagraph = $true
                    $previousParagraphListIndent = $wasParagraphListIndent
                }
                else {
                    $spacingLength = $listLine.Groups['spacing'].Length
                    $delimiterSpacing = if ($spacingLength -gt 4) { 1 } else { $spacingLength }
                    $markerLength = $listLine.Groups['bullet'].Length
                    if ($markerLength -eq 0) { $markerLength = $listLine.Groups['ordered'].Length + 1 }
                    $previousLineParagraph = -not [string]::IsNullOrWhiteSpace($listLine.Groups['body'].Value)
                    $previousParagraphListIndent = if ($previousLineParagraph) {
                        $listLine.Groups['leading'].Length + $markerLength + $delimiterSpacing
                    }
                    else {
                        0
                    }
                }
            }
            else {
                $previousLineParagraph = -not $nonParagraphBlock
                $previousParagraphListIndent = if ($previousLineParagraph -and $wasParagraph -and
                    $quoteContent.QuoteCount -eq $wasParagraphQuoteCount -and
                    (Get-MarkdownIndentColumns -LineText $contentLine) -ge $wasParagraphListIndent) {
                    $wasParagraphListIndent
                }
                else {
                    0
                }
            }
            $previousParagraphQuoteCount = if ($previousLineParagraph) { $quoteContent.QuoteCount } else { -1 }
        }

        $quoteContentForBlock = Get-MarkdownLeadingQuoteContent -LineText $lineText
        $contentForBlock = $quoteContentForBlock.Text
        $listBlock = [regex]::IsMatch($contentForBlock, '^[ ]{0,3}(?:[*+-]|[0-9]{1,9}[.)])[ \t]+')
        $standaloneBlock = $contentForBlock -match '^[ ]{0,3}(?:#{1,6}(?:[ \t]|$)|<!--|\[(?:\\[^\r\n]|[^\]\\\r\n])+\]:)' -or
            $contentForBlock -match '^[ ]{0,3}(?:=+|-+|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})[ \t]*$' -or
            $quoteContentForBlock.QuoteCount -gt 0
        $previousAllowsIndentedCode = $lineBlank -or $closedFenceThisLine -or $closedHtmlThisLine -or
            (-not $listBlock -and $standaloneBlock)
        $lineStart = $nextLine
    }

    $commentScanCharacters = $Content.ToCharArray()
    for ($index = 0; $index -lt $commentScanCharacters.Length; $index++) {
        if ($masked[$index] -and $commentScanCharacters[$index] -ne "`r" -and $commentScanCharacters[$index] -ne "`n") {
            $commentScanCharacters[$index] = ' '
        }
    }
    $maskedText = -join $commentScanCharacters
    foreach ($comment in [regex]::Matches($maskedText, '(?s)<!--.*?(?:-->|$)')) {
        if (Test-IsMarkdownEscaped -Content $maskedText -Index $comment.Index) { continue }
        for ($index = $comment.Index; $index -lt $comment.Index + $comment.Length; $index++) {
            $masked[$index] = $true
        }
    }

    $cursor = 0
    while ($cursor -lt $Content.Length) {
        if ($masked[$cursor] -or $Content[$cursor] -ne '`' -or
            (Test-IsMarkdownEscaped -Content $Content -Index $cursor)) {
            $cursor++
            continue
        }

        $openingStart = $cursor
        while ($cursor -lt $Content.Length -and -not $masked[$cursor] -and $Content[$cursor] -eq '`') {
            $cursor++
        }
        $delimiterLength = $cursor - $openingStart
        $search = $cursor
        $closingEnd = -1
        while ($search -lt $Content.Length) {
            if ($Content[$search] -eq "`r" -or $Content[$search] -eq "`n") {
                $nextLine = $search
                if ($Content[$nextLine] -eq "`r" -and $nextLine + 1 -lt $Content.Length -and
                    $Content[$nextLine + 1] -eq "`n") {
                    $nextLine += 2
                }
                else {
                    $nextLine++
                }
                $probe = $nextLine
                while ($probe -lt $Content.Length -and ($Content[$probe] -eq ' ' -or $Content[$probe] -eq "`t")) {
                    $probe++
                }
                if ($probe -ge $Content.Length -or $Content[$probe] -eq "`r" -or $Content[$probe] -eq "`n") {
                    break
                }
            }
            if ($masked[$search] -or
                (Test-MarkdownStartsNewInlineBlock -Content $Content -Index $search)) {
                break
            }
            if ($Content[$search] -ne '`') {
                $search++
                continue
            }
            $runStart = $search
            while ($search -lt $Content.Length -and -not $masked[$search] -and $Content[$search] -eq '`') {
                $search++
            }
            if (($search - $runStart) -eq $delimiterLength) {
                $closingEnd = $search
                break
            }
        }

        if ($closingEnd -ge 0) {
            for ($index = $openingStart; $index -lt $closingEnd; $index++) {
                $masked[$index] = $true
            }
            $cursor = $closingEnd
        }
    }

    for ($index = 0; $index -lt $characters.Length; $index++) {
        if ($masked[$index] -and $characters[$index] -ne "`r" -and $characters[$index] -ne "`n") {
            $characters[$index] = ' '
        }
    }
    return (-join $characters)
}

function Test-HasMarkdownLinkOpener {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$CloseBracketIndex
    )

    $depth = 0
    for ($cursor = $CloseBracketIndex - 1; $cursor -ge 0; $cursor--) {
        if ($Content[$cursor] -eq ']' -and -not (Test-IsMarkdownEscaped -Content $Content -Index $cursor)) {
            $depth++
        }
        elseif ($Content[$cursor] -eq '[' -and -not (Test-IsMarkdownEscaped -Content $Content -Index $cursor)) {
            if ($depth -eq 0) { return $true }
            $depth--
        }
    }
    return $false
}

function Get-MarkdownDestination {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$StartIndex,
        [switch]$AllowEmpty
    )

    $cursor = $StartIndex
    while ($cursor -lt $Content.Length -and ($Content[$cursor] -eq ' ' -or $Content[$cursor] -eq "`t")) {
        $cursor++
    }

    if ($cursor -lt $Content.Length -and ($Content[$cursor] -eq "`r" -or $Content[$cursor] -eq "`n")) {
        if ($Content[$cursor] -eq "`r" -and $cursor + 1 -lt $Content.Length -and $Content[$cursor + 1] -eq "`n") {
            $cursor += 2
        }
        else {
            $cursor++
        }
        while ($cursor -lt $Content.Length -and ($Content[$cursor] -eq ' ' -or $Content[$cursor] -eq "`t")) {
            $cursor++
        }
        if ($cursor -lt $Content.Length -and ($Content[$cursor] -eq "`r" -or $Content[$cursor] -eq "`n")) {
            return $null
        }
    }

    if ($cursor -ge $Content.Length) { return $null }

    $targetStart = $cursor
    if ($AllowEmpty -and ($Content[$cursor] -eq ')' -or $Content[$cursor] -eq '"' -or $Content[$cursor] -eq "'")) {
        return [pscustomobject]@{
            Target = ''
            Index = $targetStart
            EndIndex = $targetStart
            Balanced = $true
        }
    }

    if ($Content[$cursor] -eq '<') {
        $cursor++
        while ($cursor -lt $Content.Length) {
            if (($Content[$cursor] -eq "`r") -or ($Content[$cursor] -eq "`n")) { return $null }
            if ($Content[$cursor] -eq '>' -and -not (Test-IsMarkdownEscaped -Content $Content -Index $cursor)) {
                return [pscustomobject]@{
                    Target = $Content.Substring($targetStart, $cursor - $targetStart + 1)
                    Index = $targetStart
                    EndIndex = $cursor + 1
                    Balanced = $true
                }
            }
            $cursor++
        }
        return $null
    }

    $depth = 0
    while ($cursor -lt $Content.Length) {
        $character = $Content[$cursor]
        $escaped = Test-IsMarkdownEscaped -Content $Content -Index $cursor
        if (-not $escaped -and ($character -eq ' ' -or $character -eq "`t" -or $character -eq "`r" -or $character -eq "`n")) {
            break
        }
        if (-not $escaped -and $character -eq '(') {
            $depth++
        }
        elseif (-not $escaped -and $character -eq ')') {
            if ($depth -eq 0) { break }
            $depth--
        }
        $cursor++
    }

    if ($cursor -eq $targetStart) {
        if ($AllowEmpty) {
            return [pscustomobject]@{
                Target = ''
                Index = $targetStart
                EndIndex = $targetStart
                Balanced = $true
            }
        }
        return $null
    }

    return [pscustomobject]@{
        Target = $Content.Substring($targetStart, $cursor - $targetStart)
        Index = $targetStart
        EndIndex = $cursor
        Balanced = ($depth -eq 0)
    }
}

function Move-PastMarkdownLinkWhitespace {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$StartIndex
    )

    $cursor = $StartIndex
    $lineBreaks = 0
    while ($cursor -lt $Content.Length) {
        if ($Content[$cursor] -eq ' ' -or $Content[$cursor] -eq "`t") {
            $cursor++
            continue
        }
        if ($Content[$cursor] -eq "`r" -or $Content[$cursor] -eq "`n") {
            $lineBreaks++
            if ($lineBreaks -gt 1) {
                return [pscustomobject]@{ Valid = $false; Index = $cursor; HadWhitespace = $true }
            }
            if ($Content[$cursor] -eq "`r" -and $cursor + 1 -lt $Content.Length -and $Content[$cursor + 1] -eq "`n") {
                $cursor += 2
            }
            else {
                $cursor++
            }
            continue
        }
        break
    }
    return [pscustomobject]@{
        Valid = $true
        Index = $cursor
        HadWhitespace = ($cursor -gt $StartIndex)
    }
}

function Test-InlineMarkdownClosure {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)]$Destination
    )

    if (-not $Destination.Balanced) { return $false }

    $spacing = Move-PastMarkdownLinkWhitespace -Content $Content -StartIndex $Destination.EndIndex
    if (-not $spacing.Valid -or $spacing.Index -ge $Content.Length) { return $false }
    $cursor = $spacing.Index
    if ($Content[$cursor] -eq ')') { return $true }

    if (-not $spacing.HadWhitespace -and $Destination.Target.Length -gt 0) { return $false }
    $opener = $Content[$cursor]
    if ($opener -ne '"' -and $opener -ne "'" -and $opener -ne '(') { return $false }
    $closer = if ($opener -eq '(') { ')' } else { $opener }
    $cursor++
    $titleClosed = $false
    while ($cursor -lt $Content.Length) {
        if ($Content[$cursor] -eq $closer -and -not (Test-IsMarkdownEscaped -Content $Content -Index $cursor)) {
            $titleClosed = $true
            $cursor++
            break
        }
        $cursor++
    }
    if (-not $titleClosed) { return $false }

    $spacing = Move-PastMarkdownLinkWhitespace -Content $Content -StartIndex $cursor
    return ($spacing.Valid -and $spacing.Index -lt $Content.Length -and $Content[$spacing.Index] -eq ')')
}

function Test-ReferenceDefinitionTail {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)]$Destination
    )

    if (-not $Destination.Balanced) { return $false }

    $cursor = $Destination.EndIndex
    while ($cursor -lt $Content.Length -and ($Content[$cursor] -eq ' ' -or $Content[$cursor] -eq "`t")) {
        $cursor++
    }
    if ($cursor -ge $Content.Length -or $Content[$cursor] -eq "`r" -or $Content[$cursor] -eq "`n") {
        return $true
    }

    $opener = $Content[$cursor]
    if ($opener -ne '"' -and $opener -ne "'" -and $opener -ne '(') { return $false }
    $closer = if ($opener -eq '(') { ')' } else { $opener }
    $cursor++
    $titleClosed = $false
    while ($cursor -lt $Content.Length) {
        if ($Content[$cursor] -eq $closer -and -not (Test-IsMarkdownEscaped -Content $Content -Index $cursor)) {
            $titleClosed = $true
            $cursor++
            break
        }
        if ($Content[$cursor] -eq "`r" -or $Content[$cursor] -eq "`n") {
            if ($Content[$cursor] -eq "`r" -and $cursor + 1 -lt $Content.Length -and $Content[$cursor + 1] -eq "`n") {
                $cursor += 2
            }
            else {
                $cursor++
            }
            $probe = $cursor
            while ($probe -lt $Content.Length -and ($Content[$probe] -eq ' ' -or $Content[$probe] -eq "`t")) {
                $probe++
            }
            if ($probe -ge $Content.Length -or $Content[$probe] -eq "`r" -or $Content[$probe] -eq "`n") {
                return $false
            }
            continue
        }
        $cursor++
    }
    if (-not $titleClosed) { return $false }

    while ($cursor -lt $Content.Length -and ($Content[$cursor] -eq ' ' -or $Content[$cursor] -eq "`t")) {
        $cursor++
    }
    return ($cursor -ge $Content.Length -or $Content[$cursor] -eq "`r" -or $Content[$cursor] -eq "`n")
}

function Convert-PercentDecodedText {
    param([Parameter(Mandatory = $true)][string]$Value)

    $current = [System.Net.WebUtility]::HtmlDecode($Value)
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try {
            $decoded = [System.Uri]::UnescapeDataString($current)
        }
        catch {
            return $current
        }
        if ($decoded -ceq $current) { break }
        $current = $decoded
    }
    return $current
}

function Test-ExternalMarkdownTarget {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][int]$MatchIndex
    )

    $relativeFile = Get-RelativePath $SourceFile
    $line = Get-LineNumber $Content $MatchIndex
    # Target может содержать credentials, signed query, userinfo или PII.
    # Никогда не интерполировать его в diagnostics.
    if ($Target.StartsWith('//')) {
        $issues.Add("Protocol-relative Markdown URI запрещен: ${relativeFile}:$line")
        return $true
    }
    if ($Target -notmatch '^(?i:[a-z][a-z0-9+.-]*):') {
        return $false
    }

    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($Target, [System.UriKind]::Absolute, [ref]$parsedUri) -or
        -not [System.Uri]::IsWellFormedUriString($Target, [System.UriKind]::Absolute)) {
        $issues.Add("Некорректный внешний Markdown URI: ${relativeFile}:$line")
        return $true
    }
    if ($parsedUri.Scheme -cne 'https') {
        $issues.Add("Внешний Markdown URI должен использовать только https: ${relativeFile}:$line")
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($parsedUri.Host)) {
        $issues.Add("HTTPS Markdown URI не содержит host: ${relativeFile}:$line")
        return $true
    }
    if (-not [string]::IsNullOrWhiteSpace($parsedUri.UserInfo)) {
        $issues.Add("UserInfo в Markdown URI запрещен: ${relativeFile}:$line")
        return $true
    }

    if (-not [string]::IsNullOrWhiteSpace($parsedUri.Query)) {
        $query = [System.Net.WebUtility]::HtmlDecode($parsedUri.Query.TrimStart('?'))
        foreach ($pair in @($query -split '[&;]')) {
            if ([string]::IsNullOrWhiteSpace($pair)) { continue }
            $rawName = $pair.Split('=', 2)[0].Replace('+', ' ')
            $decodedName = Convert-PercentDecodedText $rawName
            $normalizedName = ($decodedName.ToLowerInvariant() -replace '[^a-z0-9]', '')
            if ($normalizedName -match '^(?:token|accesstoken|idtoken|refreshtoken|secret|signature|sig|key|apikey|password|passwd|credential|auth|authorization|proxyauthorization|sharedaccesssignature|expires|xamzsignature|xamzcredential|xamzexpires|xamzsecuritytoken|xgoogsignature|xgoogcredential|xgoogexpires|awsaccesskeyid|googleaccessid|policy)$') {
                $issues.Add("Credential-bearing query в Markdown URI запрещен: ${relativeFile}:$line")
                return $true
            }
        }
    }
    return $true
}

function Test-MarkdownTarget {
    param(
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)][string]$Content,
        [AllowEmptyString()]
        [Parameter(Mandatory = $true)][string]$RawTarget,
        [Parameter(Mandatory = $true)][int]$MatchIndex
    )

    $relativeFile = Get-RelativePath $SourceFile
    $syntaxTarget = if ($RawTarget.Length -ge 2 -and $RawTarget[0] -eq '<' -and
        $RawTarget[$RawTarget.Length - 1] -eq '>') {
        $RawTarget.Substring(1, $RawTarget.Length - 2)
    }
    else {
        $RawTarget
    }
    $normalized = Convert-FromCommonMarkDestination -RawTarget $syntaxTarget
    if (-not $normalized.Success) {
        $issues.Add("Неподдерживаемая character reference: ${relativeFile}:$((Get-LineNumber $Content $MatchIndex)) (unsupported-character-reference).")
        return
    }
    $target = $normalized.Value
    if ($target -match '^(?i:file):') {
        $issues.Add("Абсолютный локальный file URI запрещен: ${relativeFile}:$((Get-LineNumber $Content $MatchIndex))")
        return
    }
    if ($target -match '^[A-Za-z]:') {
        $issues.Add("Локальный путь диска запрещен: ${relativeFile}:$((Get-LineNumber $Content $MatchIndex)) (absolute-drive-path).")
        return
    }
    if ($target.StartsWith('\') -or $target -match '^(?i:/(?:Users|home|tmp|var/tmp)(?:/|$)|~[\\/])') {
        $issues.Add("Абсолютный локальный путь запрещен: ${relativeFile}:$((Get-LineNumber $Content $MatchIndex)) (absolute-local-path).")
        return
    }
    if (Test-ExternalMarkdownTarget -SourceFile $SourceFile -Content $Content -Target $target -MatchIndex $MatchIndex) {
        return
    }

    $parts = $target -split '#', 2
    try {
        $pathPart = [System.Uri]::UnescapeDataString($parts[0])
    }
    catch {
        $issues.Add("Некорректное URL-кодирование ссылки: ${relativeFile}:$((Get-LineNumber $Content $MatchIndex)) (invalid-percent-encoding).")
        return
    }

    $anchor = if ($parts.Count -gt 1) { $parts[1] } else { '' }
    try {
        $resolved = if ([string]::IsNullOrWhiteSpace($pathPart)) {
            $SourceFile
        }
        elseif ($pathPart.StartsWith('/')) {
            Join-Path $rootPath $pathPart.TrimStart('/')
        }
        else {
            Join-Path (Split-Path -Parent $SourceFile) $pathPart
        }
        $resolved = [System.IO.Path]::GetFullPath($resolved)
    }
    catch {
        $issues.Add("Некорректный Markdown-путь: ${relativeFile}:$((Get-LineNumber $Content $MatchIndex)) (invalid-local-target).")
        return
    }

    $line = Get-LineNumber $Content $MatchIndex
    if (-not (Test-PathWithinRoot $resolved)) {
        $issues.Add("Markdown-ссылка выходит за корень: ${relativeFile}:$line (outside-root-target).")
    }
    elseif (-not (Test-Path -LiteralPath $resolved)) {
        if (-not (Test-IsLegacyRetiredHistoryReference -SourceFile $SourceFile -TargetFile $resolved)) {
            $issues.Add("Битая Markdown-ссылка: ${relativeFile}:$line (missing-local-target).")
        }
    }
    elseif ($effectiveMode -cin @('TemplateSource', 'DistributionTemplate') -and -not (Test-IsTemplateLinkAllowed -SourceFile $SourceFile -TargetFile $resolved)) {
        $issues.Add("Markdown-ссылка ведет вне переносимого allowlist: ${relativeFile}:$line (target-not-portable).")
    }
    elseif ($null -ne (Get-ReparsePointInPath $resolved)) {
        $issues.Add("Markdown-ссылка ведет через reparse point: ${relativeFile}:$line (reparse-target).")
    }
    elseif (-not (Test-ExactPathCase $resolved)) {
        $issues.Add("Неверный регистр Markdown-пути: ${relativeFile}:$line (target-case-mismatch).")
    }
    elseif (-not (Test-Anchor $resolved $anchor)) {
        $issues.Add("Отсутствующий anchor: ${relativeFile}:$line (missing-anchor).")
    }
}

$commonMarkUriAutolinkPattern = '<(?<target>[A-Za-z][A-Za-z0-9+.-]{1,31}:[^<>\x00-\x20\x7F]*)>'
$commonMarkEmailAutolinkPattern = '(?i)<(?<target>[A-Z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?)*)>'
$rawHtmlTagPattern = '(?is)</?[A-Za-z][A-Za-z0-9-]*(?:\s+[^<>]*?)?/?>'
$rawHtmlDeclarationPattern = '(?is)<(?:\?|![A-Z]|!\[CDATA\[)'

foreach ($filePath in $canonicalMarkdown) {
    $fileReparse = Get-ReparsePointInPath $filePath
    if ($null -ne $fileReparse) {
        $issues.Add("Reparse point в Markdown-пути: $(Get-RelativePath $fileReparse)")
        continue
    }
    $content = Read-BoundedUtf8File -LiteralPath $filePath -MaxBytes $resourceLimits.MarkdownBytes -Label (Get-RelativePath $filePath)
    $linkScanContent = Get-MarkdownLinkScanContent -Content $content
    $renderedSurfaceContent = Get-MarkdownLinkScanContent -Content $content -PreserveHtmlBlocks
    $relativeFile = Get-RelativePath $filePath

    foreach ($pattern in $absolutePathPatterns) {
        foreach ($match in [regex]::Matches($content, $pattern)) {
            $issues.Add("Абсолютный локальный путь: ${relativeFile}:$((Get-LineNumber $content $match.Index))")
        }
    }

    # Canonical Markdown должен оставаться переносимым и безопасным для
    # рендереров: URI-autolinks проходят тот же HTTPS gate, email-autolinks
    # запрещены. Любой raw HTML консервативно считается активным, потому что
    # возможности Markdown-рендереров различаются. Кодовые блоки и code spans
    # замаскированы.
    foreach ($match in [regex]::Matches($linkScanContent, $commonMarkUriAutolinkPattern)) {
        if (Test-IsMarkdownEscaped -Content $linkScanContent -Index $match.Index) { continue }
        $target = $match.Groups['target'].Value
        [void](Test-ExternalMarkdownTarget -SourceFile $filePath -Content $content -Target $target -MatchIndex $match.Index)
    }
    foreach ($match in [regex]::Matches($linkScanContent, $commonMarkEmailAutolinkPattern)) {
        if (Test-IsMarkdownEscaped -Content $linkScanContent -Index $match.Index) { continue }
        $issues.Add("Email autolink запрещен, используй обычную HTTPS-ссылку: ${relativeFile}:$((Get-LineNumber $content $match.Index))")
    }
    foreach ($match in [regex]::Matches($renderedSurfaceContent, $rawHtmlTagPattern)) {
        if (Test-IsMarkdownEscaped -Content $renderedSurfaceContent -Index $match.Index) { continue }
        $issues.Add("Активный raw HTML запрещен в каноническом Markdown: ${relativeFile}:$((Get-LineNumber $content $match.Index))")
    }
    foreach ($match in [regex]::Matches($renderedSurfaceContent, $rawHtmlDeclarationPattern)) {
        if (Test-IsMarkdownEscaped -Content $renderedSurfaceContent -Index $match.Index) { continue }
        $issues.Add("Raw HTML declaration или processing instruction запрещены: ${relativeFile}:$((Get-LineNumber $content $match.Index))")
    }

    foreach ($match in [regex]::Matches($linkScanContent, '\]\(')) {
        if ((Test-IsMarkdownEscaped -Content $linkScanContent -Index $match.Index) -or
            -not (Test-HasMarkdownLinkOpener -Content $linkScanContent -CloseBracketIndex $match.Index)) {
            continue
        }
        $destination = Get-MarkdownDestination -Content $linkScanContent -StartIndex ($match.Index + $match.Length) -AllowEmpty
        if ($null -eq $destination -or
            -not (Test-InlineMarkdownClosure -Content $linkScanContent -Destination $destination)) {
            $issues.Add("Некорректная inline Markdown-ссылка: ${relativeFile}:$((Get-LineNumber $content $match.Index))")
            continue
        }
        Test-MarkdownTarget -SourceFile $filePath -Content $content -RawTarget $destination.Target -MatchIndex $match.Index
    }

    $referenceDefinitions = @{}
    $definitionPattern = '(?m)^[ \t]{0,3}\[(?<label>(?:\\[^\r\n]|[^\]\\\r\n])+)\]:'
    foreach ($match in [regex]::Matches($linkScanContent, $definitionPattern)) {
        $destination = Get-MarkdownDestination -Content $linkScanContent -StartIndex ($match.Index + $match.Length)
        if ($null -eq $destination) { continue }
        if (-not (Test-ReferenceDefinitionTail -Content $linkScanContent -Destination $destination)) {
            $issues.Add("Некорректная reference definition: ${relativeFile}:$((Get-LineNumber $content $match.Index))")
            continue
        }
        $label = Convert-ToReferenceLabel $match.Groups['label'].Value
        if (-not $referenceDefinitions.ContainsKey($label)) {
            $referenceDefinitions[$label] = $destination.Target
        }
        Test-MarkdownTarget -SourceFile $filePath -Content $content -RawTarget $destination.Target -MatchIndex $match.Index
    }

    $referenceUsePattern = '(?<!!)!?\[(?<text>(?:\\[^\r\n]|[^\]\\\r\n])*)\]\[(?<label>(?:\\[^\r\n]|[^\]\\\r\n])*)\]'
    foreach ($match in [regex]::Matches($linkScanContent, $referenceUsePattern)) {
        $rawLabel = if ([string]::IsNullOrWhiteSpace($match.Groups['label'].Value)) { $match.Groups['text'].Value } else { $match.Groups['label'].Value }
        $label = Convert-ToReferenceLabel $rawLabel
        if (-not $referenceDefinitions.ContainsKey($label)) {
            $issues.Add("Битая reference-ссылка: ${relativeFile}:$((Get-LineNumber $content $match.Index)) (missing-reference-definition).")
        }
    }

    foreach ($match in [regex]::Matches($linkScanContent, '\[\[(?<body>[^\]]+)\]\]')) {
        $body = ($match.Groups['body'].Value -split '\|', 2)[0]
        $parts = $body -split '#', 2
        $linkPath = $parts[0].Trim()
        $anchor = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        $line = Get-LineNumber $content $match.Index
        $resolvedCandidates = @(Resolve-Wikilink $filePath $linkPath)
        $existing = @($resolvedCandidates | Where-Object { (Test-PathWithinRoot $_) -and (Test-Path -LiteralPath $_ -PathType Leaf) })

        if ($existing.Count -eq 0) {
            $issues.Add("Битый Wikilink: ${relativeFile}:$line (missing-wikilink-target).")
        }
        elseif ($existing.Count -gt 1) {
            $issues.Add("Неоднозначный Wikilink: ${relativeFile}:$line (ambiguous-wikilink-target).")
        }
        elseif ($effectiveMode -cin @('TemplateSource', 'DistributionTemplate') -and -not (Test-IsTemplateLinkAllowed -SourceFile $filePath -TargetFile $existing[0])) {
            $issues.Add("Wikilink ведет вне переносимого allowlist: ${relativeFile}:$line (wikilink-target-not-portable).")
        }
        elseif ($null -ne (Get-ReparsePointInPath $existing[0])) {
            $issues.Add("Wikilink ведет через reparse point: ${relativeFile}:$line (wikilink-reparse-target).")
        }
        elseif (-not (Test-ExactPathCase $existing[0])) {
            $issues.Add("Неверный регистр Wikilink: ${relativeFile}:$line (wikilink-case-mismatch).")
        }
        elseif (-not (Test-Anchor $existing[0] $anchor)) {
            $issues.Add("Отсутствующий Wikilink anchor: ${relativeFile}:$line (missing-wikilink-anchor).")
        }
    }
}

function Invoke-TrustedSemanticGate {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [Parameter(Mandatory = $true)][string]$GateLabel,
        [Parameter(Mandatory = $true)][string]$PowerShellExecutable,
        [string[]]$AdditionalArguments = @()
    )

    $verifierPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $verifierPath -PathType Leaf)) {
        $issues.Add("Trusted $GateLabel verifier отсутствует рядом с verify-structure.ps1.")
        return
    }
    $verifierReparse = Get-EarlyReparsePoint $verifierPath
    if ($null -ne $verifierReparse) {
        $issues.Add("Trusted $GateLabel verifier проходит через reparse point.")
        return
    }
    $gateArguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $verifierPath,
        '-Root', $rootPath
    )
    if ($AdditionalArguments.Count -gt 0) { $gateArguments += $AdditionalArguments }
    $gateResult = Invoke-SanitizedProcess -Executable $PowerShellExecutable -Arguments $gateArguments
    if ($gateResult.ExitCode -ne 0) {
        $issues.Add("Semantic $GateLabel gate завершился с ошибкой.")
        foreach ($gateLine in $gateResult.Output) {
            Write-Host (Convert-ToSafeStructureDiagnostic -Text ([string]$gateLine))
        }
    }
}

$powershellExe = Get-TrustedCurrentPowerShellHost
if ($null -eq $powershellExe) {
    $issues.Add('Текущий PowerShell host не прошел trusted executable gate.')
}
else {
    if ($effectiveMode -cne 'DistributionTemplate') {
        Invoke-TrustedSemanticGate -ScriptName 'update-knowledge-graph.ps1' -GateLabel 'knowledge-graph' -PowerShellExecutable $powershellExe -AdditionalArguments @('-Mode', 'Check')
        Invoke-TrustedSemanticGate -ScriptName 'update-mastery-index.ps1' -GateLabel 'mastery-index' -PowerShellExecutable $powershellExe -AdditionalArguments @('-Mode', 'Check')
        Invoke-TrustedSemanticGate -ScriptName 'verify-canon.ps1' -GateLabel 'canon' -PowerShellExecutable $powershellExe
        Invoke-TrustedSemanticGate -ScriptName 'verify-analysis.ps1' -GateLabel 'analysis' -PowerShellExecutable $powershellExe
        Invoke-TrustedSemanticGate -ScriptName 'verify-plans.ps1' -GateLabel 'plans' -PowerShellExecutable $powershellExe
        Invoke-TrustedSemanticGate -ScriptName 'verify-knowledge.ps1' -GateLabel 'knowledge' -PowerShellExecutable $powershellExe
    }
    Invoke-TrustedSemanticGate -ScriptName 'verify-codex-agents.ps1' -GateLabel 'codex-agents' -PowerShellExecutable $powershellExe
    $sanitizeScope = if ($effectiveMode -ceq 'TemplateSource') { 'Source' } else { 'Consumer' }
    Invoke-TrustedSemanticGate -ScriptName 'verify-template-sanitization.ps1' -GateLabel 'sanitization' -PowerShellExecutable $powershellExe -AdditionalArguments @('-Scope', $sanitizeScope)
}

if ($issues.Count -gt 0) {
    Write-Host "FAIL [$effectiveMode]: найдено проблем - $($issues.Count)" -ForegroundColor Red
    $issues | Sort-Object -Unique | ForEach-Object {
        Write-Host "- $(Convert-ToSafeStructureDiagnostic -Text ([string]$_))"
    }
    exit 1
}

Write-Host "PASS [$effectiveMode]: структура и ссылки корректны. Канонических Markdown-файлов: $($canonicalMarkdown.Count)."
exit 0
