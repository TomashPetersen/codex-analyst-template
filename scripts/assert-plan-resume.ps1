[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PlanRef,
    [string]$Root = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Plan.psm1'
Import-Module $modulePath -Force

try {
    $rootPath = Get-ModelProjectPlanRoot -Root $Root
    $normalizedRef = $PlanRef.Replace('\', '/')
    if ($normalizedRef -cnotmatch '^plans/\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*\.md$') { throw 'Некорректный PlanRef.' }
    $planPath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $normalizedRef))
    $document = Read-ModelProjectPlanDocument -Path $planPath -Root $rootPath
    $match = [regex]::Match($document.Body, '(?m)^- Git checkpoint:\s*(?<value>v1:[0-9a-f]{64})\s*$')
    if (-not $match.Success) { throw 'Plan не содержит корректный Git checkpoint.' }
    $expected = $match.Groups['value'].Value
    $actual = Get-ModelProjectPlanWorktreeFingerprint -Root $rootPath -PlanRef $normalizedRef
    if ($actual -cne $expected) {
        Write-Host 'BLOCKED: plan-worktree-drift' -ForegroundColor Red
        Write-Host "EXPECTED=$expected"
        Write-Host "ACTUAL=$actual"
        exit 2
    }
    Write-Host 'PASS: plan и worktree checkpoint совпадают.'
    Write-Output "PLAN_REF=$normalizedRef"
    Write-Output "PLAN_CHECKPOINT=$actual"
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
