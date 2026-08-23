[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PlanRef,

    [Parameter(Mandatory = $true)]
    [ValidateSet('planned', 'in-progress', 'complete', 'blocked')]
    [string]$Status,

    [string]$CurrentPhase = '',

    [string]$BlockedReason = '',

    [string]$Root = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Plan.psm1'
Import-Module $modulePath -Force
$platformModulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Platform.psm1'
Import-Module $platformModulePath -Force

function Assert-SafeSingleLine {
    param([string]$Value, [string]$Label, [int]$MaxLength = 300)
    if ($Value.Length -gt $MaxLength -or $Value -match '[\r\n\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' -or $Value -match '\x1B\[') {
        throw "$Label содержит запрещенные символы или превышает лимит."
    }
}

function Set-PhaseMarker {
    param([string]$Content, [string]$PhaseId, [string]$Marker)
    $pattern = '(?m)^(## Фаза ' + [regex]::Escape($PhaseId) + ' - )\[(?: |WIP|x)\](?<tail>\s+.+)$'
    $matches = [regex]::Matches($Content, $pattern)
    if ($matches.Count -ne 1) { throw "Фаза $PhaseId отсутствует или неоднозначна в body." }
    return [regex]::Replace(
        $Content,
        $pattern,
        [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $match.Groups[1].Value + '[' + $Marker + ']' + $match.Groups['tail'].Value },
        1
    )
}

function Set-CheckpointLine {
    param([string]$Content, [string]$Label, [string]$Value)
    $pattern = '(?m)^- ' + [regex]::Escape($Label) + ':.*$'
    if ([regex]::Matches($Content, $pattern).Count -ne 1) { throw "Checkpoint field '$Label' отсутствует или неоднозначен." }
    $replacement = '- ' + $Label + ': ' + $Value
    return [regex]::Replace($Content, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement }, 1)
}

try {
    $rootPath = Get-ModelProjectPlanRoot -Root $Root
    Assert-SafeSingleLine -Value $PlanRef -Label 'PlanRef' -MaxLength 220
    Assert-SafeSingleLine -Value $CurrentPhase -Label 'CurrentPhase' -MaxLength 20
    Assert-SafeSingleLine -Value $BlockedReason -Label 'BlockedReason'
    $normalizedRef = $PlanRef.Replace('\', '/')
    if ($normalizedRef -cnotmatch '^plans/\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*\.md$') {
        throw 'PlanRef должен быть переносимым путем plans/YYYY-MM-DD-<task-key>.md.'
    }
    $planPath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $normalizedRef))
    $plansRoot = [System.IO.Path]::GetFullPath((Join-Path $rootPath 'plans'))
    if (-not (Test-ModelProjectPathWithinRoot -Root $plansRoot -Path $planPath)) {
        throw 'PlanRef выходит за plans/.'
    }
    if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { throw "Plan не найден: $normalizedRef" }
    if ((Get-Item -LiteralPath $planPath -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw 'Plan не может быть link или reparse point.'
    }

    $document = Read-ModelProjectPlanDocument -Path $planPath -Root $rootPath
    if ([string]$document.Data.plan_contract_version -cne '2') { throw 'Transition command поддерживает только Plan v2.' }
    $oldStatus = [string]$document.Data.status
    if ($oldStatus -ceq $Status) {
        Write-Output "PLAN_ID=$($document.Data.plan_id)"
        Write-Output "PLAN_REF=$normalizedRef"
        Write-Output "PLAN_STATUS=$Status"
        Write-Output 'PLAN_ACTION=unchanged'
        exit 0
    }
    $allowed = @{
        planned = @('in-progress', 'blocked')
        'in-progress' = @('complete', 'blocked')
        blocked = @('in-progress')
        complete = @()
    }
    if (-not $allowed.ContainsKey($oldStatus) -or $Status -cnotin $allowed[$oldStatus]) {
        throw "Недопустимый переход Plan v2: $oldStatus -> $Status."
    }

    $content = $document.Content
    $timestamp = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $phase = if (-not [string]::IsNullOrWhiteSpace($CurrentPhase)) { $CurrentPhase } elseif ($null -ne $document.Data.current_phase) { [string]$document.Data.current_phase } else { '' }
    if ($phase -and $phase -cnotmatch '^P[1-9][0-9]*$') { throw 'CurrentPhase должен иметь вид P1, P2 и так далее.' }

    if ($Status -ceq 'in-progress') {
        if (-not $phase) {
            $firstPhase = [regex]::Match($document.Body, '(?m)^## Фаза (?<id>P[1-9][0-9]*) - \[ \]')
            if (-not $firstPhase.Success) { throw 'Не удалось определить первую незавершенную фазу.' }
            $phase = $firstPhase.Groups['id'].Value
        }
        $content = Set-PhaseMarker -Content $content -PhaseId $phase -Marker 'WIP'
        $content = Set-ModelProjectPlanField -Content $content -Field current_phase -Value $phase
        $content = Set-ModelProjectPlanField -Content $content -Field blocked_reason -Value $null
        $content = Set-CheckpointLine -Content $content -Label 'Текущая фаза' -Value $phase
        $content = Set-CheckpointLine -Content $content -Label 'Блокеры' -Value 'нет'
    }
    elseif ($Status -ceq 'blocked') {
        if ([string]::IsNullOrWhiteSpace($BlockedReason)) { throw 'Blocked plan требует непустой BlockedReason.' }
        if (-not $phase) {
            $firstPhase = [regex]::Match($document.Body, '(?m)^## Фаза (?<id>P[1-9][0-9]*) - \[ \]')
            if (-not $firstPhase.Success) { throw 'Не удалось определить фазу для blocked transition.' }
            $phase = $firstPhase.Groups['id'].Value
        }
        $content = Set-PhaseMarker -Content $content -PhaseId $phase -Marker 'WIP'
        $content = Set-ModelProjectPlanField -Content $content -Field current_phase -Value $phase
        $content = Set-ModelProjectPlanField -Content $content -Field blocked_reason -Value $BlockedReason
        $content = Set-CheckpointLine -Content $content -Label 'Текущая фаза' -Value $phase
        $content = Set-CheckpointLine -Content $content -Label 'Блокеры' -Value $BlockedReason
    }
    elseif ($Status -ceq 'complete') {
        if ($document.Body -match '(?m)^## Фаза P[1-9][0-9]* - \[(?: |WIP)\]' -or $document.Body -match '(?m)^\s*- \[ \]') {
            throw 'Complete plan не может содержать незакрытые фазы или checklist items.'
        }
        if ([string]$document.Data.closeout_status -cne 'complete') { throw 'Сначала выполни plan closeout и установи closeout_status: complete.' }
        if ($null -eq $document.Data.knowledge_outcome -or [string]$document.Data.knowledge_outcome -cnotmatch '^(?:none|existing|ready:KC-[0-9]{8}-[a-z0-9-]+|applied:KC-[0-9]{8}-[a-z0-9-]+)$') {
            throw 'Complete plan требует финальный knowledge_outcome.'
        }
        if (@($document.Data.result_refs).Count -eq 0) { throw 'Complete plan требует result_refs.' }
        $content = Set-ModelProjectPlanField -Content $content -Field current_phase -Value $null
        $content = Set-ModelProjectPlanField -Content $content -Field completed_at -Value $timestamp
        $content = Set-ModelProjectPlanField -Content $content -Field blocked_reason -Value $null
        $content = Set-CheckpointLine -Content $content -Label 'Текущая фаза' -Value 'нет - план завершен'
        $content = Set-CheckpointLine -Content $content -Label 'Следующее действие' -Value 'нет - plan terminal; follow-up требует новый plan_id'
        $content = Set-CheckpointLine -Content $content -Label 'Блокеры' -Value 'нет'
    }

    $content = Set-ModelProjectPlanField -Content $content -Field status -Value $Status
    $content = Set-ModelProjectPlanField -Content $content -Field updated_at -Value $timestamp
    $content = Set-CheckpointLine -Content $content -Label 'Git checkpoint' -Value (Get-ModelProjectPlanWorktreeFingerprint -Root $rootPath -PlanRef $normalizedRef)
    $content = Set-CheckpointLine -Content $content -Label 'Обновлено' -Value $timestamp
    Write-ModelProjectAtomicText -Path $planPath -Content $content
    [void](Update-ModelProjectPlanIndex -Root $rootPath -Mode Write)

    Write-Output "PLAN_ID=$($document.Data.plan_id)"
    Write-Output "PLAN_REF=$normalizedRef"
    Write-Output "PLAN_STATUS=$Status"
    Write-Output 'PLAN_ACTION=updated'
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
