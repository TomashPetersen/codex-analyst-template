[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskKey,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [string]$PromptRef = '',

    [string]$Root = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Plan.psm1'
Import-Module $modulePath -Force

function Assert-SafeSingleLine {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label,
        [int]$MaxLength = 160
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { throw "$Label не может быть пустым." }
    if ($Value.Length -gt $MaxLength) { throw "$Label превышает лимит $MaxLength символов." }
    if ($Value -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' -or $Value -match '\x1B\[' -or $Value -match '[\r\n]') {
        throw "$Label содержит запрещенные управляющие символы."
    }
}

try {
    $rootPath = Get-ModelProjectPlanRoot -Root $Root
    Assert-SafeSingleLine -Value $TaskKey -Label 'Task key' -MaxLength 64
    Assert-SafeSingleLine -Value $Title -Label 'Название' -MaxLength 160
    if ($TaskKey -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw 'Task key должен состоять из lowercase ASCII букв, цифр и одиночных дефисов.'
    }

    $active = @(Get-ModelProjectPlanActiveByTaskKey -Root $rootPath -TaskKey $TaskKey)
    if ($active.Count -gt 1) {
        throw "Найдено несколько активных plans с task_key '$TaskKey'. Сначала устрани неоднозначность."
    }
    if ($active.Count -eq 1) {
        Write-Output "PLAN_ID=$($active[0].Data.plan_id)"
        Write-Output "PLAN_REF=$($active[0].RelativePath)"
        Write-Output 'PLAN_ACTION=existing'
        exit 0
    }

    $promptScalar = $null
    if (-not [string]::IsNullOrWhiteSpace($PromptRef)) {
        Assert-SafeSingleLine -Value $PromptRef -Label 'PromptRef' -MaxLength 200
        $normalizedPrompt = $PromptRef.Replace('\', '/')
        if ($normalizedPrompt -cnotmatch '^prompts/[a-z0-9][a-z0-9-]*\.md$') {
            throw 'PromptRef должен быть переносимым путем prompts/<name>.md.'
        }
        $promptPath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $normalizedPrompt))
        if (-not (Test-Path -LiteralPath $promptPath -PathType Leaf)) {
            throw "PromptRef не существует: $normalizedPrompt"
        }
        $promptScalar = $normalizedPrompt
    }

    $templatePath = Join-Path $rootPath 'plans/TEMPLATE.md'
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw 'Отсутствует trusted plans/TEMPLATE.md.' }
    if ((Get-Item -LiteralPath $templatePath -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        throw 'plans/TEMPLATE.md не может быть link или reparse point.'
    }

    $localDate = [DateTimeOffset]::Now.ToString('yyyy-MM-dd')
    $compactDate = $localDate.Replace('-', '')
    $timestamp = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $planId = "PLAN-$compactDate-$TaskKey"
    $relativePath = "plans/$localDate-$TaskKey.md"
    $targetPath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $relativePath))
    if (Test-Path -LiteralPath $targetPath) { throw "Целевой файл уже существует: $relativePath" }

    $content = Read-ModelProjectPlanText -Path $templatePath
    $replacements = [ordered]@{
        '{{PLAN_ID}}' = $planId
        '{{TASK_KEY}}' = $TaskKey
        '{{PROMPT_REF}}' = ConvertTo-ModelProjectPlanYamlScalar -Value $promptScalar
        '{{UPDATED_AT}}' = $timestamp
        '{{TITLE}}' = $Title
        '{{GIT_CHECKPOINT}}' = Get-ModelProjectPlanWorktreeFingerprint -Root $rootPath -PlanRef $relativePath
    }
    foreach ($token in $replacements.Keys) {
        if (-not $content.Contains($token)) { throw "Trusted template не содержит token $token." }
        $content = $content.Replace($token, [string]$replacements[$token])
    }
    if ($content -match '\{\{[A-Z0-9_]+\}\}') { throw 'Trusted template содержит незаполненные machine tokens.' }

    Write-ModelProjectAtomicText -Path $targetPath -Content $content -CreateNew
    try {
        [void](Update-ModelProjectPlanIndex -Root $rootPath -Mode Write)
    }
    catch {
        Remove-Item -LiteralPath $targetPath -Force
        throw
    }

    Write-Output "PLAN_ID=$planId"
    Write-Output "PLAN_REF=$relativePath"
    Write-Output 'PLAN_ACTION=created'
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
