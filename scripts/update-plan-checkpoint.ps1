[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PlanRef,
    [Parameter(Mandatory = $true)][string]$CurrentPhase,
    [Parameter(Mandatory = $true)][string]$Completed,
    [Parameter(Mandatory = $true)][string]$Checks,
    [Parameter(Mandatory = $true)][string]$WorkingPaths,
    [Parameter(Mandatory = $true)][string]$NextAction,
    [string]$Blockers = 'нет',
    [string]$Root = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Plan.psm1'
Import-Module $modulePath -Force

function Assert-SafeCheckpointValue {
    param([string]$Value, [string]$Label, [int]$MaxLength = 1000)
    if ([string]::IsNullOrWhiteSpace($Value)) { throw "$Label не может быть пустым." }
    if ($Value.Length -gt $MaxLength -or $Value -match '[\r\n\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' -or $Value -match '\x1B\[') {
        throw "$Label содержит запрещенные символы или превышает лимит."
    }
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
    foreach ($item in @(
        @{ Value = $PlanRef; Label = 'PlanRef'; Limit = 220 },
        @{ Value = $CurrentPhase; Label = 'CurrentPhase'; Limit = 20 },
        @{ Value = $Completed; Label = 'Completed'; Limit = 1000 },
        @{ Value = $Checks; Label = 'Checks'; Limit = 1000 },
        @{ Value = $WorkingPaths; Label = 'WorkingPaths'; Limit = 1000 },
        @{ Value = $NextAction; Label = 'NextAction'; Limit = 1000 },
        @{ Value = $Blockers; Label = 'Blockers'; Limit = 1000 }
    )) { Assert-SafeCheckpointValue -Value $item.Value -Label $item.Label -MaxLength $item.Limit }
    if ($CurrentPhase -cnotmatch '^P[1-9][0-9]*$') { throw 'CurrentPhase должен иметь вид P1, P2 и так далее.' }
    $normalizedRef = $PlanRef.Replace('\', '/')
    if ($normalizedRef -cnotmatch '^plans/\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*\.md$') { throw 'Некорректный PlanRef.' }
    $planPath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $normalizedRef))
    if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { throw "Plan не найден: $normalizedRef" }
    $document = Read-ModelProjectPlanDocument -Path $planPath -Root $rootPath
    if ([string]$document.Data.plan_contract_version -cne '2') { throw 'Checkpoint command поддерживает только Plan v2.' }
    if ([string]$document.Data.status -cnotin @('in-progress', 'blocked')) { throw 'Checkpoint обновляется только для active Plan v2.' }
    if ($document.Body -notmatch ('(?m)^## Фаза ' + [regex]::Escape($CurrentPhase) + ' - \[WIP\]')) { throw 'CurrentPhase должна совпадать с WIP-фазой.' }
    $timestamp = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $fingerprint = Get-ModelProjectPlanWorktreeFingerprint -Root $rootPath -PlanRef $normalizedRef
    $content = $document.Content
    $content = Set-ModelProjectPlanField -Content $content -Field current_phase -Value $CurrentPhase
    $content = Set-ModelProjectPlanField -Content $content -Field updated_at -Value $timestamp
    $content = Set-CheckpointLine -Content $content -Label 'Текущая фаза' -Value $CurrentPhase
    $content = Set-CheckpointLine -Content $content -Label 'Уже выполнено' -Value $Completed
    $content = Set-CheckpointLine -Content $content -Label 'Последние успешные проверки' -Value $Checks
    $content = Set-CheckpointLine -Content $content -Label 'Точные рабочие paths' -Value $WorkingPaths
    $content = Set-CheckpointLine -Content $content -Label 'Git checkpoint' -Value $fingerprint
    $content = Set-CheckpointLine -Content $content -Label 'Следующее действие' -Value $NextAction
    $content = Set-CheckpointLine -Content $content -Label 'Блокеры' -Value $Blockers
    $content = Set-CheckpointLine -Content $content -Label 'Обновлено' -Value $timestamp
    Write-ModelProjectAtomicText -Path $planPath -Content $content
    [void](Update-ModelProjectPlanIndex -Root $rootPath -Mode Write)
    Write-Output "PLAN_REF=$normalizedRef"
    Write-Output "PLAN_CHECKPOINT=$fingerprint"
    Write-Output "PLAN_UPDATED_AT=$timestamp"
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
