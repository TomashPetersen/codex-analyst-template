[CmdletBinding()]
param(
    [string]$Root = '',

    [ValidateSet('A31', 'A32', 'A33', 'A34', 'A35', 'A36', 'A37', 'A38', 'A39', 'A40', 'A41', 'A42')]
    [string[]]$CaseId = @('A31', 'A32', 'A33', 'A34', 'A35', 'A36', 'A37', 'A38', 'A39', 'A40', 'A41', 'A42'),

    [ValidateRange(30, 600)]
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$harnessRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $harnessRoot 'scripts/lib/ModelProject.Platform.psm1') -Force
$fixturePrefix = 'ModelProjectPrivacy-'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ($fixturePrefix + [guid]::NewGuid().ToString('N'))
$harnessExitCode = 1
$caseResults = [System.Collections.Generic.List[object]]::new()

function Invoke-PowerShellChild {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][int]$Timeout,
        [switch]$AllowLineBreakArguments
    )

    $hostPath = (Get-Process -Id $PID).Path
    $allArguments = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $ScriptPath
    ) + $Arguments

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $hostPath
    foreach ($argument in $allArguments) {
        $value = [string]$argument
        if ($value.IndexOf([char]0) -ge 0 -or
            (-not $AllowLineBreakArguments -and $value -match '[\r\n]')) {
            throw 'HARNESS-UNSAFE-CHILD-ARGUMENT'
        }
        [void]$startInfo.ArgumentList.Add($value)
    }
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $utf8NoBom
    $startInfo.StandardErrorEncoding = $utf8NoBom

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'HARNESS-CHILD-START'
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($Timeout * 1000)
        if ($timedOut) {
            try { $process.Kill() } catch { }
            [void]$process.WaitForExit(10000)
        }
        else {
            $process.WaitForExit()
        }
        return [pscustomobject]@{
            ExitCode = if ($timedOut) { 124 } else { [int]$process.ExitCode }
            Stdout = [string]$stdoutTask.Result
            Stderr = [string]$stderrTask.Result
            TimedOut = [bool]$timedOut
        }
    }
    finally {
        $process.Dispose()
    }
}

function Test-SafeRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        $RelativePath -notmatch '^[A-Za-z0-9._/\-]+$' -or
        $RelativePath.StartsWith('/') -or
        $RelativePath.EndsWith('/') -or
        $RelativePath.Contains('\')) {
        return $false
    }
    foreach ($segment in ($RelativePath -split '/')) {
        if ($segment -in @('', '.', '..') -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) {
            return $false
        }
    }
    return $true
}

function Assert-NotReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'HARNESS-REPARSE-POINT-REJECTED'
    }
}

function Copy-PortableSeed {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$SeedRoot
    )

    $manifestPath = Join-Path $SourceRoot '.template-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'HARNESS-MANIFEST-MISSING'
    }
    Assert-NotReparsePoint -Path $manifestPath
    $manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
    if ($manifestBytes.Length -gt 1MB) {
        throw 'HARNESS-MANIFEST-OVERSIZED'
    }
    $manifest = ($utf8Strict.GetString($manifestBytes) | ConvertFrom-Json)
    if ($null -eq $manifest.portable_files -or $null -eq $manifest.portable_empty_directories) {
        throw 'HARNESS-MANIFEST-SHAPE'
    }

    New-Item -ItemType Directory -Path $SeedRoot | Out-Null
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in @($manifest.portable_files)) {
        $relative = [string]$entry
        if (-not (Test-SafeRelativePath -RelativePath $relative) -or -not $seen.Add($relative)) {
            throw 'HARNESS-MANIFEST-PATH-UNSAFE'
        }
        $source = Join-Path $SourceRoot $relative
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw 'HARNESS-MANIFEST-FILE-MISSING'
        }
        Assert-NotReparsePoint -Path $source
        $destination = Join-Path $SeedRoot $relative
        $destinationParent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $source -Destination $destination
    }
    foreach ($entry in @($manifest.portable_empty_directories)) {
        $relative = [string]$entry
        if (-not (Test-SafeRelativePath -RelativePath $relative) -or -not $seen.Add($relative)) {
            throw 'HARNESS-MANIFEST-PATH-UNSAFE'
        }
        New-Item -ItemType Directory -Path (Join-Path $SeedRoot $relative) -Force | Out-Null
    }
}

function Write-Utf8Fixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n", "`n"), $utf8NoBom)
}

function Read-Utf8Strict {
    param([Parameter(Mandatory = $true)][string]$Path)

    return $utf8Strict.GetString([System.IO.File]::ReadAllBytes($Path))
}

function Get-TreeHashSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $canonicalRoot = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    return @(
        Get-ChildItem -LiteralPath $canonicalRoot -Recurse -Force |
            ForEach-Object {
                $relative = $_.FullName.Substring($canonicalRoot.Length + 1).Replace('\', '/')
                if ($_.PSIsContainer) {
                    'D|{0}' -f $relative
                }
                else {
                    $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    'F|{0}|{1}|{2}' -f $relative, $_.Length, $hash
                }
            } |
            Sort-Object
    )
}

function Test-SafeFixtureRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $canonical = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]'\/')
    $actualParent = [System.IO.Path]::GetFullPath((Split-Path -Parent $canonical)).TrimEnd([char[]]'\/')
    $leaf = Split-Path -Leaf $canonical
    $comparison = Get-ModelProjectPathComparison -Path $tempRoot
    if (-not $actualParent.Equals($tempRoot, $comparison) -or
        $leaf -cnotmatch ('^' + [regex]::Escape($fixturePrefix) + '[0-9a-f]{32}$')) {
        return $false
    }
    if (Test-Path -LiteralPath $canonical) {
        $item = Get-Item -LiteralPath $canonical -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $false
        }
    }
    return $true
}

function Get-RawFixtureContent {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$StorageBasis = 'explicit-user-request',
        [string]$AuthorityRef = 'user-request:privacy-public-cli-harness',
        [string]$DataClass = 'internal',
        [string]$ContentMode = 'summary',
        [string]$PersonalData = 'none',
        [string]$Retention = '2099-12-31',
        [string]$Rights = 'public-summary',
        [string]$Status = 'captured',
        [string]$ExtraFrontMatter = '',
        [string]$Body = 'Synthetic aggregate summary without personal data.'
    )

    $extra = if ([string]::IsNullOrWhiteSpace($ExtraFrontMatter)) { '' } else { $ExtraFrontMatter.Trim() + "`n" }
    return @"
---
id: $Id
captured_at: 2026-08-01T00:00:00+04:00
storage_basis: $StorageBasis
authority_ref: $AuthorityRef
data_class: $DataClass
content_mode: $ContentMode
personal_data: $PersonalData
retention: $Retention
source: logical-source-privacy-public-cli-harness
rights: $Rights
author: synthetic-fixture
scope: project
status: $Status
$($extra)related: []
---

# Synthetic RAW fixture

## Stored material

$Body
"@
}

function Test-RawTemplateOracle {
    param([Parameter(Mandatory = $true)][string]$SeedRoot)

    foreach ($relative in @('inbox/raw/TEMPLATE.md')) {
        $path = Join-Path $SeedRoot $relative
        $text = (Read-Utf8Strict -Path $path).Replace("`r`n", "`n")
        if (-not $text.StartsWith("---`n", [System.StringComparison]::Ordinal)) { return $false }
        $end = $text.IndexOf("`n---`n", 4, [System.StringComparison]::Ordinal)
        if ($end -lt 0) { return $false }
        $frontMatter = $text.Substring(4, $end - 4)
        $values = @{}
        foreach ($line in ($frontMatter -split "`n")) {
            if ($line -notmatch '^(?<key>[a-z_]+):(?<value>.*)$') { continue }
            $key = $Matches['key']
            if ($values.ContainsKey($key)) { return $false }
            $values[$key] = $Matches['value'].Trim()
        }
        if (-not $values.ContainsKey('storage_basis') -or $values['storage_basis'] -cne 'null') { return $false }
        if (-not $values.ContainsKey('authority_ref') -or $values['authority_ref'] -cne 'null') { return $false }
        if ($frontMatter -match '(?m)^storage_basis:\s*(?:explicit-user-request|authorized-import)\s*$' -or
            $frontMatter -match '(?m)^authority_ref:\s*user-request:') {
            return $false
        }
    }
    return $true
}

function Add-CaseResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Summary
    )

    $caseResults.Add([pscustomobject]@{ Name = $Name; Passed = $Passed; Summary = $Summary }) | Out-Null
    $prefix = if ($Passed) { 'PASS' } else { 'RED' }
    Write-Host "${prefix}: $Name $Summary"
}

function Invoke-IsolatedVerifierCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SeedRoot,
        [Parameter(Mandatory = $true)][scriptblock]$Arrange,
        [Parameter(Mandatory = $true)][bool]$ExpectBlocked,
        [string]$ExpectedDiagnostic = '',
        [string[]]$ForbiddenEchoes = @(),
        [switch]$Report
    )

    $leaf = ($Name.ToLowerInvariant() -replace '[^a-z0-9-]', '-') + '-case'
    $caseRoot = Join-Path $fixtureRoot $leaf
    Copy-Item -LiteralPath $SeedRoot -Destination $caseRoot -Recurse
    & $Arrange $caseRoot

    $treeBefore = Get-TreeHashSnapshot -Path $caseRoot
    $arguments = @('-Root', $caseRoot)
    if ($Report) { $arguments += '-Report' }
    $verifier = Join-Path $caseRoot 'scripts/verify-knowledge.ps1'
    $result = Invoke-PowerShellChild -ScriptPath $verifier -Arguments $arguments -WorkingDirectory $caseRoot -Timeout $TimeoutSeconds
    $treeAfter = Get-TreeHashSnapshot -Path $caseRoot
    $diagnostic = $result.Stdout + "`n" + $result.Stderr

    if ($result.TimedOut) {
        Add-CaseResult -Name $Name -Passed $false -Summary 'public verifier timed out.'
        return
    }
    if (@(Compare-Object -ReferenceObject $treeBefore -DifferenceObject $treeAfter).Count -ne 0) {
        Add-CaseResult -Name $Name -Passed $false -Summary 'public verifier changed the fixture tree.'
        return
    }
    $temporaryArtifacts = @(
        Get-ChildItem -LiteralPath $caseRoot -Recurse -File -Force |
            Where-Object { $_.Name -match '(?i)(?:\.tmp$|\.lock$|\.draft$|\.partial$)' }
    )
    if ($temporaryArtifacts.Count -ne 0) {
        Add-CaseResult -Name $Name -Passed $false -Summary 'public verifier left a temporary artifact.'
        return
    }
    foreach ($forbidden in $ForbiddenEchoes) {
        if (-not [string]::IsNullOrEmpty($forbidden) -and
            $diagnostic.IndexOf($forbidden, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Add-CaseResult -Name $Name -Passed $false -Summary 'diagnostics disclosed a synthetic sentinel.'
            return
        }
    }

    if ($ExpectBlocked) {
        if ($result.ExitCode -eq 0) {
            Add-CaseResult -Name $Name -Passed $false -Summary 'unexpected PASS for a forbidden fixture.'
            return
        }
        if ([string]::IsNullOrWhiteSpace($ExpectedDiagnostic) -or $diagnostic -notmatch $ExpectedDiagnostic) {
            Add-CaseResult -Name $Name -Passed $false -Summary 'blocked without the expected safe diagnostic class.'
            return
        }
        Add-CaseResult -Name $Name -Passed $true -Summary 'forbidden fixture is blocked safely and read-only.'
        return
    }

    if ($result.ExitCode -ne 0) {
        Add-CaseResult -Name $Name -Passed $false -Summary 'valid fixture was rejected.'
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedDiagnostic) -and $diagnostic -notmatch $ExpectedDiagnostic) {
        Add-CaseResult -Name $Name -Passed $false -Summary 'expected safe report class is missing.'
        return
    }
    Add-CaseResult -Name $Name -Passed $true -Summary 'valid fixture passes read-only public verification.'
}

function Invoke-RawCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SeedRoot,
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][bool]$ExpectBlocked,
        [string]$ExpectedDiagnostic = '',
        [string[]]$ForbiddenEchoes = @(),
        [switch]$Report
    )

    $fixtureContent = $Content
    $fixtureName = ($Name.ToLowerInvariant() -replace '[^a-z0-9-]', '-') + '.md'
    $writeUtf8Fixture = ${function:Write-Utf8Fixture}
    $arrange = {
        param($caseRoot)
        & $writeUtf8Fixture -Path (Join-Path $caseRoot ('inbox/raw/' + $fixtureName)) -Content $fixtureContent
    }.GetNewClosure()
    Invoke-IsolatedVerifierCase -Name $Name -SeedRoot $SeedRoot -Arrange $arrange -ExpectBlocked $ExpectBlocked `
        -ExpectedDiagnostic $ExpectedDiagnostic -ForbiddenEchoes $ForbiddenEchoes -Report:$Report
}

function Get-CandidateFinalFiles {
    param([Parameter(Mandatory = $true)][string]$Root)

    $candidateRoot = Join-Path $Root 'knowledge/candidates'
    if (-not (Test-Path -LiteralPath $candidateRoot -PathType Container)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter 'KC-*.md' -Force
    )
}

function Get-GeneratorTransientFiles {
    param([Parameter(Mandatory = $true)][string]$Root)

    return @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
            Where-Object {
                $_.Name -match '(?i)(?:\.tmp$|\.lock$|\.draft$|\.partial$|^\.candidate-|^candidate-.*\.final$)'
            }
    )
}

function Invoke-PublicCandidateGenerator {
    param(
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)][string]$ClaimKey,
        [Parameter(Mandatory = $true)][string]$Basis,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][int]$Timeout
    )

    $generator = Join-Path $CaseRoot 'scripts/new-knowledge-candidate.ps1'
    $arguments = @(
        '-Root', $CaseRoot,
        '-Type', 'fact',
        '-Domain', 'research',
        '-ClaimKey', $ClaimKey,
        '-TargetRef', 'idea/vision.md',
        '-SourceRefs', 'PROJECT.md',
        '-Confidence', 'medium',
        '-CaptureBasis', 'explicit-user-capture',
        '-DataClass', 'internal',
        '-Title', $Title,
        '-Basis', $Basis,
        '-ProposedChange', 'Record a bounded synthetic aggregate claim in project canon.',
        '-DuplicateCheck', 'Compared claim_key and target_ref in the isolated fixture.',
        '-ReviewDue', '2099-12-31',
        '-WriteIntent', 'explicit-promotion',
        '-AuthorityRef', 'user-request:privacy-public-cli-harness'
    )

    return Invoke-PowerShellChild -ScriptPath $generator -Arguments $arguments `
        -WorkingDirectory $CaseRoot -Timeout $Timeout -AllowLineBreakArguments:($Basis -match "[`r`n]")
}

function Invoke-GeneratorSafetyCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SeedRoot,
        [Parameter(Mandatory = $true)][string]$Basis,
        [Parameter(Mandatory = $true)][bool]$ExpectBlocked,
        [string[]]$ForbiddenEchoes = @()
    )

    $leaf = ($Name.ToLowerInvariant() -replace '[^a-z0-9-]', '-') + '-generator-case'
    $caseRoot = Join-Path $fixtureRoot $leaf
    Copy-Item -LiteralPath $SeedRoot -Destination $caseRoot -Recurse
    $claimKey = ($Name.ToLowerInvariant() -replace '[^a-z0-9-]', '-')
    $title = "Synthetic privacy generator control $claimKey"

    $treeBefore = Get-TreeHashSnapshot -Path $caseRoot
    $result = Invoke-PublicCandidateGenerator -CaseRoot $caseRoot -ClaimKey $claimKey `
        -Basis $Basis -Title $title -Timeout $TimeoutSeconds
    $treeAfter = Get-TreeHashSnapshot -Path $caseRoot
    $diagnostic = $result.Stdout + "`n" + $result.Stderr
    $finalFiles = @(Get-CandidateFinalFiles -Root $caseRoot)
    $transientFiles = @(Get-GeneratorTransientFiles -Root $caseRoot)

    if ($result.TimedOut) {
        Add-CaseResult -Name $Name -Passed $false -Summary 'public generator timed out.'
        return
    }
    foreach ($forbidden in @($ForbiddenEchoes + @($caseRoot, $fixtureRoot))) {
        if (-not [string]::IsNullOrEmpty($forbidden) -and
            $diagnostic.IndexOf($forbidden, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Add-CaseResult -Name $Name -Passed $false -Summary 'generator diagnostics disclosed a synthetic sentinel or absolute temp root.'
            return
        }
    }
    if ($transientFiles.Count -ne 0) {
        Add-CaseResult -Name $Name -Passed $false -Summary 'generator left draft, temp, lock, partial, or final-named transient data.'
        return
    }

    if ($ExpectBlocked) {
        if ($result.ExitCode -eq 0) {
            Add-CaseResult -Name $Name -Passed $false -Summary 'unsafe generator input unexpectedly succeeded.'
            return
        }
        if ($finalFiles.Count -ne 0) {
            Add-CaseResult -Name $Name -Passed $false -Summary 'blocked generator left a final candidate.'
            return
        }
        if (@(Compare-Object -ReferenceObject $treeBefore -DifferenceObject $treeAfter).Count -ne 0) {
            Add-CaseResult -Name $Name -Passed $false -Summary 'blocked generator changed the fixture tree.'
            return
        }
        Add-CaseResult -Name $Name -Passed $true -Summary 'unsafe generator input is blocked with no final, draft, temp, or lock artifact.'
        return
    }

    if ($result.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($result.Stderr)) {
        Add-CaseResult -Name $Name -Passed $false -Summary 'safe generator control was rejected or wrote stderr.'
        return
    }
    if ($finalFiles.Count -ne 1 -or $diagnostic -notmatch '(?m)^READY \[KC-') {
        Add-CaseResult -Name $Name -Passed $false -Summary 'safe generator control did not publish exactly one READY candidate.'
        return
    }
    $beforeVerify = Get-TreeHashSnapshot -Path $caseRoot
    $verifyResult = Invoke-PowerShellChild -ScriptPath (Join-Path $caseRoot 'scripts/verify-knowledge.ps1') `
        -Arguments @('-Root', $caseRoot) -WorkingDirectory $caseRoot -Timeout $TimeoutSeconds
    $afterVerify = Get-TreeHashSnapshot -Path $caseRoot
    if ($verifyResult.TimedOut -or $verifyResult.ExitCode -ne 0 -or
        @(Compare-Object -ReferenceObject $beforeVerify -DifferenceObject $afterVerify).Count -ne 0) {
        Add-CaseResult -Name $Name -Passed $false -Summary 'safe generated candidate failed read-only strict verification.'
        return
    }
    Add-CaseResult -Name $Name -Passed $true -Summary 'safe generator control publishes one verified candidate without transient artifacts.'
}

function Invoke-InvalidRootRedactionCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SeedRoot,
        [Parameter(Mandatory = $true)][ValidateSet('knowledge', 'structure')][string]$VerifierKind
    )

    $leaf = ($Name.ToLowerInvariant() -replace '[^a-z0-9-]', '-') + '-invalid-root-case'
    $caseRoot = Join-Path $fixtureRoot $leaf
    Copy-Item -LiteralPath $SeedRoot -Destination $caseRoot -Recurse
    $invalidLeaf = 'A42InvalidRoot@example.invalid-api_key=A42InvalidRootQuerySecret'
    $invalidRoot = Join-Path $fixtureRoot $invalidLeaf
    $scriptPath = if ($VerifierKind -ceq 'knowledge') {
        Join-Path $caseRoot 'scripts/verify-knowledge.ps1'
    }
    else {
        Join-Path $caseRoot 'scripts/verify-structure.ps1'
    }
    $arguments = @('-Root', $invalidRoot)
    if ($VerifierKind -ceq 'knowledge') { $arguments += '-Report' }
    $treeBefore = Get-TreeHashSnapshot -Path $caseRoot
    $result = Invoke-PowerShellChild -ScriptPath $scriptPath -Arguments $arguments `
        -WorkingDirectory $caseRoot -Timeout $TimeoutSeconds
    $treeAfter = Get-TreeHashSnapshot -Path $caseRoot
    $diagnostic = $result.Stdout + "`n" + $result.Stderr
    $forbidden = @(
        'A42InvalidRoot@example.invalid',
        'A42InvalidRootQuerySecret',
        $invalidRoot,
        $caseRoot,
        $fixtureRoot
    )

    $passed = -not $result.TimedOut -and
        $result.ExitCode -ne 0 -and
        @(Compare-Object -ReferenceObject $treeBefore -DifferenceObject $treeAfter).Count -eq 0
    foreach ($value in $forbidden) {
        if ($diagnostic.IndexOf($value, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $passed = $false
        }
    }
    Add-CaseResult -Name $Name -Passed $passed -Summary $(if ($passed) {
        'invalid Root is rejected read-only without secret, email, query, or absolute temp-root disclosure.'
    } else {
        'invalid Root redaction or read-only contract failed.'
    })
}

function Invoke-BadMarkdownTargetRedactionCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SeedRoot,
        [Parameter(Mandatory = $true)][ValidateSet('knowledge', 'structure')][string]$VerifierKind
    )

    $leaf = ($Name.ToLowerInvariant() -replace '[^a-z0-9-]', '-') + '-bad-link-case'
    $caseRoot = Join-Path $fixtureRoot $leaf
    Copy-Item -LiteralPath $SeedRoot -Destination $caseRoot -Recurse
    $email = 'A42MissingTarget@example.invalid'
    $querySecret = 'A42MissingTargetQuerySecret'
    $indexPath = Join-Path $caseRoot 'knowledge/INDEX.md'
    $indexText = Read-Utf8Strict -Path $indexPath
    $badTarget = "missing/$email.md?api_key=$querySecret"
    $mutated = $indexText.Replace('(candidates/TEMPLATE.md)', "($badTarget)")
    if ($mutated -ceq $indexText) {
        throw 'HARNESS-BAD-LINK-ARRANGE-FAILED'
    }
    Write-Utf8Fixture -Path $indexPath -Content $mutated

    $scriptPath = if ($VerifierKind -ceq 'knowledge') {
        Join-Path $caseRoot 'scripts/verify-knowledge.ps1'
    }
    else {
        Join-Path $caseRoot 'scripts/verify-structure.ps1'
    }
    $arguments = @('-Root', $caseRoot)
    if ($VerifierKind -ceq 'knowledge') { $arguments += '-Report' }
    $treeBefore = Get-TreeHashSnapshot -Path $caseRoot
    $result = Invoke-PowerShellChild -ScriptPath $scriptPath -Arguments $arguments `
        -WorkingDirectory $caseRoot -Timeout $TimeoutSeconds
    $treeAfter = Get-TreeHashSnapshot -Path $caseRoot
    $diagnostic = $result.Stdout + "`n" + $result.Stderr
    $forbidden = @($email, $querySecret, $badTarget, $caseRoot, $fixtureRoot)

    $passed = -not $result.TimedOut -and
        $result.ExitCode -ne 0 -and
        @(Compare-Object -ReferenceObject $treeBefore -DifferenceObject $treeAfter).Count -eq 0
    foreach ($value in $forbidden) {
        if ($diagnostic.IndexOf($value, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $passed = $false
        }
    }
    Add-CaseResult -Name $Name -Passed $passed -Summary $(if ($passed) {
        'bad Markdown target is rejected read-only without secret, email, query, or absolute temp-root disclosure.'
    } else {
        'bad Markdown target redaction or read-only contract failed.'
    })
}

try {
    $sourceRoot = if ([string]::IsNullOrWhiteSpace($Root)) {
        Split-Path -Parent $PSScriptRoot
    }
    else {
        [System.IO.Path]::GetFullPath($Root)
    }
    $sourceRoot = [System.IO.Path]::GetFullPath($sourceRoot).TrimEnd([char[]]'\/')
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
        throw 'HARNESS-SOURCE-ROOT-MISSING'
    }
    if (-not (Test-SafeFixtureRoot -Path $fixtureRoot)) {
        throw 'HARNESS-TEMP-ROOT-UNSAFE'
    }

    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    $seedRoot = Join-Path $fixtureRoot 'generated-seed'
    Copy-PortableSeed -SourceRoot $sourceRoot -SeedRoot $seedRoot

    $initializer = Join-Path $seedRoot 'scripts/initialize-project.ps1'
    $initializeResult = Invoke-PowerShellChild -ScriptPath $initializer -Arguments @(
        '-ProjectName', 'Privacy Public CLI Fixture',
        '-ProjectSlug', 'privacy-public-cli-fixture',
        '-Description', 'Synthetic generated project for bounded privacy regression tests.',
        '-Owner', 'fixture-owner',
        '-InitializeGit'
    ) -WorkingDirectory $seedRoot -Timeout $TimeoutSeconds
    if ($initializeResult.TimedOut -or $initializeResult.ExitCode -ne 0) {
        throw 'HARNESS-PUBLIC-INITIALIZER-FAILED'
    }

    $seedBefore = Get-TreeHashSnapshot -Path $seedRoot
    $seedVerifier = Join-Path $seedRoot 'scripts/verify-knowledge.ps1'
    $seedResult = Invoke-PowerShellChild -ScriptPath $seedVerifier -Arguments @('-Root', $seedRoot) `
        -WorkingDirectory $seedRoot -Timeout $TimeoutSeconds
    $seedAfter = Get-TreeHashSnapshot -Path $seedRoot
    if ($seedResult.TimedOut -or $seedResult.ExitCode -ne 0 -or
        @(Compare-Object -ReferenceObject $seedBefore -DifferenceObject $seedAfter).Count -ne 0) {
        throw 'HARNESS-CLEAN-GENERATED-SEED-FAILED'
    }

    $selected = @($CaseId | Select-Object -Unique)

    if ($selected -ccontains 'A31') {
        Add-CaseResult -Name 'A31' -Passed (Test-RawTemplateOracle -SeedRoot $seedRoot) `
            -Summary 'independent template oracle requires null storage_basis and authority_ref.'
    }

    if ($selected -ccontains 'A32') {
        $content = Get-RawFixtureContent -Id 'raw-20260801-003200-a32' -AuthorityRef 'null'
        Invoke-RawCase -Name 'A32' -SeedRoot $seedRoot -Content $content -ExpectBlocked $true `
            -ExpectedDiagnostic '(?is)(?:authority_ref|authority).{0,180}(?:null|required|missing|must|требу|заполн)|(?:null|required|missing|must|требу|заполн).{0,180}(?:authority_ref|authority)'
    }

    if ($selected -ccontains 'A33') {
        $content = Get-RawFixtureContent -Id 'raw-20260801-003300-a33' -DataClass 'sensitive' `
            -ContentMode 'verbatim' -PersonalData 'none' -Rights 'user-owned' -Body 'Synthetic verbatim fixture without personal data.'
        Invoke-RawCase -Name 'A33' -SeedRoot $seedRoot -Content $content -ExpectBlocked $true `
            -ExpectedDiagnostic '(?is)(?:sensitive.{0,160}verbatim|verbatim.{0,160}sensitive|raw[-_ ]?sensitive[-_ ]?verbatim)'
    }

    if ($selected -ccontains 'A34') {
        $sentinel = 'a34-private-sentinel@example.invalid'
        $content = Get-RawFixtureContent -Id 'raw-20260801-003400-a34' -PersonalData 'anonymized' `
            -Body "Synthetic contact marker: $sentinel"
        Invoke-RawCase -Name 'A34' -SeedRoot $seedRoot -Content $content -ExpectBlocked $true `
            -ExpectedDiagnostic '(?is)(?:email-or-pii|email|personal[-_ ]?data|privacy|электронн)' -ForbiddenEchoes @($sentinel)
    }

    if ($selected -ccontains 'A35') {
        $phone = '+1 202' + ' 555 0199'
        $sentinel = 'A35PhoneSentinel'
        $content = Get-RawFixtureContent -Id 'raw-20260801-003500-a35' -PersonalData 'anonymized' `
            -Body "Phone: $phone ($sentinel)"
        Invoke-RawCase -Name 'A35' -SeedRoot $seedRoot -Content $content -ExpectBlocked $true `
            -ExpectedDiagnostic '(?is)(?:phone-or-contact|phone|mobile|personal[-_ ]?data|телефон|мобильн)' `
            -ForbiddenEchoes @($phone, $sentinel)

        $generatorPhone = '+44 20' + ' 7946 0958'
        $generatorPhoneSentinel = 'A35GeneratorPhoneSentinel'
        Invoke-GeneratorSafetyCase -Name 'A35-generator-international-phone' -SeedRoot $seedRoot `
            -Basis "International phone: $generatorPhone $generatorPhoneSentinel" -ExpectBlocked $true `
            -ForbiddenEchoes @($generatorPhone, $generatorPhoneSentinel)
    }

    if ($selected -ccontains 'A36') {
        $a36Cases = @(
            [pscustomobject]@{
                Name = 'A36-name'
                Id = 'raw-20260801-003601-a36-name'
                Body = 'Full legal name / ФИО: Testov Ivan Ivanovich A36NameSentinel'
                Pattern = '(?is)(?:full[-_ ]?(?:legal[-_ ]?)?name|person[-_ ]?name|personal[-_ ]?data|фио|имя)'
                Sentinels = @('Testov Ivan Ivanovich', 'A36NameSentinel')
            },
            [pscustomobject]@{
                Name = 'A36-address'
                Id = 'raw-20260801-003602-a36-address'
                Body = 'Home address / домашний адрес: 42 Synthetic Street, Test City A36AddressSentinel'
                Pattern = '(?is)(?:home[-_ ]?address|postal[-_ ]?address|personal[-_ ]?data|address|адрес)'
                Sentinels = @('42 Synthetic Street', 'A36AddressSentinel')
            },
            [pscustomobject]@{
                Name = 'A36-dob'
                Id = 'raw-20260801-003603-a36-dob'
                Body = 'Date of birth / дата рождения: 1988-04-12 A36DobSentinel'
                Pattern = '(?is)(?:date[-_ ]?of[-_ ]?birth|birth[-_ ]?date|dob|personal[-_ ]?data|дата рождения)'
                Sentinels = @('1988-04-12', 'A36DobSentinel')
            }
        )
        foreach ($case in $a36Cases) {
            $content = Get-RawFixtureContent -Id $case.Id -PersonalData 'anonymized' -Body $case.Body
            Invoke-RawCase -Name $case.Name -SeedRoot $seedRoot -Content $content -ExpectBlocked $true `
                -ExpectedDiagnostic $case.Pattern -ForbiddenEchoes $case.Sentinels
        }

        $a36GeneratorCases = @(
            [pscustomobject]@{
                Name = 'A36-generator-full-name'
                Basis = 'Full legal name: Synthetic Test Person A36GeneratorNameSentinel'
                Sentinels = @('Synthetic Test Person', 'A36GeneratorNameSentinel')
            },
            [pscustomobject]@{
                Name = 'A36-generator-home-address'
                Basis = 'Home address: 42 Synthetic Avenue, Test City A36GeneratorAddressSentinel'
                Sentinels = @('42 Synthetic Avenue', 'A36GeneratorAddressSentinel')
            },
            [pscustomobject]@{
                Name = 'A36-generator-date-of-birth'
                Basis = 'Date of birth: 1988-04-12 A36GeneratorDobSentinel'
                Sentinels = @('1988-04-12', 'A36GeneratorDobSentinel')
            }
        )
        foreach ($case in $a36GeneratorCases) {
            Invoke-GeneratorSafetyCase -Name $case.Name -SeedRoot $seedRoot -Basis $case.Basis `
                -ExpectBlocked $true -ForbiddenEchoes $case.Sentinels
        }
    }

    if ($selected -ccontains 'A37') {
        $a37Cases = @(
            [pscustomobject]@{
                Name = 'A37-api-key'
                Id = 'raw-20260801-003701-a37-api-key'
                Body = 'api_key=A37SyntheticApiKeySentinel0123456789'
                Pattern = '(?is)(?:credential-value|credential-like|api[-_ ]?key|secret)'
                Sentinel = 'A37SyntheticApiKeySentinel0123456789'
            },
            [pscustomobject]@{
                Name = 'A37-bearer'
                Id = 'raw-20260801-003702-a37-bearer'
                Body = 'Authorization: Bearer A37BearerSentinel0123456789'
                Pattern = '(?is)(?:bearer-token|bearer|credential)'
                Sentinel = 'A37BearerSentinel0123456789'
            },
            [pscustomobject]@{
                Name = 'A37-cookie'
                Id = 'raw-20260801-003703-a37-cookie'
                Body = 'Cookie: session=A37CookieSentinel0123456789'
                Pattern = '(?is)(?:cookie|session[-_ ]?credential)'
                Sentinel = 'A37CookieSentinel0123456789'
            },
            [pscustomobject]@{
                Name = 'A37-signed-url'
                Id = 'raw-20260801-003704-a37-signed-url'
                Body = 'Synthetic URL: https://example.invalid/object?X-Amz-Signature=A37SignedUrlSentinel0123456789'
                Pattern = '(?is)(?:signed-url|signed.{0,80}url|подписан)'
                Sentinel = 'A37SignedUrlSentinel0123456789'
            }
        )
        foreach ($case in $a37Cases) {
            $content = Get-RawFixtureContent -Id $case.Id -Body $case.Body
            Invoke-RawCase -Name $case.Name -SeedRoot $seedRoot -Content $content -ExpectBlocked $true `
                -ExpectedDiagnostic $case.Pattern -ForbiddenEchoes @($case.Sentinel)
        }


        $generatorCookieSentinel = 'A37GeneratorCookieSentinel0123456789'
        Invoke-GeneratorSafetyCase -Name 'A37-generator-cookie' -SeedRoot $seedRoot `
            -Basis "Cookie: session=$generatorCookieSentinel" -ExpectBlocked $true `
            -ForbiddenEchoes @($generatorCookieSentinel)
    }

    if ($selected -ccontains 'A38') {
        $sentinel = 'A38SyntheticClientSecretSentinel0123456789'
        $readUtf8Strict = ${function:Read-Utf8Strict}
        $writeUtf8Fixture = ${function:Write-Utf8Fixture}
        $arrange = {
            param($caseRoot)
            $runRoot = Join-Path $caseRoot 'research/runs/2026-08-01-privacy-a38'
            New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
            $templateRoot = Join-Path $caseRoot '.agents/skills/startup-researcher/assets/run-template'
            foreach ($name in @('brief.md', 'queries.md', 'evidence.jsonl', 'candidates.md', 'red-team.md', 'decision.md')) {
                Copy-Item -LiteralPath (Join-Path $templateRoot $name) -Destination (Join-Path $runRoot $name)
            }
            $decisionPath = Join-Path $runRoot 'decision.md'
            $decision = & $readUtf8Strict -Path $decisionPath
            & $writeUtf8Fixture -Path $decisionPath -Content ($decision.TrimEnd() + "`n`n## Synthetic negative fixture`n`nclient_secret=$sentinel`n")
        }.GetNewClosure()
        Invoke-IsolatedVerifierCase -Name 'A38' -SeedRoot $seedRoot -Arrange $arrange -ExpectBlocked $true `
            -ExpectedDiagnostic '(?is)(?:credential-value|credential-like|client[-_ ]?secret|secret)' -ForbiddenEchoes @($sentinel)

        $surfaceCases = @(
            [pscustomobject]@{
                Name = 'A38-candidate-template-sensitive-scan'
                Relative = 'knowledge/candidates/TEMPLATE.md'
                Sentinel = 'A38CandidateTemplate@example.invalid'
                Line = 'Synthetic contact: A38CandidateTemplate@example.invalid'
            },
            [pscustomobject]@{
                Name = 'A38-raw-template-sensitive-scan'
                Relative = 'inbox/raw/TEMPLATE.md'
                Sentinel = 'A38RawTemplateSecret0123456789'
                Line = 'api_key=A38RawTemplateSecret0123456789'
            },
            [pscustomobject]@{
                Name = 'A38-raw-readme-sensitive-scan'
                Relative = 'inbox/raw/README.md'
                Sentinel = 'A38RawReadme@example.invalid'
                Line = 'Synthetic contact: A38RawReadme@example.invalid'
            },
            [pscustomobject]@{
                Name = 'A38-local-index-sensitive-scan'
                Relative = 'mastery/local/INDEX.md'
                Sentinel = 'A38LocalIndexCookieSentinel0123456789'
                Line = 'Cookie: session=A38LocalIndexCookieSentinel0123456789'
            }
        )
        foreach ($surface in $surfaceCases) {
            $relative = $surface.Relative
            $line = $surface.Line
            $arrangeSurface = {
                param($caseRoot)
                $path = Join-Path $caseRoot $relative
                $text = & $readUtf8Strict -Path $path
                & $writeUtf8Fixture -Path $path -Content ($text.TrimEnd() + "`n`n$line`n")
            }.GetNewClosure()
            Invoke-IsolatedVerifierCase -Name $surface.Name -SeedRoot $seedRoot -Arrange $arrangeSurface `
                -ExpectBlocked $true -ExpectedDiagnostic '(?is)(?:repository data|email-or-pii|credential-value|cookie-credential)' `
                -ForbiddenEchoes @($surface.Sentinel)
        }
    }

    if ($selected -ccontains 'A39') {
        $sentinel = 'A39TranscriptSentinel'
        $turns = [System.Collections.Generic.List[string]]::new()
        for ($index = 1; $index -le 12; $index++) {
            $turns.Add("Interviewer: Question $index about the synthetic workflow and observed behavior?") | Out-Null
            $suffix = if ($index -eq 7) { " $sentinel" } else { '' }
            $turns.Add("Participant: Detailed synthetic answer $index preserving the complete conversational turn.$suffix") | Out-Null
        }
        $content = Get-RawFixtureContent -Id 'raw-20260801-003900-a39' -ContentMode 'verbatim' `
            -PersonalData 'anonymized' -Rights 'user-owned' -Body ($turns -join "`n`n")
        Invoke-RawCase -Name 'A39' -SeedRoot $seedRoot -Content $content -ExpectBlocked $true `
            -ExpectedDiagnostic '(?is)(?:full[-_ ]?(?:interview[-_ ]?)?transcript|interview[-_ ]?transcript|transcript|интервью|транскрипт)' `
            -ForbiddenEchoes @($sentinel)

        $explicitTranscriptSentinel = 'A39GeneratorExplicitTranscriptSentinel'
        Invoke-GeneratorSafetyCase -Name 'A39-generator-explicit-full-transcript' -SeedRoot $seedRoot `
            -Basis "Full interview transcript: $explicitTranscriptSentinel" -ExpectBlocked $true `
            -ForbiddenEchoes @($explicitTranscriptSentinel)

        $generatorTurns = [System.Collections.Generic.List[string]]::new()
        for ($index = 1; $index -le 5; $index++) {
            $generatorTurns.Add("Interviewer: Synthetic bounded question ${index}?") | Out-Null
            $suffix = if ($index -eq 4) { ' A39GeneratorSpeakerTurnSentinel' } else { '' }
            $generatorTurns.Add("Participant: Synthetic bounded answer $index.$suffix") | Out-Null
        }
        Invoke-GeneratorSafetyCase -Name 'A39-generator-speaker-turn-corpus' -SeedRoot $seedRoot `
            -Basis ($generatorTurns -join "`n") -ExpectBlocked $true `
            -ForbiddenEchoes @('A39GeneratorSpeakerTurnSentinel')
    }

    if ($selected -ccontains 'A40') {
        $content = Get-RawFixtureContent -Id 'raw-20260801-004000-a40' -PersonalData 'anonymized' `
            -Body 'Anonymized aggregate summary: three coded observations support a synthetic workflow hypothesis.'
        Invoke-RawCase -Name 'A40' -SeedRoot $seedRoot -Content $content -ExpectBlocked $false

        Invoke-GeneratorSafetyCase -Name 'A40-generator-safe-control' -SeedRoot $seedRoot `
            -Basis 'Synthetic aggregate evidence contains no personal data or credentials.' -ExpectBlocked $false

        $safeSurfaceArrange = {
            param($caseRoot)
            foreach ($relative in @(
                'knowledge/candidates/TEMPLATE.md',
                'inbox/raw/TEMPLATE.md',
                'inbox/raw/README.md',
                'mastery/local/INDEX.md'
            )) {
                $path = Join-Path $caseRoot $relative
                $text = Read-Utf8Strict -Path $path
                Write-Utf8Fixture -Path $path -Content ($text.TrimEnd() + "`n`nSynthetic aggregate control text.`n")
            }
        }
        Invoke-IsolatedVerifierCase -Name 'A40-safe-control-surfaces' -SeedRoot $seedRoot `
            -Arrange $safeSurfaceArrange -ExpectBlocked $false
    }

    if ($selected -ccontains 'A41') {
        $sentinel = 'A41PayloadSentinelNoDelete'
        $content = Get-RawFixtureContent -Id 'raw-20260801-004100-a41' -Retention '2000-01-01' `
            -Body "Synthetic expired-retention summary. $sentinel"
        Invoke-RawCase -Name 'A41' -SeedRoot $seedRoot -Content $content -ExpectBlocked $false -Report `
            -ExpectedDiagnostic '(?is)(?:overdue.{0,160}(?:[1-9]|a41)|a41.{0,160}overdue)' -ForbiddenEchoes @($sentinel)
    }

    if ($selected -ccontains 'A42') {
        $a42Cases = @(
            [pscustomobject]@{
                Name = 'A42-target-ref'
                Content = Get-RawFixtureContent -Id 'raw-20260801-004201-a42-target' -ExtraFrontMatter 'target_ref: null'
                Pattern = '(?is)(?:unknown|closed|schema|неизвестн|закрыт).{0,160}target_ref|target_ref.{0,160}(?:unknown|closed|schema|неизвестн|запрещ|закрыт)'
            },
            [pscustomobject]@{
                Name = 'A42-candidate-ready'
                Content = Get-RawFixtureContent -Id 'raw-20260801-004202-a42-ready' -Status 'candidate-ready'
                Pattern = '(?is)(?:invalid|forbidden|unsupported|недопуст|запрещ).{0,160}(?:raw[-_ ]?status|status|candidate-ready)|(?:raw[-_ ]?status|status|candidate-ready).{0,160}(?:invalid|forbidden|unsupported|недопуст|запрещ)'
            },
            [pscustomobject]@{
                Name = 'A42-promoted'
                Content = Get-RawFixtureContent -Id 'raw-20260801-004203-a42-promoted' -Status 'promoted'
                Pattern = '(?is)(?:invalid|forbidden|unsupported|недопуст|запрещ).{0,160}(?:raw[-_ ]?status|status|promoted)|(?:raw[-_ ]?status|status|promoted).{0,160}(?:invalid|forbidden|unsupported|недопуст|запрещ)'
            },
            [pscustomobject]@{
                Name = 'A42-knowledge-outcome'
                Content = Get-RawFixtureContent -Id 'raw-20260801-004204-a42-outcome' `
                    -Body "Synthetic summary.`n`n## Knowledge outcome`n`n- Main result: none"
                Pattern = '(?is)(?:knowledge outcome|promotion|closed[-_ ]?schema|raw[-_ ]?promotion|запрещ)'
            }
        )
        foreach ($case in $a42Cases) {
            Invoke-RawCase -Name $case.Name -SeedRoot $seedRoot -Content $case.Content -ExpectBlocked $true `
                -ExpectedDiagnostic $case.Pattern
        }

        Invoke-BadMarkdownTargetRedactionCase -Name 'A42-knowledge-report-bad-markdown-redaction' `
            -SeedRoot $seedRoot -VerifierKind knowledge
        Invoke-BadMarkdownTargetRedactionCase -Name 'A42-structure-bad-markdown-redaction' `
            -SeedRoot $seedRoot -VerifierKind structure
        Invoke-InvalidRootRedactionCase -Name 'A42-knowledge-report-invalid-root-redaction' `
            -SeedRoot $seedRoot -VerifierKind knowledge
        Invoke-InvalidRootRedactionCase -Name 'A42-structure-invalid-root-redaction' `
            -SeedRoot $seedRoot -VerifierKind structure
    }

    $failed = @($caseResults | Where-Object { -not $_.Passed })
    if ($failed.Count -eq 0) {
        Write-Host "HARNESS PASS: privacy/RAW public-CLI cases passed ($($caseResults.Count) bounded checks)."
        $harnessExitCode = 0
    }
    else {
        Write-Host "HARNESS RED: privacy/RAW gaps remain ($($failed.Count) of $($caseResults.Count) bounded checks failed)."
        $harnessExitCode = 1
    }
}
catch {
    Write-Host "HARNESS SETUP RED: $($_.Exception.Message)"
    $harnessExitCode = 1
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        if (-not (Test-SafeFixtureRoot -Path $fixtureRoot)) {
            Write-Host 'HARNESS CLEANUP BLOCKED: unsafe fixture root.'
            $harnessExitCode = 1
        }
        else {
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
        }
    }
}

exit $harnessExitCode
