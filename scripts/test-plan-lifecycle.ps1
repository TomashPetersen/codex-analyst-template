[CmdletBinding()]
param([string]$Root = '')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$sourceRoot = if ([string]::IsNullOrWhiteSpace($Root)) { Split-Path -Parent $PSScriptRoot } else { [System.IO.Path]::GetFullPath($Root) }
Import-Module (Join-Path $sourceRoot 'scripts/lib/ModelProject.Platform.psm1') -Force
$pwshPath = Get-ModelProjectPowerShellHost -ControlledRoots @($sourceRoot)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$tempBase = [System.IO.Path]::GetFullPath((Resolve-ModelProjectFileSystemLinkPath -Path ([System.IO.Path]::GetTempPath()))).TrimEnd([char[]]'\/')
$tempRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('model-project-plan-fixture-' + [guid]::NewGuid().ToString('N'))))
$tempComparison = Get-ModelProjectPathComparison -Path $tempBase
$tempPrefix = $tempBase + [System.IO.Path]::DirectorySeparatorChar
if (-not $tempRoot.StartsWith($tempPrefix, $tempComparison) -or
    [System.IO.Path]::GetFileName($tempRoot) -cnotmatch '^model-project-plan-fixture-[0-9a-f]{32}$') {
    throw 'Unsafe fixture root.'
}

function Write-FixtureText {
    param([string]$Path, [string]$Content)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [void](New-Item -ItemType Directory -Path $directory -Force) }
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Invoke-ScriptExpected {
    param([string]$Script, [string[]]$Arguments, [int[]]$ExpectedExitCodes = @(0))
    $output = @(& $pwshPath -NoProfile -File $Script @Arguments 2>&1)
    $code = $LASTEXITCODE
    if ($code -cnotin $ExpectedExitCodes) {
        throw "Unexpected exit $code for $Script. Output: $($output -join ' | ')"
    }
    return $output
}

function Fill-Checkpoint {
    param([string]$PlanPath)
    $content = [System.IO.File]::ReadAllText($PlanPath)
    $content = $content.Replace('- Уже выполнено:', '- Уже выполнено: plan contract fixture prepared.')
    $content = $content.Replace('- Последние успешные проверки:', '- Последние успешные проверки: schema preflight PASS.')
    $content = $content.Replace('- Точные рабочие paths:', '- Точные рабочие paths: plans/ and changed.txt.')
    $content = $content.Replace('- Следующее действие:', '- Следующее действие: execute fixture phase.')
    $content = $content.Replace('- Блокеры:', '- Блокеры: нет.')
    Write-FixtureText -Path $PlanPath -Content $content
}

function Set-MethodSelection {
    param(
        [string]$PlanPath,
        [string]$IntentId = 'implementation',
        [string]$MethodId = 'none',
        [string]$MethodRef = 'none'
    )
    $content = [System.IO.File]::ReadAllText($PlanPath)
    $content = $content.Replace('- Intent ID: pending', "- Intent ID: $IntentId")
    $content = $content.Replace('- Local method ID: none', "- Local method ID: $MethodId")
    $content = $content.Replace('- Local method ref: none', "- Local method ref: $MethodRef")
    Write-FixtureText -Path $PlanPath -Content $content
}

try {
    [void](New-Item -ItemType Directory -Path (Join-Path $tempRoot 'plans') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $tempRoot 'prompts') -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $tempRoot 'mastery/local') -Force)
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'plans/TEMPLATE.md') -Destination (Join-Path $tempRoot 'plans/TEMPLATE.md')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'mastery/INTENTS.json') -Destination (Join-Path $tempRoot 'mastery/INTENTS.json')
    Write-FixtureText -Path (Join-Path $tempRoot '.template-manifest.json') -Content @'
{
  "source_only_paths": []
}
'@
    Write-FixtureText -Path (Join-Path $tempRoot 'prompts/required.md') -Content @'
---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: required
---
# Required
До записи вызови scripts/new-plan.ps1 по task_key и не создавай второй plan. При PLAN_ACTION=existing сначала прочитай plan и Resume checkpoint. Только при PLAN_ACTION=created выбери intent через mastery/INTENTS.json, проверь mastery/local/INDEX.md и заполни Метод выполнения. После этого вызови scripts/set-plan-status.ps1. Только после preflight начинай работу.
'@
    Write-FixtureText -Path (Join-Path $tempRoot 'prompts/existing.md') -Content @'
---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: existing
---
# Existing
Продолжи <PLAN_REF>, сначала прочитай Resume checkpoint.
'@
    Write-FixtureText -Path (Join-Path $tempRoot 'prompts/none.md') -Content @'
---
artifact_kind: codex-prompt
prompt_contract_version: 1
plan_policy: none
---
# None
Выполни read-only review и ничего не меняй.
'@
    & git -C $tempRoot init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'git init fixture failed.' }

    $newPlanScript = Join-Path $sourceRoot 'scripts/new-plan.ps1'
    $setStatusScript = Join-Path $sourceRoot 'scripts/set-plan-status.ps1'
    $updateCheckpointScript = Join-Path $sourceRoot 'scripts/update-plan-checkpoint.ps1'
    $updateIndexScript = Join-Path $sourceRoot 'scripts/update-plan-index.ps1'
    $updateMasteryIndexScript = Join-Path $sourceRoot 'scripts/update-mastery-index.ps1'
    $assertResumeScript = Join-Path $sourceRoot 'scripts/assert-plan-resume.ps1'
    $verifyScript = Join-Path $sourceRoot 'scripts/verify-plans.ps1'
    [void](Invoke-ScriptExpected -Script $updateMasteryIndexScript -Arguments @('-Root', $tempRoot, '-Mode', 'Write'))

    $created = @(Invoke-ScriptExpected -Script $newPlanScript -Arguments @('-Root', $tempRoot, '-TaskKey', 'fixture-task', '-Title', 'Fixture task', '-PromptRef', 'prompts/required.md'))
    if (($created -join "`n") -notmatch 'PLAN_ACTION=created') { throw 'new-plan did not create plan.' }
    $existing = @(Invoke-ScriptExpected -Script $newPlanScript -Arguments @('-Root', $tempRoot, '-TaskKey', 'fixture-task', '-Title', 'Fixture task', '-PromptRef', 'prompts/required.md'))
    if (($existing -join "`n") -notmatch 'PLAN_ACTION=existing') { throw 'new-plan did not reuse active plan.' }
    if (@(Get-ChildItem -LiteralPath (Join-Path $tempRoot 'plans') -Filter '*fixture-task.md').Count -ne 1) { throw 'new-plan created a duplicate.' }
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot))

    $planPath = @(Get-ChildItem -LiteralPath (Join-Path $tempRoot 'plans') -Filter '*fixture-task.md')[0].FullName
    $planRef = 'plans/' + [System.IO.Path]::GetFileName($planPath)
    Fill-Checkpoint -PlanPath $planPath
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $planRef, '-Status', 'in-progress') -ExpectedExitCodes @(1))
    Set-MethodSelection -PlanPath $planPath
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $planRef, '-Status', 'in-progress'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot))
    [void](Invoke-ScriptExpected -Script $assertResumeScript -Arguments @('-Root', $tempRoot, '-PlanRef', $planRef))
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $planRef, '-Status', 'planned') -ExpectedExitCodes @(1))

    $validPlan = [System.IO.File]::ReadAllText($planPath)

    $noneCreated = @(Invoke-ScriptExpected -Script $newPlanScript -Arguments @('-Root', $tempRoot, '-TaskKey', 'registry-none', '-Title', 'Registry none'))
    $noneRef = (($noneCreated | Where-Object { [string]$_ -like 'PLAN_REF=*' }) -replace '^PLAN_REF=', '')
    $nonePath = Join-Path $tempRoot $noneRef
    Fill-Checkpoint -PlanPath $nonePath
    Set-MethodSelection -PlanPath $nonePath
    [System.IO.File]::AppendAllText((Join-Path $tempRoot 'mastery/local/INDEX.md'), "registry drift`n", $utf8NoBom)
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot) -ExpectedExitCodes @(1))
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $noneRef, '-Status', 'in-progress') -ExpectedExitCodes @(1))
    [void](Invoke-ScriptExpected -Script $updateMasteryIndexScript -Arguments @('-Root', $tempRoot, '-Mode', 'Write'))
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $noneRef, '-Status', 'in-progress'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot))

    Write-FixtureText -Path $planPath -Content ($validPlan.Replace('- Intent ID: implementation', '- Intent ID: pending'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot) -ExpectedExitCodes @(1))
    Write-FixtureText -Path $planPath -Content ($validPlan.Replace('- Intent ID: implementation', '- Intent ID: unknown-intent'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot) -ExpectedExitCodes @(1))
    Write-FixtureText -Path $planPath -Content ($validPlan.Replace('- Local method ID: none', '- Local method ID: orphan-method'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot) -ExpectedExitCodes @(1))
    Write-FixtureText -Path $planPath -Content ($validPlan.Replace('- Local method ref: none', "- Local method ID: none`n- Local method ref: none"))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot) -ExpectedExitCodes @(1))

    Write-FixtureText -Path $planPath -Content ($validPlan.Replace('- Local method ID: none', '- Local method ID: missing-method').Replace('- Local method ref: none', '- Local method ref: mastery/local/missing-method.md'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot) -ExpectedExitCodes @(1))
    Write-FixtureText -Path $planPath -Content ($validPlan.Replace('- Local method ID: none', '- Local method ID: missing-method').Replace('- Local method ref: none', '- Local method ref: mastery\\local\\missing-method.md'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot) -ExpectedExitCodes @(1))
    Write-FixtureText -Path $planPath -Content $validPlan

    Write-FixtureText -Path (Join-Path $tempRoot 'plans/duplicate.md') -Content $validPlan
    [void](Invoke-ScriptExpected -Script $updateIndexScript -Arguments @('-Root', $tempRoot, '-Mode', 'Write'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot) -ExpectedExitCodes @(1))
    Remove-Item -LiteralPath (Join-Path $tempRoot 'plans/duplicate.md') -Force
    [void](Invoke-ScriptExpected -Script $updateIndexScript -Arguments @('-Root', $tempRoot, '-Mode', 'Write'))

    Write-FixtureText -Path $planPath -Content ($validPlan.Replace('current_phase: P1', 'current_phase: P9'))
    [void](Invoke-ScriptExpected -Script $updateIndexScript -Arguments @('-Root', $tempRoot, '-Mode', 'Write'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot) -ExpectedExitCodes @(1))
    Write-FixtureText -Path $planPath -Content $validPlan
    [void](Invoke-ScriptExpected -Script $updateIndexScript -Arguments @('-Root', $tempRoot, '-Mode', 'Write'))

    $indexPath = Join-Path $tempRoot 'plans/INDEX.md'
    $validIndex = [System.IO.File]::ReadAllText($indexPath)
    Write-FixtureText -Path $indexPath -Content ($validIndex + "manual drift`n")
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot) -ExpectedExitCodes @(1))
    [void](Invoke-ScriptExpected -Script $updateIndexScript -Arguments @('-Root', $tempRoot, '-Mode', 'Write'))

    $requiredPromptPath = Join-Path $tempRoot 'prompts/required.md'
    $validPrompt = [System.IO.File]::ReadAllText($requiredPromptPath)
    Write-FixtureText -Path $requiredPromptPath -Content ($validPrompt.Replace('scripts/new-plan.ps1', 'missing-plan-command'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot) -ExpectedExitCodes @(1))
    Write-FixtureText -Path $requiredPromptPath -Content ($validPrompt.Replace('mastery/INTENTS.json', 'missing-intent-catalog'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot) -ExpectedExitCodes @(1))
    Write-FixtureText -Path $requiredPromptPath -Content $validPrompt

    Write-FixtureText -Path (Join-Path $tempRoot 'changed.txt') -Content "fixture change`n"
    [void](Invoke-ScriptExpected -Script $assertResumeScript -Arguments @('-Root', $tempRoot, '-PlanRef', $planRef) -ExpectedExitCodes @(2))
    [void](Invoke-ScriptExpected -Script $updateCheckpointScript -Arguments @(
        '-Root', $tempRoot, '-PlanRef', $planRef, '-CurrentPhase', 'P1',
        '-Completed', 'fixture change created.', '-Checks', 'drift fixture PASS.',
        '-WorkingPaths', 'changed.txt and plans/.', '-NextAction', 'complete fixture plan.'
    ))
    [void](Invoke-ScriptExpected -Script $assertResumeScript -Arguments @('-Root', $tempRoot, '-PlanRef', $planRef))

    $content = [System.IO.File]::ReadAllText($planPath)
    $content = $content.Replace('## Фаза P1 - [WIP]', '## Фаза P1 - [x]')
    $content = $content.Replace('- [ ]', '- [x]')
    $content = $content.Replace('closeout_status: pending', 'closeout_status: complete')
    $content = $content.Replace('knowledge_outcome: null', 'knowledge_outcome: none')
    $content = $content.Replace('result_refs: []', "result_refs:`n  - changed.txt")
    $content = [regex]::Replace($content, '(?m)^## Проверки\r?$', "## Проверки`n`n- PASS fixture.", 1)
    Write-FixtureText -Path $planPath -Content $content
    $withoutSelection = [regex]::Replace($content, '(?ms)^## Метод выполнения\s*\r?\n.*?(?=^## Границы\s*$)', '')
    Write-FixtureText -Path $planPath -Content $withoutSelection
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $planRef, '-Status', 'complete') -ExpectedExitCodes @(1))
    Write-FixtureText -Path $planPath -Content $content
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $planRef, '-Status', 'complete'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot))
    $completePlan = [System.IO.File]::ReadAllText($planPath)
    $legacyComplete = [regex]::Replace($completePlan, '(?ms)^## Метод выполнения\s*\r?\n.*?(?=^## Границы\s*$)', '')
    Write-FixtureText -Path $planPath -Content $legacyComplete
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot))
    Write-FixtureText -Path $planPath -Content $completePlan
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $planRef, '-Status', 'in-progress') -ExpectedExitCodes @(1))

    $blockedCreate = @(Invoke-ScriptExpected -Script $newPlanScript -Arguments @('-Root', $tempRoot, '-TaskKey', 'blocked-flow', '-Title', 'Blocked flow'))
    $blockedRef = (($blockedCreate | Where-Object { [string]$_ -like 'PLAN_REF=*' }) -replace '^PLAN_REF=', '')
    $blockedPath = Join-Path $tempRoot $blockedRef
    Fill-Checkpoint -PlanPath $blockedPath
    Set-MethodSelection -PlanPath $blockedPath -IntentId 'review'
    [System.IO.File]::AppendAllText((Join-Path $tempRoot 'mastery/local/INDEX.md'), "registry drift`n", $utf8NoBom)
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $blockedRef, '-Status', 'blocked', '-BlockedReason', 'waiting for authority'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot, '-MethodPlanRef', $blockedRef) -ExpectedExitCodes @(1))
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $blockedRef, '-Status', 'in-progress') -ExpectedExitCodes @(1))
    [void](Invoke-ScriptExpected -Script $updateMasteryIndexScript -Arguments @('-Root', $tempRoot, '-Mode', 'Write'))
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $blockedRef, '-Status', 'in-progress'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot))

    $catalogBlockedCreate = @(Invoke-ScriptExpected -Script $newPlanScript -Arguments @('-Root', $tempRoot, '-TaskKey', 'catalog-blocked', '-Title', 'Catalog blocked'))
    $catalogBlockedRef = (($catalogBlockedCreate | Where-Object { [string]$_ -like 'PLAN_REF=*' }) -replace '^PLAN_REF=', '')
    $catalogBlockedPath = Join-Path $tempRoot $catalogBlockedRef
    Fill-Checkpoint -PlanPath $catalogBlockedPath
    $catalogPath = Join-Path $tempRoot 'mastery/INTENTS.json'
    $validCatalog = [System.IO.File]::ReadAllText($catalogPath)
    Write-FixtureText -Path $catalogPath -Content "{}`n"
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $catalogBlockedRef, '-Status', 'blocked', '-BlockedReason', 'intent catalog is unavailable'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot, '-MethodPlanRef', $catalogBlockedRef) -ExpectedExitCodes @(1))
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $catalogBlockedRef, '-Status', 'in-progress') -ExpectedExitCodes @(1))
    Write-FixtureText -Path $catalogPath -Content $validCatalog
    Set-MethodSelection -PlanPath $catalogBlockedPath -IntentId 'review'
    [void](Invoke-ScriptExpected -Script $setStatusScript -Arguments @('-Root', $tempRoot, '-PlanRef', $catalogBlockedRef, '-Status', 'in-progress'))
    [void](Invoke-ScriptExpected -Script $verifyScript -Arguments @('-Root', $tempRoot))

    $agentsText = [System.IO.File]::ReadAllText((Join-Path $sourceRoot 'AGENTS.md'))
    if ($agentsText -notmatch 'plans/INDEX\.md' -or $agentsText -notmatch 'Resume checkpoint' -or $agentsText -notmatch 'assert-plan-resume\.ps1' -or
        $agentsText -notmatch 'generated-project.*update-knowledge-graph\.ps1' -or $agentsText -notmatch 'template-source.*TEMPLATE\.md') {
        throw 'AGENTS.md не обеспечивает session rediscovery route.'
    }
    $deliveryText = [System.IO.File]::ReadAllText((Join-Path $sourceRoot '.agents/skills/project-delivery/SKILL.md'))
    if ($deliveryText -notmatch 'mastery/INTENTS\.json' -or $deliveryText -notmatch 'mastery/local/INDEX\.md' -or $deliveryText -notmatch 'Метод выполнения') {
        throw 'project-delivery не обеспечивает Local Mastery retrieval route.'
    }
    $policyPosition = $deliveryText.IndexOf('Определи `plan_policy`', [System.StringComparison]::Ordinal)
    $intentPosition = $deliveryText.IndexOf('mastery/INTENTS.json', [System.StringComparison]::Ordinal)
    $existingPosition = $deliveryText.IndexOf('Для `existing` сначала', [System.StringComparison]::Ordinal)
    $newPlanPosition = $deliveryText.IndexOf('scripts/new-plan.ps1', [System.StringComparison]::Ordinal)
    $requiredExistingPosition = $deliveryText.IndexOf('PLAN_ACTION=existing', [System.StringComparison]::Ordinal)
    $createdPosition = $deliveryText.IndexOf('PLAN_ACTION=created', [System.StringComparison]::Ordinal)
    if ($policyPosition -lt 0 -or $existingPosition -le $policyPosition -or $newPlanPosition -le $existingPosition -or
        $requiredExistingPosition -le $newPlanPosition -or $createdPosition -le $requiredExistingPosition -or $intentPosition -le $createdPosition) {
        throw 'project-delivery не сохраняет existing selection до created-only method selection.'
    }
    $planReadmeText = [System.IO.File]::ReadAllText((Join-Path $sourceRoot 'plans/README.md'))
    $readmeExistingPosition = $planReadmeText.IndexOf('PLAN_ACTION=existing', [System.StringComparison]::Ordinal)
    $readmeCreatedPosition = $planReadmeText.IndexOf('PLAN_ACTION=created', [System.StringComparison]::Ordinal)
    $readmeIntentPosition = $planReadmeText.IndexOf('mastery/INTENTS.json', [System.StringComparison]::Ordinal)
    if ($readmeExistingPosition -lt 0 -or $readmeCreatedPosition -le $readmeExistingPosition -or $readmeIntentPosition -le $readmeCreatedPosition) {
        throw 'plans/README.md не сохраняет existing selection до created-only method selection.'
    }
    Write-Host 'PASS: Plan v2 lifecycle, Local Mastery selection, deduplication, prompt preflight, deterministic index and resume drift fixtures passed.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        if (-not $tempRoot.StartsWith($tempPrefix, $tempComparison) -or
            [System.IO.Path]::GetFileName($tempRoot) -cnotmatch '^model-project-plan-fixture-[0-9a-f]{32}$') {
            throw 'Unsafe fixture cleanup target.'
        }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
