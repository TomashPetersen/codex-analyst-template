[CmdletBinding()]
param(
    [string]$Root = '',
    [ValidateSet('A19', 'A20', 'A21', 'A22', 'A23', 'A24', 'A25', 'A26', 'A27', 'A28', 'A29', 'A30')]
    [string]$CaseId = 'A22',
    [ValidateRange(30, 600)]
    [int]$TimeoutSeconds = 240
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$fixturePrefix = 'ModelProjectSemantic-'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ($fixturePrefix + [guid]::NewGuid().ToString('N'))
$harnessExitCode = 1

function ConvertTo-ProcessArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Invoke-PowerShellChild {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][int]$Timeout
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
    $startInfo.Arguments = (($allArguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join ' ')
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
        if (-not $process.WaitForExit($Timeout * 1000)) {
            try { $process.Kill() } catch { }
            throw 'HARNESS-CHILD-TIMEOUT'
        }
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdoutTask.Result
            Stderr = $stderrTask.Result
        }
    }
    finally {
        $process.Dispose()
    }
}

function Write-Utf8Fixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n", "`n"), $utf8NoBom)
}

function Test-ExactFixtureText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$ExpectedContent
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $expected = $ExpectedContent.Replace("`r`n", "`n")
    $actual = [System.IO.File]::ReadAllText($Path)
    return $actual -ceq $expected
}

function Get-TreeHashSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $canonicalRoot = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    return @(
        Get-ChildItem -LiteralPath $canonicalRoot -Recurse -File -Force |
            ForEach-Object {
                $relative = $_.FullName.Substring($canonicalRoot.Length + 1).Replace('\', '/')
                $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                '{0}|{1}|{2}' -f $relative, $_.Length, $hash
            } |
            Sort-Object
    )
}

function Get-TreeStateSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $canonicalRoot = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $entries = [System.Collections.Generic.List[string]]::new()
    $pending.Push($canonicalRoot)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            $relative = $item.FullName.Substring($canonicalRoot.Length + 1).Replace('\', '/')
            $isReparse = ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            if ($isReparse) {
                $linkType = if ($null -ne $item.PSObject.Properties['LinkType']) {
                    [string]$item.LinkType
                }
                else {
                    'reparse'
                }
                $linkTargets = if ($null -ne $item.PSObject.Properties['Target']) {
                    @($item.Target | ForEach-Object { [string]$_ }) -join ','
                }
                else {
                    ''
                }
                $kind = if ($item.PSIsContainer) { 'REPARSE-DIR' } else { 'REPARSE-FILE' }
                $entries.Add(('{0}|{1}|{2}|{3}' -f $kind, $relative, $linkType, $linkTargets)) | Out-Null
                continue
            }
            if ($item.PSIsContainer) {
                $entries.Add(('DIR|{0}' -f $relative)) | Out-Null
                $pending.Push($item.FullName)
                continue
            }
            $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $entries.Add(('FILE|{0}|{1}|{2}' -f $relative, $item.Length, $hash)) | Out-Null
        }
    }
    return @($entries | Sort-Object)
}

function Get-UnexpectedFixtureArtifacts {
    param([Parameter(Mandatory = $true)][string]$Path)

    $canonicalRoot = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $unexpected = [System.Collections.Generic.List[string]]::new()
    $pending.Push($canonicalRoot)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            $relative = $item.FullName.Substring($canonicalRoot.Length + 1).Replace('\', '/')
            if ($item.Name -match '(?i)(?:\.tmp$|\.lock$|\.draft$|\.partial$)') {
                $unexpected.Add($relative) | Out-Null
            }
            $isReparse = ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            if ($item.PSIsContainer -and -not $isReparse) {
                $pending.Push($item.FullName)
            }
        }
    }
    return @($unexpected | Sort-Object)
}

function Remove-FixtureReparsePoints {
    param([Parameter(Mandatory = $true)][string]$Path)

    $canonicalRoot = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $reparsePaths = [System.Collections.Generic.List[object]]::new()
    $pending.Push($canonicalRoot)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            $isReparse = ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            if ($isReparse) {
                $reparsePaths.Add([pscustomobject]@{
                    FullName = $item.FullName
                    IsDirectory = [bool]$item.PSIsContainer
                    Depth = @($item.FullName.Substring($canonicalRoot.Length) -split '[\\/]' | Where-Object { $_ }).Count
                }) | Out-Null
            }
            elseif ($item.PSIsContainer) {
                $pending.Push($item.FullName)
            }
        }
    }
    foreach ($entry in @($reparsePaths | Sort-Object Depth -Descending)) {
        if ($entry.IsDirectory) {
            [System.IO.Directory]::Delete([string]$entry.FullName)
        }
        else {
            [System.IO.File]::Delete([string]$entry.FullName)
        }
    }
}

function New-SemanticCandidateContent {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$ClaimKey,
        [Parameter(Mandatory = $true)][string[]]$SourceRefs,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ConflictRefs,
        [Parameter(Mandatory = $true)][string]$CaptureBasis,
        [Parameter(Mandatory = $true)][string]$AuthorityRef,
        [Parameter(Mandatory = $true)][string]$DismissReason,
        [string]$TargetRef = 'idea/superidea.md#суперидея',
        [string]$AppliedAt = 'null'
    )

    $sourceBlock = @($SourceRefs | ForEach-Object { "  - '$($_.Replace("'", "''"))'" }) -join "`n"
    $conflictBlock = if ($ConflictRefs.Count -eq 0) {
        ' []'
    }
    else {
        "`n" + (@($ConflictRefs | ForEach-Object { "  - '$($_.Replace("'", "''"))'" }) -join "`n")
    }
    return @"
---
id: $Id
state: $State
type: fact
owner_scope: project
domain: idea
claim_key: $ClaimKey
target_ref: $TargetRef
source_refs:
$sourceBlock
conflict_refs:$conflictBlock
confidence: high
capture_basis: $CaptureBasis
data_class: public
created_at: 2026-08-01T00:00:00+04:00
review_due: null
authority_ref: '$AuthorityRef'
applied_at: $AppliedAt
dismiss_reason: $DismissReason
supersedes: null
---

# Semantic negative fixture

## Основание

Synthetic source-only regression fixture.

## Предлагаемое изменение

No canonical write is performed.

## Проверка дублей и противоречий

Only the named negative condition is present.

## Обоснование lifecycle

The public verifier must reject the fixture without changing it.
"@
}

function Test-NegativeVerifierResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Verification,
        [Parameter(Mandatory = $true)][string[]]$StateBefore,
        [Parameter(Mandatory = $true)][string[]]$StateAfter,
        [Parameter(Mandatory = $true)][string]$CaseRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedPattern,
        [switch]$RequireSingleMatch
    )

    $stateDelta = @(Compare-Object -ReferenceObject $StateBefore -DifferenceObject $StateAfter)
    $unexpectedArtifacts = @(Get-UnexpectedFixtureArtifacts -Path $CaseRoot)
    if ($stateDelta.Count -ne 0 -or $unexpectedArtifacts.Count -ne 0) {
        Write-Host "RED: $Name verifier changed SHA/directory/reparse state or left a temporary artifact."
        return $false
    }
    if ($Verification.ExitCode -eq 0) {
        Write-Host "RED: $Name unexpected PASS - invalid reference or lifecycle state was accepted."
        return $false
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Verification.Stderr)) {
        Write-Host "RED: $Name verifier wrote an implementation diagnostic to stderr."
        return $false
    }
    $diagnostic = [string]$Verification.Stdout
    $casePattern = [regex]::Escape([System.IO.Path]::GetFullPath($CaseRoot))
    if ($diagnostic -match $casePattern -or
        $diagnostic -match '(?i)(?:InvocationInfo|ScriptStackTrace|PositionMessage)') {
        Write-Host "RED: $Name verifier exposed an unsafe implementation or absolute-path diagnostic."
        return $false
    }
    $diagnosticMatches = [regex]::Matches($diagnostic, $ExpectedPattern)
    if ($diagnosticMatches.Count -eq 0) {
        $knownDiagnosticCodes = [System.Collections.Generic.List[string]]::new()
        foreach ($known in @(
            [pscustomobject]@{ Code = 'duplicate-candidate-id'; Pattern = 'Duplicate candidate ID' },
            [pscustomobject]@{ Code = 'duplicate-claim-key'; Pattern = 'Duplicate claim_key' },
            [pscustomobject]@{ Code = 'invalid-candidate-id'; Pattern = 'invalid candidate id' },
            [pscustomobject]@{ Code = 'invalid-claim-key'; Pattern = 'invalid claim_key' },
            [pscustomobject]@{ Code = 'authority-ref'; Pattern = 'authority_ref' },
            [pscustomobject]@{ Code = 'missing-target'; Pattern = 'target_ref: отсутствующий файл' },
            [pscustomobject]@{ Code = 'missing-backlink'; Pattern = 'не имеет Markdown-backlink' }
        )) {
            if ($diagnostic -match $known.Pattern) { $knownDiagnosticCodes.Add($known.Code) | Out-Null }
        }
        $knownSummary = if ($knownDiagnosticCodes.Count -eq 0) { 'none' } else { @($knownDiagnosticCodes) -join ',' }
        Write-Host "RED: $Name blocked without the expected case-specific safe diagnostic; observed-codes=$knownSummary."
        return $false
    }
    if ($RequireSingleMatch -and $diagnosticMatches.Count -ne 1) {
        Write-Host "RED: $Name emitted an unexpected number of case-specific diagnostics."
        return $false
    }
    Write-Host "PASS: $Name is blocked safely, read-only, and without stderr."
    return $true
}

function Test-SafeFixtureRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $canonical = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    $expectedParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]'\/')
    $actualParent = [System.IO.Path]::GetFullPath((Split-Path -Parent $canonical)).TrimEnd([char[]]'\/')
    $leaf = Split-Path -Leaf $canonical
    return (
        $actualParent.Equals($expectedParent, [System.StringComparison]::OrdinalIgnoreCase) -and
        $leaf -cmatch ('^' + [regex]::Escape($fixturePrefix) + '[0-9a-f]{32}$')
    )
}

try {
    $sourceRoot = if ([string]::IsNullOrWhiteSpace($Root)) {
        Split-Path -Parent $PSScriptRoot
    }
    else {
        [System.IO.Path]::GetFullPath($Root)
    }
    $sourceRoot = [System.IO.Path]::GetFullPath($sourceRoot).TrimEnd([char[]]'\/')
    $verifier = Join-Path $sourceRoot 'scripts\verify-knowledge.ps1'
    $manifestPath = Join-Path $sourceRoot '.template-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $verifier -PathType Leaf)) {
        throw 'HARNESS-PUBLIC-ENTRYPOINT-MISSING'
    }

    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    $seedRoot = Join-Path $fixtureRoot 'seed'
    New-Item -ItemType Directory -Path $seedRoot | Out-Null
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    foreach ($relativeFile in @($manifest.portable_files)) {
        $relative = [string]$relativeFile
        if ($relative -notmatch '^[A-Za-z0-9._/\-]+$' -or
            $relative.StartsWith('/') -or
            $relative.Contains('\') -or
            @($relative -split '/' | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
            throw 'HARNESS-MANIFEST-PATH-UNSAFE'
        }
        $source = Join-Path $sourceRoot $relative.Replace('/', '\')
        $destination = Join-Path $seedRoot $relative.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw 'HARNESS-MANIFEST-FILE-MISSING'
        }
        $destinationParent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationParent | Out-Null
        }
        Copy-Item -LiteralPath $source -Destination $destination
    }
    foreach ($relativeDirectory in @($manifest.portable_empty_directories)) {
        $relative = [string]$relativeDirectory
        if ($relative -notmatch '^[A-Za-z0-9._/\-]+$' -or
            $relative.StartsWith('/') -or
            $relative.Contains('\') -or
            @($relative -split '/' | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
            throw 'HARNESS-MANIFEST-PATH-UNSAFE'
        }
        New-Item -ItemType Directory -Path (Join-Path $seedRoot $relative.Replace('/', '\')) -Force | Out-Null
    }

    $initializer = Join-Path $seedRoot 'scripts\initialize-project.ps1'
    $seedResult = Invoke-PowerShellChild -ScriptPath $initializer -Arguments @(
        '-ProjectName', 'Semantic A22 Fixture',
        '-ProjectSlug', 'semantic-a22-fixture',
        '-Description', 'Synthetic generated project for A22 verifier regression.',
        '-Owner', 'fixture-owner',
        '-InitializeGit'
    ) -Timeout $TimeoutSeconds
    if ($seedResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $seedRoot -PathType Container)) {
        Write-Host "HARNESS-SETUP-FAILED: public initialize-project exit=$($seedResult.ExitCode)"
        foreach ($setupLine in @([string]$seedResult.Stdout -split "\r?\n" | Where-Object {
            $_ -match '^(?:FAIL:|-[ ])'
        })) {
            $safeSetupLine = [regex]::Replace(
                $setupLine,
                '(?i)(?:[A-Z]:[\\/]|\\\\)[^\r\n]*',
                '<absolute-path-redacted>'
            )
            Write-Host "HARNESS-SETUP-DIAGNOSTIC: $safeSetupLine"
        }
        $harnessExitCode = 1
    }
    else {
        $seedVerification = Invoke-PowerShellChild -ScriptPath $verifier -Arguments @('-Root', $seedRoot) -Timeout $TimeoutSeconds
        if ($seedVerification.ExitCode -ne 0) {
            Write-Host "HARNESS-SETUP-FAILED: clean generated seed semantic exit=$($seedVerification.ExitCode)"
            throw 'HARNESS-SEED-SEMANTICS'
        }
        if ($CaseId -ceq 'A19') {
            $duplicateSubcases = @(
                [pscustomobject]@{
                    Name = 'A19-duplicate-id'
                    Kind = 'duplicate-id'
                },
                [pscustomobject]@{
                    Name = 'A19-normalized-claim-key'
                    Kind = 'normalized-claim-key'
                }
            )
            $allDuplicateSubcasesPassed = $true
            foreach ($spec in $duplicateSubcases) {
                $caseRoot = Join-Path $fixtureRoot ($spec.Name.ToLowerInvariant() + '-case')
                Copy-Item -LiteralPath $seedRoot -Destination $caseRoot -Recurse
                $candidateFixtures = [System.Collections.Generic.List[object]]::new()
                if ($spec.Kind -ceq 'duplicate-id') {
                    $duplicateId = 'KC-20260801-000000-a1900001'
                    $firstRelative = "knowledge/candidates/2026/$duplicateId.md"
                    $secondRelative = "knowledge/candidates/2027/$duplicateId.md"
                    $candidateFixtures.Add([pscustomobject]@{
                        Relative = $firstRelative
                        Content = New-SemanticCandidateContent `
                            -Id $duplicateId -State 'ready' -ClaimKey 'a19-duplicate-id-one' `
                            -SourceRefs @('idea/INDEX.md') -ConflictRefs @() `
                            -CaptureBasis 'repo-derived' -AuthorityRef 'policy:knowledge-contract-v1' `
                            -DismissReason 'null'
                    }) | Out-Null
                    $candidateFixtures.Add([pscustomobject]@{
                        Relative = $secondRelative
                        Content = New-SemanticCandidateContent `
                            -Id $duplicateId -State 'ready' -ClaimKey 'a19-duplicate-id-two' `
                            -SourceRefs @('idea/INDEX.md') -ConflictRefs @() `
                            -CaptureBasis 'repo-derived' -AuthorityRef 'policy:knowledge-contract-v1' `
                            -DismissReason 'null'
                    }) | Out-Null
                    $expectedPattern = '(?m)^- Duplicate candidate ID: (?:' +
                        [regex]::Escape($firstRelative) + ' и ' + [regex]::Escape($secondRelative) + '|' +
                        [regex]::Escape($secondRelative) + ' и ' + [regex]::Escape($firstRelative) + ')\.\r?$'
                }
                else {
                    $firstId = 'KC-20260801-000000-a1900011'
                    $secondId = 'KC-20260801-000000-a1900012'
                    $firstRelative = "knowledge/candidates/2026/$firstId.md"
                    $secondRelative = "knowledge/candidates/2026/$secondId.md"
                    $candidateFixtures.Add([pscustomobject]@{
                        Relative = $firstRelative
                        Content = New-SemanticCandidateContent `
                            -Id $firstId -State 'ready' -ClaimKey 'a19-normalized-claim' `
                            -SourceRefs @('idea/INDEX.md') -ConflictRefs @() `
                            -CaptureBasis 'repo-derived' -AuthorityRef 'policy:knowledge-contract-v1' `
                            -DismissReason 'null'
                    }) | Out-Null
                    $candidateFixtures.Add([pscustomobject]@{
                        Relative = $secondRelative
                        Content = New-SemanticCandidateContent `
                            -Id $secondId -State 'ready' -ClaimKey 'A19-NORMALIZED-CLAIM' `
                            -SourceRefs @('idea/INDEX.md') -ConflictRefs @() `
                            -CaptureBasis 'repo-derived' -AuthorityRef 'policy:knowledge-contract-v1' `
                            -DismissReason 'null'
                    }) | Out-Null
                    $expectedPattern = '(?m)^- Duplicate claim_key: (?:' +
                        [regex]::Escape($firstRelative) + ' и ' + [regex]::Escape($secondRelative) + '|' +
                        [regex]::Escape($secondRelative) + ' и ' + [regex]::Escape($firstRelative) + ')\.\r?$'
                }

                $textOracleBefore = $true
                foreach ($fixture in $candidateFixtures) {
                    $candidatePath = Join-Path $caseRoot $fixture.Relative.Replace('/', '\')
                    Write-Utf8Fixture -Path $candidatePath -Content $fixture.Content
                    if (-not (Test-ExactFixtureText -Path $candidatePath -ExpectedContent $fixture.Content)) {
                        $textOracleBefore = $false
                    }
                }
                $stateBefore = Get-TreeStateSnapshot -Path $caseRoot
                $verification = Invoke-PowerShellChild -ScriptPath $verifier -Arguments @('-Root', $caseRoot) -Timeout $TimeoutSeconds
                $stateAfter = Get-TreeStateSnapshot -Path $caseRoot
                $textOracleAfter = $true
                foreach ($fixture in $candidateFixtures) {
                    $candidatePath = Join-Path $caseRoot $fixture.Relative.Replace('/', '\')
                    if (-not (Test-ExactFixtureText -Path $candidatePath -ExpectedContent $fixture.Content)) {
                        $textOracleAfter = $false
                    }
                }
                $passed = Test-NegativeVerifierResult `
                    -Name $spec.Name `
                    -Verification $verification `
                    -StateBefore $stateBefore `
                    -StateAfter $stateAfter `
                    -CaseRoot $caseRoot `
                    -ExpectedPattern $expectedPattern `
                    -RequireSingleMatch
                if (-not $textOracleBefore -or -not $textOracleAfter) {
                    Write-Host "RED: $($spec.Name) independent fixture text oracle failed."
                    $passed = $false
                }
                if (-not $passed) { $allDuplicateSubcasesPassed = $false }
            }
            $harnessExitCode = if ($allDuplicateSubcasesPassed) { 0 } else { 1 }
        }
        elseif ($CaseId -ceq 'A20') {
            $caseRoot = Join-Path $fixtureRoot 'a20-applied-without-direct-authority-case'
            Copy-Item -LiteralPath $seedRoot -Destination $caseRoot -Recurse
            $candidateId = 'KC-20260801-000000-a2000001'
            $candidateRelative = "knowledge/candidates/2026/$candidateId.md"
            $candidatePath = Join-Path $caseRoot $candidateRelative.Replace('/', '\')
            $targetPath = Join-Path $caseRoot 'idea\superidea.md'
            $targetOriginal = [System.IO.File]::ReadAllText($targetPath)
            $targetExpected = $targetOriginal.TrimEnd() + @"


- Applied knowledge fixture: [$candidateId](../knowledge/candidates/2026/$candidateId.md).
"@
            Write-Utf8Fixture -Path $targetPath -Content $targetExpected
            $candidateContent = New-SemanticCandidateContent `
                -Id $candidateId -State 'applied' -ClaimKey 'a20-applied-without-direct-authority' `
                -SourceRefs @('idea/INDEX.md') -ConflictRefs @() `
                -CaptureBasis 'repo-derived' -AuthorityRef 'policy:knowledge-contract-v1' `
                -DismissReason 'null' -AppliedAt '2026-08-01T00:01:00+04:00'
            Write-Utf8Fixture -Path $candidatePath -Content $candidateContent
            $textOracleBefore = (
                (Test-ExactFixtureText -Path $candidatePath -ExpectedContent $candidateContent) -and
                (Test-ExactFixtureText -Path $targetPath -ExpectedContent $targetExpected)
            )
            $stateBefore = Get-TreeStateSnapshot -Path $caseRoot
            $verification = Invoke-PowerShellChild -ScriptPath $verifier -Arguments @('-Root', $caseRoot) -Timeout $TimeoutSeconds
            $stateAfter = Get-TreeStateSnapshot -Path $caseRoot
            $textOracleAfter = (
                (Test-ExactFixtureText -Path $candidatePath -ExpectedContent $candidateContent) -and
                (Test-ExactFixtureText -Path $targetPath -ExpectedContent $targetExpected)
            )
            $expectedPattern = '(?m)^- ' + [regex]::Escape($candidateRelative) + ': applied candidate требует authority_ref\.\r?$'
            $passed = Test-NegativeVerifierResult `
                -Name 'A20-applied-without-direct-authority' `
                -Verification $verification `
                -StateBefore $stateBefore `
                -StateAfter $stateAfter `
                -CaseRoot $caseRoot `
                -ExpectedPattern $expectedPattern `
                -RequireSingleMatch
            if (-not $textOracleBefore -or -not $textOracleAfter) {
                Write-Host 'RED: A20 independent candidate/target text oracle failed.'
                $passed = $false
            }
            $harnessExitCode = if ($passed) { 0 } else { 1 }
        }
        elseif ($CaseId -ceq 'A21') {
            $targetSubcases = @(
                [pscustomobject]@{
                    Name = 'A21-applied-without-target'
                    Id = 'KC-20260801-000000-a2100001'
                    ClaimKey = 'a21-applied-without-target'
                    TargetRef = 'idea/missing-a21-target.md#missing'
                    PatternKind = 'missing-target'
                },
                [pscustomobject]@{
                    Name = 'A21-applied-without-backlink'
                    Id = 'KC-20260801-000000-a2100002'
                    ClaimKey = 'a21-applied-without-backlink'
                    TargetRef = 'idea/superidea.md#суперидея'
                    PatternKind = 'missing-backlink'
                }
            )
            $allTargetSubcasesPassed = $true
            foreach ($spec in $targetSubcases) {
                $caseRoot = Join-Path $fixtureRoot ($spec.Name.ToLowerInvariant() + '-case')
                Copy-Item -LiteralPath $seedRoot -Destination $caseRoot -Recurse
                $candidateRelative = "knowledge/candidates/2026/$($spec.Id).md"
                $candidatePath = Join-Path $caseRoot $candidateRelative.Replace('/', '\')
                $candidateContent = New-SemanticCandidateContent `
                    -Id $spec.Id -State 'applied' -ClaimKey $spec.ClaimKey `
                    -SourceRefs @('idea/INDEX.md') -ConflictRefs @() `
                    -CaptureBasis 'explicit-user-capture' -AuthorityRef 'user-request:a21-semantic-fixture' `
                    -DismissReason 'null' -TargetRef $spec.TargetRef `
                    -AppliedAt '2026-08-01T00:01:00+04:00'
                Write-Utf8Fixture -Path $candidatePath -Content $candidateContent
                $targetPath = Join-Path $caseRoot 'idea\superidea.md'
                $targetExpected = [System.IO.File]::ReadAllText($targetPath)
                $textOracleBefore = (
                    (Test-ExactFixtureText -Path $candidatePath -ExpectedContent $candidateContent) -and
                    (Test-ExactFixtureText -Path $targetPath -ExpectedContent $targetExpected)
                )
                $stateBefore = Get-TreeStateSnapshot -Path $caseRoot
                $verification = Invoke-PowerShellChild -ScriptPath $verifier -Arguments @('-Root', $caseRoot) -Timeout $TimeoutSeconds
                $stateAfter = Get-TreeStateSnapshot -Path $caseRoot
                $textOracleAfter = (
                    (Test-ExactFixtureText -Path $candidatePath -ExpectedContent $candidateContent) -and
                    (Test-ExactFixtureText -Path $targetPath -ExpectedContent $targetExpected)
                )
                $expectedPattern = if ($spec.PatternKind -ceq 'missing-target') {
                    '(?m)^- ' + [regex]::Escape($candidateRelative) +
                        ' target_ref: отсутствующий файл: idea/missing-a21-target\.md\r?$'
                }
                else {
                    '(?m)^- ' + [regex]::Escape($candidateRelative) +
                        ': applied candidate не имеет Markdown-backlink из target_ref\.\r?$'
                }
                $passed = Test-NegativeVerifierResult `
                    -Name $spec.Name `
                    -Verification $verification `
                    -StateBefore $stateBefore `
                    -StateAfter $stateAfter `
                    -CaseRoot $caseRoot `
                    -ExpectedPattern $expectedPattern `
                    -RequireSingleMatch
                if (-not $textOracleBefore -or -not $textOracleAfter) {
                    Write-Host "RED: $($spec.Name) independent candidate/target text oracle failed."
                    $passed = $false
                }
                if (-not $passed) { $allTargetSubcasesPassed = $false }
            }
            $harnessExitCode = if ($allTargetSubcasesPassed) { 0 } else { 1 }
        }
        elseif ($CaseId -ceq 'A23') {
            $caseRoot = Join-Path $fixtureRoot 'a23-ready-conflict-report-case'
            Copy-Item -LiteralPath $seedRoot -Destination $caseRoot -Recurse
            $candidateId = 'KC-20260801-000000-a2300001'
            $candidateRelative = "knowledge/candidates/2026/$candidateId.md"
            $candidatePath = Join-Path $caseRoot $candidateRelative.Replace('/', '\')
            $candidateContent = New-SemanticCandidateContent `
                -Id $candidateId -State 'ready' -ClaimKey 'a23-ready-conflict-report' `
                -SourceRefs @('idea/INDEX.md') -ConflictRefs @('idea/INDEX.md') `
                -CaptureBasis 'explicit-user-capture' -AuthorityRef 'user-request:a23-semantic-fixture' `
                -DismissReason 'null'
            Write-Utf8Fixture -Path $candidatePath -Content $candidateContent
            $textOracleBefore = Test-ExactFixtureText -Path $candidatePath -ExpectedContent $candidateContent
            $stateBefore = Get-TreeStateSnapshot -Path $caseRoot
            $strictVerification = Invoke-PowerShellChild -ScriptPath $verifier -Arguments @('-Root', $caseRoot) -Timeout $TimeoutSeconds
            $stateAfterStrict = Get-TreeStateSnapshot -Path $caseRoot
            $reportVerification = Invoke-PowerShellChild -ScriptPath $verifier -Arguments @('-Root', $caseRoot, '-Report') -Timeout $TimeoutSeconds
            $stateAfterReport = Get-TreeStateSnapshot -Path $caseRoot
            $textOracleAfter = Test-ExactFixtureText -Path $candidatePath -ExpectedContent $candidateContent
            $strictStateDelta = @(Compare-Object -ReferenceObject $stateBefore -DifferenceObject $stateAfterStrict)
            $reportStateDelta = @(Compare-Object -ReferenceObject $stateBefore -DifferenceObject $stateAfterReport)
            $unexpectedArtifacts = @(Get-UnexpectedFixtureArtifacts -Path $caseRoot)
            $reportText = [string]$reportVerification.Stdout
            $reportConflictHeader = [regex]::Matches($reportText, '(?m)^- conflicts: 1\r?$')
            $reportConflictItem = [regex]::Matches(
                $reportText,
                '(?m)^  - ' + [regex]::Escape($candidateId) + ' -> count=1\r?$'
            )
            $casePattern = [regex]::Escape([System.IO.Path]::GetFullPath($caseRoot))
            $passed = $true
            if (-not $textOracleBefore -or -not $textOracleAfter) {
                Write-Host 'RED: A23 independent candidate text oracle failed.'
                $passed = $false
            }
            if ($strictStateDelta.Count -ne 0 -or $reportStateDelta.Count -ne 0 -or $unexpectedArtifacts.Count -ne 0) {
                Write-Host 'RED: A23 verifier/report changed SHA/directory state or left a temporary artifact.'
                $passed = $false
            }
            if ($strictVerification.ExitCode -ne 0 -or
                -not [string]::IsNullOrWhiteSpace([string]$strictVerification.Stderr) -or
                ([string]$strictVerification.Stdout).Trim() -cne 'PASS: semantic knowledge gate.') {
                Write-Host 'RED: A23 strict verifier did not return the exact clean PASS contract.'
                $passed = $false
            }
            if ($reportVerification.ExitCode -ne 0 -or
                -not [string]::IsNullOrWhiteSpace([string]$reportVerification.Stderr) -or
                $reportText -match '(?m)^FAIL:' -or
                $reportText -match $casePattern -or
                $reportText -match '(?i)(?:InvocationInfo|ScriptStackTrace|PositionMessage)' -or
                $reportConflictHeader.Count -ne 1 -or
                $reportConflictItem.Count -ne 1) {
                Write-Host 'RED: A23 report omitted or distorted the exact ready-conflict entry.'
                $passed = $false
            }
            if ($passed) {
                Write-Host 'PASS: A23 ready candidate with conflict_refs passes strict and appears exactly once in -Report.'
            }
            $harnessExitCode = if ($passed) { 0 } else { 1 }
        }
        elseif ($CaseId -ceq 'A25') {
            $allCycleSubcasesPassed = $true
            foreach ($nodeCount in @(2, 3)) {
                $subcaseName = "A25-$nodeCount-node"
                $caseRoot = Join-Path $fixtureRoot ("a25-$nodeCount-node-case")
                Copy-Item -LiteralPath $seedRoot -Destination $caseRoot -Recurse

                $candidateIds = if ($nodeCount -eq 2) {
                    @(
                        'KC-20260801-000000-a2500001',
                        'KC-20260801-000000-a2500002'
                    )
                }
                else {
                    @(
                        'KC-20260801-000000-a2500011',
                        'KC-20260801-000000-a2500012',
                        'KC-20260801-000000-a2500013'
                    )
                }
                $candidatePaths = [System.Collections.Generic.List[string]]::new()
                for ($candidateIndex = 0; $candidateIndex -lt $candidateIds.Count; $candidateIndex++) {
                    $candidateId = $candidateIds[$candidateIndex]
                    $supersededId = $candidateIds[($candidateIndex + 1) % $candidateIds.Count]
                    $candidatePath = Join-Path $caseRoot "knowledge\candidates\2026\$candidateId.md"
                    Write-Utf8Fixture -Path $candidatePath -Content @"
---
id: $candidateId
state: ready
type: fact
owner_scope: project
domain: idea
claim_key: a25-$nodeCount-node-$candidateIndex
target_ref: idea/superidea.md#суперидея
source_refs:
  - idea/INDEX.md
conflict_refs: []
confidence: high
capture_basis: explicit-user-capture
data_class: public
created_at: 2026-08-01T00:00:00+04:00
review_due: null
authority_ref: user-request:a25-semantic-fixture
applied_at: null
dismiss_reason: null
supersedes: $supersededId
---

# A25 supersedes cycle node

## Основание

Synthetic source-only regression fixture.

## Предлагаемое изменение

No canonical write is performed for a ready candidate.

## Проверка дублей и противоречий

No unresolved conflict exists.

## Обоснование lifecycle

Every ready invariant except membership in a supersedes cycle is satisfied.
"@
                    $candidatePaths.Add($candidatePath) | Out-Null
                }

                $candidateHashesBefore = @(
                    $candidatePaths | ForEach-Object {
                        (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
                    }
                )
                $treeBefore = Get-TreeHashSnapshot -Path $caseRoot
                $verification = Invoke-PowerShellChild -ScriptPath $verifier -Arguments @('-Root', $caseRoot) -Timeout $TimeoutSeconds
                $treeAfter = Get-TreeHashSnapshot -Path $caseRoot
                $candidateHashesAfter = @(
                    $candidatePaths | ForEach-Object {
                        (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
                    }
                )
                $treeDelta = @(Compare-Object -ReferenceObject $treeBefore -DifferenceObject $treeAfter)
                $candidateHashDelta = @(Compare-Object -ReferenceObject $candidateHashesBefore -DifferenceObject $candidateHashesAfter)
                $unexpectedArtifacts = @(
                    Get-ChildItem -LiteralPath $caseRoot -Recurse -File -Force |
                        Where-Object { $_.Name -match '(?i)(?:\.tmp$|\.lock$|\.draft$|\.partial$)' }
                )

                if ($treeDelta.Count -ne 0 -or $candidateHashDelta.Count -ne 0 -or $unexpectedArtifacts.Count -ne 0) {
                    Write-Host "RED: $subcaseName verifier changed fixture state or left a temporary artifact."
                    $allCycleSubcasesPassed = $false
                }
                elseif ($verification.ExitCode -eq 0) {
                    Write-Host "RED: $subcaseName unexpected PASS - supersedes cycle was accepted."
                    $allCycleSubcasesPassed = $false
                }
                else {
                    $diagnostic = $verification.Stdout + "`n" + $verification.Stderr
                    $safePattern = '(?is)(?:supersedes.{0,160}(?:cycle|цикл)|(?:cycle|цикл).{0,160}supersedes|candidate[-_ ]?supersedes[-_ ]?cycle)'
                    if ($diagnostic -notmatch $safePattern) {
                        Write-Host "RED: $subcaseName blocked without the expected safe cycle diagnostic."
                        $allCycleSubcasesPassed = $false
                    }
                    else {
                        Write-Host "PASS: $subcaseName supersedes cycle is blocked safely and read-only."
                    }
                }
            }
            $harnessExitCode = if ($allCycleSubcasesPassed) { 0 } else { 1 }
        }
        elseif ($CaseId -ceq 'A27') {
            $stateSubcases = @(
                [pscustomobject]@{
                    Name = 'A27-ready-applied-at'
                    Id = 'KC-20260801-000000-a2700001'
                    ClaimKey = 'a27-ready-applied-at'
                    State = 'ready'
                    AppliedAt = '2026-08-01T00:01:00+04:00'
                    DismissReason = 'null'
                    NeedsBacklink = $false
                    Pattern = '(?is)(?:ready.{0,160}applied_at|applied_at.{0,160}ready|candidate[-_ ]?state[-_ ]?fields)'
                },
                [pscustomobject]@{
                    Name = 'A27-ready-dismiss-reason'
                    Id = 'KC-20260801-000000-a2700002'
                    ClaimKey = 'a27-ready-dismiss-reason'
                    State = 'ready'
                    AppliedAt = 'null'
                    DismissReason = 'rejected'
                    NeedsBacklink = $false
                    Pattern = '(?is)(?:ready.{0,160}dismiss_reason|dismiss_reason.{0,160}ready|candidate[-_ ]?state[-_ ]?fields)'
                },
                [pscustomobject]@{
                    Name = 'A27-applied-dismiss-reason'
                    Id = 'KC-20260801-000000-a2700003'
                    ClaimKey = 'a27-applied-dismiss-reason'
                    State = 'applied'
                    AppliedAt = '2026-08-01T00:01:00+04:00'
                    DismissReason = 'rejected'
                    NeedsBacklink = $true
                    Pattern = '(?is)(?:applied.{0,160}dismiss_reason|dismiss_reason.{0,160}applied|candidate[-_ ]?state[-_ ]?fields)'
                },
                [pscustomobject]@{
                    Name = 'A27-dismissed-applied-at'
                    Id = 'KC-20260801-000000-a2700004'
                    ClaimKey = 'a27-dismissed-applied-at'
                    State = 'dismissed'
                    AppliedAt = '2026-08-01T00:01:00+04:00'
                    DismissReason = 'rejected'
                    NeedsBacklink = $false
                    Pattern = '(?is)(?:dismissed.{0,160}applied_at|applied_at.{0,160}dismissed|candidate[-_ ]?state[-_ ]?fields)'
                }
            )
            $allStateSubcasesPassed = $true
            foreach ($spec in $stateSubcases) {
                $caseRoot = Join-Path $fixtureRoot ($spec.Name.ToLowerInvariant() + '-case')
                Copy-Item -LiteralPath $seedRoot -Destination $caseRoot -Recurse
                $candidatePath = Join-Path $caseRoot "knowledge\candidates\2026\$($spec.Id).md"
                if ($spec.NeedsBacklink) {
                    $targetPath = Join-Path $caseRoot 'idea\superidea.md'
                    $targetContent = [System.IO.File]::ReadAllText($targetPath)
                    Write-Utf8Fixture -Path $targetPath -Content ($targetContent.TrimEnd() + @"


- Applied knowledge fixture: [$($spec.Id)](../knowledge/candidates/2026/$($spec.Id).md).
"@)
                }
                Write-Utf8Fixture -Path $candidatePath -Content @"
---
id: $($spec.Id)
state: $($spec.State)
type: fact
owner_scope: project
domain: idea
claim_key: $($spec.ClaimKey)
target_ref: idea/superidea.md#суперидея
source_refs:
  - idea/INDEX.md
conflict_refs: []
confidence: high
capture_basis: explicit-user-capture
data_class: public
created_at: 2026-08-01T00:00:00+04:00
review_due: null
authority_ref: user-request:a27-semantic-fixture
applied_at: $($spec.AppliedAt)
dismiss_reason: $($spec.DismissReason)
supersedes: null
---

# A27 invalid state-field combination fixture

## Основание

Synthetic source-only regression fixture.

## Предлагаемое изменение

The target and provenance fields are otherwise valid.

## Проверка дублей и противоречий

No unresolved conflict exists.

## Обоснование lifecycle

Exactly one forbidden state-field combination is present.
"@

                $candidateHashBefore = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
                $treeBefore = Get-TreeHashSnapshot -Path $caseRoot
                $verification = Invoke-PowerShellChild -ScriptPath $verifier -Arguments @('-Root', $caseRoot) -Timeout $TimeoutSeconds
                $treeAfter = Get-TreeHashSnapshot -Path $caseRoot
                $candidateHashAfter = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
                $treeDelta = @(Compare-Object -ReferenceObject $treeBefore -DifferenceObject $treeAfter)
                $unexpectedArtifacts = @(
                    Get-ChildItem -LiteralPath $caseRoot -Recurse -File -Force |
                        Where-Object { $_.Name -match '(?i)(?:\.tmp$|\.lock$|\.draft$|\.partial$)' }
                )

                if ($candidateHashBefore -cne $candidateHashAfter -or $treeDelta.Count -ne 0 -or $unexpectedArtifacts.Count -ne 0) {
                    Write-Host "RED: $($spec.Name) verifier changed fixture state or left a temporary artifact."
                    $allStateSubcasesPassed = $false
                }
                elseif ($verification.ExitCode -eq 0) {
                    Write-Host "RED: $($spec.Name) unexpected PASS - invalid state-field combination was accepted."
                    $allStateSubcasesPassed = $false
                }
                else {
                    $diagnostic = $verification.Stdout + "`n" + $verification.Stderr
                    if ($diagnostic -notmatch $spec.Pattern) {
                        Write-Host "RED: $($spec.Name) blocked without the expected safe state-field diagnostic."
                        $allStateSubcasesPassed = $false
                    }
                    else {
                        Write-Host "PASS: $($spec.Name) is blocked safely and read-only."
                    }
                }
            }
            $harnessExitCode = if ($allStateSubcasesPassed) { 0 } else { 1 }
        }
        elseif ($CaseId -ceq 'A28') {
            $dismissalSubcases = @(
                [pscustomobject]@{
                    Name = 'A28-dismissed-without-reason'
                    Id = 'KC-20260801-000000-a2800001'
                    ClaimKey = 'a28-dismissed-without-reason'
                    CaptureBasis = 'explicit-user-capture'
                    AuthorityRef = 'user-request:a28-semantic-fixture'
                    DismissReason = 'null'
                    Pattern = '(?is)(?:dismissed.{0,180}(?:dismiss_reason|reason)|dismiss_reason.{0,180}dismissed)'
                },
                [pscustomobject]@{
                    Name = 'A28-dismissed-without-direct-authority'
                    Id = 'KC-20260801-000000-a2800002'
                    ClaimKey = 'a28-dismissed-without-direct-authority'
                    CaptureBasis = 'repo-derived'
                    AuthorityRef = 'policy:knowledge-contract-v1'
                    DismissReason = 'rejected'
                    Pattern = '(?is)(?:dismissed.{0,180}authority_ref|authority_ref.{0,180}dismissed)'
                }
            )
            $allDismissalSubcasesPassed = $true
            foreach ($spec in $dismissalSubcases) {
                $caseRoot = Join-Path $fixtureRoot ($spec.Name.ToLowerInvariant() + '-case')
                Copy-Item -LiteralPath $seedRoot -Destination $caseRoot -Recurse
                $candidatePath = Join-Path $caseRoot "knowledge\candidates\2026\$($spec.Id).md"
                $candidateContent = New-SemanticCandidateContent `
                    -Id $spec.Id `
                    -State 'dismissed' `
                    -ClaimKey $spec.ClaimKey `
                    -SourceRefs @('idea/INDEX.md') `
                    -ConflictRefs @() `
                    -CaptureBasis $spec.CaptureBasis `
                    -AuthorityRef $spec.AuthorityRef `
                    -DismissReason $spec.DismissReason
                Write-Utf8Fixture -Path $candidatePath -Content $candidateContent

                $stateBefore = Get-TreeStateSnapshot -Path $caseRoot
                $verification = Invoke-PowerShellChild -ScriptPath $verifier -Arguments @('-Root', $caseRoot) -Timeout $TimeoutSeconds
                $stateAfter = Get-TreeStateSnapshot -Path $caseRoot
                $passed = Test-NegativeVerifierResult `
                    -Name $spec.Name `
                    -Verification $verification `
                    -StateBefore $stateBefore `
                    -StateAfter $stateAfter `
                    -CaseRoot $caseRoot `
                    -ExpectedPattern $spec.Pattern
                if (-not $passed) {
                    $allDismissalSubcasesPassed = $false
                }
            }
            $harnessExitCode = if ($allDismissalSubcasesPassed) { 0 } else { 1 }
        }
        elseif ($CaseId -ceq 'A29') {
            $brokenReferenceSubcases = @(
                [pscustomobject]@{
                    Name = 'A29-broken-source-ref'
                    Id = 'KC-20260801-000000-a2900001'
                    ClaimKey = 'a29-broken-source-ref'
                    SourceRefs = @('docs/missing-a29-source.md')
                    ConflictRefs = @()
                    Pattern = '(?is)source_refs.{0,180}(?:отсутствующ|missing|broken)'
                },
                [pscustomobject]@{
                    Name = 'A29-broken-conflict-ref'
                    Id = 'KC-20260801-000000-a2900002'
                    ClaimKey = 'a29-broken-conflict-ref'
                    SourceRefs = @('idea/INDEX.md')
                    ConflictRefs = @('docs/missing-a29-conflict.md')
                    Pattern = '(?is)conflict_refs.{0,180}(?:отсутствующ|missing|broken)'
                }
            )
            $allBrokenReferenceSubcasesPassed = $true
            foreach ($spec in $brokenReferenceSubcases) {
                $caseRoot = Join-Path $fixtureRoot ($spec.Name.ToLowerInvariant() + '-case')
                Copy-Item -LiteralPath $seedRoot -Destination $caseRoot -Recurse
                $candidatePath = Join-Path $caseRoot "knowledge\candidates\2026\$($spec.Id).md"
                $candidateContent = New-SemanticCandidateContent `
                    -Id $spec.Id `
                    -State 'ready' `
                    -ClaimKey $spec.ClaimKey `
                    -SourceRefs $spec.SourceRefs `
                    -ConflictRefs $spec.ConflictRefs `
                    -CaptureBasis 'repo-derived' `
                    -AuthorityRef 'policy:knowledge-contract-v1' `
                    -DismissReason 'null'
                Write-Utf8Fixture -Path $candidatePath -Content $candidateContent

                $stateBefore = Get-TreeStateSnapshot -Path $caseRoot
                $verification = Invoke-PowerShellChild -ScriptPath $verifier -Arguments @('-Root', $caseRoot) -Timeout $TimeoutSeconds
                $stateAfter = Get-TreeStateSnapshot -Path $caseRoot
                $passed = Test-NegativeVerifierResult `
                    -Name $spec.Name `
                    -Verification $verification `
                    -StateBefore $stateBefore `
                    -StateAfter $stateAfter `
                    -CaseRoot $caseRoot `
                    -ExpectedPattern $spec.Pattern
                if (-not $passed) {
                    $allBrokenReferenceSubcasesPassed = $false
                }
            }
            $harnessExitCode = if ($allBrokenReferenceSubcasesPassed) { 0 } else { 1 }
        }
        elseif ($CaseId -ceq 'A30') {
            $pathSafetySubcases = @(
                [pscustomobject]@{
                    Name = 'A30-absolute-local-path'
                    Id = 'KC-20260801-000000-a3000001'
                    ClaimKey = 'a30-absolute-local-path'
                    SourceRef = 'C:/forbidden/a30-reference.md'
                    Setup = 'none'
                    Pattern = '(?is)(?:absolute-local-path|абсолютн.{0,100}путь)'
                },
                [pscustomobject]@{
                    Name = 'A30-path-traversal'
                    Id = 'KC-20260801-000000-a3000002'
                    ClaimKey = 'a30-path-traversal'
                    SourceRef = '../outside-a30.md'
                    Setup = 'none'
                    Pattern = '(?is)(?:path-traversal|traversal|выходит за корень)'
                },
                [pscustomobject]@{
                    Name = 'A30-reparse-chain-to-file'
                    Id = 'KC-20260801-000000-a3000003'
                    ClaimKey = 'a30-reparse-chain-to-file'
                    SourceRef = 'docs/a30-directory-link/source.md'
                    Setup = 'directory-reparse'
                    Pattern = '(?is)reparse point'
                },
                [pscustomobject]@{
                    Name = 'A30-unsafe-uri'
                    Id = 'KC-20260801-000000-a3000004'
                    ClaimKey = 'a30-unsafe-uri'
                    SourceRef = 'javascript:alert(1)'
                    Setup = 'none'
                    Pattern = '(?is)(?:dangerous-markdown-uri|source_refs.{0,240}(?:URI|scheme|ссылк)|неподдерживаемая внешняя ссылка)'
                }
            )
            $allPathSafetySubcasesPassed = $true
            foreach ($spec in $pathSafetySubcases) {
                $caseRoot = Join-Path $fixtureRoot ($spec.Name.ToLowerInvariant() + '-case')
                Copy-Item -LiteralPath $seedRoot -Destination $caseRoot -Recurse
                switch ($spec.Setup) {
                    'directory-reparse' {
                        $realDirectory = Join-Path $caseRoot 'docs\a30-directory-target'
                        $linkDirectory = Join-Path $caseRoot 'docs\a30-directory-link'
                        New-Item -ItemType Directory -Path $realDirectory | Out-Null
                        Write-Utf8Fixture -Path (Join-Path $realDirectory 'source.md') -Content "# A30 directory reparse target`n"
                        New-Item -ItemType Junction -Path $linkDirectory -Target $realDirectory -ErrorAction Stop | Out-Null
                        $linkItem = Get-Item -LiteralPath $linkDirectory -Force
                        if (($linkItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                            throw 'HARNESS-A30-DIRECTORY-REPARSE-NOT-CREATED'
                        }
                    }
                }

                $candidatePath = Join-Path $caseRoot "knowledge\candidates\2026\$($spec.Id).md"
                $candidateContent = New-SemanticCandidateContent `
                    -Id $spec.Id `
                    -State 'ready' `
                    -ClaimKey $spec.ClaimKey `
                    -SourceRefs @($spec.SourceRef) `
                    -ConflictRefs @() `
                    -CaptureBasis 'repo-derived' `
                    -AuthorityRef 'policy:knowledge-contract-v1' `
                    -DismissReason 'null'
                Write-Utf8Fixture -Path $candidatePath -Content $candidateContent

                $stateBefore = Get-TreeStateSnapshot -Path $caseRoot
                $verification = Invoke-PowerShellChild -ScriptPath $verifier -Arguments @('-Root', $caseRoot) -Timeout $TimeoutSeconds
                $stateAfter = Get-TreeStateSnapshot -Path $caseRoot
                $passed = Test-NegativeVerifierResult `
                    -Name $spec.Name `
                    -Verification $verification `
                    -StateBefore $stateBefore `
                    -StateAfter $stateAfter `
                    -CaseRoot $caseRoot `
                    -ExpectedPattern $spec.Pattern
                if (-not $passed) {
                    $allPathSafetySubcasesPassed = $false
                }
            }
            $harnessExitCode = if ($allPathSafetySubcasesPassed) { 0 } else { 1 }
        }
        else {
        $caseRoot = Join-Path $fixtureRoot ($CaseId.ToLowerInvariant() + '-case')
        Copy-Item -LiteralPath $seedRoot -Destination $caseRoot -Recurse

        $candidateId = switch ($CaseId) {
            'A22' { 'KC-20260801-000000-a2200001' }
            'A24' { 'KC-20260801-000000-a2400001' }
            'A26' { 'KC-20260801-000000-a2600001' }
        }
        $candidateRelative = "knowledge/candidates/2026/$candidateId.md"
        $candidatePath = Join-Path $caseRoot $candidateRelative.Replace('/', '\')
        if ($CaseId -ceq 'A22') {
            $targetPath = Join-Path $caseRoot 'idea\superidea.md'
            $targetContent = [System.IO.File]::ReadAllText($targetPath)
            Write-Utf8Fixture -Path $targetPath -Content ($targetContent.TrimEnd() + @"


- Applied knowledge fixture: [$candidateId](../knowledge/candidates/2026/$candidateId.md).
"@)
            $candidateContent = @"
---
id: $candidateId
state: applied
type: fact
owner_scope: project
domain: idea
claim_key: a22-applied-conflict
target_ref: idea/superidea.md#суперидея
source_refs:
  - idea/INDEX.md
conflict_refs:
  - idea/INDEX.md
confidence: high
capture_basis: explicit-user-capture
data_class: public
created_at: 2026-08-01T00:00:00+04:00
review_due: null
authority_ref: user-request:a22-semantic-fixture
applied_at: 2026-08-01T00:01:00+04:00
dismiss_reason: null
supersedes: null
---

# A22 applied conflict fixture

## Основание

Synthetic source-only regression fixture.

## Предлагаемое изменение

Synthetic canonical backlink exists.

## Проверка дублей и противоречий

The unresolved conflict is intentional for A22.

## Обоснование lifecycle

Every applied invariant except empty conflict refs is satisfied.
"@
            $safePattern = '(?is)(?:applied.{0,160}conflict_refs|conflict_refs.{0,160}applied|candidate[-_ ]?conflict)'
            $unexpectedPassMessage = 'RED: A22 unexpected PASS - applied candidate retained nonempty conflict_refs.'
            $wrongDiagnosticMessage = 'RED: A22 blocked without the expected safe conflict diagnostic.'
            $passMessage = 'PASS: A22 applied candidate with nonempty conflict_refs is blocked safely and read-only.'
        }
        elseif ($CaseId -ceq 'A24') {
            $candidateContent = @"
---
id: $candidateId
state: ready
type: fact
owner_scope: project
domain: idea
claim_key: a24-self-supersedes
target_ref: idea/superidea.md#суперидея
source_refs:
  - idea/INDEX.md
conflict_refs: []
confidence: high
capture_basis: explicit-user-capture
data_class: public
created_at: 2026-08-01T00:00:00+04:00
review_due: null
authority_ref: user-request:a24-semantic-fixture
applied_at: null
dismiss_reason: null
supersedes: $candidateId
---

# A24 self-supersedes fixture

## Основание

Synthetic source-only regression fixture.

## Предлагаемое изменение

No canonical write is performed for a ready candidate.

## Проверка дублей и противоречий

No unresolved conflict exists.

## Обоснование lifecycle

Every ready invariant except the self-referential supersedes edge is satisfied.
"@
            $safePattern = '(?is)(?:self.{0,120}supersedes|supersedes.{0,160}(?:self|itself|себя|сам)|candidate[-_ ]?supersedes[-_ ]?self)'
            $unexpectedPassMessage = 'RED: A24 unexpected PASS - candidate supersedes itself.'
            $wrongDiagnosticMessage = 'RED: A24 blocked without the expected safe self-supersedes diagnostic.'
            $passMessage = 'PASS: A24 self-supersedes is blocked safely and read-only.'
        }
        else {
            $targetPath = Join-Path $caseRoot 'idea\superidea.md'
            $targetContent = [System.IO.File]::ReadAllText($targetPath)
            Write-Utf8Fixture -Path $targetPath -Content ($targetContent.TrimEnd() + @"


- Applied knowledge fixture: [$candidateId](../knowledge/candidates/2026/$candidateId.md).
"@)
            $candidateContent = @"
---
id: $candidateId
state: applied
type: fact
owner_scope: project
domain: idea
claim_key: a26-applied-before-created
target_ref: idea/superidea.md#суперидея
source_refs:
  - idea/INDEX.md
conflict_refs: []
confidence: high
capture_basis: explicit-user-capture
data_class: public
created_at: 2026-08-01T00:01:00+04:00
review_due: null
authority_ref: user-request:a26-semantic-fixture
applied_at: 2026-08-01T00:00:00+04:00
dismiss_reason: null
supersedes: null
---

# A26 invalid lifecycle date order fixture

## Основание

Synthetic source-only regression fixture.

## Предлагаемое изменение

Synthetic canonical backlink exists.

## Проверка дублей и противоречий

No unresolved conflict exists.

## Обоснование lifecycle

Every applied invariant except lifecycle date ordering is satisfied.
"@
            $safePattern = '(?is)(?:applied_at.{0,160}created_at|created_at.{0,160}applied_at|candidate[-_ ]?date[-_ ]?order)'
            $unexpectedPassMessage = 'RED: A26 unexpected PASS - applied_at precedes created_at.'
            $wrongDiagnosticMessage = 'RED: A26 blocked without the expected safe lifecycle date diagnostic.'
            $passMessage = 'PASS: A26 applied_at before created_at is blocked safely and read-only.'
        }
        Write-Utf8Fixture -Path $candidatePath -Content $candidateContent

        $candidateHashBefore = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
        $treeBefore = Get-TreeHashSnapshot -Path $caseRoot
        $verification = Invoke-PowerShellChild -ScriptPath $verifier -Arguments @('-Root', $caseRoot) -Timeout $TimeoutSeconds
        $treeAfter = Get-TreeHashSnapshot -Path $caseRoot
        $candidateHashAfter = (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
        $treeDelta = @(Compare-Object -ReferenceObject $treeBefore -DifferenceObject $treeAfter)
        $unexpectedArtifacts = @(
            Get-ChildItem -LiteralPath $caseRoot -Recurse -File -Force |
                Where-Object { $_.Name -match '(?i)(?:\.tmp$|\.lock$|\.draft$|\.partial$)' }
        )

        if ($candidateHashBefore -cne $candidateHashAfter -or $treeDelta.Count -ne 0 -or $unexpectedArtifacts.Count -ne 0) {
            Write-Host "RED: $CaseId verifier changed fixture state or left a temporary artifact."
            $harnessExitCode = 1
        }
        elseif ($verification.ExitCode -eq 0) {
            Write-Host $unexpectedPassMessage
            $harnessExitCode = 1
        }
        else {
            $diagnostic = $verification.Stdout + "`n" + $verification.Stderr
            if ($diagnostic -notmatch $safePattern) {
                Write-Host $wrongDiagnosticMessage
                $harnessExitCode = 1
            }
            else {
                Write-Host $passMessage
                $harnessExitCode = 0
            }
        }
        }
    }
}
catch {
    Write-Host "HARNESS-FAILED: $($_.Exception.Message)"
    $harnessExitCode = 1
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        if (-not (Test-SafeFixtureRoot -Path $fixtureRoot)) {
            Write-Host 'HARNESS-CLEANUP-BLOCKED: unsafe fixture root.'
            $harnessExitCode = 1
        }
        else {
            try {
                Remove-FixtureReparsePoints -Path $fixtureRoot
            }
            catch {
                Write-Host 'HARNESS-CLEANUP-FAILED: fixture reparse point remains.'
                $harnessExitCode = 1
            }
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
            if (Test-Path -LiteralPath $fixtureRoot) {
                Write-Host 'HARNESS-CLEANUP-FAILED: fixture root remains.'
                $harnessExitCode = 1
            }
        }
    }
}

exit $harnessExitCode
