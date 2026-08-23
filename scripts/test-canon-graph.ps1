[CmdletBinding()]
param([string]$Root = '')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$sourceRoot = if ([string]::IsNullOrWhiteSpace($Root)) { Split-Path -Parent $PSScriptRoot } else { [System.IO.Path]::GetFullPath($Root) }
Import-Module (Join-Path $sourceRoot 'scripts/lib/ModelProject.Platform.psm1') -Force
$pwshPath = (Get-Process -Id $PID).Path
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]'\/')
$tempComparison = Get-ModelProjectPathComparison -Path $tempBase
$fixtureRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('model-project-canon-fixture-' + [guid]::NewGuid().ToString('N'))))

function Write-FixtureText {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Invoke-ScriptExpected {
    param(
        [Parameter(Mandatory = $true)][string]$Script,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int[]]$ExpectedExitCodes = @(0)
    )
    $output = @(& $pwshPath -NoProfile -File $Script @Arguments 2>&1)
    $code = $LASTEXITCODE
    if ($code -cnotin $ExpectedExitCodes) {
        throw "Unexpected exit $code for $Script. Output: $($output -join ' | ')"
    }
    return @($output | ForEach-Object { [string]$_ })
}

function New-CanonText {
    param(
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)][string]$Heading,
        [ValidateSet('template', 'active', 'deprecated')][string]$Status = 'template',
        [AllowNull()][string]$VerifiedAt = $null,
        [string[]]$SourceRefs = @(),
        [string]$Body = ''
    )
    $verifiedValue = if ([string]::IsNullOrWhiteSpace($VerifiedAt)) { 'null' } else { $VerifiedAt }
    $sourceBlock = if ($SourceRefs.Count -eq 0) {
        'source_refs: []'
    }
    else {
        "source_refs:`n" + (($SourceRefs | ForEach-Object { "  - $_" }) -join "`n")
    }
    return @"
---
artifact_kind: canon
canon_contract_version: 1
domain: $Domain
status: $Status
verified_at: $verifiedValue
$sourceBlock
---

# $Heading

$Body
"@
}

function Set-FixtureCanon {
    param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][string]$Content)
    Write-FixtureText -Path (Join-Path $fixtureRoot $RelativePath) -Content $Content
}

function Assert-CanonFailure {
    param([Parameter(Mandatory = $true)][string]$ExpectedFragment)
    $output = Invoke-ScriptExpected -Script $verifyCanonScript -Arguments @('-Root', $fixtureRoot) -ExpectedExitCodes @(1)
    if (($output -join "`n") -notmatch [regex]::Escape($ExpectedFragment)) {
        throw "Canon failure did not contain '$ExpectedFragment'. Output: $($output -join ' | ')"
    }
}

$required = [ordered]@{
    'product/overview.md' = @('product', 'Product overview')
    'product/users-and-jobs.md' = @('product', 'Users and jobs')
    'product/experience.md' = @('product', 'Experience')
    'product/capabilities.md' = @('product', 'Capabilities')
    'product/glossary.md' = @('product', 'Glossary')
    'business/overview.md' = @('business', 'Business overview')
    'business/architecture.md' = @('business', 'Business architecture')
    'business/model-and-economics.md' = @('business', 'Model and economics')
    'business/go-to-market.md' = @('business', 'Go to market')
    'business/goals-and-metrics.md' = @('business', 'Goals and metrics')
    'docs/architecture/overview.md' = @('architecture', 'Architecture overview')
    'docs/codebase/overview.md' = @('codebase', 'Codebase overview')
}

$verifyCanonScript = Join-Path $sourceRoot 'scripts/verify-canon.ps1'
$graphScript = Join-Path $sourceRoot 'scripts/update-knowledge-graph.ps1'

try {
    if (-not $fixtureRoot.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, $tempComparison)) {
        throw 'Unsafe canon fixture root.'
    }
    [System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    Write-FixtureText -Path (Join-Path $fixtureRoot '.template-manifest.json') -Content @'
{
  "schema_version": 1,
  "template_version": "1.0.0",
  "portable_files": [],
  "portable_empty_directories": [],
  "source_only_paths": [],
  "generated_forbidden_paths": [],
  "generated_extension_zones": [],
  "mastery_baseline": { "bundle_version": "1.0.0", "verified_at": "2026-08-20", "review_due": "2027-02-20", "files": [] }
}
'@
    Write-FixtureText -Path (Join-Path $fixtureRoot 'PROJECT.md') -Content "# Fixture project`n"
    Write-FixtureText -Path (Join-Path $fixtureRoot 'knowledge/INDEX.md') -Content "# Knowledge`n"
    Write-FixtureText -Path (Join-Path $fixtureRoot 'knowledge/candidates/TEMPLATE.md') -Content "# Candidate template`n"
    foreach ($index in @('product/INDEX.md', 'business/INDEX.md', 'docs/architecture/INDEX.md', 'docs/codebase/INDEX.md')) {
        Write-FixtureText -Path (Join-Path $fixtureRoot $index) -Content "# Domain index`n"
    }
    foreach ($entry in $required.GetEnumerator()) {
        Set-FixtureCanon -RelativePath ([string]$entry.Key) -Content (New-CanonText -Domain ([string]$entry.Value[0]) -Heading ([string]$entry.Value[1]))
    }

    [void](Invoke-ScriptExpected -Script $verifyCanonScript -Arguments @('-Root', $fixtureRoot, '-Report'))

    $productOverview = Join-Path $fixtureRoot 'product/overview.md'
    Set-FixtureCanon -RelativePath 'product/overview.md' -Content (New-CanonText -Domain 'product' -Heading 'Product overview' -Status active -VerifiedAt '2026-08-20' -Body '[Business](../business/overview.md)')
    Set-FixtureCanon -RelativePath 'business/overview.md' -Content (New-CanonText -Domain 'business' -Heading 'Business overview' -Status active -VerifiedAt '2026-08-20')
    Write-FixtureText -Path (Join-Path $fixtureRoot 'product/TEMPLATE.md') -Content (New-CanonText -Domain 'product' -Heading 'Excluded service file' -Status active -VerifiedAt '2026-08-20')
    Write-FixtureText -Path (Join-Path $fixtureRoot 'plans/fixture.md') -Content (New-CanonText -Domain 'product' -Heading 'Excluded plan' -Status active -VerifiedAt '2026-08-20')
    Write-FixtureText -Path (Join-Path $fixtureRoot 'inbox/raw/fixture.md') -Content (New-CanonText -Domain 'product' -Heading 'Excluded raw' -Status active -VerifiedAt '2026-08-20')
    Write-FixtureText -Path (Join-Path $fixtureRoot 'retrospectives/fixture.md') -Content (New-CanonText -Domain 'product' -Heading 'Excluded retrospective' -Status active -VerifiedAt '2026-08-20')
    [void](Invoke-ScriptExpected -Script $verifyCanonScript -Arguments @('-Root', $fixtureRoot))
    $writeOutput = Invoke-ScriptExpected -Script $graphScript -Arguments @('-Root', $fixtureRoot, '-Mode', 'Write')
    if (($writeOutput -join "`n") -notmatch 'nodes=2; edges=1') { throw "Graph did not contain exactly two canon nodes and one edge: $($writeOutput -join ' | ')" }
    [void](Invoke-ScriptExpected -Script $graphScript -Arguments @('-Root', $fixtureRoot, '-Mode', 'Check'))
    $graphPath = Join-Path $fixtureRoot 'knowledge/graph/INDEX.md'
    $graph = [System.IO.File]::ReadAllText($graphPath)
    foreach ($included in @('product/overview.md', 'business/overview.md')) {
        if ($graph -notmatch [regex]::Escape($included)) { throw "Graph omitted active canon $included." }
    }
    foreach ($excluded in @('product/TEMPLATE.md', 'plans/fixture.md', 'inbox/raw/fixture.md', 'retrospectives/fixture.md', 'product/capabilities.md')) {
        if ($graph -match [regex]::Escape($excluded)) { throw "Graph included excluded artifact $excluded." }
    }

    $validProduct = [System.IO.File]::ReadAllText($productOverview)
    Set-FixtureCanon -RelativePath 'product/overview.md' -Content ($validProduct.Replace('verified_at: 2026-08-20', 'verified_at: null'))
    Assert-CanonFailure -ExpectedFragment 'active canon требует verified_at'
    Set-FixtureCanon -RelativePath 'product/overview.md' -Content $validProduct

    Set-FixtureCanon -RelativePath 'product/overview.md' -Content ($validProduct.Replace('domain: product', 'domain: business'))
    Assert-CanonFailure -ExpectedFragment 'domain не совпадает с owner path'
    Set-FixtureCanon -RelativePath 'product/overview.md' -Content $validProduct

    Set-FixtureCanon -RelativePath 'product/overview.md' -Content ($validProduct.Replace('status: active', "unexpected_field: value`nstatus: active"))
    Assert-CanonFailure -ExpectedFragment 'неизвестное canon field unexpected_field'
    Set-FixtureCanon -RelativePath 'product/overview.md' -Content $validProduct

    Set-FixtureCanon -RelativePath 'product/overview.md' -Content (New-CanonText -Domain 'product' -Heading 'Product overview' -Status active -VerifiedAt '2026-08-20' -SourceRefs @('C:/private/source.md'))
    Assert-CanonFailure -ExpectedFragment 'небезопасный или отсутствующий source_ref'

    Set-FixtureCanon -RelativePath 'product/overview.md' -Content (New-CanonText -Domain 'product' -Heading 'Product overview' -Status active -VerifiedAt '2026-08-20' -SourceRefs @('logical:test/source', 'logical:test/source'))
    Assert-CanonFailure -ExpectedFragment 'source_refs содержит дубли'
    Set-FixtureCanon -RelativePath 'product/overview.md' -Content $validProduct

    $requiredPath = Join-Path $fixtureRoot 'product/glossary.md'
    $requiredText = [System.IO.File]::ReadAllText($requiredPath)
    Remove-Item -LiteralPath $requiredPath -Force
    Assert-CanonFailure -ExpectedFragment 'product/glossary.md отсутствует'
    Write-FixtureText -Path $requiredPath -Content $requiredText

    Set-FixtureCanon -RelativePath 'product/constraints.md' -Content (New-CanonText -Domain 'product' -Heading 'Constraints')
    $additionalOutput = Invoke-ScriptExpected -Script $verifyCanonScript -Arguments @('-Root', $fixtureRoot, '-Report')
    if (($additionalOutput -join "`n") -notmatch 'canon files checked - 13') { throw 'Additional canon file was not discovered.' }
    Set-FixtureCanon -RelativePath 'product/constraints.md' -Content "# Missing frontmatter`n"
    Assert-CanonFailure -ExpectedFragment 'product/constraints.md: Отсутствует корректный YAML frontmatter'
    Remove-Item -LiteralPath (Join-Path $fixtureRoot 'product/constraints.md') -Force

    [void](Invoke-ScriptExpected -Script $graphScript -Arguments @('-Root', $fixtureRoot, '-Mode', 'Write'))
    Write-FixtureText -Path $graphPath -Content ([System.IO.File]::ReadAllText($graphPath) + "manual drift`n")
    $staleOutput = Invoke-ScriptExpected -Script $graphScript -Arguments @('-Root', $fixtureRoot, '-Mode', 'Check') -ExpectedExitCodes @(1)
    if (($staleOutput -join "`n") -notmatch 'stale-knowledge-graph') { throw 'Stale graph was not blocked.' }

    Write-Host 'PASS: canon discovery, negative schema fixtures, graph inclusion boundary and stale detection passed.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
        $full = [System.IO.Path]::GetFullPath($fixtureRoot)
        if (-not $full.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, $tempComparison) -or
            [System.IO.Path]::GetFileName($full) -cnotmatch '^model-project-canon-fixture-[a-f0-9]{32}$') {
            throw 'Unsafe canon fixture cleanup target.'
        }
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
