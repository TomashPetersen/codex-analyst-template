[CmdletBinding()]
param(
    [string]$Root = '',

    [ValidateSet('Check', 'Write', 'Report')]
    [string]$Mode = 'Check'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Plan.psm1'
Import-Module $modulePath -Force

try {
    $result = Update-ModelProjectPlanIndex -Root $Root -Mode $Mode
    if ($Mode -ceq 'Write') {
        Write-Host "PASS: plans/INDEX.md пересобран: $($result.Path)"
    }
    elseif ($result.Changed) {
        Write-Host 'REPORT: plans/INDEX.md отсутствует или устарел.'
    }
    else {
        Write-Host 'PASS: plans/INDEX.md актуален.'
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
