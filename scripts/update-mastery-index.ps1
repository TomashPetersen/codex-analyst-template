[CmdletBinding()]
param(
    [string]$Root = '',

    [ValidateSet('Check', 'Write', 'Report')]
    [string]$Mode = 'Check'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Mastery.psm1'
Import-Module $modulePath -Force

try {
    $result = Update-ModelProjectMasteryIndex -Root $Root -Mode $Mode
    if ($Mode -ceq 'Write') {
        Write-Host "PASS: mastery/local/INDEX.md пересобран: $($result.Path)"
    }
    elseif ($result.Changed) {
        Write-Host 'REPORT: mastery/local/INDEX.md отсутствует или устарел.'
    }
    else {
        Write-Host 'PASS: mastery/local/INDEX.md актуален.'
    }
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
