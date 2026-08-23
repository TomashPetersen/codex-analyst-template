[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$repositoryRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$verifierPath = Join-Path $PSScriptRoot 'verify-knowledge.ps1'
$runTemplateSeedRoot = Join-Path $repositoryRoot '.agents\skills\startup-researcher\assets\run-template'
$runTemplateFileNames = @(
    'brief.md',
    'queries.md',
    'evidence.jsonl',
    'candidates.md',
    'red-team.md',
    'decision.md'
)
$temporaryPrefix = 'ModelProjectArtifactHarness-'
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Write-FixtureText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $fullPath = Join-Path $Root $RelativePath.Replace('/', '\')
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($fullPath, $Content, $utf8NoBom)
}

function Get-RelativeFixturePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $rootWithSeparator = $Root.TrimEnd([char[]]'\/') + [System.IO.Path]::DirectorySeparatorChar
    $rootUri = [System.Uri]::new($rootWithSeparator)
    $pathUri = [System.Uri]::new($FullPath)
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function Get-TreeFingerprint {
    param([Parameter(Mandatory = $true)][string]$Root)

    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd([char[]]'\/')
    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($item in (Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force)) {
        $relative = Get-RelativeFixturePath -Root $resolvedRoot -FullPath $item.FullName
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "SHA tree oracle отказался читать reparse point: $relative"
        }
        if ($item.PSIsContainer) {
            $rows.Add("D|$relative") | Out-Null
            continue
        }
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $rows.Add("F|$relative|$($item.Length)|$hash") | Out-Null
    }

    $ordered = $rows.ToArray()
    [array]::Sort($ordered, [System.StringComparer]::Ordinal)
    $payload = [string]::Join("`n", $ordered)
    $bytes = $utf8NoBom.GetBytes($payload)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-PowerShellExecutable {
    $current = (Get-Process -Id $PID).Path
    if (-not [string]::IsNullOrWhiteSpace($current) -and (Test-Path -LiteralPath $current -PathType Leaf)) {
        return $current
    }
    foreach ($name in @('pwsh', 'powershell')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
    }
    throw 'Не найден PowerShell executable для child-process проверки.'
}

function Add-ProcessArgument {
    param(
        [Parameter(Mandatory = $true)]$StartInfo,
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Fallback
    )

    if ($null -ne $StartInfo.ArgumentList) {
        $StartInfo.ArgumentList.Add($Value)
    }
    else {
        $Fallback.Add($Value) | Out-Null
    }
}

function ConvertTo-NativeArgumentString {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    return (($Arguments | ForEach-Object {
        if ($_ -notmatch '[\s"]') { return $_ }
        $escaped = [regex]::Replace($_, '(\\*)"', '$1$1\"')
        $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
        return '"' + $escaped + '"'
    }) -join ' ')
}

function Invoke-PublicVerifier {
    param([Parameter(Mandatory = $true)][string]$FixtureRoot)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = Get-PowerShellExecutable
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $fallback = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $verifierPath, '-Root', $FixtureRoot)) {
        Add-ProcessArgument -StartInfo $startInfo -Value $argument -Fallback $fallback
    }
    if ($fallback.Count -gt 0) {
        $startInfo.Arguments = ConvertTo-NativeArgumentString -Arguments $fallback.ToArray()
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Не удалось запустить public verifier.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdout
            Stderr = $stderr
        }
    }
    finally {
        $process.Dispose()
    }
}

function Copy-RunTemplateSeed {
    param([Parameter(Mandatory = $true)][string]$FixtureRoot)

    if (-not (Test-Path -LiteralPath $runTemplateSeedRoot -PathType Container)) {
        throw "Portable run-template seed отсутствует: $runTemplateSeedRoot"
    }
    $unexpectedDirectories = @(Get-ChildItem -LiteralPath $runTemplateSeedRoot -Directory -Force)
    if ($unexpectedDirectories.Count -gt 0) {
        throw 'Portable run-template seed содержит недопустимые вложенные каталоги.'
    }

    $seedFiles = @(Get-ChildItem -LiteralPath $runTemplateSeedRoot -File -Force)
    $actualNames = @($seedFiles | ForEach-Object { $_.Name })
    $expectedNames = @($runTemplateFileNames)
    [array]::Sort($actualNames, [System.StringComparer]::Ordinal)
    [array]::Sort($expectedNames, [System.StringComparer]::Ordinal)
    if ($actualNames.Count -ne $expectedNames.Count -or
        [string]::Join("`n", $actualNames) -cne [string]::Join("`n", $expectedNames)) {
        throw 'Portable run-template seed не соответствует exact six-file inventory.'
    }

    $destinationRoot = Join-Path $FixtureRoot '.agents\skills\startup-researcher\assets\run-template'
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    foreach ($name in $runTemplateFileNames) {
        $source = Join-Path $runTemplateSeedRoot $name
        $sourceItem = Get-Item -LiteralPath $source -Force
        if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Portable run-template seed file является reparse point: $name"
        }
        $destination = Join-Path $destinationRoot $name
        [System.IO.File]::WriteAllBytes($destination, [System.IO.File]::ReadAllBytes($source))
        $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($sourceHash -cne $destinationHash) {
            throw "SHA mismatch при копировании portable run-template seed: $name"
        }
    }
}

function New-BaseFixture {
    param([Parameter(Mandatory = $true)][string]$Root)

    $fixtureProjectId = '11111111' + '-1111-4111-8111-' + '111111111111'
    Write-FixtureText -Root $Root -RelativePath 'PROJECT.md' -Content @"
---
repository_kind: generated-project
project_status: active
project_id: $fixtureProjectId
knowledge_contract_version: 1
knowledge_capture_mode: report-only
---

# Artifact fixture

## Паспорт

- Slug: artifact-fixture
- Описание: Проверка связности knowledge artifacts.
- Владелец: `fixture-owner`
- Стадия: исследование
- Канонический репозиторий: этот репозиторий
- Дата последней проверки паспорта: 2026-08-01

## Проблема

Knowledge artifacts должны ссылаться только на существующие и допустимые сущности.

## Проверяемая гипотеза

Public verifier обнаруживает нарушение связности артефактов.

## Границы

Входит:

- Проверка ADR, plans и retrospectives.

Не входит:

- Выбор технического стека.

## Критерии успеха и провала

- Успех: положительные fixtures проходят, отрицательные блокируются.
- Провал: нарушение контракта получает false-green.
- Срок или объем проверки: один harness run.
- Кто принимает финальное решение: fixture-owner.

## Стек и эксплуатация

- Стек: не требуется для research-stage fixture.

## Связи

- [Карта](INDEX.md)
"@
    Write-FixtureText -Root $Root -RelativePath 'docs/source.md' -Content "# Source`n"
    Write-FixtureText -Root $Root -RelativePath 'docs/target.md' -Content "# Target`n`n## Knowledge`n"
    Copy-RunTemplateSeed -FixtureRoot $Root
}

function Update-RootIndex {
    param([Parameter(Mandatory = $true)][string]$Root)

    $links = [System.Collections.Generic.List[string]]::new()
    $links.Add('- [Project](PROJECT.md)') | Out-Null
    foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $Root 'docs') -Recurse -File -Filter '*.md' | Sort-Object FullName)) {
        $relative = Get-RelativeFixturePath -Root $Root -FullPath $file.FullName
        $links.Add("- [$relative]($relative)") | Out-Null
    }
    $assetRoot = Join-Path $Root '.agents\skills\startup-researcher\assets\run-template'
    foreach ($file in (Get-ChildItem -LiteralPath $assetRoot -File -Filter '*.md' | Sort-Object FullName)) {
        $relative = Get-RelativeFixturePath -Root $Root -FullPath $file.FullName
        $links.Add("- [$relative]($relative)") | Out-Null
    }
    Write-FixtureText -Root $Root -RelativePath 'INDEX.md' -Content ("# Index`n`n" + ($links -join "`n") + "`n")
}

function Add-TargetBacklink {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$CandidateId
    )

    $targetPath = Join-Path $Root 'docs\target.md'
    $existing = [System.IO.File]::ReadAllText($targetPath)
    $relativeCandidate = "../knowledge/candidates/2026/$CandidateId.md"
    [System.IO.File]::WriteAllText(
        $targetPath,
        $existing.TrimEnd() + "`n`n[$CandidateId]($relativeCandidate)`n",
        $utf8NoBom
    )
}

function Write-Candidate {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$ClaimKey,
        [ValidateSet('ready', 'applied', 'dismissed')][string]$State = 'ready',
        [string]$AuthorityRef = 'policy:knowledge-contract-v1',
        [string]$TargetRef = 'docs/target.md#knowledge',
        [string]$AppliedAt = 'null',
        [string]$DismissReason = 'null'
    )

    Write-FixtureText -Root $Root -RelativePath "knowledge/candidates/2026/$Id.md" -Content @"
---
id: '$Id'
state: $State
type: decision
owner_scope: project
domain: architecture
claim_key: $ClaimKey
target_ref: '$TargetRef'
source_refs:
  - 'https://example.com/evidence'
conflict_refs: []
confidence: high
capture_basis: repo-derived
data_class: internal
created_at: '2026-07-30T12:00:00+04:00'
review_due: '2099-12-31'
authority_ref: '$AuthorityRef'
applied_at: $AppliedAt
dismiss_reason: $DismissReason
supersedes: null
---

# Fixture claim $ClaimKey

## Основание

Проверяемое основание.

## Предлагаемое изменение

Добавить проверяемое правило.

## Проверка дублей и противоречий

Дубли и противоречия не найдены.

## Обоснование lifecycle

- Статус: $State
"@
    if ($State -ceq 'applied') {
        Add-TargetBacklink -Root $Root -CandidateId $Id
    }
}

function Write-Decision {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FileName,
        [ValidateSet('proposed', 'accepted', 'superseded', 'rejected')][string]$Status = 'accepted',
        [AllowNull()][string]$KnowledgeOutcome = 'none',
        [string[]]$CandidateIds = @(),
        [string[]]$AffectedCanon = @(),
        [string[]]$Supersedes = @(),
        [AllowNull()][string]$BlockedReason = $null
    )

    $outcomeYaml = if ($null -eq $KnowledgeOutcome) { 'null' } else { $KnowledgeOutcome }
    $candidateYaml = if ($CandidateIds.Count -eq 0) { '[]' } else { "`n" + (($CandidateIds | ForEach-Object { "  - $_" }) -join "`n") }
    $affectedYaml = if ($AffectedCanon.Count -eq 0) { '[]' } else { "`n" + (($AffectedCanon | ForEach-Object { "  - $_" }) -join "`n") }
    $supersedesYaml = if ($Supersedes.Count -eq 0) { '[]' } else { "`n" + (($Supersedes | ForEach-Object { "  - $_" }) -join "`n") }
    $reasonYaml = if ($null -eq $BlockedReason) { 'null' } else { "'$BlockedReason'" }
    Write-FixtureText -Root $Root -RelativePath "docs/decisions/$FileName" -Content @"
---
artifact_kind: decision
status: $Status
knowledge_outcome: $outcomeYaml
candidate_ids: $candidateYaml
affected_canon: $affectedYaml
supersedes: $supersedesYaml
blocked_reason: $reasonYaml
---

# Decision $FileName

## Контекст и владелец

Fixture owner.

## Решение

Проверить машинные ссылки.
"@
}

function Write-Plan {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FileName,
        [ValidateSet('planned', 'in-progress', 'complete', 'blocked')][string]$Status = 'complete',
        [AllowNull()][string]$KnowledgeOutcome = 'none',
        [string[]]$CandidateIds = @(),
        [string[]]$AffectedCanon = @(),
        [AllowNull()][string]$BlockedReason = $null
    )

    $outcomeYaml = if ($null -eq $KnowledgeOutcome) { 'null' } else { $KnowledgeOutcome }
    $candidateYaml = if ($CandidateIds.Count -eq 0) { '[]' } else { "`n" + (($CandidateIds | ForEach-Object { "  - $_" }) -join "`n") }
    $affectedYaml = if ($AffectedCanon.Count -eq 0) { '[]' } else { "`n" + (($AffectedCanon | ForEach-Object { "  - $_" }) -join "`n") }
    $reasonYaml = if ($null -eq $BlockedReason) { 'null' } else { "'$BlockedReason'" }
    Write-FixtureText -Root $Root -RelativePath "plans/$FileName" -Content @"
---
artifact_kind: plan
status: $Status
knowledge_outcome: $outcomeYaml
candidate_ids: $candidateYaml
affected_canon: $affectedYaml
blocked_reason: $reasonYaml
---

# Plan $FileName

## Цель

Проверить historical knowledge outcome.

## Проверки

- Public verifier вызван как child process.
"@
}

function Write-Retrospective {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FileName,
        [AllowNull()][string]$KnowledgeOutcome = 'none',
        [string[]]$CandidateIds = @(),
        [string[]]$AffectedCanon = @(),
        [AllowNull()][string]$BlockedReason = $null
    )

    $outcomeYaml = if ($null -eq $KnowledgeOutcome) { 'null' } else { $KnowledgeOutcome }
    $candidateYaml = if ($CandidateIds.Count -eq 0) { '[]' } else { "`n" + (($CandidateIds | ForEach-Object { "  - $_" }) -join "`n") }
    $affectedYaml = if ($AffectedCanon.Count -eq 0) { '[]' } else { "`n" + (($AffectedCanon | ForEach-Object { "  - $_" }) -join "`n") }
    $reasonYaml = if ($null -eq $BlockedReason) { 'null' } else { "'$BlockedReason'" }
    Write-FixtureText -Root $Root -RelativePath "retrospectives/$FileName" -Content @"
---
artifact_kind: retrospective
knowledge_outcome: $outcomeYaml
candidate_ids: $candidateYaml
affected_canon: $affectedYaml
blocked_reason: $reasonYaml
---

# Retrospective $FileName

## Что проверено

Historical knowledge outcome проверен public verifier.
"@
}

function Assert-CaseResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][int]$ExpectedExitCode,
        [Parameter(Mandatory = $true)][string[]]$StdoutPatterns,
        [Parameter(Mandatory = $true)][string]$BeforeFingerprint,
        [Parameter(Mandatory = $true)][string]$AfterFingerprint
    )

    $caseFailures = [System.Collections.Generic.List[string]]::new()
    if ($Result.ExitCode -ne $ExpectedExitCode) {
        $caseFailures.Add("exit=$($Result.ExitCode), ожидался $ExpectedExitCode") | Out-Null
    }
    if (-not [string]::IsNullOrEmpty($Result.Stderr)) {
        $caseFailures.Add('stderr должен быть пустым') | Out-Null
    }
    foreach ($pattern in $StdoutPatterns) {
        if ($Result.Stdout -notmatch $pattern) {
            $caseFailures.Add("stdout не содержит /$pattern/") | Out-Null
        }
    }
    if ($ExpectedExitCode -eq 0 -and $Result.Stdout -match '(?m)^FAIL:') {
        $caseFailures.Add('positive case содержит FAIL в stdout') | Out-Null
    }
    if ($ExpectedExitCode -ne 0 -and $Result.Stdout -match '(?m)^PASS:') {
        $caseFailures.Add('negative case содержит PASS в stdout') | Out-Null
    }
    if ($BeforeFingerprint -cne $AfterFingerprint) {
        $caseFailures.Add('public verifier изменил SHA tree fixture') | Out-Null
    }

    if ($caseFailures.Count -eq 0) {
        $passes.Add($Name) | Out-Null
        Write-Host "PASS $Name"
        return
    }

    $summary = $caseFailures -join '; '
    $failures.Add("$Name`: $summary") | Out-Null
    Write-Host "FAIL $Name`: $summary"
    $safeStdout = ([string]$Result.Stdout).Trim()
    $safeStderr = ([string]$Result.Stderr).Trim()
    if (-not [string]::IsNullOrWhiteSpace($safeStdout)) { Write-Host "  stdout: $safeStdout" }
    if (-not [string]::IsNullOrWhiteSpace($safeStderr)) { Write-Host "  stderr: $safeStderr" }
}

function Invoke-ArtifactCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Arrange,
        [Parameter(Mandatory = $true)][int]$ExpectedExitCode,
        [Parameter(Mandatory = $true)][string[]]$StdoutPatterns
    )

    $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ($temporaryPrefix + [guid]::NewGuid().ToString('N'))
    $expectedParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]'\/')
    try {
        New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
        New-BaseFixture -Root $temporaryRoot
        & $Arrange $temporaryRoot
        Update-RootIndex -Root $temporaryRoot
        $before = Get-TreeFingerprint -Root $temporaryRoot
        $result = Invoke-PublicVerifier -FixtureRoot $temporaryRoot
        $after = Get-TreeFingerprint -Root $temporaryRoot
        Assert-CaseResult `
            -Name $Name `
            -Result $result `
            -ExpectedExitCode $ExpectedExitCode `
            -StdoutPatterns $StdoutPatterns `
            -BeforeFingerprint $before `
            -AfterFingerprint $after
    }
    catch {
        $failures.Add("$Name`: harness exception $($_.Exception.Message)") | Out-Null
        Write-Host "FAIL $Name`: harness exception $($_.Exception.Message)"
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
            $resolved = (Resolve-Path -LiteralPath $temporaryRoot).Path
            $leaf = Split-Path -Leaf $resolved
            $parent = Split-Path -Parent $resolved
            if ($parent -cne $expectedParent -or -not $leaf.StartsWith($temporaryPrefix, [System.StringComparison]::Ordinal)) {
                throw "Отказ от очистки небезопасного harness path: $resolved"
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

if (-not (Test-Path -LiteralPath $verifierPath -PathType Leaf)) {
    throw "Public verifier не найден: $verifierPath"
}

Invoke-ArtifactCase -Name 'A55 accepted ADR blocks missing candidate ID' -ExpectedExitCode 1 -StdoutPatterns @(
    '(?m)^FAIL: semantic knowledge gate',
    '(?i)(?:candidate_ids|candidate).*(?:missing|absent|отсутств|не существ|broken)'
) -Arrange {
    param($root)
    $missing = 'KC-20260730-120000-bad0bad0'
    Write-Decision -Root $root -FileName 'ADR-A55.md' -KnowledgeOutcome "applied:$missing" -CandidateIds @($missing) -AffectedCanon @('docs/target.md')
}

Invoke-ArtifactCase -Name 'A56 blocks broken affected canon' -ExpectedExitCode 1 -StdoutPatterns @(
    '(?m)^FAIL: semantic knowledge gate',
    '(?i)affected_canon'
) -Arrange {
    param($root)
    $id = 'KC-20260730-120001-a56a56a5'
    Write-Decision -Root $root -FileName 'ADR-A56.md' -KnowledgeOutcome "applied:$id" -CandidateIds @($id) -AffectedCanon @('docs/missing.md')
    Write-Candidate -Root $root -Id $id -ClaimKey 'a56-affected-canon' -State applied -AuthorityRef 'docs/decisions/ADR-A56.md' -AppliedAt "'2026-07-30T12:05:00+04:00'"
}

Invoke-ArtifactCase -Name 'A57 blocks ADR self supersedes' -ExpectedExitCode 1 -StdoutPatterns @(
    '(?m)^FAIL: semantic knowledge gate',
    '(?i)(?:decision|adr|supersedes).*(?:self|cycle|cyclic|цикл|сам)'
) -Arrange {
    param($root)
    Write-Decision -Root $root -FileName 'ADR-A57-self.md' -Supersedes @('docs/decisions/ADR-A57-self.md')
}

Invoke-ArtifactCase -Name 'A57 blocks two-node ADR cycle' -ExpectedExitCode 1 -StdoutPatterns @(
    '(?m)^FAIL: semantic knowledge gate',
    '(?i)(?:decision|adr|supersedes).*(?:cycle|cyclic|цикл)'
) -Arrange {
    param($root)
    Write-Decision -Root $root -FileName 'ADR-A57-one.md' -Supersedes @('docs/decisions/ADR-A57-two.md')
    Write-Decision -Root $root -FileName 'ADR-A57-two.md' -Supersedes @('docs/decisions/ADR-A57-one.md')
}

Invoke-ArtifactCase -Name 'A58 valid accepted ADR passes' -ExpectedExitCode 0 -StdoutPatterns @(
    '(?m)^PASS: semantic knowledge gate\.\r?$'
) -Arrange {
    param($root)
    $id = 'KC-20260730-120002-a58a58a5'
    Write-Decision -Root $root -FileName 'ADR-A58.md' -KnowledgeOutcome "applied:$id" -CandidateIds @($id) -AffectedCanon @('docs/target.md')
    Write-Candidate -Root $root -Id $id -ClaimKey 'a58-valid-adr' -State applied -AuthorityRef 'docs/decisions/ADR-A58.md' -AppliedAt "'2026-07-30T12:05:00+04:00'"
}

Invoke-ArtifactCase -Name 'A59 complete plan blocks null outcome' -ExpectedExitCode 1 -StdoutPatterns @(
    '(?m)^FAIL: semantic knowledge gate',
    '(?i)(?:plans/|plan|knowledge_outcome)'
) -Arrange {
    param($root)
    Write-Plan -Root $root -FileName 'A59-null.md' -KnowledgeOutcome $null
}

Invoke-ArtifactCase -Name 'A59 complete plan blocks invalid outcome' -ExpectedExitCode 1 -StdoutPatterns @(
    '(?m)^FAIL: semantic knowledge gate',
    '(?i)(?:plans/|plan|knowledge_outcome)'
) -Arrange {
    param($root)
    Write-Plan -Root $root -FileName 'A59-invalid.md' -KnowledgeOutcome 'invalid-outcome'
}

Invoke-ArtifactCase -Name 'A60 complete plan blocks missing candidate ID' -ExpectedExitCode 1 -StdoutPatterns @(
    '(?m)^FAIL: semantic knowledge gate',
    '(?i)(?:candidate_ids|candidate).*(?:missing|absent|отсутств|не существ|broken)'
) -Arrange {
    param($root)
    $missing = 'KC-20260730-120003-bad0bad0'
    Write-Plan -Root $root -FileName 'A60-missing-candidate.md' -KnowledgeOutcome "ready:$missing" -CandidateIds @($missing)
}

Invoke-ArtifactCase -Name 'A61 retrospective blocks missing candidate ID' -ExpectedExitCode 1 -StdoutPatterns @(
    '(?m)^FAIL: semantic knowledge gate',
    '(?i)(?:candidate_ids|candidate).*(?:missing|absent|отсутств|не существ|broken)'
) -Arrange {
    param($root)
    $missing = 'KC-20260730-120004-bad0bad0'
    Write-Retrospective -Root $root -FileName 'A61-missing-candidate.md' -KnowledgeOutcome "ready:$missing" -CandidateIds @($missing)
}

Invoke-ArtifactCase -Name 'A62 blocked plan requires reason' -ExpectedExitCode 1 -StdoutPatterns @(
    '(?m)^FAIL: semantic knowledge gate',
    '(?i)blocked_reason'
) -Arrange {
    param($root)
    Write-Plan -Root $root -FileName 'A62-blocked-without-reason.md' -Status blocked -KnowledgeOutcome 'blocked' -BlockedReason $null
}

Invoke-ArtifactCase -Name 'A63 historical ready remains valid after applied' -ExpectedExitCode 0 -StdoutPatterns @(
    '(?m)^PASS: semantic knowledge gate\.\r?$'
) -Arrange {
    param($root)
    $id = 'KC-20260730-120005-a63a63a5'
    Write-Decision -Root $root -FileName 'ADR-A63-applied.md' -KnowledgeOutcome "applied:$id" -CandidateIds @($id) -AffectedCanon @('docs/target.md')
    Write-Candidate -Root $root -Id $id -ClaimKey 'a63-applied-history' -State applied -AuthorityRef 'docs/decisions/ADR-A63-applied.md' -AppliedAt "'2026-07-30T12:05:00+04:00'"
    Write-Plan -Root $root -FileName 'A63-ready-after-applied.md' -KnowledgeOutcome "ready:$id" -CandidateIds @($id)
}

Invoke-ArtifactCase -Name 'A63 historical ready remains valid after dismissed' -ExpectedExitCode 0 -StdoutPatterns @(
    '(?m)^PASS: semantic knowledge gate\.\r?$'
) -Arrange {
    param($root)
    $id = 'KC-20260730-120006-a63d63d6'
    Write-Candidate -Root $root -Id $id -ClaimKey 'a63-dismissed-history' -State dismissed -AuthorityRef 'user-request:artifact-harness' -DismissReason 'rejected'
    Write-Retrospective -Root $root -FileName 'A63-ready-after-dismissed.md' -KnowledgeOutcome "ready:$id" -CandidateIds @($id)
}

Invoke-ArtifactCase -Name 'A64 historical applied requires currently applied candidate' -ExpectedExitCode 1 -StdoutPatterns @(
    '(?m)^FAIL: semantic knowledge gate',
    '(?i)(?:applied.*candidate|candidate.*applied|knowledge_outcome)'
) -Arrange {
    param($root)
    $id = 'KC-20260730-120007-a64a64a6'
    Write-Candidate -Root $root -Id $id -ClaimKey 'a64-ready-not-applied' -State ready
    Write-Retrospective -Root $root -FileName 'A64-applied-requires-applied.md' -KnowledgeOutcome "applied:$id" -CandidateIds @($id) -AffectedCanon @('docs/target.md')
}

Invoke-ArtifactCase -Name 'A65 analysis run is forbidden in affected_canon' -ExpectedExitCode 1 -StdoutPatterns @(
    '(?m)^FAIL: semantic knowledge gate',
    '(?i)affected_canon.*canonical zone'
) -Arrange {
    param($root)
    $runRef = 'analysis/runs/RUN-20260815-120000-artifact-case-a1b2c3/decision.md'
    Write-FixtureText -Root $root -RelativePath $runRef -Content "# Decision`n"
    Write-Plan -Root $root -FileName 'A65-analysis-affected.md' -AffectedCanon @($runRef)
}

Invoke-ArtifactCase -Name 'A65 analysis run is forbidden as candidate target_ref' -ExpectedExitCode 1 -StdoutPatterns @(
    '(?m)^FAIL: semantic knowledge gate',
    '(?i)target_ref.*рабочую'
) -Arrange {
    param($root)
    $runRef = 'analysis/runs/RUN-20260815-120001-artifact-case-d4e5f6/decision.md'
    Write-FixtureText -Root $root -RelativePath $runRef -Content "# Decision`n"
    Write-Candidate -Root $root -Id 'KC-20260730-120008-a65a65a6' -ClaimKey 'a65-analysis-target' -TargetRef $runRef
}

Write-Host ("Artifact harness: pass={0}, fail={1}." -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "- $failure" }
    exit 1
}

exit 0
