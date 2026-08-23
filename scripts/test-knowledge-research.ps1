[CmdletBinding()]
param(
    [string]$Root = '',

    [ValidateSet('A43', 'A44', 'A45', 'A46', 'A47', 'A48', 'A49', 'A50', 'A51', 'A52', 'A53', 'A54')]
    [string[]]$CaseId = @(
        'A43', 'A44', 'A45', 'A46', 'A47', 'A48',
        'A49', 'A50', 'A51', 'A52', 'A53', 'A54'
    ),

    [ValidateRange(30, 600)]
    [int]$TimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'
$utf8Bom = [System.Text.UTF8Encoding]::new($true)
$fixturePrefix = 'ModelProjectResearch-'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ($fixturePrefix + [guid]::NewGuid().ToString('N'))
$harnessExitCode = 1
$expectedRunFiles = @(
    'brief.md',
    'candidates.md',
    'decision.md',
    'evidence.jsonl',
    'queries.md',
    'red-team.md'
)

function ConvertTo-ProcessArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value.IndexOf([char]0) -ge 0 -or $Value -match '[\r\n]') {
        throw 'HARNESS-UNSAFE-CHILD-ARGUMENT'
    }
    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s&()^|<>"]') { return $Value }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Stop-ChildProcessTree {
    param([Parameter(Mandatory = $true)][System.Diagnostics.Process]$Process)

    try {
        if ($Process.HasExited) { return }
    }
    catch { return }

    $taskkillPath = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    if (Test-Path -LiteralPath $taskkillPath -PathType Leaf) {
        $killInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $killInfo.FileName = $taskkillPath
        $killInfo.Arguments = "/PID $($Process.Id) /T /F"
        $killInfo.UseShellExecute = $false
        $killInfo.CreateNoWindow = $true
        $killProcess = [System.Diagnostics.Process]::new()
        $killProcess.StartInfo = $killInfo
        try {
            if ($killProcess.Start()) {
                if (-not $killProcess.WaitForExit(10000)) {
                    try { $killProcess.Kill() } catch { }
                }
            }
        }
        catch { }
        finally { $killProcess.Dispose() }
    }
    try {
        if (-not $Process.HasExited) { $Process.Kill() }
    }
    catch { }
}

function Invoke-PowerShellChild {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][int]$Timeout
    )

    $hostPath = (Get-Process -Id $PID).Path
    $allArguments = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $ScriptPath
    ) + $Arguments

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $hostPath
    $startInfo.Arguments = (($allArguments | ForEach-Object {
        ConvertTo-ProcessArgument ([string]$_)
    }) -join ' ')
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'HARNESS-CHILD-START'
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($Timeout * 1000)
        if ($timedOut) {
            Stop-ChildProcessTree -Process $process
            [void]$process.WaitForExit(10000)
        }
        else { $process.WaitForExit() }

        $streamTasks = [System.Threading.Tasks.Task[]]@($stdoutTask, $stderrTask)
        $streamsCompleted = $false
        try { $streamsCompleted = [System.Threading.Tasks.Task]::WaitAll($streamTasks, 10000) }
        catch { $streamsCompleted = $false }
        $stdout = if ($streamsCompleted) { [string]$stdoutTask.Result } else { '<bounded-stream-collection-timeout>' }
        $stderr = if ($streamsCompleted) { [string]$stderrTask.Result } else { '<bounded-stream-collection-timeout>' }
        return [pscustomobject]@{
            ExitCode = $(if ($timedOut) { 124 } else { [int]$process.ExitCode })
            Stdout = $stdout
            Stderr = $stderr
            TimedOut = $timedOut
            StreamTimedOut = (-not $streamsCompleted)
        }
    }
    finally {
        $process.Dispose()
    }
}

function Write-Utf8BomFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n", "`n"), $utf8Bom)
}

function Get-TreeHashSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $canonicalRoot = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    $gitRoot = Join-Path $canonicalRoot '.git'
    return @(
        Get-ChildItem -LiteralPath $canonicalRoot -Recurse -Force |
            Where-Object {
                -not $_.FullName.Equals($gitRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
                -not $_.FullName.StartsWith(
                    $gitRoot + [System.IO.Path]::DirectorySeparatorChar,
                    [System.StringComparison]::OrdinalIgnoreCase
                )
            } |
            ForEach-Object {
                $relative = $_.FullName.Substring($canonicalRoot.Length + 1).Replace('\', '/')
                $isReparse = ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
                if ($_.PSIsContainer) {
                    'D|{0}|reparse={1}' -f $relative, $isReparse
                }
                else {
                    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    'F|{0}|{1}|{2}|reparse={3}' -f $relative, $_.Length, $hash, $isReparse
                }
            } |
            Sort-Object
    )
}

function Assert-NoVerifierLeftovers {
    param(
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $canonicalRoot = [System.IO.Path]::GetFullPath($CaseRoot).TrimEnd([char[]]'\/')
    $gitRoot = Join-Path $canonicalRoot '.git'
    $leftovers = @(
        Get-ChildItem -LiteralPath $canonicalRoot -Recurse -Force |
            Where-Object {
                -not $_.FullName.Equals($gitRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
                -not $_.FullName.StartsWith(
                    $gitRoot + [System.IO.Path]::DirectorySeparatorChar,
                    [System.StringComparison]::OrdinalIgnoreCase
                ) -and
                (
                    $_.Name -match '(?i)(?:\.lock|\.lck|\.tmp|\.temp|\.draft|\.partial)$' -or
                    $_.Name -match '(?i)^\.(?:locks?|tmp|temp|drafts?|partial)$'
                )
            }
    )
    if ($leftovers.Count -gt 0) {
        throw "${Name}: verifier left a lock, temp, draft, or partial artifact."
    }
}

function Assert-TreeUnchanged {
    param(
        [Parameter(Mandatory = $true)][string[]]$Before,
        [Parameter(Mandatory = $true)][string[]]$After,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (($Before -join "`n") -cne ($After -join "`n")) {
        throw "${Name}: public verifier mutated the fixture tree."
    }
}

function Get-RunFileNames {
    param([Parameter(Mandatory = $true)][string]$RunRoot)

    return @(
        Get-ChildItem -LiteralPath $RunRoot -File -Force |
            Select-Object -ExpandProperty Name |
            Sort-Object
    )
}

function Assert-ExactRunFiles {
    param(
        [Parameter(Mandatory = $true)][string]$RunRoot,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $actual = @(Get-RunFileNames -RunRoot $RunRoot)
    $sortedExpected = @($Expected | Sort-Object)
    if (($actual -join "`n") -cne ($sortedExpected -join "`n")) {
        throw "${Name}: fixture file oracle mismatch. expected=$($sortedExpected -join ',') actual=$($actual -join ',')"
    }
}

function Get-SafeChildSummary {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$FixturePath
    )

    $stdout = ([string]$Result.Stdout).Replace($FixturePath, '<fixture-root>')
    $stderr = ([string]$Result.Stderr).Replace($FixturePath, '<fixture-root>')
    return "exit=$($Result.ExitCode); timeout=$($Result.TimedOut); stream_timeout=$($Result.StreamTimedOut); stdout=$($stdout.Trim()); stderr=$($stderr.Trim())"
}

function Invoke-PublicVerifier {
    param([Parameter(Mandatory = $true)][string]$CaseRoot)

    return Invoke-PowerShellChild `
        -ScriptPath (Join-Path $CaseRoot 'scripts\verify-knowledge.ps1') `
        -Arguments @('-Root', $CaseRoot) `
        -WorkingDirectory $CaseRoot `
        -Timeout $TimeoutSeconds
}

function New-CaseRoot {
    param(
        [Parameter(Mandatory = $true)][string]$SeedRoot,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $caseRoot = Join-Path $fixtureRoot $Name
    Copy-Item -LiteralPath $SeedRoot -Destination $caseRoot -Recurse -Force
    return $caseRoot
}

function Get-RunAssetFiles {
    param([Parameter(Mandatory = $true)][string]$CaseRoot)

    $assetRoot = Join-Path $CaseRoot '.agents\skills\startup-researcher\assets\run-template'
    if (-not (Test-Path -LiteralPath $assetRoot -PathType Container)) {
        throw 'HARNESS-RUN-ASSET-ROOT-MISSING'
    }
    $assetFiles = @(
        Get-ChildItem -LiteralPath $assetRoot -File -Force |
            Sort-Object Name
    )
    $assetNames = @($assetFiles | Select-Object -ExpandProperty Name)
    if (($assetNames -join "`n") -cne (($expectedRunFiles | Sort-Object) -join "`n")) {
        throw "HARNESS-RUN-ASSET-CONTRACT: expected=$($expectedRunFiles -join ',') actual=$($assetNames -join ',')"
    }
    return $assetFiles
}

function Convert-ToValidRunText {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    $Text = $Text.Replace('`evidence:EVIDENCE_ID`', 'ссылку с префиксом `evidence:`')
    $Text = $Text.Replace('`evidence:<evidence_id>`', 'ссылку с префиксом `evidence:`')

    if ($Name -ceq 'brief.md') {
        $Text = $Text.Replace('- Дата запуска: `YYYY-MM-DD`', '- Дата запуска: `2026-08-01`')
        $Text = $Text.Replace('- Тип задачи: `поиск ниш | сравнение идей | deep dive | оценка проекта | refresh | аудит`', '- Тип задачи: `поиск ниш`')
        $Text = $Text.Replace('- Intent ID: `niche-discovery | idea-comparison | deep-dive | project-assessment | refresh | external-research-audit`', '- Intent ID: `niche-discovery`')
        $Text = $Text.Replace('- Глубина: `быстрый обзор | стандартное | глубокое`', '- Глубина: `быстрый обзор`')
        $Text = $Text.Replace('- Решение, которое должен поддержать ресерч:', '- Решение, которое должен поддержать ресерч: выбрать следующий тест')
        $Text = $Text.Replace('- Исследовательский вопрос:', '- Исследовательский вопрос: какой наблюдаемый сигнал нужен')
        $Text = $Text.Replace('- Основной baseline profile ref:', '- Основной baseline profile ref: mastery/researcher/bill-aulet.md')
        $Text = $Text.Replace('- Основной baseline method ref:', '- Основной baseline method ref: mastery/researcher/bill-aulet.md#метод-1-market-segmentation-и-выбор-beachhead')
        $Text = $Text.Replace('- Почему эти методы подходят:', '- Почему эти методы подходят: baseline соответствует intent')
    }
    elseif ($Name -ceq 'decision.md') {
        $Text = $Text.Replace('- Дата:', '- Дата: 2026-08-01')
        $Text = $Text.Replace('- Тип и глубина:', '- Тип и глубина: поиск ниш, быстрый обзор')
        $Text = $Text.Replace('- Intent ID:', '- Intent ID: niche-discovery')
        $Text = $Text.Replace('- Решение: `перейти к следующей проверке | сузить сегмент | переформулировать гипотезу | провести поведенческий тест | приостановить | отклонить | недостаточно данных | перспективный кандидат не найден`', '- Решение: `недостаточно данных`')
        $Text = $Text.Replace('- Основной baseline method ref:', '- Основной baseline method ref: mastery/researcher/bill-aulet.md#метод-1-market-segmentation-и-выбор-beachhead')
        $Text = $Text.Replace('- Краткое основание:', '- Краткое основание: недостаточно данных')
        $Text = $Text.Replace('- Критические противоречия:', '- Критические противоречия: нет')
        $Text = $Text.Replace('- Критические пробелы:', '- Критические пробелы: нет evidence')
        $Text = $Text.Replace('- Ближайший опровергающий тест:', '- Ближайший опровергающий тест: получить прямой сигнал')
        $Text = $Text.Replace('- Write intent: `none | automatic-capture | explicit-promotion`', '- Write intent: none')
        $Text = $Text.Replace('- Причина `blocked`: `не применимо | capture-disabled | report-only | shared-owner | missing-provenance | missing-diff-baseline | missing-git-baseline | unsafe-data | candidate-dismissed`', '- Причина `blocked`: не применимо')
        $Text = $Text.Replace('- Разрешение на удаление: `нет | прямая команда пользователя`', '- Разрешение на удаление: `нет`')
    }
    elseif ($Name -ceq 'queries.md') {
        $Text = $Text.Replace('- Дата проверки:', '- Дата проверки: 2026-08-01')
        $Text = $Text.Replace('- Logical source ID или класс:', '- Logical source ID или класс: logical:research/fixture')
    }
    return $Text
}

function New-ResearchRun {
    param(
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)][string[]]$IncludeFiles
    )

    $runRoot = Join-Path $CaseRoot 'research\runs\2026-08-01-research-harness'
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    $assetFiles = @(Get-RunAssetFiles -CaseRoot $CaseRoot)
    foreach ($asset in $assetFiles) {
        if ($asset.Name -cnotin $IncludeFiles) { continue }
        $text = [System.IO.File]::ReadAllText($asset.FullName)
        $text = Convert-ToValidRunText -Name $asset.Name -Text $text
        Write-Utf8BomFixture -Path (Join-Path $runRoot $asset.Name) -Content $text
    }
    return $runRoot
}

function New-EvidenceRow {
    param(
        [Parameter(Mandatory = $true)][string]$EvidenceId,
        [Parameter(Mandatory = $true)][string]$ClaimId,
        [Parameter(Mandatory = $true)][string]$OriginGroupId,
        [Parameter(Mandatory = $true)][string]$DatasetOrigin,
        [Parameter(Mandatory = $true)][string]$SourceLeaf,
        [Parameter(Mandatory = $true)][string]$Fingerprint
    )

    return [ordered]@{
        evidence_id = $EvidenceId
        claim_id = $ClaimId
        claim = 'Synthetic fixture observation.'
        claim_type = 'fact'
        stance = 'supports'
        source_url = "https://example.test/$SourceLeaf"
        source_title = 'Synthetic fixture source'
        publisher = 'Example Test Publisher'
        source_type = 'official-documentation'
        published_at = '2026-07-01'
        accessed_at = '2026-08-01'
        locator = 'section-fixture'
        observation = 'A deterministic non-personal observation for verifier regression.'
        directness = 'direct'
        origin_group_id = $OriginGroupId
        original_source_url = "https://example.test/$SourceLeaf"
        syndication_or_quote_of = ''
        dataset_origin = $DatasetOrigin
        content_fingerprint = $Fingerprint
        geography = 'global'
        time_scope = '2026'
        limitations = 'Synthetic source-only fixture; not a product claim.'
        participant_code = 'not-applicable'
        prompt_injection_detected = $false
    }
}

function Set-EvidenceRows {
    param(
        [Parameter(Mandatory = $true)][string]$RunRoot,
        [Parameter(Mandatory = $true)][object[]]$Rows
    )

    $lines = @(
        foreach ($row in $Rows) {
            ConvertTo-Json -InputObject $row -Compress -Depth 4
        }
    )
    $content = if ($lines.Count -eq 0) { "`n" } else { ($lines -join "`n") + "`n" }
    Write-Utf8BomFixture -Path (Join-Path $RunRoot 'evidence.jsonl') -Content $content
}

function Set-DecisionEvidenceRefs {
    param(
        [Parameter(Mandatory = $true)][string]$RunRoot,
        [Parameter(Mandatory = $true)][string[]]$EvidenceIds
    )

    $decisionPath = Join-Path $RunRoot 'decision.md'
    $text = [System.IO.File]::ReadAllText($decisionPath)
    $marker = "## Направления`n"
    if (-not $text.Contains($marker)) {
        throw 'HARNESS-DECISION-DIRECTION-MARKER-MISSING'
    }
    $refs = @($EvidenceIds | ForEach-Object { "evidence:$_" }) -join ', '
    if ($text -match '(?m)^- Fixture evidence refs:') {
        $text = [regex]::Replace(
            $text,
            '(?m)^- Fixture evidence refs:[^\r\n]*$',
            "- Fixture evidence refs: $refs"
        )
    }
    else {
        $text = $text.Replace($marker, "$marker`n- Fixture evidence refs: $refs`n")
    }
    Write-Utf8BomFixture -Path $decisionPath -Content $text
}

function Set-DecisionCandidateOutcome {
    param(
        [Parameter(Mandatory = $true)][string]$RunRoot,
        [Parameter(Mandatory = $true)][string[]]$CandidateIds,
        [ValidateSet('ready', 'applied')][string]$OutcomeKind = 'ready',
        [ValidateSet('automatic-capture', 'explicit-promotion')][string]$WriteIntent = 'automatic-capture',
        [string]$AuthorityRef = 'policy:knowledge-contract-v1',
        [string]$AffectedCanon = 'нет'
    )

    if ($CandidateIds.Count -eq 0) {
        throw 'HARNESS-CANDIDATE-OUTCOME-EMPTY'
    }
    $decisionPath = Join-Path $RunRoot 'decision.md'
    $text = [System.IO.File]::ReadAllText($decisionPath)
    $text = [regex]::Replace(
        $text,
        '(?m)^- Основной результат closeout:[^\r\n]*$',
        "- Основной результат closeout: ${OutcomeKind}:$($CandidateIds[0])"
    )
    $text = [regex]::Replace(
        $text,
        '(?m)^- Central candidate IDs в порядке влияния на решение:[^\r\n]*$',
        "- Central candidate IDs в порядке влияния на решение: [$($CandidateIds -join ', ')]"
    )
    $text = [regex]::Replace($text, '(?m)^- Write intent:[^\r\n]*$', "- Write intent: $WriteIntent")
    $text = [regex]::Replace($text, '(?m)^- Authority ref:[^\r\n]*$', "- Authority ref: $AuthorityRef")
    $text = [regex]::Replace($text, '(?m)^- Причина `blocked`:[^\r\n]*$', '- Причина `blocked`: не применимо')
    $text = [regex]::Replace($text, '(?m)^- Затронутый канон:[^\r\n]*$', "- Затронутый канон: $AffectedCanon")
    Write-Utf8BomFixture -Path $decisionPath -Content $text
}

function Set-DecisionBlockedOutcome {
    param(
        [Parameter(Mandatory = $true)][string]$RunRoot,
        [AllowEmptyString()][string]$BlockedReason = 'missing-provenance',
        [switch]$OmitBlockedReason
    )

    $decisionPath = Join-Path $RunRoot 'decision.md'
    $text = [System.IO.File]::ReadAllText($decisionPath)
    $text = [regex]::Replace($text, '(?m)^- Основной результат closeout:[^\r\n]*$', '- Основной результат closeout: blocked')
    $text = [regex]::Replace($text, '(?m)^- Write intent:[^\r\n]*$', '- Write intent: none')
    $text = [regex]::Replace($text, '(?m)^- Authority ref:[^\r\n]*$', '- Authority ref: null')
    $text = [regex]::Replace($text, '(?m)^- Central candidate IDs в порядке влияния на решение:[^\r\n]*$', '- Central candidate IDs в порядке влияния на решение: []')
    $text = [regex]::Replace($text, '(?m)^- Затронутый канон:[^\r\n]*$', '- Затронутый канон: `нет`')
    if ($OmitBlockedReason) {
        $text = [regex]::Replace($text, '(?m)^- Причина `blocked`:[^\r\n]*\r?\n', '')
    }
    else {
        $text = [regex]::Replace(
            $text,
            '(?m)^- Причина `blocked`:[^\r\n]*$',
            ('- Причина `blocked`: {0}' -f $BlockedReason)
        )
    }
    Write-Utf8BomFixture -Path $decisionPath -Content $text
}

function Write-ResearchCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)][string]$RunRelative,
        [Parameter(Mandatory = $true)][string]$CandidateId,
        [Parameter(Mandatory = $true)][string]$EvidenceId,
        [Parameter(Mandatory = $true)][string]$ClaimKey,
        [ValidateSet('ready', 'applied')][string]$State = 'ready',
        [string]$AuthorityRef = 'policy:knowledge-contract-v1'
    )

    $candidatePath = Join-Path $CaseRoot "knowledge\candidates\2026\$CandidateId.md"
    $appliedAt = if ($State -ceq 'applied') { '2026-08-01T00:01:00+04:00' } else { 'null' }
    $content = @"
---
id: $CandidateId
state: $State
type: fact
owner_scope: project
domain: research
claim_key: $ClaimKey
target_ref: idea/superidea.md#суперидея
source_refs:
  - $RunRelative/decision.md
  - evidence:$EvidenceId
conflict_refs: []
confidence: medium
capture_basis: research-derived
data_class: internal
created_at: 2026-08-01T00:00:00+04:00
review_due: null
authority_ref: $AuthorityRef
applied_at: $appliedAt
dismiss_reason: null
supersedes: null
---

# Synthetic research candidate

## Основание

The current synthetic run and evidence row support this regression-only claim.

## Предлагаемое изменение

No canonical write is performed by this ready candidate fixture.

## Проверка дублей и противоречий

- Поиск по канону: no duplicate.
- Поиск по candidates: no duplicate.
- Противоречия: none.

## Обоснование lifecycle

The fixture provenance is declared explicitly and verified through the public entrypoint.
"@
    Write-Utf8BomFixture -Path $candidatePath -Content $content
    return $candidatePath
}

function Add-CandidateBacklink {
    param(
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)][string]$CandidateId
    )

    $targetPath = Join-Path $CaseRoot 'idea\superidea.md'
    $text = [System.IO.File]::ReadAllText($targetPath)
    $relativeCandidate = "../knowledge/candidates/2026/$CandidateId.md"
    if (-not $text.Contains("($relativeCandidate)")) {
        $text = $text.TrimEnd() + "`n`n- [Applied fixture candidate]($relativeCandidate)`n"
        Write-Utf8BomFixture -Path $targetPath -Content $text
    }
}

function Set-ActiveProjectCaptureMode {
    param(
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)][ValidateSet('report-only', 'safe-local')][string]$CaptureMode
    )

    $projectPath = Join-Path $CaseRoot 'PROJECT.md'
    $existing = [System.IO.File]::ReadAllText($projectPath)
    $projectIdMatch = [regex]::Match($existing, '(?m)^project_id:[ \t]*(?<value>[^\r\n]+)[ \t]*$')
    if (-not $projectIdMatch.Success) {
        throw 'HARNESS-PROJECT-ID-MISSING'
    }
    $projectId = $projectIdMatch.Groups['value'].Value.Trim()
    $content = @"
---
repository_kind: generated-project
project_status: active
project_id: $projectId
knowledge_contract_version: 1
knowledge_capture_mode: $CaptureMode
---

# Research Harness Project

## Паспорт

- Slug: research-harness-project
- Описание: Synthetic generated project for research contract fixtures.
- Владелец: fixture-owner
- Стадия: исследование
- Канонический репозиторий: этот репозиторий
- Дата последней проверки паспорта: 2026-08-01

## Проблема

Проверить строгие machine-readable контракты research run на синтетических данных.

## Проверяемая гипотеза

Детерминированные public-CLI fixtures обнаруживают нарушение provenance без изменения дерева.

## Границы

Входит:

- Проверка локальных синтетических артефактов.

Не входит:

- Запись продуктовых данных или внешние действия.

## Критерии успеха и провала

- Успех: ожидаемые валидные fixtures проходят.
- Провал: хотя бы один отрицательный fixture принят.
- Срок или объем проверки: один локальный regression run.
- Кто принимает финальное решение: fixture-owner.
"@
    Write-Utf8BomFixture -Path $projectPath -Content $content
}

function New-FixtureGitHead {
    param([Parameter(Mandatory = $true)][string]$CaseRoot)

    $gitCommand = Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $gitCommand) {
        $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    if ($null -eq $gitCommand -or [string]::IsNullOrWhiteSpace([string]$gitCommand.Source)) {
        throw 'HARNESS-GIT-MISSING'
    }
    $addOutput = @(
        & $gitCommand.Source `
            -c core.fsmonitor=false `
            -c core.hooksPath=NUL `
            -C $CaseRoot `
            add -- PROJECT.md TEMPLATE-ORIGIN.md 2>&1
    )
    if ($LASTEXITCODE -ne 0) {
        throw "HARNESS-GIT-ADD: exit=$LASTEXITCODE output=$($addOutput -join ' ')"
    }

    $output = @(
        & $gitCommand.Source `
            -c core.fsmonitor=false `
            -c core.hooksPath=NUL `
            -c user.name=Fixture `
            -c user.email=fixture@example.test `
            -C $CaseRoot `
            commit -m fixture-baseline 2>&1
    )
    if ($LASTEXITCODE -ne 0) {
        throw "HARNESS-GIT-HEAD: exit=$LASTEXITCODE output=$($output -join ' ')"
    }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Add-LocalMethodFixture {
    param(
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)][string]$MethodId,
        [Parameter(Mandatory = $true)][ValidateSet('active', 'deprecated', 'superseded')][string]$Status,
        [Parameter(Mandatory = $true)][string]$VerifiedAt,
        [Parameter(Mandatory = $true)][string]$ReviewDue,
        [AllowNull()][string]$Supersedes = $null
    )

    $candidateRoot = Join-Path $CaseRoot 'knowledge/candidates'
    $candidateIdsBefore = @(
        Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter 'KC-*.md' -Force |
            ForEach-Object { $_.BaseName }
    )
    $candidateResult = Invoke-PowerShellChild `
        -ScriptPath (Join-Path $CaseRoot 'scripts/new-knowledge-candidate.ps1') `
        -Arguments @(
            '-Root', $CaseRoot,
            '-Type', 'method',
            '-Domain', 'mastery',
            '-ClaimKey', "method.$MethodId",
            '-TargetRef', 'mastery/local/INDEX.md#зарегистрированные-расширения',
            '-SourceRefs', 'PROJECT.md',
            '-Confidence', 'high',
            '-CaptureBasis', 'explicit-user-capture',
            '-DataClass', 'internal',
            '-Title', "Fixture method $MethodId",
            '-Basis', 'Прямая fixture-коррекция подтверждает повторяемый исследовательский метод.',
            '-ProposedChange', 'Проверять research evidence и критерий решения единым воспроизводимым способом.',
            '-MethodKind', 'checklist',
            '-MethodSummary', 'Проверяет research evidence и критерий решения перед завершением запуска.',
            '-MethodAppliesTo', 'niche-discovery',
            '-DuplicateCheck', 'Совпадающий fixture method отсутствует.',
            '-ReviewDue', $ReviewDue,
            '-AuthorityRef', "user-request:research-harness-$MethodId",
            '-WriteIntent', 'explicit-promotion'
        ) `
        -WorkingDirectory $CaseRoot `
        -Timeout $TimeoutSeconds
    if ($candidateResult.TimedOut -or $candidateResult.StreamTimedOut -or $candidateResult.ExitCode -ne 0) {
        throw "HARNESS-METHOD-CANDIDATE: $(Get-SafeChildSummary -Result $candidateResult -FixturePath $CaseRoot)"
    }
    $candidateFiles = @(
        Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter 'KC-*.md' -Force |
            Where-Object { $_.BaseName -cnotin $candidateIdsBefore }
    )
    if ($candidateFiles.Count -ne 1) {
        throw "HARNESS-METHOD-CANDIDATE-COUNT: $($candidateFiles.Count)"
    }
    $candidatePath = $candidateFiles[0].FullName
    $candidateRelative = [System.IO.Path]::GetRelativePath($CaseRoot, $candidatePath).Replace('\', '/')
    $candidateText = [System.IO.File]::ReadAllText($candidatePath)
    $createdAtMatch = [regex]::Match($candidateText, '(?m)^created_at:\s*(?<value>[^\r\n]+?)\s*$')
    if (-not $createdAtMatch.Success) { throw 'HARNESS-METHOD-CANDIDATE-CREATED-AT' }
    $candidateText = [regex]::Replace($candidateText, '(?m)^state: ready\s*$', 'state: applied')
    $candidateText = [regex]::Replace(
        $candidateText,
        '(?m)^applied_at: null\s*$',
        'applied_at: ' + $createdAtMatch.Groups['value'].Value
    )
    Write-Utf8BomFixture -Path $candidatePath -Content $candidateText

    $safeFileName = $MethodId + '.md'
    $methodPath = Join-Path $CaseRoot ('mastery\local\' + $safeFileName)
    $supersedesValue = if ([string]::IsNullOrWhiteSpace($Supersedes)) { 'null' } else { $Supersedes }
    $content = @"
---
mastery_contract_version: 2
method_id: $MethodId
method_kind: checklist
summary: Проверяет research evidence и критерий решения перед завершением запуска.
owner_scope: project
applies_to:
  - niche-discovery
status: $Status
source_refs:
  - $candidateRelative
verified_at: $VerifiedAt
review_due: $ReviewDue
supersedes: $supersedesValue
---

# Fixture method

## Purpose

Дать воспроизводимую проверку research evidence и критерия решения.

## Use when

Использовать для synthetic niche-discovery fixture.

## Do not use when

Не использовать вне bounded research run.

## Inputs

Research brief, evidence ledger и decision.

## Workflow

Сверить evidence, ограничения и критерий решения.

## Quality gate

Вывод поддержан точными evidence refs.

## Failure modes

При недостатке evidence вернуть blocked outcome.

## Provenance

Источник метода указан во frontmatter.
"@
    Write-Utf8BomFixture -Path $methodPath -Content $content

    $indexResult = Invoke-PowerShellChild `
        -ScriptPath (Join-Path $CaseRoot 'scripts/update-mastery-index.ps1') `
        -Arguments @('-Root', $CaseRoot, '-Mode', 'Write') `
        -WorkingDirectory $CaseRoot `
        -Timeout $TimeoutSeconds
    if ($indexResult.TimedOut -or $indexResult.StreamTimedOut -or $indexResult.ExitCode -ne 0) {
        throw "HARNESS-METHOD-INDEX: $(Get-SafeChildSummary -Result $indexResult -FixturePath $CaseRoot)"
    }
    return ('mastery/local/' + $safeFileName)
}

function Set-RunLocalMethodRef {
    param(
        [Parameter(Mandatory = $true)][string]$RunRoot,
        [Parameter(Mandatory = $true)][string]$MethodId,
        [Parameter(Mandatory = $true)][string]$MethodRef
    )

    foreach ($fileName in @('brief.md', 'decision.md')) {
        $path = Join-Path $RunRoot $fileName
        $text = [System.IO.File]::ReadAllText($path)
        $text = $text.Replace('- Local method IDs: []', "- Local method IDs: [$MethodId]")
        $text = $text.Replace('- Local method refs: []', "- Local method refs: [$MethodRef]")
        Write-Utf8BomFixture -Path $path -Content $text

        $readBack = [System.IO.File]::ReadAllText($path)
        $idPattern = '(?m)^- Local method IDs: \[' + [regex]::Escape($MethodId) + '\][ \t]*\r?$'
        $refPattern = '(?m)^- Local method refs: \[' + [regex]::Escape($MethodRef) + '\][ \t]*\r?$'
        if ([regex]::Matches($readBack, $idPattern).Count -ne 1 -or
            [regex]::Matches($readBack, $refPattern).Count -ne 1 -or
            $readBack.Contains('- Local method IDs: []') -or
            $readBack.Contains('- Local method refs: []')) {
            throw "HARNESS-LOCAL-METHOD-READBACK: $fileName"
        }
    }
}

function Invoke-BlockingCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)][string]$RunRoot,
        [Parameter(Mandatory = $true)][string[]]$ExpectedFiles,
        [Parameter(Mandatory = $true)][string]$ExpectedIssuePattern
    )

    Assert-ExactRunFiles -RunRoot $RunRoot -Expected $ExpectedFiles -Name $Name
    $before = @(Get-TreeHashSnapshot -Path $CaseRoot)
    $verification = Invoke-PublicVerifier -CaseRoot $CaseRoot
    Assert-NoVerifierLeftovers -CaseRoot $CaseRoot -Name $Name
    $after = @(Get-TreeHashSnapshot -Path $CaseRoot)
    Assert-TreeUnchanged -Before $before -After $after -Name $Name
    Assert-ExactRunFiles -RunRoot $RunRoot -Expected $ExpectedFiles -Name $Name
    if ($verification.TimedOut -or $verification.StreamTimedOut) {
        throw "${Name}: public verifier timed out."
    }
    if ($verification.ExitCode -eq 0) {
        throw "RED: $Name expected a blocking exit. $(Get-SafeChildSummary -Result $verification -FixturePath $CaseRoot)"
    }
    if ([string]$verification.Stdout -cnotmatch $ExpectedIssuePattern) {
        throw "FAIL: $Name blocked without its expected diagnostic. $(Get-SafeChildSummary -Result $verification -FixturePath $CaseRoot)"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$verification.Stderr)) {
        throw "FAIL: $Name emitted unexpected stderr. $(Get-SafeChildSummary -Result $verification -FixturePath $CaseRoot)"
    }
    Write-Host "PASS: $Name blocked through public verifier (exit=$($verification.ExitCode))."
}

function Invoke-PassingCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)][string]$RunRoot,
        [Parameter(Mandatory = $true)][string[]]$ExpectedFiles
    )

    Assert-ExactRunFiles -RunRoot $RunRoot -Expected $ExpectedFiles -Name $Name
    $before = @(Get-TreeHashSnapshot -Path $CaseRoot)
    $verification = Invoke-PublicVerifier -CaseRoot $CaseRoot
    Assert-NoVerifierLeftovers -CaseRoot $CaseRoot -Name $Name
    $after = @(Get-TreeHashSnapshot -Path $CaseRoot)
    Assert-TreeUnchanged -Before $before -After $after -Name $Name
    Assert-ExactRunFiles -RunRoot $RunRoot -Expected $ExpectedFiles -Name $Name
    if ($verification.TimedOut -or $verification.StreamTimedOut -or $verification.ExitCode -ne 0) {
        throw "FAIL: $Name expected exit 0. $(Get-SafeChildSummary -Result $verification -FixturePath $CaseRoot)"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$verification.Stderr)) {
        throw "FAIL: $Name emitted unexpected stderr. $(Get-SafeChildSummary -Result $verification -FixturePath $CaseRoot)"
    }
    Write-Host "PASS: $Name accepted through public verifier (exit=0)."
}

function Test-SafeFixtureRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $canonical = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    $expectedParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]'\/')
    $actualParent = [System.IO.Path]::GetFullPath((Split-Path -Parent $canonical)).TrimEnd([char[]]'\/')
    $leaf = Split-Path -Leaf $canonical
    $lexicallySafe = (
        $actualParent.Equals($expectedParent, [System.StringComparison]::OrdinalIgnoreCase) -and
        $leaf -cmatch ('^' + [regex]::Escape($fixturePrefix) + '[0-9a-f]{32}$')
    )
    if (-not $lexicallySafe) { return $false }
    if (-not (Test-Path -LiteralPath $canonical -PathType Container)) { return $true }
    try {
        $resolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $canonical).Path).TrimEnd([char[]]'\/')
        if (-not $resolved.Equals($canonical, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        $rootItem = Get-Item -LiteralPath $canonical -Force
        if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $nestedReparse = @(
            Get-ChildItem -LiteralPath $canonical -Recurse -Force |
                Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 }
        )
        return $nestedReparse.Count -eq 0
    }
    catch { return $false }
}

function Assert-PortableRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$FieldName
    )

    if ($RelativePath -notmatch '^[A-Za-z0-9._/\-]+$' -or
        $RelativePath.StartsWith('/') -or
        $RelativePath.Contains('\') -or
        @($RelativePath -split '/' | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
        throw "HARNESS-MANIFEST-PATH-UNSAFE: $FieldName"
    }
}

function New-PortableGeneratedSeed {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$SeedRoot
    )

    $manifestPath = Join-Path $SourceRoot '.template-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'HARNESS-PUBLIC-MANIFEST-MISSING'
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    New-Item -ItemType Directory -Path $SeedRoot | Out-Null
    foreach ($relativeValue in @($manifest.portable_files)) {
        $relative = [string]$relativeValue
        Assert-PortableRelativePath -RelativePath $relative -FieldName 'portable_files'
        $source = Join-Path $SourceRoot $relative.Replace('/', '\')
        $destination = Join-Path $SeedRoot $relative.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw 'HARNESS-MANIFEST-FILE-MISSING'
        }
        $destinationParent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $source -Destination $destination
    }
    foreach ($relativeValue in @($manifest.portable_empty_directories)) {
        $relative = [string]$relativeValue
        Assert-PortableRelativePath -RelativePath $relative -FieldName 'portable_empty_directories'
        New-Item -ItemType Directory -Path (Join-Path $SeedRoot $relative.Replace('/', '\')) -Force | Out-Null
    }

    $initializer = Join-Path $SeedRoot 'scripts\initialize-project.ps1'
    if (-not (Test-Path -LiteralPath $initializer -PathType Leaf)) {
        throw 'HARNESS-PUBLIC-INITIALIZER-MISSING'
    }
    $initialization = Invoke-PowerShellChild `
        -ScriptPath $initializer `
        -Arguments @(
            '-ProjectName', 'Research Harness Project',
            '-ProjectSlug', 'research-harness-project',
            '-Description', 'Synthetic generated project for source-only research regression fixtures.',
            '-Owner', 'fixture-owner',
            '-InitializeGit'
        ) `
        -WorkingDirectory $SeedRoot `
        -Timeout $TimeoutSeconds
    if ($initialization.TimedOut -or $initialization.ExitCode -ne 0) {
        throw "HARNESS-SEED-INITIALIZATION: $(Get-SafeChildSummary -Result $initialization -FixturePath $SeedRoot)"
    }

    $seedVerification = Invoke-PublicVerifier -CaseRoot $SeedRoot
    if ($seedVerification.TimedOut -or $seedVerification.ExitCode -ne 0) {
        throw "HARNESS-SEED-VERIFICATION: $(Get-SafeChildSummary -Result $seedVerification -FixturePath $SeedRoot)"
    }
}

try {
    $sourceRoot = if ([string]::IsNullOrWhiteSpace($Root)) {
        Split-Path -Parent $PSScriptRoot
    }
    else {
        [System.IO.Path]::GetFullPath($Root)
    }
    $sourceRoot = [System.IO.Path]::GetFullPath($sourceRoot).TrimEnd([char[]]'\/')
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    $seedRoot = Join-Path $fixtureRoot 'seed'
    New-PortableGeneratedSeed -SourceRoot $sourceRoot -SeedRoot $seedRoot

    $failures = [System.Collections.Generic.List[string]]::new()
    foreach ($requestedCase in $CaseId) {
        try {
            switch ($requestedCase) {
                'A43' {
                    $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name 'a43-two-file-run'
                    $included = @('decision.md', 'evidence.jsonl')
                    $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $included
                    Invoke-BlockingCase `
                        -Name 'A43 two-file run' `
                        -CaseRoot $caseRoot `
                        -RunRoot $runRoot `
                        -ExpectedFiles $included `
                        -ExpectedIssuePattern 'research-run-incomplete'
                }
                'A44' {
                    $subcaseFailures = [System.Collections.Generic.List[string]]::new()
                    foreach ($missing in $expectedRunFiles) {
                        try {
                            $safeLeaf = $missing.Replace('.', '-')
                            $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name "a44-missing-$safeLeaf"
                            $included = @($expectedRunFiles | Where-Object { $_ -cne $missing })
                            $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $included
                            Invoke-BlockingCase `
                                -Name "A44 missing $missing" `
                                -CaseRoot $caseRoot `
                                -RunRoot $runRoot `
                                -ExpectedFiles $included `
                                -ExpectedIssuePattern 'research-run-incomplete'
                        }
                        catch {
                            $subcaseFailures.Add($_.Exception.Message) | Out-Null
                            Write-Host $_.Exception.Message
                        }
                    }
                    if ($subcaseFailures.Count -gt 0) {
                        throw "A44 had $($subcaseFailures.Count) missing-file false result(s)."
                    }
                }
                'A45' {
                    $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name 'a45-full-scaffold'
                    $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                    Invoke-PassingCase -Name 'A45 full scaffold' -CaseRoot $caseRoot -RunRoot $runRoot -ExpectedFiles $expectedRunFiles
                }
                'A46' {
                    $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name 'a46-corrupted-jsonl'
                    $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                    Write-Utf8BomFixture `
                        -Path (Join-Path $runRoot 'evidence.jsonl') `
                        -Content "{invalid-json-fixture`n"
                    Invoke-BlockingCase `
                        -Name 'A46 corrupted JSONL' `
                        -CaseRoot $caseRoot `
                        -RunRoot $runRoot `
                        -ExpectedFiles $expectedRunFiles `
                        -ExpectedIssuePattern 'corrupted evidence JSONL'
                }
                'A47' {
                    $subcaseFailures = [System.Collections.Generic.List[string]]::new()
                    foreach ($subcase in @('broken', 'duplicate')) {
                        try {
                            $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name "a47-$subcase-evidence-id"
                            $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                            if ($subcase -ceq 'broken') {
                                $rows = @(
                                    New-EvidenceRow `
                                        -EvidenceId 'broken evidence id' `
                                        -ClaimId 'CL-A47-001' `
                                        -OriginGroupId 'OG-A47-001' `
                                        -DatasetOrigin 'dataset-a47-broken' `
                                        -SourceLeaf 'a47-broken' `
                                        -Fingerprint 'fp-a47-broken'
                                )
                                Set-EvidenceRows -RunRoot $runRoot -Rows $rows
                            }
                            else {
                                $rows = @(
                                    New-EvidenceRow -EvidenceId 'EV-A47-001' -ClaimId 'CL-A47-001' -OriginGroupId 'OG-A47-001' -DatasetOrigin 'dataset-a47-one' -SourceLeaf 'a47-one' -Fingerprint 'fp-a47-one'
                                    New-EvidenceRow -EvidenceId 'EV-A47-001' -ClaimId 'CL-A47-002' -OriginGroupId 'OG-A47-002' -DatasetOrigin 'dataset-a47-two' -SourceLeaf 'a47-two' -Fingerprint 'fp-a47-two'
                                )
                                Set-EvidenceRows -RunRoot $runRoot -Rows $rows
                                Set-DecisionEvidenceRefs -RunRoot $runRoot -EvidenceIds @('EV-A47-001')
                            }
                            $expectedEvidenceIssue = if ($subcase -ceq 'broken') {
                                'invalid evidence_id'
                            }
                            else {
                                'Duplicate evidence ID'
                            }
                            Invoke-BlockingCase `
                                -Name "A47 $subcase evidence ID" `
                                -CaseRoot $caseRoot `
                                -RunRoot $runRoot `
                                -ExpectedFiles $expectedRunFiles `
                                -ExpectedIssuePattern $expectedEvidenceIssue
                        }
                        catch {
                            $subcaseFailures.Add($_.Exception.Message) | Out-Null
                            Write-Host $_.Exception.Message
                        }
                    }
                    if ($subcaseFailures.Count -gt 0) {
                        throw "A47 had $($subcaseFailures.Count) evidence-ID false result(s)."
                    }
                }
                'A48' {
                    $subcaseFailures = [System.Collections.Generic.List[string]]::new()
                    foreach ($subcase in @('origin-assignment', 'exact-observation')) {
                        try {
                            $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name "a48-$subcase"
                            $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                            if ($subcase -ceq 'origin-assignment') {
                                $rows = @(
                                    New-EvidenceRow -EvidenceId 'EV-A48-001' -ClaimId 'CL-A48-001' -OriginGroupId 'OG-A48-001' -DatasetOrigin 'dataset-a48-shared' -SourceLeaf 'a48-one' -Fingerprint 'fp-a48-one'
                                    New-EvidenceRow -EvidenceId 'EV-A48-002' -ClaimId 'CL-A48-002' -OriginGroupId 'OG-A48-002' -DatasetOrigin 'dataset-a48-shared' -SourceLeaf 'a48-two' -Fingerprint 'fp-a48-two'
                                )
                                $expectedIssue = 'duplicate origin group assignment'
                            }
                            else {
                                $rows = @(
                                    New-EvidenceRow -EvidenceId 'EV-A48-101' -ClaimId 'CL-A48-101' -OriginGroupId 'OG-A48-101' -DatasetOrigin 'dataset-a48-observation' -SourceLeaf 'a48-observation' -Fingerprint 'fp-a48-observation'
                                    New-EvidenceRow -EvidenceId 'EV-A48-102' -ClaimId 'CL-A48-101' -OriginGroupId 'OG-A48-101' -DatasetOrigin 'dataset-a48-observation' -SourceLeaf 'a48-observation' -Fingerprint 'fp-a48-observation'
                                )
                                $expectedIssue = 'duplicate research observation'
                            }
                            Set-EvidenceRows -RunRoot $runRoot -Rows $rows
                            Set-DecisionEvidenceRefs `
                                -RunRoot $runRoot `
                                -EvidenceIds @($rows | ForEach-Object { [string]$_.evidence_id })
                            Invoke-BlockingCase `
                                -Name "A48 $subcase" `
                                -CaseRoot $caseRoot `
                                -RunRoot $runRoot `
                                -ExpectedFiles $expectedRunFiles `
                                -ExpectedIssuePattern $expectedIssue
                        }
                        catch {
                            $subcaseFailures.Add($_.Exception.Message) | Out-Null
                            Write-Host $_.Exception.Message
                        }
                    }
                    if ($subcaseFailures.Count -gt 0) {
                        throw "A48 had $($subcaseFailures.Count) research-origin false result(s)."
                    }
                }
                'A49' {
                    $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name 'a49-broken-central-candidate'
                    $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                    Set-DecisionCandidateOutcome `
                        -RunRoot $runRoot `
                        -CandidateIds @('KC-20260801-120000-deadbeef')
                    Invoke-BlockingCase `
                        -Name 'A49 broken central candidate ID' `
                        -CaseRoot $caseRoot `
                        -RunRoot $runRoot `
                        -ExpectedFiles $expectedRunFiles `
                        -ExpectedIssuePattern 'Central candidate ID.*candidate'
                }
                'A50' {
                    $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name 'a50-promotion-proposal'
                    $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                    Write-Utf8BomFixture `
                        -Path (Join-Path $runRoot 'promotion-proposal.md') `
                        -Content "# Promotion proposal`n`nSynthetic forbidden run-local artifact.`n"
                    $withForbiddenFile = @($expectedRunFiles + 'promotion-proposal.md')
                    Invoke-BlockingCase `
                        -Name 'A50 run-local promotion-proposal.md' `
                        -CaseRoot $caseRoot `
                        -RunRoot $runRoot `
                        -ExpectedFiles $withForbiddenFile `
                        -ExpectedIssuePattern 'research-run-extra: promotion-proposal\.md'
                }
                'A51' {
                    $subcaseFailures = [System.Collections.Generic.List[string]]::new()
                    $runRelative = 'research/runs/2026-08-01-research-harness'

                    try {
                        $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name 'a51-four-central-candidates'
                        Set-ActiveProjectCaptureMode -CaseRoot $caseRoot -CaptureMode 'safe-local'
                        New-FixtureGitHead -CaseRoot $caseRoot
                        $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                        $candidateIds = @(
                            'KC-20260801-000001-a5100001',
                            'KC-20260801-000002-a5100002',
                            'KC-20260801-000003-a5100003',
                            'KC-20260801-000004-a5100004'
                        )
                        $evidenceIds = @('EV-A51-001', 'EV-A51-002', 'EV-A51-003', 'EV-A51-004')
                        $rows = @()
                        for ($index = 0; $index -lt 3; $index++) {
                            $ordinal = $index + 1
                            $rows += New-EvidenceRow `
                                -EvidenceId $evidenceIds[$index] `
                                -ClaimId ("CL-A51-{0:D3}" -f $ordinal) `
                                -OriginGroupId ("OG-A51-{0:D3}" -f $ordinal) `
                                -DatasetOrigin ("dataset-a51-$ordinal") `
                                -SourceLeaf ("a51-$ordinal") `
                                -Fingerprint ("fp-a51-$ordinal")
                            Write-ResearchCandidate `
                                -CaseRoot $caseRoot `
                                -RunRelative $runRelative `
                                -CandidateId $candidateIds[$index] `
                                -EvidenceId $evidenceIds[$index] `
                                -ClaimKey ("a51-central-candidate-$ordinal") | Out-Null
                        }
                        Set-EvidenceRows -RunRoot $runRoot -Rows $rows
                        Set-DecisionEvidenceRefs -RunRoot $runRoot -EvidenceIds $evidenceIds[0..2]
                        Set-DecisionCandidateOutcome -RunRoot $runRoot -CandidateIds $candidateIds[0..2]
                        Invoke-PassingCase -Name 'A51 three-candidate control' -CaseRoot $caseRoot -RunRoot $runRoot -ExpectedFiles $expectedRunFiles

                        $rows += New-EvidenceRow `
                            -EvidenceId $evidenceIds[3] `
                            -ClaimId 'CL-A51-004' `
                            -OriginGroupId 'OG-A51-004' `
                            -DatasetOrigin 'dataset-a51-4' `
                            -SourceLeaf 'a51-4' `
                            -Fingerprint 'fp-a51-4'
                        Write-ResearchCandidate `
                            -CaseRoot $caseRoot `
                            -RunRelative $runRelative `
                            -CandidateId $candidateIds[3] `
                            -EvidenceId $evidenceIds[3] `
                            -ClaimKey 'a51-central-candidate-4' | Out-Null
                        Set-EvidenceRows -RunRoot $runRoot -Rows $rows
                        Set-DecisionEvidenceRefs -RunRoot $runRoot -EvidenceIds $evidenceIds
                        Set-DecisionCandidateOutcome -RunRoot $runRoot -CandidateIds $candidateIds
                        Invoke-BlockingCase `
                            -Name 'A51 more than three central candidates' `
                            -CaseRoot $caseRoot `
                            -RunRoot $runRoot `
                            -ExpectedFiles $expectedRunFiles `
                            -ExpectedIssuePattern 'central candidates'
                    }
                    catch {
                        $subcaseFailures.Add($_.Exception.Message) | Out-Null
                        Write-Host $_.Exception.Message
                    }

                    foreach ($readySubcase in @(
                        [pscustomobject]@{ Name = 'current-ready-provenance-control'; CandidateAuthority = 'policy:knowledge-contract-v1'; Pass = $true },
                        [pscustomobject]@{ Name = 'current-ready-provenance-mismatch'; CandidateAuthority = 'user-request:a51-ready-mismatch'; Pass = $false }
                    )) {
                        try {
                            $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name "a51-$($readySubcase.Name)"
                            Set-ActiveProjectCaptureMode -CaseRoot $caseRoot -CaptureMode 'safe-local'
                            New-FixtureGitHead -CaseRoot $caseRoot
                            $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                            $candidateId = if ($readySubcase.Pass) { 'KC-20260801-010001-a51a0001' } else { 'KC-20260801-010002-a51a0002' }
                            $evidenceId = if ($readySubcase.Pass) { 'EV-A51-101' } else { 'EV-A51-102' }
                            $row = New-EvidenceRow `
                                -EvidenceId $evidenceId `
                                -ClaimId ("CL-$evidenceId") `
                                -OriginGroupId ("OG-$evidenceId") `
                                -DatasetOrigin ("dataset-$($readySubcase.Name)") `
                                -SourceLeaf $readySubcase.Name `
                                -Fingerprint ("fp-$($readySubcase.Name)")
                            Set-EvidenceRows -RunRoot $runRoot -Rows @($row)
                            Set-DecisionEvidenceRefs -RunRoot $runRoot -EvidenceIds @($evidenceId)
                            Write-ResearchCandidate `
                                -CaseRoot $caseRoot `
                                -RunRelative $runRelative `
                                -CandidateId $candidateId `
                                -EvidenceId $evidenceId `
                                -ClaimKey $readySubcase.Name `
                                -AuthorityRef $readySubcase.CandidateAuthority | Out-Null
                            Set-DecisionCandidateOutcome -RunRoot $runRoot -CandidateIds @($candidateId)
                            if ($readySubcase.Pass) {
                                Invoke-PassingCase `
                                    -Name "A51 $($readySubcase.Name)" `
                                    -CaseRoot $caseRoot `
                                    -RunRoot $runRoot `
                                    -ExpectedFiles $expectedRunFiles
                            }
                            else {
                                Invoke-BlockingCase `
                                    -Name "A51 $($readySubcase.Name)" `
                                    -CaseRoot $caseRoot `
                                    -RunRoot $runRoot `
                                    -ExpectedFiles $expectedRunFiles `
                                    -ExpectedIssuePattern 'current ready outcome .*candidate provenance'
                            }
                        }
                        catch {
                            $subcaseFailures.Add($_.Exception.Message) | Out-Null
                            Write-Host $_.Exception.Message
                        }
                    }

                    foreach ($appliedSubcase in @(
                        [pscustomobject]@{ Name = 'applied-authority-control'; CandidateAuthority = 'user-request:a51-applied-control'; DecisionAuthority = 'user-request:a51-applied-control'; Pass = $true },
                        [pscustomobject]@{ Name = 'applied-authority-mismatch'; CandidateAuthority = 'user-request:a51-applied-candidate'; DecisionAuthority = 'user-request:a51-applied-decision'; Pass = $false }
                    )) {
                        try {
                            $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name "a51-$($appliedSubcase.Name)"
                            $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                            $candidateId = if ($appliedSubcase.Pass) { 'KC-20260801-020001-a51b0001' } else { 'KC-20260801-020002-a51b0002' }
                            $evidenceId = if ($appliedSubcase.Pass) { 'EV-A51-201' } else { 'EV-A51-202' }
                            $row = New-EvidenceRow `
                                -EvidenceId $evidenceId `
                                -ClaimId ("CL-$evidenceId") `
                                -OriginGroupId ("OG-$evidenceId") `
                                -DatasetOrigin ("dataset-$($appliedSubcase.Name)") `
                                -SourceLeaf $appliedSubcase.Name `
                                -Fingerprint ("fp-$($appliedSubcase.Name)")
                            Set-EvidenceRows -RunRoot $runRoot -Rows @($row)
                            Set-DecisionEvidenceRefs -RunRoot $runRoot -EvidenceIds @($evidenceId)
                            Write-ResearchCandidate `
                                -CaseRoot $caseRoot `
                                -RunRelative $runRelative `
                                -CandidateId $candidateId `
                                -EvidenceId $evidenceId `
                                -ClaimKey $appliedSubcase.Name `
                                -State 'applied' `
                                -AuthorityRef $appliedSubcase.CandidateAuthority | Out-Null
                            Add-CandidateBacklink -CaseRoot $caseRoot -CandidateId $candidateId
                            Set-DecisionCandidateOutcome `
                                -RunRoot $runRoot `
                                -CandidateIds @($candidateId) `
                                -OutcomeKind 'applied' `
                                -WriteIntent 'explicit-promotion' `
                                -AuthorityRef $appliedSubcase.DecisionAuthority `
                                -AffectedCanon 'idea/superidea.md#суперидея'
                            if ($appliedSubcase.Pass) {
                                Invoke-PassingCase `
                                    -Name "A51 $($appliedSubcase.Name)" `
                                    -CaseRoot $caseRoot `
                                    -RunRoot $runRoot `
                                    -ExpectedFiles $expectedRunFiles
                            }
                            else {
                                Invoke-BlockingCase `
                                    -Name "A51 $($appliedSubcase.Name)" `
                                    -CaseRoot $caseRoot `
                                    -RunRoot $runRoot `
                                    -ExpectedFiles $expectedRunFiles `
                                    -ExpectedIssuePattern 'applied outcome .*candidate promotion authority'
                            }
                        }
                        catch {
                            $subcaseFailures.Add($_.Exception.Message) | Out-Null
                            Write-Host $_.Exception.Message
                        }
                    }

                    try {
                        $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name 'a51-historical-automatic-after-report-only'
                        Set-ActiveProjectCaptureMode -CaseRoot $caseRoot -CaptureMode 'safe-local'
                        New-FixtureGitHead -CaseRoot $caseRoot
                        $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                        $candidateId = 'KC-20260801-030001-a51c0001'
                        $evidenceId = 'EV-A51-301'
                        $row = New-EvidenceRow `
                            -EvidenceId $evidenceId `
                            -ClaimId 'CL-A51-301' `
                            -OriginGroupId 'OG-A51-301' `
                            -DatasetOrigin 'dataset-a51-historical' `
                            -SourceLeaf 'a51-historical' `
                            -Fingerprint 'fp-a51-historical'
                        Set-EvidenceRows -RunRoot $runRoot -Rows @($row)
                        Set-DecisionEvidenceRefs -RunRoot $runRoot -EvidenceIds @($evidenceId)
                        $candidatePath = Write-ResearchCandidate `
                            -CaseRoot $caseRoot `
                            -RunRelative $runRelative `
                            -CandidateId $candidateId `
                            -EvidenceId $evidenceId `
                            -ClaimKey 'a51-historical-automatic'
                        Set-DecisionCandidateOutcome -RunRoot $runRoot -CandidateIds @($candidateId)
                        Invoke-PassingCase `
                            -Name 'A51 safe-local automatic provenance control' `
                            -CaseRoot $caseRoot `
                            -RunRoot $runRoot `
                            -ExpectedFiles $expectedRunFiles

                        $decisionPath = Join-Path $runRoot 'decision.md'
                        $candidateHashBeforeModeSwitch = Get-FileSha256 -Path $candidatePath
                        $decisionHashBeforeModeSwitch = Get-FileSha256 -Path $decisionPath
                        Set-ActiveProjectCaptureMode -CaseRoot $caseRoot -CaptureMode 'report-only'
                        if ((Get-FileSha256 -Path $candidatePath) -cne $candidateHashBeforeModeSwitch -or
                            (Get-FileSha256 -Path $decisionPath) -cne $decisionHashBeforeModeSwitch) {
                            throw 'A51 report-only transition rewrote historical provenance before verification.'
                        }
                        Invoke-PassingCase `
                            -Name 'A51 historical automatic provenance remains valid in report-only' `
                            -CaseRoot $caseRoot `
                            -RunRoot $runRoot `
                            -ExpectedFiles $expectedRunFiles
                        if ((Get-FileSha256 -Path $candidatePath) -cne $candidateHashBeforeModeSwitch -or
                            (Get-FileSha256 -Path $decisionPath) -cne $decisionHashBeforeModeSwitch) {
                            throw 'A51 public verifier rewrote historical provenance after report-only transition.'
                        }
                    }
                    catch {
                        $subcaseFailures.Add($_.Exception.Message) | Out-Null
                        Write-Host $_.Exception.Message
                    }

                    if ($subcaseFailures.Count -gt 0) {
                        throw "A51 had $($subcaseFailures.Count) candidate provenance false result(s)."
                    }
                }
                'A52' {
                    $subcaseFailures = [System.Collections.Generic.List[string]]::new()
                    try {
                        # This deterministic case covers the public scaffold/verifier boundary.
                        # The instruction-driven startup-researcher route needs a separate forward-test.
                        $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name 'a52-no-authority-no-idea-mutation'
                        $ideaRoot = Join-Path $caseRoot 'idea'
                        $ideaBefore = @(Get-TreeHashSnapshot -Path $ideaRoot)
                        $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                        $ideaAfterScaffold = @(Get-TreeHashSnapshot -Path $ideaRoot)
                        Assert-TreeUnchanged -Before $ideaBefore -After $ideaAfterScaffold -Name 'A52 scaffold without authority'
                        $decisionText = [System.IO.File]::ReadAllText((Join-Path $runRoot 'decision.md'))
                        if ($decisionText -cnotmatch '(?m)^- Write intent: none\s*$' -or
                            $decisionText -cnotmatch '(?m)^- Authority ref: null\s*$' -or
                            $decisionText -cnotmatch '(?m)^- Затронутый канон: `нет`\s*$') {
                            throw 'A52 no-authority decision oracle mismatch.'
                        }
                        Invoke-PassingCase -Name 'A52 verifier-only no-authority run leaves idea unchanged' -CaseRoot $caseRoot -RunRoot $runRoot -ExpectedFiles $expectedRunFiles
                        $ideaAfterVerifier = @(Get-TreeHashSnapshot -Path $ideaRoot)
                        Assert-TreeUnchanged -Before $ideaBefore -After $ideaAfterVerifier -Name 'A52 public verifier'
                    }
                    catch {
                        $subcaseFailures.Add($_.Exception.Message) | Out-Null
                        Write-Host $_.Exception.Message
                    }

                    foreach ($blockedSubcase in @(
                        [pscustomobject]@{ Name = 'missing-reason'; Reason = ''; Omit = $true; Pass = $false; Pattern = 'Knowledge outcome .*exact Write intent, Authority ref' },
                        [pscustomobject]@{ Name = 'not-applicable-reason'; Reason = 'не применимо'; Omit = $false; Pass = $false; Pattern = 'blocked outcome' },
                        [pscustomobject]@{ Name = 'closed-reason-control'; Reason = 'missing-provenance'; Omit = $false; Pass = $true; Pattern = '' }
                    )) {
                        try {
                            $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name "a52-$($blockedSubcase.Name)"
                            $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                            Set-DecisionBlockedOutcome `
                                -RunRoot $runRoot `
                                -BlockedReason $blockedSubcase.Reason `
                                -OmitBlockedReason:$blockedSubcase.Omit
                            if ($blockedSubcase.Pass) {
                                Invoke-PassingCase `
                                    -Name "A52 $($blockedSubcase.Name)" `
                                    -CaseRoot $caseRoot `
                                    -RunRoot $runRoot `
                                    -ExpectedFiles $expectedRunFiles
                            }
                            else {
                                Invoke-BlockingCase `
                                    -Name "A52 $($blockedSubcase.Name)" `
                                    -CaseRoot $caseRoot `
                                    -RunRoot $runRoot `
                                    -ExpectedFiles $expectedRunFiles `
                                    -ExpectedIssuePattern $blockedSubcase.Pattern
                            }
                        }
                        catch {
                            $subcaseFailures.Add($_.Exception.Message) | Out-Null
                            Write-Host $_.Exception.Message
                        }
                    }
                    if ($subcaseFailures.Count -gt 0) {
                        throw "A52 had $($subcaseFailures.Count) authority or blocked-reason false result(s)."
                    }
                }
                'A53' {
                    $subcaseFailures = [System.Collections.Generic.List[string]]::new()
                    $methodSubcases = @(
                        [pscustomobject]@{ Name = 'unknown'; MethodId = 'unknown-fixture-method'; MethodRef = 'mastery/local/unknown-fixture-method.md'; Status = ''; VerifiedAt = ''; ReviewDue = '' },
                        [pscustomobject]@{ Name = 'expired'; MethodId = 'expired-fixture-method'; MethodRef = ''; Status = 'active'; VerifiedAt = '2026-07-01'; ReviewDue = '2026-07-31' },
                        [pscustomobject]@{ Name = 'deprecated'; MethodId = 'deprecated-fixture-method'; MethodRef = ''; Status = 'deprecated'; VerifiedAt = '2026-08-01'; ReviewDue = '2099-12-31' },
                        [pscustomobject]@{ Name = 'superseded'; MethodId = 'superseded-fixture-method'; MethodRef = ''; Status = 'superseded'; VerifiedAt = '2026-08-01'; ReviewDue = '2099-12-31' }
                    )
                    foreach ($subcase in $methodSubcases) {
                        try {
                            $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name "a53-$($subcase.Name)-method"
                            $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                            $methodRef = [string]$subcase.MethodRef
                            if ($subcase.Name -cne 'unknown') {
                                $initialStatus = if ($subcase.Name -ceq 'superseded') { 'deprecated' } else { $subcase.Status }
                                $methodRef = Add-LocalMethodFixture `
                                    -CaseRoot $caseRoot `
                                    -MethodId $subcase.MethodId `
                                    -Status $initialStatus `
                                    -VerifiedAt $subcase.VerifiedAt `
                                    -ReviewDue $subcase.ReviewDue
                                if ($subcase.Name -ceq 'superseded') {
                                    $replacementRef = Add-LocalMethodFixture `
                                        -CaseRoot $caseRoot `
                                        -MethodId 'replacement-fixture-method' `
                                        -Status active `
                                        -VerifiedAt '2026-08-01' `
                                        -ReviewDue '2099-12-31'
                                    $supersededPath = Join-Path $caseRoot $methodRef
                                    $replacementPath = Join-Path $caseRoot $replacementRef
                                    $supersededText = [System.IO.File]::ReadAllText($supersededPath).Replace(
                                        'status: deprecated',
                                        'status: superseded'
                                    )
                                    $replacementText = [System.IO.File]::ReadAllText($replacementPath).Replace(
                                        'supersedes: null',
                                        "supersedes: $($subcase.MethodId)"
                                    )
                                    Write-Utf8BomFixture -Path $supersededPath -Content $supersededText
                                    Write-Utf8BomFixture -Path $replacementPath -Content $replacementText
                                    $indexResult = Invoke-PowerShellChild `
                                        -ScriptPath (Join-Path $caseRoot 'scripts/update-mastery-index.ps1') `
                                        -Arguments @('-Root', $caseRoot, '-Mode', 'Write') `
                                        -WorkingDirectory $caseRoot `
                                        -Timeout $TimeoutSeconds
                                    if ($indexResult.TimedOut -or $indexResult.StreamTimedOut -or $indexResult.ExitCode -ne 0) {
                                        throw "HARNESS-SUPERSEDED-INDEX: $(Get-SafeChildSummary -Result $indexResult -FixturePath $caseRoot)"
                                    }
                                }
                            }
                            Set-RunLocalMethodRef -RunRoot $runRoot -MethodId $subcase.MethodId -MethodRef $methodRef
                            $expectedMethodIssue = switch ($subcase.Name) {
                                'unknown' { 'unknown local method ID' }
                                'expired' { 'local method overdue' }
                                'deprecated' { 'local method .*active' }
                                'superseded' { 'local method .*active' }
                            }
                            Invoke-BlockingCase `
                                -Name "A53 $($subcase.Name) local method ref" `
                                -CaseRoot $caseRoot `
                                -RunRoot $runRoot `
                                -ExpectedFiles $expectedRunFiles `
                                -ExpectedIssuePattern $expectedMethodIssue
                        }
                        catch {
                            $subcaseFailures.Add($_.Exception.Message) | Out-Null
                            Write-Host $_.Exception.Message
                        }
                    }
                    if ($subcaseFailures.Count -gt 0) {
                        throw "A53 had $($subcaseFailures.Count) local-method false result(s)."
                    }
                }
                'A54' {
                    $caseRoot = New-CaseRoot -SeedRoot $seedRoot -Name 'a54-valid-local-method'
                    $runRoot = New-ResearchRun -CaseRoot $caseRoot -IncludeFiles $expectedRunFiles
                    $methodRef = Add-LocalMethodFixture `
                        -CaseRoot $caseRoot `
                        -MethodId 'valid-fixture-method' `
                        -Status 'active' `
                        -VerifiedAt '2026-08-01' `
                        -ReviewDue '2099-12-31'
                    Set-RunLocalMethodRef `
                        -RunRoot $runRoot `
                        -MethodId 'valid-fixture-method' `
                        -MethodRef $methodRef
                    Invoke-PassingCase -Name 'A54 valid local method ref' -CaseRoot $caseRoot -RunRoot $runRoot -ExpectedFiles $expectedRunFiles
                }
            }
        }
        catch {
            $failures.Add($_.Exception.Message) | Out-Null
            Write-Host $_.Exception.Message
        }
    }

    if ($failures.Count -gt 0) {
        Write-Host "RESEARCH-HARNESS-FAILED: $($failures.Count) case or subcase failure(s)."
        $harnessExitCode = 1
    }
    else {
        Write-Host "RESEARCH-HARNESS-PASSED: $($CaseId.Count) requested case(s)."
        $harnessExitCode = 0
    }
}
catch {
    Write-Host "RESEARCH-HARNESS-SETUP-FAILED: $($_.Exception.Message)"
    $harnessExitCode = 1
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        if (-not (Test-SafeFixtureRoot -Path $fixtureRoot)) {
            Write-Host 'RESEARCH-HARNESS-CLEANUP-BLOCKED: unsafe fixture root.'
            $harnessExitCode = 1
        }
        else {
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
        }
    }
}

exit $harnessExitCode
