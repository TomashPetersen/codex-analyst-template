[CmdletBinding()]
param([string]$Root = '')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$sourceRoot = if ([string]::IsNullOrWhiteSpace($Root)) {
    Split-Path -Parent $PSScriptRoot
}
else {
    [System.IO.Path]::GetFullPath($Root)
}
Import-Module (Join-Path $sourceRoot 'scripts/lib/ModelProject.Platform.psm1') -Force
$pwshPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]'\/')
$tempComparison = Get-ModelProjectPathComparison -Path $tempBase
$fixtureRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('model-project-mastery-v2-' + [guid]::NewGuid().ToString('N'))))

function Write-FixtureText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Invoke-ChildScript {
    param(
        [Parameter(Mandatory = $true)][string]$Script,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwshPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $utf8NoBom
    $startInfo.StandardErrorEncoding = $utf8NoBom
    foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $Script) + $Arguments) {
        $startInfo.ArgumentList.Add([string]$argument)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "Не удалось запустить fixture script: $Script" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $result = [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdoutTask.GetAwaiter().GetResult()
        Stderr = $stderrTask.GetAwaiter().GetResult()
    }
    $process.Dispose()
    return $result
}

function Assert-ChildResult {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [string[]]$StdoutPatterns = @(),
        [string[]]$StderrPatterns = @()
    )
    if ($Result.ExitCode -ne $ExitCode) {
        throw "Unexpected exit $($Result.ExitCode), expected $ExitCode. stdout=$($Result.Stdout) stderr=$($Result.Stderr)"
    }
    foreach ($pattern in $StdoutPatterns) {
        if ([string]$Result.Stdout -cnotmatch $pattern) {
            throw "stdout не содержит pattern: $pattern. Actual: $($Result.Stdout)"
        }
    }
    foreach ($pattern in $StderrPatterns) {
        if ([string]$Result.Stderr -cnotmatch $pattern) {
            throw "stderr не содержит pattern: $pattern. Actual: $($Result.Stderr)"
        }
    }
}

function Get-TreeFingerprint {
    param([Parameter(Mandatory = $true)][string]$RootPath)
    $records = foreach ($file in @(Get-ChildItem -LiteralPath $RootPath -Recurse -File -Force | Where-Object {
        $_.FullName -notmatch '[\\/]\.git(?:[\\/]|$)'
    } | Sort-Object -Property FullName)) {
        $relative = [System.IO.Path]::GetRelativePath($RootPath, $file.FullName).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relative`t$hash"
    }
    $bytes = $utf8NoBom.GetBytes(($records -join "`n"))
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function New-MethodCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$ClaimId,
        [Parameter(Mandatory = $true)][string]$Title,
        [string[]]$Intents = @('planning', 'review')
    )
    $parameters = @{
        Root = $fixtureRoot
        Type = 'method'
        Domain = 'mastery'
        ClaimKey = "method.$ClaimId"
        TargetRef = 'mastery/local/INDEX.md#зарегистрированные-расширения'
        SourceRefs = @('PROJECT.md')
        Confidence = 'high'
        CaptureBasis = 'explicit-user-capture'
        DataClass = 'internal'
        Title = $Title
        Basis = 'Прямая коррекция владельца подтверждает повторяемый fixture method.'
        ProposedChange = 'Сверить критерии приемки, фактический diff и evidence до завершения фазы.'
        MethodKind = 'checklist'
        MethodSummary = 'Проверяет завершение фазы по критериям, diff и evidence.'
        MethodAppliesTo = @($Intents)
        DuplicateCheck = 'Совпадающий method_id и активный Local Mastery отсутствуют.'
        ReviewDue = [datetime]::UtcNow.AddMonths(6).ToString('yyyy-MM-dd')
        AuthorityRef = "user-request:mastery-v2-$ClaimId"
        WriteIntent = 'explicit-promotion'
    }
    $candidateRoot = Join-Path $fixtureRoot 'knowledge/candidates'
    $before = @(
        Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter 'KC-*.md' -Force |
            ForEach-Object { $_.BaseName }
    )
    [void](& (Join-Path $fixtureRoot 'scripts/new-knowledge-candidate.ps1') @parameters 2>&1)
    $added = @(
        Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter 'KC-*.md' -Force |
            ForEach-Object { $_.BaseName } |
            Where-Object { $_ -cnotin $before }
    )
    if ($added.Count -ne 1 -or $added[0] -cnotmatch '^KC-\d{8}-\d{6}-[0-9a-f]{8}$') {
        throw "Candidate generator должен создать ровно один candidate, найдено: $($added -join ', ')."
    }
    return [string]$added[0]
}

function Invoke-RepositoryScript {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
        [int]$ExpectedExitCode = 0,
        [string[]]$StdoutPatterns = @(),
        [string[]]$StderrPatterns = @()
    )
    $result = Invoke-ChildScript -Script (Join-Path $fixtureRoot $RelativePath) -Arguments $Arguments
    Assert-ChildResult -Result $result -ExitCode $ExpectedExitCode -StdoutPatterns $StdoutPatterns -StderrPatterns $StderrPatterns
    return $result
}

try {
    if (-not $fixtureRoot.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, $tempComparison) -or
        [System.IO.Path]::GetFileName($fixtureRoot) -cnotmatch '^model-project-mastery-v2-[a-f0-9]{32}$') {
        throw 'Unsafe Mastery v2 fixture root.'
    }

    $newProject = Invoke-ChildScript -Script (Join-Path $sourceRoot 'scripts/new-project.ps1') -Arguments @(
        '-Destination', $fixtureRoot,
        '-ProjectName', 'Mastery v2 fixture',
        '-ProjectSlug', 'mastery-v2-fixture',
        '-Description', 'Generic fixture for Local Mastery lifecycle.',
        '-Owner', 'project-owner'
    )
    Assert-ChildResult -Result $newProject -ExitCode 0 -StdoutPatterns @('Новый проект создан атомарным rename')

    $candidateId = New-MethodCandidate -ClaimId 'phase-review-checklist' -Title 'Phase review checklist'
    $masteryArguments = @(
        '-Root', $fixtureRoot,
        '-CandidateId', $candidateId,
        '-AuthorityRef', 'user-request:mastery-v2-approval'
    )

    $beforePreview = Get-TreeFingerprint -RootPath $fixtureRoot
    [void](Invoke-RepositoryScript -RelativePath 'scripts/new-mastery.ps1' -Arguments ($masteryArguments + '-WhatIf') -StdoutPatterns @(
        '^PREVIEW ',
        '(?m)^MUTATION=none\r?$'
    ))
    $afterPreview = Get-TreeFingerprint -RootPath $fixtureRoot
    if ($beforePreview -cne $afterPreview) { throw 'WhatIf изменил fixture tree.' }

    $beforeInvalidAuthority = Get-TreeFingerprint -RootPath $fixtureRoot
    [void](Invoke-RepositoryScript -RelativePath 'scripts/new-mastery.ps1' -Arguments @(
        '-Root', $fixtureRoot,
        '-CandidateId', $candidateId,
        '-AuthorityRef', 'policy:not-user-authority'
    ) -ExpectedExitCode 1)
    if ($beforeInvalidAuthority -cne (Get-TreeFingerprint -RootPath $fixtureRoot)) {
        throw 'Invalid authority изменила fixture tree.'
    }

    [void](Invoke-RepositoryScript -RelativePath 'scripts/new-mastery.ps1' -Arguments $masteryArguments -StdoutPatterns @(
        "(?m)^APPLIED \[$([regex]::Escape($candidateId))\]: mastery/local/phase-review-checklist\.md\r?$",
        '(?m)^KNOWLEDGE_GRAPH=updated\r?$'
    ))
    $candidatePath = @(Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'knowledge/candidates') -Recurse -File -Filter "$candidateId.md")[0].FullName
    $candidateText = [System.IO.File]::ReadAllText($candidatePath)
    $methodPath = Join-Path $fixtureRoot 'mastery/local/phase-review-checklist.md'
    if ($candidateText -cnotmatch '(?m)^state: applied\s*$' -or
        $candidateText -cnotmatch "(?m)^authority_ref: 'user-request:mastery-v2-approval'\s*$" -or
        -not (Test-Path -LiteralPath $methodPath -PathType Leaf)) {
        throw 'Applied candidate или method artifact не соответствует ожидаемому post-state.'
    }
    $methodText = [System.IO.File]::ReadAllText($methodPath)
    foreach ($pattern in @(
        '(?m)^mastery_contract_version: 2\s*$',
        "(?m)^method_id: 'phase-review-checklist'\s*$",
        "(?m)^  - 'planning'\s*$",
        [regex]::Escape("  - '$($candidatePath.Substring($fixtureRoot.Length + 1).Replace('\', '/'))'")
    )) {
        if ($methodText -cnotmatch $pattern) { throw "Method artifact не содержит pattern: $pattern" }
    }

    [void](Invoke-RepositoryScript -RelativePath 'scripts/verify-knowledge.ps1' -Arguments @('-Root', $fixtureRoot))
    [void](Invoke-RepositoryScript -RelativePath 'scripts/update-mastery-index.ps1' -Arguments @('-Root', $fixtureRoot, '-Mode', 'Check'))
    [void](Invoke-RepositoryScript -RelativePath 'scripts/update-knowledge-graph.ps1' -Arguments @('-Root', $fixtureRoot, '-Mode', 'Check'))
    [void](Invoke-RepositoryScript -RelativePath 'scripts/verify-structure.ps1' -Arguments @('-Root', $fixtureRoot, '-Mode', 'GeneratedProject'))

    $indexPath = Join-Path $fixtureRoot 'mastery/local/INDEX.md'
    $validIndex = [System.IO.File]::ReadAllText($indexPath)
    Write-FixtureText -Path $indexPath -Content ($validIndex + "manual drift`n")
    [void](Invoke-RepositoryScript -RelativePath 'scripts/update-mastery-index.ps1' -Arguments @('-Root', $fixtureRoot, '-Mode', 'Check') -ExpectedExitCode 1 -StderrPatterns @('mastery/local/INDEX\.md'))
    [void](Invoke-RepositoryScript -RelativePath 'scripts/update-mastery-index.ps1' -Arguments @('-Root', $fixtureRoot, '-Mode', 'Write'))

    $beforeInvalidIntent = Get-TreeFingerprint -RootPath $fixtureRoot
    $invalidIntentBlocked = $false
    try {
        [void](New-MethodCandidate -ClaimId 'invalid-intent' -Title 'Invalid intent fixture' -Intents @('planning-near-miss'))
    }
    catch {
        $invalidIntentBlocked = $true
    }
    if (-not $invalidIntentBlocked -or $beforeInvalidIntent -cne (Get-TreeFingerprint -RootPath $fixtureRoot)) {
        throw 'Unknown intent не был заблокирован до мутации.'
    }

    $rollbackCandidateId = New-MethodCandidate -ClaimId 'rollback-checklist' -Title 'Rollback checklist'
    [void](Invoke-RepositoryScript -RelativePath 'scripts/update-knowledge-graph.ps1' -Arguments @('-Root', $fixtureRoot, '-Mode', 'Write'))
    $verifyStructurePath = Join-Path $fixtureRoot 'scripts/verify-structure.ps1'
    $verifyStructureSnapshot = [System.IO.File]::ReadAllText($verifyStructurePath)
    Write-FixtureText -Path $verifyStructurePath -Content "[Console]::Error.WriteLine('forced late failure')`nexit 1`n"
    $beforeRollback = Get-TreeFingerprint -RootPath $fixtureRoot
    [void](Invoke-RepositoryScript -RelativePath 'scripts/new-mastery.ps1' -Arguments @(
        '-Root', $fixtureRoot,
        '-CandidateId', $rollbackCandidateId,
        '-AuthorityRef', 'user-request:mastery-v2-rollback'
    ) -ExpectedExitCode 1 -StderrPatterns @('blocked: mastery-apply-rollback'))
    $afterRollback = Get-TreeFingerprint -RootPath $fixtureRoot
    if ($beforeRollback -cne $afterRollback) { throw 'Late apply failure не восстановил pre-apply SHA tree.' }
    $rollbackMethod = Join-Path $fixtureRoot 'mastery/local/rollback-checklist.md'
    if (Test-Path -LiteralPath $rollbackMethod) { throw 'Rollback оставил method artifact.' }
    $rollbackCandidatePath = @(Get-ChildItem -LiteralPath (Join-Path $fixtureRoot 'knowledge/candidates') -Recurse -File -Filter "$rollbackCandidateId.md")[0].FullName
    if ([System.IO.File]::ReadAllText($rollbackCandidatePath) -cnotmatch '(?m)^state: ready\s*$') {
        throw 'Rollback не вернул candidate в ready state.'
    }
    Write-FixtureText -Path $verifyStructurePath -Content $verifyStructureSnapshot
    [void](Invoke-RepositoryScript -RelativePath 'scripts/verify-knowledge.ps1' -Arguments @('-Root', $fixtureRoot))
    [void](Invoke-RepositoryScript -RelativePath 'scripts/update-mastery-index.ps1' -Arguments @('-Root', $fixtureRoot, '-Mode', 'Check'))
    [void](Invoke-RepositoryScript -RelativePath 'scripts/update-knowledge-graph.ps1' -Arguments @('-Root', $fixtureRoot, '-Mode', 'Check'))
    [void](Invoke-RepositoryScript -RelativePath 'scripts/verify-structure.ps1' -Arguments @('-Root', $fixtureRoot, '-Mode', 'GeneratedProject'))

    Write-Host 'PASS: Mastery v2 preview, authority, apply, index, intent and rollback fixtures passed.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
        $full = [System.IO.Path]::GetFullPath($fixtureRoot)
        if (-not $full.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, $tempComparison) -or
            [System.IO.Path]::GetFileName($full) -cnotmatch '^model-project-mastery-v2-[a-f0-9]{32}$') {
            throw 'Unsafe Mastery v2 fixture cleanup target.'
        }
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
