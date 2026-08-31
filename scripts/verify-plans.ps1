[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$Report,
    [string]$MethodPlanRef = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Plan.psm1'
Import-Module $modulePath -Force
$masteryModulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Mastery.psm1'
Import-Module $masteryModulePath -Force
$knowledgeModulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Knowledge.psm1'
Import-Module $knowledgeModulePath -Force
$platformModulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Platform.psm1'
Import-Module $platformModulePath -Force
$rootPath = Get-ModelProjectPlanRoot -Root $Root
$issues = [System.Collections.Generic.List[string]]::new()
$script:requiresCanonicalKnowledgeGate = $false

function Add-Issue {
    param([string]$Message)
    $issues.Add($Message)
}

function Test-ExactFields {
    param($Document)
    $required = @(
        'artifact_kind', 'plan_contract_version', 'plan_id', 'task_key', 'prompt_ref',
        'status', 'current_phase', 'updated_at', 'completed_at', 'closeout_status',
        'knowledge_outcome', 'candidate_ids', 'result_refs', 'affected_canon', 'blocked_reason'
    )
    foreach ($field in $required) {
        if (-not $Document.Data.Contains($field)) { Add-Issue "$($Document.RelativePath): отсутствует поле $field." }
    }
    foreach ($field in @($Document.Data.Keys)) {
        if ($field -cnotin $required) { Add-Issue "$($Document.RelativePath): неизвестное поле $field." }
    }
}

function Test-ListField {
    param($Document, [string]$Field)
    if (-not $Document.Data.Contains($Field)) { return }
    $value = $Document.Data[$Field]
    if ($null -eq $value -or $value -is [string]) {
        Add-Issue "$($Document.RelativePath): $Field должен быть YAML-списком."
    }
}

function Get-CheckpointValue {
    param([string]$Body, [string]$Label)
    $match = [regex]::Match($Body, '(?m)^- ' + [regex]::Escape($Label) + ':\s*(?<value>.*?)\s*$')
    if ($match.Success) { return $match.Groups['value'].Value.Trim() }
    return $null
}

function Test-CanonicalMethodKnowledge {
    if (-not $script:requiresCanonicalKnowledgeGate) { return }
    $verifyKnowledgeScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'verify-knowledge.ps1'))
    try {
        $pwshPath = Get-ModelProjectPowerShellHost -ControlledRoots @($rootPath)
        $result = Invoke-ModelProjectProcess `
            -Executable $pwshPath `
            -Arguments @('-NoProfile', '-File', $verifyKnowledgeScript, '-Root', $rootPath) `
            -WorkingDirectory $rootPath `
            -MaxLines 2000 `
            -MaxCharacters 2MB
        if ($result.LimitExceeded -or $result.ExitCode -ne 0) {
            Add-Issue 'Выбранный Local Mastery method не прошел canonical knowledge gate.'
        }
    }
    catch { Add-Issue 'Canonical knowledge gate для Local Mastery method не выполнен.' }
}

function Test-MethodSelection {
    param($Document, [string]$Status)

    $headers = [regex]::Matches($Document.Body, '(?m)^## Метод выполнения\s*$')
    if ($headers.Count -eq 0) {
        if ($Status -cin @('planned', 'in-progress', 'blocked')) {
            Add-Issue "$($Document.RelativePath): active plan требует раздел Метод выполнения."
        }
        return
    }
    if ($headers.Count -ne 1) {
        Add-Issue "$($Document.RelativePath): требуется не более одного раздела Метод выполнения."
        return
    }

    $section = [regex]::Match($Document.Body, '(?ms)^## Метод выполнения[ \t]*\r?\n(?<value>.*?)(?=^## |\z)')
    if (-not $section.Success) {
        Add-Issue "$($Document.RelativePath): раздел Метод выполнения не читается."
        return
    }
    $selection = [regex]::Match(
        $section.Groups['value'].Value,
        '^\s*- Intent ID: (?<intent>[^\r\n]+)\r?\n- Local method ID: (?<method>[^\r\n]+)\r?\n- Local method ref: (?<ref>[^\r\n]+)\s*$'
    )
    if (-not $selection.Success) {
        Add-Issue "$($Document.RelativePath): Метод выполнения должен содержать exact Intent ID, Local method ID и Local method ref."
        return
    }

    $intentId = $selection.Groups['intent'].Value.Trim()
    $methodId = $selection.Groups['method'].Value.Trim()
    $methodRef = $selection.Groups['ref'].Value.Trim()
    if ($intentId -ceq 'pending') {
        if ($Status -cne 'planned' -or $methodId -cne 'none' -or $methodRef -cne 'none') {
            Add-Issue "$($Document.RelativePath): pending intent допустим только для planned plan без local method."
        }
        return
    }

    if ($methodId -ceq 'none' -or $methodRef -ceq 'none') {
        if ($methodId -cne 'none' -or $methodRef -cne 'none') {
            Add-Issue "$($Document.RelativePath): Local method ID и ref должны быть одновременно none."
            return
        }
    }
    elseif ($methodId -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,126}[a-z0-9])?$' -or
        $methodRef -cne "mastery/local/$methodId.md") {
        Add-Issue "$($Document.RelativePath): Local method ID и ref не совпадают."
        return
    }

    $intentCatalog = @()
    try { $intentCatalog = @(Get-ModelProjectMasteryIntentCatalog -Root $rootPath) }
    catch { Add-Issue "$($Document.RelativePath): не удалось проверить mastery intent catalog."; return }
    if ($intentId -cnotin @($intentCatalog | ForEach-Object { [string]$_.Id })) {
        Add-Issue "$($Document.RelativePath): Intent ID отсутствует в mastery/INTENTS.json."
        return
    }

    $registryChecked = $false
    if ($Status -cin @('planned', 'in-progress', 'blocked')) {
        try {
            [void](Update-ModelProjectMasteryIndex -Root $rootPath -Mode Check)
            $registryChecked = $true
        }
        catch { Add-Issue "$($Document.RelativePath): mastery registry неактуален."; return }
    }

    if ($methodId -ceq 'none') { return }

    $methodPath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $methodRef))
    if (-not (Test-Path -LiteralPath $methodPath -PathType Leaf)) {
        Add-Issue "$($Document.RelativePath): Local method ref не существует."
        return
    }
    try { $method = Read-ModelProjectLocalMasteryRecord -Root $rootPath -Path $methodPath -IntentCatalog $intentCatalog }
    catch { Add-Issue "$($Document.RelativePath): Local method ref не прошел mastery contract."; return }
    $script:requiresCanonicalKnowledgeGate = $true
    $methodText = Read-ModelProjectBoundedUtf8File -Root $rootPath -Path $methodPath -MaxBytes 2MB
    foreach ($heading in @('Purpose', 'Use when', 'Do not use when', 'Inputs', 'Workflow', 'Quality gate', 'Failure modes', 'Provenance', 'Navigation')) {
        $methodSection = [regex]::Matches($methodText, '(?ms)^## ' + [regex]::Escape($heading) + '[ \t]*\r?\n(?<value>.*?)(?=^## |\z)')
        if ($methodSection.Count -ne 1 -or [string]::IsNullOrWhiteSpace($methodSection[0].Groups['value'].Value)) {
            Add-Issue "$($Document.RelativePath): Local method не содержит заполненный раздел $heading."
            return
        }
    }
    if ($method.MethodId -cne $methodId) {
        Add-Issue "$($Document.RelativePath): Local method ID не совпадает с artifact."
        return
    }

    if (-not $registryChecked) {
        try { [void](Update-ModelProjectMasteryIndex -Root $rootPath -Mode Check) }
        catch { Add-Issue "$($Document.RelativePath): Local method отсутствует в актуальном mastery registry."; return }
    }
    if ($Status -cin @('planned', 'in-progress', 'blocked')) {
        $reviewDue = [datetime]::ParseExact($method.ReviewDue, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        if ($method.Status -cne 'active' -or $reviewDue.Date -lt [datetime]::UtcNow.Date -or $intentId -cnotin @($method.AppliesTo)) {
            Add-Issue "$($Document.RelativePath): active plan выбрал неактивный, просроченный или неприменимый local method."
        }
    }
}

function Test-V2Plan {
    param($Document)
    $data = $Document.Data
    Test-ExactFields -Document $Document
    foreach ($field in @('candidate_ids', 'result_refs', 'affected_canon')) { Test-ListField -Document $Document -Field $field }
    if ($data.Contains('artifact_kind') -and [string]$data.artifact_kind -cne 'plan') { Add-Issue "$($Document.RelativePath): artifact_kind должен быть plan." }
    if ($data.Contains('plan_contract_version') -and [string]$data.plan_contract_version -cne '2') { Add-Issue "$($Document.RelativePath): plan_contract_version должен быть 2." }
    if (-not $data.Contains('task_key') -or [string]$data.task_key -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or ([string]$data.task_key).Length -gt 64) {
        Add-Issue "$($Document.RelativePath): некорректный task_key."
    }

    $fileName = [System.IO.Path]::GetFileName($Document.Path)
    if ($fileName -notmatch '^(?<date>\d{4}-\d{2}-\d{2})-(?<key>[a-z0-9][a-z0-9-]*)\.md$') {
        Add-Issue "$($Document.RelativePath): имя Plan v2 не соответствует YYYY-MM-DD-<task-key>.md."
    }
    elseif ($data.Contains('task_key')) {
        $expectedId = 'PLAN-' + $Matches['date'].Replace('-', '') + '-' + [string]$data.task_key
        if ([string]$data.task_key -cne $Matches['key']) { Add-Issue "$($Document.RelativePath): task_key не совпадает с именем файла." }
        if (-not $data.Contains('plan_id') -or [string]$data.plan_id -cne $expectedId) { Add-Issue "$($Document.RelativePath): plan_id не совпадает с датой и task_key." }
    }

    $statuses = @('planned', 'in-progress', 'complete', 'blocked')
    $status = if ($data.Contains('status')) { [string]$data.status } else { '' }
    if ($status -cnotin $statuses) { Add-Issue "$($Document.RelativePath): неизвестный status '$status'." }
    Test-MethodSelection -Document $Document -Status $status
    if (-not $data.Contains('updated_at') -or [string]$data.updated_at -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') {
        Add-Issue "$($Document.RelativePath): updated_at должен быть UTC timestamp."
    }

    if ($data.Contains('prompt_ref') -and $null -ne $data.prompt_ref) {
        $promptRef = ([string]$data.prompt_ref).Replace('\', '/')
        if ($promptRef -cnotmatch '^prompts/[a-z0-9][a-z0-9-]*\.md$' -or -not (Test-Path -LiteralPath (Join-Path $rootPath $promptRef) -PathType Leaf)) {
            Add-Issue "$($Document.RelativePath): prompt_ref не указывает на существующий portable prompt."
        }
    }

    $phaseMatches = [regex]::Matches($Document.Body, '(?m)^## Фаза (?<id>P[1-9][0-9]*) - \[(?<state> |WIP|x)\]\s+.+$')
    if ($phaseMatches.Count -eq 0) { Add-Issue "$($Document.RelativePath): отсутствуют фазы со стабильными IDs." }
    $phaseIds = @($phaseMatches | ForEach-Object { $_.Groups['id'].Value })
    if (@($phaseIds | Sort-Object -Unique).Count -ne $phaseIds.Count) { Add-Issue "$($Document.RelativePath): phase IDs должны быть уникальны." }
    $wip = @($phaseMatches | Where-Object { $_.Groups['state'].Value -ceq 'WIP' })
    $current = if ($data.Contains('current_phase') -and $null -ne $data.current_phase) { [string]$data.current_phase } else { '' }
    if ($current -and $current -cnotin $phaseIds) { Add-Issue "$($Document.RelativePath): current_phase отсутствует в body." }
    if ($status -ceq 'planned' -and ($current -or $wip.Count -gt 0)) { Add-Issue "$($Document.RelativePath): planned plan не может иметь current_phase или WIP." }
    if ($status -cin @('in-progress', 'blocked')) {
        if (-not $current -or $wip.Count -ne 1 -or ($wip.Count -eq 1 -and $wip[0].Groups['id'].Value -cne $current)) {
            Add-Issue "$($Document.RelativePath): active plan требует одну WIP-фазу, совпадающую с current_phase."
        }
    }

    $checkpointHeader = [regex]::Matches($Document.Body, '(?m)^## Resume checkpoint\s*$')
    if ($checkpointHeader.Count -ne 1) { Add-Issue "$($Document.RelativePath): требуется один раздел Resume checkpoint." }
    $checkpointLabels = @('Текущая фаза', 'Уже выполнено', 'Последние успешные проверки', 'Точные рабочие paths', 'Git checkpoint', 'Следующее действие', 'Блокеры', 'Обновлено')
    if ($status -cin @('in-progress', 'blocked', 'complete')) {
        foreach ($label in $checkpointLabels) {
            $value = Get-CheckpointValue -Body $Document.Body -Label $label
            if ([string]::IsNullOrWhiteSpace($value) -or $value -match '^\{\{.+\}\}$') { Add-Issue "$($Document.RelativePath): checkpoint '$label' не заполнен." }
        }
        $checkpointUpdated = Get-CheckpointValue -Body $Document.Body -Label 'Обновлено'
        if ($data.Contains('updated_at') -and $checkpointUpdated -notlike ('*' + [string]$data.updated_at + '*')) {
            Add-Issue "$($Document.RelativePath): checkpoint Обновлено не совпадает с updated_at."
        }
        $gitCheckpoint = Get-CheckpointValue -Body $Document.Body -Label 'Git checkpoint'
        if ($gitCheckpoint -cnotmatch '^v1:[0-9a-f]{64}$') { Add-Issue "$($Document.RelativePath): Git checkpoint имеет неверный формат." }
    }

    if ($status -ceq 'blocked') {
        if (-not $data.Contains('blocked_reason') -or [string]::IsNullOrWhiteSpace([string]$data.blocked_reason)) { Add-Issue "$($Document.RelativePath): blocked plan требует blocked_reason." }
        $next = Get-CheckpointValue -Body $Document.Body -Label 'Следующее действие'
        if ([string]::IsNullOrWhiteSpace($next) -or $next -ceq 'нет') { Add-Issue "$($Document.RelativePath): blocked plan требует следующее действие." }
    }
    elseif ($data.Contains('blocked_reason') -and $null -ne $data.blocked_reason) {
        Add-Issue "$($Document.RelativePath): blocked_reason допустим только для blocked."
    }

    if ($status -ceq 'complete') {
        if ($current -or $wip.Count -gt 0 -or $Document.Body -match '(?m)^## Фаза P[1-9][0-9]* - \[ \]' -or $Document.Body -match '(?m)^\s*- \[ \]') {
            Add-Issue "$($Document.RelativePath): complete plan содержит незавершенную работу."
        }
        if (-not $data.Contains('completed_at') -or [string]$data.completed_at -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') { Add-Issue "$($Document.RelativePath): complete plan требует completed_at." }
        if (-not $data.Contains('closeout_status') -or [string]$data.closeout_status -cne 'complete') { Add-Issue "$($Document.RelativePath): complete plan требует closeout_status complete." }
        if (-not $data.Contains('knowledge_outcome') -or $null -eq $data.knowledge_outcome -or [string]$data.knowledge_outcome -cnotmatch '^(?:none|existing|ready:KC-[0-9]{8}-[a-z0-9-]+|applied:KC-[0-9]{8}-[a-z0-9-]+)$') {
            Add-Issue "$($Document.RelativePath): complete plan требует финальный knowledge_outcome."
        }
        if (@($data.result_refs).Count -eq 0) { Add-Issue "$($Document.RelativePath): complete plan требует result_refs." }
        foreach ($reference in @($data.result_refs)) {
            $clean = ([string]$reference -split '#', 2)[0].Replace('\', '/')
            if ($clean -match '^(?:[A-Za-z]:|/|\\|https?:)' -or $clean -match '(^|/)\.\.(/|$)' -or -not (Test-Path -LiteralPath (Join-Path $rootPath $clean))) {
                Add-Issue "$($Document.RelativePath): result_ref не существует или небезопасен: $reference."
            }
        }
        $checksMatch = [regex]::Match($Document.Body, '(?ms)^## Проверки[ \t]*\r?\n(?<value>.*?)(?=^## |\z)')
        if (-not $checksMatch.Success -or [string]::IsNullOrWhiteSpace($checksMatch.Groups['value'].Value)) { Add-Issue "$($Document.RelativePath): complete plan требует заполненные проверки." }
        $resultMatch = [regex]::Match($Document.Body, '(?ms)^## Итог[ \t]*\r?\n(?<value>.+)\z')
        if (-not $resultMatch.Success -or [string]::IsNullOrWhiteSpace($resultMatch.Groups['value'].Value)) { Add-Issue "$($Document.RelativePath): complete plan требует итог." }
    }
    else {
        if ($data.Contains('completed_at') -and $null -ne $data.completed_at) { Add-Issue "$($Document.RelativePath): completed_at допустим только для complete." }
        if ($data.Contains('closeout_status') -and [string]$data.closeout_status -cnotin @('pending', 'blocked')) { Add-Issue "$($Document.RelativePath): незавершенный plan имеет некорректный closeout_status." }
    }
}

function Test-PromptContracts {
    $promptRoot = Join-Path $rootPath 'prompts'
    if (-not (Test-Path -LiteralPath $promptRoot -PathType Container)) { Add-Issue 'Отсутствует prompts/.'; return }
    foreach ($file in @(Get-ChildItem -LiteralPath $promptRoot -File -Filter '*.md' | Where-Object Name -cne 'README.md' | Sort-Object Name)) {
        $relative = Get-ModelProjectPlanRelativePath -Root $rootPath -Path $file.FullName
        try { $document = Read-ModelProjectPlanDocument -Path $file.FullName -Root $rootPath } catch { Add-Issue "${relative}: $($_.Exception.Message)"; continue }
        $fields = @('artifact_kind', 'prompt_contract_version', 'plan_policy')
        foreach ($field in $fields) { if (-not $document.Data.Contains($field)) { Add-Issue "${relative}: отсутствует prompt field $field." } }
        if ($document.Data.Contains('artifact_kind') -and [string]$document.Data.artifact_kind -cne 'codex-prompt') { Add-Issue "${relative}: artifact_kind должен быть codex-prompt." }
        if ($document.Data.Contains('prompt_contract_version') -and [string]$document.Data.prompt_contract_version -cne '1') { Add-Issue "${relative}: prompt_contract_version должен быть 1." }
        $policy = if ($document.Data.Contains('plan_policy')) { [string]$document.Data.plan_policy } else { '' }
        if ($policy -cnotin @('none', 'required', 'existing')) { Add-Issue "${relative}: неизвестный plan_policy '$policy'."; continue }
        if ($policy -ceq 'required') {
            foreach ($token in @('scripts/new-plan.ps1', 'scripts/set-plan-status.ps1', 'Resume checkpoint', 'task_key', 'не создавай второй', 'PLAN_ACTION=existing', 'PLAN_ACTION=created', 'mastery/INTENTS.json', 'mastery/local/INDEX.md', 'Метод выполнения')) {
                if ($document.Body.IndexOf($token, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { Add-Issue "${relative}: required prompt не содержит preflight token '$token'." }
            }
            $createPosition = $document.Body.IndexOf('scripts/new-plan.ps1', [System.StringComparison]::OrdinalIgnoreCase)
            $existingActionPosition = $document.Body.IndexOf('PLAN_ACTION=existing', [System.StringComparison]::OrdinalIgnoreCase)
            $createdActionPosition = $document.Body.IndexOf('PLAN_ACTION=created', [System.StringComparison]::OrdinalIgnoreCase)
            $intentPosition = $document.Body.IndexOf('mastery/INTENTS.json', [System.StringComparison]::OrdinalIgnoreCase)
            if ($existingActionPosition -le $createPosition -or $createdActionPosition -le $createPosition -or $intentPosition -le $createdActionPosition) {
                Add-Issue "${relative}: required prompt выбирает новый method до ветвления результата new-plan."
            }
            $workPosition = $document.Body.IndexOf('начинай', [System.StringComparison]::OrdinalIgnoreCase)
            if ($workPosition -ge 0 -and $createPosition -gt $workPosition) { Add-Issue "${relative}: реализация разрешена до plan preflight." }
        }
        elseif ($policy -ceq 'existing') {
            if ($document.Body.IndexOf('<PLAN_REF>', [System.StringComparison]::Ordinal) -lt 0) { Add-Issue "${relative}: existing prompt обязан требовать <PLAN_REF>." }
            if ($document.Body.IndexOf('Resume checkpoint', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { Add-Issue "${relative}: existing prompt обязан перечитать Resume checkpoint." }
        }
        elseif ($document.Body -match '(?im)^\s*(?:реализуй|исправь|внеси изменения|выполни миграцию|опубликуй)\b') {
            Add-Issue "${relative}: plan_policy none содержит прямую команду предметного изменения."
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($MethodPlanRef)) {
    $normalizedMethodPlanRef = $MethodPlanRef.Replace('\', '/')
    if ($normalizedMethodPlanRef -cnotmatch '^plans/\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*\.md$') {
        Add-Issue 'MethodPlanRef должен быть переносимым путем Plan v2.'
    }
    else {
        $methodPlanPath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $normalizedMethodPlanRef))
        try {
            $methodPlan = Read-ModelProjectPlanDocument -Path $methodPlanPath -Root $rootPath
            if (-not $methodPlan.Data.Contains('plan_contract_version') -or [string]$methodPlan.Data.plan_contract_version -cne '2') {
                Add-Issue "$normalizedMethodPlanRef`: method gate поддерживает только Plan v2."
            }
            else {
                $methodPlanStatus = if ($methodPlan.Data.Contains('status')) { [string]$methodPlan.Data.status } else { '' }
                Test-MethodSelection -Document $methodPlan -Status $methodPlanStatus
            }
        }
        catch { Add-Issue "$normalizedMethodPlanRef`: method selection не читается." }
    }
    Test-CanonicalMethodKnowledge
    if ($issues.Count -gt 0) {
        Write-Host "FAIL: Plan method selection problems - $($issues.Count)." -ForegroundColor Red
        $issues | Sort-Object -Unique | ForEach-Object { Write-Host "- $_" }
        exit 1
    }
    Write-Host 'PASS: Plan Local Mastery selection корректен.'
    exit 0
}

$manifestPath = Join-Path $rootPath '.template-manifest.json'
$legacyAllowed = @{}
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($path in @($manifest.source_only_paths)) { $legacyAllowed[([string]$path).Replace('\', '/')] = $true }
    }
    catch { Add-Issue 'Не удалось прочитать source_only_paths для legacy plan gate.' }
}

$activeByTask = @{}
foreach ($file in @(Get-ModelProjectPlanFiles -Root $rootPath)) {
    try { $document = Read-ModelProjectPlanDocument -Path $file.FullName -Root $rootPath } catch { Add-Issue $_.Exception.Message; continue }
    $isV2 = $document.Data.Contains('plan_contract_version') -and [string]$document.Data.plan_contract_version -ceq '2'
    if (-not $isV2) {
        if (-not $legacyAllowed.ContainsKey($document.RelativePath)) { Add-Issue "$($document.RelativePath): legacy plan допустим только как manifest-declared source-only history." }
        continue
    }
    Test-V2Plan -Document $document
    if ($document.Data.Contains('status') -and [string]$document.Data.status -cin @('planned', 'in-progress', 'blocked') -and $document.Data.Contains('task_key')) {
        $key = [string]$document.Data.task_key
        if (-not $activeByTask.ContainsKey($key)) { $activeByTask[$key] = [System.Collections.Generic.List[string]]::new() }
        $activeByTask[$key].Add($document.RelativePath)
    }
}
foreach ($key in $activeByTask.Keys) {
    if ($activeByTask[$key].Count -gt 1) { Add-Issue "task_key '$key' имеет несколько активных plans: $($activeByTask[$key] -join ', ')." }
}

Test-PromptContracts
try { [void](Update-ModelProjectPlanIndex -Root $rootPath -Mode Check) } catch { Add-Issue $_.Exception.Message }
Test-CanonicalMethodKnowledge

if ($issues.Count -gt 0) {
    Write-Host "FAIL: Plan contract problems - $($issues.Count)." -ForegroundColor Red
    $issues | Sort-Object -Unique | ForEach-Object { Write-Host "- $_" }
    exit 1
}

if ($Report) { Write-Host 'REPORT: Plan v2 schema, Local Mastery selection, active uniqueness, prompt contracts and deterministic index checked.' }
Write-Host 'PASS: Plan v2 contract корректен.'
exit 0
