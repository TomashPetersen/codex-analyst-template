[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$Report
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$rootPath = if ([string]::IsNullOrWhiteSpace($Root)) { Split-Path -Parent $PSScriptRoot } else { [System.IO.Path]::GetFullPath($Root) }
$modulePath = Join-Path $PSScriptRoot 'lib/ModelProject.Knowledge.psm1'
Import-Module $modulePath -Force
$issues = [System.Collections.Generic.List[string]]::new()
$requiredCanon = [ordered]@{
    'product/overview.md' = 'product'
    'product/users-and-jobs.md' = 'product'
    'product/experience.md' = 'product'
    'product/capabilities.md' = 'product'
    'product/glossary.md' = 'product'
    'business/overview.md' = 'business'
    'business/architecture.md' = 'business'
    'business/model-and-economics.md' = 'business'
    'business/go-to-market.md' = 'business'
    'business/goals-and-metrics.md' = 'business'
    'docs/architecture/overview.md' = 'architecture'
    'docs/codebase/overview.md' = 'codebase'
}
$ownerZones = [ordered]@{
    'product' = 'product'
    'business' = 'business'
    'docs/architecture' = 'architecture'
    'docs/codebase' = 'codebase'
}
$requiredFields = @('artifact_kind', 'canon_contract_version', 'domain', 'status', 'verified_at', 'source_refs')
$serviceLeaves = @('INDEX.md', 'README.md', 'TEMPLATE.md')
$canonFiles = [ordered]@{}

foreach ($entry in $requiredCanon.GetEnumerator()) {
    $relative = [string]$entry.Key
    $path = Join-Path $rootPath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $issues.Add("$relative отсутствует.") }
}

foreach ($zone in $ownerZones.GetEnumerator()) {
    $zonePath = Join-Path $rootPath ([string]$zone.Key)
    if (-not (Test-Path -LiteralPath $zonePath -PathType Container)) { continue }
    try {
        if ($null -ne (Get-ModelProjectReparsePointInFullChain -Root $rootPath -Path $zonePath)) {
            $issues.Add("$($zone.Key): owner zone пересекает reparse point.")
            continue
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $zonePath -Recurse -File -Filter '*.md' -Force | Sort-Object FullName)) {
            $relative = Get-ModelProjectRepositoryRelativePath -Root $rootPath -Path $file.FullName
            if ($file.Name -cin $serviceLeaves -or $relative -cmatch '^business/(?:assets|analysis)/') { continue }
            if (-not (Test-ModelProjectExactPathCase -Root $rootPath -Path $file.FullName)) {
                $issues.Add("${relative}: path case не совпадает с файловой системой.")
                continue
            }
            if ($canonFiles.Contains($relative)) {
                $issues.Add("${relative}: canon path обнаружен повторно.")
                continue
            }
            $canonFiles[$relative] = [string]$zone.Value
        }
    }
    catch { $issues.Add("$($zone.Key): owner zone не прошла safe enumeration.") }
}

foreach ($entry in $canonFiles.GetEnumerator()) {
    $relative = [string]$entry.Key
    $path = Join-Path $rootPath $relative
    try { $document = Read-ModelProjectSimpleFrontMatterDocument -Root $rootPath -Path $path } catch { $issues.Add("${relative}: $($_.Exception.Message)"); continue }
    $data = $document.Data
    foreach ($field in $requiredFields) { if (-not $data.Contains($field)) { $issues.Add("${relative}: отсутствует $field.") } }
    foreach ($field in @($data.Keys)) { if ($field -cnotin $requiredFields) { $issues.Add("${relative}: неизвестное canon field $field.") } }
    if ($data.Contains('artifact_kind') -and [string]$data.artifact_kind -cne 'canon') { $issues.Add("${relative}: artifact_kind должен быть canon.") }
    if ($data.Contains('canon_contract_version') -and [string]$data.canon_contract_version -cne '1') { $issues.Add("${relative}: canon_contract_version должен быть 1.") }
    if ($data.Contains('domain') -and [string]$data.domain -cne [string]$entry.Value) { $issues.Add("${relative}: domain не совпадает с owner path.") }
    $status = if ($data.Contains('status')) { [string]$data.status } else { '' }
    if ($status -cnotin @('template', 'active', 'deprecated')) { $issues.Add("${relative}: неизвестный canon status '$status'.") }
    if (-not $data.Contains('verified_at') -or ($null -ne $data.verified_at -and [string]$data.verified_at -cnotmatch '^\d{4}-\d{2}-\d{2}$')) {
        $issues.Add("${relative}: verified_at должен быть YYYY-MM-DD или null.")
    }
    if ($status -ceq 'active' -and $null -eq $data.verified_at) { $issues.Add("${relative}: active canon требует verified_at.") }
    if (-not $data.Contains('source_refs') -or $null -eq $data.source_refs -or $data.source_refs -is [string]) {
        $issues.Add("${relative}: source_refs должен быть YAML-списком.")
    }
    else {
        $refs = @($data.source_refs | ForEach-Object { [string]$_ })
        if (@($refs | Sort-Object -Unique).Count -ne $refs.Count) { $issues.Add("${relative}: source_refs содержит дубли.") }
        foreach ($reference in $refs) {
            if ($reference.Length -gt 500) { $issues.Add("${relative}: source_ref превышает лимит."); continue }
            try {
                $resolved = Resolve-ModelProjectSafeReference -Root $rootPath -SourcePath $path -Reference $reference -ReferenceBase Repository -AllowHttps -AllowLogical
                if ($resolved.Kind -ceq 'invalid' -or -not $resolved.Exists -or -not $resolved.ExactCase -or -not $resolved.AnchorExists) {
                    $issues.Add("${relative}: небезопасный или отсутствующий source_ref '$reference'.")
                }
            }
            catch { $issues.Add("${relative}: source_ref не прошел safe resolver.") }
        }
    }
    if ($document.Body -notmatch '(?m)^#\s+\S') { $issues.Add("${relative}: отсутствует H1.") }
    if (@(Get-ModelProjectSensitiveTextFindings -Text $document.Content).Count -gt 0) { $issues.Add("${relative}: найден sensitive content.") }
}

foreach ($index in @('product/INDEX.md', 'business/INDEX.md', 'docs/architecture/INDEX.md', 'docs/codebase/INDEX.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $rootPath $index) -PathType Leaf)) { $issues.Add("$index отсутствует.") }
}

if ($issues.Count -gt 0) {
    Write-Host "FAIL: Canon contract problems - $($issues.Count)." -ForegroundColor Red
    $issues | Sort-Object -Unique | ForEach-Object { Write-Host "- $_" }
    exit 1
}
if ($Report) { Write-Host "REPORT: core canon files checked - $($canonFiles.Count); formal analysis delegated to verify-analysis.ps1." }
Write-Host 'PASS: core canon owner boundaries корректны.'
exit 0
