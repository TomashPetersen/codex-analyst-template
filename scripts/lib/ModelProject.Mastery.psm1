Set-StrictMode -Version 2.0

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:KnowledgeModulePath = Join-Path $PSScriptRoot 'ModelProject.Knowledge.psm1'
Import-Module $script:KnowledgeModulePath -Scope Local

$script:RequiredIntentIds = @(
    'research',
    'product',
    'business-architecture',
    'planning',
    'architecture',
    'implementation',
    'testing',
    'debugging',
    'review',
    'security',
    'release',
    'operations',
    'design',
    'content',
    'collaboration',
    'knowledge-curation'
)
$script:MethodKinds = @('heuristic', 'checklist', 'workflow', 'standard')
$script:MethodStatuses = @('active', 'deprecated', 'superseded')

function Get-ModelProjectMasteryRoot {
    param([string]$Root = '')

    $candidate = if ([string]::IsNullOrWhiteSpace($Root)) {
        Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }
    else {
        $Root
    }
    $rootPath = [System.IO.Path]::GetFullPath($candidate).TrimEnd([char[]]'\/')
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
        throw 'Корень репозитория не найден.'
    }
    if ($null -ne (Get-ModelProjectReparsePointInFullChain -Root $rootPath -Path $rootPath)) {
        throw 'Корень репозитория не может проходить через reparse point.'
    }
    return $rootPath
}

function Assert-ModelProjectMasterySafeText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label,
        [int]$MaxLength = 240,
        [switch]$AllowEmpty
    )

    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value)) {
        throw "$Label не заполнено."
    }
    if ($Value.Length -gt $MaxLength -or
        $Value -match '[\r\n\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' -or
        $Value -match '[<>\[\]|]') {
        throw "$Label содержит запрещенные символы или превышает лимит."
    }
    if (@(Get-ModelProjectSensitiveTextFindings -Text $Value).Count -gt 0) {
        throw "$Label содержит потенциально чувствительные данные."
    }
}

function Get-ModelProjectMasteryIntentCatalog {
    param([string]$Root = '')

    $rootPath = Get-ModelProjectMasteryRoot -Root $Root
    $catalogPath = Join-Path $rootPath 'mastery/INTENTS.json'
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf) -or
        -not (Test-ModelProjectExactPathCase -Root $rootPath -Path $catalogPath) -or
        $null -ne (Get-ModelProjectReparsePointInFullChain -Root $rootPath -Path $catalogPath)) {
        throw 'mastery/INTENTS.json отсутствует или не прошел path integrity check.'
    }
    $text = Read-ModelProjectBoundedUtf8File -Root $rootPath -Path $catalogPath -MaxBytes 256KB
    try {
        $catalog = $text | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'mastery/INTENTS.json содержит некорректный JSON.'
    }
    if ($null -eq $catalog -or $catalog -is [System.Array] -or
        ((@($catalog.PSObject.Properties.Name | Sort-Object) -join ',') -cne 'intents,schema_version') -or
        [string]$catalog.schema_version -cne '1' -or
        -not ($catalog.intents -is [System.Array]) -or
        @($catalog.intents).Count -eq 0 -or
        @($catalog.intents).Count -gt 128) {
        throw 'mastery/INTENTS.json не соответствует catalog contract v1.'
    }

    $records = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($intent in @($catalog.intents)) {
        if ($null -eq $intent -or $intent -is [System.Array] -or
            ((@($intent.PSObject.Properties.Name | Sort-Object) -join ',') -cne 'description,id,label')) {
            throw 'mastery/INTENTS.json содержит intent с неизвестной схемой.'
        }
        $id = [string]$intent.id
        $label = [string]$intent.label
        $description = [string]$intent.description
        if ($id -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$' -or -not $seen.Add($id)) {
            throw 'mastery/INTENTS.json содержит invalid или duplicate intent id.'
        }
        Assert-ModelProjectMasterySafeText -Value $label -Label 'Intent label' -MaxLength 80
        Assert-ModelProjectMasterySafeText -Value $description -Label 'Intent description' -MaxLength 240
        $records.Add([pscustomobject]@{
            Id = $id
            Label = $label
            Description = $description
        }) | Out-Null
    }
    foreach ($requiredId in $script:RequiredIntentIds) {
        if (-not $seen.Contains($requiredId)) {
            throw "mastery/INTENTS.json не содержит обязательный intent '$requiredId'."
        }
    }
    return @($records | Sort-Object -Property Id)
}

function Get-ModelProjectLocalMasteryFiles {
    param([string]$Root = '')

    $rootPath = Get-ModelProjectMasteryRoot -Root $Root
    $localPath = Join-Path $rootPath 'mastery/local'
    if (-not (Test-Path -LiteralPath $localPath -PathType Container)) { return @() }
    if ($null -ne (Get-ModelProjectReparsePointInFullChain -Root $rootPath -Path $localPath)) {
        throw 'mastery/local не может проходить через reparse point.'
    }
    $nested = @(Get-ChildItem -LiteralPath $localPath -Directory -Force)
    if ($nested.Count -gt 0) { throw 'mastery/local поддерживает только плоский каталог методов.' }
    $unexpected = @(Get-ChildItem -LiteralPath $localPath -File -Force | Where-Object {
        $_.Name -cnotin @('INDEX.md', 'TEMPLATE.md') -and $_.Extension -cne '.md'
    })
    if ($unexpected.Count -gt 0) { throw 'mastery/local содержит файл неподдерживаемого типа.' }
    return @(
        Get-ChildItem -LiteralPath $localPath -File -Filter '*.md' -Force |
            Where-Object { $_.Name -cnotin @('INDEX.md', 'TEMPLATE.md') } |
            Sort-Object -Property Name
    )
}

function Read-ModelProjectLocalMasteryRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path,
        [object[]]$IntentCatalog = @()
    )

    $rootPath = Get-ModelProjectMasteryRoot -Root $Root
    $document = Read-ModelProjectSimpleFrontMatterDocument -Root $rootPath -Path $Path -MaxBytes 2MB
    $data = $document.Data
    $fields = @(
        'mastery_contract_version', 'method_id', 'method_kind', 'summary', 'owner_scope',
        'applies_to', 'status', 'source_refs', 'verified_at', 'review_due', 'supersedes'
    )
    if (@($fields | Where-Object { -not $data.Contains($_) }).Count -gt 0 -or
        @($data.Keys | Where-Object { $_ -cnotin $fields }).Count -gt 0) {
        throw "$($document.RelativePath): Local Mastery closed schema нарушена."
    }
    foreach ($field in @('mastery_contract_version', 'method_id', 'method_kind', 'summary', 'owner_scope', 'status', 'verified_at', 'review_due')) {
        if (-not (Test-ModelProjectFrontMatterScalarValue -Value $data[$field])) {
            throw "$($document.RelativePath): '$field' должен быть scalar."
        }
    }
    if (-not (Test-ModelProjectFrontMatterScalarValue -Value $data.supersedes -AllowNull)) {
        throw "$($document.RelativePath): supersedes должен быть scalar или null."
    }
    $methodId = [string]$data.method_id
    $methodKind = [string]$data.method_kind
    $summary = [string]$data.summary
    $status = [string]$data.status
    if ([string]$data.mastery_contract_version -cne '2' -or
        $methodId -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?$' -or
        [System.IO.Path]::GetFileName($Path) -cne "$methodId.md" -or
        $methodKind -cnotin $script:MethodKinds -or
        [string]$data.owner_scope -cne 'project' -or
        $status -cnotin $script:MethodStatuses) {
        throw "$($document.RelativePath): Local Mastery metadata недопустима."
    }
    Assert-ModelProjectMasterySafeText -Value $summary -Label 'Method summary' -MaxLength 160

    $intentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($intent in $IntentCatalog) { [void]$intentIds.Add([string]$intent.Id) }
    $appliesTo = @(
        if ($data.applies_to -is [System.Array]) { $data.applies_to | ForEach-Object { [string]$_ } }
    )
    if ($appliesTo.Count -eq 0 -or @($appliesTo | Sort-Object -Unique -CaseSensitive).Count -ne $appliesTo.Count -or
        @($appliesTo | Where-Object { -not $intentIds.Contains($_) }).Count -gt 0) {
        throw "$($document.RelativePath): applies_to не соответствует mastery/INTENTS.json."
    }
    $sourceRefs = @(
        if ($data.source_refs -is [System.Array]) { $data.source_refs | ForEach-Object { [string]$_ } }
    )
    if ($sourceRefs.Count -ne 1 -or $sourceRefs[0] -cnotmatch '^knowledge/candidates/\d{4}/KC-\d{8}-\d{6}-[0-9a-f]{8}\.md$') {
        throw "$($document.RelativePath): source_refs должен содержать один applied method candidate."
    }
    $resolvedSource = Resolve-ModelProjectSafeReference `
        -Root $rootPath `
        -SourcePath $document.Path `
        -Reference $sourceRefs[0] `
        -ReferenceBase Repository
    if (-not $resolvedSource.Exists -or -not $resolvedSource.ExactCase) {
        throw "$($document.RelativePath): candidate source отсутствует или имеет неверный регистр."
    }
    $verifiedDate = [datetime]::MinValue
    $reviewDate = [datetime]::MinValue
    if (-not [datetime]::TryParseExact([string]$data.verified_at, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$verifiedDate) -or
        -not [datetime]::TryParseExact([string]$data.review_due, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$reviewDate) -or
        $verifiedDate.Date -gt [datetime]::UtcNow.Date -or
        $reviewDate.Date -lt $verifiedDate.Date) {
        throw "$($document.RelativePath): verified_at или review_due недопустимы."
    }
    $supersedes = if ($null -eq $data.supersedes) { $null } else { [string]$data.supersedes }
    if ($null -ne $supersedes -and $supersedes -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?$') {
        throw "$($document.RelativePath): supersedes содержит invalid method_id."
    }
    $titleMatch = [regex]::Match($document.Body, '(?m)^#[ \t]+(?<title>[^\r\n]+?)[ \t]*$')
    if (-not $titleMatch.Success) { throw "$($document.RelativePath): отсутствует H1 title." }
    $title = $titleMatch.Groups['title'].Value.Trim()
    Assert-ModelProjectMasterySafeText -Value $title -Label 'Method title' -MaxLength 120
    if (@(Get-ModelProjectSensitiveTextFindings -Text $document.Content).Count -gt 0) {
        throw "$($document.RelativePath): обнаружены потенциально чувствительные данные."
    }
    return [pscustomobject]@{
        MethodId = $methodId
        MethodKind = $methodKind
        Summary = $summary
        AppliesTo = $appliesTo
        Status = $status
        SourceRefs = $sourceRefs
        CandidateId = [System.IO.Path]::GetFileNameWithoutExtension($sourceRefs[0])
        VerifiedAt = [string]$data.verified_at
        ReviewDue = [string]$data.review_due
        Supersedes = $supersedes
        Title = $title
        RelativePath = $document.RelativePath
        FileName = [System.IO.Path]::GetFileName($document.Path)
    }
}

function ConvertTo-ModelProjectMasteryCell {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    return $Value.Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function Get-ModelProjectMasteryIndexContent {
    param([string]$Root = '')

    $rootPath = Get-ModelProjectMasteryRoot -Root $Root
    $catalog = @(Get-ModelProjectMasteryIntentCatalog -Root $rootPath)
    $records = [System.Collections.Generic.List[object]]::new()
    $seenMethods = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @(Get-ModelProjectLocalMasteryFiles -Root $rootPath)) {
        $record = Read-ModelProjectLocalMasteryRecord -Root $rootPath -Path $file.FullName -IntentCatalog $catalog
        if (-not $seenMethods.Add($record.MethodId)) { throw 'Duplicate Local Mastery method_id.' }
        $records.Add($record) | Out-Null
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Local Mastery')
    $lines.Add('')
    $lines.Add('Этот файл создается детерминированно командой `scripts/update-mastery-index.ps1`. Не редактируй его вручную.')
    $lines.Add('')
    $lines.Add('Local Mastery хранит только примененные project-local методы. Новый метод сначала проходит candidate lifecycle и отдельное одобрение; автоматического преобразования Mastery в Skill нет.')
    $lines.Add('')
    $lines.Add('## Каталог intents')
    $lines.Add('')
    $lines.Add('Источник - [`../INTENTS.json`](../INTENTS.json). Новую категорию добавляй в каталог, а не в PowerShell-код.')
    $lines.Add('')
    $lines.Add('| Intent ID | Название | Назначение |')
    $lines.Add('|---|---|---|')
    foreach ($intent in $catalog) {
        $lines.Add('| `' + $intent.Id + '` | ' +
            (ConvertTo-ModelProjectMasteryCell -Value $intent.Label) + ' | ' +
            (ConvertTo-ModelProjectMasteryCell -Value $intent.Description) + ' |')
    }
    $lines.Add('')
    $lines.Add('## Зарегистрированные расширения')
    $lines.Add('')
    $lines.Add('| Method ID | Вид | Краткое описание | Intents | Проверено | Review due | Статус | Метод | Candidate |')
    $lines.Add('|---|---|---|---|---|---|---|---|---|')
    if ($records.Count -eq 0) {
        $lines.Add('| Пока нет | - | - | - | - | - | - | - | - |')
    }
    else {
        foreach ($record in @($records | Sort-Object -Property MethodId)) {
            $candidateTarget = '../../' + $record.SourceRefs[0]
            $intentCell = @($record.AppliesTo | ForEach-Object { '`' + $_ + '`' }) -join ', '
            $lines.Add('| `' + $record.MethodId + '` | `' + $record.MethodKind + '` | ' +
                (ConvertTo-ModelProjectMasteryCell -Value $record.Summary) + ' | ' + $intentCell + ' | ' +
                $record.VerifiedAt + ' | ' + $record.ReviewDue + ' | `' + $record.Status + '` | [' +
                (ConvertTo-ModelProjectMasteryCell -Value $record.Title) + '](' + $record.FileName + ') | [' +
                $record.CandidateId + '](' + $candidateTarget + ') |')
        }
    }
    $lines.Add('')
    $lines.Add('## Retrieval route')
    $lines.Add('')
    $lines.Add('1. Выбери intent из каталога.')
    $lines.Add('2. Открой максимум один `active`, непросроченный и релевантный local method.')
    $lines.Add('3. Зафиксируй `method_id` и точный file ref в plan или research brief.')
    $lines.Add('4. Не выбирай автоматически `deprecated`, `superseded` или просроченный метод.')
    $lines.Add('')
    $lines.Add('## Маршруты')
    $lines.Add('')
    $lines.Add('- [Project Mastery](../INDEX.md)')
    $lines.Add('- [Шаблон метода](TEMPLATE.md)')
    $lines.Add('- [Knowledge lifecycle](../../knowledge/INDEX.md)')
    $lines.Add('- [Knowledge graph](../../knowledge/graph/INDEX.md)')
    return (($lines -join "`n") + "`n")
}

function Write-ModelProjectMasteryAtomicText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content,
        [switch]$CreateNew
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory)
    }
    $temporary = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($temporary, $Content, $script:Utf8NoBom)
        if ($CreateNew -and (Test-Path -LiteralPath $Path)) { throw 'Целевой файл уже существует.' }
        [System.IO.File]::Move($temporary, $Path, -not $CreateNew)
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { [System.IO.File]::Delete($temporary) }
    }
}

function Update-ModelProjectMasteryIndex {
    param(
        [string]$Root = '',
        [ValidateSet('Check', 'Write', 'Report')][string]$Mode = 'Check'
    )

    $rootPath = Get-ModelProjectMasteryRoot -Root $Root
    $indexPath = Join-Path $rootPath 'mastery/local/INDEX.md'
    $expected = Get-ModelProjectMasteryIndexContent -Root $rootPath
    $actual = if (Test-Path -LiteralPath $indexPath -PathType Leaf) {
        Read-ModelProjectBoundedUtf8File -Root $rootPath -Path $indexPath -MaxBytes 2MB
    }
    else { $null }
    $matches = $null -ne $actual -and $actual -ceq $expected
    if ($Mode -ceq 'Write') {
        Write-ModelProjectMasteryAtomicText -Path $indexPath -Content $expected
        return [pscustomobject]@{ Changed = -not $matches; Path = $indexPath; Content = $expected }
    }
    if ($Mode -ceq 'Check' -and -not $matches) {
        throw 'mastery/local/INDEX.md отсутствует или устарел.'
    }
    return [pscustomobject]@{ Changed = -not $matches; Path = $indexPath; Content = $expected }
}

Microsoft.PowerShell.Core\Export-ModuleMember -Function @(
    'Get-ModelProjectMasteryRoot',
    'Get-ModelProjectMasteryIntentCatalog',
    'Get-ModelProjectLocalMasteryFiles',
    'Read-ModelProjectLocalMasteryRecord',
    'Get-ModelProjectMasteryIndexContent',
    'Write-ModelProjectMasteryAtomicText',
    'Update-ModelProjectMasteryIndex'
)
