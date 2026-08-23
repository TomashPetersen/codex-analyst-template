[CmdletBinding()]
param(
    [string]$Root = '',

    [Parameter(Mandatory = $true)]
    [ValidateSet('fact', 'decision', 'constraint', 'preference', 'method')]
    [string]$Type,

    [Parameter(Mandatory = $true)]
    [ValidateSet('idea', 'product', 'business', 'architecture', 'codebase', 'operations', 'research', 'mastery', 'instructions')]
    [string]$Domain,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?$')]
    [string]$ClaimKey,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetRef,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$SourceRefs,

    [string[]]$ConflictRefs = @(),

    [Parameter(Mandatory = $true)]
    [ValidateSet('high', 'medium', 'low', 'unknown')]
    [string]$Confidence,

    [Parameter(Mandatory = $true)]
    [ValidateSet('repo-derived', 'explicit-user-capture', 'research-derived', 'plan-closeout')]
    [string]$CaptureBasis,

    [Parameter(Mandatory = $true)]
    [ValidateSet('public', 'internal')]
    [string]$DataClass,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Basis,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProposedChange,

    [string]$MethodKind = '',

    [string]$MethodSummary = '',

    [string[]]$MethodAppliesTo = @(),

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DuplicateCheck,

    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$ReviewDue = '',

    [ValidateNotNullOrEmpty()]
    [string]$AuthorityRef = 'policy:knowledge-contract-v1',

    [ValidateSet('automatic-capture', 'explicit-promotion')]
    [string]$WriteIntent = 'automatic-capture'
)

$ErrorActionPreference = 'Stop'
$safeGeneratorErrors = @(
    'blocked: repository-mode',
    'blocked: missing-git-baseline',
    'blocked: repository-preflight',
    'blocked: invalid-authority',
    'blocked: shared-owner',
    'blocked: candidate-lock-timeout',
    'blocked: claim-key-collision',
    'blocked: candidate-id-exhausted'
)
trap {
    $message = [string]$_.Exception.Message
    if ([string]::IsNullOrWhiteSpace([string]$MyInvocation.ScriptName)) {
        if ($message -cin $safeGeneratorErrors) {
            [Console]::Error.WriteLine("ERROR: $message")
        }
        else {
            [Console]::Error.WriteLine(
                'ERROR: создание knowledge candidate отклонено. Запусти scripts/verify-knowledge.ps1 для безопасного отчета.'
            )
        }
        exit 1
    }
    throw $message
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$maxEvidenceFileBytes = 16MB
$maxEvidenceLineChars = 262144
$maxEvidenceRecordsPerFile = 10000
$maxEvidenceLedgers = 1000
$maxEvidenceRecordsTotal = 100000
$maxEvidenceCorpusBytes = 128MB
$maxTextFileBytes = 4MB
$maxTextCorpusBytes = 128MB
$maxTextFiles = 10000
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

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Корень репозитория не найден: $Root"
}
$rootPath = (Resolve-Path -LiteralPath $Root).Path.TrimEnd([char[]]'\/')
$script:candidatePathComparison = if (
    [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )
) {
    [System.StringComparison]::OrdinalIgnoreCase
}
else {
    [System.StringComparison]::Ordinal
}

function Test-PathWithinRoot {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    return (
        $full.Equals($rootPath, $script:candidatePathComparison) -or
        $full.StartsWith(
            $rootPath + [System.IO.Path]::DirectorySeparatorChar,
            $script:candidatePathComparison
        )
    )
}

function Get-ReparsePointInPath {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    if (-not (Test-PathWithinRoot $full)) { return $null }

    $current = $rootPath
    if (Test-Path -LiteralPath $current) {
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $current
        }
    }

    $relative = if ($full.Equals($rootPath, $script:candidatePathComparison)) {
        ''
    }
    else {
        $full.Substring($rootPath.Length + 1)
    }
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
if ($null -eq $trustedPlatformModule -or
    -not [System.IO.Path]::GetFullPath([string]$trustedPlatformModule.Path).Equals(
        $trustedPlatformModulePath,
        $script:candidatePathComparison
    )) {
    throw $knowledgeModuleIntegrityError
}
$trustedPlatformCommands = @{}
foreach ($commandName in @(
    'Get-ModelProjectGitExecutable', 'Get-ModelProjectNullDevice', 'Invoke-ModelProjectProcess',
    'Enter-ModelProjectFileLock', 'Exit-ModelProjectFileLock', 'Get-ModelProjectPathComparison',
    'Get-ModelProjectPowerShellHost'
)) {
    $command = $trustedPlatformModule.ExportedCommands[$commandName]
    if ($null -eq $command -or $null -eq $command.Module -or
        -not [System.IO.Path]::GetFullPath([string]$command.Module.Path).Equals(
            $trustedPlatformModulePath,
            $script:candidatePathComparison
        )) {
        throw $knowledgeModuleIntegrityError
    }
    $trustedPlatformCommands[$commandName] = $command
}
$script:mppGetGitExecutable = $trustedPlatformCommands['Get-ModelProjectGitExecutable']
$script:mppGetNullDevice = $trustedPlatformCommands['Get-ModelProjectNullDevice']
$script:mppInvokeProcess = $trustedPlatformCommands['Invoke-ModelProjectProcess']
$script:mppEnterLock = $trustedPlatformCommands['Enter-ModelProjectFileLock']
$script:mppExitLock = $trustedPlatformCommands['Exit-ModelProjectFileLock']
$script:mppGetPathComparison = $trustedPlatformCommands['Get-ModelProjectPathComparison']
$script:mppGetPowerShellHost = $trustedPlatformCommands['Get-ModelProjectPowerShellHost']
$script:nullDevice = & $script:mppGetNullDevice
$script:candidatePathComparison = & $script:mppGetPathComparison -Path $rootPath
$pathComparer = if ($script:candidatePathComparison -eq [System.StringComparison]::OrdinalIgnoreCase) {
    [System.StringComparer]::OrdinalIgnoreCase
}
else {
    [System.StringComparer]::Ordinal
}
$script:textReadPaths = [System.Collections.Generic.HashSet[string]]::new($pathComparer)
if (-not [System.IO.Path]::GetDirectoryName($trustedKnowledgeLibRoot).Equals(
        $trustedKnowledgeScriptsRoot,
        $script:candidatePathComparison
    ) -or
    -not [System.IO.Path]::GetDirectoryName($trustedKnowledgeModulePath).Equals(
        $trustedKnowledgeLibRoot,
        $script:candidatePathComparison
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
        $script:candidatePathComparison
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
            $script:candidatePathComparison
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

function Read-BoundedUtf8Text {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Context,
        [long]$MaxBytes = 0
    )

    $full = [System.IO.Path]::GetFullPath($FilePath)
    if (-not (Test-PathWithinRoot $full)) {
        throw "$Context выходит за корень репозитория."
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "$Context не найден: $full"
    }
    $reparse = Get-ReparsePointInPath $full
    if ($null -ne $reparse) {
        throw "$Context проходит через reparse point: $reparse"
    }

    $file = Get-Item -LiteralPath $full -Force
    $effectiveLimit = if ($MaxBytes -gt 0) { [Math]::Min([long]$MaxBytes, [long]$maxTextFileBytes) } else { [long]$maxTextFileBytes }
    if ($file.Length -gt $effectiveLimit) {
        throw "$Context превышает file limit $effectiveLimit bytes."
    }
    if (-not $script:textReadPaths.Contains($full)) {
        if (($script:textReadPaths.Count + 1) -gt $maxTextFiles) {
            throw "Text corpus превышает file-count limit $maxTextFiles."
        }
        if (($script:textReadCorpusBytes + $file.Length) -gt $maxTextCorpusBytes) {
            throw "Text corpus превышает byte limit $maxTextCorpusBytes."
        }
        $script:textReadPaths.Add($full) | Out-Null
        $script:textReadCorpusBytes += $file.Length
    }

    $reparse = Get-ReparsePointInPath $full
    if ($null -ne $reparse) {
        throw "$Context проходит через reparse point непосредственно перед чтением: $reparse"
    }
    try {
        return [System.IO.File]::ReadAllText($full, $utf8Strict)
    }
    catch {
        throw "$Context не удалось прочитать как строгий UTF-8: $($_.Exception.Message)"
    }
}

function Convert-FrontMatterScalar {
    param([string]$Raw)

    $value = $Raw.Trim()
    if ($value -eq 'null') { return $null }
    if ($value -eq '[]') { return ,@() }
    if ($value.Length -ge 2 -and $value[0] -eq "'" -and $value[$value.Length - 1] -eq "'") {
        return $value.Substring(1, $value.Length - 2).Replace("''", "'")
    }
    if ($value.Length -ge 2 -and $value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') {
        try {
            return ($value | ConvertFrom-Json)
        }
        catch {
            throw 'Некорректная quoted-строка во frontmatter.'
        }
    }
    return $value
}

function Read-SimpleFrontMatter {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $text = Read-BoundedUtf8Text -FilePath $FilePath -Context $FilePath
    $lines = @($text -split "\r?\n")
    if ($lines.Count -lt 3 -or $lines[0].Trim() -cne '---') {
        throw "Отсутствует frontmatter: $FilePath"
    }

    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ceq '---') {
            $end = $i
            break
        }
    }
    if ($end -lt 0) { throw "Frontmatter не закрыт: $FilePath" }

    $data = @{}
    for ($i = 1; $i -lt $end; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^([a-z_][a-z0-9_]*):(?:\s*(.*))?$') {
            throw "Неподдерживаемая строка frontmatter в $FilePath`: $line"
        }
        $key = $Matches[1]
        $raw = $Matches[2]
        if ($data.ContainsKey($key)) { throw "Повтор поля '$key' в $FilePath" }
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $items = [System.Collections.Generic.List[string]]::new()
            while (($i + 1) -lt $end -and $lines[$i + 1] -match '^\s{2}-\s+(.+?)\s*$') {
                $i++
                $item = Convert-FrontMatterScalar $Matches[1]
                if ($null -eq $item -or $item -is [System.Array]) {
                    throw "Некорректный элемент списка '$key' в $FilePath"
                }
                $items.Add([string]$item)
            }
            $data[$key] = @($items)
        }
        else {
            $data[$key] = Convert-FrontMatterScalar $raw
        }
    }
    return $data
}

function ConvertFrom-SimpleFrontMatterText {
    param([Parameter(Mandatory = $true)][string]$Text)

    $lines = @($Text -split "\r?\n")
    if ($lines.Count -lt 3 -or $lines[0].Trim() -cne '---') {
        throw 'Rendered candidate не начинается с frontmatter.'
    }
    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -ceq '---') {
            $end = $i
            break
        }
    }
    if ($end -lt 0) { throw 'Rendered candidate имеет незакрытый frontmatter.' }

    $data = @{}
    for ($i = 1; $i -lt $end; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^([a-z_][a-z0-9_]*):(?:\s*(.*))?$') {
            throw "Rendered candidate содержит неподдерживаемую строку frontmatter: $line"
        }
        $key = $Matches[1]
        $raw = $Matches[2]
        if ($data.ContainsKey($key)) { throw "Rendered candidate повторяет поле '$key'." }
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $items = [System.Collections.Generic.List[string]]::new()
            while (($i + 1) -lt $end -and $lines[$i + 1] -match '^\s{2}-\s+(.+?)\s*$') {
                $i++
                $item = Convert-FrontMatterScalar $Matches[1]
                if ($null -eq $item -or $item -is [System.Array]) {
                    throw "Rendered candidate содержит некорректный элемент списка '$key'."
                }
                $items.Add([string]$item)
            }
            $data[$key] = @($items)
        }
        else {
            $data[$key] = Convert-FrontMatterScalar $raw
        }
    }
    $body = if (($end + 1) -lt $lines.Count) {
        ($lines[($end + 1)..($lines.Count - 1)] -join "`n")
    }
    else {
        ''
    }
    return [pscustomobject]@{ Data = $data; Body = $body }
}

function Test-ExactPathCase {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)

    $full = [System.IO.Path]::GetFullPath($AbsolutePath).TrimEnd([char[]]'\/')
    if (-not (Test-PathWithinRoot $full)) { return $false }
    $relative = if ($full.Equals($rootPath, $script:candidatePathComparison)) {
        ''
    }
    else {
        $full.Substring($rootPath.Length + 1)
    }
    $current = $rootPath
    foreach ($segment in (($relative -split '[\\/]') | Where-Object { $_ -ne '' })) {
        $match = Get-ChildItem -LiteralPath $current -Force |
            Where-Object { $_.Name -ceq $segment } |
            Select-Object -First 1
        if ($null -eq $match) { return $false }
        $current = $match.FullName
    }
    return $true
}

function Convert-ToAnchor {
    param([Parameter(Mandatory = $true)][string]$Heading)

    $value = $Heading.ToLowerInvariant()
    $value = $value -replace '[`*_~]', ''
    $value = $value -replace '<[^>]+>', ''
    $value = $value -replace '[^\p{L}\p{Nd}\s_-]', ''
    return ($value.Trim() -replace '\s+', '-')
}

function Test-MarkdownAnchor {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$Anchor
    )

    if ([string]::IsNullOrWhiteSpace($Anchor)) { return $true }
    if ([System.IO.Path]::GetExtension($FilePath) -ine '.md') { return $false }
    $wanted = Convert-ToAnchor ([System.Uri]::UnescapeDataString($Anchor))
    $text = Read-BoundedUtf8Text -FilePath $FilePath -Context "Markdown anchor source '$FilePath'"
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
    $visible = [regex]::Replace($visible, '(?s)<!--.*?(?:-->|$)', $maskPreservingLines)
    return [regex]::Replace(
        $visible,
        '(?s)(?<ticks>`+)(?!`).*?(?<!`)\k<ticks>(?!`)',
        $maskPreservingLines
    )
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

function Get-UnsafeMarkdownUriKinds {
    param([Parameter(Mandatory = $true)][string]$Text)

    $scanText = Get-CommonMarkVisibleText $Text
    $destinations = [System.Collections.Generic.List[string]]::new()
    $findings = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($link in (Get-InlineMarkdownLinks -Text $scanText)) {
        if (-not $link.Valid) {
            $findings.Add('неоднозначную Markdown-ссылку') | Out-Null
            continue
        }
        $destinations.Add($link.Target) | Out-Null
    }
    $definitionPattern = '(?m)^ {0,3}\[(?:\\[^\r\n]|[^\]\\\r\n])+\]:'
    foreach ($match in [regex]::Matches($scanText, $definitionPattern)) {
        if (& $script:mpkTestMarkdownEscaped -Text $scanText -Index $match.Index) { continue }
        $destination = Get-MarkdownDestination -Content $scanText -StartIndex ($match.Index + $match.Length)
        if ($null -eq $destination -or -not $destination.Balanced) {
            $findings.Add('неоднозначную Markdown-ссылку') | Out-Null
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
            $findings.Add('protocol-relative Markdown URI') | Out-Null
        }
        elseif ($destination -match '^(?i)(?<scheme>[A-Za-z][A-Za-z0-9+.-]*):' -and
            $Matches['scheme'] -ine 'https') {
            $findings.Add('опасный Markdown URI') | Out-Null
        }
    }
    return @($findings)
}

function Test-UnsafeMarkdownStructure {
    param([Parameter(Mandatory = $true)][string]$Text)

    if ($Text -match '(?m)^ {0,3}#{1,6}[ \t]+\S') { return 'CommonMark ATX heading' }
    if ($Text -match '(?m)^ {0,3}(?:=+|-+)[ \t]*$') { return 'Setext heading' }
    if ($Text -match '(?m)^ {0,3}(?:\*(?:[ \t]*\*){2,}|_(?:[ \t]*_){2,}|-(?:[ \t]*-){2,})[ \t]*$') {
        return 'horizontal rule'
    }
    return $null
}

function Assert-SafeReference {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Field,
        [switch]$AllowExternal,
        [switch]$AllowLogical,
        [switch]$MustExist
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -ne $Value.Trim() -or $Value -match "[`r`n`0]") {
        throw "$Field содержит пустое значение, перенос строки или внешние пробелы."
    }

    if ($Value -match '^(?i:https://)') {
        if (-not $AllowExternal) { throw "$Field не допускает внешний URL." }
        switch (& $script:mpkGetHttpsUrlSafetyFinding -Value $Value) {
            'invalid-https-url' { throw "$Field содержит некорректный HTTPS URL." }
            'https-url-userinfo' { throw "$Field содержит HTTPS URL с запрещенным userinfo." }
            'signed-url' { throw "$Field содержит потенциально подписанный URL или credential в query." }
        }
        return
    }
    if ($Value -cmatch '^logical:shared-mastery/') {
        throw 'blocked: shared-owner'
    }
    if ($AllowLogical -and (
        $Value -match '^(?:urn|logical|doi|isbn|source|task|user-request|evidence):[A-Za-z0-9][A-Za-z0-9._:/-]*$' -or
        $Value -match '^KC-\d{8}-\d{6}-[0-9a-f]{8}$'
    )) {
        return
    }
    if ($Value -match '^(?i:[A-Za-z][A-Za-z0-9+.-]*:|//)') {
        throw "$Field содержит неподдерживаемую внешнюю ссылку или URI scheme."
    }

    if ($Value.Contains('\')) { throw "$Field должен использовать '/' вместо '\'." }
    if ($Value -match '^(?:[A-Za-z]:|/|~[/\\]|file:|\\\\)' -or [System.IO.Path]::IsPathRooted($Value)) {
        throw "$Field содержит абсолютный локальный путь."
    }
    if ($Value.Contains('?') -or ([regex]::Matches($Value, '#').Count -gt 1)) {
        throw "$Field не допускает query-строку или несколько fragments."
    }

    $parts = $Value.Split('#', 2)
    $pathPart = $parts[0]
    $fragment = if ($parts.Count -eq 2) { $parts[1] } else { '' }
    try {
        $decodedPath = [System.Uri]::UnescapeDataString($pathPart)
    }
    catch {
        throw "$Field содержит некорректное percent-encoding."
    }
    if ([string]::IsNullOrWhiteSpace($decodedPath) -or
        $decodedPath -match '(^|/)\.{1,2}(/|$)' -or
        $decodedPath.Contains(':') -or
        $decodedPath.Contains('//')) {
        throw "$Field содержит traversal или недопустимый относительный путь."
    }

    try {
        $absolute = [System.IO.Path]::GetFullPath((Join-Path $rootPath $decodedPath))
    }
    catch {
        throw "$Field содержит путь, который невозможно нормализовать."
    }
    if (-not (Test-PathWithinRoot $absolute)) { throw "$Field выходит за корень репозитория." }
    $reparse = Get-ReparsePointInPath $absolute
    if ($null -ne $reparse) { throw "$Field проходит через reparse point." }
    if ($MustExist) {
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
            throw "$Field ссылается на отсутствующий файл: $decodedPath"
        }
        if (-not (Test-ExactPathCase $absolute)) {
            throw "$Field содержит неверный регистр пути: $decodedPath"
        }
        if (-not [string]::IsNullOrWhiteSpace($fragment) -and -not (Test-MarkdownAnchor -FilePath $absolute -Anchor $fragment)) {
            throw "$Field ссылается на отсутствующий Markdown anchor в $decodedPath."
        }
    }
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Value)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $utf8Strict.GetBytes($Value)
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-ClaimLockResourceKey {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$NormalizedClaimKey
    )

    $null = $RepositoryRoot
    return 'candidate-' + (Get-Sha256Hex $NormalizedClaimKey)
}

function Get-TrustedGitExecutable {
    try { return (& $script:mppGetGitExecutable -ControlledRoots @($rootPath)) }
    catch { throw 'blocked: missing-git-baseline' }
}

function Get-TrustedGitMetadata {
    $gitMetadataPath = Join-Path $rootPath '.git'
    if (-not (Test-ExactPathCase $gitMetadataPath) -or
        $null -ne (Get-ReparsePointInFullChain $gitMetadataPath)) {
        return $null
    }

    if (Test-Path -LiteralPath $gitMetadataPath -PathType Container) {
        return [pscustomobject]@{
            GitDirectory = [System.IO.Path]::GetFullPath($gitMetadataPath).TrimEnd([char[]]'\/')
            WorkTree = $rootPath
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
            [System.IO.Path]::GetFullPath((Join-Path $rootPath $gitDirectoryValue))
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
                $script:candidatePathComparison
            )) {
            return $null
        }

        return [pscustomobject]@{
            GitDirectory = $gitDirectoryPath
            WorkTree = $rootPath
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
    $result = & $script:mppInvokeProcess `
        -Executable $GitPath `
        -Arguments $gitArguments `
        -GitEnvironment `
        -MaxLines $MaxLines `
        -MaxCharacters $MaxCharacters
    return [pscustomobject]@{
        ExitCode = $result.ExitCode
        Lines = @($result.StdoutLines)
        LimitExceeded = $result.LimitExceeded
    }
}

function Assert-TrustedGitHead {
    $metadata = Get-TrustedGitMetadata
    if ($null -eq $metadata) {
        throw 'blocked: missing-git-baseline'
    }

    $gitPath = Get-TrustedGitExecutable
    $result = Invoke-TrustedGitCommand `
        -GitPath $gitPath `
        -Metadata $metadata `
        -Arguments @('rev-parse', '--verify', '--quiet', 'HEAD^{commit}') `
        -MaxLines 1 `
        -MaxCharacters 128
    if ($result.LimitExceeded -or
        $result.ExitCode -ne 0 -or
        $result.Lines.Count -ne 1 -or
        $result.Lines[0] -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        throw 'blocked: missing-git-baseline'
    }
}

function Assert-AuthorityContract {
    if ($WriteIntent -ceq 'automatic-capture') {
        if ($AuthorityRef -cne 'policy:knowledge-contract-v1' -or
            $CaptureBasis -ceq 'explicit-user-capture') {
            throw 'blocked: invalid-authority'
        }
        return
    }

    if ($AuthorityRef -cmatch '^user-request:[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        return
    }
    if ($AuthorityRef -cnotmatch '^docs/decisions/(?!README\.md$|TEMPLATE\.md$)[A-Za-z0-9][A-Za-z0-9._/-]*\.md$') {
        throw 'blocked: invalid-authority'
    }

    try {
        Assert-SafeReference -Value $AuthorityRef -Field 'AuthorityRef' -MustExist
        $authorityPath = Join-Path $rootPath $AuthorityRef
        $authorityData = Read-SimpleFrontMatter $authorityPath
        if (-not $authorityData.ContainsKey('artifact_kind') -or
            [string]$authorityData.artifact_kind -cne 'decision' -or
            -not $authorityData.ContainsKey('status') -or
            [string]$authorityData.status -cne 'accepted') {
            throw 'blocked: invalid-authority'
        }
    }
    catch {
        throw 'blocked: invalid-authority'
    }
}

function Get-CandidateBodyText {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $text = Read-BoundedUtf8Text -FilePath $FilePath -Context 'existing candidate'
    $match = [regex]::Match(
        $text,
        '(?ms)\A---[ \t]*\r?\n.*?^---[ \t]*\r?\n(?<body>.*)\z'
    )
    if (-not $match.Success) { return $null }
    return $match.Groups['body'].Value
}

function Get-CandidateSectionText {
    param(
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $true)][string]$Heading
    )

    $match = [regex]::Match(
        $Body,
        "(?ms)^##[ \t]+$([regex]::Escape($Heading))[ \t]*\r?\n(?<value>.*?)(?=^##[ \t]+|\z)"
    )
    if (-not $match.Success) { return $null }
    return $match.Groups['value'].Value.Trim()
}

function Test-ExistingCandidateRequestMatch {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)]$Data
    )

    foreach ($field in $candidateFields) {
        if (-not $Data.ContainsKey($field)) { return $false }
    }
    foreach ($field in @($Data.Keys)) {
        if ($field -cnotin $candidateAllowedFields) { return $false }
    }
    foreach ($field in @($candidateScalarFields + $candidateOptionalMethodScalarFields)) {
        if (-not $Data.ContainsKey($field)) {
            if ($Type -ceq 'method') { return $false }
            continue
        }
        $allowNull = $field -cin $candidateNullableScalarFields
        if ($field -cin $candidateOptionalMethodScalarFields) { $allowNull = $true }
        if (-not (& $script:mpkTestFrontMatterScalarValue -Value $Data[$field] -AllowNull:$allowNull)) {
            return $false
        }
    }

    $candidateId = [string]$Data.id
    if ($candidateId -cnotmatch '^KC-\d{8}-\d{6}-[0-9a-f]{8}$' -or
        [System.IO.Path]::GetFileNameWithoutExtension($FilePath) -cne $candidateId -or
        -not (Test-ExactPathCase $FilePath) -or
        $null -ne (Get-ReparsePointInPath $FilePath)) {
        return $false
    }

    $expectedReviewDue = if ([string]::IsNullOrWhiteSpace($ReviewDue)) { $null } else { $ReviewDue }
    $expectedScalars = @{
        type = $Type
        owner_scope = 'project'
        domain = $Domain
        claim_key = $ClaimKey
        target_ref = $TargetRef
        confidence = $Confidence
        capture_basis = $CaptureBasis
        data_class = $DataClass
        review_due = $expectedReviewDue
        method_kind = $(if ($Type -ceq 'method') { $MethodKind } else { $null })
        method_summary = $(if ($Type -ceq 'method') { $MethodSummary } else { $null })
    }
    foreach ($entry in $expectedScalars.GetEnumerator()) {
        if (-not $Data.ContainsKey($entry.Key) -and $Type -cne 'method' -and
            $entry.Key -cin $candidateOptionalMethodScalarFields) {
            continue
        }
        if ($null -eq $entry.Value) {
            if ($null -ne $Data[$entry.Key]) { return $false }
        }
        elseif ([string]$Data[$entry.Key] -cne [string]$entry.Value) {
            return $false
        }
    }

    foreach ($arrayContract in @(
        [pscustomobject]@{ Name = 'source_refs'; Expected = @($SourceRefs | ForEach-Object { [string]$_ }) },
        [pscustomobject]@{ Name = 'conflict_refs'; Expected = @($ConflictRefs | ForEach-Object { [string]$_ }) },
        [pscustomobject]@{ Name = 'method_applies_to'; Expected = @($MethodAppliesTo | ForEach-Object { [string]$_ }) }
    )) {
        if (-not $Data.ContainsKey($arrayContract.Name) -and $Type -cne 'method' -and
            $arrayContract.Name -ceq 'method_applies_to') {
            continue
        }
        $actual = $Data[$arrayContract.Name]
        if (-not ($actual -is [System.Array])) { return $false }
        $actualValues = @($actual)
        $expectedValues = @($arrayContract.Expected)
        if ($actualValues.Count -ne $expectedValues.Count) { return $false }
        for ($i = 0; $i -lt $expectedValues.Count; $i++) {
            if ([string]$actualValues[$i] -cne [string]$expectedValues[$i]) { return $false }
        }
    }

    $state = [string]$Data.state
    if ($state -cnotin @('ready', 'applied', 'dismissed')) { return $false }
    if ($state -ceq 'ready' -and [string]$Data.authority_ref -cne $AuthorityRef) {
        return $false
    }
    $body = Get-CandidateBodyText $FilePath
    if ($null -eq $body) { return $false }
    $titleMatch = [regex]::Match($body, '(?m)^#[ \t]+(?<value>[^\r\n]+?)[ \t]*$')
    if (-not $titleMatch.Success -or
        -not $titleMatch.Groups['value'].Value.Trim().Equals($Title.Trim(), [System.StringComparison]::Ordinal)) {
        return $false
    }

    $expectedSections = @(
        @('Основание', $Basis.Trim()),
        @('Предлагаемое изменение', $ProposedChange.Trim()),
        @('Проверка дублей и противоречий', $DuplicateCheck.Trim())
    )
    foreach ($section in $expectedSections) {
        $actual = Get-CandidateSectionText -Body $body -Heading ([string]$section[0])
        if ($null -eq $actual -or
            -not $actual.Equals([string]$section[1], [System.StringComparison]::Ordinal)) {
            return $false
        }
    }
    return $true
}

function Complete-ExistingCandidateRequest {
    param([Parameter(Mandatory = $true)]$ExistingCandidate)

    if (-not (Test-ExistingCandidateRequestMatch `
        -FilePath $ExistingCandidate.File `
        -Data $ExistingCandidate.Data)) {
        throw 'blocked: claim-key-collision'
    }
    $existingId = [string]$ExistingCandidate.Data.id
    Write-Host "EXISTING [$existingId]: $($ExistingCandidate.Relative)"
    return [pscustomobject]@{
        id = $existingId
        state = 'existing'
        candidate_state = [string]$ExistingCandidate.Data.state
        path = $ExistingCandidate.Relative
        claim_key = $ClaimKey
    }
}

function Assert-SafeCandidateText {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Field,
        [switch]$SingleLine,
        [switch]$AllowDocumentStructure
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { throw "$Field не заполнено." }
    if ($SingleLine -and $Value -match "[`r`n]") { throw "$Field должно быть одной строкой." }
    if ($Value.IndexOf([char]0) -ge 0) { throw "$Field содержит NUL." }
    try {
        $valueBytes = $utf8Strict.GetByteCount($Value)
    }
    catch {
        throw "$Field невозможно представить как строгий UTF-8."
    }
    if ($valueBytes -gt $maxTextFileBytes) {
        throw "$Field превышает UTF-8 byte limit $maxTextFileBytes."
    }

    $sensitiveFindings = @(& $script:mpkGetSensitiveTextFindings -Text $Value)
    if ($sensitiveFindings.Count -gt 0) {
        switch ([string]$sensitiveFindings[0]) {
            'invalid-https-url' { throw "$Field содержит некорректный HTTPS URL." }
            'https-url-userinfo' { throw "$Field содержит HTTPS URL с запрещенным userinfo." }
            'signed-url' { throw "$Field содержит потенциально подписанный URL или credential в query." }
            default {
                throw "$Field содержит потенциально небезопасный материал по эвристическому сигналу ($($sensitiveFindings[0]))."
            }
        }
    }
    if ($Value -match '(?:^|[\s(\x27\x22])\.\.[\\/]') {
        throw "$Field содержит потенциально небезопасный материал по эвристическому сигналу (path-traversal)."
    }

    if ($Value -match '(?is)<!--.*?(?:-->|$)|<\s*/?\s*[A-Za-z][A-Za-z0-9-]*(?:[ \t\r\n]+[^<>]*?)?\s*/?\s*>|<![A-Za-z][^<>]*>|<\?[^<>]*\?>') {
        throw "$Field не допускает raw HTML tags или comments."
    }
    $unsafeMarkdownUris = @(Get-UnsafeMarkdownUriKinds $Value)
    if ($unsafeMarkdownUris.Count -gt 0) {
        throw "$Field содержит $($unsafeMarkdownUris[0])."
    }
    if (-not $SingleLine -and -not $AllowDocumentStructure) {
        $unsafeStructure = Test-UnsafeMarkdownStructure $Value
        if ($null -ne $unsafeStructure) {
            throw "$Field не допускает $unsafeStructure."
        }
    }
}

function Convert-ToYamlScalar {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-AllowedMasteryIntentIds {
    $catalogPath = Join-Path $rootPath 'mastery/INTENTS.json'
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf) -or
        -not (Test-ExactPathCase $catalogPath) -or
        $null -ne (Get-ReparsePointInPath $catalogPath)) {
        throw 'mastery/INTENTS.json отсутствует или не прошел path integrity check.'
    }
    $catalogText = Read-BoundedUtf8Text -FilePath $catalogPath -Context 'mastery intent catalog'
    try {
        $catalog = $catalogText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'mastery/INTENTS.json содержит некорректный JSON.'
    }
    if ($null -eq $catalog -or $catalog -is [System.Array] -or
        ((@($catalog.PSObject.Properties.Name | Sort-Object) -join ',') -cne 'intents,schema_version') -or
        [string]$catalog.schema_version -cne '1' -or
        -not ($catalog.intents -is [System.Array]) -or
        @($catalog.intents).Count -eq 0) {
        throw 'mastery/INTENTS.json не соответствует catalog contract v1.'
    }
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($intent in @($catalog.intents)) {
        if ($null -eq $intent -or $intent -is [System.Array] -or
            ((@($intent.PSObject.Properties.Name | Sort-Object) -join ',') -cne 'description,id,label')) {
            throw 'mastery/INTENTS.json содержит intent с неизвестной схемой.'
        }
        $intentId = [string]$intent.id
        if ($intentId -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$' -or -not $ids.Add($intentId)) {
            throw 'mastery/INTENTS.json содержит invalid или duplicate intent id.'
        }
    }
    return $ids
}

function Assert-RenderedCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$ExpectedId,
        [Parameter(Mandatory = $true)][string]$ExpectedType,
        [Parameter(Mandatory = $true)][string]$ExpectedDomain,
        [Parameter(Mandatory = $true)][string]$ExpectedClaimKey,
        [Parameter(Mandatory = $true)][string]$ExpectedTargetRef,
        [Parameter(Mandatory = $true)][string[]]$ExpectedSourceRefs,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ExpectedConflictRefs,
        [Parameter(Mandatory = $true)][string]$ExpectedConfidence,
        [Parameter(Mandatory = $true)][string]$ExpectedCaptureBasis,
        [Parameter(Mandatory = $true)][string]$ExpectedDataClass,
        [AllowNull()][string]$ExpectedMethodKind,
        [AllowNull()][string]$ExpectedMethodSummary,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ExpectedMethodAppliesTo,
        [Parameter(Mandatory = $true)][string]$ExpectedCreatedAt,
        [AllowNull()][string]$ExpectedReviewDue,
        [Parameter(Mandatory = $true)][string]$ExpectedAuthorityRef,
        [Parameter(Mandatory = $true)][string]$ExpectedTitle
    )

    $document = ConvertFrom-SimpleFrontMatterText $Content
    $data = $document.Data
    foreach ($field in $candidateFields) {
        if (-not $data.ContainsKey($field)) {
            throw "Rendered candidate не содержит обязательное поле '$field'."
        }
    }
    foreach ($field in $candidateOptionalMethodFields) {
        if (-not $data.ContainsKey($field)) {
            throw "Rendered candidate не содержит method-поле '$field'."
        }
    }
    foreach ($field in @($data.Keys)) {
        if ($field -cnotin $candidateAllowedFields) {
            throw "Rendered candidate содержит неизвестное поле '$field'."
        }
    }
    foreach ($field in @($candidateScalarFields + $candidateOptionalMethodScalarFields)) {
        if (-not $data.ContainsKey($field)) { continue }
        $allowNull = $field -cin $candidateNullableScalarFields
        if ($field -cin $candidateOptionalMethodScalarFields) { $allowNull = $true }
        if (-not (& $script:mpkTestFrontMatterScalarValue -Value $data[$field] -AllowNull:$allowNull)) {
            $expectedKind = if ($allowNull) { 'YAML scalar или null' } else { 'YAML scalar' }
            throw "Rendered candidate field '$field' должен быть $expectedKind."
        }
    }

    $expectedScalars = @{
        id = $ExpectedId
        state = 'ready'
        type = $ExpectedType
        owner_scope = 'project'
        domain = $ExpectedDomain
        claim_key = $ExpectedClaimKey
        target_ref = $ExpectedTargetRef
        confidence = $ExpectedConfidence
        capture_basis = $ExpectedCaptureBasis
        data_class = $ExpectedDataClass
        method_kind = $ExpectedMethodKind
        method_summary = $ExpectedMethodSummary
        created_at = $ExpectedCreatedAt
        review_due = $ExpectedReviewDue
        authority_ref = $ExpectedAuthorityRef
        applied_at = $null
        dismiss_reason = $null
        supersedes = $null
    }
    foreach ($entry in $expectedScalars.GetEnumerator()) {
        $actual = $data[$entry.Key]
        if ($null -eq $entry.Value) {
            if ($null -ne $actual) {
                throw "Rendered candidate изменил nullable field '$($entry.Key)'."
            }
        }
        elseif ([string]$actual -cne [string]$entry.Value) {
            throw "Rendered candidate изменил field '$($entry.Key)'."
        }
    }

    foreach ($arrayContract in @(
        [pscustomobject]@{ Name = 'source_refs'; Expected = @($ExpectedSourceRefs) },
        [pscustomobject]@{ Name = 'conflict_refs'; Expected = @($ExpectedConflictRefs) },
        [pscustomobject]@{ Name = 'method_applies_to'; Expected = @($ExpectedMethodAppliesTo) }
    )) {
        $actual = $data[$arrayContract.Name]
        if (-not ($actual -is [System.Array])) {
            throw "Rendered candidate field '$($arrayContract.Name)' не является списком."
        }
        $actualValues = @($actual)
        $expectedValues = @($arrayContract.Expected)
        if ($actualValues.Count -ne $expectedValues.Count) {
            throw "Rendered candidate изменил размер списка '$($arrayContract.Name)'."
        }
        for ($i = 0; $i -lt $expectedValues.Count; $i++) {
            if ([string]$actualValues[$i] -cne [string]$expectedValues[$i]) {
                throw "Rendered candidate изменил элемент списка '$($arrayContract.Name)'."
            }
        }
    }

    $body = [string]$document.Body
    if ($body -match '(?m)^\s*---\s*$') {
        throw 'Rendered candidate содержит внедренную frontmatter-границу в body.'
    }
    if ($body -match '(?m)^ {0,3}(?:=+|-+)[ \t]*$' -or
        $body -match '(?m)^ {0,3}(?:\*(?:[ \t]*\*){2,}|_(?:[ \t]*_){2,}|-(?:[ \t]*-){2,})[ \t]*$') {
        throw 'Rendered candidate содержит Setext heading или внедренный horizontal rule.'
    }
    $headingLines = @($body -split "\r?\n" | Where-Object { $_ -match '^ {0,3}#{1,6}[ \t]+' })
    $expectedHeadingLines = @(
        "# $ExpectedTitle",
        '## Основание',
        '## Предлагаемое изменение',
        '## Проверка дублей и противоречий',
        '## Обоснование lifecycle'
    )
    if ($headingLines.Count -ne $expectedHeadingLines.Count) {
        throw 'Rendered candidate содержит отсутствующий или внедренный Markdown heading.'
    }
    for ($i = 0; $i -lt $expectedHeadingLines.Count; $i++) {
        if ($headingLines[$i].TrimEnd() -cne $expectedHeadingLines[$i]) {
            throw 'Rendered candidate изменил порядок или значение Markdown headings.'
        }
    }
    foreach ($heading in $expectedHeadingLines[1..($expectedHeadingLines.Count - 1)]) {
        $escaped = [regex]::Escape($heading)
        if ($body -notmatch "(?ms)^$escaped\s*\r?\n\s*(?<content>\S.+?)(?=^##\s|\z)") {
            throw "Rendered candidate содержит пустой section '$heading'."
        }
    }
}

function Assert-TrustedKnowledgePreflight {
    $trustedScriptRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
    $verifierPath = [System.IO.Path]::GetFullPath((Join-Path $trustedScriptRoot 'verify-knowledge.ps1'))
    if (-not (Split-Path -Parent $verifierPath).Equals(
        $trustedScriptRoot,
        $script:candidatePathComparison
    )) {
        throw 'Trusted knowledge verifier вышел за каталог scripts.'
    }
    if (-not (Test-Path -LiteralPath $verifierPath -PathType Leaf)) {
        throw 'Trusted knowledge verifier не найден.'
    }
    $verifierItem = Get-Item -LiteralPath $verifierPath -Force
    if ($verifierItem.Name -cne 'verify-knowledge.ps1' -or
        $null -ne (Get-ReparsePointInFullChain $verifierPath)) {
        throw 'Trusted knowledge verifier не прошел path integrity check.'
    }

    try { $hostPath = & $script:mppGetPowerShellHost -ControlledRoots @($rootPath) }
    catch { throw 'Exact PowerShell host path не прошел integrity check.' }

    $preflight = & $script:mppInvokeProcess `
        -Executable $hostPath `
        -Arguments @(
            '-NoLogo', '-NoProfile', '-NonInteractive',
            '-File', $verifierPath,
            '-Root', $rootPath
        ) `
        -WorkingDirectory $rootPath `
        -MaxLines 5000 `
        -MaxCharacters 8MB
    if ($preflight.LimitExceeded -or $preflight.ExitCode -ne 0) {
        throw 'blocked: repository-preflight'
    }
}

$rootReparse = Get-ReparsePointInFullChain $rootPath
if ($null -ne $rootReparse) {
    throw "Корень репозитория или его существующий ancestor является reparse point: $rootReparse"
}

$ClaimKey = $ClaimKey.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()

function Invoke-CandidateCreationLocked {
    $lockedRootReparse = Get-ReparsePointInFullChain $rootPath
    if ($null -ne $lockedRootReparse) {
        throw 'Корень репозитория не прошел повторную path integrity check.'
    }

$projectPath = Join-Path $rootPath 'PROJECT.md'
if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
    throw 'PROJECT.md не найден.'
}
$project = Read-SimpleFrontMatter $projectPath
foreach ($field in $projectScalarFields) {
    if (-not $project.ContainsKey($field)) {
        throw "PROJECT.md: отсутствует обязательное поле '$field'."
    }
        if (-not (& $script:mpkTestFrontMatterScalarValue -Value $project[$field])) {
        throw "PROJECT.md: поле '$field' должно быть YAML scalar."
    }
    if ([string]::IsNullOrWhiteSpace([string]$project[$field])) {
        throw "PROJECT.md: отсутствует обязательное поле '$field'."
    }
}
if ([string]$project.repository_kind -cne 'generated-project' -or
    [string]$project.knowledge_contract_version -cne '1') {
    throw 'blocked: repository-mode'
}
$projectStatus = [string]$project.project_status
$captureMode = [string]$project.knowledge_capture_mode
if ($WriteIntent -ceq 'automatic-capture') {
    if ($projectStatus -cne 'active' -or $captureMode -cne 'safe-local') {
        throw 'blocked: repository-mode'
    }
}
else {
    $explicitTuple = "$projectStatus|$captureMode"
    if ($explicitTuple -cnotin @(
        'initialized|report-only',
        'active|report-only',
        'active|safe-local'
    )) {
        throw 'blocked: repository-mode'
    }
}
if ($captureMode -ceq 'safe-local') {
    Assert-TrustedGitHead
}
if ([string]$project.project_id -match '\{\{.+\}\}') {
    throw 'PROJECT.md не инициализирован: project_id содержит placeholder.'
}

Assert-AuthorityContract

Assert-SafeCandidateText -Value $ClaimKey -Field 'ClaimKey' -SingleLine
Assert-SafeCandidateText -Value $Title -Field 'Title' -SingleLine
Assert-SafeCandidateText -Value $Basis -Field 'Basis'
Assert-SafeCandidateText -Value $ProposedChange -Field 'ProposedChange'
Assert-SafeCandidateText -Value $DuplicateCheck -Field 'DuplicateCheck'
$MethodKind = $MethodKind.Trim()
$MethodSummary = $MethodSummary.Trim()
$MethodAppliesTo = @($MethodAppliesTo | ForEach-Object { ([string]$_).Trim() })
if ($Type -ceq 'method') {
    if ($MethodKind -cnotin @('heuristic', 'checklist', 'workflow', 'standard')) {
        throw 'Method candidate требует MethodKind heuristic, checklist, workflow или standard.'
    }
    Assert-SafeCandidateText -Value $MethodSummary -Field 'MethodSummary' -SingleLine
    if ($MethodSummary.Length -gt 160 -or $MethodSummary -match '[<>\[\]|]') {
        throw 'MethodSummary содержит запрещенные символы или превышает лимит 160 символов.'
    }
    if ($Title -cnotmatch '^[\p{L}\p{N}][\p{L}\p{N} .,:;!?()/_+\-]{0,119}$') {
        throw 'Method Title не соответствует безопасному однострочному формату.'
    }
    if ($MethodAppliesTo.Count -eq 0 -or
        @($MethodAppliesTo | Sort-Object -Unique -CaseSensitive).Count -ne $MethodAppliesTo.Count) {
        throw 'Method candidate требует непустой MethodAppliesTo без дублей.'
    }
    $allowedIntentIds = Get-AllowedMasteryIntentIds
    foreach ($intentId in $MethodAppliesTo) {
        if ($intentId -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$' -or
            -not $allowedIntentIds.Contains($intentId)) {
            throw 'MethodAppliesTo содержит intent вне mastery/INTENTS.json.'
        }
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($MethodKind) -or
    -not [string]::IsNullOrWhiteSpace($MethodSummary) -or
    $MethodAppliesTo.Count -gt 0) {
    throw 'Method-поля допустимы только для Type method.'
}
if ($TargetRef -cmatch '^logical:shared-mastery/') {
    throw 'blocked: shared-owner'
}
Assert-SafeReference -Value $TargetRef -Field 'TargetRef'
$targetPathPart = $TargetRef.Split('#', 2)[0]
if ([System.IO.Path]::GetExtension($targetPathPart) -cne '.md') {
    throw 'TargetRef должен указывать на канонический Markdown-файл.'
}
if ($targetPathPart -match '^(?:knowledge/candidates|research/runs|analysis/runs|inbox/raw|plans|retrospectives)(?:/|$)') {
    throw "TargetRef указывает в рабочую или RAW-зону, а не в канон: $TargetRef"
}

$normalizedSources = @($SourceRefs | ForEach-Object { [string]$_ })
if ($normalizedSources.Count -eq 0) { throw 'SourceRefs должен содержать хотя бы одну ссылку.' }
if (@($normalizedSources | Sort-Object -Unique).Count -ne $normalizedSources.Count) {
    throw 'SourceRefs содержит дубли.'
}
foreach ($sourceRef in $normalizedSources) {
    Assert-SafeReference -Value $sourceRef -Field 'SourceRefs' -AllowExternal -AllowLogical -MustExist
}
if ($CaptureBasis -ceq 'plan-closeout' -and @($normalizedSources | Where-Object { $_ -match '^plans/\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*\.md(?:#.+)?$' }).Count -eq 0) {
    throw 'plan-closeout candidate требует source_ref на Plan v2.'
}

$normalizedConflicts = @($ConflictRefs | ForEach-Object { [string]$_ })
if (@($normalizedConflicts | Sort-Object -Unique).Count -ne $normalizedConflicts.Count) {
    throw 'ConflictRefs содержит дубли.'
}
foreach ($conflictRef in $normalizedConflicts) {
    Assert-SafeReference -Value $conflictRef -Field 'ConflictRefs' -AllowExternal -AllowLogical -MustExist
}

if ($Type -ceq 'method' -and [string]::IsNullOrWhiteSpace($ReviewDue)) {
    $ReviewDue = [System.DateTime]::UtcNow.Date.AddDays(180).ToString('yyyy-MM-dd')
}
if (-not [string]::IsNullOrWhiteSpace($ReviewDue)) {
    $parsedReviewDue = [datetime]::MinValue
    if (-not [datetime]::TryParseExact(
        $ReviewDue,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsedReviewDue
    )) {
        throw "ReviewDue имеет некорректную дату: $ReviewDue"
    }
}

if ($Type -ceq 'method') {
    if ($Domain -cne 'mastery') { throw 'Method candidate требует Domain mastery.' }
    if ($TargetRef -cne 'mastery/local/INDEX.md#зарегистрированные-расширения') {
        throw 'Method candidate требует exact TargetRef локального mastery registry.'
    }
    if ($ClaimKey -cnotmatch '^method\.[a-z0-9](?:[a-z0-9._-]{0,119}[a-z0-9])?$') {
        throw 'Method candidate требует ClaimKey вида method.<id>.'
    }
    if ($Confidence -cnotin @('medium', 'high')) {
        throw 'Method candidate требует Confidence medium или high.'
    }

    $taskSourceIdentities = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $hasProjectSource = $false
    foreach ($sourceRef in $normalizedSources) {
        $sourcePath = ([string]$sourceRef).Split('#', 2)[0]
        if ($sourcePath -match '^(?:[A-Za-z][A-Za-z0-9+.-]*:|//|KC-)') { continue }
        if ($sourcePath -notmatch '^knowledge/candidates/' -and
            $sourcePath -notmatch '(?:^|/)(?:README|INDEX|TEMPLATE)\.md$') {
            $hasProjectSource = $true
        }
        if ($sourcePath -match '^research/runs/(?<run>[^/]+)/decision\.md$') {
            [void]$taskSourceIdentities.Add('research:' + [string]$Matches['run'])
        }
        elseif ($sourcePath -match '^plans/(?<task>\d{4}-\d{2}-\d{2}-[^/]+)\.md$') {
            [void]$taskSourceIdentities.Add('plan:' + [string]$Matches['task'])
        }
        elseif ($sourcePath -match '^retrospectives/(?<task>[^/]+)\.md$') {
            [void]$taskSourceIdentities.Add('retrospective:' + [string]$Matches['task'])
        }
    }
    $explicitOperatorCorrection = (
        $CaptureBasis -ceq 'explicit-user-capture' -and
        $AuthorityRef -cmatch '^user-request:[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -and
        $hasProjectSource
    )
    if ($taskSourceIdentities.Count -lt 2 -and -not $explicitOperatorCorrection) {
        throw 'Method candidate требует два независимых task/run source или explicit operator correction с user authority и project source.'
    }
}

$candidateRoot = [System.IO.Path]::Combine($rootPath, 'knowledge', 'candidates')
$knownCandidateIds = @{}
$existingClaimCandidate = $null
    if (Test-Path -LiteralPath $candidateRoot) {
    $candidateRootReparse = Get-ReparsePointInPath $candidateRoot
    if ($null -ne $candidateRootReparse) {
        throw 'Каталог candidates проходит через reparse point.'
    }
    $existingCandidates = @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter 'KC-*.md' -Force |
        Select-Object -First ($maxTextFiles + 1))
    if ($existingCandidates.Count -gt $maxTextFiles) {
        throw "Candidates corpus превышает file-count limit $maxTextFiles."
    }
    foreach ($existing in $existingCandidates) {
        $frontMatter = Read-SimpleFrontMatter $existing.FullName
        if ($frontMatter.ContainsKey('id') -and [string]$frontMatter.id -match '^KC-\d{8}-\d{6}-[0-9a-f]{8}$') {
            $knownCandidateIds[[string]$frontMatter.id] = $true
        }
        if ($frontMatter.ContainsKey('claim_key') -and [string]$frontMatter.claim_key -ieq $ClaimKey -and
            $null -eq $existingClaimCandidate) {
            $existingClaimCandidate = [pscustomobject]@{
                File = $existing.FullName
                Relative = $existing.FullName.Substring($rootPath.Length + 1).Replace('\', '/')
                Data = $frontMatter
            }
        }
    }
}

$knownEvidenceIds = @{}
$researchRuns = [System.IO.Path]::Combine($rootPath, 'research', 'runs')
if (Test-Path -LiteralPath $researchRuns -PathType Container) {
    $researchReparse = Get-ReparsePointInPath $researchRuns
    if ($null -ne $researchReparse) {
        throw 'research/runs проходит через reparse point.'
    }
    $ledgers = @(Get-ChildItem -LiteralPath $researchRuns -Recurse -File -Filter 'evidence.jsonl' -Force)
    if ($ledgers.Count -gt $maxEvidenceLedgers) {
        throw "Слишком много evidence ledgers: $($ledgers.Count), limit=$maxEvidenceLedgers."
    }
    $totalEvidenceRecords = 0
    $totalEvidenceBytes = [long]0
    foreach ($ledger in $ledgers) {
        $ledgerRelative = $ledger.FullName.Substring($rootPath.Length + 1).Replace('\', '/')
        if (($ledger.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Evidence ledger является reparse point: $ledgerRelative"
        }
        if ($ledger.Length -gt $maxEvidenceFileBytes) {
            throw "Evidence ledger превышает file limit $maxEvidenceFileBytes bytes: $ledgerRelative"
        }
        $totalEvidenceBytes += $ledger.Length
        if ($totalEvidenceBytes -gt $maxEvidenceCorpusBytes) {
            throw "Evidence corpus превышает byte limit $maxEvidenceCorpusBytes."
        }
        $lineNumber = 0
        $recordCount = 0
        $ledgerReparse = Get-ReparsePointInPath $ledger.FullName
        if ($null -ne $ledgerReparse) {
            throw "Evidence ledger проходит через reparse point непосредственно перед чтением: $ledgerRelative"
        }
        $lineEnumerator = [System.IO.File]::ReadLines($ledger.FullName, $utf8Strict).GetEnumerator()
        try {
            while ($lineEnumerator.MoveNext()) {
                $line = [string]$lineEnumerator.Current
                $lineNumber++
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $recordCount++
                $totalEvidenceRecords++
                if ($line.Length -gt $maxEvidenceLineChars) {
                    throw "Evidence line превышает char limit ${maxEvidenceLineChars}: ${ledgerRelative}:$lineNumber"
                }
                if ($recordCount -gt $maxEvidenceRecordsPerFile) {
                    throw "Evidence ledger превышает record limit ${maxEvidenceRecordsPerFile}: $ledgerRelative"
                }
                if ($totalEvidenceRecords -gt $maxEvidenceRecordsTotal) {
                    throw "Evidence corpus превышает total record limit $maxEvidenceRecordsTotal."
                }
                try {
                    $row = $line | ConvertFrom-Json
                }
                catch {
                    throw "Corrupted evidence JSONL до создания candidate: ${ledgerRelative}:$lineNumber"
                }
                if ($null -eq $row -or $row -is [System.Array] -or $row -is [string] -or $row -is [ValueType]) {
                    throw "Evidence row должен быть JSON object: ${ledgerRelative}:$lineNumber"
                }
                $propertyNames = @($row.PSObject.Properties.Name)
                $missingFields = @($evidenceFields | Where-Object { $_ -cnotin $propertyNames })
                $unknownFields = @($propertyNames | Where-Object { $_ -cnotin $evidenceFields })
                if ($missingFields.Count -gt 0 -or $unknownFields.Count -gt 0) {
                    throw "Evidence schema mismatch: ${ledgerRelative}:$lineNumber; missing_count=$($missingFields.Count); unknown_count=$($unknownFields.Count)."
                }
                foreach ($property in $row.PSObject.Properties) {
            if (-not (& $script:mpkTestJsonScalar -Value $property.Value)) {
                        throw "Evidence field должен быть scalar: ${ledgerRelative}:$lineNumber"
                    }
                }
                $evidenceId = [string]$row.evidence_id
                if ($evidenceId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') {
                    throw "Invalid evidence_id: ${ledgerRelative}:$lineNumber"
                }
                if ($knownEvidenceIds.ContainsKey($evidenceId)) {
                    throw "Duplicate evidence_id обнаружен до создания candidate: ${ledgerRelative}:$lineNumber"
                }
                $knownEvidenceIds[$evidenceId] = $true
            }
        }
        finally {
            if ($lineEnumerator -is [System.IDisposable]) {
                $lineEnumerator.Dispose()
            }
        }
    }
}

foreach ($sourceRef in $normalizedSources) {
    if ($sourceRef -match '^KC-\d{8}-\d{6}-[0-9a-f]{8}$' -and -not $knownCandidateIds.ContainsKey($sourceRef)) {
        throw "SourceRefs ссылается на отсутствующий candidate: $sourceRef"
    }
    if ($sourceRef -match '^evidence:(.+)$' -and -not $knownEvidenceIds.ContainsKey($Matches[1])) {
        throw 'SourceRefs ссылается на отсутствующий evidence ID.'
    }
}
foreach ($conflictRef in $normalizedConflicts) {
    if ($conflictRef -match '^KC-\d{8}-\d{6}-[0-9a-f]{8}$' -and -not $knownCandidateIds.ContainsKey($conflictRef)) {
        throw "ConflictRefs ссылается на отсутствующий candidate: $conflictRef"
    }
    if ($conflictRef -match '^evidence:(.+)$' -and -not $knownEvidenceIds.ContainsKey($Matches[1])) {
        throw 'ConflictRefs ссылается на отсутствующий evidence ID.'
    }
}

if ($null -ne $existingClaimCandidate) {
    if (-not (Test-ExistingCandidateRequestMatch `
        -FilePath $existingClaimCandidate.File `
        -Data $existingClaimCandidate.Data)) {
        throw 'blocked: claim-key-collision'
    }
    return [pscustomobject]@{
        InternalResultKind = 'existing-requires-strict-preflight'
        ExistingCandidate = $existingClaimCandidate
    }
}

Assert-TrustedKnowledgePreflight

$knowledgeRoot = Join-Path $rootPath 'knowledge'
if (-not (Test-Path -LiteralPath $knowledgeRoot -PathType Container)) {
    throw 'Knowledge root отсутствует.'
}
if ($null -ne (Get-ReparsePointInPath $knowledgeRoot)) {
    throw 'Knowledge root проходит через reparse point.'
}
if (-not (Test-Path -LiteralPath $candidateRoot -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($candidateRoot) | Out-Null
}
if ($null -ne (Get-ReparsePointInPath $candidateRoot)) {
    throw 'Каталог candidates проходит через reparse point.'
}

$published = $false
$id = $null
$finalPath = $null
for ($attempt = 0; $attempt -lt 16; $attempt++) {
    $now = [System.DateTimeOffset]::Now
    $randomBytes = [byte[]]::new(4)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($randomBytes)
    }
    finally {
        $rng.Dispose()
    }
    $suffix = ([System.BitConverter]::ToString($randomBytes)).Replace('-', '').ToLowerInvariant()
    $candidateId = 'KC-{0}-{1}-{2}' -f $now.ToString('yyyyMMdd'), $now.ToString('HHmmss'), $suffix
    $candidatePath = [System.IO.Path]::Combine(
        $candidateRoot,
        $now.ToString('yyyy'),
        "$candidateId.md"
    )
    if (Test-Path -LiteralPath $candidatePath) { continue }

    $reviewDueYaml = if ([string]::IsNullOrWhiteSpace($ReviewDue)) { 'null' } else { Convert-ToYamlScalar $ReviewDue }
    $reviewDueValue = if ([string]::IsNullOrWhiteSpace($ReviewDue)) { $null } else { $ReviewDue }
    $createdAtValue = $now.ToString('yyyy-MM-ddTHH:mm:ssK')
    $sourceYaml = ($normalizedSources | ForEach-Object { '  - ' + (Convert-ToYamlScalar $_) }) -join "`n"
    $conflictYaml = if ($normalizedConflicts.Count -eq 0) {
        '[]'
    }
    else {
        "`n" + (($normalizedConflicts | ForEach-Object { '  - ' + (Convert-ToYamlScalar $_) }) -join "`n")
    }
    $methodKindYaml = if ($Type -ceq 'method') { Convert-ToYamlScalar $MethodKind } else { 'null' }
    $methodSummaryYaml = if ($Type -ceq 'method') { Convert-ToYamlScalar $MethodSummary } else { 'null' }
    $methodAppliesYaml = if ($Type -ceq 'method') {
        "`n" + (($MethodAppliesTo | ForEach-Object { '  - ' + (Convert-ToYamlScalar $_) }) -join "`n")
    }
    else { '[]' }

    $content = @"
---
id: $(Convert-ToYamlScalar $candidateId)
state: ready
type: $Type
owner_scope: project
domain: $Domain
method_kind: $methodKindYaml
method_summary: $methodSummaryYaml
method_applies_to: $methodAppliesYaml
claim_key: $(Convert-ToYamlScalar $ClaimKey)
target_ref: $(Convert-ToYamlScalar $TargetRef)
source_refs:
$sourceYaml
conflict_refs: $conflictYaml
confidence: $Confidence
capture_basis: $CaptureBasis
data_class: $DataClass
created_at: $(Convert-ToYamlScalar $createdAtValue)
review_due: $reviewDueYaml
authority_ref: $(Convert-ToYamlScalar $AuthorityRef)
applied_at: null
dismiss_reason: null
supersedes: null
---

# $Title

## Основание

$($Basis.Trim())

## Предлагаемое изменение

$($ProposedChange.Trim())

## Проверка дублей и противоречий

$($DuplicateCheck.Trim())

## Обоснование lifecycle

Candidate ожидает review или explicit promotion в $TargetRef. Основание authority зафиксировано во frontmatter.
"@
    $content = $content.TrimEnd() + "`n"

    try {
        $contentBytes = $utf8Strict.GetByteCount($content)
    }
    catch {
        throw 'Сгенерированный candidate невозможно представить как строгий UTF-8.'
    }
    if ($contentBytes -gt $maxTextFileBytes) {
        throw "Сгенерированный candidate превышает UTF-8 byte limit $maxTextFileBytes."
    }
    Assert-SafeCandidateText -Value $content -Field 'Сгенерированный candidate' -AllowDocumentStructure
    Assert-RenderedCandidate `
        -Content $content `
        -ExpectedId $candidateId `
        -ExpectedType $Type `
        -ExpectedDomain $Domain `
        -ExpectedClaimKey $ClaimKey `
        -ExpectedTargetRef $TargetRef `
        -ExpectedSourceRefs $normalizedSources `
        -ExpectedConflictRefs $normalizedConflicts `
        -ExpectedConfidence $Confidence `
        -ExpectedCaptureBasis $CaptureBasis `
        -ExpectedDataClass $DataClass `
        -ExpectedMethodKind $(if ($Type -ceq 'method') { $MethodKind } else { $null }) `
        -ExpectedMethodSummary $(if ($Type -ceq 'method') { $MethodSummary } else { $null }) `
        -ExpectedMethodAppliesTo $MethodAppliesTo `
        -ExpectedCreatedAt $createdAtValue `
        -ExpectedReviewDue $reviewDueValue `
        -ExpectedAuthorityRef $AuthorityRef `
        -ExpectedTitle $Title

    $yearDirectory = Split-Path -Parent $candidatePath
    if (-not (Test-Path -LiteralPath $yearDirectory -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($yearDirectory) | Out-Null
    }
    if ($null -ne (Get-ReparsePointInPath $yearDirectory)) {
        throw 'Целевой каталог проходит через reparse point.'
    }

    $temporaryPath = Join-Path $knowledgeRoot ('.candidate-{0}.tmp' -f [guid]::NewGuid().ToString('N'))
    $stream = $null
    $writer = $null
    $retryCollision = $false
    try {
        $stream = [System.IO.FileStream]::new(
            $temporaryPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None,
            4096,
            [System.IO.FileOptions]::WriteThrough
        )
        $writer = [System.IO.StreamWriter]::new($stream, $utf8NoBom)
        $writer.Write($content)
        $writer.Flush()
        $stream.Flush($true)
        $writer.Dispose()
        $writer = $null
        $stream = $null

        try {
            [System.IO.File]::Move($temporaryPath, $candidatePath)
        }
        catch [System.IO.IOException] {
            if (Test-Path -LiteralPath $candidatePath) {
                $retryCollision = $true
            }
            else {
                throw
            }
        }
    }
    finally {
        if ($null -ne $writer) { $writer.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            [System.IO.File]::Delete($temporaryPath)
        }
    }
    if ($retryCollision) { continue }

    $id = $candidateId
    $finalPath = $candidatePath
    $published = $true
    break
}
if (-not $published) {
    throw 'blocked: candidate-id-exhausted'
}

$relativePath = $finalPath.Substring($rootPath.Length + 1).Replace('\', '/')
Write-Host "READY [$id]: $relativePath"
return [pscustomobject]@{
    id = $id
    state = 'ready'
    path = $relativePath
    claim_key = $ClaimKey
}
}

$claimLockResourceKey = Get-ClaimLockResourceKey -RepositoryRoot $rootPath -NormalizedClaimKey $ClaimKey
$claimLock = $null
$lockedResult = $null
try {
    try {
        $claimLock = & $script:mppEnterLock `
            -RepositoryRoot $rootPath `
            -ResourceKey $claimLockResourceKey `
            -TimeoutSeconds 60
    }
    catch {
        throw 'blocked: candidate-lock-timeout'
    }
    $lockedResult = Invoke-CandidateCreationLocked
}
finally {
    if ($null -ne $claimLock) { & $script:mppExitLock -Lock $claimLock }
}

if ($null -ne $lockedResult -and
    $lockedResult.PSObject.Properties.Name -ccontains 'InternalResultKind' -and
    [string]$lockedResult.InternalResultKind -ceq 'existing-requires-strict-preflight') {
    Assert-TrustedKnowledgePreflight
    return (Complete-ExistingCandidateRequest -ExistingCandidate $lockedResult.ExistingCandidate)
}
return $lockedResult
