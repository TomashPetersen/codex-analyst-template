[CmdletBinding()]
param(
    [string]$Root = '',

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^KC-\d{8}-\d{6}-[0-9a-f]{8}$')]
    [string]$CandidateId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^user-request:[A-Za-z0-9][A-Za-z0-9._-]{0,127}$')]
    [string]$AuthorityRef,

    [switch]$WhatIf
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:masteryApplyDetail = $null
$safeErrors = @(
    'blocked: repository-mode',
    'blocked: invalid-authority',
    'blocked: candidate-not-found',
    'blocked: candidate-contract',
    'blocked: method-exists',
    'blocked: repository-preflight',
    'blocked: mastery-apply-rollback',
    'blocked: mastery-apply-rollback-incomplete'
)
trap {
    $message = [string]$_.Exception.Message
    if ([string]::IsNullOrWhiteSpace([string]$MyInvocation.ScriptName)) {
        $safe = if ($message -cin $safeErrors) { $message } else { 'blocked: mastery-apply' }
        [Console]::Error.WriteLine("ERROR: $safe")
        if ($VerbosePreference -ceq 'Continue') {
            $detail = if ([string]::IsNullOrWhiteSpace([string]$script:masteryApplyDetail)) { $message } else { [string]$script:masteryApplyDetail }
            [Console]::Error.WriteLine("DETAIL: $detail")
        }
        exit 1
    }
    throw
}

$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$knowledgeModulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Knowledge.psm1'
$masteryModulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Mastery.psm1'
Import-Module $knowledgeModulePath -Force
Import-Module $masteryModulePath -Force

function ConvertTo-MasteryYamlScalar {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Set-CandidateScalar {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Field,
        [Parameter(Mandatory = $true)][string]$YamlValue
    )
    $pattern = '(?m)^' + [regex]::Escape($Field) + ':[^\r\n]*$'
    if ([regex]::Matches($Content, $pattern).Count -ne 1) {
        throw 'blocked: candidate-contract'
    }
    $replacement = $Field + ': ' + $YamlValue
    return [regex]::Replace(
        $Content,
        $pattern,
        [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement },
        1
    )
}

function Get-CandidateSection {
    param(
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $true)][string]$Heading
    )
    $match = [regex]::Match(
        $Body,
        '(?ms)^##[ \t]+' + [regex]::Escape($Heading) + '[ \t]*\r?\n(?<value>.*?)(?=^##[ \t]+|\z)'
    )
    if (-not $match.Success -or [string]::IsNullOrWhiteSpace($match.Groups['value'].Value)) {
        throw 'blocked: candidate-contract'
    }
    return $match.Groups['value'].Value.Trim()
}

function Invoke-TrustedScript {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $scriptPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Name))
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf) -or
        [System.IO.Path]::GetDirectoryName($scriptPath) -cne [System.IO.Path]::GetFullPath($PSScriptRoot)) {
        throw 'blocked: repository-preflight'
    }
    $hostPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ([string]::IsNullOrWhiteSpace($hostPath) -or -not (Test-Path -LiteralPath $hostPath -PathType Leaf)) {
        throw 'blocked: repository-preflight'
    }
    $output = @(& $hostPath -NoLogo -NoProfile -NonInteractive -File $scriptPath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        if ($VerbosePreference -ceq 'Continue') {
            $script:masteryApplyDetail = $Name + ' failed: ' + ((@($output | ForEach-Object { [string]$_ })) -join ' | ')
        }
        throw 'blocked: repository-preflight'
    }
    $output = $null
}

function Get-OptionalTextSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ Exists = $false; Text = $null }
    }
    return [pscustomobject]@{
        Exists = $true
        Text = [System.IO.File]::ReadAllText($Path, $utf8Strict)
    }
}

function Restore-TextSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Snapshot
    )
    if ($Snapshot.Exists) {
        Write-ModelProjectMasteryAtomicText -Path $Path -Content ([string]$Snapshot.Text)
    }
    elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
        [System.IO.File]::Delete($Path)
    }
}

try {
    $rootPath = Get-ModelProjectMasteryRoot -Root $Root
    if ($AuthorityRef -cnotmatch '^user-request:[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        throw 'blocked: invalid-authority'
    }

    $projectPath = Join-Path $rootPath 'PROJECT.md'
    $projectDocument = Read-ModelProjectSimpleFrontMatterDocument -Root $rootPath -Path $projectPath
    $project = $projectDocument.Data
    $projectTuple = [string]$project.project_status + '|' + [string]$project.knowledge_capture_mode
    if ([string]$project.repository_kind -cne 'generated-project' -or
        $projectTuple -cnotin @('initialized|report-only', 'active|report-only', 'active|safe-local')) {
        throw 'blocked: repository-mode'
    }

    Invoke-TrustedScript -Name 'verify-knowledge.ps1' -Arguments @('-Root', $rootPath)
    Invoke-TrustedScript -Name 'update-mastery-index.ps1' -Arguments @('-Root', $rootPath, '-Mode', 'Check')

    $matches = @(Get-ChildItem -LiteralPath (Join-Path $rootPath 'knowledge/candidates') -Recurse -File -Filter "$CandidateId.md" -Force)
    if ($matches.Count -ne 1) { throw 'blocked: candidate-not-found' }
    $candidatePath = $matches[0].FullName
    $candidateDocument = Read-ModelProjectSimpleFrontMatterDocument -Root $rootPath -Path $candidatePath
    $candidate = $candidateDocument.Data
    $candidateRelative = $candidateDocument.RelativePath
    $methodId = if ($candidate.Contains('claim_key') -and [string]$candidate.claim_key -cmatch '^method\.(?<id>[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?)$') {
        [string]$Matches['id']
    }
    else { '' }
    $methodIntents = @(
        if ($candidate.Contains('method_applies_to') -and $candidate.method_applies_to -is [System.Array]) {
            $candidate.method_applies_to | ForEach-Object { [string]$_ }
        }
    )
    if ([string]$candidate.id -cne $CandidateId -or
        [string]$candidate.state -cne 'ready' -or
        [string]$candidate.type -cne 'method' -or
        [string]$candidate.domain -cne 'mastery' -or
        [string]$candidate.target_ref -cne 'mastery/local/INDEX.md#зарегистрированные-расширения' -or
        [string]::IsNullOrWhiteSpace($methodId) -or
        [string]$candidate.method_kind -cnotin @('heuristic', 'checklist', 'workflow', 'standard') -or
        [string]::IsNullOrWhiteSpace([string]$candidate.method_summary) -or
        $methodIntents.Count -eq 0 -or
        -not ($candidate.conflict_refs -is [System.Array]) -or
        @($candidate.conflict_refs).Count -ne 0) {
        throw 'blocked: candidate-contract'
    }
    $catalog = @(Get-ModelProjectMasteryIntentCatalog -Root $rootPath)
    $catalogIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($intent in $catalog) { [void]$catalogIds.Add([string]$intent.Id) }
    if (@($methodIntents | Sort-Object -Unique -CaseSensitive).Count -ne $methodIntents.Count -or
        @($methodIntents | Where-Object { -not $catalogIds.Contains($_) }).Count -gt 0) {
        throw 'blocked: candidate-contract'
    }

    $reviewDue = [datetime]::MinValue
    if (-not [datetime]::TryParseExact([string]$candidate.review_due, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$reviewDue) -or
        $reviewDue.Date -lt [datetime]::UtcNow.Date) {
        throw 'blocked: candidate-contract'
    }
    $titleMatch = [regex]::Match($candidateDocument.Body, '(?m)^#[ \t]+(?<title>[^\r\n]+?)[ \t]*$')
    if (-not $titleMatch.Success) { throw 'blocked: candidate-contract' }
    $title = $titleMatch.Groups['title'].Value.Trim()
    if ($title -cnotmatch '^[\p{L}\p{N}][\p{L}\p{N} .,:;!?()/_+\-]{0,119}$') {
        throw 'blocked: candidate-contract'
    }
    $workflow = Get-CandidateSection -Body $candidateDocument.Body -Heading 'Предлагаемое изменение'
    $methodPath = Join-Path $rootPath "mastery/local/$methodId.md"
    if (Test-Path -LiteralPath $methodPath) { throw 'blocked: method-exists' }

    $verifiedAt = [datetime]::UtcNow.ToString('yyyy-MM-dd')
    $appliedAt = [System.DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssK')
    $intentYaml = ($methodIntents | ForEach-Object { '  - ' + (ConvertTo-MasteryYamlScalar $_) }) -join "`n"
    $intentDisplay = @($methodIntents | ForEach-Object { '`' + $_ + '`' }) -join ', '
    $methodContent = @"
---
mastery_contract_version: 2
method_id: $(ConvertTo-MasteryYamlScalar $methodId)
method_kind: $(ConvertTo-MasteryYamlScalar ([string]$candidate.method_kind))
summary: $(ConvertTo-MasteryYamlScalar ([string]$candidate.method_summary))
owner_scope: project
applies_to:
$intentYaml
status: active
source_refs:
  - $(ConvertTo-MasteryYamlScalar $candidateRelative)
verified_at: $(ConvertTo-MasteryYamlScalar $verifiedAt)
review_due: $(ConvertTo-MasteryYamlScalar ([string]$candidate.review_due))
supersedes: null
---

# $title

## Purpose

$([string]$candidate.method_summary)

## Use when

Применять для intents: $intentDisplay.

## Do not use when

Не применять вне указанных intents или при отсутствии необходимых входов и authority.

## Inputs

Определи источники истины, ограничения и проверяемый ожидаемый результат до начала работы.

## Workflow

$workflow

## Quality gate

Результат проверен по заявленной цели, evidence и релевантным project gates.

## Failure modes

При недостаточных входах, конфликте канона или недоказанном результате остановиться и зафиксировать blocker.

## Provenance

Applied method candidate указан во frontmatter `source_refs`; видимый backlink хранится в derived Local Mastery registry.

## Navigation

- [Local Mastery registry](INDEX.md)
"@
    $methodContent = $methodContent.TrimEnd() + "`n"
    $updatedCandidate = Set-CandidateScalar -Content $candidateDocument.Content -Field state -YamlValue 'applied'
    $updatedCandidate = Set-CandidateScalar -Content $updatedCandidate -Field authority_ref -YamlValue (ConvertTo-MasteryYamlScalar $AuthorityRef)
    $updatedCandidate = Set-CandidateScalar -Content $updatedCandidate -Field applied_at -YamlValue (ConvertTo-MasteryYamlScalar $appliedAt)

    $methodRelative = "mastery/local/$methodId.md"
    if ($WhatIf) {
        Write-Output "PREVIEW [$CandidateId]: $methodRelative"
        Write-Output "METHOD_ID=$methodId"
        Write-Output "METHOD_KIND=$($candidate.method_kind)"
        Write-Output "METHOD_INTENTS=$($methodIntents -join ',')"
        Write-Output "AUTHORITY_REF=$AuthorityRef"
        Write-Output 'MUTATION=none'
        exit 0
    }

    $indexPath = Join-Path $rootPath 'mastery/local/INDEX.md'
    $graphPath = Join-Path $rootPath 'knowledge/graph/INDEX.md'
    $candidateSnapshot = Get-OptionalTextSnapshot -Path $candidatePath
    $indexSnapshot = Get-OptionalTextSnapshot -Path $indexPath
    $graphSnapshot = Get-OptionalTextSnapshot -Path $graphPath
    $rollbackFailed = $false
    try {
        Write-ModelProjectMasteryAtomicText -Path $methodPath -Content $methodContent -CreateNew
        Write-ModelProjectMasteryAtomicText -Path $candidatePath -Content $updatedCandidate
        [void](Update-ModelProjectMasteryIndex -Root $rootPath -Mode Write)
        Invoke-TrustedScript -Name 'update-knowledge-graph.ps1' -Arguments @('-Root', $rootPath, '-Mode', 'Write')
        Invoke-TrustedScript -Name 'verify-knowledge.ps1' -Arguments @('-Root', $rootPath)
        Invoke-TrustedScript -Name 'update-mastery-index.ps1' -Arguments @('-Root', $rootPath, '-Mode', 'Check')
        Invoke-TrustedScript -Name 'update-knowledge-graph.ps1' -Arguments @('-Root', $rootPath, '-Mode', 'Check')
        Invoke-TrustedScript -Name 'verify-structure.ps1' -Arguments @('-Root', $rootPath, '-Mode', 'GeneratedProject')
    }
    catch {
        if ([string]::IsNullOrWhiteSpace([string]$script:masteryApplyDetail)) {
            $script:masteryApplyDetail = [string]$_.Exception.Message
        }
        try { Restore-TextSnapshot -Path $candidatePath -Snapshot $candidateSnapshot } catch { $rollbackFailed = $true }
        try { Restore-TextSnapshot -Path $indexPath -Snapshot $indexSnapshot } catch { $rollbackFailed = $true }
        try { Restore-TextSnapshot -Path $graphPath -Snapshot $graphSnapshot } catch { $rollbackFailed = $true }
        try {
            if (Test-Path -LiteralPath $methodPath -PathType Leaf) { [System.IO.File]::Delete($methodPath) }
        }
        catch { $rollbackFailed = $true }
        if ($rollbackFailed) { throw 'blocked: mastery-apply-rollback-incomplete' }
        throw 'blocked: mastery-apply-rollback'
    }

    Write-Output "APPLIED [$CandidateId]: $methodRelative"
    Write-Output "METHOD_ID=$methodId"
    Write-Output "CANDIDATE_REF=$candidateRelative"
    Write-Output 'KNOWLEDGE_GRAPH=updated'
}
catch {
    throw
}
