[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$Report,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
$script:knowledgeModuleBootstrapComplete = $false
trap {
    if (-not $script:knowledgeModuleBootstrapComplete -and
        [string]::IsNullOrWhiteSpace([string]$MyInvocation.ScriptName)) {
        [Console]::Error.WriteLine('ERROR: trusted knowledge helper module не прошел integrity/load check.')
        exit 1
    }
    if ($SelfTest -and $script:knowledgeModuleBootstrapComplete) {
        Write-Host "SELFTEST ERROR: $(Convert-ToSafeDiagnostic -Text ([string]$_.Exception.Message))"
    }
    throw
}
$script:verificationRoot = ''
$script:currentIssues = $null
$script:currentReport = $null
$script:pathComparison = if (
    [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )
) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}
$script:pathComparer = if ($script:pathComparison -eq [System.StringComparison]::OrdinalIgnoreCase) {
    [System.StringComparer]::OrdinalIgnoreCase
}
else {
    [System.StringComparer]::Ordinal
}
$maxEvidenceFileBytes = 16MB
$maxEvidenceLineChars = 262144
$maxEvidenceRecordsPerFile = 10000
$maxEvidenceLedgers = 1000
$maxEvidenceRecordsTotal = 100000
$maxEvidenceCorpusBytes = 128MB
$maxTextFileBytes = 4MB
$maxTextCorpusBytes = 128MB
$maxTextFiles = 10000
$maxGitHeadBlobBytes = 512KB
$maxGitTreeEntries = 10000
$maxGitTreeOutputChars = 4MB
$maxResearchDecisionFiles = 1000
$maxResearchDecisionTokensPerFile = 20000
$maxResearchDecisionTokensTotal = 200000
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$script:textReadPaths = $null
$script:textReadCorpusBytes = [long]0

$candidateFields = @(
    'id',
    'state',
    'type',
    'owner_scope',
    'domain',
    'claim_key',
    'target_ref',
    'source_refs',
    'conflict_refs',
    'confidence',
    'capture_basis',
    'data_class',
    'created_at',
    'review_due',
    'authority_ref',
    'applied_at',
    'dismiss_reason',
    'supersedes'
)
$candidateOptionalMethodFields = @(
    'method_kind',
    'method_summary',
    'method_applies_to'
)
$candidateAllowedFields = @($candidateFields + $candidateOptionalMethodFields)
$candidateScalarFields = @(
    'id',
    'state',
    'type',
    'owner_scope',
    'domain',
    'claim_key',
    'target_ref',
    'confidence',
    'capture_basis',
    'data_class',
    'created_at',
    'review_due',
    'authority_ref',
    'applied_at',
    'dismiss_reason',
    'supersedes'
)
$candidateOptionalMethodScalarFields = @('method_kind', 'method_summary')
$candidateNullableScalarFields = @(
    'review_due',
    'applied_at',
    'dismiss_reason',
    'supersedes'
)
$projectScalarFields = @(
    'repository_kind',
    'project_status',
    'project_id',
    'knowledge_contract_version',
    'knowledge_capture_mode'
)
$rawFields = @(
    'id',
    'captured_at',
    'storage_basis',
    'authority_ref',
    'data_class',
    'content_mode',
    'personal_data',
    'retention',
    'source',
    'rights',
    'author',
    'scope',
    'status',
    'related'
)
$rawScalarFields = @(
    'id',
    'captured_at',
    'storage_basis',
    'authority_ref',
    'data_class',
    'content_mode',
    'personal_data',
    'retention',
    'source',
    'rights',
    'author',
    'scope',
    'status'
)
$rawNullableScalarFields = @(
    'id',
    'captured_at',
    'author',
    'scope',
    'storage_basis',
    'authority_ref'
)

$evidenceFields = @(
    'evidence_id',
    'claim_id',
    'claim',
    'claim_type',
    'stance',
    'source_url',
    'source_title',
    'publisher',
    'source_type',
    'published_at',
    'accessed_at',
    'locator',
    'observation',
    'directness',
    'origin_group_id',
    'original_source_url',
    'syndication_or_quote_of',
    'dataset_origin',
    'content_fingerprint',
    'geography',
    'time_scope',
    'limitations',
    'participant_code',
    'prompt_injection_detected'
)

function Add-Issue {
    param([Parameter(Mandatory = $true)][string]$Message)
    $script:currentIssues.Add($Message) | Out-Null
}

function Add-ReportItem {
    param(
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $script:currentReport[$Category].Add($Value) | Out-Null
}

function Get-RelativePath {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    if ($full.Equals($script:verificationRoot, $script:pathComparison)) {
        return ''
    }
    if (-not $full.StartsWith(
        $script:verificationRoot + [System.IO.Path]::DirectorySeparatorChar,
        $script:pathComparison
    )) {
        return $null
    }
    return $full.Substring($script:verificationRoot.Length + 1).Replace('\', '/')
}

function Test-PathWithinRoot {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    if ($script:knowledgeModuleBootstrapComplete) {
        return (& $script:mpkTestPathWithinRoot -Root $script:verificationRoot -Path $AbsolutePath)
    }
    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    return (
        $full.Equals($script:verificationRoot, $script:pathComparison) -or
        $full.StartsWith(
            $script:verificationRoot + [System.IO.Path]::DirectorySeparatorChar,
            $script:pathComparison
        )
    )
}

function Get-ReparsePointInPath {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    if ($script:knowledgeModuleBootstrapComplete) {
        try { return (& $script:mpkGetReparsePointInFullChain -Root $script:verificationRoot -Path $AbsolutePath) } catch { return $null }
    }
    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    if (-not (Test-PathWithinRoot $full)) { return $null }

    $current = $script:verificationRoot
    if (Test-Path -LiteralPath $current) {
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $current
        }
    }

    $relative = Get-RelativePath $full
    foreach ($segment in (($relative -split '/') | Where-Object { $_ -ne '' })) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { break }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $current
        }
    }
    return $null
}

function Get-ReparsePointInFullChain {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    $pathRoot = [System.IO.Path]::GetPathRoot($full)
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

$trustedKnowledgeScriptsRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char[]]'\/')
$trustedKnowledgeLibRoot = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($trustedKnowledgeScriptsRoot, 'lib')
)
$trustedKnowledgeModulePath = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($trustedKnowledgeLibRoot, 'ModelProject.Knowledge.psm1')
)
$knowledgeModuleIntegrityError = 'Trusted knowledge helper module failed integrity/load check.'
$trustedPlatformModulePath = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($trustedKnowledgeLibRoot, 'ModelProject.Platform.psm1')
)
if (-not [System.IO.File]::Exists($trustedPlatformModulePath) -or
    $null -ne (Get-ReparsePointInFullChain $trustedPlatformModulePath) -or
    @([System.IO.Directory]::EnumerateFiles($trustedKnowledgeLibRoot) | Where-Object {
        [System.IO.Path]::GetFileName($_) -ceq 'ModelProject.Platform.psm1'
    }).Count -ne 1) {
    throw $knowledgeModuleIntegrityError
}
try {
    $trustedPlatformModule = Microsoft.PowerShell.Core\Import-Module `
        -Name $trustedPlatformModulePath `
        -Scope Local `
        -Force `
        -PassThru `
        -ErrorAction Stop
}
catch { throw $knowledgeModuleIntegrityError }
$trustedPlatformExportNames = @(
    'Get-ModelProjectNormalizedFullPath', 'Resolve-ModelProjectFileSystemLinkPath',
    'Test-ModelProjectIsWindows', 'Test-ModelProjectIsMacOS',
    'Get-ModelProjectNullDevice', 'Get-ModelProjectPathComparison', 'Test-ModelProjectPathWithinRoot',
    'Get-ModelProjectLinkInFullChain', 'Assert-ModelProjectNoLinkInFullChain',
    'Get-ModelProjectTrustedApplication', 'Get-ModelProjectGitExecutable', 'Get-ModelProjectPowerShellHost',
    'Set-ModelProjectSanitizedGitEnvironment', 'Invoke-ModelProjectProcess', 'Assert-ModelProjectInputText',
    'Enter-ModelProjectFileLock', 'Exit-ModelProjectFileLock'
)
if ($null -eq $trustedPlatformModule -or
    $trustedPlatformModule.ExportedCommands.Count -ne $trustedPlatformExportNames.Count -or
    -not [System.IO.Path]::GetFullPath([string]$trustedPlatformModule.Path).Equals(
        $trustedPlatformModulePath,
        $script:pathComparison
    )) {
    throw $knowledgeModuleIntegrityError
}
$trustedPlatformCommands = @{}
foreach ($commandName in $trustedPlatformExportNames) {
    $command = $trustedPlatformModule.ExportedCommands[$commandName]
    if ($null -eq $command -or
        $command.CommandType -ne [System.Management.Automation.CommandTypes]::Function -or
        $null -eq $command.Module -or
        -not [System.IO.Path]::GetFullPath([string]$command.Module.Path).Equals(
            $trustedPlatformModulePath,
            $script:pathComparison
        )) {
        throw $knowledgeModuleIntegrityError
    }
    $trustedPlatformCommands[$commandName] = $command
}
$script:mppGetGitExecutable = $trustedPlatformCommands['Get-ModelProjectGitExecutable']
$script:mppGetPowerShellHost = $trustedPlatformCommands['Get-ModelProjectPowerShellHost']
$script:mppGetNullDevice = $trustedPlatformCommands['Get-ModelProjectNullDevice']
$script:mppGetPathComparison = $trustedPlatformCommands['Get-ModelProjectPathComparison']
$script:mppResolveFileSystemLinkPath = $trustedPlatformCommands['Resolve-ModelProjectFileSystemLinkPath']
$script:mppIsWindows = $trustedPlatformCommands['Test-ModelProjectIsWindows']
$script:mppSetGitEnvironment = $trustedPlatformCommands['Set-ModelProjectSanitizedGitEnvironment']
$script:nullDevice = & $script:mppGetNullDevice
$script:pathComparison = & $script:mppGetPathComparison -Path $trustedKnowledgeScriptsRoot
$script:pathComparer = if ($script:pathComparison -eq [System.StringComparison]::OrdinalIgnoreCase) {
    [System.StringComparer]::OrdinalIgnoreCase
}
else {
    [System.StringComparer]::Ordinal
}
if (-not [System.IO.Path]::GetDirectoryName($trustedKnowledgeLibRoot).Equals(
        $trustedKnowledgeScriptsRoot,
        $script:pathComparison
    ) -or
    -not [System.IO.Path]::GetDirectoryName($trustedKnowledgeModulePath).Equals(
        $trustedKnowledgeLibRoot,
        $script:pathComparison
    ) -or
    -not [System.IO.Directory]::Exists($trustedKnowledgeLibRoot) -or
    -not [System.IO.File]::Exists($trustedKnowledgeModulePath) -or
    $null -ne (Get-ReparsePointInFullChain $trustedKnowledgeModulePath)) {
    throw $knowledgeModuleIntegrityError
}
$exactKnowledgeLib = $false
foreach ($candidateDirectory in [System.IO.Directory]::EnumerateDirectories($trustedKnowledgeScriptsRoot)) {
    if ([System.IO.Path]::GetFileName($candidateDirectory) -ceq 'lib') {
        $exactKnowledgeLib = $true
        break
    }
}
$exactKnowledgeModule = $false
foreach ($candidateFile in [System.IO.Directory]::EnumerateFiles($trustedKnowledgeLibRoot)) {
    if ([System.IO.Path]::GetFileName($candidateFile) -ceq 'ModelProject.Knowledge.psm1') {
        $exactKnowledgeModule = $true
        break
    }
}
if (-not $exactKnowledgeLib -or -not $exactKnowledgeModule) {
    throw $knowledgeModuleIntegrityError
}
try {
    $trustedKnowledgeModules = @(
        Microsoft.PowerShell.Core\Import-Module `
            -Name $trustedKnowledgeModulePath `
            -Scope Local `
            -Force `
            -PassThru `
            -ErrorAction Stop
    )
}
catch {
    throw $knowledgeModuleIntegrityError
}
if ($trustedKnowledgeModules.Count -ne 1 -or
    [string]::IsNullOrWhiteSpace([string]$trustedKnowledgeModules[0].Path) -or
    -not [System.IO.Path]::GetFullPath([string]$trustedKnowledgeModules[0].Path).Equals(
        $trustedKnowledgeModulePath,
        $script:pathComparison
    )) {
    throw $knowledgeModuleIntegrityError
}
$trustedKnowledgeModule = $trustedKnowledgeModules[0]
$trustedKnowledgeExportNames = @(
    'Test-ModelProjectFrontMatterScalarValue',
    'ConvertFrom-ModelProjectSimpleYamlScalar',
    'Read-ModelProjectSimpleFrontMatterDocument',
    'Test-ModelProjectJsonScalar',
    'ConvertTo-ModelProjectPercentDecodedText',
    'Get-ModelProjectHttpsUrlSafetyFinding',
    'Get-ModelProjectHttpsUrlsFromText',
    'Get-ModelProjectSensitiveTextFindings',
    'Remove-ModelProjectCommonMarkContainerPrefixes',
    'Test-ModelProjectMarkdownEscaped',
    'Get-ModelProjectMarkdownLinkOpenerIndex',
    'Test-ModelProjectInlineMarkdownClosure',
    'Test-ModelProjectPathWithinRoot',
    'Get-ModelProjectReparsePointInFullChain',
    'Get-ModelProjectRepositoryRelativePath',
    'Test-ModelProjectExactPathCase',
    'Read-ModelProjectBoundedUtf8File',
    'ConvertTo-ModelProjectMarkdownAnchor',
    'Test-ModelProjectMarkdownAnchorExists',
    'Resolve-ModelProjectSafeReference'
)
if ($trustedKnowledgeModule.ExportedCommands.Count -ne $trustedKnowledgeExportNames.Count) {
    throw $knowledgeModuleIntegrityError
}
$trustedKnowledgeCommands = @{}
foreach ($commandName in $trustedKnowledgeExportNames) {
    $command = $trustedKnowledgeModule.ExportedCommands[$commandName]
    if ($null -eq $command -or
        $command.Name -cne $commandName -or
        $command.CommandType -ne [System.Management.Automation.CommandTypes]::Function -or
        $null -eq $command.Module -or
        [string]::IsNullOrWhiteSpace([string]$command.Module.Path) -or
        -not [System.IO.Path]::GetFullPath([string]$command.Module.Path).Equals(
            $trustedKnowledgeModulePath,
            $script:pathComparison
        )) {
        throw $knowledgeModuleIntegrityError
    }
    $trustedKnowledgeCommands[$commandName] = $command
}
$script:mpkTestFrontMatterScalarValue = $trustedKnowledgeCommands['Test-ModelProjectFrontMatterScalarValue']
$script:mpkTestJsonScalar = $trustedKnowledgeCommands['Test-ModelProjectJsonScalar']
$script:mpkConvertPercentDecodedText = $trustedKnowledgeCommands['ConvertTo-ModelProjectPercentDecodedText']
$script:mpkGetHttpsUrlSafetyFinding = $trustedKnowledgeCommands['Get-ModelProjectHttpsUrlSafetyFinding']
$script:mpkGetHttpsUrlsFromText = $trustedKnowledgeCommands['Get-ModelProjectHttpsUrlsFromText']
$script:mpkGetSensitiveTextFindings = $trustedKnowledgeCommands['Get-ModelProjectSensitiveTextFindings']
$script:mpkRemoveCommonMarkContainerPrefixes = $trustedKnowledgeCommands['Remove-ModelProjectCommonMarkContainerPrefixes']
$script:mpkTestMarkdownEscaped = $trustedKnowledgeCommands['Test-ModelProjectMarkdownEscaped']
$script:mpkGetMarkdownLinkOpenerIndex = $trustedKnowledgeCommands['Get-ModelProjectMarkdownLinkOpenerIndex']
$script:mpkTestInlineMarkdownClosure = $trustedKnowledgeCommands['Test-ModelProjectInlineMarkdownClosure']
$script:mpkTestPathWithinRoot = $trustedKnowledgeCommands['Test-ModelProjectPathWithinRoot']
$script:mpkGetReparsePointInFullChain = $trustedKnowledgeCommands['Get-ModelProjectReparsePointInFullChain']
$script:mpkGetRepositoryRelativePath = $trustedKnowledgeCommands['Get-ModelProjectRepositoryRelativePath']
$script:mpkTestExactPathCase = $trustedKnowledgeCommands['Test-ModelProjectExactPathCase']
$script:mpkReadBoundedUtf8File = $trustedKnowledgeCommands['Read-ModelProjectBoundedUtf8File']
$script:mpkConvertMarkdownAnchor = $trustedKnowledgeCommands['ConvertTo-ModelProjectMarkdownAnchor']
$script:mpkTestMarkdownAnchorExists = $trustedKnowledgeCommands['Test-ModelProjectMarkdownAnchorExists']
$script:mpkResolveSafeReference = $trustedKnowledgeCommands['Resolve-ModelProjectSafeReference']
$script:knowledgeModuleBootstrapComplete = $true

function Read-BoundedUtf8Text {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Context,
        [long]$MaxBytes = 0
    )

    try {
        $full = [System.IO.Path]::GetFullPath($FilePath)
    }
    catch {
        Add-Issue "$Context`: путь невозможно нормализовать."
        return $null
    }
    if (-not (Test-PathWithinRoot $full)) {
        Add-Issue "$Context`: чтение выходит за корень репозитория."
        return $null
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        Add-Issue "$Context`: файл отсутствует."
        return $null
    }
    $reparse = Get-ReparsePointInPath $full
    if ($null -ne $reparse) {
        Add-Issue "$Context`: чтение проходит через reparse point: $(Get-RelativePath $reparse)"
        return $null
    }

    $file = Get-Item -LiteralPath $full -Force
    $effectiveLimit = if ($MaxBytes -gt 0) { [Math]::Min([long]$MaxBytes, [long]$maxTextFileBytes) } else { [long]$maxTextFileBytes }
    if ($file.Length -gt $effectiveLimit) {
        Add-Issue "$Context`: text file превышает limit $effectiveLimit bytes."
        return $null
    }
    if (-not $script:textReadPaths.Contains($full)) {
        if (($script:textReadPaths.Count + 1) -gt $maxTextFiles) {
            Add-Issue "Text corpus превышает file-count limit $maxTextFiles."
            return $null
        }
        if (($script:textReadCorpusBytes + $file.Length) -gt $maxTextCorpusBytes) {
            Add-Issue "Text corpus превышает byte limit $maxTextCorpusBytes."
            return $null
        }
        $script:textReadPaths.Add($full) | Out-Null
        $script:textReadCorpusBytes += $file.Length
    }

    $reparse = Get-ReparsePointInPath $full
    if ($null -ne $reparse) {
        Add-Issue "$Context`: чтение проходит через reparse point непосредственно перед чтением: $(Get-RelativePath $reparse)"
        return $null
    }
    try {
        return (& $script:mpkReadBoundedUtf8File -Root $script:verificationRoot -Path $full -MaxBytes $effectiveLimit)
    }
    catch {
        Add-Issue "$Context`: файл не удалось прочитать как строгий UTF-8: $($_.Exception.Message)"
        return $null
    }
}

function Test-ExactPathCase {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    return (& $script:mpkTestExactPathCase -Root $script:verificationRoot -Path $AbsolutePath)
}

function Convert-FrontMatterScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Raw,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $value = $Raw.Trim()
    if ($value -ceq 'null') { return $null }
    if ($value -ceq '[]') { return ,@() }
    if ($value.Length -ge 2 -and $value[0] -eq "'" -and $value[$value.Length - 1] -eq "'") {
        return $value.Substring(1, $value.Length - 2).Replace("''", "'")
    }
    if ($value.Length -ge 2 -and $value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') {
        try {
            return ($value | ConvertFrom-Json)
        }
        catch {
            Add-Issue "$Context`: некорректная quoted-строка frontmatter."
            return $value
        }
    }
    if ($value.StartsWith('[') -or $value.StartsWith('{') -or $value.StartsWith('|') -or $value.StartsWith('>')) {
        Add-Issue "$Context`: поддерживаются только простые scalars и block-sequences."
    }
    return $value
}

function Read-FrontMatterDocument {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $relative = Get-RelativePath $FilePath
    $text = Read-BoundedUtf8Text -FilePath $FilePath -Context $relative
    if ($null -eq $text) { return $null }
    if ($text.IndexOf([char]0) -ge 0) {
        Add-Issue "$relative`: файл содержит NUL."
    }

    $lines = @($text -split "\r?\n")
    if ($lines.Count -lt 3 -or $lines[0].Trim() -cne '---') {
        Add-Issue "$relative`: отсутствует YAML frontmatter."
        return [pscustomobject]@{ Data = @{}; Body = $text; Text = $text }
    }

    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ceq '---') {
            $end = $i
            break
        }
    }
    if ($end -lt 0) {
        Add-Issue "$relative`: frontmatter не закрыт."
        return [pscustomobject]@{ Data = @{}; Body = ''; Text = $text }
    }

    $data = @{}
    for ($i = 1; $i -lt $end; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^([a-z_][a-z0-9_]*):(?:\s*(.*))?$') {
            Add-Issue "$relative`:$($i + 1): неподдерживаемая строка frontmatter."
            continue
        }
        $key = $Matches[1]
        $raw = $Matches[2]
        if ($data.ContainsKey($key)) {
            Add-Issue "$relative`:$($i + 1): поле '$key' повторяется."
            continue
        }
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $items = [System.Collections.Generic.List[string]]::new()
            while (($i + 1) -lt $end -and $lines[$i + 1] -match '^\s{2}-\s+(.+?)\s*$') {
                $i++
                $item = Convert-FrontMatterScalar -Raw $Matches[1] -Context "$relative`:$($i + 1)"
                if ($null -eq $item -or $item -is [System.Array]) {
                    Add-Issue "$relative`:$($i + 1): список '$key' содержит некорректное значение."
                }
                else {
                    $items.Add([string]$item)
                }
            }
            if ($items.Count -gt 0) {
                $data[$key] = [string[]]$items.ToArray()
            }
            else {
                $data[$key] = $null
            }
        }
        else {
            $data[$key] = Convert-FrontMatterScalar -Raw $raw -Context "$relative`:$($i + 1)"
        }
    }

    $body = if (($end + 1) -lt $lines.Count) {
        ($lines[($end + 1)..($lines.Count - 1)] -join "`n")
    }
    else {
        ''
    }
    return [pscustomobject]@{ Data = $data; Body = $body; Text = $text }
}

function Test-IsNullValue {
    param($Value)
    return ($null -eq $Value -or ([string]$Value).Trim() -ceq '')
}

function Test-DateOnly {
    param([string]$Value)
    $parsed = [datetime]::MinValue
    return [datetime]::TryParseExact(
        $Value,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
}

function Test-DateTimeOffsetValue {
    param([string]$Value)
    $parsed = [System.DateTimeOffset]::MinValue
    return [System.DateTimeOffset]::TryParse(
        $Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )
}

function Get-DateTimeOffsetOrNull {
    param([string]$Value)

    $parsed = [System.DateTimeOffset]::MinValue
    if (-not [System.DateTimeOffset]::TryParse(
        $Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )) {
        return $null
    }
    return $parsed
}

function Convert-ToAnchor {
    param([string]$Heading)
    return (& $script:mpkConvertMarkdownAnchor -Heading $Heading)
}

function Test-MarkdownAnchor {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Anchor
    )

    if ([string]::IsNullOrWhiteSpace($Anchor)) { return $true }
    if ([System.IO.Path]::GetExtension($FilePath) -ine '.md') { return $false }
    try {
        $wanted = Convert-ToAnchor ([System.Uri]::UnescapeDataString($Anchor))
    }
    catch {
        return $false
    }

    $text = Read-BoundedUtf8Text -FilePath $FilePath -Context "Markdown anchor source '$(Get-RelativePath $FilePath)'"
    if ($null -eq $text) { return $false }
    $seen = @{}
    foreach ($line in @($text -split "\r?\n")) {
        if ($line -notmatch '^ {0,3}#{1,6}[ \t]+(.+?)\s*#*\s*$') { continue }
        $base = Convert-ToAnchor $Matches[1]
        $count = if ($seen.ContainsKey($base)) { [int]$seen[$base] } else { 0 }
        $actual = if ($count -eq 0) { $base } else { "$base-$count" }
        $seen[$base] = $count + 1
        if ($actual -ceq $wanted) { return $true }
    }
    return $false
}

function Get-UnsafeMarkdownUriKinds {
    param([Parameter(Mandatory = $true)][string]$Text)

    $scanText = Get-CommonMarkVisibleText $Text
    $destinations = [System.Collections.Generic.List[string]]::new()
    $findings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($link in (Get-InlineMarkdownLinks -Text $scanText)) {
        if (-not $link.Valid) {
            $findings.Add('ambiguous-markdown-link') | Out-Null
            continue
        }
        $destinations.Add($link.Target) | Out-Null
    }
    $definitionPattern = '(?m)^ {0,3}\[(?:\\[^\r\n]|[^\]\\\r\n])+\]:'
    foreach ($match in [regex]::Matches($scanText, $definitionPattern)) {
        if (& $script:mpkTestMarkdownEscaped -Text $scanText -Index $match.Index) { continue }
        $destination = Get-MarkdownDestination -Content $scanText -StartIndex ($match.Index + $match.Length)
        if ($null -eq $destination -or -not $destination.Balanced) {
            $findings.Add('ambiguous-markdown-link') | Out-Null
            continue
        }
        $destinations.Add($destination.Target) | Out-Null
    }
    foreach ($match in [regex]::Matches(
        $scanText,
        '(?is)<(?<dest>(?:[A-Za-z][A-Za-z0-9+.-]*:|//)[^<>\r\n]*)>'
    )) {
        if (& $script:mpkTestMarkdownEscaped -Text $scanText -Index $match.Index) { continue }
        $destinations.Add($match.Groups['dest'].Value) | Out-Null
    }

    foreach ($destinationValue in $destinations) {
        $destination = $destinationValue.Trim()
        if ($destination.StartsWith('<') -and $destination.EndsWith('>')) {
            $destination = $destination.Substring(1, $destination.Length - 2)
        }
        $destination = & $script:mpkConvertPercentDecodedText -Value $destination
        $destination = $destination -replace '\\([!#$%&''()*+,\-./:;<=>?@\[\]^_`{|}~])', '$1'
        $destination = $destination.Trim()
        if ($destination.StartsWith('//', [System.StringComparison]::Ordinal)) {
            $findings.Add('protocol-relative-uri') | Out-Null
        }
        elseif ($destination -match '^(?i)(?<scheme>[A-Za-z][A-Za-z0-9+.-]*):' -and
            $Matches['scheme'] -ine 'https') {
            $findings.Add('dangerous-markdown-uri') | Out-Null
        }
    }
    return @($findings)
}

function Get-UnsafeFindings {
    param([Parameter(Mandatory = $true)][string]$Text)

    $findings = [System.Collections.Generic.List[string]]::new()
    foreach ($finding in (& $script:mpkGetSensitiveTextFindings -Text $Text)) {
        if (-not $findings.Contains([string]$finding)) {
            $findings.Add([string]$finding) | Out-Null
        }
    }
    if ($Text -match '(?:^|[\s(\x27\x22])\.\.[\\/]' -and
        -not $findings.Contains('path-traversal')) {
        $findings.Add('path-traversal') | Out-Null
    }
    if ($Text -match '(?is)<!--.*?(?:-->|$)|<\s*/?\s*[A-Za-z][A-Za-z0-9-]*(?:[ \t\r\n]+[^<>]*?)?\s*/?\s*>|<![A-Za-z][^<>]*>|<\?[^<>]*\?>') {
        $findings.Add('raw-html') | Out-Null
    }
    foreach ($finding in (Get-UnsafeMarkdownUriKinds $Text)) {
        if (-not $findings.Contains($finding)) { $findings.Add($finding) | Out-Null }
    }
    return @($findings)
}

function Convert-ToSafeDiagnostic {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $findings = @(Get-UnsafeFindings $Text)
    if ($findings.Count -gt 0) {
        return "Диагностика скрыта: небезопасное значение repository data ($($findings[0]))."
    }
    return $Text
}

function Get-SensitiveDataFindings {
    param([Parameter(Mandatory = $true)][string]$Text)
    return @(& $script:mpkGetSensitiveTextFindings -Text $Text)
}

function Resolve-SafeReference {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [switch]$AllowExternal,
        [switch]$AllowLogical,
        [switch]$MustExist
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -ne $Value.Trim() -or $Value -match "[`r`n`0]") {
        Add-Issue "$Context`: пустая ссылка, перенос строки или внешние пробелы."
        return $null
    }

    if ($Value -match '^(?i:https://)') {
        if (-not $AllowExternal) {
            Add-Issue "$Context`: внешний URL недопустим."
            return $null
        }
        switch (& $script:mpkGetHttpsUrlSafetyFinding -Value $Value) {
            'invalid-https-url' {
                Add-Issue "$Context`: некорректный HTTPS URL."
                return $null
            }
            'https-url-userinfo' {
                Add-Issue "$Context`: HTTPS URL содержит запрещенный userinfo."
                return $null
            }
            'signed-url' {
                Add-Issue "$Context`: потенциально подписанный URL или credential в query."
            }
        }
        return [pscustomobject]@{ Kind = 'external'; FullPath = $null; Fragment = '' }
    }
    if ($Value -cmatch '^logical:shared-mastery/') {
        Add-Issue "$Context`: blocked: shared-owner."
        return $null
    }
    if ($AllowLogical -and (
        $Value -ceq 'policy:knowledge-contract-v1' -or
        $Value -match '^(?:urn|logical|doi|isbn|source|task|user-request|evidence):[A-Za-z0-9][A-Za-z0-9._:/-]*$' -or
        $Value -match '^KC-\d{8}-\d{6}-[0-9a-f]{8}$'
    )) {
        return [pscustomobject]@{ Kind = 'logical'; FullPath = $null; Fragment = '' }
    }
    if ($Value -match '^(?i:[A-Za-z][A-Za-z0-9+.-]*:|//)') {
        Add-Issue "$Context`: неподдерживаемая внешняя ссылка или URI scheme."
        return $null
    }

    if ($Value.Contains('\')) {
        Add-Issue "$Context`: используй '/' вместо '\'."
        return $null
    }
    if ($Value -match '^(?:[A-Za-z]:|/|~[/\\]|file:|\\\\)' -or [System.IO.Path]::IsPathRooted($Value)) {
        Add-Issue "$Context`: абсолютный локальный путь запрещен."
        return $null
    }
    if ($Value.Contains('?') -or ([regex]::Matches($Value, '#').Count -gt 1)) {
        Add-Issue "$Context`: query или несколько fragments недопустимы."
        return $null
    }

    $parts = $Value.Split('#', 2)
    $pathPart = $parts[0]
    $fragment = if ($parts.Count -eq 2) { $parts[1] } else { '' }
    try {
        $decodedPath = [System.Uri]::UnescapeDataString($pathPart)
    }
    catch {
        Add-Issue "$Context`: некорректное percent-encoding."
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($decodedPath) -or
        $decodedPath -match '(^|/)\.{1,2}(/|$)' -or
        $decodedPath.Contains(':') -or
        $decodedPath.Contains('//')) {
        Add-Issue "$Context`: traversal или недопустимый относительный путь."
        return $null
    }

    $resolverSource = Join-Path $script:verificationRoot 'PROJECT.md'
    try { $commonResult = & $script:mpkResolveSafeReference -Root $script:verificationRoot -SourcePath $resolverSource -Reference $Value -ReferenceBase Repository }
    catch { $commonResult = $null }
    if ($null -ne $commonResult -and [string]$commonResult.Error -ceq 'reparse-point') {
        Add-Issue "$Context`: путь проходит через reparse point."
        return $null
    }
    if ($null -eq $commonResult -or -not [string]::IsNullOrWhiteSpace([string]$commonResult.Error) -or $commonResult.Kind -cne 'internal') {
        Add-Issue "$Context`: путь невозможно безопасно разрешить."
        return $null
    }
    $absolute = [string]$commonResult.FullPath
    if ($MustExist) {
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
            Add-Issue "$Context`: отсутствующий файл: $decodedPath"
            return [pscustomobject]@{ Kind = 'internal'; FullPath = $absolute; Fragment = $fragment }
        }
        if (-not (Test-ExactPathCase $absolute)) {
            Add-Issue "$Context`: неверный регистр пути: $decodedPath"
        }
        if (-not [string]::IsNullOrWhiteSpace($fragment) -and -not (Test-MarkdownAnchor -FilePath $absolute -Anchor $fragment)) {
            Add-Issue "$Context`: отсутствующий Markdown anchor в $decodedPath."
        }
    }
    return [pscustomobject]@{ Kind = 'internal'; FullPath = $absolute; Fragment = $fragment }
}

function Test-CandidateAuthorityReference {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($Value -ceq 'policy:knowledge-contract-v1' -or
        $Value -cmatch '^user-request:[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        return $true
    }
    if ($Value -cnotmatch '^docs/decisions/(?!README\.md$|TEMPLATE\.md$)[A-Za-z0-9][A-Za-z0-9._/-]*\.md$') {
        Add-Issue "$Context`: invalid authority_ref grammar."
        return $false
    }

    $resolved = Resolve-SafeReference -Value $Value -Context $Context -MustExist
    if ($null -eq $resolved -or $resolved.Kind -ne 'internal' -or
        -not (Test-Path -LiteralPath $resolved.FullPath -PathType Leaf)) {
        return $false
    }
    $authorityDocument = Read-FrontMatterDocument $resolved.FullPath
    if ($null -eq $authorityDocument -or
        -not $authorityDocument.Data.ContainsKey('artifact_kind') -or
        -not $authorityDocument.Data.ContainsKey('status') -or
        [string]$authorityDocument.Data.artifact_kind -cne 'decision' -or
        [string]$authorityDocument.Data.status -cne 'accepted') {
        Add-Issue "$Context`: authority ADR должен иметь artifact_kind decision и status accepted."
        return $false
    }
    return $true
}

function Get-CommonMarkVisibleText {
    param([Parameter(Mandatory = $true)][string]$Text)

    $visibleLines = [System.Collections.Generic.List[string]]::new()
    $inFence = $false
    $fenceCharacter = [char]0
    $fenceLength = 0
    foreach ($line in @($Text -split "\r?\n")) {
        $containerContent = & $script:mpkRemoveCommonMarkContainerPrefixes -Line $line
        if ($inFence) {
            if ($containerContent -match '^ {0,3}(?<fence>`{3,}|~{3,})[ \t]*$') {
                $closingFence = [string]$Matches['fence']
                if ($closingFence[0] -eq $fenceCharacter -and $closingFence.Length -ge $fenceLength) {
                    $inFence = $false
                    $fenceCharacter = [char]0
                    $fenceLength = 0
                }
            }
            $visibleLines.Add('') | Out-Null
            continue
        }

        if ($containerContent -match '^ {0,3}(?<fence>`{3,}|~{3,})(?<info>.*)$') {
            $openingFence = [string]$Matches['fence']
            $infoString = [string]$Matches['info']
            if ($openingFence[0] -eq [char]'`' -and $infoString.Contains('`')) {
                $visibleLines.Add($containerContent) | Out-Null
                continue
            }
            $inFence = $true
            $fenceCharacter = $openingFence[0]
            $fenceLength = $openingFence.Length
            $visibleLines.Add('') | Out-Null
            continue
        }
        if ($containerContent -match '^(?: {4}|\t)') {
            $visibleLines.Add('') | Out-Null
            continue
        }
        $visibleLines.Add($containerContent) | Out-Null
    }

    $visible = $visibleLines -join "`n"
    $maskPreservingLines = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return [regex]::Replace($match.Value, '[^\r\n]', ' ')
    }
    $visible = [regex]::Replace(
        $visible,
        '(?s)<!--.*?(?:-->|$)',
        $maskPreservingLines
    )
    return [regex]::Replace(
        $visible,
        '(?s)(?<ticks>`+)(?!`).*?(?<!`)\k<ticks>(?!`)',
        $maskPreservingLines
    )
}

function Get-TopLevelMarkdownVisibleText {
    param([Parameter(Mandatory = $true)][string]$Text)

    $visibleLines = [System.Collections.Generic.List[string]]::new()
    $inFence = $false
    $fenceCharacter = [char]0
    $fenceLength = 0
    foreach ($line in @($Text -split "\r?\n")) {
        if ($inFence) {
            if ($line -match '^ {0,3}(?<fence>`{3,}|~{3,})[ \t]*$') {
                $closingFence = [string]$Matches['fence']
                if ($closingFence[0] -eq $fenceCharacter -and $closingFence.Length -ge $fenceLength) {
                    $inFence = $false
                    $fenceCharacter = [char]0
                    $fenceLength = 0
                }
            }
            $visibleLines.Add('') | Out-Null
            continue
        }
        if ($line -match '^ {0,3}(?<fence>`{3,}|~{3,})(?<info>.*)$') {
            $openingFence = [string]$Matches['fence']
            $infoString = [string]$Matches['info']
            if ($openingFence[0] -eq [char]'`' -and $infoString.Contains('`')) {
                $visibleLines.Add($line) | Out-Null
                continue
            }
            $inFence = $true
            $fenceCharacter = $openingFence[0]
            $fenceLength = $openingFence.Length
            $visibleLines.Add('') | Out-Null
            continue
        }
        if ($line -match '^(?: {4}|\t)') {
            $visibleLines.Add('') | Out-Null
            continue
        }
        $visibleLines.Add($line) | Out-Null
    }

    $visible = $visibleLines -join "`n"
    $maskPreservingLines = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return [regex]::Replace($match.Value, '[^\r\n]', ' ')
    }
    $visible = [regex]::Replace($visible, '(?s)<!--.*?(?:-->|$)', $maskPreservingLines)
    return $visible
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
    if ($cursor -ge $Content.Length) { return $null }

    $targetStart = $cursor
    if ($AllowEmpty -and ($Content[$cursor] -eq ')' -or $Content[$cursor] -eq '"' -or $Content[$cursor] -eq "'")) {
        return [pscustomobject]@{ Target = ''; EndIndex = $targetStart; Balanced = $true }
    }

    if ($Content[$cursor] -eq '<') {
        $cursor++
        while ($cursor -lt $Content.Length) {
            if ($Content[$cursor] -eq "`r" -or $Content[$cursor] -eq "`n") { return $null }
            if ($Content[$cursor] -eq '>' -and -not (& $script:mpkTestMarkdownEscaped -Text $Content -Index $cursor)) {
                return [pscustomobject]@{
                    Target = $Content.Substring($targetStart, $cursor - $targetStart + 1)
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
        $escaped = & $script:mpkTestMarkdownEscaped -Text $Content -Index $cursor
        if (-not $escaped -and ($character -eq ' ' -or $character -eq "`t" -or
            $character -eq "`r" -or $character -eq "`n")) {
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
            return [pscustomobject]@{ Target = ''; EndIndex = $targetStart; Balanced = $true }
        }
        return $null
    }
    return [pscustomobject]@{
        Target = $Content.Substring($targetStart, $cursor - $targetStart)
        EndIndex = $cursor
        Balanced = ($depth -eq 0)
    }
}

function Get-InlineMarkdownLinks {
    param([Parameter(Mandatory = $true)][string]$Text)

    $links = [System.Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches($Text, '\]\(')) {
        if (& $script:mpkTestMarkdownEscaped -Text $Text -Index $match.Index) { continue }
        $openerIndex = & $script:mpkGetMarkdownLinkOpenerIndex -Content $Text -CloseBracketIndex $match.Index
        if ($openerIndex -lt 0) { continue }

        $destination = Get-MarkdownDestination `
            -Content $Text `
            -StartIndex ($match.Index + $match.Length) `
            -AllowEmpty
        $valid = $null -ne $destination -and
            (& $script:mpkTestInlineMarkdownClosure -Content $Text -Destination $destination)
        $isImage = $openerIndex -gt 0 -and
            $Text[$openerIndex - 1] -eq '!' -and
            -not (& $script:mpkTestMarkdownEscaped -Text $Text -Index ($openerIndex - 1))
        $links.Add([pscustomobject]@{
            Valid = $valid
            Target = if ($valid) { [string]$destination.Target } else { '' }
            IsImage = $isImage
            Index = $match.Index
        }) | Out-Null
    }
    return @($links)
}

function Test-MarkdownBacklink {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$CandidatePath
    )

    $text = Read-BoundedUtf8Text -FilePath $TargetPath -Context "Backlink target '$(Get-RelativePath $TargetPath)'"
    if ($null -eq $text) { return $false }
    $text = Get-CommonMarkVisibleText $text
    foreach ($link in (Get-InlineMarkdownLinks -Text $text)) {
        if (-not $link.Valid -or $link.IsImage) { continue }
        $destination = $link.Target.Trim()
        if ($destination.StartsWith('<') -and $destination.EndsWith('>')) {
            $destination = $destination.Substring(1, $destination.Length - 2)
        }
        if ($destination -match '^[a-z][a-z0-9+.-]*:' -or $destination.StartsWith('#')) { continue }
        $pathPart = $destination.Split('#', 2)[0]
        try {
            $decoded = [System.Uri]::UnescapeDataString($pathPart)
            $resolved = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $TargetPath) $decoded))
            if ($resolved.Equals($CandidatePath, $script:pathComparison)) {
                return $true
            }
        }
        catch {
            continue
        }
    }
    return $false
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $textValidation = Read-BoundedUtf8Text -FilePath $FilePath -Context "SHA-256 source '$(Get-RelativePath $FilePath)'"
    if ($null -eq $textValidation) { return $null }
    $reparse = Get-ReparsePointInPath $FilePath
    if ($null -ne $reparse) {
        Add-Issue "SHA-256 source '$(Get-RelativePath $FilePath)' проходит через reparse point непосредственно перед чтением."
        return $null
    }
    $stream = [System.IO.File]::OpenRead($FilePath)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Get-ProjectSectionText {
    param(
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $true)][string]$Heading
    )

    $escapedHeading = [regex]::Escape($Heading)
    $match = [regex]::Match(
        $Body,
        "(?ms)^ {0,3}##[ \t]+$escapedHeading[ \t]*\r?\n(?<content>.*?)(?=^ {0,3}##[ \t]+|\z)"
    )
    if (-not $match.Success) { return $null }
    return $match.Groups['content'].Value
}

function Test-ProjectActivationValue {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $normalized = $Value.Trim().Trim('`').Trim()
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $false }
    if ($normalized -match '\{\{[^}]+\}\}' -or
        $normalized -match 'YYYY-MM-DD' -or
        $normalized -match '(?i)\b(?:todo|tbd)\b' -or
        $normalized -match '\[(?:аудитории|минимальный результат|наблюдаемый сигнал|обоснование)\]' -or
        $normalized -match '^(?i:заполнить после инициализации)\.?$') {
        return $false
    }
    return $true
}

function Get-ProjectBulletValue {
    param(
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $escapedLabel = [regex]::Escape($Label)
    $match = [regex]::Match($Section, "(?m)^ {0,3}-[ \t]+${escapedLabel}:[ \t]*(?<value>[^\r\n]*)$")
    if (-not $match.Success) { return $null }
    return $match.Groups['value'].Value.Trim()
}

function Test-ActiveProjectPassport {
    param(
        [Parameter(Mandatory = $true)]$Document,
        [Parameter(Mandatory = $true)]$Data
    )

    $missing = [System.Collections.Generic.List[string]]::new()
    $projectId = [string]$Data.project_id
    $parsedProjectId = [guid]::Empty
    if (-not [guid]::TryParse($projectId, [ref]$parsedProjectId) -or $parsedProjectId -eq [guid]::Empty) {
        $missing.Add('project_id')
    }

    $passport = Get-ProjectSectionText -Body ([string]$Document.Body) -Heading 'Паспорт'
    if ($null -eq $passport) {
        $missing.Add('passport')
    }
    else {
        $slug = Get-ProjectBulletValue -Section $passport -Label 'Slug'
        $slug = if ($null -eq $slug) { $null } else { $slug.Trim('`') }
        if (-not (Test-ProjectActivationValue $slug) -or $slug -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
            $missing.Add('slug')
        }

        foreach ($field in @(
            @{ Label = 'Описание'; Name = 'description' },
            @{ Label = 'Владелец'; Name = 'owner' }
        )) {
            if (-not (Test-ProjectActivationValue (Get-ProjectBulletValue -Section $passport -Label $field.Label))) {
                $missing.Add($field.Name)
            }
        }

        $stage = Get-ProjectBulletValue -Section $passport -Label 'Стадия'
        if (-not (Test-ProjectActivationValue $stage) -or
            $stage -cnotin @('идея', 'исследование', 'proof of value', 'MVP', 'рост', 'поддержка', 'архив')) {
            $missing.Add('stage')
        }

        $passportDate = (Get-ProjectBulletValue -Section $passport -Label 'Дата последней проверки паспорта')
        if ($null -ne $passportDate) { $passportDate = $passportDate.Trim('`').Trim("'") }
        if (-not (Test-DateOnly $passportDate)) {
            $missing.Add('passport_date')
        }
    }

    foreach ($sectionRule in @(
        @{ Heading = 'Проблема'; Name = 'problem'; Placeholder = 'Кто сталкивается с какой конкретной болью' },
        @{ Heading = 'Проверяемая гипотеза'; Name = 'hypothesis'; Placeholder = 'Если мы дадим \[аудитории\]' }
    )) {
        $section = Get-ProjectSectionText -Body ([string]$Document.Body) -Heading $sectionRule.Heading
        if (-not (Test-ProjectActivationValue $section) -or $section -match $sectionRule.Placeholder) {
            $missing.Add($sectionRule.Name)
        }
    }

    $scope = Get-ProjectSectionText -Body ([string]$Document.Body) -Heading 'Границы'
    if ($null -eq $scope) {
        $missing.Add('scope_in')
        $missing.Add('scope_out')
    }
    else {
        $scopeMatch = [regex]::Match(
            $scope,
            '(?ms)^Входит:[ \t]*\r?\n(?<in>.*?)^Не входит:[ \t]*\r?\n(?<out>.*)\z'
        )
        if (-not $scopeMatch.Success) {
            $missing.Add('scope_in')
            $missing.Add('scope_out')
        }
        else {
            foreach ($scopeRule in @(
                @{ Group = 'in'; Name = 'scope_in' },
                @{ Group = 'out'; Name = 'scope_out' }
            )) {
                $items = @([regex]::Matches($scopeMatch.Groups[$scopeRule.Group].Value, '(?m)^ {0,3}-[ \t]+(?<value>[^\r\n]+)$'))
                $realItems = @($items | Where-Object { Test-ProjectActivationValue $_.Groups['value'].Value })
                if ($realItems.Count -eq 0) { $missing.Add($scopeRule.Name) }
            }
        }
    }

    $criteria = Get-ProjectSectionText -Body ([string]$Document.Body) -Heading 'Критерии успеха и провала'
    foreach ($criterion in @(
        @{ Label = 'Успех'; Name = 'success_criterion' },
        @{ Label = 'Провал'; Name = 'failure_criterion' },
        @{ Label = 'Срок или объем проверки'; Name = 'validation_horizon' },
        @{ Label = 'Кто принимает финальное решение'; Name = 'decision_maker' }
    )) {
        if ($null -eq $criteria -or
            -not (Test-ProjectActivationValue (Get-ProjectBulletValue -Section $criteria -Label $criterion.Label))) {
            $missing.Add($criterion.Name)
        }
    }

    if ($missing.Count -gt 0) {
        $safeNames = @($missing | Sort-Object -Unique) -join ', '
        Add-Issue "PROJECT.md: activation passport не заполнен ($safeNames)."
    }
}

function Test-IsTrustedSelfRoot {
    if ([string]::IsNullOrWhiteSpace($script:verificationRoot)) { return $false }
    $selfRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)).TrimEnd([char[]]'\/')
    return $selfRoot.Equals($script:verificationRoot, $script:pathComparison)
}

function Get-TrustedGitExecutable {
    try { return (& $script:mppGetGitExecutable -ControlledRoots @($script:verificationRoot)) }
    catch { return $null }
}

function Get-TrustedCurrentPowerShellHostPath {
    try { return (& $script:mppGetPowerShellHost -ControlledRoots @($script:verificationRoot)) }
    catch { return $null }
}

function Get-TrustedGitMetadata {
    $gitMetadataPath = Join-Path $script:verificationRoot '.git'
    if (-not (Test-ExactPathCase $gitMetadataPath) -or
        $null -ne (Get-ReparsePointInFullChain $gitMetadataPath)) {
        return $null
    }

    if (Test-Path -LiteralPath $gitMetadataPath -PathType Container) {
        return [pscustomobject]@{
            GitDirectory = [System.IO.Path]::GetFullPath($gitMetadataPath).TrimEnd([char[]]'\/')
            WorkTree = $script:verificationRoot
            IsLinkedWorktree = $false
        }
    }
    if (-not (Test-Path -LiteralPath $gitMetadataPath -PathType Leaf)) {
        return $null
    }

    try {
        $metadataItem = Get-Item -LiteralPath $gitMetadataPath -Force
        if ($metadataItem.Length -lt 9 -or $metadataItem.Length -gt 4096) { return $null }
        $metadataText = [System.IO.File]::ReadAllText($gitMetadataPath, $utf8Strict)
        $match = [regex]::Match($metadataText, '\Agitdir:[ \t]+(?<path>[^\r\n]+)\r?\n?\z')
        if (-not $match.Success) { return $null }
        $gitDirectoryValue = $match.Groups['path'].Value
        if ($gitDirectoryValue -cne $gitDirectoryValue.Trim() -or
            [string]::IsNullOrWhiteSpace($gitDirectoryValue) -or
            $gitDirectoryValue.IndexOf([char]0) -ge 0) {
            return $null
        }
        $gitDirectoryPath = if ([System.IO.Path]::IsPathRooted($gitDirectoryValue)) {
            [System.IO.Path]::GetFullPath($gitDirectoryValue)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $script:verificationRoot $gitDirectoryValue))
        }
        $gitDirectoryPath = $gitDirectoryPath.TrimEnd([char[]]'\/')
        if (-not (Test-Path -LiteralPath $gitDirectoryPath -PathType Container) -or
            $null -ne (Get-ReparsePointInFullChain $gitDirectoryPath)) {
            return $null
        }

        $backlinkPath = Join-Path $gitDirectoryPath 'gitdir'
        if (-not (Test-Path -LiteralPath $backlinkPath -PathType Leaf) -or
            $null -ne (Get-ReparsePointInFullChain $backlinkPath)) {
            return $null
        }
        $backlinkItem = Get-Item -LiteralPath $backlinkPath -Force
        if ($backlinkItem.Name -cne 'gitdir' -or
            $backlinkItem.Length -lt 1 -or
            $backlinkItem.Length -gt 4096) {
            return $null
        }
        $backlinkText = [System.IO.File]::ReadAllText($backlinkPath, $utf8Strict)
        $backlinkMatch = [regex]::Match($backlinkText, '\A(?<path>[^\r\n]+)\r?\n?\z')
        if (-not $backlinkMatch.Success) { return $null }
        $backlinkValue = $backlinkMatch.Groups['path'].Value
        if ($backlinkValue -cne $backlinkValue.Trim() -or
            [string]::IsNullOrWhiteSpace($backlinkValue) -or
            $backlinkValue.IndexOf([char]0) -ge 0) {
            return $null
        }
        $backlinkTarget = if ([System.IO.Path]::IsPathRooted($backlinkValue)) {
            [System.IO.Path]::GetFullPath($backlinkValue)
        }
        else {
            [System.IO.Path]::GetFullPath((Join-Path $gitDirectoryPath $backlinkValue))
        }
        if (-not $backlinkTarget.Equals(
                [System.IO.Path]::GetFullPath($gitMetadataPath),
                $script:pathComparison
            )) {
            return $null
        }

        return [pscustomobject]@{
            GitDirectory = $gitDirectoryPath
            WorkTree = $script:verificationRoot
            IsLinkedWorktree = $true
        }
    }
    catch {
        return $null
    }
}

function Test-TrustedGitMetadataMarker {
    return ($null -ne (Get-TrustedGitMetadata))
}

function Invoke-TrustedGitCommand {
    param(
        [Parameter(Mandatory = $true)][string]$GitPath,
        [Parameter(Mandatory = $true)]$Metadata,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int]$MaxLines = 0,
        [long]$MaxCharacters = 0
    )

    $gitArguments = @(
        "--git-dir=$([string]$Metadata.GitDirectory)",
        "--work-tree=$([string]$Metadata.WorkTree)",
        '-c', 'core.fsmonitor=false',
        '-c', "core.hooksPath=$script:nullDevice",
        '-c', 'core.quotePath=false'
    ) + @($Arguments)
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GitPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $utf8NoBom
    $startInfo.StandardErrorEncoding = $utf8NoBom
    $startInfo.WorkingDirectory = $script:verificationRoot
    foreach ($argument in $gitArguments) {
        if ([string]$argument -match '[\r\n\x00]' -or ([string]$argument).Length -gt 32768) {
            throw 'Trusted Git argument rejected.'
        }
        [void]$startInfo.ArgumentList.Add([string]$argument)
    }
    & $script:mppSetGitEnvironment -Environment $startInfo.Environment

    $lines = [System.Collections.Generic.List[string]]::new()
    [long]$characterCount = 0
    $limitExceeded = $false
    $exitCode = 1
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if ($process.Start()) {
            $stderrTask = $process.StandardError.ReadToEndAsync()
            while (($line = $process.StandardOutput.ReadLine()) -ne $null) {
                $nextCharacterCount = $characterCount + ([string]$line).Length
                if ($lines.Count -gt 0) { $nextCharacterCount++ }
                if (($MaxLines -gt 0 -and ($lines.Count + 1) -gt $MaxLines) -or
                    ($MaxCharacters -gt 0 -and $nextCharacterCount -gt $MaxCharacters)) {
                    $limitExceeded = $true
                    try { $process.Kill() } catch { }
                    break
                }
                $lines.Add([string]$line) | Out-Null
                $characterCount = $nextCharacterCount
            }
            $process.WaitForExit()
            $null = $stderrTask.GetAwaiter().GetResult()
            if (-not $limitExceeded) { $exitCode = $process.ExitCode }
        }
    }
    catch { $exitCode = 1 }
    finally {
        $process.Dispose()
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Lines = @($lines)
        LimitExceeded = $limitExceeded
    }
}

function Test-TrustedGitHead {
    if (-not (Test-IsTrustedSelfRoot)) { return $false }
    $metadata = Get-TrustedGitMetadata
    if ($null -eq $metadata) { return $false }
    $gitPath = Get-TrustedGitExecutable
    if ($null -eq $gitPath) { return $false }
    $result = Invoke-TrustedGitCommand `
        -GitPath $gitPath `
        -Metadata $metadata `
        -Arguments @('rev-parse', '--verify', '--quiet', 'HEAD^{commit}') `
        -MaxLines 1 `
        -MaxCharacters 128
    return (
        -not $result.LimitExceeded -and
        $result.ExitCode -eq 0 -and
        $result.Lines.Count -eq 1 -and
        $result.Lines[0] -cmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$'
    )
}

function Test-TrustedGeneratedProjectBaseline {
    if (-not (Test-TrustedGitHead)) { return $false }

    $currentProjectPath = Join-Path $script:verificationRoot 'PROJECT.md'
    $currentOriginPath = Join-Path $script:verificationRoot 'TEMPLATE-ORIGIN.md'
    if (-not (Test-Path -LiteralPath $currentProjectPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $currentOriginPath -PathType Leaf)) {
        return $false
    }
    $currentProjectText = Read-BoundedUtf8Text -FilePath $currentProjectPath -Context 'PROJECT.md baseline gate'
    $currentOriginText = Read-BoundedUtf8Text -FilePath $currentOriginPath -Context 'TEMPLATE-ORIGIN.md baseline gate'
    $headProjectText = Get-TrustedGitHeadFileText -RelativePath 'PROJECT.md'
    $headOriginText = Get-TrustedGitHeadFileText -RelativePath 'TEMPLATE-ORIGIN.md'
    if ($null -eq $currentProjectText -or $null -eq $currentOriginText -or
        [string]::IsNullOrWhiteSpace($headProjectText) -or
        [string]::IsNullOrWhiteSpace($headOriginText)) {
        return $false
    }

    $currentKind = Get-FrontMatterScalarFromText -Text $currentProjectText -Field 'repository_kind'
    $currentProjectId = Get-FrontMatterScalarFromText -Text $currentProjectText -Field 'project_id'
    $headKind = Get-FrontMatterScalarFromText -Text $headProjectText -Field 'repository_kind'
    $headProjectId = Get-FrontMatterScalarFromText -Text $headProjectText -Field 'project_id'
    if ($currentKind -cne 'generated-project' -or $headKind -cne 'generated-project' -or
        [string]::IsNullOrWhiteSpace($currentProjectId) -or $headProjectId -cne $currentProjectId) {
        return $false
    }
    $currentOriginComparable = $currentOriginText.Replace("`r`n", "`n")
    $headOriginComparable = $headOriginText.Replace("`r`n", "`n")
    if ($currentOriginComparable.EndsWith("`n", [System.StringComparison]::Ordinal)) {
        $currentOriginComparable = $currentOriginComparable.Substring(0, $currentOriginComparable.Length - 1)
    }
    if ($headOriginComparable.EndsWith("`n", [System.StringComparison]::Ordinal)) {
        $headOriginComparable = $headOriginComparable.Substring(0, $headOriginComparable.Length - 1)
    }
    if ($currentOriginComparable -cne $headOriginComparable -or
        $currentOriginComparable -cnotmatch "(?m)^- Project ID: $([regex]::Escape($currentProjectId))\s*$") {
        return $false
    }
    return $true
}

function Test-ProjectContract {
    $projectPath = Join-Path $script:verificationRoot 'PROJECT.md'
    if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
        Add-Issue 'PROJECT.md отсутствует.'
        return
    }
    $document = Read-FrontMatterDocument $projectPath
    if ($null -eq $document) { return }
    $data = $document.Data
    $projectContractShapeValid = $true
    foreach ($field in $projectScalarFields) {
        if (-not $data.ContainsKey($field)) {
            Add-Issue "PROJECT.md: отсутствует обязательное поле '$field'."
            $projectContractShapeValid = $false
            continue
        }
        if (-not (& $script:mpkTestFrontMatterScalarValue -Value $data[$field])) {
            Add-Issue "PROJECT.md: поле '$field' должно быть YAML scalar."
            $projectContractShapeValid = $false
            continue
        }
        if (Test-IsNullValue $data[$field]) {
            Add-Issue "PROJECT.md: отсутствует обязательное поле '$field'."
            $projectContractShapeValid = $false
        }
    }
    if (-not $projectContractShapeValid) { return }

    if ([string]$data.knowledge_contract_version -cne '1') {
        Add-Issue 'PROJECT.md: поддерживается только knowledge_contract_version 1.'
    }
    if ([string]$data.repository_kind -cnotin @('template-source', 'generated-project')) {
        Add-Issue 'PROJECT.md: invalid repository_kind.'
    }
    if ([string]$data.project_status -cnotin @('template', 'initialized', 'active', 'archived')) {
        Add-Issue 'PROJECT.md: invalid project_status.'
    }
    if ([string]$data.knowledge_capture_mode -cnotin @('disabled', 'report-only', 'safe-local')) {
        Add-Issue 'PROJECT.md: invalid knowledge_capture_mode.'
    }

    $tuple = '{0}|{1}|{2}' -f $data.repository_kind, $data.project_status, $data.knowledge_capture_mode
    $validTuples = @(
        'template-source|template|disabled',
        'generated-project|initialized|report-only',
        'generated-project|active|report-only',
        'generated-project|active|safe-local',
        'generated-project|archived|disabled'
    )
    if ($tuple -cnotin $validTuples) {
        Add-Issue 'PROJECT.md: несогласованная пара режима и capture mode.'
    }
    if ([string]$data.repository_kind -ceq 'generated-project' -and [string]$data.project_id -match '\{\{.+\}\}') {
        Add-Issue 'PROJECT.md: generated project содержит placeholder project_id.'
    }
    if ([string]$data.repository_kind -ceq 'generated-project' -and [string]$data.project_status -ceq 'active') {
        Test-ActiveProjectPassport -Document $document -Data $data
    }
    if ([string]$data.repository_kind -ceq 'generated-project' -and
        [string]$data.project_status -ceq 'active' -and
        [string]$data.knowledge_capture_mode -ceq 'safe-local' -and
        -not (Test-TrustedGeneratedProjectBaseline)) {
        Add-Issue 'PROJECT.md: blocked: missing-git-baseline.'
    }
}

function Test-CandidateBody {
    param(
        [Parameter(Mandatory = $true)]$Document,
        [Parameter(Mandatory = $true)][string]$Relative
    )

    $body = [string]$Document.Body
    $allHeadings = @([regex]::Matches($body, '(?m)^ {0,3}(?<marks>#{1,6})[ \t]+(?<text>.+?)\s*$'))
    $h1 = @($allHeadings | Where-Object { $_.Groups['marks'].Value.Length -eq 1 })
    if ($h1.Count -ne 1 -or [string]::IsNullOrWhiteSpace($h1[0].Groups['text'].Value)) {
        Add-Issue "$Relative`: candidate должен иметь ровно один непустой H1 claim."
    }
    if ($allHeadings.Count -ne 5) {
        Add-Issue "$Relative`: candidate должен иметь ровно пять структурных headings без вложенных headings."
    }
    if ($body -match '(?m)^ {0,3}(?:=+|-+)[ \t]*$' -or
        $body -match '(?m)^ {0,3}(?:\*(?:[ \t]*\*){2,}|_(?:[ \t]*_){2,}|-(?:[ \t]*-){2,})[ \t]*$') {
        Add-Issue "$Relative`: Setext headings и horizontal rules внутри candidate запрещены."
    }
    foreach ($heading in @('Основание', 'Предлагаемое изменение', 'Проверка дублей и противоречий', 'Обоснование lifecycle')) {
        $escaped = [regex]::Escape($heading)
        if ($body -notmatch "(?m)^##\s+$escaped\s*$") {
            Add-Issue "$Relative`: отсутствует раздел '## $heading'."
        }
        elseif ($body -notmatch "(?ms)^##\s+$escaped\s*\r?\n\s*(?!##\s|\z)\S.+?(?=^##\s|\z)") {
            Add-Issue "$Relative`: раздел '## $heading' не заполнен."
        }
    }
    foreach ($finding in (Get-UnsafeFindings $Document.Text)) {
        Add-Issue "$Relative`: потенциально небезопасный материал в candidate по эвристическому сигналу ($finding)."
    }
}

function Get-MasteryIntentCatalog {
    if ($script:masteryIntentCatalogLoaded) {
        return [pscustomobject]@{
            Records = @($script:masteryIntentRecords)
            Ids = $script:masteryIntentIds
        }
    }
    $script:masteryIntentCatalogLoaded = $true
    $script:masteryIntentRecords = @()
    $script:masteryIntentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $catalogPath = Join-Path $script:verificationRoot 'mastery/INTENTS.json'
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf) -or
        -not (Test-ExactPathCase $catalogPath) -or
        $null -ne (Get-ReparsePointInPath $catalogPath)) {
        Add-Issue 'mastery/INTENTS.json отсутствует или не прошел path integrity check.'
        return [pscustomobject]@{ Records = @(); Ids = $script:masteryIntentIds }
    }
    $text = Read-BoundedUtf8Text -FilePath $catalogPath -Context 'mastery/INTENTS.json' -MaxBytes 262144
    if ($null -eq $text) {
        return [pscustomobject]@{ Records = @(); Ids = $script:masteryIntentIds }
    }
    try { $catalog = $text | ConvertFrom-Json -ErrorAction Stop }
    catch {
        Add-Issue 'mastery/INTENTS.json содержит некорректный JSON.'
        return [pscustomobject]@{ Records = @(); Ids = $script:masteryIntentIds }
    }
    if ($null -eq $catalog -or $catalog -is [System.Array] -or
        ((@($catalog.PSObject.Properties.Name | Sort-Object) -join ',') -cne 'intents,schema_version') -or
        [string]$catalog.schema_version -cne '1' -or
        -not ($catalog.intents -is [System.Array]) -or
        @($catalog.intents).Count -eq 0 -or
        @($catalog.intents).Count -gt 128) {
        Add-Issue 'mastery/INTENTS.json не соответствует catalog contract v1.'
        return [pscustomobject]@{ Records = @(); Ids = $script:masteryIntentIds }
    }
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($intent in @($catalog.intents)) {
        if ($null -eq $intent -or $intent -is [System.Array] -or
            ((@($intent.PSObject.Properties.Name | Sort-Object) -join ',') -cne 'description,id,label') -or
            $intent.id -isnot [string] -or $intent.label -isnot [string] -or $intent.description -isnot [string]) {
            Add-Issue 'mastery/INTENTS.json содержит intent с неизвестной схемой.'
            continue
        }
        $id = [string]$intent.id
        $label = [string]$intent.label
        $description = [string]$intent.description
        if ($id -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$' -or
            -not $script:masteryIntentIds.Add($id)) {
            Add-Issue 'mastery/INTENTS.json содержит invalid или duplicate intent id.'
            continue
        }
        if ([string]::IsNullOrWhiteSpace($label) -or $label.Length -gt 80 -or
            [string]::IsNullOrWhiteSpace($description) -or $description.Length -gt 240 -or
            ($label + $description) -match '[\r\n\x00-\x08\x0B\x0C\x0E-\x1F\x7F<>\[\]|]' -or
            @(Get-SensitiveDataFindings ($label + "`n" + $description)).Count -gt 0) {
            Add-Issue "mastery/INTENTS.json: intent '$id' содержит небезопасный label или description."
            continue
        }
        $records.Add([pscustomobject]@{ Id = $id; Label = $label; Description = $description }) | Out-Null
    }
    $requiredIntentIds = @(
        'research', 'product', 'business-architecture', 'planning', 'architecture', 'implementation',
        'testing', 'debugging', 'review', 'security', 'release', 'operations', 'design', 'content',
        'collaboration', 'knowledge-curation'
    )
    foreach ($requiredId in $requiredIntentIds) {
        if (-not $script:masteryIntentIds.Contains($requiredId)) {
            Add-Issue "mastery/INTENTS.json не содержит обязательный intent '$requiredId'."
        }
    }
    $script:masteryIntentRecords = @($records | Sort-Object -Property Id)
    return [pscustomobject]@{
        Records = @($script:masteryIntentRecords)
        Ids = $script:masteryIntentIds
    }
}

function Test-Candidates {
    $candidateRoot = [System.IO.Path]::Combine($script:verificationRoot, 'knowledge', 'candidates')
    if (-not (Test-Path -LiteralPath $candidateRoot -PathType Container)) { return }

    $rootReparse = Get-ReparsePointInPath $candidateRoot
    if ($null -ne $rootReparse) {
        Add-Issue "knowledge/candidates проходит через reparse point: $(Get-RelativePath $rootReparse)"
        return
    }
    foreach ($directory in (Get-ChildItem -LiteralPath $candidateRoot -Recurse -Directory -Force)) {
        if (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-Issue "Reparse point в candidates: $(Get-RelativePath $directory.FullName)"
        }
    }

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($file in (Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Force)) {
        $relative = Get-RelativePath $file.FullName
        if ($relative -ceq 'knowledge/candidates/TEMPLATE.md') {
            $templateText = Read-BoundedUtf8Text -FilePath $file.FullName -Context 'candidate template safety'
            if ($null -ne $templateText) {
                foreach ($finding in (Get-SensitiveDataFindings $templateText)) {
                    Add-Issue "$relative`: потенциально небезопасный материал в candidate template ($finding)."
                }
            }
            continue
        }
        if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-Issue "Reparse point candidate: $relative"
            continue
        }
        if ($relative -notmatch '^knowledge/candidates/(\d{4})/(KC-\d{8}-\d{6}-[0-9a-f]{8})\.md$') {
            Add-Issue "Недопустимый путь в knowledge/candidates: $relative"
            continue
        }
        $pathYear = $Matches[1]
        $pathId = $Matches[2]
        $document = Read-FrontMatterDocument $file.FullName
        if ($null -eq $document) { continue }
        $records.Add([pscustomobject]@{
            File = $file.FullName
            Relative = $relative
            PathYear = $pathYear
            PathId = $pathId
            Document = $document
            Data = $document.Data
        }) | Out-Null
    }

    $idMap = $script:candidateIdMap
    $claimMap = @{}
    $candidateScalarTypeValidity = @{}
    foreach ($record in $records) {
        $data = $record.Data
        $relative = $record.Relative
        foreach ($field in $candidateFields) {
            if (-not $data.ContainsKey($field)) {
                Add-Issue "$relative`: отсутствует поле '$field'."
            }
        }
        foreach ($field in @($data.Keys)) {
            if ($field -cnotin $candidateAllowedFields) {
                Add-Issue "$relative`: candidate содержит неизвестное поле."
            }
        }
        $scalarTypesValid = $true
        foreach ($field in @($candidateScalarFields + $candidateOptionalMethodScalarFields)) {
            if (-not $data.ContainsKey($field)) { continue }
            $allowNull = $field -cin $candidateNullableScalarFields
            if ($field -cin $candidateOptionalMethodScalarFields) { $allowNull = $true }
            if (-not (& $script:mpkTestFrontMatterScalarValue -Value $data[$field] -AllowNull:$allowNull)) {
                $expectedKind = if ($allowNull) { 'YAML scalar или null' } else { 'YAML scalar' }
                Add-Issue "$relative`: поле '$field' должно быть $expectedKind."
                $scalarTypesValid = $false
            }
        }
        $candidateScalarTypeValidity[$relative] = $scalarTypesValid
        if (-not $data.ContainsKey('id') -or -not $data.ContainsKey('claim_key')) { continue }
        if (-not (& $script:mpkTestFrontMatterScalarValue -Value $data.id) -or
            -not (& $script:mpkTestFrontMatterScalarValue -Value $data.claim_key)) {
            continue
        }

        $id = [string]$data.id
        $claimKey = [string]$data.claim_key
        if ($id -cnotmatch '^KC-(\d{8})-(\d{6})-([0-9a-f]{8})$') {
            Add-Issue "$relative`: invalid candidate id."
        }
        else {
            if ($id -cne $record.PathId) {
                Add-Issue "$relative`: id '$id' не совпадает с именем файла '$($record.PathId)'."
            }
            if ($Matches[1].Substring(0, 4) -cne $record.PathYear) {
                Add-Issue "$relative`: год каталога не совпадает с candidate id."
            }
            if ($idMap.ContainsKey($id)) {
                Add-Issue "Duplicate candidate ID: $($idMap[$id]) и $relative."
            }
            else {
                $idMap[$id] = $relative
                $script:candidateMetadataMap[$id] = [pscustomobject]@{
                    Relative = $relative
                    State = $(if (& $script:mpkTestFrontMatterScalarValue -Value $data.state) {
                        [string]$data.state
                    }
                    else {
                        ''
                    })
                    CaptureBasis = $(if (& $script:mpkTestFrontMatterScalarValue -Value $data.capture_basis) {
                        [string]$data.capture_basis
                    }
                    else {
                        ''
                    })
                    AuthorityRef = $(if (& $script:mpkTestFrontMatterScalarValue -Value $data.authority_ref) {
                        [string]$data.authority_ref
                    }
                    else {
                        ''
                    })
                    SourceRefs = $(if ($data.source_refs -is [System.Array]) {
                        @($data.source_refs | ForEach-Object { [string]$_ })
                    }
                    else {
                        @()
                    })
                    TargetRef = $(if (& $script:mpkTestFrontMatterScalarValue -Value $data.target_ref) {
                        [string]$data.target_ref
                    }
                    else {
                        ''
                    })
                    DataClass = $(if (& $script:mpkTestFrontMatterScalarValue -Value $data.data_class) {
                        [string]$data.data_class
                    }
                    else {
                        ''
                    })
                    CreatedAt = $(if (& $script:mpkTestFrontMatterScalarValue -Value $data.created_at) {
                        [string]$data.created_at
                    }
                    else {
                        ''
                    })
                    ReviewDue = $(if (& $script:mpkTestFrontMatterScalarValue -Value $data.review_due -AllowNull) {
                        [string]$data.review_due
                    }
                    else {
                        ''
                    })
                    ClaimTitle = ''
                    ConflictCount = 0
                    ResolvedInternalSourcePaths = @()
                }
            }
        }
        if ($claimKey -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?$') {
            Add-Issue "$relative`: invalid claim_key."
        }
        if ($claimMap.ContainsKey($claimKey)) {
            Add-Issue "Duplicate claim_key: $($claimMap[$claimKey]) и $relative."
        }
        else {
            $claimMap[$claimKey] = $relative
        }
    }

    foreach ($record in $records) {
        $data = $record.Data
        $relative = $record.Relative
        if (@($candidateFields | Where-Object { -not $data.ContainsKey($_) }).Count -gt 0 -or
            -not $candidateScalarTypeValidity[$relative]) {
            Test-CandidateBody -Document $record.Document -Relative $relative
            continue
        }

        if ([string]$data.state -cnotin @('ready', 'applied', 'dismissed')) {
            Add-Issue "$relative`: invalid state."
        }
        if ([string]$data.type -cnotin @('fact', 'decision', 'constraint', 'preference', 'method')) {
            Add-Issue "$relative`: invalid type."
        }
        if ([string]$data.owner_scope -cne 'project') {
            Add-Issue "$relative`: owner_scope должен быть project."
        }
        if ([string]$data.domain -cnotin @('idea', 'product', 'business', 'architecture', 'codebase', 'operations', 'research', 'mastery', 'instructions')) {
            Add-Issue "$relative`: invalid domain."
        }
        if ([string]$data.confidence -cnotin @('high', 'medium', 'low', 'unknown')) {
            Add-Issue "$relative`: invalid confidence."
        }
        if ([string]$data.capture_basis -cnotin @('repo-derived', 'explicit-user-capture', 'research-derived', 'plan-closeout')) {
            Add-Issue "$relative`: invalid capture_basis."
        }
        if ([string]$data.data_class -cnotin @('public', 'internal')) {
            Add-Issue "$relative`: invalid data_class."
        }
        $createdTimestamp = Get-DateTimeOffsetOrNull ([string]$data.created_at)
        if ($null -eq $createdTimestamp) {
            Add-Issue "$relative`: invalid created_at."
        }
        elseif ($createdTimestamp -gt [System.DateTimeOffset]::UtcNow.AddMinutes(5)) {
            Add-Issue "$relative`: candidate-lifecycle-future-date: created_at."
        }
        if (-not (Test-IsNullValue $data.review_due) -and -not (Test-DateOnly ([string]$data.review_due))) {
            Add-Issue "$relative`: invalid review_due."
        }
        elseif (-not (Test-IsNullValue $data.review_due)) {
            $reviewDate = [datetime]::ParseExact(
                [string]$data.review_due,
                'yyyy-MM-dd',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            if ($reviewDate.Date -lt [datetime]::Today) {
                Add-ReportItem -Category 'overdue' -Value "$($record.PathId) -> $($data.review_due)"
            }
        }

        if (-not ($data.source_refs -is [System.Array])) {
            Add-Issue "$relative`: source_refs должен быть YAML-списком."
            $sources = @()
        }
        else {
            $sources = @($data.source_refs)
        }
        if ($sources.Count -eq 0) {
            Add-Issue "$relative`: source_refs не может быть пустым."
        }
        if ([string]$data.capture_basis -ceq 'plan-closeout' -and @($sources | Where-Object { [string]$_ -match '^plans/\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*\.md(?:#.+)?$' }).Count -eq 0) {
            Add-Issue "$relative`: plan-closeout candidate требует source_ref на Plan v2."
        }
        if (@($sources | Sort-Object -Unique).Count -ne $sources.Count) {
            Add-Issue "$relative`: source_refs содержит дубли."
        }
        $candidateMetadata = if (
            (& $script:mpkTestFrontMatterScalarValue -Value $data.id) -and
            $script:candidateMetadataMap.ContainsKey([string]$data.id)
        ) {
            $script:candidateMetadataMap[[string]$data.id]
        }
        else {
            $null
        }
        foreach ($source in $sources) {
            $resolvedSource = Resolve-SafeReference `
                -Value ([string]$source) `
                -Context "$relative source_refs" `
                -AllowExternal `
                -AllowLogical `
                -MustExist
            if ($null -ne $candidateMetadata -and
                $null -ne $resolvedSource -and
                $resolvedSource.Kind -eq 'internal' -and
                (Test-Path -LiteralPath $resolvedSource.FullPath -PathType Leaf)) {
                $normalizedSourcePath = Get-RelativePath $resolvedSource.FullPath
                $candidateMetadata.ResolvedInternalSourcePaths = @(
                    @($candidateMetadata.ResolvedInternalSourcePaths) + $normalizedSourcePath |
                        Sort-Object -Unique
                )
            }
            if ([string]$source -match '^evidence:(.+)$' -and -not $script:evidenceIdMap.ContainsKey($Matches[1])) {
                Add-Issue "$relative`: broken evidence ID в source_refs."
            }
            if ([string]$source -match '^KC-\d{8}-\d{6}-[0-9a-f]{8}$' -and -not $idMap.ContainsKey([string]$source)) {
                Add-Issue "$relative`: broken candidate source '$source'."
            }
        }

        if (-not ($data.conflict_refs -is [System.Array])) {
            Add-Issue "$relative`: conflict_refs должен быть YAML-списком."
            $conflicts = @()
        }
        else {
            $conflicts = @($data.conflict_refs)
        }
        if (@($conflicts | Sort-Object -Unique).Count -ne $conflicts.Count) {
            Add-Issue "$relative`: conflict_refs содержит дубли."
        }
        if ($conflicts.Count -gt 0) {
            Add-ReportItem -Category 'conflicts' -Value "$($record.PathId) -> count=$($conflicts.Count)"
            if ([string]$data.state -ceq 'applied') {
                Add-Issue "$relative`: applied candidate требует пустой conflict_refs."
            }
        }
        if ($null -ne $candidateMetadata) {
            $candidateMetadata.ConflictCount = $conflicts.Count
            $titleMatch = [regex]::Match([string]$record.Document.Body, '(?m)^#[ \t]+(?<title>[^\r\n]{1,160})[ \t]*$')
            if ($titleMatch.Success -and [string]$data.data_class -ceq 'public') {
                $title = ([string]$titleMatch.Groups['title'].Value).Trim()
                if ($title -cmatch '^[\p{L}\p{N}][\p{L}\p{N} .,:;!?()/_+\-]{0,119}$' -and
                    @(Get-UnsafeFindings $title).Count -eq 0) {
                    $candidateMetadata.ClaimTitle = $title
                }
            }
        }
        foreach ($conflict in $conflicts) {
            Resolve-SafeReference -Value ([string]$conflict) -Context "$relative conflict_refs" -AllowExternal -AllowLogical -MustExist | Out-Null
            if ([string]$conflict -match '^evidence:(.+)$' -and -not $script:evidenceIdMap.ContainsKey($Matches[1])) {
                Add-Issue "$relative`: broken evidence ID в conflict_refs."
            }
            if ([string]$conflict -match '^KC-\d{8}-\d{6}-[0-9a-f]{8}$' -and -not $idMap.ContainsKey([string]$conflict)) {
                Add-Issue "$relative`: broken conflict candidate '$conflict'."
            }
        }

        $target = Resolve-SafeReference -Value ([string]$data.target_ref) -Context "$relative target_ref" -MustExist:([string]$data.state -ceq 'applied')
        if ($null -ne $target -and $target.Kind -eq 'internal') {
            $targetRelative = Get-RelativePath $target.FullPath
            if ([System.IO.Path]::GetExtension($target.FullPath) -cne '.md') {
                Add-Issue "$relative`: target_ref должен указывать на канонический Markdown-файл."
            }
            if ($targetRelative -match '^(?:knowledge/candidates|research/runs|analysis/runs|inbox/raw|plans|retrospectives)(?:/|$)') {
                Add-Issue "$relative`: target_ref указывает в рабочую или RAW-зону, а не в канон: $targetRelative."
            }
        }

        if ([string]$data.type -ceq 'method') {
            foreach ($field in $candidateOptionalMethodFields) {
                if (-not $data.ContainsKey($field)) {
                    Add-Issue "$relative`: method candidate требует поле '$field'."
                }
            }
            if ([string]$data.domain -cne 'mastery') {
                Add-Issue "$relative`: method candidate требует domain: mastery."
            }
            if (-not $data.ContainsKey('method_kind') -or [string]$data.method_kind -cnotin @('heuristic', 'checklist', 'workflow', 'standard')) {
                Add-Issue "$relative`: method candidate требует valid method_kind."
            }
            if (-not $data.ContainsKey('method_summary') -or
                -not (& $script:mpkTestFrontMatterScalarValue -Value $data.method_summary) -or
                [string]::IsNullOrWhiteSpace([string]$data.method_summary) -or
                ([string]$data.method_summary).Length -gt 160 -or
                [string]$data.method_summary -match '[\r\n\x00-\x08\x0B\x0C\x0E-\x1F\x7F<>\[\]|]') {
                Add-Issue "$relative`: method candidate требует безопасный method_summary."
            }
            $methodTitleMatch = [regex]::Match([string]$record.Document.Body, '(?m)^#[ \t]+(?<title>[^\r\n]+?)[ \t]*$')
            if (-not $methodTitleMatch.Success -or
                $methodTitleMatch.Groups['title'].Value.Trim() -cnotmatch '^[\p{L}\p{N}][\p{L}\p{N} .,:;!?()/_+\-]{0,119}$') {
                Add-Issue "$relative`: method candidate требует безопасный H1 title."
            }
            $methodIntents = if ($data.ContainsKey('method_applies_to') -and $data.method_applies_to -is [System.Array]) {
                @($data.method_applies_to | ForEach-Object { [string]$_ })
            }
            else { @() }
            if ($methodIntents.Count -eq 0 -or
                @($methodIntents | Sort-Object -Unique -CaseSensitive).Count -ne $methodIntents.Count) {
                Add-Issue "$relative`: method candidate требует непустой method_applies_to без дублей."
            }
            $intentCatalog = Get-MasteryIntentCatalog
            foreach ($intentId in $methodIntents) {
                if (-not $intentCatalog.Ids.Contains($intentId)) {
                    Add-Issue "$relative`: method_applies_to содержит intent вне mastery/INTENTS.json."
                }
            }
            if ([string]$data.target_ref -cne 'mastery/local/INDEX.md#зарегистрированные-расширения') {
                Add-Issue "$relative`: method candidate требует exact target_ref локального mastery registry."
            }
            if ([string]$data.claim_key -cnotmatch '^method\.[a-z0-9](?:[a-z0-9._-]{0,119}[a-z0-9])?$') {
                Add-Issue "$relative`: method candidate требует claim_key вида method.<id>."
            }
            if ([string]$data.confidence -cnotin @('medium', 'high')) {
                Add-Issue "$relative`: method candidate требует confidence medium или high."
            }
            if (Test-IsNullValue $data.review_due) {
                Add-Issue "$relative`: method candidate требует review_due."
            }

            $taskSourceIdentities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $hasProjectSource = $false
            if ($null -ne $candidateMetadata) {
                foreach ($sourcePath in @($candidateMetadata.ResolvedInternalSourcePaths)) {
                    $normalizedSource = [string]$sourcePath
                    if ($normalizedSource -notmatch '^knowledge/candidates/' -and
                        $normalizedSource -notmatch '(?:^|/)(?:README|INDEX|TEMPLATE)\.md$') {
                        $hasProjectSource = $true
                    }
                    if ($normalizedSource -match '^research/runs/(?<run>[^/]+)/decision\.md$') {
                        [void]$taskSourceIdentities.Add('research:' + [string]$Matches['run'])
                    }
                    elseif ($normalizedSource -match '^plans/(?<task>\d{4}-\d{2}-\d{2}-[^/]+)\.md$') {
                        [void]$taskSourceIdentities.Add('plan:' + [string]$Matches['task'])
                    }
                    elseif ($normalizedSource -match '^retrospectives/(?<task>[^/]+)\.md$') {
                        [void]$taskSourceIdentities.Add('retrospective:' + [string]$Matches['task'])
                    }
                }
            }
            $explicitOperatorCorrection = (
                [string]$data.capture_basis -ceq 'explicit-user-capture' -and
                [string]$data.authority_ref -cmatch '^user-request:[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -and
                $hasProjectSource
            )
            if ($taskSourceIdentities.Count -lt 2 -and -not $explicitOperatorCorrection) {
                Add-Issue "$relative`: method candidate требует два независимых task/run source или explicit operator correction с user authority и project source."
            }
        }
        else {
            if ($data.ContainsKey('method_kind') -and -not (Test-IsNullValue $data.method_kind)) {
                Add-Issue "$relative`: non-method candidate требует method_kind: null."
            }
            if ($data.ContainsKey('method_summary') -and -not (Test-IsNullValue $data.method_summary)) {
                Add-Issue "$relative`: non-method candidate требует method_summary: null."
            }
            if ($data.ContainsKey('method_applies_to') -and
                (-not ($data.method_applies_to -is [System.Array]) -or @($data.method_applies_to).Count -ne 0)) {
                Add-Issue "$relative`: non-method candidate требует method_applies_to: []."
            }
        }

        $authorityValid = Test-CandidateAuthorityReference `
            -Value ([string]$data.authority_ref) `
            -Context "$relative authority_ref"
        $terminalAuthorityValid = $authorityValid -and [string]$data.authority_ref -cne 'policy:knowledge-contract-v1'
        if ([string]$data.capture_basis -ceq 'explicit-user-capture' -and
            [string]$data.authority_ref -ceq 'policy:knowledge-contract-v1') {
            Add-Issue "$relative`: explicit-user-capture требует direct authority_ref."
        }
        switch ([string]$data.state) {
            'ready' {
                Add-ReportItem -Category 'pending' -Value $record.PathId
                if (-not (Test-IsNullValue $data.applied_at)) {
                    Add-Issue "$relative`: ready candidate не может иметь applied_at."
                }
                if (-not (Test-IsNullValue $data.dismiss_reason)) {
                    Add-Issue "$relative`: ready candidate не может иметь dismiss_reason."
                }
            }
            'applied' {
                $appliedTimestamp = Get-DateTimeOffsetOrNull ([string]$data.applied_at)
                if (Test-IsNullValue $data.applied_at -or $null -eq $appliedTimestamp) {
                    Add-Issue "$relative`: applied candidate требует valid applied_at."
                }
                else {
                    if ($null -ne $createdTimestamp -and $appliedTimestamp -lt $createdTimestamp) {
                        Add-Issue "$relative`: candidate-lifecycle-date-order: applied_at precedes created_at."
                    }
                    if ($appliedTimestamp -gt [System.DateTimeOffset]::UtcNow.AddMinutes(5)) {
                        Add-Issue "$relative`: candidate-lifecycle-future-date: applied_at."
                    }
                }
                if (-not $terminalAuthorityValid) {
                    Add-Issue "$relative`: applied candidate требует authority_ref."
                }
                if (-not (Test-IsNullValue $data.dismiss_reason)) {
                    Add-Issue "$relative`: applied candidate не может иметь dismiss_reason."
                }
                if ($null -ne $target -and
                    $target.Kind -eq 'internal' -and
                    (Test-Path -LiteralPath $target.FullPath -PathType Leaf) -and
                    -not (Test-MarkdownBacklink -TargetPath $target.FullPath -CandidatePath $record.File)) {
                    Add-Issue "$relative`: applied candidate не имеет Markdown-backlink из target_ref."
                }
            }
            'dismissed' {
                Add-ReportItem -Category 'dismissed' -Value "$($record.PathId) -> $($data.dismiss_reason)"
                if ([string]$data.dismiss_reason -cnotin @('rejected', 'duplicate', 'expired', 'superseded')) {
                    Add-Issue "$relative`: dismissed candidate требует допустимый dismiss_reason."
                }
                if (-not $terminalAuthorityValid) {
                    Add-Issue "$relative`: dismissed candidate требует authority_ref."
                }
                if (-not (Test-IsNullValue $data.applied_at)) {
                    Add-Issue "$relative`: dismissed candidate не может иметь applied_at."
                }
            }
        }
        if (-not (Test-IsNullValue $data.supersedes)) {
            if ([string]$data.supersedes -cnotmatch '^KC-\d{8}-\d{6}-[0-9a-f]{8}$') {
                Add-Issue "$relative`: supersedes должен содержать candidate ID или null."
            }
            elseif ([string]$data.supersedes -ceq [string]$data.id) {
                Add-Issue "$relative`: self-supersedes запрещен."
            }
            elseif (-not $idMap.ContainsKey([string]$data.supersedes)) {
                Add-Issue "$relative`: supersedes ссылается на отсутствующий candidate."
            }
        }
        Test-CandidateBody -Document $record.Document -Relative $relative
    }

    $supersedesMap = @{}
    foreach ($record in $records) {
        $data = $record.Data
        if (-not $data.ContainsKey('id') -or -not $data.ContainsKey('supersedes') -or
            -not (& $script:mpkTestFrontMatterScalarValue -Value $data.id) -or
            (Test-IsNullValue $data.supersedes) -or
            -not (& $script:mpkTestFrontMatterScalarValue -Value $data.supersedes)) {
            continue
        }
        $candidateId = [string]$data.id
        $supersededId = [string]$data.supersedes
        if ($candidateId -cmatch '^KC-\d{8}-\d{6}-[0-9a-f]{8}$' -and
            $supersededId -cmatch '^KC-\d{8}-\d{6}-[0-9a-f]{8}$' -and
            $idMap.ContainsKey($candidateId) -and
            $idMap.ContainsKey($supersededId)) {
            $supersedesMap[$candidateId] = $supersededId
        }
    }
    $reportedSupersedesCycles = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($startId in @($supersedesMap.Keys)) {
        $path = @{}
        $currentId = [string]$startId
        while ($supersedesMap.ContainsKey($currentId)) {
            if ($path.ContainsKey($currentId)) {
                $cycleSignature = @($path.Keys | Sort-Object) -join '|'
                if ($reportedSupersedesCycles.Add($cycleSignature)) {
                    Add-Issue "candidate-supersedes-cycle: $currentId."
                }
                break
            }
            $path[$currentId] = $true
            $currentId = [string]$supersedesMap[$currentId]
        }
    }
}

function Get-MarkdownLinkTargets {
    param([Parameter(Mandatory = $true)][string]$MarkdownPath)

    $text = Read-BoundedUtf8Text -FilePath $MarkdownPath -Context "Markdown links '$(Get-RelativePath $MarkdownPath)'"
    if ($null -eq $text) { return @() }
    $text = Get-CommonMarkVisibleText $text
    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($link in (Get-InlineMarkdownLinks -Text $text)) {
        if (-not $link.Valid -or $link.IsImage) { continue }
        $destination = $link.Target.Trim()
        if ($destination.StartsWith('<') -and $destination.EndsWith('>')) {
            $destination = $destination.Substring(1, $destination.Length - 2)
        }
        if ($destination -match '^[a-z][a-z0-9+.-]*:' -or $destination.StartsWith('#')) { continue }
        $pathPart = $destination.Split('#', 2)[0]
        try {
            $decoded = [System.Uri]::UnescapeDataString($pathPart)
            $resolved = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $MarkdownPath) $decoded))
            if ((Test-PathWithinRoot $resolved) -and (Test-ExactPathCase $resolved)) {
                $targets.Add($resolved) | Out-Null
            }
        }
        catch {
            continue
        }
    }
    return @($targets)
}

function Test-RootReachability {
    $rootIndex = Join-Path $script:verificationRoot 'INDEX.md'
    if (-not (Test-Path -LiteralPath $rootIndex -PathType Leaf)) {
        Add-Issue 'Root reachability: INDEX.md отсутствует.'
        return
    }

    $manifestPath = Join-Path $script:verificationRoot '.template-manifest.json'
    $manifest = $null
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifestText = Read-BoundedUtf8Text -FilePath $manifestPath -Context 'Root reachability manifest'
        if ($null -ne $manifestText) {
            try {
                $manifest = $manifestText | ConvertFrom-Json
            }
            catch {
                Add-Issue 'Root reachability: .template-manifest.json invalid JSON.'
            }
        }
    }

    $sourceOnly = @{}
    if ($null -ne $manifest) {
        foreach ($path in @($manifest.source_only_paths)) {
            $sourceOnly[[string]$path] = $true
        }
    }

    $projectPath = Join-Path $script:verificationRoot 'PROJECT.md'
    $isGenerated = $false
    $isTemplateSource = $false
    if (Test-Path -LiteralPath $projectPath -PathType Leaf) {
        $projectDocument = Read-FrontMatterDocument $projectPath
        if ($null -ne $projectDocument -and $projectDocument.Data.ContainsKey('repository_kind')) {
            $isGenerated = [string]$projectDocument.Data.repository_kind -ceq 'generated-project'
            $isTemplateSource = [string]$projectDocument.Data.repository_kind -ceq 'template-source'
        }
    }

    $portableCanonical = @{}
    $maintenanceCanonical = @{}
    if ($null -ne $manifest) {
        foreach ($path in @($manifest.portable_files)) {
            $relative = [string]$path
            if (-not $relative.EndsWith('.md', [System.StringComparison]::Ordinal)) { continue }
            $absolute = Join-Path $script:verificationRoot $relative
            if (Test-Path -LiteralPath $absolute -PathType Leaf) {
                $portableCanonical[(Resolve-Path -LiteralPath $absolute).Path] = $relative
            }
        }
        if ($isTemplateSource) {
            foreach ($path in @($manifest.source_only_paths)) {
                $relative = [string]$path
                if (-not $relative.EndsWith('.md', [System.StringComparison]::Ordinal)) { continue }
                if ($relative -match '^(?:plans|retrospectives|research/runs|analysis/runs|knowledge/candidates|inbox/raw|business/raw)(?:/|$)') {
                    continue
                }
                $absolute = Join-Path $script:verificationRoot $relative
                if (Test-Path -LiteralPath $absolute -PathType Leaf) {
                    $maintenanceCanonical[(Resolve-Path -LiteralPath $absolute).Path] = $relative
                }
            }
        }
    }
    else {
        foreach ($rootFile in @('AGENTS.md', 'INDEX.md', 'PROJECT.md', 'README.md', 'TEMPLATE.md', 'TEMPLATE-CHANGELOG.md')) {
            $absolute = Join-Path $script:verificationRoot $rootFile
            if (Test-Path -LiteralPath $absolute -PathType Leaf) {
                $portableCanonical[(Resolve-Path -LiteralPath $absolute).Path] = $rootFile
            }
        }
        foreach ($zone in @('idea', 'business', 'docs', 'inbox', 'knowledge', 'mastery', 'plans', 'research', 'retrospectives', '.agents')) {
            $zonePath = Join-Path $script:verificationRoot $zone
            if (-not (Test-Path -LiteralPath $zonePath -PathType Container)) { continue }
            foreach ($file in (Get-ChildItem -LiteralPath $zonePath -Recurse -File -Filter '*.md' -Force)) {
                $relative = Get-RelativePath $file.FullName
                if ($relative -match '^(?:research/runs|analysis/runs|knowledge/candidates/(?!TEMPLATE\.md$)|plans/(?!README\.md$|TEMPLATE\.md$)|retrospectives/(?!README\.md$|TEMPLATE\.md$)|inbox/raw/(?!README\.md$|TEMPLATE\.md$)|business/raw/(?!README\.md$|TEMPLATE\.md$|archive/README\.md$))(?:.*)$') {
                    continue
                }
                $portableCanonical[$file.FullName] = $relative
            }
        }
    }

    if ($isGenerated) {
        foreach ($zone in @('idea', 'business', 'docs', 'mastery/local')) {
            $zonePath = Join-Path $script:verificationRoot $zone
            if (-not (Test-Path -LiteralPath $zonePath -PathType Container)) { continue }
            foreach ($file in (Get-ChildItem -LiteralPath $zonePath -Recurse -File -Filter '*.md' -Force)) {
                $relative = Get-RelativePath $file.FullName
                if ($relative.StartsWith('business/raw/', [System.StringComparison]::Ordinal)) { continue }
                if ($sourceOnly.ContainsKey($relative)) { continue }
                $portableCanonical[$file.FullName] = $relative
            }
        }
    }

    function Get-ReachableMarkdownPaths {
        param(
            [Parameter(Mandatory = $true)][string[]]$Seeds,
            [Parameter(Mandatory = $true)][hashtable]$AllowedPaths
        )

        $visited = @{}
        $queue = [System.Collections.Generic.Queue[string]]::new()
        foreach ($seed in $Seeds) {
            if (Test-Path -LiteralPath $seed -PathType Leaf) {
                $queue.Enqueue((Resolve-Path -LiteralPath $seed).Path)
            }
        }
        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()
            if ($visited.ContainsKey($current)) { continue }
            $visited[$current] = $true
            foreach ($target in (Get-MarkdownLinkTargets $current)) {
                if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
                if ([System.IO.Path]::GetExtension($target) -ine '.md') { continue }
                $reparse = Get-ReparsePointInPath $target
                if ($null -ne $reparse) {
                    Add-Issue "Root reachability: link проходит через reparse point: $(Get-RelativePath $reparse)"
                    continue
                }
                $resolved = (Resolve-Path -LiteralPath $target).Path
                if (-not $AllowedPaths.ContainsKey($resolved)) { continue }
                if (-not $visited.ContainsKey($resolved)) { $queue.Enqueue($resolved) }
            }
        }
        return $visited
    }

    $portableVisited = Get-ReachableMarkdownPaths -Seeds @($rootIndex) -AllowedPaths $portableCanonical
    foreach ($entry in $portableCanonical.GetEnumerator()) {
        if (-not $portableVisited.ContainsKey([string]$entry.Key)) {
            Add-Issue "Orphan canonical Markdown: $($entry.Value)"
        }
    }

    if ($isTemplateSource -and $maintenanceCanonical.Count -gt 0) {
        $maintenanceRoot = Join-Path $script:verificationRoot 'TEMPLATE.md'
        if (-not $sourceOnly.ContainsKey('TEMPLATE.md') -or -not (Test-Path -LiteralPath $maintenanceRoot -PathType Leaf)) {
            Add-Issue 'Root reachability: source-only TEMPLATE.md отсутствует как maintenance root.'
            return
        }

        $maintenanceVisited = Get-ReachableMarkdownPaths -Seeds @($maintenanceRoot) -AllowedPaths $maintenanceCanonical
        foreach ($entry in $maintenanceCanonical.GetEnumerator()) {
            if (-not $maintenanceVisited.ContainsKey([string]$entry.Key)) {
                Add-Issue "Orphan canonical Markdown: $($entry.Value)"
            }
        }
    }
}

function Test-RawRecords {
    $rawIds = @{}
    foreach ($relativeRoot in @('inbox/raw', 'business/raw')) {
        $rawRoot = Join-Path $script:verificationRoot $relativeRoot
        if (-not (Test-Path -LiteralPath $rawRoot -PathType Container)) { continue }
        $rootReparse = Get-ReparsePointInPath $rawRoot
        if ($null -ne $rootReparse) {
            Add-Issue "$relativeRoot проходит через reparse point: $(Get-RelativePath $rootReparse)"
            continue
        }
        foreach ($directory in (Get-ChildItem -LiteralPath $rawRoot -Recurse -Directory -Force)) {
            $directoryRelative = Get-RelativePath $directory.FullName
            if (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Add-Issue "Reparse point в RAW: $directoryRelative"
                continue
            }
            $withinRawDirectory = $directory.FullName.Substring($rawRoot.Length + 1).Replace('\', '/')
            if ($withinRawDirectory.StartsWith('archive/', [System.StringComparison]::Ordinal)) {
                Add-Issue "Физический RAW archive subdirectory запрещен: $directoryRelative"
            }
        }
        foreach ($file in (Get-ChildItem -LiteralPath $rawRoot -Recurse -File -Force)) {
            $relative = Get-RelativePath $file.FullName
            if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Add-Issue "Reparse point RAW record: $relative"
                continue
            }
            $withinRaw = $file.FullName.Substring($rawRoot.Length + 1).Replace('\', '/')
            if ([System.IO.Path]::GetExtension($file.Name) -cne '.md') {
                Add-Issue "Недопустимый non-Markdown RAW file: $relative"
                continue
            }
            $rawText = Read-BoundedUtf8Text -FilePath $file.FullName -Context "$relative RAW safety"
            if ($null -ne $rawText) {
                $rawFindings = if ($withinRaw -cin @('README.md', 'TEMPLATE.md', 'archive/README.md')) {
                    @(Get-SensitiveDataFindings $rawText)
                }
                else {
                    @(Get-UnsafeFindings $rawText)
                }
                foreach ($finding in $rawFindings) {
                    Add-Issue "$relative`: data-safety finding in RAW ($finding)."
                }
            }
            if ($withinRaw.StartsWith('archive/', [System.StringComparison]::Ordinal)) {
                if ($withinRaw -cne 'archive/README.md') {
                    Add-Issue "Физическая RAW archive record запрещена: $relative"
                }
                continue
            }
            if ($withinRaw -ceq 'README.md') { continue }
            $document = Read-FrontMatterDocument $file.FullName
            if ($null -eq $document) { continue }
            $data = $document.Data
            foreach ($field in @($data.Keys)) {
                if ($field -cnotin $rawFields) {
                    Add-Issue "$relative`: RAW closed-schema отвергает неизвестное поле '$field'."
                }
            }
            foreach ($field in $rawFields) {
                if (-not $data.ContainsKey($field)) {
                    Add-Issue "$relative`: RAW record требует поле '$field'."
                }
            }
            $rawScalarTypesValid = $true
            foreach ($field in $rawScalarFields) {
                if (-not $data.ContainsKey($field)) { continue }
                $allowNull = $field -cin $rawNullableScalarFields
                if (-not (& $script:mpkTestFrontMatterScalarValue -Value $data[$field] -AllowNull:$allowNull)) {
                    $expectedKind = if ($allowNull) { 'YAML scalar или null' } else { 'YAML scalar' }
                    Add-Issue "$relative`: RAW поле '$field' должно быть $expectedKind."
                    $rawScalarTypesValid = $false
                }
            }
            if ($data.ContainsKey('related') -and
                -not (Test-IsNullValue $data.related) -and
                -not ($data.related -is [System.Array])) {
                Add-Issue "$relative`: RAW поле 'related' должно быть YAML-списком или null."
                $rawScalarTypesValid = $false
            }

            if ($withinRaw -ceq 'TEMPLATE.md') {
                if (-not $data.ContainsKey('storage_basis') -or -not (Test-IsNullValue $data.storage_basis)) {
                    Add-Issue "$relative`: RAW template требует storage_basis: null."
                }
                if (-not $data.ContainsKey('authority_ref') -or -not (Test-IsNullValue $data.authority_ref)) {
                    Add-Issue "$relative`: RAW template требует authority_ref: null."
                }
                continue
            }

            foreach ($field in @(
                'id', 'captured_at', 'storage_basis', 'authority_ref', 'data_class', 'content_mode',
                'personal_data', 'retention', 'source', 'rights', 'status'
            )) {
                if (-not $data.ContainsKey($field) -or (Test-IsNullValue $data[$field])) {
                    Add-Issue "$relative`: RAW record требует непустое поле '$field'."
                }
            }
            if ([string]$data.storage_basis -cnotin @('explicit-user-request', 'authorized-import')) {
                Add-Issue "$relative`: invalid storage_basis."
            }
            if (Test-IsNullValue $data.authority_ref) {
                Add-Issue "$relative`: RAW authority_ref required; null запрещен для captured record."
            }
            elseif ([string]$data.authority_ref -cnotmatch '^user-request:[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
                Add-Issue "$relative`: invalid RAW authority_ref."
            }
            if ([string]$data.data_class -cnotin @('public', 'internal', 'sensitive')) {
                Add-Issue "$relative`: invalid data_class."
            }
            if ([string]$data.content_mode -cnotin @('summary', 'verbatim')) {
                Add-Issue "$relative`: invalid content_mode."
            }
            if ([string]$data.personal_data -cnotin @('none', 'anonymized')) {
                Add-Issue "$relative`: invalid personal_data safety state."
            }
            if ([string]$data.rights -cnotin @('user-owned', 'user-authorized', 'public-summary', 'other')) {
                Add-Issue "$relative`: invalid rights."
            }
            if ([string]$data.status -cnotin @('captured', 'reviewed', 'rejected', 'retention-due')) {
                Add-Issue "$relative`: invalid RAW status."
            }
            if ([string]$data.data_class -ceq 'sensitive' -and [string]$data.content_mode -ceq 'verbatim') {
                Add-Issue "$relative`: RAW sensitive + verbatim запрещен."
            }
            if ([string]$data.content_mode -ceq 'verbatim' -and
                [string]$data.rights -cnotin @('user-owned', 'user-authorized')) {
                Add-Issue "$relative`: verbatim RAW требует rights user-owned или user-authorized."
            }
            $retention = [string]$data.retention
            if ($retention -ceq 'YYYY-MM-DD | rule' -or $retention.Length -lt 4) {
                Add-Issue "$relative`: retention не заполнен."
            }
            elseif (Test-DateOnly $retention) {
                $retentionDate = [datetime]::ParseExact(
                    $retention,
                    'yyyy-MM-dd',
                    [System.Globalization.CultureInfo]::InvariantCulture
                )
                if ($retentionDate.Date -lt [datetime]::Today) {
                    Add-ReportItem -Category 'overdue' -Value "$relative retention -> $retention"
                }
            }
            if ($data.ContainsKey('id') -and -not (Test-IsNullValue $data.id)) {
                $rawId = [string]$data.id
                if ($rawId -match 'YYYY|HHmm|slug') {
                    Add-Issue "$relative`: RAW id содержит template placeholder."
                }
                elseif ($rawIds.ContainsKey($rawId)) {
                    Add-Issue "Duplicate RAW id: $($rawIds[$rawId]) и $relative."
                }
                else {
                    $rawIds[$rawId] = $relative
                }
            }
            if ($data.ContainsKey('captured_at') -and
                -not (Test-IsNullValue $data.captured_at) -and
                -not (Test-DateTimeOffsetValue ([string]$data.captured_at))) {
                Add-Issue "$relative`: invalid captured_at."
            }
            if ([string]::IsNullOrWhiteSpace(([string]$data.source).Trim()) -or [string]$data.source -ceq 'origin-or-reference') {
                Add-Issue "$relative`: source не заполнен."
            }
            if ($document.Body -match '(?im)^ {0,3}##[ \t]+Knowledge outcome\b|Central candidate ID') {
                Add-Issue "$relative`: RAW payload не может хранить Knowledge outcome или Central candidate ID."
            }
            if ($data.related -is [System.Array]) {
                foreach ($relatedRef in @($data.related)) {
                    Resolve-SafeReference `
                        -Value ([string]$relatedRef) `
                        -Context "$relative related" `
                        -AllowExternal `
                        -AllowLogical `
                        -MustExist | Out-Null
                }
            }
        }
    }
}

function Convert-ToSemVerParts {
    param([AllowEmptyString()][string]$Value)

    $match = [regex]::Match(
        $Value,
        '^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<pre>(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$'
    )
    if (-not $match.Success) { return $null }
    return [pscustomobject]@{
        Major = [System.Numerics.BigInteger]::Parse($match.Groups['major'].Value)
        Minor = [System.Numerics.BigInteger]::Parse($match.Groups['minor'].Value)
        Patch = [System.Numerics.BigInteger]::Parse($match.Groups['patch'].Value)
        Pre = [string]$match.Groups['pre'].Value
    }
}

function Compare-SemVerParts {
    param(
        [Parameter(Mandatory = $true)]$Left,
        [Parameter(Mandatory = $true)]$Right
    )

    foreach ($name in @('Major', 'Minor', 'Patch')) {
        if ($Left.$name -lt $Right.$name) { return -1 }
        if ($Left.$name -gt $Right.$name) { return 1 }
    }
    if ([string]::IsNullOrEmpty($Left.Pre) -and [string]::IsNullOrEmpty($Right.Pre)) { return 0 }
    if ([string]::IsNullOrEmpty($Left.Pre)) { return 1 }
    if ([string]::IsNullOrEmpty($Right.Pre)) { return -1 }
    $leftIds = @($Left.Pre.Split('.'))
    $rightIds = @($Right.Pre.Split('.'))
    for ($i = 0; $i -lt [Math]::Min($leftIds.Count, $rightIds.Count); $i++) {
        $leftNumeric = $leftIds[$i] -cmatch '^\d+$'
        $rightNumeric = $rightIds[$i] -cmatch '^\d+$'
        if ($leftNumeric -and $rightNumeric) {
            $leftNumber = [System.Numerics.BigInteger]::Parse($leftIds[$i])
            $rightNumber = [System.Numerics.BigInteger]::Parse($rightIds[$i])
            if ($leftNumber -lt $rightNumber) { return -1 }
            if ($leftNumber -gt $rightNumber) { return 1 }
        }
        elseif ($leftNumeric) { return -1 }
        elseif ($rightNumeric) { return 1 }
        else {
            $comparison = [string]::CompareOrdinal($leftIds[$i], $rightIds[$i])
            if ($comparison -lt 0) { return -1 }
            if ($comparison -gt 0) { return 1 }
        }
    }
    if ($leftIds.Count -lt $rightIds.Count) { return -1 }
    if ($leftIds.Count -gt $rightIds.Count) { return 1 }
    return 0
}

function Get-MasteryBaselineFingerprint {
    param($Baseline)

    if ($null -eq $Baseline) { return '' }
    return @(
        @($Baseline.files) |
            ForEach-Object { '{0}|{1}' -f ([string]$_.path), ([string]$_.sha256).ToLowerInvariant() } |
            Sort-Object -CaseSensitive
    ) -join "`n"
}

function Test-SafeGitRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        $RelativePath -cne $RelativePath.Trim() -or
        $RelativePath -match '[\x00-\x1F\x7F\\:]' -or
        $RelativePath.StartsWith('/') -or
        $RelativePath.Contains('//')) {
        return $false
    }
    foreach ($segment in $RelativePath.Split('/')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -cin @('.', '..')) {
            return $false
        }
    }
    return $true
}

function Get-TrustedGitHeadFileText {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [switch]$AllowMissing
    )

    if (-not (Test-TrustedGitHead)) { return $null }
    if (-not (Test-SafeGitRelativePath -RelativePath $RelativePath)) {
        Add-Issue 'Git HEAD blob path не прошел safe relative-path check.'
        return $null
    }
    $metadata = Get-TrustedGitMetadata
    if ($null -eq $metadata) { return $null }
    $gitPath = Get-TrustedGitExecutable
    if ($null -eq $gitPath) { return $null }

    $objectSpec = "HEAD:$RelativePath"
    $typeResult = Invoke-TrustedGitCommand `
        -GitPath $gitPath `
        -Metadata $metadata `
        -Arguments @('cat-file', '-t', $objectSpec) `
        -MaxLines 1 `
        -MaxCharacters 32
    if ($typeResult.ExitCode -ne 0) {
        if (-not $AllowMissing) {
            Add-Issue 'Git HEAD blob недоступен через trusted object lookup.'
        }
        return $null
    }
    if ($typeResult.Lines.Count -ne 1 -or $typeResult.Lines[0] -cne 'blob') {
        Add-Issue 'Git HEAD object имеет неподдерживаемый type.'
        return $null
    }

    $sizeResult = Invoke-TrustedGitCommand `
        -GitPath $gitPath `
        -Metadata $metadata `
        -Arguments @('cat-file', '-s', $objectSpec) `
        -MaxLines 1 `
        -MaxCharacters 32
    [long]$blobSize = 0
    if ($sizeResult.ExitCode -ne 0 -or
        $sizeResult.Lines.Count -ne 1 -or
        -not [long]::TryParse($sizeResult.Lines[0], [ref]$blobSize) -or
        $blobSize -lt 0 -or
        $blobSize -gt $maxGitHeadBlobBytes) {
        Add-Issue "Git HEAD blob size отклонен bounded reader (limit $maxGitHeadBlobBytes bytes)."
        return $null
    }

    $blobResult = Invoke-TrustedGitCommand `
        -GitPath $gitPath `
        -Metadata $metadata `
        -Arguments @('cat-file', 'blob', $objectSpec) `
        -MaxCharacters $maxGitHeadBlobBytes
    if ($blobResult.ExitCode -ne 0) {
        Add-Issue 'Git HEAD blob не удалось прочитать trusted reader.'
        return $null
    }
    $blobText = $blobResult.Lines -join "`n"
    if ($utf8NoBom.GetByteCount($blobText) -gt $maxGitHeadBlobBytes) {
        Add-Issue "Git HEAD blob output превысил bounded reader limit $maxGitHeadBlobBytes bytes."
        return $null
    }
    return $blobText
}

function Get-TrustedGitHeadPaths {
    param([Parameter(Mandatory = $true)][string]$Prefix)

    if (-not (Test-TrustedGitHead)) { return @() }
    if (-not (Test-SafeGitRelativePath -RelativePath $Prefix)) {
        Add-Issue 'Git HEAD tree prefix не прошел safe relative-path check.'
        return @()
    }
    $metadata = Get-TrustedGitMetadata
    if ($null -eq $metadata) { return @() }
    $gitPath = Get-TrustedGitExecutable
    if ($null -eq $gitPath) { return @() }
    $treeResult = Invoke-TrustedGitCommand `
        -GitPath $gitPath `
        -Metadata $metadata `
        -Arguments @('ls-tree', '-r', '--name-only', 'HEAD', '--', $Prefix) `
        -MaxLines $maxGitTreeEntries `
        -MaxCharacters $maxGitTreeOutputChars
    if ($treeResult.LimitExceeded) {
        Add-Issue "Git HEAD tree превысил bounded inventory limit ($maxGitTreeEntries entries)."
        return @()
    }
    if ($treeResult.ExitCode -ne 0) {
        Add-Issue 'Git HEAD tree не удалось прочитать trusted reader.'
        return @()
    }
    $paths = @($treeResult.Lines | ForEach-Object { ([string]$_).Replace('\', '/') })
    $outputChars = [long]0
    foreach ($path in $paths) {
        $outputChars += $path.Length
        if (-not (Test-SafeGitRelativePath -RelativePath $path)) {
            Add-Issue 'Git HEAD tree содержит небезопасный path.'
            return @()
        }
    }
    if ($paths.Count -gt $maxGitTreeEntries -or $outputChars -gt $maxGitTreeOutputChars) {
        Add-Issue "Git HEAD tree превысил bounded inventory limit ($maxGitTreeEntries entries)."
        return @()
    }
    return $paths
}

function Get-FrontMatterScalarFromText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Field
    )

    $normalized = $Text.TrimStart([char]0xFEFF).Replace("`r`n", "`n")
    $match = [regex]::Match(
        $normalized,
        '(?m)\A---\n(?:(?!---$).*\n)*?' + [regex]::Escape($Field) + ':[ \t]*(?<value>[^\n]*)[ \t]*$'
    )
    if (-not $match.Success) { return $null }
    return ([string]$match.Groups['value'].Value).Trim().Trim("'", '"')
}

function Get-RawImmutableSnapshotFromText {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $normalized = $Text.TrimStart([char]0xFEFF).Replace("`r`n", "`n")
    $lines = @($normalized -split "`n", -1)
    if ($lines.Count -lt 3 -or $lines[0] -cne '---') { return $null }
    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -ceq '---') { $end = $i; break }
    }
    if ($end -lt 0) { return $null }
    $immutableFrontMatter = @(
        for ($i = 1; $i -lt $end; $i++) {
            if ($lines[$i] -cmatch '^(?:status|retention):') { continue }
            $lines[$i]
        }
    ) -join "`n"
    $body = if (($end + 1) -lt $lines.Count) { $lines[($end + 1)..($lines.Count - 1)] -join "`n" } else { '' }
    return $immutableFrontMatter + "`n---BODY---`n" + $body
}

function Test-TrustedHistoryContracts {
    if (-not (Test-TrustedGitHead)) { return }

    $headProjectText = Get-TrustedGitHeadFileText -RelativePath 'PROJECT.md'
    $currentProjectPath = Join-Path $script:verificationRoot 'PROJECT.md'
    if (-not [string]::IsNullOrWhiteSpace($headProjectText) -and
        (Test-Path -LiteralPath $currentProjectPath -PathType Leaf)) {
        $currentProjectText = Read-BoundedUtf8Text -FilePath $currentProjectPath -Context 'PROJECT.md history gate'
        if ($null -ne $currentProjectText) {
            $headKind = Get-FrontMatterScalarFromText -Text $headProjectText -Field 'repository_kind'
            $headStatus = Get-FrontMatterScalarFromText -Text $headProjectText -Field 'project_status'
            $currentKind = Get-FrontMatterScalarFromText -Text $currentProjectText -Field 'repository_kind'
            $currentStatus = Get-FrontMatterScalarFromText -Text $currentProjectText -Field 'project_status'
            $currentCapture = Get-FrontMatterScalarFromText -Text $currentProjectText -Field 'knowledge_capture_mode'
            if ($headKind -ceq 'generated-project' -and $headStatus -ceq 'archived' -and
                ($currentStatus -cne 'archived' -or $currentCapture -cne 'disabled')) {
                if ($currentKind -cne 'generated-project' -or
                    $currentStatus -cne 'initialized' -or
                    $currentCapture -cne 'report-only') {
                    Add-Issue 'PROJECT.md: archived restore разрешает только initialized + report-only.'
                }
            }
        }
    }

    foreach ($headCandidatePath in (Get-TrustedGitHeadPaths -Prefix 'knowledge/candidates')) {
        if ($headCandidatePath -cnotmatch '^knowledge/candidates/\d{4}/(?<id>KC-\d{8}-\d{6}-[0-9a-f]{8})\.md$') { continue }
        $candidateId = [string]$Matches['id']
        if (-not $script:candidateMetadataMap.ContainsKey($candidateId)) {
            Add-Issue "$headCandidatePath`: tracked candidate deletion запрещен history gate."
            continue
        }
        $headCandidateText = Get-TrustedGitHeadFileText -RelativePath $headCandidatePath
        if ([string]::IsNullOrWhiteSpace($headCandidateText)) { continue }
        $headState = Get-FrontMatterScalarFromText -Text $headCandidateText -Field 'state'
        $currentState = [string]$script:candidateMetadataMap[$candidateId].State
        if ($headState -cnotin @('ready', 'applied', 'dismissed')) {
            Add-Issue "$headCandidatePath`: trusted HEAD содержит неизвестный candidate state."
            continue
        }
        if ($currentState -ceq $headState) { continue }
        if ($headState -ceq 'ready' -and $currentState -cin @('applied', 'dismissed')) { continue }
        Add-Issue "$headCandidatePath`: invalid candidate state transition relative trusted HEAD."
    }

    foreach ($rawPrefix in @('inbox/raw', 'business/raw')) {
        foreach ($headRawPath in (Get-TrustedGitHeadPaths -Prefix $rawPrefix)) {
            if ($headRawPath -cnotmatch '^(?:inbox/raw|business/raw)/.+\.md$' -or
                $headRawPath -match '/(?:README|TEMPLATE)\.md$') { continue }
            $currentRawPath = Join-Path $script:verificationRoot $headRawPath
            if (-not (Test-Path -LiteralPath $currentRawPath -PathType Leaf)) {
                Add-Issue "$headRawPath`: tracked RAW deletion требует отдельного authorized delete workflow."
                continue
            }
            $headRawText = Get-TrustedGitHeadFileText -RelativePath $headRawPath
            $currentRawText = Read-BoundedUtf8Text -FilePath $currentRawPath -Context "$headRawPath history gate"
            if ($null -eq $headRawText -or $null -eq $currentRawText) { continue }
            $headSnapshot = Get-RawImmutableSnapshotFromText $headRawText
            $currentSnapshot = Get-RawImmutableSnapshotFromText $currentRawText
            if ($null -eq $headSnapshot -or $null -eq $currentSnapshot -or $headSnapshot -cne $currentSnapshot) {
                Add-Issue "$headRawPath`: RAW payload или immutable capture metadata изменены относительно trusted HEAD."
            }
        }
    }
}

function Test-Mastery {
    $manifestPath = Join-Path $script:verificationRoot '.template-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return }
    $manifestText = Read-BoundedUtf8Text -FilePath $manifestPath -Context '.template-manifest.json'
    if ($null -eq $manifestText) { return }
    try { $manifest = $manifestText | ConvertFrom-Json }
    catch {
        Add-Issue '.template-manifest.json: invalid JSON.'
        return
    }
    if ($null -eq $manifest.mastery_baseline) {
        Add-Issue '.template-manifest.json: отсутствует mastery_baseline.'
        return
    }

    $baseline = $manifest.mastery_baseline
    $bundleVersion = [string]$baseline.bundle_version
    $bundleSemVer = Convert-ToSemVerParts $bundleVersion
    if ($null -eq $bundleSemVer) {
        Add-Issue '.template-manifest.json: mastery_baseline.bundle_version должен быть strict SemVer.'
    }
    $verifiedAt = [string]$baseline.verified_at
    $reviewDue = [string]$baseline.review_due
    $verifiedDate = $null
    $reviewDate = $null
    if (-not (Test-DateOnly $verifiedAt)) {
        Add-Issue '.template-manifest.json: mastery_baseline.verified_at требует YYYY-MM-DD.'
    }
    else {
        $verifiedDate = [datetime]::ParseExact($verifiedAt, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        if ($verifiedDate.Date -gt [datetime]::Today) {
            Add-Issue '.template-manifest.json: mastery_baseline.verified_at находится в будущем.'
        }
    }
    if (-not (Test-DateOnly $reviewDue)) {
        Add-Issue '.template-manifest.json: mastery_baseline.review_due требует YYYY-MM-DD.'
    }
    else {
        $reviewDate = [datetime]::ParseExact($reviewDue, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        if ($null -ne $verifiedDate -and $reviewDate.Date -lt $verifiedDate.Date) {
            Add-Issue '.template-manifest.json: mastery_baseline.review_due раньше verified_at.'
        }
        if ($reviewDate.Date -lt [datetime]::Today) {
            Add-ReportItem -Category 'overdue' -Value "mastery baseline -> $reviewDue"
        }
    }

    $files = @($baseline.files)
    if ($files.Count -eq 0) { Add-Issue '.template-manifest.json: mastery_baseline.files пуст.' }
    $seen = @{}
    foreach ($entry in $files) {
        $path = [string]$entry.path
        $expectedHash = ([string]$entry.sha256).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($path) -or $path -notmatch '^mastery/(?:researcher|analyst)/[A-Za-z0-9._/-]+\.md$') {
            Add-Issue ".template-manifest.json: unsafe mastery baseline path '$path'."
            continue
        }
        if ($seen.ContainsKey($path)) {
            Add-Issue ".template-manifest.json: duplicate mastery baseline path '$path'."
            continue
        }
        $seen[$path] = $true
        $resolved = Resolve-SafeReference -Value $path -Context '.template-manifest.json mastery baseline' -MustExist
        if ($expectedHash -cnotmatch '^[0-9a-f]{64}$') {
            Add-Issue ".template-manifest.json: invalid SHA-256 для '$path'."
            continue
        }
        if ($null -ne $resolved -and (Test-Path -LiteralPath $resolved.FullPath -PathType Leaf)) {
            $actualHash = Get-Sha256 $resolved.FullPath
            if ($null -ne $actualHash -and $actualHash -cne $expectedHash) {
                $message = "$path expected=$expectedHash actual=$actualHash"
                Add-Issue "Mastery baseline drift: $message"
                Add-ReportItem -Category 'mastery_drift' -Value $message
            }
        }
    }
    foreach ($baselineRootRelative in @('mastery\researcher')) {
        $baselineRoot = Join-Path $script:verificationRoot $baselineRootRelative
        if (Test-Path -LiteralPath $baselineRoot -PathType Container) {
            foreach ($file in (Get-ChildItem -LiteralPath $baselineRoot -File -Filter '*.md' -Force)) {
                $relative = Get-RelativePath $file.FullName
                if (-not $seen.ContainsKey($relative)) {
                    Add-Issue "Незарегистрированный mastery baseline файл: $relative"
                    Add-ReportItem -Category 'mastery_drift' -Value "unregistered baseline: $relative"
                }
            }
        }
    }

    if (Test-TrustedGitHead) {
        $headManifestText = Get-TrustedGitHeadFileText -RelativePath '.template-manifest.json' -AllowMissing
        if (-not [string]::IsNullOrWhiteSpace($headManifestText)) {
            try { $headManifest = $headManifestText | ConvertFrom-Json }
            catch {
                Add-Issue 'HEAD .template-manifest.json: invalid JSON для mastery comparison.'
                $headManifest = $null
            }
            if ($null -ne $headManifest -and $null -ne $headManifest.mastery_baseline) {
                $headBaseline = $headManifest.mastery_baseline
                $headVersion = [string]$headBaseline.bundle_version
                $headSemVer = Convert-ToSemVerParts $headVersion
                if ($null -eq $headSemVer) {
                    Add-Issue 'HEAD mastery_baseline.bundle_version не является strict SemVer.'
                }
                elseif ($null -ne $bundleSemVer) {
                    $fingerprintChanged = (Get-MasteryBaselineFingerprint $baseline) -cne (Get-MasteryBaselineFingerprint $headBaseline)
                    $versionComparison = Compare-SemVerParts -Left $bundleSemVer -Right $headSemVer
                    $projectPath = Join-Path $script:verificationRoot 'PROJECT.md'
                    $projectKind = ''
                    if (Test-Path -LiteralPath $projectPath -PathType Leaf) {
                        $projectDocument = Read-FrontMatterDocument $projectPath
                        if ($null -ne $projectDocument -and $projectDocument.Data.ContainsKey('repository_kind')) {
                            $projectKind = [string]$projectDocument.Data.repository_kind
                        }
                    }
                    if ($projectKind -ceq 'generated-project') {
                        if ($fingerprintChanged -or $versionComparison -ne 0) {
                            Add-Issue 'Generated project baseline mutation относительно trusted HEAD запрещена.'
                        }
                    }
                    elseif ($projectKind -ceq 'template-source') {
                        if ($fingerprintChanged -and $versionComparison -le 0) {
                            Add-Issue 'Mastery baseline fingerprint изменен без строгого bundle_version bump.'
                        }
                        if (-not $fingerprintChanged -and $versionComparison -ne 0) {
                            Add-Issue 'Mastery baseline version-only bump без fingerprint change запрещен.'
                        }
                    }
                }
            }
        }
    }

    $localRoot = [System.IO.Path]::Combine($script:verificationRoot, 'mastery', 'local')
    if (-not (Test-Path -LiteralPath $localRoot -PathType Container)) { return }
    $localReparse = Get-ReparsePointInPath $localRoot
    if ($null -ne $localReparse) {
        Add-Issue "mastery/local проходит через reparse point: $(Get-RelativePath $localReparse)"
        return
    }
    $indexPath = Join-Path $localRoot 'INDEX.md'
    $registered = [System.Collections.Generic.HashSet[string]]::new($script:pathComparer)
    if (Test-Path -LiteralPath $indexPath -PathType Leaf) {
        foreach ($target in (Get-MarkdownLinkTargets $indexPath)) {
            $registered.Add([System.IO.Path]::GetFullPath($target)) | Out-Null
        }
    }
    else { Add-Issue 'mastery/local/INDEX.md отсутствует.' }

    $intentCatalog = Get-MasteryIntentCatalog
    $allowedFields = @(
        'mastery_contract_version', 'method_id', 'method_kind', 'summary', 'owner_scope',
        'applies_to', 'status', 'source_refs', 'verified_at', 'review_due', 'supersedes'
    )
    $records = [System.Collections.Generic.List[object]]::new()
    $methodIds = @{}
    foreach ($file in (Get-ChildItem -LiteralPath $localRoot -Recurse -File -Filter '*.md' -Force)) {
        if ($file.FullName.Equals($indexPath, $script:pathComparison)) {
            $indexText = Read-BoundedUtf8Text -FilePath $file.FullName -Context 'mastery/local index safety'
            if ($null -ne $indexText) {
                foreach ($finding in (Get-SensitiveDataFindings $indexText)) {
                    Add-Issue "mastery/local/INDEX.md: потенциально небезопасный материал в local mastery ($finding)."
                }
            }
            continue
        }
        if ($file.Name -ceq 'TEMPLATE.md') {
            $templateText = Read-BoundedUtf8Text -FilePath $file.FullName -Context 'mastery/local template safety'
            if ($null -ne $templateText) {
                foreach ($finding in (Get-SensitiveDataFindings $templateText)) {
                    Add-Issue "mastery/local/TEMPLATE.md: потенциально небезопасный материал в local mastery template ($finding)."
                }
            }
            continue
        }
        $relative = Get-RelativePath $file.FullName
        if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-Issue "Reparse point в mastery/local: $relative"
            continue
        }
        $isRegistered = $registered.Contains([System.IO.Path]::GetFullPath($file.FullName))
        if (-not $isRegistered) {
            Add-Issue "Незарегистрированное mastery/local расширение: $relative"
            Add-ReportItem -Category 'mastery_drift' -Value "unregistered local: $relative"
        }
        $document = Read-FrontMatterDocument $file.FullName
        if ($null -eq $document) { continue }
        $data = $document.Data
        foreach ($field in $allowedFields) {
            if (-not $data.ContainsKey($field)) { Add-Issue "$relative`: local mastery требует поле '$field'." }
        }
        foreach ($field in @($data.Keys)) {
            if ($field -cnotin $allowedFields) { Add-Issue "$relative`: local mastery closed-schema отвергает поле '$field'." }
        }
        foreach ($field in @('mastery_contract_version', 'method_id', 'method_kind', 'summary', 'owner_scope', 'status', 'verified_at', 'review_due', 'supersedes')) {
            if ($data.ContainsKey($field)) {
                $allowNull = $field -ceq 'supersedes'
                if (-not (& $script:mpkTestFrontMatterScalarValue -Value $data[$field] -AllowNull:$allowNull)) {
                    Add-Issue "$relative`: local mastery '$field' должен быть scalar$(if ($allowNull) { ' или null' } else { '' })."
                }
            }
        }

        $methodId = [string]$data.method_id
        if ([string]$data.mastery_contract_version -cne '2') {
            Add-Issue "$relative`: local mastery требует mastery_contract_version: 2."
        }
        if ($methodId -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?$') {
            Add-Issue "$relative`: invalid method_id."
        }
        elseif ($methodIds.ContainsKey($methodId)) {
            Add-Issue "Duplicate local method_id: $($methodIds[$methodId]) и $relative."
        }
        else { $methodIds[$methodId] = $relative }
        if ([System.IO.Path]::GetFileNameWithoutExtension($file.Name) -cne $methodId -or
            $file.DirectoryName -cne $localRoot) {
            Add-Issue "$relative`: filename должен совпадать с method_id в плоском mastery/local."
        }
        $methodKind = [string]$data.method_kind
        if ($methodKind -cnotin @('heuristic', 'checklist', 'workflow', 'standard')) {
            Add-Issue "$relative`: invalid method_kind."
        }
        $methodSummary = [string]$data.summary
        if ([string]::IsNullOrWhiteSpace($methodSummary) -or $methodSummary.Length -gt 160 -or
            $methodSummary -match '[\r\n\x00-\x08\x0B\x0C\x0E-\x1F\x7F]') {
            Add-Issue "$relative`: local mastery требует безопасный summary."
        }
        if ([string]$data.owner_scope -cne 'project') { Add-Issue "$relative`: local mastery требует owner_scope: project." }
        $status = [string]$data.status
        if ($status -cnotin @('active', 'deprecated', 'superseded')) { Add-Issue "$relative`: invalid local mastery status." }

        $appliesTo = if ($data.applies_to -is [System.Array]) { @($data.applies_to | ForEach-Object { [string]$_ }) } else { @() }
        if (-not ($data.applies_to -is [System.Array]) -or $appliesTo.Count -eq 0) {
            Add-Issue "$relative`: local mastery требует непустой applies_to list."
        }
        elseif (@($appliesTo | Sort-Object -Unique -CaseSensitive).Count -ne $appliesTo.Count) {
            Add-Issue "$relative`: applies_to содержит дубли."
        }
        foreach ($intent in $appliesTo) {
            if (-not $intentCatalog.Ids.Contains($intent)) { Add-Issue "$relative`: unknown applies_to '$intent'." }
        }

        $sources = if ($data.source_refs -is [System.Array]) { @($data.source_refs | ForEach-Object { [string]$_ }) } else { @() }
        if (-not ($data.source_refs -is [System.Array]) -or $sources.Count -ne 1) {
            Add-Issue "$relative`: local mastery требует ровно один candidate в source_refs."
        }
        elseif (@($sources | Sort-Object -Unique -CaseSensitive).Count -ne $sources.Count) {
            Add-Issue "$relative`: source_refs содержит дубли."
        }
        foreach ($source in $sources) {
            $resolvedMethodCandidate = Resolve-SafeReference -Value $source -Context "$relative source_refs" -MustExist
            if ($source -cnotmatch '^knowledge/candidates/\d{4}/(?<candidate>KC-\d{8}-\d{6}-[0-9a-f]{8})\.md$') {
                Add-Issue "$relative`: source_refs должен вести на exact method candidate path."
                continue
            }
            $methodCandidateId = [string]$Matches['candidate']
            if (-not $script:candidateMetadataMap.ContainsKey($methodCandidateId)) {
                Add-Issue "$relative`: source_refs ссылается на неизвестный candidate."
                continue
            }
            if ($null -ne $resolvedMethodCandidate -and $resolvedMethodCandidate.Kind -eq 'internal') {
                $candidateDocument = Read-FrontMatterDocument $resolvedMethodCandidate.FullPath
                if ($null -ne $candidateDocument) {
                    $candidateData = $candidateDocument.Data
                    if ([string]$candidateData.state -cne 'applied' -or
                        [string]$candidateData.type -cne 'method' -or
                        [string]$candidateData.domain -cne 'mastery' -or
                        [string]$candidateData.claim_key -cne "method.$methodId" -or
                        [string]$candidateData.method_kind -cne $methodKind -or
                        [string]$candidateData.method_summary -cne $methodSummary) {
                        Add-Issue "$relative`: Local Mastery metadata не совпадает с applied method candidate."
                    }
                    $candidateIntents = if ($candidateData.method_applies_to -is [System.Array]) {
                        @($candidateData.method_applies_to | ForEach-Object { [string]$_ })
                    }
                    else { @() }
                    if ($candidateIntents.Count -ne $appliesTo.Count -or
                        @(Compare-Object -ReferenceObject $candidateIntents -DifferenceObject $appliesTo -CaseSensitive).Count -gt 0) {
                        Add-Issue "$relative`: applies_to не совпадает с applied method candidate."
                    }
                }
            }
        }

        $verified = $null
        $due = $null
        if (-not (Test-DateOnly ([string]$data.verified_at))) {
            Add-Issue "$relative`: local mastery требует valid verified_at."
        }
        else {
            $verified = [datetime]::ParseExact([string]$data.verified_at, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            if ($verified.Date -gt [datetime]::Today) { Add-Issue "$relative`: verified_at находится в будущем." }
        }
        if (-not (Test-DateOnly ([string]$data.review_due))) {
            Add-Issue "$relative`: local mastery требует valid review_due."
        }
        else {
            $due = [datetime]::ParseExact([string]$data.review_due, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            if ($null -ne $verified -and $due.Date -lt $verified.Date) { Add-Issue "$relative`: review_due раньше verified_at." }
            if ($due.Date -lt [datetime]::Today) { Add-ReportItem -Category 'overdue' -Value "$relative -> $($data.review_due)" }
        }
        foreach ($finding in (Get-UnsafeFindings $document.Text)) {
            Add-Issue "$relative`: потенциально небезопасный материал в local mastery по эвристическому сигналу ($finding)."
        }

        $record = [pscustomobject]@{
            MethodId = $methodId
            Relative = $relative
            FullPath = $file.FullName
            Status = $status
            MethodKind = $methodKind
            Summary = $methodSummary
            AppliesTo = $appliesTo
            ReviewDue = $due
            Registered = $isRegistered
            Supersedes = $(if (Test-IsNullValue $data.supersedes) { '' } else { [string]$data.supersedes })
        }
        $records.Add($record) | Out-Null
        if (-not [string]::IsNullOrWhiteSpace($methodId) -and -not $script:localMethodMap.ContainsKey($methodId)) {
            $script:localMethodMap[$methodId] = $record
        }
    }

    $supersedesMap = @{}
    $incomingSupersedes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($record in $records) {
        if ([string]::IsNullOrWhiteSpace($record.Supersedes)) {
            continue
        }
        if ($record.Supersedes -ceq $record.MethodId) {
            Add-Issue "$($record.Relative): local mastery self-supersedes запрещен."
            continue
        }
        if (-not $script:localMethodMap.ContainsKey($record.Supersedes)) {
            Add-Issue "$($record.Relative): supersedes ссылается на missing method_id."
            continue
        }
        if ([string]$script:localMethodMap[$record.Supersedes].MethodId -cne $record.Supersedes) {
            Add-Issue "$($record.Relative): supersedes method_id требует exact case."
            continue
        }
        $supersededRecord = $script:localMethodMap[$record.Supersedes]
        if ([string]$supersededRecord.Status -cne 'superseded') {
            Add-Issue "$($record.Relative): supersedes target должен иметь status superseded."
        }
        $supersedesMap[$record.MethodId] = $record.Supersedes
        $incomingSupersedes.Add($record.Supersedes) | Out-Null
    }
    foreach ($record in $records) {
        if ($record.Status -ceq 'superseded' -and
            -not $incomingSupersedes.Contains([string]$record.MethodId)) {
            Add-Issue "$($record.Relative): superseded method требует incoming replacement edge."
        }
    }
    foreach ($start in @($supersedesMap.Keys)) {
        $path = @{}
        $current = [string]$start
        while ($supersedesMap.ContainsKey($current)) {
            if ($path.ContainsKey($current)) {
                Add-Issue "$start`: local-mastery-supersedes-cycle detected."
                break
            }
            $path[$current] = $true
            $current = [string]$supersedesMap[$current]
        }
    }
}

function Get-ExactResearchBulletValue {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $visible = Get-TopLevelMarkdownVisibleText -Text $Text
    $matches = @([regex]::Matches(
        $visible,
        '(?m)^-[ \t]+' + [regex]::Escape($Label) + ':[ \t]*(?<value>[^\r\n]*)[ \t]*$'
    ))
    if ($matches.Count -ne 1) {
        Add-Issue "$Context`: требуется ровно одно поле '$Label'."
        return $null
    }
    return ([string]$matches[0].Groups['value'].Value).Trim()
}

function Convert-ResearchBracketList {
    param(
        $Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string]$ItemPattern
    )

    if ($null -eq $Value) { return [pscustomobject]@{ Valid = $false; Items = @() } }
    $text = [string]$Value
    if ($text -ceq '[]') { return [pscustomobject]@{ Valid = $true; Items = @() } }
    if ($text -cnotmatch '^\[(?<items>[^\[\]]+)\]$') {
        Add-Issue "$Context`: требуется bracket-list без кавычек."
        return [pscustomobject]@{ Valid = $false; Items = @() }
    }
    $items = @($Matches['items'].Split(',') | ForEach-Object { $_.Trim() })
    if ($items.Count -eq 0 -or @($items | Where-Object { $_ -cnotmatch $ItemPattern }).Count -gt 0) {
        Add-Issue "$Context`: list содержит недопустимое значение."
        return [pscustomobject]@{ Valid = $false; Items = @() }
    }
    if (@($items | Sort-Object -Unique -CaseSensitive).Count -ne $items.Count) {
        Add-Issue "$Context`: list содержит дубли."
        return [pscustomobject]@{ Valid = $false; Items = @() }
    }
    return [pscustomobject]@{ Valid = $true; Items = $items }
}

function Test-ResearchBaselineReference {
    param(
        $Value,
        [Parameter(Mandatory = $true)][string]$Context,
        [switch]$Method,
        [switch]$AllowNotApplicable
    )

    if ($null -eq $Value) { return $null }
    $reference = ([string]$Value).Trim()
    if ($reference.Length -ge 2 -and $reference.StartsWith('`') -and $reference.EndsWith('`')) {
        $reference = $reference.Substring(1, $reference.Length - 2)
    }
    if ($AllowNotApplicable -and $reference -ceq 'не применимо') { return $reference }
    if ([string]::IsNullOrWhiteSpace($reference)) {
        Add-Issue "$Context`: baseline ref не заполнен."
        return $null
    }
    $resolved = Resolve-SafeReference -Value $reference -Context $Context -MustExist
    if ($reference -cnotmatch '^mastery/researcher/(?!INDEX\.md$)[A-Za-z0-9._/-]+\.md(?:#[^#]+)?$') {
        Add-Issue "$Context`: baseline ref должен вести в зарегистрированный researcher profile."
    }
    if ($Method -and -not $reference.Contains('#')) {
        Add-Issue "$Context`: baseline method ref требует точный Markdown anchor."
    }
    if (-not $Method -and $reference.Contains('#')) {
        Add-Issue "$Context`: baseline profile ref не должен содержать anchor."
    }
    return $reference
}

function Test-ResearchMethodReferences {
    $runsRoot = [System.IO.Path]::Combine($script:verificationRoot, 'research', 'runs')
    if (-not (Test-Path -LiteralPath $runsRoot -PathType Container)) { return }
    foreach ($run in (Get-ChildItem -LiteralPath $runsRoot -Directory -Force)) {
        if (($run.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $briefPath = Join-Path $run.FullName 'brief.md'
        $decisionPath = Join-Path $run.FullName 'decision.md'
        if (-not (Test-Path -LiteralPath $briefPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $decisionPath -PathType Leaf)) { continue }
        $runRelative = Get-RelativePath $run.FullName
        $briefText = Read-BoundedUtf8Text -FilePath $briefPath -Context "$runRelative/brief.md method refs"
        $decisionText = Read-BoundedUtf8Text -FilePath $decisionPath -Context "$runRelative/decision.md method refs"
        if ($null -eq $briefText -or $null -eq $decisionText) { continue }

        $briefProfile = Test-ResearchBaselineReference `
            -Value (Get-ExactResearchBulletValue -Text $briefText -Label 'Основной baseline profile ref' -Context "$runRelative/brief.md") `
            -Context "$runRelative/brief.md baseline profile"
        $briefMethod = Test-ResearchBaselineReference `
            -Value (Get-ExactResearchBulletValue -Text $briefText -Label 'Основной baseline method ref' -Context "$runRelative/brief.md") `
            -Context "$runRelative/brief.md baseline method" `
            -Method
        $decisionMethod = Test-ResearchBaselineReference `
            -Value (Get-ExactResearchBulletValue -Text $decisionText -Label 'Основной baseline method ref' -Context "$runRelative/decision.md") `
            -Context "$runRelative/decision.md baseline method" `
            -Method
        if ($null -ne $briefMethod -and $null -ne $decisionMethod -and $briefMethod -cne $decisionMethod) {
            Add-Issue "$runRelative`: brief и decision используют разные main baseline method refs."
        }
        if ($null -ne $briefProfile -and $null -ne $briefMethod -and
            $briefMethod.Split('#', 2)[0] -cne $briefProfile) {
            Add-Issue "$runRelative`: main baseline profile и method ref указывают на разные файлы."
        }
        $briefComplementaryProfile = Test-ResearchBaselineReference `
            -Value (Get-ExactResearchBulletValue -Text $briefText -Label 'Дополняющий baseline profile ref' -Context "$runRelative/brief.md") `
            -Context "$runRelative/brief.md complementary baseline profile" `
            -AllowNotApplicable
        $briefComplementary = Test-ResearchBaselineReference `
            -Value (Get-ExactResearchBulletValue -Text $briefText -Label 'Дополняющий baseline method ref' -Context "$runRelative/brief.md") `
            -Context "$runRelative/brief.md complementary baseline method" `
            -Method `
            -AllowNotApplicable
        $decisionComplementary = Test-ResearchBaselineReference `
            -Value (Get-ExactResearchBulletValue -Text $decisionText -Label 'Дополняющий baseline method ref' -Context "$runRelative/decision.md") `
            -Context "$runRelative/decision.md complementary baseline method" `
            -Method `
            -AllowNotApplicable
        if ($null -ne $briefComplementary -and $null -ne $decisionComplementary -and
            $briefComplementary -cne $decisionComplementary) {
            Add-Issue "$runRelative`: brief и decision используют разные complementary baseline method refs."
        }
        if ($null -ne $briefComplementaryProfile -and $null -ne $briefComplementary) {
            $profileNotApplicable = $briefComplementaryProfile -ceq 'не применимо'
            $methodNotApplicable = $briefComplementary -ceq 'не применимо'
            if ($profileNotApplicable -ne $methodNotApplicable) {
                Add-Issue "$runRelative`: complementary baseline profile и method ref должны быть одновременно применимы."
            }
            elseif (-not $profileNotApplicable -and
                $briefComplementary.Split('#', 2)[0] -cne $briefComplementaryProfile) {
                Add-Issue "$runRelative`: complementary baseline profile и method ref указывают на разные файлы."
            }
        }

        $briefIds = Convert-ResearchBracketList `
            -Value (Get-ExactResearchBulletValue -Text $briefText -Label 'Local method IDs' -Context "$runRelative/brief.md") `
            -Context "$runRelative/brief.md Local method IDs" `
            -ItemPattern '^[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?$'
        $briefRefs = Convert-ResearchBracketList `
            -Value (Get-ExactResearchBulletValue -Text $briefText -Label 'Local method refs' -Context "$runRelative/brief.md") `
            -Context "$runRelative/brief.md Local method refs" `
            -ItemPattern '^mastery/local/[A-Za-z0-9._/-]+\.md$'
        $decisionIds = Convert-ResearchBracketList `
            -Value (Get-ExactResearchBulletValue -Text $decisionText -Label 'Local method IDs' -Context "$runRelative/decision.md") `
            -Context "$runRelative/decision.md Local method IDs" `
            -ItemPattern '^[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?$'
        $decisionRefs = Convert-ResearchBracketList `
            -Value (Get-ExactResearchBulletValue -Text $decisionText -Label 'Local method refs' -Context "$runRelative/decision.md") `
            -Context "$runRelative/decision.md Local method refs" `
            -ItemPattern '^mastery/local/[A-Za-z0-9._/-]+\.md$'
        if (-not ($briefIds.Valid -and $briefRefs.Valid -and $decisionIds.Valid -and $decisionRefs.Valid)) { continue }
        if ($briefIds.Items.Count -gt 1 -or $briefRefs.Items.Count -gt 1) {
            Add-Issue "$runRelative`: research run может использовать максимум один local method."
        }
        if ($briefIds.Items.Count -ne $briefRefs.Items.Count -or
            $decisionIds.Items.Count -ne $decisionRefs.Items.Count) {
            Add-Issue "$runRelative`: Local method IDs и refs должны иметь одинаковую длину."
        }
        if (($briefIds.Items -join "`n") -cne ($decisionIds.Items -join "`n") -or
            ($briefRefs.Items -join "`n") -cne ($decisionRefs.Items -join "`n")) {
            Add-Issue "$runRelative`: local method refs в brief и decision должны совпадать."
        }
        for ($i = 0; $i -lt [Math]::Min($briefIds.Items.Count, $briefRefs.Items.Count); $i++) {
            $methodId = [string]$briefIds.Items[$i]
            $methodRef = [string]$briefRefs.Items[$i]
            if (-not $script:localMethodMap.ContainsKey($methodId)) {
                Add-Issue "$runRelative`: unknown local method ID."
                continue
            }
            $metadata = $script:localMethodMap[$methodId]
            if ([string]$metadata.MethodId -cne $methodId) {
                Add-Issue "$runRelative`: local method ID требует exact case."
            }
            if ([string]$metadata.Relative -cne $methodRef) {
                Add-Issue "$runRelative`: local method ref не соответствует method_id."
            }
            Resolve-SafeReference -Value $methodRef -Context "$runRelative local method ref" -MustExist | Out-Null
            if (-not $metadata.Registered) { Add-Issue "$runRelative`: local method не зарегистрирован." }
            if ([string]$metadata.Status -cne 'active') { Add-Issue "$runRelative`: local method не active." }
            if ($null -eq $metadata.ReviewDue -or $metadata.ReviewDue.Date -lt [datetime]::Today) {
                Add-Issue "$runRelative`: local method overdue."
            }
        }
    }
}

function Get-JsonProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Convert-ToOriginIdentityValue {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [switch]$Url
    )

    $trimmed = $Value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $null }
    if (-not $Url) {
        return $trimmed.TrimEnd('/').ToLowerInvariant()
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($trimmed, [System.UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ine 'https' -or
        [string]::IsNullOrWhiteSpace($uri.Host) -or
        -not [string]::IsNullOrWhiteSpace($uri.UserInfo)) {
        return $null
    }
    $normalizedHost = $uri.IdnHost.ToLowerInvariant()
    if ($normalizedHost.Contains(':') -and -not $normalizedHost.StartsWith('[')) {
        $normalizedHost = "[$normalizedHost]"
    }
    $port = if ($uri.IsDefaultPort) { '' } else { ':' + $uri.Port }
    return (
        $uri.Scheme.ToLowerInvariant() +
        '://' +
        $normalizedHost +
        $port +
        $uri.AbsolutePath
    )
}

function Test-ResearchRunInventoryAndSafety {
    $assetsRoot = [System.IO.Path]::Combine(
        $script:verificationRoot,
        '.agents',
        'skills',
        'startup-researcher',
        'assets',
        'run-template'
    )
    if (-not (Test-Path -LiteralPath $assetsRoot -PathType Container)) {
        Add-Issue 'research-run-contract: startup-researcher run-template assets отсутствуют.'
        return
    }
    if ($null -ne (Get-ReparsePointInPath $assetsRoot)) {
        Add-Issue 'research-run-contract: run-template assets проходят через reparse point.'
        return
    }
    $assetFiles = @(Get-ChildItem -LiteralPath $assetsRoot -File -Force)
    $expectedNames = @($assetFiles | ForEach-Object { $_.Name } | Sort-Object)
    if ($expectedNames.Count -ne 6 -or
        @($expectedNames | Where-Object { $_ -cnotin @(
            'brief.md', 'queries.md', 'evidence.jsonl', 'candidates.md', 'red-team.md', 'decision.md'
        ) }).Count -gt 0) {
        Add-Issue 'research-run-contract: assets должны задавать exact six-file scaffold.'
        return
    }

    $runsRoot = [System.IO.Path]::Combine($script:verificationRoot, 'research', 'runs')
    if (-not (Test-Path -LiteralPath $runsRoot -PathType Container)) { return }
    if ($null -ne (Get-ReparsePointInPath $runsRoot)) {
        Add-Issue 'research/runs проходит через reparse point.'
        return
    }
    foreach ($rootFile in (Get-ChildItem -LiteralPath $runsRoot -File -Force)) {
        if ($rootFile.Name -cne '.gitkeep') {
            Add-Issue "research-run-contract: недопустимый root file '$($rootFile.Name)'."
        }
    }
    foreach ($runDirectory in (Get-ChildItem -LiteralPath $runsRoot -Directory -Force)) {
        $runRelative = Get-RelativePath $runDirectory.FullName
        if (($runDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-Issue "research-run-contract: reparse run directory $runRelative."
            continue
        }
        if ($runDirectory.Name -cnotmatch '^\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*$') {
            Add-Issue "$runRelative`: research-run-name должен быть YYYY-MM-DD-slug."
        }
        foreach ($nested in (Get-ChildItem -LiteralPath $runDirectory.FullName -Directory -Force)) {
            Add-Issue "$runRelative`: nested research directory запрещен."
        }
        $actualFiles = @(Get-ChildItem -LiteralPath $runDirectory.FullName -File -Force)
        $actualNames = @($actualFiles | ForEach-Object { $_.Name })
        foreach ($expectedName in $expectedNames) {
            if ($actualNames -cnotcontains $expectedName) {
                Add-Issue "$runRelative`: research-run-incomplete: missing $expectedName."
            }
        }
        foreach ($actualFile in $actualFiles) {
            if (($actualFile.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Add-Issue "$runRelative`: research file является reparse point."
                continue
            }
            if ($actualFile.Name -ceq 'promotion-proposal.md') {
                Add-Issue "$runRelative`: research-run-extra: promotion-proposal.md запрещен."
                continue
            }
            if ($actualFile.Name -cnotin $expectedNames) {
                Add-Issue "$runRelative`: research-run-extra: $($actualFile.Name)."
                continue
            }
            if ($actualFile.Name -cne 'evidence.jsonl') {
                $researchText = Read-BoundedUtf8Text `
                    -FilePath $actualFile.FullName `
                    -Context "$runRelative/$($actualFile.Name)"
                if ($null -ne $researchText) {
                    foreach ($finding in (Get-UnsafeFindings $researchText)) {
                        Add-Issue "$runRelative/$($actualFile.Name): data-safety finding in research artifact ($finding)."
                    }
                }
            }
        }
    }
}

function Test-ResearchEvidence {
    $script:evidenceIdMap = @{}
    $script:evidenceDecisionRefMap = @{}
    $script:researchRunEvidenceIds = @{}
    $evidenceRoot = [System.IO.Path]::Combine($script:verificationRoot, 'research', 'runs')
    if (-not (Test-Path -LiteralPath $evidenceRoot -PathType Container)) { return }
    $rootReparse = Get-ReparsePointInPath $evidenceRoot
    if ($null -ne $rootReparse) {
        Add-Issue "research/runs проходит через reparse point: $(Get-RelativePath $rootReparse)"
        return
    }

    $originIdentityMap = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
    $observationFingerprintMap = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::Ordinal
    )
    $runIds = $script:researchRunEvidenceIds
    $ledgers = @(Get-ChildItem -LiteralPath $evidenceRoot -Recurse -File -Filter 'evidence.jsonl' -Force)
    if ($ledgers.Count -gt $maxEvidenceLedgers) {
        Add-Issue "Research evidence: слишком много ledgers ($($ledgers.Count)), limit=$maxEvidenceLedgers."
        return
    }
    $totalRecordCount = 0
    $totalEvidenceBytes = [long]0
    foreach ($file in $ledgers) {
        $relative = Get-RelativePath $file.FullName
        if ($file.Name -cne 'evidence.jsonl') {
            Add-Issue "$relative`: research evidence filename должен быть exact-case evidence.jsonl."
            continue
        }
        if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-Issue "Reparse point evidence ledger: $relative"
            continue
        }
        if ($file.Length -gt $maxEvidenceFileBytes) {
            Add-Issue "$relative`: evidence file превышает limit $maxEvidenceFileBytes bytes."
            continue
        }
        $totalEvidenceBytes += $file.Length
        if ($totalEvidenceBytes -gt $maxEvidenceCorpusBytes) {
            Add-Issue "Research evidence: corpus bytes превышают limit $maxEvidenceCorpusBytes."
            return
        }
        $runDirectory = Split-Path -Parent $file.FullName
        $decisionSiblings = @(
            Get-ChildItem -LiteralPath $runDirectory -File -Force -Filter 'decision.md' |
                Where-Object { $_.Name -ceq 'decision.md' }
        )
        if ($decisionSiblings.Count -ne 1) {
            Add-Issue "$relative`: research run требует ровно один sibling decision.md."
        }
        $runKey = $runDirectory.ToLowerInvariant()
        if (-not $runIds.ContainsKey($runKey)) { $runIds[$runKey] = @{} }
        $lineNumber = 0
        $recordCount = 0
        $readReparse = Get-ReparsePointInPath $file.FullName
        if ($null -ne $readReparse) {
            Add-Issue "$relative`: evidence ledger проходит через reparse point непосредственно перед чтением."
            continue
        }
        $lineEnumerator = [System.IO.File]::ReadLines($file.FullName, $utf8Strict).GetEnumerator()
        try {
            while ($lineEnumerator.MoveNext()) {
                $line = [string]$lineEnumerator.Current
                $lineNumber++
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $recordCount++
                $totalRecordCount++
                $context = "$relative`:$lineNumber"
                if ($line.Length -gt $maxEvidenceLineChars) {
                    Add-Issue "$context`: evidence line превышает char limit $maxEvidenceLineChars."
                    continue
                }
                if ($recordCount -gt $maxEvidenceRecordsPerFile) {
                    Add-Issue "$relative`: evidence records превышают limit $maxEvidenceRecordsPerFile."
                    break
                }
                if ($totalRecordCount -gt $maxEvidenceRecordsTotal) {
                    Add-Issue "Research evidence: total records превышают limit $maxEvidenceRecordsTotal."
                    return
                }
                try {
                    $row = $line | ConvertFrom-Json
                }
                catch {
                    Add-Issue "$context`: corrupted evidence JSONL."
                    continue
                }
                if ($null -eq $row -or $row -is [System.Array] -or $row -is [string] -or $row -is [ValueType]) {
                    Add-Issue "$context`: каждая строка evidence должна быть JSON-объектом."
                    continue
                }
                $propertyNames = @($row.PSObject.Properties.Name)
                $schemaInvalid = $false
                foreach ($field in $evidenceFields) {
                    if ($field -cnotin $propertyNames) {
                        Add-Issue "$context`: отсутствует evidence field '$field'."
                        $schemaInvalid = $true
                    }
                }
                foreach ($field in @($propertyNames | Where-Object { $_ -cnotin $evidenceFields })) {
                    Add-Issue "$context`: evidence содержит неизвестное поле."
                    $schemaInvalid = $true
                }
                foreach ($property in $row.PSObject.Properties) {
                    if (-not (& $script:mpkTestJsonScalar -Value $property.Value)) {
                        Add-Issue "$context`: evidence field '$($property.Name)' должен быть scalar."
                        $schemaInvalid = $true
                    }
                }
                if ($schemaInvalid) { continue }

                $evidenceId = [string](Get-JsonProperty -Object $row -Name 'evidence_id')
                $claimId = [string](Get-JsonProperty -Object $row -Name 'claim_id')
                $originGroup = [string](Get-JsonProperty -Object $row -Name 'origin_group_id')
                if ($evidenceId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') {
                    Add-Issue "$context`: invalid evidence_id."
                }
                elseif ($script:evidenceIdMap.ContainsKey($evidenceId)) {
                    Add-Issue "Duplicate evidence ID: $($script:evidenceIdMap[$evidenceId]) и $context."
                }
                else {
                    $script:evidenceIdMap[$evidenceId] = $context
                    $runIds[$runKey][$evidenceId] = $true
                    $runRelative = Get-RelativePath $runDirectory
                    $script:evidenceDecisionRefMap[$evidenceId] = (
                        $runRelative.TrimEnd('/') + '/decision.md'
                    )
                }
                if ($claimId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') {
                    Add-Issue "$context`: invalid claim_id."
                }
                if ($originGroup -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') {
                    Add-Issue "$context`: invalid origin_group_id."
                }
                if ([string](Get-JsonProperty -Object $row -Name 'stance') -cnotin @('supports', 'contradicts', 'context')) {
                    Add-Issue "$context`: invalid stance."
                }
                $emptyFields = @($evidenceFields | Where-Object {
                    $value = Get-JsonProperty -Object $row -Name $_
                    $null -eq $value -or ([string]$value).Trim() -ceq ''
                })
                if ($emptyFields.Count -gt 0 -and
                    [string]::IsNullOrWhiteSpace([string](Get-JsonProperty -Object $row -Name 'limitations'))) {
                    Add-Issue "$context`: пустые evidence fields требуют объяснение в limitations: $($emptyFields -join ', ')."
                }

                $safeUrlIdentityFields = @{}
                foreach ($urlField in @('source_url', 'original_source_url', 'syndication_or_quote_of')) {
                    $url = [string](Get-JsonProperty -Object $row -Name $urlField)
                    if ([string]::IsNullOrWhiteSpace($url)) { continue }
                    if ($url -notmatch '^(?i:https://)') {
                        Add-Issue "$context`: $urlField должен быть https URL или пустым."
                        continue
                    }
                    Resolve-SafeReference -Value $url -Context "$context $urlField" -AllowExternal | Out-Null
                    if ($null -eq (& $script:mpkGetHttpsUrlSafetyFinding -Value $url)) {
                        $safeUrlIdentityFields[$urlField] = $true
                    }
                }

                $injectionFlag = Get-JsonProperty -Object $row -Name 'prompt_injection_detected'
                if ($injectionFlag -isnot [bool] -and -not [string]::IsNullOrWhiteSpace([string]$injectionFlag)) {
                    Add-Issue "$context`: prompt_injection_detected должен быть boolean или пустым."
                }
                foreach ($property in $row.PSObject.Properties) {
                    if ($property.Value -isnot [string]) { continue }
                    if ([string]::IsNullOrEmpty([string]$property.Value)) { continue }
                    foreach ($finding in (Get-UnsafeFindings ([string]$property.Value))) {
                        Add-Issue "$context`: evidence field '$($property.Name)' содержит потенциально небезопасный материал по эвристическому сигналу ($finding)."
                    }
                }

                $sourceIdentity = ''
                foreach ($sourceField in @('original_source_url', 'syndication_or_quote_of', 'source_url')) {
                    if (-not $safeUrlIdentityFields.ContainsKey($sourceField)) { continue }
                    $sourceIdentity = Convert-ToOriginIdentityValue `
                        -Value ([string](Get-JsonProperty -Object $row -Name $sourceField)) `
                        -Url
                    if (-not [string]::IsNullOrWhiteSpace($sourceIdentity)) { break }
                }
                if ([string]::IsNullOrWhiteSpace($sourceIdentity)) {
                    $sourceIdentity = Convert-ToOriginIdentityValue `
                        -Value ([string](Get-JsonProperty -Object $row -Name 'dataset_origin'))
                }
                $observationValue = (
                    [regex]::Replace(
                        ([string](Get-JsonProperty -Object $row -Name 'observation')).Trim(),
                        '\s+',
                        ' '
                    )
                )
                $locatorValue = (
                    [regex]::Replace(
                        ([string](Get-JsonProperty -Object $row -Name 'locator')).Trim(),
                        '\s+',
                        ' '
                    )
                )
                if (-not [string]::IsNullOrWhiteSpace($claimId) -and
                    -not [string]::IsNullOrWhiteSpace($sourceIdentity) -and
                    -not [string]::IsNullOrWhiteSpace($locatorValue) -and
                    -not [string]::IsNullOrWhiteSpace($observationValue)) {
                    $separator = [string][char]31
                    $observationFingerprint = (
                        $claimId + $separator + $sourceIdentity + $separator +
                        $locatorValue + $separator + $observationValue
                    )
                    if ($observationFingerprintMap.ContainsKey($observationFingerprint)) {
                        Add-Issue "$context`: duplicate research observation."
                    }
                    else {
                        $observationFingerprintMap[$observationFingerprint] = $context
                    }
                }

                $identityValues = @(
                    @('dataset_origin', [string](Get-JsonProperty -Object $row -Name 'dataset_origin')),
                    @('original_source_url', [string](Get-JsonProperty -Object $row -Name 'original_source_url')),
                    @('syndication_or_quote_of', [string](Get-JsonProperty -Object $row -Name 'syndication_or_quote_of')),
                    @('content_fingerprint', [string](Get-JsonProperty -Object $row -Name 'content_fingerprint')),
                    @('source_url', [string](Get-JsonProperty -Object $row -Name 'source_url'))
                )
                foreach ($identityPair in $identityValues) {
                    $identityField = [string]$identityPair[0]
                    $isUrlIdentity = $identityField -cin @('source_url', 'original_source_url', 'syndication_or_quote_of')
                    if ($isUrlIdentity -and -not $safeUrlIdentityFields.ContainsKey($identityField)) {
                        continue
                    }
                    $identityValue = Convert-ToOriginIdentityValue -Value ([string]$identityPair[1]) -Url:$isUrlIdentity
                    if ([string]::IsNullOrWhiteSpace($identityValue)) { continue }
                    $identityNamespace = if ($isUrlIdentity) {
                        'url'
                    }
                    else {
                        $identityField
                    }
                    $identityKey = '{0}:{1}' -f $identityNamespace, $identityValue
                    if ($originIdentityMap.ContainsKey($identityKey) -and
                        [string]$originIdentityMap[$identityKey].Group -cne $originGroup) {
                        Add-Issue "$context`: duplicate origin group assignment для '$identityNamespace' identity."
                    }
                    elseif (-not $originIdentityMap.ContainsKey($identityKey)) {
                        $originIdentityMap[$identityKey] = [pscustomobject]@{ Group = $originGroup; Context = $context }
                    }
                }
            }
        }
        catch {
            Add-Issue "$relative`: evidence file не удалось прочитать как строгий UTF-8."
        }
        finally {
            if ($lineEnumerator -is [System.IDisposable]) {
                $lineEnumerator.Dispose()
            }
        }
    }

    foreach ($runDirectory in (Get-ChildItem -LiteralPath $evidenceRoot -Recurse -Directory -Force)) {
        if (($runDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-Issue "Reparse point research run: $(Get-RelativePath $runDirectory.FullName)"
        }
    }
}

function Initialize-ResearchCandidateAssociations {
    $script:researchDecisionCandidateIds = @{}

    foreach ($candidateId in @($script:candidateMetadataMap.Keys)) {
        $metadata = $script:candidateMetadataMap[$candidateId]
        $explicitDecisionRefs = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        $evidenceDecisionRefs = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        $analysisRunIds = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        $analysisDecisionRefs = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($normalizedSourcePath in @($metadata.ResolvedInternalSourcePaths)) {
            $sourcePath = [string]$normalizedSourcePath
            if ($sourcePath -match '^research/runs/.+/decision\.md$') {
                $explicitDecisionRefs.Add($sourcePath) | Out-Null
            }
            if ($sourcePath -match '^analysis/runs/(?<run>[^/]+)/(?<asset>[^/]+\.md)$') {
                $analysisRunIds.Add([string]$Matches['run']) | Out-Null
                if ([string]$Matches['asset'] -ceq 'decision.md') {
                    $analysisDecisionRefs.Add($sourcePath) | Out-Null
                }
            }
        }
        foreach ($sourceRef in @($metadata.SourceRefs)) {
            $sourceText = [string]$sourceRef
            if ($sourceText -match '^evidence:(.+)$' -and
                $script:evidenceDecisionRefMap.ContainsKey($Matches[1])) {
                $evidenceDecisionRefs.Add([string]$script:evidenceDecisionRefMap[$Matches[1]]) | Out-Null
            }
        }

        $hasResearchSource = $explicitDecisionRefs.Count -gt 0 -or $evidenceDecisionRefs.Count -gt 0
        if ($hasResearchSource -and [string]$metadata.CaptureBasis -cne 'research-derived') {
            Add-Issue "$($metadata.Relative): candidate с research source требует capture_basis research-derived."
        }
        if ([string]$metadata.CaptureBasis -ceq 'research-derived') {
            if ($explicitDecisionRefs.Count -eq 0) {
                Add-Issue "$($metadata.Relative): research-derived candidate требует точный source_ref на decision.md."
            }
            if ($evidenceDecisionRefs.Count -eq 0) {
                Add-Issue "$($metadata.Relative): research-derived candidate требует source_ref на evidence текущего run."
            }
            foreach ($explicitDecision in $explicitDecisionRefs) {
                if (-not $evidenceDecisionRefs.Contains($explicitDecision)) {
                    Add-Issue "$($metadata.Relative): research-derived candidate требует evidence из run своего decision.md."
                }
            }
        }

        foreach ($analysisRunId in $analysisRunIds) {
            $analysisDecisionRef = "analysis/runs/$analysisRunId/decision.md"
            if (-not $analysisDecisionRefs.Contains($analysisDecisionRef)) {
                Add-Issue "$($metadata.Relative): source из analysis run требует exact source_ref на decision.md того же run."
                continue
            }
            $analysisDecisionPath = Join-Path $script:verificationRoot $analysisDecisionRef
            $analysisDecision = Read-FrontMatterDocument $analysisDecisionPath
            if ($null -eq $analysisDecision) { continue }
            $analysisData = $analysisDecision.Data
            $analysisBasis = if (& $script:mpkTestFrontMatterScalarValue -Value $analysisData.capture_basis) { [string]$analysisData.capture_basis } else { '' }
            if ([string]$analysisData.run_status -cne 'completed' -or [string]$analysisData.decision_outcome -cne 'handoff') {
                Add-Issue "$($metadata.Relative): analysis source требует completed handoff decision."
            }
            if ($analysisBasis -cnotin @('repo-derived', 'explicit-user-capture', 'research-derived') -or [string]$metadata.CaptureBasis -cne $analysisBasis) {
                Add-Issue "$($metadata.Relative): candidate обязан наследовать capture_basis analysis handoff."
            }
            $analysisProvenance = if ($analysisData.provenance_refs -is [System.Array]) {
                @($analysisData.provenance_refs | ForEach-Object { [string]$_ })
            }
            else { @() }
            if ($analysisBasis -ceq 'research-derived') {
                foreach ($provenanceRef in @($analysisProvenance | Where-Object { $_ -match '^evidence:' })) {
                    if (@($metadata.SourceRefs) -cnotcontains $provenanceRef) {
                        Add-Issue "$($metadata.Relative): research-derived candidate не наследует evidence ref analysis handoff."
                    }
                }
            }
            if ($analysisBasis -ceq 'explicit-user-capture') {
                $userRefs = @($analysisProvenance | Where-Object { $_ -match '^user-request:' })
                if ($userRefs.Count -eq 0 -or $userRefs -cnotcontains [string]$metadata.AuthorityRef) {
                    Add-Issue "$($metadata.Relative): explicit-user candidate не наследует user authority analysis handoff."
                }
            }
        }

        $associatedDecisionRefs = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($decisionRef in $explicitDecisionRefs) {
            $associatedDecisionRefs.Add($decisionRef) | Out-Null
        }
        if ($explicitDecisionRefs.Count -eq 0) {
            foreach ($decisionRef in $evidenceDecisionRefs) {
                $associatedDecisionRefs.Add($decisionRef) | Out-Null
            }
        }
        foreach ($decisionRef in $associatedDecisionRefs) {
            if (-not $script:researchDecisionCandidateIds.ContainsKey($decisionRef)) {
                $script:researchDecisionCandidateIds[$decisionRef] =
                    [System.Collections.Generic.List[string]]::new()
            }
            $script:researchDecisionCandidateIds[$decisionRef].Add([string]$candidateId)
        }
    }
}

function Test-ResearchDecisionKnowledgeOutcome {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$RelativeDecision,
        [Parameter(Mandatory = $true)]$RunEvidenceIds
    )

    $visibleText = Get-TopLevelMarkdownVisibleText -Text $Text
    $sectionMatches = [regex]::Matches(
        $visibleText,
        '(?ms)^##[ \t]+Knowledge outcome[ \t]*\r?\n(?<body>.*?)(?=^ {0,3}#{1,2}[ \t]+|\z)'
    )
    if ($sectionMatches.Count -ne 1) {
        Add-Issue "$RelativeDecision`: требуется ровно один структурный раздел Knowledge outcome."
        return
    }

    $sectionBody = $sectionMatches[0].Groups['body'].Value
    $outcomeMatches = [regex]::Matches(
        $sectionBody,
        '(?m)^-[ \t]+Основной результат closeout:[ \t]*(?<value>\S+)[ \t]*$'
    )
    $candidateListMatches = [regex]::Matches(
        $sectionBody,
        '(?m)^-[ \t]+Central candidate IDs в порядке влияния на решение:[ \t]*(?<value>\[[^\r\n]{0,510}\])[ \t]*$'
    )
    $writeIntentMatches = [regex]::Matches(
        $sectionBody,
        '(?m)^-[ \t]+Write intent:[ \t]*(?<value>\S+)[ \t]*$'
    )
    $authorityMatches = [regex]::Matches(
        $sectionBody,
        '(?m)^-[ \t]+Authority ref:[ \t]*(?<value>\S+)[ \t]*$'
    )
    $blockedReasonMatches = [regex]::Matches(
        $sectionBody,
        '(?m)^-[ \t]+Причина `blocked`:[ \t]*(?<value>[^\r\n]+?)[ \t]*$'
    )
    $affectedCanonMatches = [regex]::Matches(
        $sectionBody,
        '(?m)^-[ \t]+Затронутый канон:[ \t]*(?<value>[^\r\n]+?)[ \t]*$'
    )
    if ($outcomeMatches.Count -ne 1) {
        Add-Issue "$RelativeDecision`: Knowledge outcome требует одно машинно-читаемое поле основного результата."
        return
    }
    if ($candidateListMatches.Count -ne 1) {
        Add-Issue "$RelativeDecision`: Knowledge outcome требует один машинно-читаемый список Central candidate IDs."
        return
    }
    $legacySelfTestMachineFields = (
        $SelfTest -and
        ($writeIntentMatches.Count -ne 1 -or $authorityMatches.Count -ne 1 -or
            $blockedReasonMatches.Count -ne 1 -or $affectedCanonMatches.Count -ne 1)
    )
    if (-not $legacySelfTestMachineFields -and
        ($writeIntentMatches.Count -ne 1 -or $authorityMatches.Count -ne 1 -or
            $blockedReasonMatches.Count -ne 1 -or $affectedCanonMatches.Count -ne 1)) {
        Add-Issue "$RelativeDecision`: Knowledge outcome требует exact Write intent, Authority ref, Причина blocked и Затронутый канон."
        return
    }
    $outcomeMatch = $outcomeMatches[0]
    $candidateListMatch = $candidateListMatches[0]

    $outcome = $outcomeMatch.Groups['value'].Value
    if ($legacySelfTestMachineFields) {
        $writeIntent = if ($outcome -cmatch '^ready:') { 'automatic-capture' } elseif ($outcome -cmatch '^applied:') { 'explicit-promotion' } else { 'none' }
        $authorityRef = if ($writeIntent -ceq 'automatic-capture') { 'policy:knowledge-contract-v1' } elseif ($writeIntent -ceq 'explicit-promotion') { 'user-request:selftest-promotion' } else { 'null' }
        $blockedReason = if ($outcome -ceq 'blocked') { 'missing-provenance' } else { 'не применимо' }
        $affectedCanon = if ($outcome -cmatch '^applied:') { 'docs/target.md' } else { 'нет' }
    }
    else {
        $writeIntent = [string]$writeIntentMatches[0].Groups['value'].Value
        $authorityRef = [string]$authorityMatches[0].Groups['value'].Value
        $blockedReason = ([string]$blockedReasonMatches[0].Groups['value'].Value).Trim().Trim('`')
        $affectedCanon = ([string]$affectedCanonMatches[0].Groups['value'].Value).Trim().Trim('`')
    }
    $allowedBlockedReasons = @(
        'capture-disabled',
        'report-only',
        'shared-owner',
        'missing-provenance',
        'missing-diff-baseline',
        'missing-git-baseline',
        'unsafe-data',
        'candidate-dismissed'
    )
    if ($outcome -ceq 'blocked') {
        if ($blockedReason -cnotin $allowedBlockedReasons) {
            Add-Issue "$RelativeDecision`: blocked outcome требует допустимую Причина blocked."
        }
    }
    elseif ($blockedReason -cne 'не применимо') {
        Add-Issue "$RelativeDecision`: Причина blocked должна быть 'не применимо' для неблокированного outcome."
    }
    if ($writeIntent -cnotin @('none', 'automatic-capture', 'explicit-promotion')) {
        Add-Issue "$RelativeDecision`: invalid research Write intent."
    }
    switch ($writeIntent) {
        'none' {
            if ($authorityRef -cne 'null') {
                Add-Issue "$RelativeDecision`: Write intent none требует Authority ref null."
            }
        }
        'automatic-capture' {
            if ($authorityRef -cne 'policy:knowledge-contract-v1') {
                Add-Issue "$RelativeDecision`: automatic-capture требует policy authority."
            }
        }
        'explicit-promotion' {
            if ($authorityRef -ceq 'policy:knowledge-contract-v1' -or $authorityRef -ceq 'null' -or
                -not (Test-CandidateAuthorityReference -Value $authorityRef -Context "$RelativeDecision Authority ref")) {
                Add-Issue "$RelativeDecision`: explicit-promotion требует direct user-request или accepted ADR authority."
            }
        }
    }
    if ($affectedCanon -cne 'нет') {
        if ($authorityRef -ceq 'null') {
            Add-Issue "$RelativeDecision`: research без authority не может объявлять canonical change."
        }
        $resolvedCanon = Resolve-SafeReference -Value $affectedCanon -Context "$RelativeDecision affected canon" -MustExist
        if ($null -ne $resolvedCanon -and $resolvedCanon.Kind -eq 'internal') {
            $canonRelative = Get-RelativePath $resolvedCanon.FullPath
            if ($canonRelative -match '^(?:research/runs|analysis/runs|knowledge/candidates|inbox/raw|business/raw|plans|retrospectives)(?:/|$)') {
                Add-Issue "$RelativeDecision`: affected canon указывает вне canonical zone."
            }
        }
    }
    $candidateListText = $candidateListMatch.Groups['value'].Value.Trim()
    if ($candidateListText.Length -gt 512) {
        Add-Issue "$RelativeDecision`: Central candidate IDs имеет недопустимый формат."
        return
    }
    $candidateIds = [System.Collections.Generic.List[string]]::new()
    $candidateListValid = $true
    if ($candidateListText -cne '[]') {
        if ($candidateListText -notmatch '^\[(?<items>[^\[\]\r\n]+)\]$') {
            $candidateListValid = $false
        }
        else {
            foreach ($rawId in ($Matches['items'] -split ',')) {
                $candidateId = $rawId.Trim()
                if ($candidateId -cnotmatch '^KC-\d{8}-\d{6}-[0-9a-f]{8}$') {
                    $candidateListValid = $false
                    continue
                }
                $candidateIds.Add($candidateId)
            }
        }
    }
    if (-not $candidateListValid) {
        Add-Issue "$RelativeDecision`: Central candidate IDs имеет недопустимый формат."
        return
    }

    $declaredSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($candidateId in $candidateIds) {
        if (-not $declaredSet.Add($candidateId)) {
            Add-Issue "$RelativeDecision`: Central candidate IDs содержит дубли."
        }
    }

    $linkedCandidateIds = if ($script:researchDecisionCandidateIds.ContainsKey($RelativeDecision)) {
        @($script:researchDecisionCandidateIds[$RelativeDecision])
    }
    else {
        @()
    }
    if ($candidateIds.Count -gt 3 -or $linkedCandidateIds.Count -gt 3) {
        Add-Issue "$RelativeDecision`: research run может иметь не более трех central candidates."
    }

    $linkedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($candidateId in $linkedCandidateIds) { $linkedSet.Add($candidateId) | Out-Null }
    if ($declaredSet.Count -ne $linkedSet.Count -or
        @($declaredSet | Where-Object { -not $linkedSet.Contains($_) }).Count -gt 0) {
        Add-Issue "$RelativeDecision`: Central candidate IDs не совпадает с candidates, ссылающимися на этот decision.md."
    }

    foreach ($candidateId in $candidateIds) {
        if (-not $script:candidateMetadataMap.ContainsKey($candidateId)) {
            Add-Issue "$RelativeDecision`: Central candidate ID ссылается на отсутствующий candidate."
            continue
        }
        $metadata = $script:candidateMetadataMap[$candidateId]
        if ([string]$metadata.CaptureBasis -cne 'research-derived') {
            Add-Issue "$RelativeDecision`: Central candidate ID должен ссылаться на research-derived candidate."
        }
        if ([string]$metadata.State -cnotin @('ready', 'applied', 'dismissed')) {
            Add-Issue "$RelativeDecision`: Central candidate ID ссылается на candidate с недопустимым состоянием."
        }
        $hasRunEvidence = $false
        foreach ($sourceRef in @($metadata.SourceRefs)) {
            if ([string]$sourceRef -match '^evidence:(.+)$' -and $RunEvidenceIds.ContainsKey($Matches[1])) {
                $hasRunEvidence = $true
                break
            }
        }
        if (-not $hasRunEvidence) {
            Add-Issue "$RelativeDecision`: Central candidate требует source_refs на evidence текущего run."
        }
    }

    $primaryId = $null
    $primaryKind = $null
    if ($outcome -cmatch '^(ready|applied):(KC-\d{8}-\d{6}-[0-9a-f]{8})$') {
        $primaryKind = $Matches[1]
        $primaryId = $Matches[2]
    }
    elseif ($outcome -cnotin @('none', 'existing', 'blocked')) {
        Add-Issue "$RelativeDecision`: основной knowledge outcome имеет недопустимый формат."
        return
    }

    if (($null -ne $primaryId) -and $writeIntent -ceq 'none') {
        Add-Issue "$RelativeDecision`: ready/applied outcome требует capture или promotion write intent."
    }
    if ($primaryKind -ceq 'applied' -and $affectedCanon -ceq 'нет') {
        Add-Issue "$RelativeDecision`: applied outcome требует затронутый canonical target."
    }

    if ($null -ne $primaryId) {
        if ($candidateIds.Count -eq 0 -or $candidateIds[0] -cne $primaryId) {
            Add-Issue "$RelativeDecision`: primary candidate должен быть первым в Central candidate IDs."
        }
        if (-not $declaredSet.Contains($primaryId)) {
            Add-Issue "$RelativeDecision`: primary candidate отсутствует в Central candidate IDs."
        }
        elseif ($script:candidateMetadataMap.ContainsKey($primaryId)) {
            $primaryMetadata = $script:candidateMetadataMap[$primaryId]
            $primaryState = [string]$primaryMetadata.State
            if ($primaryKind -ceq 'applied' -and $primaryState -cne 'applied') {
                Add-Issue "$RelativeDecision`: applied outcome требует candidate в состоянии applied."
            }
            if ($primaryKind -ceq 'ready' -and $primaryState -ceq 'ready' -and
                ($writeIntent -cne 'automatic-capture' -or
                    $authorityRef -cne 'policy:knowledge-contract-v1' -or
                    [string]$primaryMetadata.AuthorityRef -cne $authorityRef)) {
                Add-Issue "$RelativeDecision`: current ready outcome не совпадает с candidate provenance."
            }
            if ($primaryKind -ceq 'applied' -and $primaryState -ceq 'applied' -and
                ($writeIntent -cne 'explicit-promotion' -or
                    [string]$primaryMetadata.AuthorityRef -cne $authorityRef)) {
                Add-Issue "$RelativeDecision`: applied outcome не совпадает с candidate promotion authority."
            }
        }
    }
    elseif ($outcome -ceq 'blocked' -and ($candidateIds.Count -gt 0 -or $linkedCandidateIds.Count -gt 0)) {
        foreach ($candidateId in $candidateIds) {
            if (-not $script:candidateMetadataMap.ContainsKey($candidateId) -or
                [string]$script:candidateMetadataMap[$candidateId].State -cne 'dismissed') {
                Add-Issue "$RelativeDecision`: blocked outcome с Central candidate IDs допускает только dismissed candidates."
                break
            }
        }
    }
    elseif ($candidateIds.Count -gt 0 -or $linkedCandidateIds.Count -gt 0) {
        Add-Issue "$RelativeDecision`: outcome без primary candidate требует пустой список Central candidate IDs."
    }
}

function Test-ResearchDecisions {
    Initialize-ResearchCandidateAssociations
    $evidenceRoot = [System.IO.Path]::Combine($script:verificationRoot, 'research', 'runs')
    if (-not (Test-Path -LiteralPath $evidenceRoot -PathType Container)) { return }
    $runIds = $script:researchRunEvidenceIds
    $decisionCount = 0
    $totalDecisionTokens = 0
    $totalDecisionTokenLimitReported = $false
    $decisionTokenRegex = [regex]::new(
        '(?<![A-Za-z0-9_.:-])(?:(?<prefixed>evidence:)(?<evidence>[A-Za-z0-9][A-Za-z0-9._:-]*)|(?<bare>[A-Za-z0-9][A-Za-z0-9._:-]*))(?![A-Za-z0-9_.:-])',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )

    foreach ($decision in (Get-ChildItem -LiteralPath $evidenceRoot -Recurse -File -Filter 'decision.md' -Force)) {
        $decisionCount++
        if ($decisionCount -gt $maxResearchDecisionFiles) {
            Add-Issue "Research decisions: file-count превышает limit $maxResearchDecisionFiles."
            break
        }
        $relativeDecision = Get-RelativePath $decision.FullName
        if ($decision.Name -cne 'decision.md') {
            Add-Issue "$relativeDecision`: research decision filename должен быть exact-case decision.md."
            continue
        }
        if (($decision.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Add-Issue "Reparse point research decision: $relativeDecision"
            continue
        }
        $runDirectory = Split-Path -Parent $decision.FullName
        $evidenceSiblings = @(
            Get-ChildItem -LiteralPath $runDirectory -File -Force -Filter 'evidence.jsonl' |
                Where-Object { $_.Name -ceq 'evidence.jsonl' }
        )
        if ($evidenceSiblings.Count -ne 1) {
            Add-Issue "$relativeDecision`: research run требует ровно один sibling evidence.jsonl."
        }
        $runKey = $runDirectory.ToLowerInvariant()
        $ids = if ($runIds.ContainsKey($runKey)) { $runIds[$runKey] } else { @{} }
        $text = Read-BoundedUtf8Text -FilePath $decision.FullName -Context $relativeDecision -MaxBytes 1MB
        if ($null -eq $text) { continue }
        if ($text -match '(?m)^ {0,3}(?:=+|-+)[ \t]*$') {
            Add-Issue "$relativeDecision`: Setext headings и horizontal rules запрещены в research decision."
        }
        foreach ($finding in (Get-UnsafeFindings $text)) {
            Add-Issue "$relativeDecision`: data-safety finding in research decision ($finding)."
        }
        $brokenEvidenceReference = $false
        $bareEvidenceReference = $false
        $fileDecisionTokens = 0
        $decisionToken = $decisionTokenRegex.Match($text)
        while ($decisionToken.Success) {
            $fileDecisionTokens++
            $totalDecisionTokens++
            if ($fileDecisionTokens -gt $maxResearchDecisionTokensPerFile) {
                Add-Issue "$relativeDecision`: token-count превышает limit $maxResearchDecisionTokensPerFile."
                break
            }
            if ($totalDecisionTokens -gt $maxResearchDecisionTokensTotal) {
                if (-not $totalDecisionTokenLimitReported) {
                    Add-Issue "Research decisions: token-count превышает limit $maxResearchDecisionTokensTotal."
                    $totalDecisionTokenLimitReported = $true
                }
                break
            }
            if ($decisionToken.Groups['prefixed'].Success) {
                $reference = $decisionToken.Groups['evidence'].Value
                if ($reference.Length -gt 128 -or -not $ids.ContainsKey($reference)) {
                    $brokenEvidenceReference = $true
                }
            }
            else {
                $bareToken = $decisionToken.Groups['bare'].Value
                if ($bareToken.Length -le 128 -and $ids.ContainsKey($bareToken)) {
                    $bareEvidenceReference = $true
                }
            }
            $decisionToken = $decisionToken.NextMatch()
        }
        if ($brokenEvidenceReference) {
            Add-Issue "$relativeDecision`: broken evidence ID в обязательной форме evidence:<id>."
        }
        if ($bareEvidenceReference) {
            Add-Issue "$relativeDecision`: evidence ID должен использовать однозначный синтаксис evidence:<id>."
        }
        Test-ResearchDecisionKnowledgeOutcome `
            -Text $text `
            -RelativeDecision $relativeDecision `
            -RunEvidenceIds $ids
    }
}

function Test-LifecycleArtifacts {
    $legacySourceOnly = @{}
    $manifestPath = Join-Path $script:verificationRoot '.template-manifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifestText = Read-BoundedUtf8Text -FilePath $manifestPath -Context 'Lifecycle manifest'
        if ($null -ne $manifestText) {
            try {
                $manifest = $manifestText | ConvertFrom-Json -ErrorAction Stop
                foreach ($path in @($manifest.source_only_paths)) { $legacySourceOnly[[string]$path] = $true }
            }
            catch { Add-Issue 'Lifecycle manifest не прошел JSON parsing.' }
        }
    }
    $retiredLegacyAffectedCanon = @(
        'analysis/CONTRACT.md',
        'mastery/analyst/INDEX.md',
        'scripts/verify-analysis.ps1'
    )
    $configs = @(
        [pscustomobject]@{
            Root = 'docs/decisions'; Kind = 'decision'
            Fields = @('artifact_kind', 'status', 'knowledge_outcome', 'candidate_ids', 'affected_canon', 'supersedes', 'blocked_reason')
            Statuses = @('proposed', 'accepted', 'superseded', 'rejected'); HasSupersedes = $true
        },
        [pscustomobject]@{
            Root = 'plans'; Kind = 'plan'
            Fields = @('artifact_kind', 'status', 'knowledge_outcome', 'candidate_ids', 'affected_canon', 'blocked_reason')
            Statuses = @('planned', 'in-progress', 'complete', 'blocked'); HasSupersedes = $false
        },
        [pscustomobject]@{
            Root = 'retrospectives'; Kind = 'retrospective'
            Fields = @('artifact_kind', 'knowledge_outcome', 'candidate_ids', 'affected_canon', 'blocked_reason')
            Statuses = @(); HasSupersedes = $false
        }
    )
    $decisionSupersedes = @{}

    foreach ($config in $configs) {
        $artifactRoot = Join-Path $script:verificationRoot $config.Root
        if (-not (Test-Path -LiteralPath $artifactRoot -PathType Container)) { continue }
        foreach ($file in (Get-ChildItem -LiteralPath $artifactRoot -Recurse -File -Filter '*.md' -Force)) {
            if ($file.Name -cin @('README.md', 'TEMPLATE.md', 'INDEX.md')) { continue }
            $relative = Get-RelativePath $file.FullName
            if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Add-Issue "$relative`: lifecycle artifact является reparse point."
                continue
            }
            $document = Read-FrontMatterDocument $file.FullName
            if ($null -eq $document) { continue }
            $data = $document.Data
            $isPlanV2 = $config.Kind -ceq 'plan' -and $data.ContainsKey('plan_contract_version') -and [string]$data.plan_contract_version -ceq '2'
            $expectedFields = if ($isPlanV2) {
                @(
                    'artifact_kind', 'plan_contract_version', 'plan_id', 'task_key', 'prompt_ref',
                    'status', 'current_phase', 'updated_at', 'completed_at', 'closeout_status',
                    'knowledge_outcome', 'candidate_ids', 'result_refs', 'affected_canon', 'blocked_reason'
                )
            }
            else { $config.Fields }
            foreach ($field in $expectedFields) {
                if (-not $data.ContainsKey($field)) {
                    Add-Issue "$relative`: lifecycle artifact требует поле '$field'."
                }
            }
            foreach ($field in @($data.Keys)) {
                if ($field -cnotin $expectedFields) {
                    Add-Issue "$relative`: lifecycle closed-schema отвергает поле '$field'."
                }
            }
            if (-not $data.ContainsKey('artifact_kind') -or
                -not (& $script:mpkTestFrontMatterScalarValue -Value $data.artifact_kind) -or
                [string]$data.artifact_kind -cne $config.Kind) {
                Add-Issue "$relative`: invalid artifact_kind для $($config.Kind)."
            }

            $status = ''
            if ($config.Statuses.Count -gt 0) {
                if (-not $data.ContainsKey('status') -or
                    -not (& $script:mpkTestFrontMatterScalarValue -Value $data.status) -or
                    [string]$data.status -cnotin $config.Statuses) {
                    Add-Issue "$relative`: invalid lifecycle status."
                }
                else { $status = [string]$data.status }
            }
            if (-not $data.ContainsKey('knowledge_outcome') -or
                -not (& $script:mpkTestFrontMatterScalarValue -Value $data.knowledge_outcome -AllowNull)) {
                Add-Issue "$relative`: knowledge_outcome должен быть scalar или null."
                $outcome = $null
            }
            else {
                $outcome = if (Test-IsNullValue $data.knowledge_outcome) { $null } else { [string]$data.knowledge_outcome }
            }
            foreach ($listField in @('candidate_ids', 'affected_canon')) {
                if (-not $data.ContainsKey($listField) -or -not ($data[$listField] -is [System.Array])) {
                    Add-Issue "$relative`: $listField должен быть YAML-списком."
                }
                elseif (@($data[$listField] | Sort-Object -Unique).Count -ne @($data[$listField]).Count) {
                    Add-Issue "$relative`: $listField содержит дубли."
                }
            }
            if (-not $data.ContainsKey('blocked_reason') -or
                -not (& $script:mpkTestFrontMatterScalarValue -Value $data.blocked_reason -AllowNull)) {
                Add-Issue "$relative`: blocked_reason должен быть scalar или null."
            }

            $candidateIds = if ($data.candidate_ids -is [System.Array]) {
                @($data.candidate_ids | ForEach-Object { [string]$_ })
            }
            else { @() }
            foreach ($candidateId in $candidateIds) {
                if ($candidateId -cnotmatch '^KC-\d{8}-\d{6}-[0-9a-f]{8}$' -or
                    -not $script:candidateMetadataMap.ContainsKey($candidateId)) {
                    Add-Issue "$relative`: candidate_ids содержит missing candidate '$candidateId'."
                }
            }

            $affectedCanon = if ($data.affected_canon -is [System.Array]) {
                @($data.affected_canon | ForEach-Object { [string]$_ })
            }
            else { @() }
            foreach ($affectedRef in $affectedCanon) {
                $isLegacyRetiredReference = (
                    -not $isPlanV2 -and
                    $legacySourceOnly.ContainsKey($relative) -and
                    $relative -cmatch '^(?:docs/decisions|plans|retrospectives)/2026-[^/]+\.md$' -and
                    $retiredLegacyAffectedCanon -ccontains $affectedRef
                )
                if ($isLegacyRetiredReference) { continue }
                $resolvedAffected = Resolve-SafeReference -Value $affectedRef -Context "$relative affected_canon" -MustExist
                if ($affectedRef.Contains('#')) {
                    Add-Issue "$relative`: affected_canon принимает только file paths без anchor."
                }
                if ($null -ne $resolvedAffected -and $resolvedAffected.Kind -eq 'internal') {
                    $affectedRelative = Get-RelativePath $resolvedAffected.FullPath
                    if ($affectedRelative -match '^(?:knowledge/candidates|research/runs|analysis/runs|inbox/raw|business/raw|plans|retrospectives)(?:/|$)') {
                        Add-Issue "$relative`: affected_canon указывает вне canonical zone."
                    }
                }
            }

            $requiresFinalOutcome = (
                $config.Kind -ceq 'retrospective' -or
                ($config.Kind -ceq 'plan' -and (($isPlanV2 -and $status -ceq 'complete') -or (-not $isPlanV2 -and $status -cin @('complete', 'blocked')))) -or
                ($config.Kind -ceq 'decision' -and $status -cne 'proposed')
            )
            if ($null -eq $outcome) {
                if ($requiresFinalOutcome) { Add-Issue "$relative`: final lifecycle artifact требует knowledge_outcome." }
            }
            elseif ($outcome -cnotmatch '^(?:none|existing|blocked|ready:(?<ready>KC-\d{8}-\d{6}-[0-9a-f]{8})|applied:(?<applied>KC-\d{8}-\d{6}-[0-9a-f]{8}))$') {
                Add-Issue "$relative`: invalid knowledge_outcome."
            }
            else {
                $outcomeKind = $outcome.Split(':', 2)[0]
                $primaryId = if ($outcome.Contains(':')) { $outcome.Split(':', 2)[1] } else { '' }
                if ($outcomeKind -ceq 'none' -and $candidateIds.Count -ne 0) {
                    Add-Issue "$relative`: knowledge_outcome none не допускает candidate_ids."
                }
                if ($outcomeKind -cin @('ready', 'applied')) {
                    if ($candidateIds -cnotcontains $primaryId) {
                        Add-Issue "$relative`: primary knowledge_outcome ID отсутствует в candidate_ids."
                    }
                    if (-not $script:candidateMetadataMap.ContainsKey($primaryId)) {
                        Add-Issue "$relative`: knowledge_outcome ссылается на missing candidate."
                    }
                    elseif ($outcomeKind -ceq 'applied' -and
                        [string]$script:candidateMetadataMap[$primaryId].State -cne 'applied') {
                        Add-Issue "$relative`: applied knowledge_outcome требует currently applied candidate."
                    }
                }
                if (-not $isPlanV2 -and $outcomeKind -ceq 'blocked') {
                    if (-not $data.ContainsKey('blocked_reason') -or (Test-IsNullValue $data.blocked_reason)) {
                        Add-Issue "$relative`: blocked knowledge_outcome требует blocked_reason."
                    }
                }
                elseif (-not $isPlanV2 -and $data.ContainsKey('blocked_reason') -and -not (Test-IsNullValue $data.blocked_reason)) {
                    Add-Issue "$relative`: blocked_reason допустим только для blocked outcome."
                }
            }
            if ($config.Kind -ceq 'plan' -and -not $isPlanV2 -and $status -ceq 'blocked' -and $outcome -cne 'blocked') {
                Add-Issue "$relative`: blocked plan требует knowledge_outcome: blocked."
            }
            if ($isPlanV2 -and $status -ceq 'blocked' -and (Test-IsNullValue $data.blocked_reason)) {
                Add-Issue "$relative`: blocked Plan v2 требует blocked_reason."
            }
            if ($isPlanV2 -and $status -cne 'blocked' -and -not (Test-IsNullValue $data.blocked_reason)) {
                Add-Issue "$relative`: blocked_reason Plan v2 допустим только для status blocked."
            }

            if ($config.Kind -ceq 'decision') {
                if (-not $data.ContainsKey('supersedes') -or -not ($data.supersedes -is [System.Array])) {
                    Add-Issue "$relative`: decision supersedes должен быть YAML-списком."
                    $supersedes = @()
                }
                else { $supersedes = @($data.supersedes | ForEach-Object { [string]$_ }) }
                $decisionSupersedes[$relative] = @()
                foreach ($supersededRef in $supersedes) {
                    $resolvedDecision = Resolve-SafeReference -Value $supersededRef -Context "$relative decision supersedes" -MustExist
                    if ($supersededRef -ceq $relative) {
                        Add-Issue "$relative`: decision supersedes self запрещен."
                    }
                    if ($null -ne $resolvedDecision -and $resolvedDecision.Kind -eq 'internal') {
                        $supersededRelative = Get-RelativePath $resolvedDecision.FullPath
                        if ($supersededRelative -notmatch '^docs/decisions/(?!README\.md$|TEMPLATE\.md$).+\.md$') {
                            Add-Issue "$relative`: decision supersedes должен вести на ADR."
                        }
                        else { $decisionSupersedes[$relative] = @($decisionSupersedes[$relative]) + $supersededRelative }
                    }
                }
                foreach ($candidateId in $candidateIds) {
                    if (-not $script:candidateMetadataMap.ContainsKey($candidateId) -or
                        [string]$script:candidateMetadataMap[$candidateId].State -cne 'applied') { continue }
                    $candidateTarget = ([string]$script:candidateMetadataMap[$candidateId].TargetRef).Split('#', 2)[0]
                    if ($affectedCanon -cnotcontains $candidateTarget) {
                        Add-Issue "$relative`: affected_canon не содержит target applied candidate '$candidateId'."
                    }
                }
            }
        }
    }

    $reportedDecisionCycles = [System.Collections.Generic.HashSet[string]]::new(
        $script:pathComparer
    )
    function Visit-DecisionSupersedes {
        param(
            [Parameter(Mandatory = $true)][string]$Node,
            [Parameter(Mandatory = $true)][AllowEmptyCollection()][hashtable]$Active,
            [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$Visited
        )
        if ($Active.ContainsKey($Node)) {
            $signature = @($Active.Keys + $Node | Sort-Object -Unique) -join '|'
            if ($reportedDecisionCycles.Add($signature)) {
                Add-Issue "$Node`: decision-supersedes-cycle detected."
            }
            return
        }
        if ($Visited.Contains($Node)) { return }
        $Active[$Node] = $true
        foreach ($next in @($decisionSupersedes[$Node])) {
            Visit-DecisionSupersedes -Node ([string]$next) -Active $Active -Visited $Visited
        }
        $Active.Remove($Node)
        $Visited.Add($Node) | Out-Null
    }
    $visitedDecisions = [System.Collections.Generic.HashSet[string]]::new(
        $script:pathComparer
    )
    foreach ($start in @($decisionSupersedes.Keys)) {
        Visit-DecisionSupersedes -Node ([string]$start) -Active @{} -Visited $visitedDecisions
    }
}

function Invoke-KnowledgeVerification {
    param([Parameter(Mandatory = $true)][string]$VerificationRoot)

    if (-not (Test-Path -LiteralPath $VerificationRoot -PathType Container)) {
        throw "Корень проверки не найден: $VerificationRoot"
    }
    $script:verificationRoot = (Resolve-Path -LiteralPath $VerificationRoot).Path.TrimEnd([char[]]'\/')
    $script:pathComparison = & $script:mppGetPathComparison -Path $script:verificationRoot
    $script:pathComparer = if ($script:pathComparison -eq [System.StringComparison]::OrdinalIgnoreCase) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }
    $script:currentIssues = [System.Collections.Generic.List[string]]::new()
    $script:currentReport = @{
        pending = [System.Collections.Generic.List[string]]::new()
        dismissed = [System.Collections.Generic.List[string]]::new()
        overdue = [System.Collections.Generic.List[string]]::new()
        conflicts = [System.Collections.Generic.List[string]]::new()
        mastery_drift = [System.Collections.Generic.List[string]]::new()
        candidates = [System.Collections.Generic.List[string]]::new()
    }
    $script:evidenceIdMap = @{}
    $script:evidenceDecisionRefMap = @{}
    $script:researchRunEvidenceIds = @{}
    $script:candidateIdMap = @{}
    $script:candidateMetadataMap = @{}
    $script:researchDecisionCandidateIds = @{}
    $script:localMethodMap = @{}
    $script:masteryIntentCatalogLoaded = $false
    $script:masteryIntentRecords = @()
    $script:masteryIntentIds = $null
    $script:textReadPaths = [System.Collections.Generic.HashSet[string]]::new($script:pathComparer)
    $script:textReadCorpusBytes = [long]0

    $rootReparse = Get-ReparsePointInFullChain $script:verificationRoot
    if ($null -ne $rootReparse) {
        Add-Issue 'Корень репозитория или его existing ancestor является reparse point.'
        return [pscustomobject]@{
            Root = $script:verificationRoot
            Issues = @($script:currentIssues)
            Report = [pscustomobject]@{
                pending = @()
                dismissed = @()
                overdue = @()
                conflicts = @()
                mastery_drift = @()
            }
        }
    }

    Test-ProjectContract
    if (-not $SelfTest) { Test-ResearchRunInventoryAndSafety }
    Test-ResearchEvidence
    Test-Candidates
    Test-ResearchDecisions
    Test-RawRecords
    Test-Mastery
    if (-not $SelfTest) {
        Test-ResearchMethodReferences
        Test-LifecycleArtifacts
        Test-TrustedHistoryContracts
    }
    Test-RootReachability

    foreach ($candidateId in @($script:candidateMetadataMap.Keys | Sort-Object)) {
        $metadata = $script:candidateMetadataMap[$candidateId]
        $state = if ([string]$metadata.State -cin @('ready', 'applied', 'dismissed')) { [string]$metadata.State } else { 'invalid' }
        $target = if ([string]$metadata.TargetRef -cmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*\.md(?:#[^#\r\n]+)?$') {
            [string]$metadata.TargetRef
        }
        else { '[invalid]' }
        $title = if ([string]::IsNullOrWhiteSpace([string]$metadata.ClaimTitle)) { '[redacted]' } else { [string]$metadata.ClaimTitle }
        $created = Get-DateTimeOffsetOrNull ([string]$metadata.CreatedAt)
        $ageDays = if ($null -eq $created) { 'unknown' } else { [Math]::Max(0, [Math]::Floor(([System.DateTimeOffset]::UtcNow - $created).TotalDays)) }
        $review = if (Test-DateOnly ([string]$metadata.ReviewDue)) { [string]$metadata.ReviewDue } else { 'none' }
        $script:currentReport.candidates.Add(
            "$candidateId | state=$state | title=$title | target=$target | age_days=$ageDays | review_due=$review | conflicts=$($metadata.ConflictCount) | path=$($metadata.Relative)"
        ) | Out-Null
    }

    return [pscustomobject]@{
        Root = $script:verificationRoot
        Issues = @($script:currentIssues | Sort-Object -Unique)
        Report = [pscustomobject]@{
            pending = @($script:currentReport.pending | Sort-Object -Unique)
            dismissed = @($script:currentReport.dismissed | Sort-Object -Unique)
            overdue = @($script:currentReport.overdue | Sort-Object -Unique)
            conflicts = @($script:currentReport.conflicts | Sort-Object -Unique)
            mastery_drift = @($script:currentReport.mastery_drift | Sort-Object -Unique)
            candidates = @($script:currentReport.candidates | Sort-Object -Unique)
        }
    }
}

function Write-FixtureFile {
    param(
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Relative,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $path = Join-Path $Base $Relative
    $parent = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($path, $Content, $utf8NoBom)
}

function Get-FixtureCandidate {
    param(
        [string]$Id = 'KC-20260730-120000-deadbeef',
        [string]$State = 'ready',
        [string]$SourceRef = 'https://example.com/evidence',
        [string[]]$AdditionalSourceRefs = @(),
        [string]$CaptureBasis = 'repo-derived',
        [string]$AuthorityRef = 'policy:knowledge-contract-v1',
        [string]$AppliedAt = 'null',
        [string]$Type = 'decision',
        [string]$Domain = 'architecture',
        [string]$ClaimKey = 'fixture-claim',
        [string]$TargetRef = 'docs/target.md#knowledge',
        [string]$Confidence = 'high',
        [string]$ReviewDue = "'2099-12-31'",
        [string]$MethodKind = 'checklist',
        [string]$MethodSummary = 'Повторяемый fixture-метод для проверки контракта.',
        [string[]]$MethodAppliesTo = @('planning')
    )
    $sourceYaml = @($SourceRef) + @($AdditionalSourceRefs) |
        ForEach-Object { "  - '$_'" }
    $sourceYaml = $sourceYaml -join "`n"
    $methodKindYaml = if ($Type -ceq 'method') { $MethodKind } else { 'null' }
    $methodSummaryYaml = if ($Type -ceq 'method') { "'$($MethodSummary.Replace("'", "''"))'" } else { 'null' }
    $methodAppliesYaml = if ($Type -ceq 'method') {
        "`n" + (($MethodAppliesTo | ForEach-Object { "  - '$_'" }) -join "`n")
    }
    else { '[]' }
    return @"
---
id: '$Id'
state: $State
type: $Type
owner_scope: project
domain: $Domain
method_kind: $methodKindYaml
method_summary: $methodSummaryYaml
method_applies_to: $methodAppliesYaml
claim_key: $ClaimKey
target_ref: '$TargetRef'
source_refs:
$sourceYaml
conflict_refs: []
confidence: $Confidence
capture_basis: $CaptureBasis
data_class: internal
created_at: '2026-07-30T12:00:00+04:00'
review_due: $ReviewDue
authority_ref: '$AuthorityRef'
applied_at: $AppliedAt
dismiss_reason: null
supersedes: null
---

# Fixture claim

## Основание

Проверяемое основание.

## Предлагаемое изменение

Добавить правило.

## Проверка дублей и противоречий

Дубли не найдены.

## Обоснование lifecycle

- Статус: $State
"@
}

function Get-FixtureDecision {
    param(
        [string]$EvidenceRefs = 'evidence:SRC-001',
        [string]$Outcome = 'none',
        [string[]]$CandidateIds = @()
    )

    $candidateList = if ($CandidateIds.Count -eq 0) {
        '[]'
    }
    else {
        '[' + ($CandidateIds -join ', ') + ']'
    }
    $writeIntent = if ($Outcome -cmatch '^ready:') { 'automatic-capture' } elseif ($Outcome -cmatch '^applied:') { 'explicit-promotion' } else { 'none' }
    $authorityRef = if ($writeIntent -ceq 'automatic-capture') { 'policy:knowledge-contract-v1' } elseif ($writeIntent -ceq 'explicit-promotion') { 'user-request:selftest-promotion' } else { 'null' }
    $affectedCanon = if ($Outcome -cmatch '^applied:') { 'docs/target.md' } else { '`нет`' }
    return @"
# Decision

- Основной baseline method ref: mastery/researcher/profile.md#method
- Дополняющий baseline method ref: `не применимо`
- Local method IDs: []
- Local method refs: []

Evidence: $EvidenceRefs

## Knowledge outcome

- Основной результат closeout: $Outcome
- Write intent: $writeIntent
- Authority ref: $authorityRef
- Причина ``blocked``: $(if ($Outcome -ceq 'blocked') { 'missing-provenance' } else { 'не применимо' })
- Central candidate IDs в порядке влияния на решение: $candidateList
- Затронутый канон: $affectedCanon
"@
}

function Get-FixtureEvidenceRow {
    param(
        [string]$EvidenceId = 'SRC-001',
        [string]$OriginGroupId = 'OG-001',
        [string]$SourceUrl = 'https://example.com/source'
    )

    return [ordered]@{
        evidence_id = $EvidenceId
        claim_id = 'CLAIM-001'
        claim = 'Проверяемый fixture claim'
        claim_type = 'fact'
        stance = 'supports'
        source_url = $SourceUrl
        source_title = 'Fixture source'
        publisher = 'Fixture publisher'
        source_type = 'primary'
        published_at = '2026-07-01'
        accessed_at = '2026-07-30'
        locator = 'section-1'
        observation = 'Fixture observation'
        directness = 'direct'
        origin_group_id = $OriginGroupId
        original_source_url = $SourceUrl
        syndication_or_quote_of = ''
        dataset_origin = 'fixture-dataset'
        content_fingerprint = 'fixture-fingerprint'
        geography = 'global'
        time_scope = '2026'
        limitations = 'No material limitations in fixture.'
        participant_code = 'anonymous'
        prompt_injection_detected = $false
    }
}

function Assert-SelfTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if (-not $Condition) { throw "SELFTEST FAIL: $Name" }
    Write-Host "SELFTEST PASS: $Name"
}

function Assert-SelfTestIssueSet {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)][string[]]$AllowedPatterns,
        [AllowEmptyCollection()]
        [string[]]$RequiredPatterns = @(),
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($RequiredPatterns.Count -eq 0) {
        $RequiredPatterns = @($AllowedPatterns)
    }
    $issues = @($Result.Issues)
    $unexpected = [System.Collections.Generic.List[string]]::new()
    foreach ($issue in $issues) {
        $matched = $false
        foreach ($pattern in $AllowedPatterns) {
            if ($issue -match $pattern) {
                $matched = $true
                break
            }
        }
        if (-not $matched) { $unexpected.Add($issue) | Out-Null }
    }

    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($pattern in $RequiredPatterns) {
        if (@($issues | Where-Object { $_ -match $pattern }).Count -eq 0) {
            $missing.Add($pattern) | Out-Null
        }
    }
    if ($unexpected.Count -gt 0 -or $missing.Count -gt 0) {
        throw "SELFTEST FAIL: $Name. Missing patterns: $($missing -join ', '); unexpected issues: $($unexpected -join ' | ')"
    }
    Write-Host "SELFTEST PASS: $Name"
}

function Assert-GeneratorRejectedWithoutArtifact {
    param(
        [Parameter(Mandatory = $true)][string]$FixtureRoot,
        [Parameter(Mandatory = $true)][string]$ClaimKey,
        [Parameter(Mandatory = $true)][string]$ExpectedMessagePattern,
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$SourceRefs = @('https://example.com/evidence'),
        [string[]]$ConflictRefs = @(),
        [string]$TargetRef = 'docs/target.md#knowledge',
        [string]$Title = 'Rejected generator fixture',
        [string]$Basis = 'Проверяемое основание.',
        [string]$ProposedChange = 'Добавить правило.',
        [string]$DuplicateCheck = 'Дубли не найдены.',
        [string[]]$ForbiddenMessagePatterns = @(),
        [string]$Type = 'decision',
        [string]$Domain = 'architecture',
        [string]$Confidence = 'high',
        [string]$CaptureBasis = 'repo-derived',
        [string]$ReviewDue = '2099-12-31',
        [string]$WriteIntent = 'explicit-promotion',
        [string]$AuthorityRef = 'user-request:selftest-generator',
        [string]$MethodKind = 'checklist',
        [string]$MethodSummary = 'Повторяемый fixture-метод для проверки generator.',
        [string[]]$MethodAppliesTo = @('planning')
    )

    $candidateDirectory = [System.IO.Path]::Combine($FixtureRoot, 'knowledge', 'candidates')
    $beforeCandidates = @(Get-ChildItem -LiteralPath $candidateDirectory -Recurse -File -Filter 'KC-*.md' -Force).Count
    $beforeDirectories = @(Get-ChildItem -LiteralPath $candidateDirectory -Recurse -Directory -Force).Count
    $rejected = $false
    $message = ''
    try {
        $generatorArguments = @{
            Root = $FixtureRoot
            Type = $Type
            Domain = $Domain
            ClaimKey = $ClaimKey
            TargetRef = $TargetRef
            SourceRefs = $SourceRefs
            ConflictRefs = $ConflictRefs
            Confidence = $Confidence
            CaptureBasis = $CaptureBasis
            DataClass = 'internal'
            Title = $Title
            Basis = $Basis
            ProposedChange = $ProposedChange
            DuplicateCheck = $DuplicateCheck
            ReviewDue = $ReviewDue
            WriteIntent = $WriteIntent
            AuthorityRef = $AuthorityRef
        }
        if ($Type -ceq 'method') {
            $generatorArguments.MethodKind = $MethodKind
            $generatorArguments.MethodSummary = $MethodSummary
            $generatorArguments.MethodAppliesTo = $MethodAppliesTo
        }
        & (Join-Path $PSScriptRoot 'new-knowledge-candidate.ps1') @generatorArguments | Out-Null
    }
    catch {
        $rejected = $true
        $message = $_.Exception.Message
    }
    $afterCandidates = @(Get-ChildItem -LiteralPath $candidateDirectory -Recurse -File -Filter 'KC-*.md' -Force).Count
    $afterDirectories = @(Get-ChildItem -LiteralPath $candidateDirectory -Recurse -Directory -Force).Count
    $temporaryFiles = @(Get-ChildItem -LiteralPath $candidateDirectory -Recurse -File -Filter '.candidate-*.tmp' -Force).Count
    $forbiddenMessageFound = @($ForbiddenMessagePatterns | Where-Object { $message -match $_ }).Count -gt 0
    $passed = (
        $rejected -and
        $message -match $ExpectedMessagePattern -and
        -not $forbiddenMessageFound -and
        $afterCandidates -eq $beforeCandidates -and
        $afterDirectories -eq $beforeDirectories -and
        $temporaryFiles -eq 0
    )
    $diagnosticName = if ($passed) {
        $Name
    }
    else {
        $messageClass = switch -Regex ($message) {
            '^Trusted knowledge verifier' { 'trusted-verifier-integrity'; break }
            '^Exact PowerShell host path|^Не удалось определить exact PowerShell host path|^Текущий процесс' { 'host-integrity'; break }
            '^blocked: repository-preflight$' { 'repository-preflight'; break }
            '^Evidence|^Corrupted evidence|^Invalid evidence|^Duplicate evidence' { 'manual-evidence'; break }
            '^SourceRefs|^ConflictRefs|^TargetRef|^AuthorityRef' { 'input-reference'; break }
            '^Basis|^ProposedChange|^DuplicateCheck|^Сгенерированный candidate' { 'input-body'; break }
            default { 'other'; break }
        }
        "$Name [class=$messageClass rejected=$rejected expected=$($message -match $ExpectedMessagePattern) redacted=$(-not $forbiddenMessageFound) candidates=$beforeCandidates/$afterCandidates dirs=$beforeDirectories/$afterDirectories temp=$temporaryFiles]"
    }
    Assert-SelfTest -Condition $passed -Name $diagnosticName
}

function Assert-GeneratorCliRejectIsRedacted {
    param(
        [Parameter(Mandatory = $true)][string]$FixtureRoot,
        [Parameter(Mandatory = $true)][string[]]$ForbiddenMessagePatterns,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $candidateDirectory = [System.IO.Path]::Combine($FixtureRoot, 'knowledge', 'candidates')
    $beforeCandidates = @(Get-ChildItem -LiteralPath $candidateDirectory -Recurse -File -Filter 'KC-*.md' -Force).Count
    $hostPath = Get-TrustedCurrentPowerShellHostPath
    if ($null -eq $hostPath) {
        throw 'SELFTEST FAIL: unsupported PowerShell host for generator CLI redaction.'
    }
    $creatorPath = Join-Path $PSScriptRoot 'new-knowledge-candidate.ps1'
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $cliOutput = @(
            & $hostPath `
                -NoLogo `
                -NoProfile `
                -NonInteractive `
                -ExecutionPolicy Bypass `
                -File $creatorPath `
                -Root $FixtureRoot `
                -Type decision `
                -Domain architecture `
                -ClaimKey 'generator-cli-redaction' `
                -TargetRef 'docs/target.md#knowledge' `
                -SourceRefs 'https://example.com/evidence' `
                -Confidence high `
                -CaptureBasis repo-derived `
                -DataClass internal `
                -Title 'Generator CLI redaction fixture' `
                -Basis 'Проверяемое основание.' `
                -ProposedChange 'Добавить правило.' `
                -DuplicateCheck 'Дубли не найдены.' `
                -ReviewDue '2099-12-31' `
                -WriteIntent explicit-promotion `
                -AuthorityRef user-request:selftest-generator-cli 2>&1
        )
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $outputText = @($cliOutput | ForEach-Object { [string]$_ }) -join "`n"
    $afterCandidates = @(Get-ChildItem -LiteralPath $candidateDirectory -Recurse -File -Filter 'KC-*.md' -Force).Count
    $forbiddenFound = @($ForbiddenMessagePatterns | Where-Object { $outputText -match $_ }).Count -gt 0
    Assert-SelfTest -Condition (
        $exitCode -ne 0 -and
        $outputText -ceq 'ERROR: создание knowledge candidate отклонено. Запусти scripts/verify-knowledge.ps1 для безопасного отчета.' -and
        -not $forbiddenFound -and
        $afterCandidates -eq $beforeCandidates
    ) -Name $Name
}

function Invoke-SelfTests {
    $physicalTemp = [System.IO.Path]::GetFullPath((& $script:mppResolveFileSystemLinkPath -Path ([System.IO.Path]::GetTempPath()))).TrimEnd([char[]]'\/')
    $temporaryBase = [System.IO.Path]::GetFullPath((Join-Path $physicalTemp ('knowledge-selftest-' + [guid]::NewGuid().ToString('N'))))
    $expectedPrefix = $physicalTemp +
        [System.IO.Path]::DirectorySeparatorChar +
        'knowledge-selftest-'
    $temporaryComparison = & $script:mppGetPathComparison -Path $physicalTemp
    $reparseItemType = if (& $script:mppIsWindows) { 'Junction' } else { 'SymbolicLink' }
    if (-not $temporaryBase.StartsWith($expectedPrefix, $temporaryComparison)) {
        throw "Небезопасный self-test path: $temporaryBase"
    }

    try {
        New-Item -ItemType Directory -Path $temporaryBase | Out-Null
        $selfTestProjectId = '11111111' + '-1111-4111-8111-' + '111111111111'
        $project = @"
---
repository_kind: generated-project
project_status: active
project_id: "$selfTestProjectId"
knowledge_contract_version: 1
knowledge_capture_mode: report-only
---

# Fixture

## Паспорт

- Slug: fixture-project
- Описание: Проверка semantic knowledge gate.
- Владелец: `fixture-owner`
- Стадия: исследование
- Канонический репозиторий: этот репозиторий
- Дата последней проверки паспорта: 2026-08-01

## Проблема

Контрольная плоскость должна отклонять некорректные знания.

## Проверяемая гипотеза

Строгий verifier отделяет валидные артефакты от нарушений контракта.

## Границы

Входит:

- Проверка knowledge artifacts.

Не входит:

- Выбор технического стека.

## Критерии успеха и провала

- Успех: положительные fixtures проходят.
- Провал: отрицательные fixtures получают false-green.
- Срок или объем проверки: один self-test run.
- Кто принимает финальное решение: fixture-owner.

## Стек и эксплуатация

- Стек: не требуется для research-stage fixture.

## Связи

- [Карта](INDEX.md)
"@
        Write-FixtureFile -Base $temporaryBase -Relative 'PROJECT.md' -Content $project
        Write-FixtureFile -Base $temporaryBase -Relative 'INDEX.md' -Content @"
# Index

- [Project](PROJECT.md)
- [Source](docs/source.md)
- [Target](docs/target.md)
- [Candidate template](knowledge/candidates/TEMPLATE.md)
- [Local mastery](mastery/local/INDEX.md)
- [Researcher profile](mastery/researcher/profile.md)
- [Brief asset](.agents/skills/startup-researcher/assets/run-template/brief.md)
- [Candidates asset](.agents/skills/startup-researcher/assets/run-template/candidates.md)
- [Decision asset](.agents/skills/startup-researcher/assets/run-template/decision.md)
- [Queries asset](.agents/skills/startup-researcher/assets/run-template/queries.md)
- [Red-team asset](.agents/skills/startup-researcher/assets/run-template/red-team.md)
"@
        Write-FixtureFile -Base $temporaryBase -Relative 'docs/source.md' -Content "# Source`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'docs/target.md' -Content "# Target`n`n## Knowledge`n`n[Candidate](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'knowledge/candidates/TEMPLATE.md' -Content "# Template`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'knowledge/candidates/2026/KC-20260730-120000-deadbeef.md' -Content (Get-FixtureCandidate)
        Write-FixtureFile -Base $temporaryBase -Relative 'mastery/local/INDEX.md' -Content "# Local`n"
        $intentCatalogSource = Join-Path (Split-Path -Parent $PSScriptRoot) 'mastery/INTENTS.json'
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'mastery/INTENTS.json' `
            -Content ([System.IO.File]::ReadAllText($intentCatalogSource, $utf8Strict))
        Write-FixtureFile -Base $temporaryBase -Relative 'mastery/researcher/profile.md' -Content "# Profile`n`n## Method`n`nSynthetic baseline method.`n"
        $sourceAssetRoot = Join-Path (Split-Path -Parent $PSScriptRoot) '.agents/skills/startup-researcher/assets/run-template'
        $fixtureAssetRoot = Join-Path $temporaryBase '.agents/skills/startup-researcher/assets/run-template'
        $fixtureRunRoot = Join-Path $temporaryBase 'research/runs/2026-07-30-test'
        New-Item -ItemType Directory -Path $fixtureAssetRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $fixtureRunRoot -Force | Out-Null
        foreach ($assetName in @('brief.md', 'queries.md', 'evidence.jsonl', 'candidates.md', 'red-team.md', 'decision.md')) {
            Copy-Item -LiteralPath (Join-Path $sourceAssetRoot $assetName) -Destination (Join-Path $fixtureAssetRoot $assetName)
            Copy-Item -LiteralPath (Join-Path $sourceAssetRoot $assetName) -Destination (Join-Path $fixtureRunRoot $assetName)
        }
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/brief.md' -Content @"
# Brief

- Основной baseline profile ref: mastery/researcher/profile.md
- Основной baseline method ref: mastery/researcher/profile.md#method
- Дополняющий baseline profile ref: `не применимо`
- Дополняющий baseline method ref: `не применимо`
- Local method IDs: []
- Local method refs: []
"@
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/.gitkeep' -Content ''
        $httpsEvidenceRow = Get-FixtureEvidenceRow
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content (($httpsEvidenceRow | ConvertTo-Json -Compress) + "`n")
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/decision.md' -Content (Get-FixtureDecision)
        $rawTemplatePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'inbox/raw/TEMPLATE.md'
        $safeRaw = [System.IO.File]::ReadAllText($rawTemplatePath, $utf8Strict).
            Replace('id: raw-YYYYMMDD-HHmm-slug', 'id: raw-20260730-1159-safe').
            Replace('captured_at: YYYY-MM-DDTHH:mm:ss+00:00', "captured_at: '2026-07-30T11:59:00+04:00'").
            Replace('storage_basis: null', 'storage_basis: explicit-user-request').
            Replace('authority_ref: null', 'authority_ref: user-request:selftest-raw').
            Replace('data_class: public | internal | sensitive', 'data_class: public').
            Replace('content_mode: summary | verbatim', 'content_mode: summary').
            Replace('personal_data: none | anonymized', 'personal_data: none').
            Replace('retention: YYYY-MM-DD | rule', "retention: '2099-12-31'").
            Replace('source: logical-source-identifier', 'source: logical:selftest/raw').
            Replace('rights: user-owned | user-authorized | public-summary | other', 'rights: public-summary').
            Replace(
                'status: captured | reviewed | rejected | retention-due',
                'status: captured'
            )
        Write-FixtureFile -Base $temporaryBase -Relative 'inbox/raw/2026-07-30_11-59_safe.md' -Content $safeRaw

        $reparseTarget = Join-Path $temporaryBase 'reparse-target'
        $reparseRoot = Join-Path $temporaryBase 'reparse-root'
        New-Item -ItemType Directory -Path $reparseTarget | Out-Null
        try {
            New-Item -ItemType $reparseItemType -Path $reparseRoot -Target $reparseTarget | Out-Null
            $reparseVerification = Invoke-KnowledgeVerification $reparseRoot
            Assert-SelfTestIssueSet -Result $reparseVerification -AllowedPatterns @(
                '^Корень репозитория.*reparse point'
            ) -Name 'verifier rejects reparse root before repository reads'

            $creatorRejectedReparse = $false
            $creatorReparseMessage = ''
            try {
                & (Join-Path $PSScriptRoot 'new-knowledge-candidate.ps1') `
                    -Root $reparseRoot `
                    -Type decision `
                    -Domain architecture `
                    -ClaimKey reparse-root `
                    -TargetRef 'docs/target.md#knowledge' `
                    -SourceRefs 'https://example.com/evidence' `
                    -Confidence high `
                    -CaptureBasis repo-derived `
                    -DataClass internal `
                    -Title 'Reparse fixture' `
                    -Basis 'Проверяемое основание.' `
                    -ProposedChange 'Добавить правило.' `
                    -DuplicateCheck 'Дубли не найдены.' `
                    -ReviewDue '2099-12-31' | Out-Null
            }
            catch {
                $creatorRejectedReparse = $true
                $creatorReparseMessage = $_.Exception.Message
            }
            Assert-SelfTest -Condition (
                $creatorRejectedReparse -and
                $creatorReparseMessage -match 'reparse point' -and
                $creatorReparseMessage -notmatch 'PROJECT.md'
            ) -Name 'generator rejects reparse root before repository reads'
        }
        finally {
            if (Test-Path -LiteralPath $reparseRoot) {
                Remove-Item -LiteralPath $reparseRoot -Force
            }
        }

        $valid = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $valid -AllowedPatterns @() -Name 'valid candidate, dynamic collections, project contract and template-derived RAW'
        Remove-Item `
            -LiteralPath (Join-Path $temporaryBase 'research/runs/2026-07-30-test/decision.md') `
            -Force
        $missingResearchDecision = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $missingResearchDecision -AllowedPatterns @(
            'research run требует ровно один sibling decision\.md'
        ) -Name 'research evidence run requires its exact sibling decision file'
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/decision.md' -Content (Get-FixtureDecision)
        $blankTargetRaw = $safeRaw.Replace('related: []', "target_ref:`nrelated: []")
        Write-FixtureFile -Base $temporaryBase -Relative 'inbox/raw/2026-07-30_11-59_safe.md' -Content $blankTargetRaw
        $blankTargetRawResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $blankTargetRawResult -AllowedPatterns @(
            "RAW closed-schema отвергает неизвестное поле 'target_ref'"
        ) -Name 'removed blank RAW target_ref is rejected by closed schema'
        $listTargetRaw = $safeRaw.Replace('related: []', "target_ref: []`nrelated: []")
        Write-FixtureFile -Base $temporaryBase -Relative 'inbox/raw/2026-07-30_11-59_safe.md' -Content $listTargetRaw
        $listTargetRawResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $listTargetRawResult -AllowedPatterns @(
            "RAW closed-schema отвергает неизвестное поле 'target_ref'"
        ) -Name 'removed list RAW target_ref is rejected by closed schema'
        Write-FixtureFile -Base $temporaryBase -Relative 'inbox/raw/2026-07-30_11-59_safe.md' -Content $safeRaw

        $knowledgeFieldsAfterH1 = @"
# Decision

Evidence: evidence:SRC-001

## Knowledge outcome

# Поддельный новый документ

- Основной результат closeout: none
- Central candidate IDs в порядке влияния на решение: []
"@
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content $knowledgeFieldsAfterH1
        $knowledgeFieldsAfterH1Result = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $knowledgeFieldsAfterH1Result -AllowedPatterns @(
            'Knowledge outcome требует одно машинно-читаемое поле основного результата'
        ) -Name 'research Knowledge outcome cannot source machine fields from a later H1 document'

        $knowledgeFieldsAfterIndentedH1 = @"
# Decision

Evidence: evidence:SRC-001

## Knowledge outcome

 # Поддельный новый документ

- Основной результат closeout: none
- Central candidate IDs в порядке влияния на решение: []
"@
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content $knowledgeFieldsAfterIndentedH1
        $knowledgeFieldsAfterIndentedH1Result = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $knowledgeFieldsAfterIndentedH1Result -AllowedPatterns @(
            'Knowledge outcome требует одно машинно-читаемое поле основного результата'
        ) -Name 'research Knowledge outcome cannot cross a CommonMark-indented H1 boundary'

        $knowledgeFieldsAfterSetext = @"
# Decision

Evidence: evidence:SRC-001

## Knowledge outcome

Поддельный документ
===================

- Основной результат closeout: none
- Central candidate IDs в порядке влияния на решение: []
"@
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content $knowledgeFieldsAfterSetext
        $knowledgeFieldsAfterSetextResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $knowledgeFieldsAfterSetextResult -AllowedPatterns @(
            'Setext headings и horizontal rules запрещены в research decision'
        ) -Name 'research decision rejects Setext section-boundary bypass'

        $knowledgeFieldsInRawHtml = @"
# Decision

Evidence: evidence:SRC-001

<div>
## Knowledge outcome

- Основной результат closeout: none
- Central candidate IDs в порядке влияния на решение: []
</div>
"@
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content $knowledgeFieldsInRawHtml
        $knowledgeFieldsInRawHtmlResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $knowledgeFieldsInRawHtmlResult -AllowedPatterns @(
            'data-safety finding in research decision \(raw-html\)'
        ) -Name 'research decision rejects raw HTML wrapped machine fields'

        $knowledgeFieldsInListFence = @"
# Decision

Evidence: evidence:SRC-001

- ~~~text
  ## Knowledge outcome

- Основной результат closeout: none
- Central candidate IDs в порядке влияния на решение: []
"@
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content $knowledgeFieldsInListFence
        $knowledgeFieldsInListFenceResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $knowledgeFieldsInListFenceResult -AllowedPatterns @(
            'требуется ровно один структурный раздел Knowledge outcome'
        ) -Name 'research decision rejects list-container tilde-fence section bypass'

        $splitOutcomeField = @"
# Decision

Evidence: evidence:SRC-001

## Knowledge outcome

- Основной результат closeout:
none
- Central candidate IDs в порядке влияния на решение: []
"@
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content $splitOutcomeField
        $splitOutcomeFieldResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $splitOutcomeFieldResult -AllowedPatterns @(
            'Knowledge outcome требует одно машинно-читаемое поле основного результата'
        ) -Name 'research outcome machine field must remain on one physical line'

        $splitCandidateListField = @"
# Decision

Evidence: evidence:SRC-001

## Knowledge outcome

- Основной результат closeout: none
- Central candidate IDs в порядке влияния на решение:
[]
"@
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content $splitCandidateListField
        $splitCandidateListFieldResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $splitCandidateListFieldResult -AllowedPatterns @(
            'Knowledge outcome требует один машинно-читаемый список Central candidate IDs'
        ) -Name 'research candidate ID machine field must remain on one physical line'

        $inlineCodeHeading = @'
# Decision

Evidence: evidence:SRC-001

## `fake` Knowledge outcome

- Основной результат closeout: none
- Central candidate IDs в порядке влияния на решение: []
'@
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content $inlineCodeHeading
        $inlineCodeHeadingResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $inlineCodeHeadingResult -AllowedPatterns @(
            'требуется ровно один структурный раздел Knowledge outcome'
        ) -Name 'research Knowledge outcome heading cannot be synthesized by masking inline code'

        $inlineCodeOutcomeSuffix = @'
# Decision

Evidence: evidence:SRC-001

## Knowledge outcome

- Основной результат closeout: none `ready:KC-20260730-120000-deadbeef`
- Central candidate IDs в порядке влияния на решение: []
'@
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content $inlineCodeOutcomeSuffix
        $inlineCodeOutcomeSuffixResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $inlineCodeOutcomeSuffixResult -AllowedPatterns @(
            'Knowledge outcome требует одно машинно-читаемое поле основного результата'
        ) -Name 'research outcome field rejects contradictory trailing inline code'

        $inlineCodeCandidateListSuffix = @'
# Decision

Evidence: evidence:SRC-001

## Knowledge outcome

- Основной результат closeout: none
- Central candidate IDs в порядке влияния на решение: [] `[KC-20260730-120000-deadbeef]`
'@
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content $inlineCodeCandidateListSuffix
        $inlineCodeCandidateListSuffixResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $inlineCodeCandidateListSuffixResult -AllowedPatterns @(
            'Knowledge outcome требует один машинно-читаемый список Central candidate IDs'
        ) -Name 'research candidate ID field rejects contradictory trailing inline code'

        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/decision.md' -Content (Get-FixtureDecision)

        $researchCandidatePath = 'knowledge/candidates/2026/KC-20260730-120000-deadbeef.md'
        $primaryResearchCandidateId = 'KC-20260730-120000-deadbeef'
        $researchCandidate = Get-FixtureCandidate `
            -SourceRef 'research/runs/2026-07-30-test/decision.md' `
            -AdditionalSourceRefs 'evidence:SRC-001' `
            -CaptureBasis 'research-derived'
        Write-FixtureFile -Base $temporaryBase -Relative $researchCandidatePath -Content $researchCandidate
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content (Get-FixtureDecision -Outcome "ready:$primaryResearchCandidateId" -CandidateIds $primaryResearchCandidateId)
        $validResearchCandidateOutcome = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet `
            -Result $validResearchCandidateOutcome `
            -AllowedPatterns @() `
            -Name 'research decision accepts exact decision source, run evidence and one primary candidate'

        $otherEvidenceRow = Get-FixtureEvidenceRow `
            -EvidenceId 'OTHER-001' `
            -OriginGroupId 'OG-OTHER-001' `
            -SourceUrl 'https://example.org/other-source'
        $otherEvidenceRow.dataset_origin = 'fixture-other-dataset'
        $otherEvidenceRow.content_fingerprint = 'fixture-other-fingerprint'
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/other/evidence.jsonl' `
            -Content (($otherEvidenceRow | ConvertTo-Json -Compress) + "`n")
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/other/decision.md' `
            -Content (Get-FixtureDecision -EvidenceRefs 'evidence:OTHER-001')
        $crossRunEvidenceCandidate = Get-FixtureCandidate `
            -SourceRef 'research/runs/2026-07-30-test/decision.md' `
            -AdditionalSourceRefs @('evidence:SRC-001', 'evidence:OTHER-001') `
            -CaptureBasis 'research-derived'
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative $researchCandidatePath `
            -Content $crossRunEvidenceCandidate
        $crossRunEvidenceResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet `
            -Result $crossRunEvidenceResult `
            -AllowedPatterns @() `
            -Name 'research candidate may cite additional evidence from another run without joining its decision'
        Remove-Item `
            -LiteralPath (Join-Path $temporaryBase 'research/runs/other') `
            -Recurse `
            -Force
        Write-FixtureFile -Base $temporaryBase -Relative $researchCandidatePath -Content $researchCandidate

        $encodedResearchDecisionSource = Get-FixtureCandidate `
            -SourceRef 'research/runs/2026-07-30-test/%64ecision.md' `
            -AdditionalSourceRefs 'evidence:SRC-001' `
            -CaptureBasis 'research-derived'
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative $researchCandidatePath `
            -Content $encodedResearchDecisionSource
        $encodedResearchDecisionSourceResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet `
            -Result $encodedResearchDecisionSourceResult `
            -AllowedPatterns @() `
            -Name 'research decision association uses normalized percent-decoded internal source path'

        $anchoredResearchDecisionSource = Get-FixtureCandidate `
            -SourceRef 'research/runs/2026-07-30-test/decision.md#knowledge-outcome' `
            -AdditionalSourceRefs 'evidence:SRC-001' `
            -CaptureBasis 'research-derived'
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative $researchCandidatePath `
            -Content $anchoredResearchDecisionSource
        $anchoredResearchDecisionSourceResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet `
            -Result $anchoredResearchDecisionSourceResult `
            -AllowedPatterns @() `
            -Name 'research decision association normalizes an allowed decision anchor to its exact file'
        Write-FixtureFile -Base $temporaryBase -Relative $researchCandidatePath -Content $researchCandidate

        $researchCandidateWithoutDecisionSource = Get-FixtureCandidate `
            -SourceRef 'evidence:SRC-001' `
            -CaptureBasis 'research-derived'
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative $researchCandidatePath `
            -Content $researchCandidateWithoutDecisionSource
        $missingDecisionSource = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $missingDecisionSource -AllowedPatterns @(
            'research-derived candidate требует точный source_ref на decision\.md'
        ) -Name 'research candidate requires exact decision file source rather than run directory or implicit ownership'

        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content (Get-FixtureDecision)
        $symmetricOrphanResearchCandidate = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $symmetricOrphanResearchCandidate -AllowedPatterns @(
            'research-derived candidate требует точный source_ref на decision\.md',
            'Central candidate IDs не совпадает с candidates, ссылающимися на этот decision\.md',
            'outcome без primary candidate требует пустой список Central candidate IDs'
        ) -Name 'evidence-only research candidate cannot hide behind decision none and empty IDs'
        Write-FixtureFile -Base $temporaryBase -Relative $researchCandidatePath -Content $researchCandidate

        $missingResearchCandidateId = 'KC-20260730-120099-11112222'
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content (Get-FixtureDecision -Outcome "ready:$missingResearchCandidateId" -CandidateIds $missingResearchCandidateId)
        $missingResearchCandidate = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $missingResearchCandidate -AllowedPatterns @(
            'Central candidate IDs не совпадает с candidates, ссылающимися на этот decision\.md',
            'Central candidate ID ссылается на отсутствующий candidate'
        ) -Name 'research decision rejects nonexistent central candidate ID'

        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content (Get-FixtureDecision `
                -Outcome "ready:$primaryResearchCandidateId" `
                -CandidateIds @($primaryResearchCandidateId, $primaryResearchCandidateId))
        $duplicateResearchCandidateIds = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $duplicateResearchCandidateIds -AllowedPatterns @(
            'Central candidate IDs содержит дубли'
        ) -Name 'research decision rejects duplicate central candidate IDs'

        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content (Get-FixtureDecision -Outcome "applied:$primaryResearchCandidateId" -CandidateIds $primaryResearchCandidateId)
        $researchAppliedStateMismatch = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $researchAppliedStateMismatch -AllowedPatterns @(
            'applied outcome требует candidate в состоянии applied'
        ) -Name 'research applied outcome requires applied candidate state'

        $appliedResearchCandidate = Get-FixtureCandidate `
            -State 'applied' `
            -SourceRef 'research/runs/2026-07-30-test/decision.md' `
            -AdditionalSourceRefs 'evidence:SRC-001' `
            -CaptureBasis 'research-derived' `
            -AuthorityRef 'user-request:selftest-research-promotion' `
            -AppliedAt "'2026-07-30T12:30:00+04:00'"
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative $researchCandidatePath `
            -Content $appliedResearchCandidate
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content (Get-FixtureDecision -Outcome "ready:$primaryResearchCandidateId" -CandidateIds $primaryResearchCandidateId)
        $historicalReadyAfterPromotion = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet `
            -Result $historicalReadyAfterPromotion `
            -AllowedPatterns @() `
            -Name 'historical research ready outcome remains valid after candidate promotion to applied'

        $dismissedResearchCandidate = $researchCandidate.
            Replace('state: ready', 'state: dismissed').
            Replace('dismiss_reason: null', 'dismiss_reason: rejected').
            Replace("authority_ref: 'policy:knowledge-contract-v1'", "authority_ref: 'user-request:selftest-research-dismissal'")
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative $researchCandidatePath `
            -Content $dismissedResearchCandidate
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content (Get-FixtureDecision -Outcome "ready:$primaryResearchCandidateId" -CandidateIds $primaryResearchCandidateId)
        $historicalReadyAfterDismissal = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet `
            -Result $historicalReadyAfterDismissal `
            -AllowedPatterns @() `
            -Name 'historical research ready outcome remains valid after candidate dismissal'
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content (Get-FixtureDecision -Outcome "READY:$primaryResearchCandidateId" -CandidateIds $primaryResearchCandidateId)
        $researchOutcomeCaseMismatch = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $researchOutcomeCaseMismatch -AllowedPatterns @(
            'основной knowledge outcome имеет недопустимый формат'
        ) -Name 'research outcome keywords are case-sensitive and cannot bypass state checks'
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content (Get-FixtureDecision -Outcome 'blocked' -CandidateIds $primaryResearchCandidateId)
        $researchDismissedBlockedOutcome = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet `
            -Result $researchDismissedBlockedOutcome `
            -AllowedPatterns @() `
            -Name 'research blocked outcome retains dismissed candidate provenance'
        Write-FixtureFile -Base $temporaryBase -Relative $researchCandidatePath -Content $researchCandidate

        $additionalResearchCandidates = @(
            [pscustomobject]@{ Id = 'KC-20260730-120001-a1b2c3d4'; Claim = 'fixture-research-claim-two' },
            [pscustomobject]@{ Id = 'KC-20260730-120002-b2c3d4e5'; Claim = 'fixture-research-claim-three' },
            [pscustomobject]@{ Id = 'KC-20260730-120003-c3d4e5f6'; Claim = 'fixture-research-claim-four' }
        )
        foreach ($entry in @($additionalResearchCandidates[0])) {
            $candidateContent = (Get-FixtureCandidate `
                -Id $entry.Id `
                -SourceRef 'research/runs/2026-07-30-test/decision.md' `
                -AdditionalSourceRefs 'evidence:SRC-001' `
                -CaptureBasis 'research-derived').Replace('claim_key: fixture-claim', "claim_key: $($entry.Claim)")
            Write-FixtureFile `
                -Base $temporaryBase `
                -Relative "knowledge/candidates/2026/$($entry.Id).md" `
                -Content $candidateContent
        }

        $secondResearchCandidateId = $additionalResearchCandidates[0].Id
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content (Get-FixtureDecision `
                -Outcome "ready:$secondResearchCandidateId" `
                -CandidateIds @(
                    $primaryResearchCandidateId,
                    $secondResearchCandidateId
                ))
        $researchPrimaryOrderMismatch = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $researchPrimaryOrderMismatch -AllowedPatterns @(
            'primary candidate должен быть первым'
        ) -Name 'research decision requires primary candidate first'

        foreach ($entry in @($additionalResearchCandidates[1..2])) {
            $candidateContent = (Get-FixtureCandidate `
                -Id $entry.Id `
                -SourceRef 'research/runs/2026-07-30-test/decision.md' `
                -AdditionalSourceRefs 'evidence:SRC-001' `
                -CaptureBasis 'research-derived').Replace('claim_key: fixture-claim', "claim_key: $($entry.Claim)")
            Write-FixtureFile `
                -Base $temporaryBase `
                -Relative "knowledge/candidates/2026/$($entry.Id).md" `
                -Content $candidateContent
        }

        $fourResearchCandidateIds = @($primaryResearchCandidateId) + @($additionalResearchCandidates.Id)
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content (Get-FixtureDecision `
                -Outcome "ready:$primaryResearchCandidateId" `
                -CandidateIds $fourResearchCandidateIds)
        $researchCandidateLimit = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $researchCandidateLimit -AllowedPatterns @(
            'research run может иметь не более трех central candidates'
        ) -Name 'research decision and linked candidates enforce noise budget of three'

        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative $researchCandidatePath `
            -Content (Get-FixtureCandidate `
                -SourceRef 'evidence:SRC-001' `
                -CaptureBasis 'research-derived')
        foreach ($entry in $additionalResearchCandidates) {
            $orphanCandidateContent = (Get-FixtureCandidate `
                -Id $entry.Id `
                -SourceRef 'evidence:SRC-001' `
                -CaptureBasis 'research-derived').Replace(
                    'claim_key: fixture-claim',
                    "claim_key: $($entry.Claim)"
                )
            Write-FixtureFile `
                -Base $temporaryBase `
                -Relative "knowledge/candidates/2026/$($entry.Id).md" `
                -Content $orphanCandidateContent
        }
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content (Get-FixtureDecision)
        $fourOrphanResearchCandidates = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $fourOrphanResearchCandidates -AllowedPatterns @(
            'research-derived candidate требует точный source_ref на decision\.md',
            'research run может иметь не более трех central candidates',
            'Central candidate IDs не совпадает с candidates, ссылающимися на этот decision\.md',
            'outcome без primary candidate требует пустой список Central candidate IDs'
        ) -Name 'four evidence-only research candidates cannot bypass decision registration or noise budget'

        foreach ($entry in $additionalResearchCandidates) {
            Remove-Item `
                -LiteralPath (Join-Path $temporaryBase "knowledge/candidates/2026/$($entry.Id).md") `
                -Force
        }
        Write-FixtureFile -Base $temporaryBase -Relative $researchCandidatePath -Content (Get-FixtureCandidate)
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/decision.md' -Content (Get-FixtureDecision)

        $projectSequence = $project.Replace(
            'repository_kind: generated-project',
            "repository_kind:`n  - generated-project"
        )
        Write-FixtureFile -Base $temporaryBase -Relative 'PROJECT.md' -Content $projectSequence
        $projectSequenceResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $projectSequenceResult -AllowedPatterns @(
            "^PROJECT\.md: поле 'repository_kind' должно быть YAML scalar\.$"
        ) -Name 'verifier rejects one-item PROJECT scalar sequence'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'project-scalar-sequence' `
            -ExpectedMessagePattern "^PROJECT\.md: поле 'repository_kind' должно быть YAML scalar\.$" `
            -Name 'generator rejects one-item PROJECT scalar sequence without artifact'
        $projectMetadataSentinel = 'ProjectMetadataLeakSentinel123456'
        $invalidProjectMetadata = $project.Replace('repository_kind: generated-project', "repository_kind: $projectMetadataSentinel")
        Write-FixtureFile -Base $temporaryBase -Relative 'PROJECT.md' -Content $invalidProjectMetadata
        $invalidProjectMetadataResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $invalidProjectMetadataResult -AllowedPatterns @(
            '^PROJECT\.md: invalid repository_kind\.$',
            '^PROJECT\.md: несогласованная пара режима и capture mode\.$'
        ) -Name 'project invalid metadata is rejected without raw value'
        Assert-SelfTest -Condition (
            @($invalidProjectMetadataResult.Issues | Where-Object {
                $_ -match [regex]::Escape($projectMetadataSentinel)
            }).Count -eq 0
        ) -Name 'project metadata diagnostics omit sentinel'
        Write-FixtureFile -Base $temporaryBase -Relative 'PROJECT.md' -Content $project

        Assert-SelfTest -Condition ((Get-UnsafeFindings 'https://example.com/path').Count -eq 0) -Name 'HTTPS is not a local drive path'
        $safeHttpsSamples = @(
            'https://example.com/candidate',
            'Evidence source https://example.com/evidence?view=summary',
            'RAW source https://example.com/raw',
            '[Safe link](https://example.com/path)',
            '<https://example.com/autolink>',
            'Code `https://example.com/docs?mode=public`.'
        )
        Assert-SelfTest -Condition (
            @($safeHttpsSamples | Where-Object { (Get-UnsafeFindings $_).Count -ne 0 }).Count -eq 0
        ) -Name 'HTTPS candidate, evidence, RAW and autolink pass safety heuristics'
        $maskedSignedUrlSentinel = 'CodeMaskSecretSentinel123456'
        $maskedSignedUrlSamples = @(
            ('Code `https://example.com/resource?X-Amz-Signature=' + $maskedSignedUrlSentinel + '`.'),
            (@(
                '```text',
                ('https://example.com/resource?token=' + $maskedSignedUrlSentinel),
                '```'
            ) -join "`n")
        )
        Assert-SelfTest -Condition (
            @($maskedSignedUrlSamples | Where-Object {
                'signed-url' -cnotin @(Get-UnsafeFindings $_)
            }).Count -eq 0
        ) -Name 'signed URLs remain unsafe inside inline and fenced code for candidate RAW evidence and mastery'

        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/decision.md' -Content (Get-FixtureDecision -EvidenceRefs 'evidence:SRC-001, evidence:SRC-999')
        $brokenArbitraryEvidence = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $brokenArbitraryEvidence -AllowedPatterns @(
            'broken evidence ID в обязательной форме evidence:<id>'
        ) -Name 'arbitrary broken evidence ID'
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/decision.md' -Content (Get-FixtureDecision -EvidenceRefs 'SRC-001')
        $bareEvidence = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $bareEvidence -AllowedPatterns @(
            'evidence ID должен использовать однозначный синтаксис evidence:<id>'
        ) -Name 'decision requires evidence colon syntax'
        $decisionTokenFlood = (('x ' * ($maxResearchDecisionTokensPerFile + 1)) + "`n" + (Get-FixtureDecision))
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/decision.md' `
            -Content $decisionTokenFlood
        $decisionTokenFloodResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $decisionTokenFloodResult -AllowedPatterns @(
            "token-count превышает limit $maxResearchDecisionTokensPerFile"
        ) -Name 'research decision token budget bounds adversarial many-token input'
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/decision.md' -Content (Get-FixtureDecision)

        $evidencePropertySentinel = 'EvidencePropertyLeakSentinel123456'
        $nestedEvidenceRow = Get-FixtureEvidenceRow
        $nestedEvidenceRow.observation = [ordered]@{ nested = 'forbidden' }
        $nestedEvidenceRow[$evidencePropertySentinel] = 'forbidden'
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content (($nestedEvidenceRow | ConvertTo-Json -Compress -Depth 4) + "`n")
        $invalidEvidenceShape = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $invalidEvidenceShape -AllowedPatterns @(
            'evidence содержит неизвестное поле',
            "evidence field 'observation' должен быть scalar",
            'broken evidence ID в обязательной форме evidence:<id>'
        ) -RequiredPatterns @(
            'evidence содержит неизвестное поле',
            "evidence field 'observation' должен быть scalar"
        ) -Name 'evidence rejects unknown and nested fields'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'evidence-schema-redaction' `
            -ExpectedMessagePattern '^Evidence schema mismatch: research/runs/2026-07-30-test/evidence\.jsonl:1;' `
            -ForbiddenMessagePatterns @(
                [regex]::Escape($temporaryBase),
                [regex]::Escape($evidencePropertySentinel)
            ) `
            -Name 'generator evidence schema diagnostics omit property and absolute path'

        $nestedEvidenceRow.Remove($evidencePropertySentinel)
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content (($nestedEvidenceRow | ConvertTo-Json -Compress -Depth 4) + "`n")
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'evidence-type-redaction' `
            -ExpectedMessagePattern '^Evidence field должен быть scalar: research/runs/2026-07-30-test/evidence\.jsonl:1$' `
            -ForbiddenMessagePatterns @(
                [regex]::Escape($temporaryBase),
                'observation|nested|forbidden'
            ) `
            -Name 'generator evidence type diagnostics omit field payload and absolute path'

        $evidenceMetadataSentinel = 'EvidenceMetadataLeakSentinel123456!'
        $invalidEvidenceMetadataRow = Get-FixtureEvidenceRow -EvidenceId $evidenceMetadataSentinel
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content (($invalidEvidenceMetadataRow | ConvertTo-Json -Compress) + "`n")
        $invalidEvidenceMetadataResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $invalidEvidenceMetadataResult -AllowedPatterns @(
            'invalid evidence_id',
            'broken evidence ID в обязательной форме evidence:<id>'
        ) -Name 'evidence invalid metadata is rejected without raw value'
        Assert-SelfTest -Condition (
            @($invalidEvidenceMetadataResult.Issues | Where-Object {
                $_ -match [regex]::Escape($evidenceMetadataSentinel)
            }).Count -eq 0
        ) -Name 'evidence metadata diagnostics omit sentinel'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'evidence-id-redaction' `
            -ExpectedMessagePattern '^Invalid evidence_id: research/runs/2026-07-30-test/evidence\.jsonl:1$' `
            -ForbiddenMessagePatterns @(
                [regex]::Escape($temporaryBase),
                [regex]::Escape($evidenceMetadataSentinel)
            ) `
            -Name 'generator invalid evidence ID diagnostics omit ID and absolute path'
        Assert-GeneratorCliRejectIsRedacted `
            -FixtureRoot $temporaryBase `
            -ForbiddenMessagePatterns @(
                [regex]::Escape($temporaryBase),
                [regex]::Escape((Split-Path -Parent $PSScriptRoot)),
                [regex]::Escape($evidenceMetadataSentinel),
                '(?m)^At '
            ) `
            -Name 'generator CLI rejection omits InvocationInfo, metadata and absolute paths'

        $duplicateEvidenceSentinel = 'EvidenceDuplicateLeakSentinel123456'
        $duplicateEvidenceRow = Get-FixtureEvidenceRow -EvidenceId $duplicateEvidenceSentinel
        $duplicateEvidenceJson = $duplicateEvidenceRow | ConvertTo-Json -Compress
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'research/runs/2026-07-30-test/evidence.jsonl' `
            -Content ($duplicateEvidenceJson + "`n" + $duplicateEvidenceJson + "`n")
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'duplicate-evidence-id-redaction' `
            -ExpectedMessagePattern '^Duplicate evidence_id обнаружен до создания candidate: research/runs/2026-07-30-test/evidence\.jsonl:2$' `
            -ForbiddenMessagePatterns @(
                [regex]::Escape($temporaryBase),
                [regex]::Escape($duplicateEvidenceSentinel)
            ) `
            -Name 'generator duplicate evidence ID diagnostics omit ID and absolute path'

        $encodedHtmlEvidenceRow = Get-FixtureEvidenceRow
        $encodedHtmlEvidenceRow.observation = '<img src=x onerror=alert(1)>'
        $encodedHtmlJson = $encodedHtmlEvidenceRow | ConvertTo-Json -Compress
        $encodedHtmlJson = $encodedHtmlJson.Replace('<', '\u003c').Replace('>', '\u003e')
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content ($encodedHtmlJson + "`n")
        $decodedUnsafeEvidence = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $decodedUnsafeEvidence -AllowedPatterns @(
            "evidence field 'observation'.*\(raw-html\)"
        ) -Name 'evidence scans decoded scalar strings for unsafe HTML'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'decoded-unsafe-evidence-preflight' `
            -SourceRefs 'evidence:SRC-001' `
            -ExpectedMessagePattern '^blocked: repository-preflight$' `
            -ForbiddenMessagePatterns 'onerror|alert\(1\)' `
            -Name 'generator trusted preflight rejects decoded unsafe evidence without artifact or disclosure'
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content (($httpsEvidenceRow | ConvertTo-Json -Compress) + "`n")

        $oversizedEvidenceLine = '{"oversized":"' + ('A' * ($maxEvidenceLineChars + 1)) + '"}'
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content ($oversizedEvidenceLine + "`n")
        $oversizedEvidence = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $oversizedEvidence -AllowedPatterns @(
            'evidence line превышает char limit',
            'broken evidence ID в обязательной форме evidence:<id>'
        ) -RequiredPatterns @('evidence line превышает char limit') -Name 'evidence line limit'
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content (($httpsEvidenceRow | ConvertTo-Json -Compress) + "`n")

        $secretSamples = @(
            ('github_pat_' + ('A' * 30)),
            ('xoxb-' + ('A' * 20)),
            ('AIza' + ('A' * 35)),
            ('sk_live_' + ('A' * 24))
        )
        $secretFindings = @($secretSamples | Where-Object { (Get-UnsafeFindings $_).Count -eq 0 })
        Assert-SelfTest -Condition ($secretFindings.Count -eq 0) -Name 'expanded credential signatures are detected heuristically'

        $creatorPath = Join-Path $PSScriptRoot 'new-knowledge-candidate.ps1'
        $candidateDirectory = [System.IO.Path]::Combine($temporaryBase, 'knowledge', 'candidates')
        $positiveGeneratorPreflight = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet `
            -Result $positiveGeneratorPreflight `
            -AllowedPatterns @() `
            -Name 'positive generator fixture passes strict preflight'
        $selfTestHostPath = Get-TrustedCurrentPowerShellHostPath
        if ($null -eq $selfTestHostPath) {
            throw 'SELFTEST FAIL: unsupported PowerShell host for public strict preflight.'
        }
        $publicPreflightOutput = @(
            & $selfTestHostPath `
                -NoLogo `
                -NoProfile `
                -NonInteractive `
                -ExecutionPolicy Bypass `
                -File (Join-Path $PSScriptRoot 'verify-knowledge.ps1') `
                -Root $temporaryBase 2>&1
        )
        $publicPreflightExitCode = $LASTEXITCODE
        if ($publicPreflightExitCode -ne 0) {
            foreach ($publicPreflightLine in $publicPreflightOutput) {
                Write-Host "SELFTEST PUBLIC PREFLIGHT: $(Convert-ToSafeDiagnostic -Text ([string]$publicPreflightLine))"
            }
        }
        Assert-SelfTest `
            -Condition ($publicPreflightExitCode -eq 0) `
            -Name 'positive generator fixture passes public strict preflight'
        $positiveCreatorResult = & $creatorPath `
            -Root $temporaryBase `
            -Type decision `
            -Domain architecture `
            -ClaimKey https-generator-positive `
            -TargetRef 'docs/target.md#knowledge' `
            -SourceRefs 'https://example.com/evidence' `
            -Confidence high `
            -CaptureBasis repo-derived `
            -DataClass internal `
            -Title 'HTTPS generator fixture' `
             -Basis '[Безопасная метка \]](https://example.com/evidence) и `[literal](vbscript:msgbox(1))`.' `
            -ProposedChange 'Добавить правило.' `
            -DuplicateCheck 'Дубли не найдены.' `
            -ReviewDue '2099-12-31' `
            -WriteIntent explicit-promotion `
            -AuthorityRef user-request:selftest-generator-positive
        $positiveCreatorPath = Join-Path $temporaryBase ([string]$positiveCreatorResult.path)
        Assert-SelfTest -Condition (
            [string]$positiveCreatorResult.state -ceq 'ready' -and
            (Test-Path -LiteralPath $positiveCreatorPath -PathType Leaf)
        ) -Name 'generator accepts safe HTTPS candidate'
        Remove-Item -LiteralPath $positiveCreatorPath -Force

        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content ($oversizedEvidenceLine + "`n")
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'oversized-ledger' `
            -ExpectedMessagePattern '^Evidence line превышает char limit' `
            -Name 'generator bounded ledger scan leaves no final or draft'
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content (($httpsEvidenceRow | ConvertTo-Json -Compress) + "`n")

        $halfCandidateLimit = 'A' * [int]($maxTextFileBytes / 2)
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'oversized-rendered-candidate' `
            -Basis $halfCandidateLimit `
            -ProposedChange $halfCandidateLimit `
            -ExpectedMessagePattern "^Сгенерированный candidate превышает UTF-8 byte limit $maxTextFileBytes\.$" `
            -ForbiddenMessagePatterns 'A{64}' `
            -Name 'generator rejects oversized rendered candidate without file directory draft or body disclosure'
        $halfCandidateLimit = $null

        $structureCases = @(
            [pscustomobject]@{
                Key = 'atx-heading-zero-space'
                Body = "Допустимая строка.`n# Injected H1"
                Pattern = '^Basis не допускает CommonMark ATX heading\.$'
            },
            [pscustomobject]@{
                Key = 'atx-heading-three-spaces'
                Body = "Допустимая строка.`n   ### Injected H3"
                Pattern = '^Basis не допускает CommonMark ATX heading\.$'
            },
            [pscustomobject]@{
                Key = 'setext-heading'
                Body = "Допустимая строка.`nInjected title`n==="
                Pattern = '^Basis не допускает Setext heading\.$'
            },
            [pscustomobject]@{
                Key = 'horizontal-rule'
                Body = "Допустимая строка.`n* * *"
                Pattern = '^Basis не допускает horizontal rule\.$'
            }
        )
        foreach ($case in $structureCases) {
            Assert-GeneratorRejectedWithoutArtifact `
                -FixtureRoot $temporaryBase `
                -ClaimKey $case.Key `
                -Basis $case.Body `
                -ExpectedMessagePattern $case.Pattern `
                -Name "generator rejects $($case.Key) without final or draft"
        }

        $rawHtmlCases = @(
            [pscustomobject]@{ Key = 'raw-html-img'; Body = '<img src="https://example.com/x.png">'; Label = 'img tag' },
            [pscustomobject]@{ Key = 'raw-html-anchor'; Body = '<a href="https://example.com">link</a>'; Label = 'a tag' },
            [pscustomobject]@{ Key = 'raw-html-comment'; Body = '<!-- hidden instruction -->'; Label = 'HTML comment' }
        )
        foreach ($case in $rawHtmlCases) {
            Assert-GeneratorRejectedWithoutArtifact `
                -FixtureRoot $temporaryBase `
                -ClaimKey $case.Key `
                -Basis $case.Body `
                -ExpectedMessagePattern '^Basis не допускает raw HTML tags или comments\.$' `
                -Name "generator rejects $($case.Label) before publish"
        }

        $markdownUriCases = @(
            [pscustomobject]@{ Key = 'markdown-link-dangerous'; Body = '[link](javascript:alert(1))'; Pattern = '^Basis содержит опасный Markdown URI\.$' },
            [pscustomobject]@{ Key = 'markdown-link-vbscript'; Body = '[open](vbscript:msgbox(1))'; Pattern = '^Basis содержит опасный Markdown URI\.$' },
            [pscustomobject]@{ Key = 'markdown-escaped-label-vbscript'; Body = '[a\]](vbscript:msgbox(1))'; Pattern = '^Basis содержит опасный Markdown URI\.$' },
            [pscustomobject]@{ Key = 'markdown-image-dangerous'; Body = '![image](data:image/svg+xml;base64,AAAA)'; Pattern = '^Basis содержит опасный Markdown URI\.$' },
            [pscustomobject]@{ Key = 'markdown-link-protocol-relative'; Body = '[link](//evil.example/path)'; Pattern = '^Basis содержит protocol-relative Markdown URI\.$' },
            [pscustomobject]@{ Key = 'markdown-autolink-dangerous'; Body = '<javascript:alert(1)>'; Pattern = '^Basis содержит опасный Markdown URI\.$' },
            [pscustomobject]@{ Key = 'markdown-autolink-protocol-relative'; Body = '<//evil.example/path>'; Pattern = '^Basis содержит protocol-relative Markdown URI\.$' }
        )
        foreach ($case in $markdownUriCases) {
            Assert-GeneratorRejectedWithoutArtifact `
                -FixtureRoot $temporaryBase `
                -ClaimKey $case.Key `
                -Basis $case.Body `
                -ExpectedMessagePattern $case.Pattern `
                -Name "generator rejects $($case.Key) before publish"
        }

        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'signed-source-x-amz' `
            -SourceRefs 'https://example.com/object?X-Amz-Signature=abcdef' `
            -ExpectedMessagePattern '^SourceRefs содержит потенциально подписанный URL или credential в query\.$' `
            -Name 'generator rejects X-Amz-Signature in SourceRefs'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'signed-source-percent-token' `
            -SourceRefs 'https://example.com/object?to%6ben=abcdef' `
            -ExpectedMessagePattern '^SourceRefs содержит потенциально подписанный URL или credential в query\.$' `
            -Name 'generator rejects percent-decoded token in SourceRefs'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'signed-body-percent-token' `
            -Basis 'Источник https://example.com/object?to%6ben=abcdef' `
            -ExpectedMessagePattern '^Basis содержит потенциально подписанный URL или credential в query\.$' `
            -Name 'generator rejects percent-decoded token in candidate body'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'signed-body-authorization' `
            -Basis 'Источник https://example.com/object?AuTh%6frization=SecretValue123456' `
            -ExpectedMessagePattern '^Basis содержит потенциально подписанный URL или credential в query\.$' `
            -Name 'generator rejects percent-decoded authorization query without logging value' `
            -ForbiddenMessagePatterns 'SecretValue123456'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'signed-inline-code-url' `
            -Basis ('Наблюдение: `https://example.com/resource?X-Amz-Signature=' + $maskedSignedUrlSentinel + '`.') `
            -ExpectedMessagePattern '^Basis содержит потенциально подписанный URL или credential в query\.$' `
            -Name 'generator rejects signed URL inside inline code without artifact or disclosure' `
            -ForbiddenMessagePatterns $maskedSignedUrlSentinel
        $fencedSignedGeneratorBody = @(
            '```text',
            ('https://example.com/resource?token=' + $maskedSignedUrlSentinel),
            '```'
        ) -join "`n"
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'signed-fenced-code-url' `
            -Basis $fencedSignedGeneratorBody `
            -ExpectedMessagePattern '^Basis содержит потенциально подписанный URL или credential в query\.$' `
            -Name 'generator rejects signed URL inside fenced code without artifact or disclosure' `
            -ForbiddenMessagePatterns $maskedSignedUrlSentinel
        $sensitiveQueryGeneratorCases = @(
            [pscustomobject]@{
                ClaimKey = 'signed-body-auth'
                Query = 'a%75th=SecretValue123456'
                Name = 'generator rejects percent-decoded auth query without logging value or artifact'
            },
            [pscustomobject]@{
                ClaimKey = 'signed-body-passwd'
                Query = 'PaSs%77d=SecretValue123456'
                Name = 'generator rejects case-mixed percent-decoded passwd query without logging value or artifact'
            },
            [pscustomobject]@{
                ClaimKey = 'signed-body-shared-access-signature'
                Query = 'ShArEd%41ccessSignature=SecretValue123456'
                Name = 'generator rejects case-mixed percent-decoded sharedaccesssignature query without logging value or artifact'
            }
        )
        foreach ($case in $sensitiveQueryGeneratorCases) {
            Assert-GeneratorRejectedWithoutArtifact `
                -FixtureRoot $temporaryBase `
                -ClaimKey $case.ClaimKey `
                -Basis "Источник https://example.com/object?$($case.Query)" `
                -ExpectedMessagePattern '^Basis содержит потенциально подписанный URL или credential в query\.$' `
                -Name $case.Name `
                -ForbiddenMessagePatterns 'SecretValue123456'
        }
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'external-target-redaction' `
            -TargetRef 'https://user:ExternalRefSecretSentinel123456@localhost/object?auth=ExternalRefSecretSentinel123456' `
            -ExpectedMessagePattern '^TargetRef не допускает внешний URL\.$' `
            -ForbiddenMessagePatterns 'ExternalRefSecretSentinel123456' `
            -Name 'generator redacts external TargetRef userinfo and query value'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'invalid-body-https' `
            -Basis 'Источник https://[invalid' `
            -ExpectedMessagePattern '^Basis содержит некорректный HTTPS URL\.$' `
            -Name 'generator rejects invalid HTTPS URL in body without final or draft'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'userinfo-body-https' `
            -Basis 'Источник https://user@localhost/path' `
            -ExpectedMessagePattern '^Basis содержит HTTPS URL с запрещенным userinfo\.$' `
            -Name 'generator rejects HTTPS userinfo in body without final or draft'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'missing-conflict-evidence' `
            -ConflictRefs 'evidence:MissingEvidenceRefLeakSentinel123456' `
            -ExpectedMessagePattern '^ConflictRefs ссылается на отсутствующий evidence ID\.$' `
            -ForbiddenMessagePatterns 'MissingEvidenceRefLeakSentinel123456' `
            -Name 'generator rejects broken evidence conflict without artifact or ID disclosure'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'research-run-directory-source' `
            -SourceRefs 'research/runs/2026-07-30-test' `
            -ExpectedMessagePattern '^SourceRefs ссылается на отсутствующий файл: research/runs/2026-07-30-test$' `
            -Name 'generator rejects research run directory and requires exact source file'

        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -ClaimKey 'secret-rendered-body' `
            -Basis ('github_pat_' + ('A' * 30)) `
            -ExpectedMessagePattern '^Basis содержит потенциально небезопасный материал.*credential-like-token-prefix' `
            -Name 'generator rejects credential signature without final or draft'
        Assert-GeneratorRejectedWithoutArtifact `
            -FixtureRoot $temporaryBase `
            -Type method `
            -Domain architecture `
            -ClaimKey 'method.generator-invalid-domain' `
            -TargetRef 'mastery/local/INDEX.md#зарегистрированные-расширения' `
            -SourceRefs 'docs/source.md' `
            -CaptureBasis explicit-user-capture `
            -AuthorityRef user-request:selftest-method-generator `
            -ExpectedMessagePattern '^Method candidate требует Domain mastery\.$' `
            -Name 'generator rejects method candidate with non-mastery domain'

        $fixtureCandidatePath = 'knowledge/candidates/2026/KC-20260730-120000-deadbeef.md'
        $baseCandidateContent = Get-FixtureCandidate
        $stateSequenceContent = $baseCandidateContent.Replace(
            'state: ready',
            "state:`n  - ready"
        )
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $stateSequenceContent
        $stateSequenceResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $stateSequenceResult -AllowedPatterns @(
            "^knowledge/candidates/2026/KC-20260730-120000-deadbeef\.md: поле 'state' должно быть YAML scalar\.$"
        ) -Name 'verifier rejects one-item candidate state sequence'

        $nullableSequenceContent = $baseCandidateContent.Replace(
            "review_due: '2099-12-31'",
            "review_due:`n  - '2099-12-31'"
        )
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $nullableSequenceContent
        $nullableSequenceResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $nullableSequenceResult -AllowedPatterns @(
            "^knowledge/candidates/2026/KC-20260730-120000-deadbeef\.md: поле 'review_due' должно быть YAML scalar или null\.$"
        ) -Name 'verifier rejects one-item candidate nullable sequence'

        $candidateMetadataSentinel = 'CandidateMetadataLeakSentinel123456'
        $invalidCandidateMetadata = $baseCandidateContent.Replace(
            "id: 'KC-20260730-120000-deadbeef'",
            "id: '$candidateMetadataSentinel'"
        )
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $invalidCandidateMetadata
        $invalidCandidateMetadataResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $invalidCandidateMetadataResult -AllowedPatterns @(
            'invalid candidate id'
        ) -Name 'candidate invalid metadata is rejected without raw value'
        Assert-SelfTest -Condition (
            @($invalidCandidateMetadataResult.Issues | Where-Object {
                $_ -match [regex]::Escape($candidateMetadataSentinel)
            }).Count -eq 0
        ) -Name 'candidate metadata diagnostics omit sentinel'
        $duplicateInvalidCandidatePath = 'knowledge/candidates/2026/KC-20260730-120001-feedface.md'
        $duplicateInvalidCandidate = $invalidCandidateMetadata.Replace(
            'claim_key: fixture-claim',
            'claim_key: fixture-claim-duplicate-invalid-id'
        )
        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative $duplicateInvalidCandidatePath `
            -Content $duplicateInvalidCandidate
        $duplicateInvalidCandidateResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $duplicateInvalidCandidateResult -AllowedPatterns @(
            'invalid candidate id'
        ) -Name 'duplicate invalid candidate IDs do not enter duplicate map'
        Assert-SelfTest -Condition (
            @($duplicateInvalidCandidateResult.Issues | Where-Object {
                $_ -match [regex]::Escape($candidateMetadataSentinel)
            }).Count -eq 0
        ) -Name 'duplicate invalid candidate ID diagnostics omit sentinel'
        Remove-Item -LiteralPath (Join-Path $temporaryBase $duplicateInvalidCandidatePath) -Force
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $baseCandidateContent

        $validExplicitMethodCandidate = Get-FixtureCandidate `
            -Type method `
            -Domain mastery `
            -ClaimKey method.fixture-analysis-review `
            -TargetRef 'mastery/local/INDEX.md#зарегистрированные-расширения' `
            -SourceRef 'docs/source.md' `
            -CaptureBasis explicit-user-capture `
            -AuthorityRef user-request:selftest-method-correction
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $validExplicitMethodCandidate
        $validExplicitMethodResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $validExplicitMethodResult -AllowedPatterns @() -Name 'method candidate accepts explicit operator correction with project source'

        $methodWithoutLearningEvidence = Get-FixtureCandidate `
            -Type method `
            -Domain mastery `
            -ClaimKey method.fixture-analysis-review `
            -TargetRef 'mastery/local/INDEX.md#зарегистрированные-расширения' `
            -SourceRef 'docs/source.md'
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $methodWithoutLearningEvidence
        $methodWithoutLearningEvidenceResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $methodWithoutLearningEvidenceResult -AllowedPatterns @(
            'method candidate требует два независимых task/run source или explicit operator correction'
        ) -RequiredPatterns @(
            'method candidate требует два независимых task/run source или explicit operator correction'
        ) -Name 'method candidate rejects single non-authoritative learning source'

        $methodWithNearMissTarget = $validExplicitMethodCandidate.Replace(
            "target_ref: 'mastery/local/INDEX.md#зарегистрированные-расширения'",
            "target_ref: 'mastery/local/INDEX.md#зарегистрированное-расширение'"
        )
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $methodWithNearMissTarget
        $methodWithNearMissTargetResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $methodWithNearMissTargetResult -AllowedPatterns @(
            'method candidate требует exact target_ref локального mastery registry'
        ) -RequiredPatterns @(
            'method candidate требует exact target_ref локального mastery registry'
        ) -Name 'method candidate rejects near-miss local mastery target'

        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $baseCandidateContent

        $candidateStructureCases = @(
            [pscustomobject]@{
                Name = 'verifier rejects ATX heading with three spaces'
                Content = $baseCandidateContent.Replace('Проверяемое основание.', "Проверяемое основание.`n   ### Injected H3")
            },
            [pscustomobject]@{
                Name = 'verifier rejects Setext heading'
                Content = $baseCandidateContent.Replace('Проверяемое основание.', "Проверяемое основание.`nInjected title`n===")
            },
            [pscustomobject]@{
                Name = 'verifier rejects horizontal rule'
                Content = $baseCandidateContent.Replace('Проверяемое основание.', "Проверяемое основание.`n_ _ _")
            }
        )
        foreach ($case in $candidateStructureCases) {
            Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $case.Content
            $result = Invoke-KnowledgeVerification $temporaryBase
            Assert-SelfTestIssueSet -Result $result -AllowedPatterns @(
                'candidate должен иметь ровно пять структурных headings|Setext headings и horizontal rules'
            ) -RequiredPatterns @(
                $(if ($case.Name -match 'ATX') { 'candidate должен иметь ровно пять структурных headings' } else { 'Setext headings и horizontal rules' })
            ) -Name $case.Name
        }

        $candidateUnsafeCases = @(
            [pscustomobject]@{ Name = 'verifier rejects raw img HTML'; Body = '<img src="https://example.com/x.png">'; Finding = 'raw-html' },
            [pscustomobject]@{ Name = 'verifier rejects raw anchor HTML'; Body = '<a href="https://example.com">link</a>'; Finding = 'raw-html' },
            [pscustomobject]@{ Name = 'verifier rejects raw HTML comment'; Body = '<!-- hidden -->'; Finding = 'raw-html' },
            [pscustomobject]@{ Name = 'verifier rejects dangerous Markdown link'; Body = '[link](javascript:alert(1))'; Finding = 'dangerous-markdown-uri' },
            [pscustomobject]@{ Name = 'verifier rejects vbscript Markdown link'; Body = '[open](vbscript:msgbox(1))'; Finding = 'dangerous-markdown-uri' },
            [pscustomobject]@{ Name = 'verifier rejects dangerous escaped-label Markdown link'; Body = '[a\]](vbscript:msgbox(1))'; Finding = 'dangerous-markdown-uri' },
            [pscustomobject]@{ Name = 'verifier rejects dangerous Markdown image'; Body = '![image](data:image/svg+xml;base64,AAAA)'; Finding = 'dangerous-markdown-uri' },
            [pscustomobject]@{ Name = 'verifier rejects protocol-relative Markdown link'; Body = '[link](//evil.example/path)'; Finding = 'protocol-relative-uri' },
            [pscustomobject]@{ Name = 'verifier rejects dangerous autolink'; Body = '<javascript:alert(1)>'; Finding = 'dangerous-markdown-uri' },
            [pscustomobject]@{ Name = 'verifier rejects protocol-relative autolink'; Body = '<//evil.example/path>'; Finding = 'protocol-relative-uri' }
        )
        foreach ($case in $candidateUnsafeCases) {
            $content = $baseCandidateContent.Replace('Проверяемое основание.', $case.Body)
            Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $content
            $result = Invoke-KnowledgeVerification $temporaryBase
            Assert-SelfTestIssueSet -Result $result -AllowedPatterns @(
                "потенциально небезопасный материал в candidate.*\($([regex]::Escape($case.Finding))\)"
            ) -Name $case.Name
        }

        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content (
            Get-FixtureCandidate -SourceRef 'https://example.com/object?X-Amz-Signature=abcdef'
        )
        $signedSource = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $signedSource -AllowedPatterns @(
            'потенциально подписанный URL или credential в query',
            'потенциально небезопасный материал в candidate.*\(signed-url\)'
        ) -Name 'verifier rejects X-Amz-Signature in candidate SourceRefs'

        $signedBodyContent = $baseCandidateContent.Replace(
            'Проверяемое основание.',
            'Источник https://example.com/object?to%6ben=abcdef'
        )
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $signedBodyContent
        $signedBody = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $signedBody -AllowedPatterns @(
            'потенциально небезопасный материал в candidate.*\(signed-url\)'
        ) -Name 'verifier rejects percent-decoded token in candidate body'

        $inlineCodeSignedBody = $baseCandidateContent.Replace(
            'Проверяемое основание.',
            ('Наблюдение: `https://example.com/resource?X-Amz-Signature=' + $maskedSignedUrlSentinel + '`.')
        )
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $inlineCodeSignedBody
        $inlineCodeSignedResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $inlineCodeSignedResult -AllowedPatterns @(
            'потенциально небезопасный материал в candidate.*\(signed-url\)'
        ) -Name 'verifier rejects signed URL inside inline code'
        Assert-SelfTest -Condition (
            @($inlineCodeSignedResult.Issues | Where-Object { $_ -match [regex]::Escape($maskedSignedUrlSentinel) }).Count -eq 0
        ) -Name 'inline-code signed URL diagnostics omit sentinel'

        $fencedSignedVerifierBody = @(
            '```text',
            ('https://example.com/resource?token=' + $maskedSignedUrlSentinel),
            '```'
        ) -join "`n"
        $fencedCodeSignedBody = $baseCandidateContent.Replace('Проверяемое основание.', $fencedSignedVerifierBody)
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $fencedCodeSignedBody
        $fencedCodeSignedResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $fencedCodeSignedResult -AllowedPatterns @(
            'потенциально небезопасный материал в candidate.*\(signed-url\)'
        ) -Name 'verifier rejects signed URL inside fenced code'
        Assert-SelfTest -Condition (
            @($fencedCodeSignedResult.Issues | Where-Object { $_ -match [regex]::Escape($maskedSignedUrlSentinel) }).Count -eq 0
        ) -Name 'fenced-code signed URL diagnostics omit sentinel'

        $authorizationBodyContent = $baseCandidateContent.Replace(
            'Проверяемое основание.',
            'Источник https://example.com/object?AuTh%6frization=SecretValue123456'
        )
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $authorizationBodyContent
        $authorizationBody = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $authorizationBody -AllowedPatterns @(
            'потенциально небезопасный материал в candidate.*\(signed-url\)'
        ) -Name 'verifier rejects percent-decoded authorization query'

        $sensitiveQueryVerifierCases = @(
            [pscustomobject]@{
                Query = 'a%75th=SecretValue123456'
                Name = 'verifier rejects percent-decoded auth query without logging value'
            },
            [pscustomobject]@{
                Query = 'PaSs%77d=SecretValue123456'
                Name = 'verifier rejects case-mixed percent-decoded passwd query without logging value'
            },
            [pscustomobject]@{
                Query = 'ShArEd%41ccessSignature=SecretValue123456'
                Name = 'verifier rejects case-mixed percent-decoded sharedaccesssignature query without logging value'
            }
        )
        foreach ($case in $sensitiveQueryVerifierCases) {
            $sensitiveQueryBodyContent = $baseCandidateContent.Replace(
                'Проверяемое основание.',
                "Источник https://example.com/object?$($case.Query)"
            )
            Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $sensitiveQueryBodyContent
            $sensitiveQueryBody = Invoke-KnowledgeVerification $temporaryBase
            Assert-SelfTestIssueSet -Result $sensitiveQueryBody -AllowedPatterns @(
                '^knowledge/candidates/2026/KC-20260730-120000-deadbeef\.md: потенциально небезопасный материал в candidate по эвристическому сигналу \(signed-url\)\.$'
            ) -Name $case.Name
        }

        $externalTargetSentinel = 'ExternalTargetSecretSentinel123456'
        $externalTargetContent = $baseCandidateContent.Replace(
            "target_ref: 'docs/target.md#knowledge'",
            "target_ref: 'https://user:$externalTargetSentinel@localhost/object?auth=$externalTargetSentinel'"
        )
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $externalTargetContent
        $externalTargetResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $externalTargetResult -AllowedPatterns @(
            "^knowledge/candidates/2026/KC-20260730-120000-deadbeef\.md target_ref: внешний URL недопустим\.$",
            "^knowledge/candidates/2026/KC-20260730-120000-deadbeef\.md: потенциально небезопасный материал в candidate по эвристическому сигналу \(https-url-userinfo\)\.$"
        ) -Name 'verifier redacts external TargetRef userinfo and query value'
        Assert-SelfTest -Condition (
            @($externalTargetResult.Issues | Where-Object { $_ -match [regex]::Escape($externalTargetSentinel) }).Count -eq 0
        ) -Name 'verifier external TargetRef diagnostics omit sentinel'

        $invalidUrlBodyContent = $baseCandidateContent.Replace(
            'Проверяемое основание.',
            'Источник https://[invalid'
        )
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $invalidUrlBodyContent
        $invalidBodyUrl = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $invalidBodyUrl -AllowedPatterns @(
            'потенциально небезопасный материал в candidate.*\(invalid-https-url\)'
        ) -Name 'verifier rejects invalid HTTPS URL in candidate body'

        $userinfoUrlBodyContent = $baseCandidateContent.Replace(
            'Проверяемое основание.',
            'Источник https://user@localhost/path'
        )
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $userinfoUrlBodyContent
        $userinfoBodyUrl = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $userinfoBodyUrl -AllowedPatterns @(
            'потенциально небезопасный материал в candidate.*\(https-url-userinfo\)'
        ) -Name 'verifier rejects HTTPS userinfo in candidate body'

        $brokenConflictContent = $baseCandidateContent.Replace(
            'conflict_refs: []',
            "conflict_refs:`n  - 'evidence:SRC-999'"
        )
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $brokenConflictContent
        $brokenConflictEvidence = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $brokenConflictEvidence -AllowedPatterns @(
            'broken evidence ID в conflict_refs'
        ) -Name 'verifier rejects broken evidence conflict reference'

        $conflictReportSentinel = 'ConflictReportSecretSentinel123456'
        $sensitiveConflictContent = $baseCandidateContent.Replace(
            'conflict_refs: []',
            "conflict_refs:`n  - 'https://user:$conflictReportSentinel@localhost/object?auth=$conflictReportSentinel'"
        )
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $sensitiveConflictContent
        $sensitiveConflictResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $sensitiveConflictResult -AllowedPatterns @(
            '^knowledge/candidates/2026/KC-20260730-120000-deadbeef\.md conflict_refs: HTTPS URL содержит запрещенный userinfo\.$',
            '^knowledge/candidates/2026/KC-20260730-120000-deadbeef\.md: потенциально небезопасный материал в candidate по эвристическому сигналу \(https-url-userinfo\)\.$'
        ) -Name 'verifier rejects sensitive conflict URL without disclosure'
        Assert-SelfTest -Condition (
            @($sensitiveConflictResult.Issues | Where-Object { $_ -match [regex]::Escape($conflictReportSentinel) }).Count -eq 0 -and
            @($sensitiveConflictResult.Report.conflicts).Count -eq 1 -and
            [string]$sensitiveConflictResult.Report.conflicts[0] -ceq 'KC-20260730-120000-deadbeef -> count=1' -and
            [string]$sensitiveConflictResult.Report.conflicts[0] -notmatch [regex]::Escape($conflictReportSentinel)
        ) -Name 'conflict report prints count only and omits external ref sentinel'
        Write-FixtureFile -Base $temporaryBase -Relative $fixtureCandidatePath -Content $baseCandidateContent

        Write-FixtureFile -Base $temporaryBase -Relative 'docs/orphan.md' -Content "# Orphan`n"
        $orphan = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $orphan -AllowedPatterns @(
            '^Orphan canonical Markdown: docs/orphan\.md$'
        ) -Name 'orphan canonical Markdown'
        Remove-Item -LiteralPath (Join-Path $temporaryBase 'docs/orphan.md') -Force

        $unsafeRaw = @"
---
id: raw-20260730-1200-fixture
captured_at: '2026-07-30T12:00:00+04:00'
storage_basis: explicit-user-request
authority_ref: user-request:selftest-unsafe-raw
data_class: internal
content_mode: summary
personal_data: none
retention: '2099-12-31'
source: logical:selftest/unsafe-raw
rights: user-owned
author: unknown
scope: project
status: captured
related: []
---

# Unsafe RAW

Контакт: person@example.com
"@
        Write-FixtureFile -Base $temporaryBase -Relative 'inbox/raw/2026-07-30_12-00_fixture.md' -Content $unsafeRaw
        $rawResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $rawResult -AllowedPatterns @(
            'inbox/raw/2026-07-30_12-00_fixture\.md: data-safety finding in RAW \(email-or-pii\)'
        ) -Name 'unsafe RAW PII'
        Remove-Item -LiteralPath (Join-Path $temporaryBase 'inbox/raw/2026-07-30_12-00_fixture.md') -Force

        $rawMetadataSentinel = 'RawMetadataLeakSentinel123456'
$invalidRawMetadata = @"
---
id: raw-20260730-1201-metadata
captured_at: '2026-07-30T12:01:00+04:00'
storage_basis: $rawMetadataSentinel
authority_ref: user-request:selftest-raw-metadata
data_class: internal
content_mode: summary
personal_data: none
retention: 2099-12-31
source: https://example.com/raw-source
rights: user-owned
author: unknown
scope: project
status: captured
related: []
---

# RAW metadata fixture

Безопасное резюме.
"@
        Write-FixtureFile -Base $temporaryBase -Relative 'inbox/raw/2026-07-30_12-01_metadata.md' -Content $invalidRawMetadata
        $invalidRawMetadataResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $invalidRawMetadataResult -AllowedPatterns @(
            'invalid storage_basis'
        ) -Name 'RAW invalid metadata is rejected without raw value'
        Assert-SelfTest -Condition (
            @($invalidRawMetadataResult.Issues | Where-Object {
                $_ -match [regex]::Escape($rawMetadataSentinel)
            }).Count -eq 0
        ) -Name 'RAW metadata diagnostics omit sentinel'

        $rawScalarSequence = $invalidRawMetadata.Replace(
            "storage_basis: $rawMetadataSentinel",
            "storage_basis:`n  - explicit-user-request"
        )
        Write-FixtureFile -Base $temporaryBase -Relative 'inbox/raw/2026-07-30_12-01_metadata.md' -Content $rawScalarSequence
        $rawScalarSequenceResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $rawScalarSequenceResult -AllowedPatterns @(
            "RAW поле 'storage_basis' должно быть YAML scalar"
        ) -Name 'RAW required scalar field rejects one-item sequence'
        Remove-Item -LiteralPath (Join-Path $temporaryBase 'inbox/raw/2026-07-30_12-01_metadata.md') -Force

        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'inbox/raw/archive/secret.md' `
            -Content 'ArchiveSecretSentinel123456'
        $inboxArchiveRecord = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $inboxArchiveRecord -AllowedPatterns @(
            '^Физическая RAW archive record запрещена: inbox/raw/archive/secret\.md$'
        ) -Name 'inbox physical RAW archive record is rejected without reading content'
        Remove-Item -LiteralPath (Join-Path $temporaryBase 'inbox/raw/archive/secret.md') -Force

        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'business/raw/archive/secret.md' `
            -Content 'BusinessArchiveSecretSentinel123456'
        $businessArchiveRecord = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $businessArchiveRecord -AllowedPatterns @(
            '^Физическая RAW archive record запрещена: business/raw/archive/secret\.md$'
        ) -Name 'business physical RAW archive record is rejected without reading content'
        Remove-Item -LiteralPath (Join-Path $temporaryBase 'business/raw/archive/secret.md') -Force

        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'inbox/raw/secret.txt' `
            -Content 'InboxNonMarkdownSecretSentinel123456'
        $inboxNonMarkdownRaw = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $inboxNonMarkdownRaw -AllowedPatterns @(
            '^Недопустимый non-Markdown RAW file: inbox/raw/secret\.txt$'
        ) -Name 'inbox non-Markdown RAW file is rejected without reading content'
        Remove-Item -LiteralPath (Join-Path $temporaryBase 'inbox/raw/secret.txt') -Force

        Write-FixtureFile `
            -Base $temporaryBase `
            -Relative 'business/raw/secret.bin' `
            -Content 'BusinessNonMarkdownSecretSentinel123456'
        $businessNonMarkdownRaw = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $businessNonMarkdownRaw -AllowedPatterns @(
            '^Недопустимый non-Markdown RAW file: business/raw/secret\.bin$'
        ) -Name 'business arbitrary-extension RAW file is rejected without reading content'
        Remove-Item -LiteralPath (Join-Path $temporaryBase 'business/raw/secret.bin') -Force

        $boundedFile = Join-Path $temporaryBase 'docs/bounded.md'
        Write-FixtureFile -Base $temporaryBase -Relative 'docs/bounded.md' -Content '0123456789abcdef'
        $savedTextFileBytes = $maxTextFileBytes
        try {
            Set-Variable -Name maxTextFileBytes -Scope Script -Value 8
            $script:currentIssues = [System.Collections.Generic.List[string]]::new()
            $script:textReadPaths = [System.Collections.Generic.HashSet[string]]::new($script:pathComparer)
            $script:textReadCorpusBytes = [long]0
            Read-BoundedUtf8Text -FilePath $boundedFile -Context 'bounded file fixture' | Out-Null
            $boundedFileResult = [pscustomobject]@{ Issues = @($script:currentIssues) }
            Assert-SelfTestIssueSet -Result $boundedFileResult -AllowedPatterns @(
                '^bounded file fixture: text file превышает limit 8 bytes\.$'
            ) -Name 'bounded UTF-8 helper enforces per-file limit'
        }
        finally {
            Set-Variable -Name maxTextFileBytes -Scope Script -Value $savedTextFileBytes
        }

        Write-FixtureFile -Base $temporaryBase -Relative 'docs/bounded-two.md' -Content 'abcdefgh'
        $savedTextFiles = $maxTextFiles
        try {
            Set-Variable -Name maxTextFiles -Scope Script -Value 1
            $script:currentIssues = [System.Collections.Generic.List[string]]::new()
            $script:textReadPaths = [System.Collections.Generic.HashSet[string]]::new($script:pathComparer)
            $script:textReadCorpusBytes = [long]0
            Read-BoundedUtf8Text -FilePath $boundedFile -Context 'bounded count first' | Out-Null
            Read-BoundedUtf8Text -FilePath (Join-Path $temporaryBase 'docs/bounded-two.md') -Context 'bounded count second' | Out-Null
            $boundedCountResult = [pscustomobject]@{ Issues = @($script:currentIssues) }
            Assert-SelfTestIssueSet -Result $boundedCountResult -AllowedPatterns @(
                '^Text corpus превышает file-count limit 1\.$'
            ) -Name 'bounded UTF-8 helper enforces corpus file-count limit'
        }
        finally {
            Set-Variable -Name maxTextFiles -Scope Script -Value $savedTextFiles
        }

        $savedTextCorpusBytes = $maxTextCorpusBytes
        try {
            Set-Variable -Name maxTextCorpusBytes -Scope Script -Value 20
            $script:currentIssues = [System.Collections.Generic.List[string]]::new()
            $script:textReadPaths = [System.Collections.Generic.HashSet[string]]::new($script:pathComparer)
            $script:textReadCorpusBytes = [long]0
            Read-BoundedUtf8Text -FilePath $boundedFile -Context 'bounded corpus first' | Out-Null
            Read-BoundedUtf8Text -FilePath (Join-Path $temporaryBase 'docs/bounded-two.md') -Context 'bounded corpus second' | Out-Null
            $boundedCorpusResult = [pscustomobject]@{ Issues = @($script:currentIssues) }
            Assert-SelfTestIssueSet -Result $boundedCorpusResult -AllowedPatterns @(
                '^Text corpus превышает byte limit 20\.$'
            ) -Name 'bounded UTF-8 helper enforces corpus byte limit'
        }
        finally {
            Set-Variable -Name maxTextCorpusBytes -Scope Script -Value $savedTextCorpusBytes
        }
        Remove-Item -LiteralPath $boundedFile -Force
        Remove-Item -LiteralPath (Join-Path $temporaryBase 'docs/bounded-two.md') -Force

        $childTarget = Join-Path $temporaryBase 'child-reparse-target'
        $childJunction = Join-Path $temporaryBase 'docs/child-reparse'
        New-Item -ItemType Directory -Path $childTarget | Out-Null
        Write-FixtureFile -Base $childTarget -Relative 'source.md' -Content "# Child source`n"
        try {
            New-Item -ItemType $reparseItemType -Path $childJunction -Target $childTarget | Out-Null
            $script:currentIssues = [System.Collections.Generic.List[string]]::new()
            $script:textReadPaths = [System.Collections.Generic.HashSet[string]]::new($script:pathComparer)
            $script:textReadCorpusBytes = [long]0
            Read-BoundedUtf8Text `
                -FilePath (Join-Path $childJunction 'source.md') `
                -Context 'child reparse fixture' | Out-Null
            $childReparseResult = [pscustomobject]@{ Issues = @($script:currentIssues) }
            Assert-SelfTestIssueSet -Result $childReparseResult -AllowedPatterns @(
                '^child reparse fixture: чтение проходит через reparse point: docs/child-reparse$'
            ) -Name 'bounded UTF-8 helper rejects child reparse before read'
            Assert-GeneratorRejectedWithoutArtifact `
                -FixtureRoot $temporaryBase `
                -ClaimKey 'child-reparse-source' `
                -SourceRefs 'docs/child-reparse/source.md' `
                -ExpectedMessagePattern '^SourceRefs проходит через reparse point\.$' `
                -Name 'generator rejects child reparse source without final or draft'
        }
        finally {
            if (Test-Path -LiteralPath $childJunction) {
                [System.IO.Directory]::Delete($childJunction)
            }
        }

        Write-FixtureFile -Base $temporaryBase -Relative 'mastery/researcher/profile.md' -Content "# Profile`n"
        $indexWithProfile = @"
# Index

- [Project](PROJECT.md)
- [Source](docs/source.md)
- [Target](docs/target.md)
- [Candidate template](knowledge/candidates/TEMPLATE.md)
- [Local mastery](mastery/local/INDEX.md)
- [Researcher profile](mastery/researcher/profile.md)
- [Brief asset](.agents/skills/startup-researcher/assets/run-template/brief.md)
- [Candidates asset](.agents/skills/startup-researcher/assets/run-template/candidates.md)
- [Decision asset](.agents/skills/startup-researcher/assets/run-template/decision.md)
- [Queries asset](.agents/skills/startup-researcher/assets/run-template/queries.md)
- [Red-team asset](.agents/skills/startup-researcher/assets/run-template/red-team.md)
"@
        Write-FixtureFile -Base $temporaryBase -Relative 'INDEX.md' -Content $indexWithProfile
        $fixtureManifest = [ordered]@{
            schema_version = 1
            template_version = '1.2.0'
            portable_files = @(
                'INDEX.md',
                'PROJECT.md',
                'docs/source.md',
                'docs/target.md',
                'knowledge/candidates/TEMPLATE.md',
                'mastery/INTENTS.json',
                'mastery/local/INDEX.md',
                'mastery/researcher/profile.md'
            )
            portable_empty_directories = @('research/runs')
            source_only_paths = @()
            generated_forbidden_paths = @('.codex')
            generated_extension_zones = @('mastery/local')
            mastery_baseline = [ordered]@{
                bundle_version = '1.0.0'
                verified_at = '2026-07-30'
                review_due = '2099-12-31'
                files = @(
                    [ordered]@{
                        path = 'mastery/researcher/profile.md'
                        sha256 = ('0' * 64)
                    }
                )
            }
        }
        $manifestJsonSentinel = 'ManifestJsonSecretSentinel123456'
        $invalidManifestFixture = "{`"$manifestJsonSentinel`":]"
        $invalidManifestPath = Join-Path $temporaryBase '.template-manifest.json'
        Write-FixtureFile -Base $temporaryBase -Relative '.template-manifest.json' -Content $invalidManifestFixture
        Assert-SelfTest -Condition (
            [System.IO.File]::ReadAllText($invalidManifestPath, $utf8Strict) -ceq $invalidManifestFixture
        ) -Name 'invalid manifest fixture is written exactly before verification'
        $invalidManifestJson = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $invalidManifestJson -AllowedPatterns @(
            '^Root reachability: \.template-manifest\.json invalid JSON\.$',
            '^\.template-manifest\.json: invalid JSON\.$'
        ) -Name 'invalid manifest JSON reports generic parser errors'
        Assert-SelfTest -Condition (
            @($invalidManifestJson.Issues | Where-Object { $_ -match [regex]::Escape($manifestJsonSentinel) }).Count -eq 0
        ) -Name 'invalid manifest JSON diagnostics omit parser sentinel'

        Write-FixtureFile -Base $temporaryBase -Relative '.template-manifest.json' -Content ($fixtureManifest | ConvertTo-Json -Depth 8)
        $baselineDrift = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $baselineDrift -AllowedPatterns @(
            '^Mastery baseline drift: mastery/researcher/profile\.md '
        ) -Name 'mastery baseline hash drift'
        $fixtureManifest.mastery_baseline.files[0].sha256 = Get-Sha256 (Join-Path $temporaryBase 'mastery/researcher/profile.md')
        Write-FixtureFile -Base $temporaryBase -Relative '.template-manifest.json' -Content ($fixtureManifest | ConvertTo-Json -Depth 8)

        $templateProject = $project.Replace('repository_kind: generated-project', 'repository_kind: template-source').Replace('project_status: active', 'project_status: template').Replace('knowledge_capture_mode: report-only', 'knowledge_capture_mode: disabled')
        Write-FixtureFile -Base $temporaryBase -Relative 'PROJECT.md' -Content $templateProject
        Write-FixtureFile -Base $temporaryBase -Relative 'docs/decisions/source-only-adr.md' -Content "# Source-only ADR`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'plans/dynamic-plan.md' -Content "# Dynamic plan`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'TEMPLATE.md' -Content "# Template maintenance`n"
        $fixtureManifest.source_only_paths = @(
            'TEMPLATE.md',
            'docs/decisions/source-only-adr.md',
            'plans/dynamic-plan.md'
        )
        Write-FixtureFile -Base $temporaryBase -Relative '.template-manifest.json' -Content ($fixtureManifest | ConvertTo-Json -Depth 8)
        $sourceOnlyOrphan = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $sourceOnlyOrphan -AllowedPatterns @(
            '^Orphan canonical Markdown: docs/decisions/source-only-adr\.md$'
        ) -Name 'template maintenance root includes static source-only ADR but excludes dynamic plan'

        $templateWithEscapedSourceOnlyAdr = "# Template maintenance`n`n- \[Escaped source-only ADR](docs/decisions/source-only-adr.md)`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'TEMPLATE.md' -Content $templateWithEscapedSourceOnlyAdr
        $escapedSourceOnlyAdr = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $escapedSourceOnlyAdr -AllowedPatterns @(
            '^Orphan canonical Markdown: docs/decisions/source-only-adr\.md$'
        ) -Name 'odd-backslash escaped literal does not satisfy root reachability'

        $templateWithEvenBackslashSourceOnlyAdr = "# Template maintenance`n`n- \\[Even source-only ADR](docs/decisions/source-only-adr.md)`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'TEMPLATE.md' -Content $templateWithEvenBackslashSourceOnlyAdr
        $evenBackslashSourceOnlyAdr = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $evenBackslashSourceOnlyAdr -AllowedPatterns @() -Name 'even-backslash visible link satisfies maintenance-root reachability'

        $templateWithSourceOnlyAdr = "# Template maintenance`n`n- [Source-only ADR](docs/decisions/source-only-adr.md)`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'TEMPLATE.md' -Content $templateWithSourceOnlyAdr
        $linkedSourceOnlyAdr = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $linkedSourceOnlyAdr -AllowedPatterns @() -Name 'template source static source-only ADR is reachable from maintenance root'

        $indexWithoutProfile = $indexWithProfile -replace '(?m)^- \[Researcher profile\]\(mastery/researcher/profile\.md\)\r?\n?', ''
        $templateWithAdrAndProfile = "# Template maintenance`n`n- [Source-only ADR](docs/decisions/source-only-adr.md)`n- [Researcher profile](mastery/researcher/profile.md)`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'INDEX.md' -Content $indexWithoutProfile
        Write-FixtureFile -Base $temporaryBase -Relative 'TEMPLATE.md' -Content $templateWithAdrAndProfile
        $isolatedMaintenanceGraph = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $isolatedMaintenanceGraph -AllowedPatterns @(
            '^Orphan canonical Markdown: mastery/researcher/profile\.md$'
        ) -Name 'maintenance graph cannot satisfy portable root reachability'

        Remove-Item -LiteralPath (Join-Path $temporaryBase 'TEMPLATE.md') -Force
        $fixtureManifest.source_only_paths = @(
            'docs/decisions/source-only-adr.md',
            'plans/dynamic-plan.md'
        )
        Write-FixtureFile -Base $temporaryBase -Relative '.template-manifest.json' -Content ($fixtureManifest | ConvertTo-Json -Depth 8)
        Write-FixtureFile -Base $temporaryBase -Relative 'INDEX.md' -Content $indexWithProfile
        $missingMaintenanceRoot = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $missingMaintenanceRoot -AllowedPatterns @(
            '^Root reachability: source-only TEMPLATE\.md отсутствует как maintenance root\.$'
        ) -Name 'static source-only canonical requires exact maintenance root'

        Write-FixtureFile -Base $temporaryBase -Relative 'PROJECT.md' -Content $project
        Write-FixtureFile -Base $temporaryBase -Relative 'INDEX.md' -Content $indexWithProfile
        $fixtureManifest.source_only_paths = @()
        Write-FixtureFile -Base $temporaryBase -Relative '.template-manifest.json' -Content ($fixtureManifest | ConvertTo-Json -Depth 8)
        Remove-Item -LiteralPath (Join-Path $temporaryBase 'docs/decisions/source-only-adr.md') -Force
        Remove-Item -LiteralPath (Join-Path $temporaryBase 'plans/dynamic-plan.md') -Force

        $localMethodCandidateId = 'KC-20260730-120002-acde1234'
        $localMethodCandidateRelative = "knowledge/candidates/2026/$localMethodCandidateId.md"
        $localMethodCandidate = Get-FixtureCandidate `
            -Id $localMethodCandidateId `
            -State applied `
            -Type method `
            -Domain mastery `
            -ClaimKey method.validated-method `
            -TargetRef 'mastery/local/INDEX.md#зарегистрированные-расширения' `
            -SourceRef 'docs/source.md' `
            -CaptureBasis explicit-user-capture `
            -AuthorityRef user-request:selftest-local-method `
            -AppliedAt "'2026-07-30T12:20:00+04:00'" `
            -MethodKind checklist `
            -MethodSummary 'Повторяемый fixture-метод.' `
            -MethodAppliesTo planning
        Write-FixtureFile -Base $temporaryBase -Relative $localMethodCandidateRelative -Content $localMethodCandidate
        Write-FixtureFile -Base $temporaryBase -Relative 'mastery/local/INDEX.md' -Content @"
# Local

## Зарегистрированные расширения

[Candidate](../../$localMethodCandidateRelative)
"@
        $localExtension = @"
---
mastery_contract_version: 2
method_id: validated-method
method_kind: checklist
summary: Повторяемый fixture-метод.
owner_scope: project
applies_to:
  - planning
status: active
source_refs:
  - $localMethodCandidateRelative
verified_at: '2026-07-30'
review_due: '2099-12-31'
supersedes: null
---

# Local extension

## Provenance

Applied candidate указан во frontmatter source_refs.
"@
        Write-FixtureFile -Base $temporaryBase -Relative 'mastery/local/validated-method.md' -Content $localExtension
        $unregisteredLocal = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $unregisteredLocal -AllowedPatterns @(
            '^Незарегистрированное mastery/local расширение: mastery/local/validated-method\.md$',
            '^Orphan canonical Markdown: mastery/local/validated-method\.md$'
        ) -Name 'unregistered local mastery'
        Write-FixtureFile -Base $temporaryBase -Relative 'mastery/local/INDEX.md' -Content @"
# Local

## Зарегистрированные расширения

[Validated method](validated-method.md)
[Candidate](../../$localMethodCandidateRelative)
"@
        $registeredLocal = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $registeredLocal -AllowedPatterns @() -Name 'registered valid local mastery'
        Remove-Item -LiteralPath (Join-Path $temporaryBase 'mastery/local/validated-method.md') -Force
        Remove-Item -LiteralPath (Join-Path $temporaryBase $localMethodCandidateRelative) -Force
        Write-FixtureFile -Base $temporaryBase -Relative 'mastery/local/INDEX.md' -Content "# Local`n"
        Remove-Item -LiteralPath (Join-Path $temporaryBase '.template-manifest.json') -Force
        Remove-Item -LiteralPath (Join-Path $temporaryBase 'mastery/researcher/profile.md') -Force

        $duplicateId = 'KC-20260730-120001-cafebabe'
        $duplicateContent = (Get-FixtureCandidate -Id 'KC-20260730-120000-deadbeef').Replace('fixture-claim', 'fixture-claim-two')
        Write-FixtureFile -Base $temporaryBase -Relative "knowledge/candidates/2026/$duplicateId.md" -Content $duplicateContent
        $duplicate = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $duplicate -AllowedPatterns @(
            '^Duplicate candidate ID:',
            "id 'KC-20260730-120000-deadbeef' не совпадает с именем файла 'KC-20260730-120001-cafebabe'"
        ) -Name 'duplicate candidate ID'
        Remove-Item -LiteralPath (Join-Path $temporaryBase "knowledge/candidates/2026/$duplicateId.md") -Force

        $applied = Get-FixtureCandidate -State 'applied' -AuthorityRef 'user-request:selftest-current' -AppliedAt "'2026-07-30T12:10:00+04:00'"
        Write-FixtureFile -Base $temporaryBase -Relative 'knowledge/candidates/2026/KC-20260730-120000-deadbeef.md' -Content $applied
        $missingBacklinkPattern = '^knowledge/candidates/2026/KC-20260730-120000-deadbeef\.md: applied candidate не имеет Markdown-backlink из target_ref\.$'

        $blockquoteFencedBacklink = @'
# Target

## Knowledge

> ```md
> [Candidate](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)
> ````
'@
        Write-FixtureFile -Base $temporaryBase -Relative 'docs/target.md' -Content $blockquoteFencedBacklink
        $blockquoteFencedResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $blockquoteFencedResult -AllowedPatterns @(
            $missingBacklinkPattern
        ) -Name 'blockquote fenced link does not satisfy applied candidate backlink'

        $listFencedBacklink = @'
# Target

## Knowledge

- ~~~md
  [Candidate](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)
  ~~~~
'@
        Write-FixtureFile -Base $temporaryBase -Relative 'docs/target.md' -Content $listFencedBacklink
        $listFencedResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $listFencedResult -AllowedPatterns @(
            $missingBacklinkPattern
        ) -Name 'list fenced link does not satisfy applied candidate backlink'

        $combinedFencedBacklink = @'
# Target

## Knowledge

> 1. > ```md
>    > [Candidate](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)
>    > ````
'@
        Write-FixtureFile -Base $temporaryBase -Relative 'docs/target.md' -Content $combinedFencedBacklink
        $combinedFencedResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $combinedFencedResult -AllowedPatterns @(
            $missingBacklinkPattern
        ) -Name 'nested combined container fence masks applied candidate backlink'

        foreach ($visibleContainerBacklink in @(
            '> [Candidate](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)',
            '- [Candidate](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)',
            '> - [Candidate](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)'
        )) {
            Write-FixtureFile `
                -Base $temporaryBase `
                -Relative 'docs/target.md' `
                -Content "# Target`n`n## Knowledge`n`n$visibleContainerBacklink`n"
            $visibleContainerResult = Invoke-KnowledgeVerification $temporaryBase
            Assert-SelfTestIssueSet `
                -Result $visibleContainerResult `
                -AllowedPatterns @() `
                -Name "visible container backlink is recognized: $visibleContainerBacklink"
        }

        $escapedLiteralBacklink = @'
# Target

## Knowledge

\[Escaped backlink](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)
'@
        Write-FixtureFile -Base $temporaryBase -Relative 'docs/target.md' -Content $escapedLiteralBacklink
        $escapedLiteralResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $escapedLiteralResult -AllowedPatterns @(
            $missingBacklinkPattern
        ) -Name 'odd-backslash escaped literal does not satisfy applied candidate backlink'

        $evenBackslashBacklink = @'
# Target

## Knowledge

\\[Even-backslash backlink](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)
'@
        Write-FixtureFile -Base $temporaryBase -Relative 'docs/target.md' -Content $evenBackslashBacklink
        $evenBackslashResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $evenBackslashResult -AllowedPatterns @() -Name 'even-backslash visible link satisfies applied candidate backlink'

        $maskedBacklinks = @'
# Target

## Knowledge

```md
[Fenced](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)
```

    [Indented](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)

`[Code span](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)`

<!-- [Comment](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md) -->
'@
        Write-FixtureFile -Base $temporaryBase -Relative 'docs/target.md' -Content $maskedBacklinks
        $missingBacklink = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $missingBacklink -AllowedPatterns @(
            'applied candidate не имеет Markdown-backlink'
        ) -Name 'code and comment links do not satisfy applied candidate backlink'

        $realBacklink = $maskedBacklinks + "`n`n[Candidate](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'docs/target.md' -Content $realBacklink
        $validBacklink = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $validBacklink -AllowedPatterns @() -Name 'visible Markdown link satisfies applied candidate backlink'

        Write-FixtureFile -Base $temporaryBase -Relative 'knowledge/candidates/2026/KC-20260730-120000-deadbeef.md' -Content (Get-FixtureCandidate -SourceRef 'docs/missing.md')
        $brokenSource = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $brokenSource -AllowedPatterns @(
            "source_refs: отсутствующий файл: docs/missing\.md"
        ) -Name 'broken source reference'

        Write-FixtureFile -Base $temporaryBase -Relative 'knowledge/candidates/2026/KC-20260730-120000-deadbeef.md' -Content (Get-FixtureCandidate)
        Write-FixtureFile -Base $temporaryBase -Relative 'docs/target.md' -Content "# Target`n`n## Knowledge`n`n[Candidate](../knowledge/candidates/2026/KC-20260730-120000-deadbeef.md)`n"
        $corruptedEvidenceSentinel = 'CorruptedEvidenceSecretSentinel123456'
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content "{$corruptedEvidenceSentinel`n"
        $corrupted = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $corrupted -AllowedPatterns @(
            '^research/runs/2026-07-30-test/evidence\.jsonl:1: corrupted evidence JSONL\.$',
            'broken evidence ID в обязательной форме evidence:<id>'
        ) -Name 'corrupted evidence JSONL'
        Assert-SelfTest -Condition (
            @($corrupted.Issues | Where-Object { $_ -match [regex]::Escape($corruptedEvidenceSentinel) }).Count -eq 0
        ) -Name 'corrupted evidence parser diagnostics omit invalid line sentinel'

        $row1 = Get-FixtureEvidenceRow -EvidenceId 'EV-001' -OriginGroupId 'OG-001' -SourceUrl 'https://example.com/shared'
        $row1.original_source_url = 'https://example.com/original-one'
        $row1.dataset_origin = 'fixture-dataset-one'
        $row1.content_fingerprint = 'fixture-fingerprint-one'
        $row2 = Get-FixtureEvidenceRow -EvidenceId 'EV-002' -OriginGroupId 'OG-002' -SourceUrl 'https://example.com/source-two'
        $row2.original_source_url = 'https://example.com/shared'
        $row2.dataset_origin = 'fixture-dataset-two'
        $row2.content_fingerprint = 'fixture-fingerprint-two'
        $jsonl = ($row1 | ConvertTo-Json -Compress) + "`n" + ($row2 | ConvertTo-Json -Compress) + "`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content $jsonl
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/decision.md' -Content (Get-FixtureDecision -EvidenceRefs 'evidence:EV-001, evidence:EV-002')
        $duplicateOrigin = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $duplicateOrigin -AllowedPatterns @(
            "duplicate origin group assignment для 'url' identity"
        ) -Name 'cross-field source URL identity cannot split origin groups'

        $originUrlSentinel = 'EvidenceOriginSecretSentinel123456'
        $signedOriginUrl = "https://example.com/shared?auth=$originUrlSentinel"
        $signedOriginRow1 = Get-FixtureEvidenceRow -EvidenceId 'SIGNED-001' -OriginGroupId 'OG-SIGNED-001' -SourceUrl $signedOriginUrl
        $signedOriginRow2 = Get-FixtureEvidenceRow -EvidenceId 'SIGNED-002' -OriginGroupId 'OG-SIGNED-002' -SourceUrl $signedOriginUrl
        $signedOriginRow2.dataset_origin = 'fixture-signed-dataset-two'
        $signedOriginRow2.content_fingerprint = 'fixture-signed-fingerprint-two'
        $signedOriginJsonl = ($signedOriginRow1 | ConvertTo-Json -Compress) + "`n" +
            ($signedOriginRow2 | ConvertTo-Json -Compress) + "`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content $signedOriginJsonl
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/decision.md' -Content (Get-FixtureDecision -EvidenceRefs 'evidence:SIGNED-001, evidence:SIGNED-002')
        $signedOriginResult = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $signedOriginResult -AllowedPatterns @(
            'потенциально подписанный URL или credential в query',
            "evidence field '(?:source_url|original_source_url)'.*\(signed-url\)"
        ) -Name 'unsafe evidence URLs skip origin identity processing'
        Assert-SelfTest -Condition (
            @($signedOriginResult.Issues | Where-Object {
                $_ -match [regex]::Escape($originUrlSentinel) -or
                $_ -match 'duplicate origin group assignment'
            }).Count -eq 0
        ) -Name 'unsafe evidence URL diagnostics omit sentinel and origin identity'

        $caseRow1 = Get-FixtureEvidenceRow -EvidenceId 'CASE-001' -OriginGroupId 'OG-CASE-001' -SourceUrl 'https://EXAMPLE.com:443/File'
        $caseRow1.original_source_url = 'https://example.com/original-case-one'
        $caseRow1.dataset_origin = 'fixture-case-dataset-one'
        $caseRow1.content_fingerprint = 'fixture-case-fingerprint-one'
        $caseRow2 = Get-FixtureEvidenceRow -EvidenceId 'CASE-002' -OriginGroupId 'OG-CASE-002' -SourceUrl 'https://example.com/file'
        $caseRow2.original_source_url = 'https://example.com/original-case-two'
        $caseRow2.dataset_origin = 'fixture-case-dataset-two'
        $caseRow2.content_fingerprint = 'fixture-case-fingerprint-two'
        $caseJsonl = ($caseRow1 | ConvertTo-Json -Compress) + "`n" + ($caseRow2 | ConvertTo-Json -Compress) + "`n"
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content $caseJsonl
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/decision.md' -Content (Get-FixtureDecision -EvidenceRefs 'evidence:CASE-001, evidence:CASE-002')
        $caseSensitiveOrigins = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $caseSensitiveOrigins -AllowedPatterns @() -Name 'URL origin identity preserves path case while normalizing host and default port'

        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/evidence.jsonl' -Content (($httpsEvidenceRow | ConvertTo-Json -Compress) + "`n")
        Write-FixtureFile -Base $temporaryBase -Relative 'research/runs/2026-07-30-test/decision.md' -Content (Get-FixtureDecision)
        $badProject = $project.Replace('project_status: active', 'project_status: initialized').Replace('knowledge_capture_mode: report-only', 'knowledge_capture_mode: disabled')
        Write-FixtureFile -Base $temporaryBase -Relative 'PROJECT.md' -Content $badProject
        $invalidMode = Invoke-KnowledgeVerification $temporaryBase
        Assert-SelfTestIssueSet -Result $invalidMode -AllowedPatterns @(
            '^PROJECT\.md: несогласованная пара режима и capture mode\.$'
        ) -Name 'invalid project mode tuple'

        Write-Host 'SELFTEST PASS: все встроенные fixtures прошли.'
    }
    finally {
        if (Test-Path -LiteralPath $temporaryBase -PathType Container) {
            $resolvedTemporary = (Resolve-Path -LiteralPath $temporaryBase).Path
            if (-not $resolvedTemporary.StartsWith($expectedPrefix, $temporaryComparison)) {
                throw "Отказ от очистки небезопасного self-test path: $resolvedTemporary"
            }
            Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
        }
    }
}

if ($SelfTest) {
    Invoke-SelfTests
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
try {
    $result = Invoke-KnowledgeVerification $Root
}
catch {
    [Console]::Error.WriteLine(
        'FAIL: semantic knowledge gate заблокирован (invalid-verification-root); repository data скрыты.'
    )
    exit 1
}

if ($Report) {
    Write-Host 'KNOWLEDGE REPORT'
    foreach ($category in @('candidates', 'pending', 'dismissed', 'overdue', 'conflicts', 'mastery_drift')) {
        $values = @($result.Report.$category)
        Write-Host ("- {0}: {1}" -f $category, $values.Count)
        foreach ($value in $values) {
            Write-Host "  - $(Convert-ToSafeDiagnostic -Text ([string]$value))"
        }
    }
}

if ($result.Issues.Count -gt 0) {
    Write-Host "FAIL: semantic knowledge gate, проблем - $($result.Issues.Count)." -ForegroundColor Red
    foreach ($issue in $result.Issues) {
        Write-Host "- $(Convert-ToSafeDiagnostic -Text ([string]$issue))"
    }
    exit 1
}

Write-Host 'PASS: semantic knowledge gate.'
exit 0
