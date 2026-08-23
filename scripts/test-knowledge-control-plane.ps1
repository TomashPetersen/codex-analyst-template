[CmdletBinding()]
param(
    [ValidateSet(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23)]
    [int[]]$CaseId = @(1..23),

    [ValidateRange(2, 10)]
    [int]$RaceRepeats = 2,

    [ValidateSet('', 'GeneratorRace')]
    [string]$WorkerMode = '',

    [string]$WorkerBarrierName = '',
    [string]$WorkerRoot = '',
    [string]$WorkerClaimKey = ''
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sourceRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$powerShellHost = (Get-Process -Id $PID).Path
$verifier = Join-Path $sourceRoot 'scripts\verify-knowledge.ps1'
$newProject = Join-Path $sourceRoot 'scripts\new-project.ps1'
$script:raceBaseRoot = ''
$temporaryRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) ('model-project-hardening-' + [guid]::NewGuid().ToString('N'))))
$expectedPrefix = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]'\/') +
    [System.IO.Path]::DirectorySeparatorChar +
    'model-project-hardening-'

function Write-Utf8Fixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Convert-ToProcessArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value -match '["\r\n]' -or $Value.IndexOf([char]0) -ge 0) {
        throw 'Unsafe child-process argument.'
    }
    if ($Value.Length -eq 0) {
        return '""'
    }
    if ($Value -notmatch '[\s&()^|<>]') {
        return $Value
    }
    return '"' + $Value + '"'
}

function Start-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [hashtable]$EnvironmentVariables = @{},
        [switch]$ClearGitEnvironment
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = (($ArgumentList | ForEach-Object { Convert-ToProcessArgument ([string]$_) }) -join ' ')
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($ClearGitEnvironment -or $EnvironmentVariables.Count -gt 0) {
        # Windows PowerShell 5.1 lazily initializes the environment backing store
        # through the legacy getter; mutation then works through Environment.
        $null = $startInfo.EnvironmentVariables
        $processEnvironment = $startInfo.Environment
        if ($null -eq $processEnvironment) {
            throw 'HARNESS-PROCESS-ENVIRONMENT-UNAVAILABLE'
        }
        if ($ClearGitEnvironment) {
            foreach ($environmentName in @(
                'GIT_DIR',
                'GIT_WORK_TREE',
                'GIT_INDEX_FILE',
                'GIT_COMMON_DIR',
                'GIT_OBJECT_DIRECTORY',
                'GIT_ALTERNATE_OBJECT_DIRECTORIES',
                'GIT_CEILING_DIRECTORIES'
            )) {
                [void]$processEnvironment.Remove($environmentName)
            }
        }
        foreach ($environmentName in @($EnvironmentVariables.Keys)) {
            $environmentValue = $EnvironmentVariables[$environmentName]
            if ($null -eq $environmentValue) {
                [void]$processEnvironment.Remove([string]$environmentName)
            }
            else {
                $processEnvironment[[string]$environmentName] = [string]$environmentValue
            }
        }
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdoutReader = if ($null -eq $process) { $null } else { $process.StandardOutput }
    $stderrReader = if ($null -eq $process) { $null } else { $process.StandardError }
    if ($null -eq $process -or $null -eq $stdoutReader -or $null -eq $stderrReader) {
        if ($null -ne $process) { $process.Dispose() }
        throw 'HARNESS-PROCESS-CAPTURE-UNAVAILABLE'
    }
    $stdoutTask = $stdoutReader.ReadToEndAsync()
    $stderrTask = $stderrReader.ReadToEndAsync()
    return [pscustomobject]@{
        Process = $process
        StdOutTask = $stdoutTask
        StdErrTask = $stderrTask
        Completed = $false
    }
}

function Complete-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)]$Handle,
        [int]$TimeoutMs = 180000
    )

    $timedOut = -not $Handle.Process.WaitForExit($TimeoutMs)
    if ($timedOut) {
        try {
            $Handle.Process.Kill()
        }
        catch {
        }
        [void]$Handle.Process.WaitForExit(10000)
    }
    else {
        $Handle.Process.WaitForExit()
    }

    $exitCode = if ($timedOut) { 124 } else { $Handle.Process.ExitCode }
    $stdout = $Handle.StdOutTask.Result
    $stderr = $Handle.StdErrTask.Result
    $Handle.Completed = $true
    $Handle.Process.Dispose()
    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        StdOut = [string]$stdout
        StdErr = [string]$stderr
        TimedOut = [bool]$timedOut
    }
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [int]$TimeoutMs = 180000,
        [hashtable]$EnvironmentVariables = @{},
        [switch]$ClearGitEnvironment
    )

    $handle = Start-CapturedProcess `
        -FilePath $FilePath `
        -ArgumentList $ArgumentList `
        -WorkingDirectory $WorkingDirectory `
        -EnvironmentVariables $EnvironmentVariables `
        -ClearGitEnvironment:$ClearGitEnvironment
    return Complete-CapturedProcess -Handle $handle -TimeoutMs $TimeoutMs
}

function Invoke-CapturedProcessWithInput {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$StandardInput,
        [int]$TimeoutMs = 180000,
        [switch]$ClearGitEnvironment
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = (($ArgumentList | ForEach-Object { Convert-ToProcessArgument ([string]$_) }) -join ' ')
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($ClearGitEnvironment) {
        $null = $startInfo.EnvironmentVariables
        $processEnvironment = $startInfo.Environment
        if ($null -eq $processEnvironment) {
            throw 'HARNESS-PROCESS-ENVIRONMENT-UNAVAILABLE'
        }
        foreach ($environmentName in @($processEnvironment.Keys)) {
            if ([string]$environmentName -and
                [string]$environmentName.StartsWith('GIT_', [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$processEnvironment.Remove([string]$environmentName)
            }
        }
        $processEnvironment['GIT_CONFIG_NOSYSTEM'] = '1'
        $processEnvironment['GIT_CONFIG_SYSTEM'] = 'NUL'
        $processEnvironment['GIT_CONFIG_GLOBAL'] = 'NUL'
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    if ($null -eq $process -or
        $null -eq $process.StandardInput -or
        $null -eq $process.StandardOutput -or
        $null -eq $process.StandardError) {
        if ($null -ne $process) { $process.Dispose() }
        throw 'HARNESS-PROCESS-CAPTURE-UNAVAILABLE'
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    try {
        $process.StandardInput.Write($StandardInput)
        $process.StandardInput.Close()
        $handle = [pscustomobject]@{
            Process = $process
            StdOutTask = $stdoutTask
            StdErrTask = $stderrTask
            Completed = $false
        }
        return Complete-CapturedProcess -Handle $handle -TimeoutMs $TimeoutMs
    }
    catch {
        try {
            if (-not $process.HasExited) { $process.Kill() }
        }
        catch {
        }
        $process.Dispose()
        throw
    }
}

function Invoke-PublicGenerator {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ClaimKey,
        [ValidateSet('automatic-capture', 'explicit-promotion')]
        [string]$WriteIntent = 'automatic-capture',
        [string]$AuthorityRef = 'policy:knowledge-contract-v1',
        [ValidateSet('repo-derived', 'explicit-user-capture', 'research-derived')]
        [string]$CaptureBasis = 'repo-derived',
        [string]$Title = 'Control plane fixture candidate',
        [hashtable]$EnvironmentVariables = @{}
    )

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Join-Path $Root 'scripts\new-knowledge-candidate.ps1'),
        '-Root',
        $Root,
        '-Type',
        'fact',
        '-Domain',
        'research',
        '-ClaimKey',
        $ClaimKey,
        '-TargetRef',
        'idea/vision.md',
        '-SourceRefs',
        'PROJECT.md',
        '-Confidence',
        'medium',
        '-CaptureBasis',
        $CaptureBasis,
        '-DataClass',
        'internal',
        '-Title',
        $Title,
        '-Basis',
        'A changed PROJECT.md provides isolated fixture evidence.',
        '-ProposedChange',
        'Record the race fixture claim in project canon.',
        '-DuplicateCheck',
        'Compared claim_key and target_ref.',
        '-ReviewDue',
        '2099-12-31',
        '-WriteIntent',
        $WriteIntent,
        '-AuthorityRef',
        $AuthorityRef
    )
    return Invoke-CapturedProcess `
        -FilePath $powerShellHost `
        -ArgumentList $arguments `
        -WorkingDirectory $sourceRoot `
        -EnvironmentVariables $EnvironmentVariables
}

if ($WorkerMode -eq 'GeneratorRace') {
    try {
        if ([string]::IsNullOrWhiteSpace($WorkerBarrierName) -or
            [string]::IsNullOrWhiteSpace($WorkerRoot) -or
            [string]::IsNullOrWhiteSpace($WorkerClaimKey)) {
            throw 'Race worker arguments are incomplete.'
        }
        $barrier = [System.Threading.EventWaitHandle]::OpenExisting($WorkerBarrierName)
        try {
            if (-not $barrier.WaitOne(60000)) {
                [Console]::Error.WriteLine('Race worker barrier timeout.')
                exit 124
            }
        }
        finally {
            $barrier.Dispose()
        }

        $workerResult = Invoke-PublicGenerator -Root $WorkerRoot -ClaimKey $WorkerClaimKey
        if (-not [string]::IsNullOrEmpty($workerResult.StdOut)) {
            [Console]::Out.Write($workerResult.StdOut)
        }
        if (-not [string]::IsNullOrEmpty($workerResult.StdErr)) {
            [Console]::Error.Write($workerResult.StdErr)
        }
        exit $workerResult.ExitCode
    }
    catch {
        [Console]::Error.WriteLine('Race worker failed safely.')
        exit 1
    }
}

function Invoke-PublicVerifier {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [hashtable]$EnvironmentVariables = @{}
    )

    $fixtureVerifier = Join-Path $Root 'scripts\verify-knowledge.ps1'
    $result = Invoke-CapturedProcess `
        -FilePath $powerShellHost `
        -ArgumentList @(
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $fixtureVerifier,
            '-Root',
            $Root
        ) `
        -WorkingDirectory $sourceRoot `
        -EnvironmentVariables $EnvironmentVariables
    return [pscustomobject]@{
        ExitCode = $result.ExitCode
        Output = ([string]$result.StdOut) + ([string]$result.StdErr)
        StdOut = [string]$result.StdOut
        StdErr = [string]$result.StdErr
        TimedOut = [bool]$result.TimedOut
    }
}

function Assert-Blocked {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$SafePattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Result.TimedOut) {
        throw "RED: $Name - public verifier timed out."
    }
    if ($Result.ExitCode -eq 0) {
        throw "RED: $Name - public verifier returned exit code 0."
    }
    if ($Result.Output -notmatch $SafePattern) {
        throw "FAIL: $Name - safe diagnostic pattern was not found."
    }
    Write-Host "PASS: $Name"
}

function Assert-Success {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Result.TimedOut -or $Result.ExitCode -ne 0) {
        throw "RED: $Name - public process did not complete successfully."
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.StdErr)) {
        throw "RED: $Name - successful public process wrote to stderr."
    }
    Write-Host "PASS: $Name"
}

function Get-CandidateFiles {
    param([Parameter(Mandatory = $true)][string]$Root)

    $candidateRoot = Join-Path $Root 'knowledge\candidates'
    if (-not (Test-Path -LiteralPath $candidateRoot -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $candidateRoot -Recurse -File -Filter 'KC-*.md' -Force)
}

function Assert-NoCandidateMutation {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][int]$ExpectedCount,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $candidateFiles = @(Get-CandidateFiles -Root $Root)
    if ($candidateFiles.Count -ne $ExpectedCount) {
        throw "RED: $Name - candidate post-state changed unexpectedly."
    }
    $artifacts = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Where-Object {
        $_.Name -match '(?i)(?:\.tmp$|\.lock$|^\.candidate-)'
    })
    if ($artifacts.Count -ne 0) {
        throw "RED: $Name - temporary or lock artifacts remain."
    }
}

function Assert-GeneratorBlocked {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][int]$ExpectedCandidateCount,
        [Parameter(Mandatory = $true)][string]$SafePattern,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Result.TimedOut) {
        throw "RED: $Name - public generator timed out."
    }
    if ($Result.ExitCode -eq 0) {
        throw "RED: $Name - public generator returned exit code 0."
    }
    $combined = ([string]$Result.StdOut) + ([string]$Result.StdErr)
    if ($combined -notmatch $SafePattern) {
        throw "RED: $Name - controlled safe diagnostic was not returned."
    }
    Assert-NoCandidateMutation -Root $Root -ExpectedCount $ExpectedCandidateCount -Name $Name
    Write-Host "PASS: $Name"
}

function Assert-GeneratorReady {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][int]$ExpectedCandidateCount,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Result.TimedOut -or $Result.ExitCode -ne 0) {
        throw "RED: $Name - public generator did not complete successfully."
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Result.StdErr)) {
        throw "RED: $Name - successful public generator wrote to stderr."
    }
    $outcome = Get-RaceOutcome -StdOut ([string]$Result.StdOut)
    if ($null -eq $outcome -or $outcome.Outcome -cne 'READY') {
        throw "RED: $Name - public generator did not return exactly one controlled READY outcome."
    }
    Assert-NoCandidateMutation -Root $Root -ExpectedCount $ExpectedCandidateCount -Name $Name
    Write-Host "PASS: $Name"
    return $outcome
}

function Move-FixtureGitDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $gitDirectory = [System.IO.Path]::GetFullPath((Join-Path $Root '.git'))
    $destinationPath = [System.IO.Path]::GetFullPath($Destination)
    $temporaryPrefix = $temporaryRoot.TrimEnd([char[]]'\/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $gitDirectory.StartsWith($temporaryPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not $destinationPath.StartsWith($temporaryPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $gitDirectory -PathType Container) -or
        (Test-Path -LiteralPath $destinationPath)) {
        throw 'Refusing unsafe fixture Git metadata move.'
    }
    [System.IO.Directory]::Move($gitDirectory, $destinationPath)
    if ((Test-Path -LiteralPath $gitDirectory) -or
        -not (Test-Path -LiteralPath $destinationPath -PathType Container)) {
        throw 'Fixture Git metadata move did not reach the expected post-state.'
    }
    return $destinationPath
}

function Complete-FixturePromotionChangeSet {
    param([Parameter(Mandatory = $true)][string]$Root)

    $candidateFiles = @(Get-CandidateFiles -Root $Root)
    if ($candidateFiles.Count -ne 1) {
        throw 'A10 promotion fixture requires exactly one candidate.'
    }
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    $candidatePath = [System.IO.Path]::GetFullPath($candidateFiles[0].FullName)
    if (-not $candidatePath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing unsafe A10 candidate mutation.'
    }
    $relativeCandidate = $candidatePath.Substring($prefix.Length).Replace('\', '/')
    $candidateText = [System.IO.File]::ReadAllText($candidatePath)
    $createdMatch = [regex]::Match($candidateText, '(?m)^created_at:\s*["'']?(?<value>[^"''\r\n]+)["'']?\s*$')
    if (-not $createdMatch.Success) {
        throw 'A10 candidate created_at is unavailable.'
    }
    $createdAt = [System.DateTimeOffset]::MinValue
    if (-not [System.DateTimeOffset]::TryParse(
        $createdMatch.Groups['value'].Value,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$createdAt
    )) {
        throw 'A10 candidate created_at is invalid.'
    }
    $appliedAt = $createdAt.AddMinutes(1).ToString('yyyy-MM-ddTHH:mm:ssK')
    $candidateText = [regex]::Replace($candidateText, '(?m)^state:\s*ready\s*$', 'state: applied', 1)
    $candidateText = [regex]::Replace(
        $candidateText,
        '(?m)^applied_at:\s*null\s*$',
        "applied_at: '$appliedAt'",
        1
    )
    if ($candidateText -cnotmatch '(?m)^state: applied$' -or
        $candidateText -cnotmatch '(?m)^applied_at: ''[^'']+''$') {
        throw 'A10 candidate lifecycle mutation was incomplete.'
    }
    Write-Utf8Fixture -Path $candidatePath -Content $candidateText

    $targetPath = [System.IO.Path]::GetFullPath((Join-Path $Root 'idea\vision.md'))
    if (-not $targetPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        throw 'Refusing unsafe A10 target mutation.'
    }
    $targetText = [System.IO.File]::ReadAllText($targetPath).TrimEnd()
    $backlink = "../$relativeCandidate"
    $targetText += "`n`n## Knowledge history`n`n- [Applied candidate]($backlink)`n"
    Write-Utf8Fixture -Path $targetPath -Content $targetText
}

function New-TemplateFixtureRoot {
    param([Parameter(Mandatory = $true)][string]$Name)

    $fixtureRoot = Join-Path $temporaryRoot $Name
    [System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $sourceRoot -Force)) {
        if ($item.Name -ceq '.git') { continue }
        Copy-Item -LiteralPath $item.FullName -Destination $fixtureRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath (Join-Path $fixtureRoot '.git')) {
        throw 'Template fixture unexpectedly contains Git metadata.'
    }
    return $fixtureRoot
}

function New-PortableTemplateFixtureRoot {
    param([Parameter(Mandatory = $true)][string]$Name)

    $fixtureRoot = Join-Path $temporaryRoot $Name
    [System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    $manifest = [System.IO.File]::ReadAllText((Join-Path $sourceRoot '.template-manifest.json')) |
        ConvertFrom-Json
    foreach ($relativePath in @($manifest.portable_files | ForEach-Object { [string]$_ })) {
        $sourcePath = Join-Path $sourceRoot $relativePath.Replace('/', '\')
        $targetPath = Join-Path $fixtureRoot $relativePath.Replace('/', '\')
        $targetParent = [System.IO.Path]::GetDirectoryName($targetPath)
        [System.IO.Directory]::CreateDirectory($targetParent) | Out-Null
        [System.IO.File]::Copy($sourcePath, $targetPath, $false)
    }
    foreach ($relativePath in @($manifest.portable_empty_directories | ForEach-Object { [string]$_ })) {
        [System.IO.Directory]::CreateDirectory(
            (Join-Path $fixtureRoot $relativePath.Replace('/', '\'))
        ) | Out-Null
    }
    if (Test-Path -LiteralPath (Join-Path $fixtureRoot '.git')) {
        throw 'Portable template fixture unexpectedly contains Git metadata.'
    }
    return $fixtureRoot
}

function New-GeneratedFixtureRoot {
    param([Parameter(Mandatory = $true)][string]$Name)

    $fixtureRoot = Join-Path $temporaryRoot $Name
    $result = Invoke-CapturedProcess `
        -FilePath $powerShellHost `
        -ArgumentList @(
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $newProject,
            '-Destination',
            $fixtureRoot,
            '-ProjectName',
            'Control plane fixture',
            '-ProjectSlug',
            'control-plane-fixture',
            '-Description',
            'Temporary generated project for control plane acceptance tests.',
            '-Owner',
            'fixture-owner'
        ) `
        -WorkingDirectory $sourceRoot `
        -TimeoutMs 300000
    if ($result.TimedOut -or $result.ExitCode -ne 0) {
        throw 'RED: public new-project entrypoint failed while creating the generated fixture.'
    }
    if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) {
        throw 'RED: public new-project entrypoint wrote to stderr on success.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'PROJECT.md') -PathType Leaf)) {
        throw 'RED: public new-project entrypoint did not create PROJECT.md.'
    }
    return $fixtureRoot
}

function Invoke-PublicNewProject {
    param(
        [Parameter(Mandatory = $true)][string]$Destination,
        [hashtable]$EnvironmentVariables = @{}
    )

    return Invoke-CapturedProcess `
        -FilePath $powerShellHost `
        -ArgumentList @(
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $newProject,
            '-Destination',
            $Destination,
            '-ProjectName',
            'Security isolation fixture',
            '-ProjectSlug',
            'security-isolation-fixture',
            '-Description',
            'Temporary generated project for inherited Git environment testing.',
            '-Owner',
            'fixture-owner'
        ) `
        -WorkingDirectory $sourceRoot `
        -TimeoutMs 300000 `
        -EnvironmentVariables $EnvironmentVariables
}

function Invoke-PublicInitializer {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [hashtable]$EnvironmentVariables = @{}
    )

    return Invoke-CapturedProcess `
        -FilePath $powerShellHost `
        -ArgumentList @(
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            (Join-Path $Root 'scripts\initialize-project.ps1'),
            '-ProjectName',
            'Initializer rollback fixture',
            '-ProjectSlug',
            'initializer-rollback-fixture',
            '-Description',
            'Temporary direct initializer rollback and retry fixture.',
            '-Owner',
            'fixture-owner',
            '-InitializeGit'
        ) `
        -WorkingDirectory $Root `
        -TimeoutMs 300000 `
        -EnvironmentVariables $EnvironmentVariables
}

function Copy-GeneratedFixtureRoot {
    param(
        [Parameter(Mandatory = $true)][string]$BaseRoot,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $fixtureRoot = Join-Path $temporaryRoot $Name
    Copy-Item -LiteralPath $BaseRoot -Destination $fixtureRoot -Recurse -Force
    if (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'PROJECT.md') -PathType Leaf)) {
        throw 'Generated fixture copy is incomplete.'
    }
    return $fixtureRoot
}

function Get-ValidGeneratedProjectText {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('active', 'archived')][string]$Status,
        [Parameter(Mandatory = $true)][ValidateSet('report-only', 'safe-local', 'disabled')][string]$CaptureMode,
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$Slug
    )

    $template = @'
---
repository_kind: generated-project
project_status: {0}
project_id: "{1}"
knowledge_contract_version: 1
knowledge_capture_mode: {2}
---

# Control plane fixture

## Паспорт

- Slug: `{3}`
- Описание: Изолированная проверка режимов knowledge control plane.
- Владелец: `fixture-owner`
- Стадия: исследование
- Канонический репозиторий: этот репозиторий
- Дата последней проверки паспорта: `2026-08-01`

## Проблема

Некорректный переход режима может разрешить недопустимую запись knowledge.

## Проверяемая гипотеза

Public verifier и generator применяют один закрытый контракт режимов.

## Границы

Входит:

- Проверка текущего режима во временном generated project.

Не входит:

- Изменение исходного template repository.

## Критерии успеха и провала

- Успех: ожидаемый public process завершает или блокирует fixture предсказуемо.
- Провал: exit code или файловое post-state расходятся с контрактом.
- Срок или объем проверки: один изолированный acceptance case.
- Кто принимает финальное решение: fixture-owner.

## Стек и эксплуатация

- Стек: PowerShell public CLI.

## Связи

- [Карта](INDEX.md)
'@
    return $template -f $Status, $ProjectId, $CaptureMode, $Slug
}

function Set-ValidGeneratedProjectMode {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][ValidateSet('active', 'archived')][string]$Status,
        [Parameter(Mandatory = $true)][ValidateSet('report-only', 'safe-local', 'disabled')][string]$CaptureMode,
        [Parameter(Mandatory = $true)][string]$ProjectId,
        [Parameter(Mandatory = $true)][string]$Slug
    )

    $content = Get-ValidGeneratedProjectText `
        -Status $Status `
        -CaptureMode $CaptureMode `
        -ProjectId $ProjectId `
        -Slug $Slug
    Write-Utf8Fixture -Path (Join-Path $Root 'PROJECT.md') -Content ($content.Trim() + "`n")
    $originPath = Join-Path $Root 'TEMPLATE-ORIGIN.md'
    if (-not (Test-Path -LiteralPath $originPath -PathType Leaf)) {
        throw 'Generated fixture does not contain TEMPLATE-ORIGIN.md.'
    }
    $origin = [System.IO.File]::ReadAllText($originPath)
    if ($origin -cnotmatch '(?m)^- Project ID: [0-9a-fA-F-]+\s*$') {
        throw 'Generated fixture origin does not contain Project ID.'
    }
    $origin = [regex]::Replace(
        $origin,
        '(?m)^- Project ID: [0-9a-fA-F-]+\s*$',
        "- Project ID: $ProjectId"
    )
    Write-Utf8Fixture -Path $originPath -Content ($origin.Trim() + "`n")
}

function Invoke-FixtureGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $gitArguments = @(
        '-c', 'core.hooksPath=NUL',
        '-c', 'core.autocrlf=false',
        '-c', 'core.quotepath=false',
        '-c', 'user.name=Fixture',
        '-c', 'user.email=fixture@example.invalid',
        '-C', $Root
    ) + $Arguments
    return Invoke-CapturedProcess `
        -FilePath 'git.exe' `
        -ArgumentList $gitArguments `
        -WorkingDirectory $Root `
        -ClearGitEnvironment
}

function Assert-FixtureGitSuccess {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    if ($Result.TimedOut -or $Result.ExitCode -ne 0) {
        throw "Fixture Git operation failed: $Operation."
    }
}

function Get-FixtureRelativeFiles {
    param([Parameter(Mandatory = $true)][string]$Root)

    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    $items = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($topLevel in @(Get-ChildItem -LiteralPath $fullRoot -Force)) {
        if ($topLevel.Name -ceq '.git') { continue }
        if ($topLevel.PSIsContainer) {
            foreach ($file in @(Get-ChildItem -LiteralPath $topLevel.FullName -Recurse -File -Force)) {
                $items.Add($file)
            }
        }
        else {
            $items.Add($topLevel)
        }
    }

    return @($items | ForEach-Object {
        $full = [System.IO.Path]::GetFullPath($_.FullName)
        if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Fixture file escaped the expected root.'
        }
        $relative = $full.Substring($prefix.Length).Replace('\', '/')
        if ($relative -match '(^|/)\.\.(/|$)' -or $relative -match '[\r\n\x00]') {
            throw 'Fixture file has an unsafe relative path.'
        }
        $relative
    } | Sort-Object -Unique)
}

function Add-FixtureGitPaths {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths
    )

    $paths = @($RelativePaths | Sort-Object -Unique)
    for ($offset = 0; $offset -lt $paths.Count; $offset += 24) {
        $last = [Math]::Min($offset + 23, $paths.Count - 1)
        $chunk = @($paths[$offset..$last])
        $result = Invoke-FixtureGit -Root $Root -Arguments (@('add', '--') + $chunk)
        Assert-FixtureGitSuccess -Result $result -Operation 'add explicit fixture paths'
    }
}

function New-FixtureBaselineCommit {
    param([Parameter(Mandatory = $true)][string]$Root)

    $files = @(Get-FixtureRelativeFiles -Root $Root)
    if ($files.Count -eq 0) { throw 'Fixture baseline contains no files.' }
    Add-FixtureGitPaths -Root $Root -RelativePaths $files
    $commit = Invoke-FixtureGit -Root $Root -Arguments @('commit', '-m', 'fixture baseline')
    Assert-FixtureGitSuccess -Result $commit -Operation 'baseline commit'
}

function Add-OversizedCandidateTreeCommit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][ValidateRange(10001, 20000)][int]$EntryCount,
        [Parameter(Mandatory = $true)][string]$Sentinel
    )

    if ($Sentinel -match '[\r\n\x00]' -or [string]::IsNullOrWhiteSpace($Sentinel)) {
        throw 'Unsafe bounded-tree fixture sentinel.'
    }
    $headResult = Invoke-FixtureGit -Root $Root -Arguments @('rev-parse', '--verify', 'HEAD^{commit}')
    Assert-FixtureGitSuccess -Result $headResult -Operation 'resolve bounded-tree parent commit'
    $headCommit = $headResult.StdOut.Trim()
    if ($headCommit -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        throw 'Bounded-tree fixture returned an invalid parent object ID.'
    }
    $headRefResult = Invoke-FixtureGit -Root $Root -Arguments @('symbolic-ref', '--quiet', 'HEAD')
    Assert-FixtureGitSuccess -Result $headRefResult -Operation 'resolve bounded-tree current branch'
    $headRef = $headRefResult.StdOut.Trim()
    if ($headRef -cnotmatch '^refs/heads/[A-Za-z0-9][A-Za-z0-9._/-]*$' -or
        $headRef.Contains('..') -or
        $headRef.EndsWith('/') -or
        $headRef.Contains('//')) {
        throw 'Bounded-tree fixture returned an unsafe branch ref.'
    }

    $blobContent = "$Sentinel`n"
    $commitMessage = "bounded Git HEAD tree inventory fixture`n"
    $builder = [System.Text.StringBuilder]::new(1600000)
    [void]$builder.Append("blob`nmark :1`ndata $($utf8NoBom.GetByteCount($blobContent))`n")
    [void]$builder.Append($blobContent)
    [void]$builder.Append("commit $headRef`nmark :2`n")
    [void]$builder.Append("author Fixture <fixture@example.invalid> 1785542400 +0000`n")
    [void]$builder.Append("committer Fixture <fixture@example.invalid> 1785542400 +0000`n")
    [void]$builder.Append("data $($utf8NoBom.GetByteCount($commitMessage))`n")
    [void]$builder.Append($commitMessage)
    [void]$builder.Append("from $headCommit`n")
    for ($index = 0; $index -lt $EntryCount; $index++) {
        $suffix = $index.ToString('x8', [System.Globalization.CultureInfo]::InvariantCulture)
        [void]$builder.Append(
            "M 100644 :1 knowledge/candidates/2099/KC-20990101-000000-$suffix.md`n"
        )
    }
    [void]$builder.Append("done`n")

    $gitArguments = @(
        '-c', 'core.fsmonitor=false',
        '-c', 'core.hooksPath=NUL',
        '-c', 'core.quotePath=false',
        '-C', $Root,
        'fast-import',
        '--quiet',
        '--done'
    )
    $importResult = Invoke-CapturedProcessWithInput `
        -FilePath 'git.exe' `
        -ArgumentList $gitArguments `
        -WorkingDirectory $sourceRoot `
        -StandardInput $builder.ToString() `
        -TimeoutMs 180000 `
        -ClearGitEnvironment
    Assert-FixtureGitSuccess -Result $importResult -Operation 'create bounded Git HEAD tree without worktree files'

    $lastSuffix = ($EntryCount - 1).ToString('x8', [System.Globalization.CultureInfo]::InvariantCulture)
    $lastPath = "HEAD:knowledge/candidates/2099/KC-20990101-000000-$lastSuffix.md"
    $lastEntry = Invoke-FixtureGit -Root $Root -Arguments @('cat-file', '-e', $lastPath)
    Assert-FixtureGitSuccess -Result $lastEntry -Operation 'verify final bounded-tree entry'
}

function New-ForeignGitRepository {
    param([Parameter(Mandatory = $true)][string]$Name)

    $root = [System.IO.Path]::GetFullPath((Join-Path $temporaryRoot $Name))
    [System.IO.Directory]::CreateDirectory($root) | Out-Null
    Write-Utf8Fixture -Path (Join-Path $root 'foreign.txt') -Content "foreign repository sentinel`n"
    $init = Invoke-CapturedProcess `
        -FilePath 'git.exe' `
        -ArgumentList @('init', '-b', 'main', $root) `
        -WorkingDirectory $temporaryRoot `
        -ClearGitEnvironment
    Assert-FixtureGitSuccess -Result $init -Operation 'initialize foreign fixture repository'
    New-FixtureBaselineCommit -Root $root
    return $root
}

function Get-ForeignGitEnvironment {
    param([Parameter(Mandatory = $true)][string]$Root)

    return @{
        GIT_DIR = [System.IO.Path]::GetFullPath((Join-Path $Root '.git'))
        GIT_WORK_TREE = [System.IO.Path]::GetFullPath($Root)
        GIT_INDEX_FILE = [System.IO.Path]::GetFullPath((Join-Path $Root '.git\index'))
    }
}

function Get-DirectoryFingerprint {
    param([Parameter(Mandatory = $true)][string]$Root)

    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    $lines = @(
        Get-ChildItem -LiteralPath $fullRoot -Recurse -File -Force |
            ForEach-Object {
                $fullPath = [System.IO.Path]::GetFullPath($_.FullName)
                if (-not $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw 'Foreign repository fingerprint escaped the expected root.'
                }
                $relativePath = $fullPath.Substring($prefix.Length).Replace('\', '/')
                $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
                '{0}|{1}|{2}' -f $relativePath, $_.Length, $hash
            } |
            Sort-Object -CaseSensitive
    )
    return $lines -join "`n"
}

function Assert-ForeignRepositoryUnchanged {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Before,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $after = Get-DirectoryFingerprint -Root $Root
    if ($after -cne $Before) {
        throw "RED: $Name - inherited Git environment mutated the foreign repository."
    }
}

function Assert-SafePublicFailure {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$ForbiddenText = @(),
        [string]$RequiredPattern = ''
    )

    if ($Result.TimedOut) {
        throw "RED: $Name - public entrypoint timed out."
    }
    if ($Result.ExitCode -eq 0) {
        throw "RED: $Name - public entrypoint returned exit code 0."
    }
    $output = ([string]$Result.StdOut) + ([string]$Result.StdErr)
    if ([string]::IsNullOrWhiteSpace($output) -or $output -notmatch '(?im)^(?:FAIL:|ERROR:|blocked:)') {
        throw "RED: $Name - controlled public diagnostic was not returned."
    }
    if (-not [string]::IsNullOrWhiteSpace($RequiredPattern) -and $output -notmatch $RequiredPattern) {
        throw "RED: $Name - expected controlled failure reason was not returned."
    }
    foreach ($forbidden in @($ForbiddenText)) {
        if (-not [string]::IsNullOrEmpty($forbidden) -and
            $output.IndexOf($forbidden, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "RED: $Name - public diagnostic exposed forbidden fixture data."
        }
    }
    Write-Host "PASS: $Name"
}

function Get-FileBytesFingerprint {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
}

function Assert-NoInitializerArtifacts {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $artifacts = @(
        Get-ChildItem -LiteralPath $Root -Recurse -Force |
            Where-Object { $_.Name -match '^\.codex-(?:init|rollback)-[0-9a-f]{32}\.(?:tmp|bak)$' }
    )
    if ($artifacts.Count -ne 0) {
        throw "RED: $Name - initializer temporary or backup artifacts remain."
    }
}

function Assert-NoNewProjectStagingArtifacts {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $artifacts = @(
        Get-ChildItem -LiteralPath $Parent -Force -Directory |
            Where-Object { $_.Name -match '^\.codex-new-project-[0-9a-f]{32}$' }
    )
    if ($artifacts.Count -ne 0) {
        throw "RED: $Name - new-project staging artifacts remain."
    }
}

function Assert-ZeroCommitGeneratedProject {
    param([Parameter(Mandatory = $true)][string]$Root)

    $inside = Invoke-FixtureGit -Root $Root -Arguments @('rev-parse', '--is-inside-work-tree')
    Assert-FixtureGitSuccess -Result $inside -Operation 'generated project Git detection'
    if ($inside.StdOut.Trim() -cne 'true') {
        throw 'RED: A02 generated project is not a Git worktree.'
    }

    $head = Invoke-FixtureGit -Root $Root -Arguments @('rev-parse', '--verify', 'HEAD')
    if ($head.TimedOut -or $head.ExitCode -eq 0) {
        throw 'RED: A02 fresh generated project unexpectedly has HEAD.'
    }
    $all = Invoke-FixtureGit -Root $Root -Arguments @('rev-list', '--count', '--all')
    Assert-FixtureGitSuccess -Result $all -Operation 'count generated project commits'
    if ($all.StdOut.Trim() -cne '0') {
        throw 'RED: A02 fresh generated project does not have zero commits.'
    }
}

function Assert-InitializedReportOnlyProject {
    param([Parameter(Mandatory = $true)][string]$Root)

    $project = [System.IO.File]::ReadAllText((Join-Path $Root 'PROJECT.md'))
    foreach ($line in @(
        'repository_kind: generated-project',
        'project_status: initialized',
        'knowledge_capture_mode: report-only'
    )) {
        if ($project -cnotmatch ('(?m)^' + [regex]::Escape($line) + '$')) {
            throw 'RED: A02 fresh copy does not use initialized + report-only mode.'
        }
    }
}

function Get-FixtureIndexHash {
    param([Parameter(Mandatory = $true)][string]$Root)

    $indexPath = Join-Path $Root '.git\index'
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        throw 'Fixture Git index is missing.'
    }
    return (Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash
}

function Get-CuratorSnapshotOracle {
    param([Parameter(Mandatory = $true)][string]$Root)

    $beforeIndexHash = Get-FixtureIndexHash -Root $Root
    $status = Invoke-FixtureGit -Root $Root -Arguments @('status', '--porcelain=v1', '-z')
    $unstaged = Invoke-FixtureGit -Root $Root -Arguments @('diff', 'HEAD')
    $staged = Invoke-FixtureGit -Root $Root -Arguments @('diff', '--cached')
    $untracked = Invoke-FixtureGit -Root $Root -Arguments @('ls-files', '--others', '--exclude-standard')
    foreach ($entry in @(
        @{ Result = $status; Name = 'status snapshot' },
        @{ Result = $unstaged; Name = 'unstaged diff snapshot' },
        @{ Result = $staged; Name = 'staged diff snapshot' },
        @{ Result = $untracked; Name = 'untracked snapshot' }
    )) {
        Assert-FixtureGitSuccess -Result $entry.Result -Operation $entry.Name
    }
    $afterIndexHash = Get-FixtureIndexHash -Root $Root
    return [pscustomobject]@{
        Status = [string]$status.StdOut
        UnstagedDiff = [string]$unstaged.StdOut
        StagedDiff = [string]$staged.StdOut
        Untracked = [string]$untracked.StdOut
        IndexStable = $beforeIndexHash -ceq $afterIndexHash
    }
}

function Convert-FromPorcelainV1Z {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $parts = @($Text.Split([char]0) | Where-Object { $_.Length -gt 0 })
    $records = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $parts.Count; $index++) {
        $record = [string]$parts[$index]
        if ($record.Length -lt 4) { throw 'Malformed porcelain fixture record.' }
        $xy = $record.Substring(0, 2)
        $path = $record.Substring(3)
        $originalPath = ''
        if ($xy.Substring(0, 1) -cin @('R', 'C')) {
            if (($index + 1) -ge $parts.Count) { throw 'Malformed porcelain rename fixture record.' }
            $index++
            $originalPath = [string]$parts[$index]
        }
        $records.Add([pscustomobject]@{
            XY = $xy
            Path = $path
            OriginalPath = $originalPath
        })
    }
    return @($records)
}

function Assert-CuratorDiffOracle {
    param([Parameter(Mandatory = $true)][string]$Root)

    $fixtureDirectory = Join-Path $Root 'fixture-diff'
    [System.IO.Directory]::CreateDirectory($fixtureDirectory) | Out-Null
    $baselineFiles = @(
        'preexisting.md',
        'unstaged.md',
        'staged.md',
        'deleted.md',
        'rename-old.md'
    )
    foreach ($name in $baselineFiles) {
        Write-Utf8Fixture -Path (Join-Path $fixtureDirectory $name) -Content "baseline $name`n"
    }
    Add-FixtureGitPaths -Root $Root -RelativePaths @($baselineFiles | ForEach-Object { "fixture-diff/$_" })
    $fixtureCommit = Invoke-FixtureGit -Root $Root -Arguments @('commit', '-m', 'diff oracle baseline')
    Assert-FixtureGitSuccess -Result $fixtureCommit -Operation 'diff oracle baseline commit'

    Write-Utf8Fixture `
        -Path (Join-Path $fixtureDirectory 'preexisting.md') `
        -Content "baseline preexisting.md`npre-task dirty line`n"
    $preTask = Get-CuratorSnapshotOracle -Root $Root
    if (-not $preTask.IndexStable) {
        throw 'RED: A07 pre-task snapshot changed the Git index.'
    }
    $preRecords = @(Convert-FromPorcelainV1Z -Text $preTask.Status)
    if ($preRecords.Count -ne 1 -or
        $preRecords[0].XY -cne ' M' -or
        $preRecords[0].Path -cne 'fixture-diff/preexisting.md') {
        throw 'RED: A07 pre-existing dirty state was not isolated before task changes.'
    }

    Write-Utf8Fixture `
        -Path (Join-Path $fixtureDirectory 'unstaged.md') `
        -Content "baseline unstaged.md`ntracked unstaged line`n"
    Write-Utf8Fixture `
        -Path (Join-Path $fixtureDirectory 'staged.md') `
        -Content "baseline staged.md`nstaged line`n"
    Write-Utf8Fixture `
        -Path (Join-Path $fixtureDirectory 'untracked.md') `
        -Content "new untracked path`n"

    $deletedPath = [System.IO.Path]::GetFullPath((Join-Path $fixtureDirectory 'deleted.md'))
    $renamedFrom = [System.IO.Path]::GetFullPath((Join-Path $fixtureDirectory 'rename-old.md'))
    $renamedTo = [System.IO.Path]::GetFullPath((Join-Path $fixtureDirectory 'rename-new.md'))
    $fixturePrefix = [System.IO.Path]::GetFullPath($fixtureDirectory).TrimEnd([char[]]'\/') +
        [System.IO.Path]::DirectorySeparatorChar
    foreach ($path in @($deletedPath, $renamedFrom, $renamedTo)) {
        if (-not $path.StartsWith($fixturePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing unsafe diff fixture mutation.'
        }
    }
    Remove-Item -LiteralPath $deletedPath -Force
    Move-Item -LiteralPath $renamedFrom -Destination $renamedTo
    Add-FixtureGitPaths -Root $Root -RelativePaths @(
        'fixture-diff/staged.md',
        'fixture-diff/rename-old.md',
        'fixture-diff/rename-new.md'
    )

    $postTask = Get-CuratorSnapshotOracle -Root $Root
    if (-not $postTask.IndexStable) {
        throw 'RED: A07 post-task snapshot changed the Git index.'
    }
    $postRecords = @(Convert-FromPorcelainV1Z -Text $postTask.Status)
    $hasPreexisting = @($postRecords | Where-Object {
        $_.XY -ceq ' M' -and $_.Path -ceq 'fixture-diff/preexisting.md'
    }).Count -eq 1
    $hasUnstaged = @($postRecords | Where-Object {
        $_.XY -ceq ' M' -and $_.Path -ceq 'fixture-diff/unstaged.md'
    }).Count -eq 1
    $hasStaged = @($postRecords | Where-Object {
        $_.XY -ceq 'M ' -and $_.Path -ceq 'fixture-diff/staged.md'
    }).Count -eq 1
    $hasUntracked = @($postRecords | Where-Object {
        $_.XY -ceq '??' -and $_.Path -ceq 'fixture-diff/untracked.md'
    }).Count -eq 1
    $hasDeleted = @($postRecords | Where-Object {
        $_.XY -ceq ' D' -and $_.Path -ceq 'fixture-diff/deleted.md'
    }).Count -eq 1
    $hasRename = @($postRecords | Where-Object {
        $_.XY -ceq 'R ' -and
        @($_.Path, $_.OriginalPath) -ccontains 'fixture-diff/rename-old.md' -and
        @($_.Path, $_.OriginalPath) -ccontains 'fixture-diff/rename-new.md'
    }).Count -eq 1
    if (-not ($hasPreexisting -and $hasUnstaged -and $hasStaged -and $hasUntracked -and $hasDeleted -and $hasRename)) {
        throw 'RED: A07 Git oracle did not expose every required diff category.'
    }
    if (($postTask.Untracked -split '\r?\n') -cnotcontains 'fixture-diff/untracked.md') {
        throw 'RED: A07 explicit untracked snapshot did not include the untracked path.'
    }

    Write-Host 'PASS: A07 agent-process Git oracle sees tracked unstaged, staged, untracked, deleted, rename and preserves index'
}

function Assert-MissingDiffBaselineAgentContract {
    param([Parameter(Mandatory = $true)][string]$Root)

    $skillPath = Join-Path $Root '.agents\skills\knowledge-curator\SKILL.md'
    $skillText = [System.IO.File]::ReadAllText($skillPath, [System.Text.Encoding]::UTF8)
    foreach ($requiredText in @(
        'git status --porcelain=v1 -z',
        'git diff HEAD',
        'git diff --cached',
        'git ls-files --others --exclude-standard',
        'blocked: missing-diff-baseline'
    )) {
        if (-not $skillText.Contains($requiredText)) {
            throw 'RED: A08 knowledge-curator agent contract is incomplete.'
        }
    }
    if (@(Get-CandidateFiles -Root $Root).Count -ne 0) {
        throw 'RED: A08 contract fixture unexpectedly contains a candidate.'
    }
    Write-Host 'PASS: A08 agent-only curator contract maps missing snapshot to blocked: missing-diff-baseline (no executable curator entrypoint)'
}

function New-RaceFixtureRoot {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ([string]::IsNullOrWhiteSpace($script:raceBaseRoot) -or
        -not (Test-Path -LiteralPath $script:raceBaseRoot -PathType Container)) {
        throw 'Race fixture base is unavailable.'
    }
    $fixtureRoot = Copy-GeneratedFixtureRoot -BaseRoot $script:raceBaseRoot -Name $Name
    Set-ValidGeneratedProjectMode `
        -Root $fixtureRoot `
        -Status active `
        -CaptureMode safe-local `
        -ProjectId ('33333333' + '-3333-4333-8333-' + '333333333333') `
        -Slug 'generator-race-fixture'
    return $fixtureRoot
}

function Invoke-BarrierRace {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$ClaimKeys
    )

    $barrierName = 'Local\ModelProjectGeneratorRace-' + [guid]::NewGuid().ToString('N')
    $createdNew = $false
    $barrier = [System.Threading.EventWaitHandle]::new(
        $false,
        [System.Threading.EventResetMode]::ManualReset,
        $barrierName,
        [ref]$createdNew
    )
    if (-not $createdNew) {
        $barrier.Dispose()
        throw 'Race fixture barrier collision.'
    }

    $handles = [System.Collections.Generic.List[object]]::new()
    $results = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($claimKey in $ClaimKeys) {
            $arguments = @(
                '-NoLogo',
                '-NoProfile',
                '-NonInteractive',
                '-ExecutionPolicy',
                'Bypass',
                '-File',
                $PSCommandPath,
                '-WorkerMode',
                'GeneratorRace',
                '-WorkerBarrierName',
                $barrierName,
                '-WorkerRoot',
                $Root,
                '-WorkerClaimKey',
                $claimKey
            )
            $handles.Add((Start-CapturedProcess -FilePath $powerShellHost -ArgumentList $arguments -WorkingDirectory $Root)) | Out-Null
        }
        [void]$barrier.Set()
        foreach ($handle in $handles) {
            $results.Add((Complete-CapturedProcess -Handle $handle)) | Out-Null
        }
    }
    finally {
        [void]$barrier.Set()
        foreach ($handle in $handles) {
            if (-not $handle.Completed) {
                try {
                    [void](Complete-CapturedProcess -Handle $handle -TimeoutMs 10000)
                }
                catch {
                }
            }
        }
        $barrier.Dispose()
    }
    return @($results)
}

function Invoke-RaceVerifier {
    param([Parameter(Mandatory = $true)][string]$Root)

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        (Join-Path $Root 'scripts\verify-knowledge.ps1'),
        '-Root',
        $Root
    )
    $result = Invoke-CapturedProcess `
        -FilePath $powerShellHost `
        -ArgumentList $arguments `
        -WorkingDirectory $Root
    return [pscustomobject]@{
        ExitCode = $result.ExitCode
        Output = ([string]$result.StdOut) + ([string]$result.StdErr)
    }
}

function Get-RaceOutcome {
    param([Parameter(Mandatory = $true)][string]$StdOut)

    $match = [regex]::Match($StdOut, '(?m)^(?<outcome>READY|EXISTING) \[(?<id>KC-\d{8}-\d{6}-[0-9a-f]{8})\]')
    if (-not $match.Success) { return $null }
    return [pscustomobject]@{
        Outcome = $match.Groups['outcome'].Value
        Id = $match.Groups['id'].Value
    }
}

function Get-SafeGeneratorDiagnosticClass {
    param([Parameter(Mandatory = $true)]$Result)

    $combined = ([string]$Result.StdOut) + ([string]$Result.StdErr)
    if ($combined -match 'blocked: candidate-lock-timeout') { return 'candidate-lock-timeout' }
    if ($combined -match 'blocked: claim-key-collision') { return 'claim-key-collision' }
    if ($combined -match 'blocked: missing-git-baseline') { return 'missing-git-baseline' }
    if ($combined -match 'blocked: repository-mode') { return 'repository-mode' }
    if ($combined -match 'blocked: invalid-authority') { return 'invalid-authority' }
    if ($combined -match 'scripts/verify-knowledge\.ps1') { return 'strict-preflight' }
    if ($Result.TimedOut) { return 'timeout' }
    return 'unclassified'
}

function Assert-NoRaceArtifacts {
    param([Parameter(Mandatory = $true)][string]$Root)

    $artifacts = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Where-Object {
        $_.Name -match '(?i)(?:\.tmp$|\.lock$|^\.candidate-)'
    })
    if ($artifacts.Count -ne 0) {
        throw 'RED: race left temporary or lock artifacts.'
    }
}

function Assert-SameKeyRace {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$Results,
        [Parameter(Mandatory = $true)][int[]]$SelectedCases
    )

    if ($Results.Count -lt 8) {
        throw 'RED: A12 requires at least eight generator processes.'
    }
    if (@($Results | Where-Object { $_.TimedOut }).Count -ne 0) {
        throw 'RED: generator race timed out.'
    }
    $failedResults = @($Results | Where-Object { $_.ExitCode -ne 0 })
    if ($failedResults.Count -ne 0) {
        $exitCodes = @($failedResults | ForEach-Object { [int]$_.ExitCode } | Sort-Object -Unique) -join ','
        $diagnosticClasses = @(
            $failedResults |
                ForEach-Object { Get-SafeGeneratorDiagnosticClass -Result $_ } |
                Group-Object |
                Sort-Object Name |
                ForEach-Object { '{0}:{1}' -f $_.Name, $_.Count }
        ) -join ','
        throw "RED: generator race returned nonzero results; failed=$($failedResults.Count); exit-codes=$exitCodes; safe-classes=$diagnosticClasses."
    }
    if (@($Results | Where-Object { -not [string]::IsNullOrWhiteSpace($_.StdErr) }).Count -ne 0) {
        throw 'RED: successful generator race wrote diagnostics to stderr.'
    }

    $outcomes = @($Results | ForEach-Object { Get-RaceOutcome -StdOut $_.StdOut })
    if (@($outcomes | Where-Object { $null -eq $_ }).Count -ne 0) {
        throw 'RED: generator race did not return controlled READY or EXISTING outcomes.'
    }
    $ready = @($outcomes | Where-Object { $_.Outcome -ceq 'READY' })
    $existing = @($outcomes | Where-Object { $_.Outcome -ceq 'EXISTING' })
    if ($ready.Count -ne 1) {
        throw "RED: A14 expected one READY, actual=$($ready.Count)."
    }
    if ($existing.Count -ne ($Results.Count - 1)) {
        throw "RED: A15 expected controlled EXISTING outcomes, actual=$($existing.Count)."
    }
    $ids = @($outcomes | ForEach-Object { $_.Id } | Sort-Object -Unique)
    if ($ids.Count -ne 1) {
        throw 'RED: A15 workers returned different candidate IDs.'
    }

    $candidateFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'knowledge\candidates') -Recurse -File -Filter 'KC-*.md' -Force)
    if ($candidateFiles.Count -ne 1) {
        throw "RED: A16 expected one candidate file, actual=$($candidateFiles.Count)."
    }
    Assert-NoRaceArtifacts -Root $Root

    $strict = Invoke-RaceVerifier -Root $Root
    if ($strict.ExitCode -ne 0) {
        throw 'RED: A17 strict verifier failed after generator race.'
    }

    foreach ($case in $SelectedCases) {
        switch ($case) {
            12 { Write-Host 'PASS: A12 eight parallel generator processes completed' }
            14 { Write-Host 'PASS: A14 exactly one worker returned READY' }
            15 { Write-Host 'PASS: A15 remaining workers returned EXISTING with the same ID' }
            16 { Write-Host 'PASS: A16 exactly one candidate file remains without temp or lock artifacts' }
            17 { Write-Host 'PASS: A17 strict verifier passes after same-key race' }
        }
    }
}

function Assert-DifferentKeyRace {
    param([Parameter(Mandatory = $true)][string]$Root)

    $claimKeys = @(0..7 | ForEach-Object { 'parallel-distinct-{0}' -f $_ })
    $results = @(Invoke-BarrierRace -Root $Root -ClaimKeys $claimKeys)
    if ($results.Count -ne $claimKeys.Count -or
        @($results | Where-Object { $_.TimedOut -or $_.ExitCode -ne 0 }).Count -ne 0) {
        throw 'RED: A18 parallel distinct claim keys did not all complete successfully.'
    }
    $outcomes = @($results | ForEach-Object { Get-RaceOutcome -StdOut $_.StdOut })
    if (@($outcomes | Where-Object { $null -eq $_ -or $_.Outcome -cne 'READY' }).Count -ne 0) {
        throw 'RED: A18 distinct claim keys did not each return READY.'
    }
    if (@($outcomes | ForEach-Object { $_.Id } | Sort-Object -Unique).Count -ne $claimKeys.Count) {
        throw 'RED: A18 distinct claim keys lost a candidate ID.'
    }
    $candidateFiles = @(Get-ChildItem -LiteralPath (Join-Path $Root 'knowledge\candidates') -Recurse -File -Filter 'KC-*.md' -Force)
    if ($candidateFiles.Count -ne $claimKeys.Count) {
        throw "RED: A18 expected $($claimKeys.Count) files, actual=$($candidateFiles.Count)."
    }
    Assert-NoRaceArtifacts -Root $Root
    $strict = Invoke-RaceVerifier -Root $Root
    if ($strict.ExitCode -ne 0) {
        throw 'RED: A18 strict verifier failed after distinct-key race.'
    }
    Write-Host 'PASS: A18 parallel distinct claim keys create without loss'
}

if (-not $temporaryRoot.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe fixture root: $temporaryRoot"
}

try {
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    $templateFixtureRoot = $null
    $generatedBaseRoot = $null

    if (@($CaseId | Where-Object { $_ -in @(1, 11) }).Count -gt 0) {
        $templateFixtureRoot = New-TemplateFixtureRoot -Name 'template-source'
    }
    if (@($CaseId | Where-Object { $_ -ge 2 -and $_ -le 23 -and $_ -ne 21 }).Count -gt 0) {
        $generatedBaseRoot = New-GeneratedFixtureRoot -Name 'generated-base'
    }
    if (@($CaseId | Where-Object { $_ -ge 12 -and $_ -le 18 }).Count -gt 0) {
        $script:raceBaseRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'race-base'
        Set-ValidGeneratedProjectMode `
            -Root $script:raceBaseRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('33333333' + '-3333-4333-8333-' + '333333333333') `
            -Slug 'generator-race-fixture'
        New-FixtureBaselineCommit -Root $script:raceBaseRoot
    }

    if ($CaseId -contains 1) {
        $templateResult = Invoke-PublicVerifier -Root $templateFixtureRoot
        Assert-Success -Result $templateResult -Name 'A01 template source with placeholders and disabled mode passes'
    }

    if ($CaseId -contains 2) {
        Assert-InitializedReportOnlyProject -Root $generatedBaseRoot
        Assert-ZeroCommitGeneratedProject -Root $generatedBaseRoot
        foreach ($requiredPortablePath in @(
            '.agents/skills/it-analysis/SKILL.md',
            '.agents/skills/project-delivery/SKILL.md',
            '.agents/skills/knowledge-curator/SKILL.md',
            '.agents/skills/startup-researcher/SKILL.md',
            '.codex/config.toml',
            '.codex/agents/analysis_red_team.toml',
            '.codex/agents/analysis_reviewer.toml',
            '.codex/agents/business_analyst.toml',
            '.codex/agents/requirements_analyst.toml',
            '.codex/agents/system_analyst.toml',
            'analysis/CONTRACT.md',
            'analysis/runs/.gitkeep',
            'business/architecture.md',
            'business/analysis/INDEX.md',
            'docs/analysis/INDEX.md',
            'docs/architecture/overview.md',
            'docs/codebase/overview.md',
            'knowledge/graph/INDEX.md',
            'mastery/INTENTS.json',
            'mastery/analyst/INDEX.md',
            'mastery/local/TEMPLATE.md',
            'plans/INDEX.md',
            'plans/TEMPLATE.md',
            'product/INDEX.md',
            'prompts/analysis-run.md',
            'scripts/lib/ModelProject.Platform.psm1',
            'scripts/new-analysis-run.ps1',
            'scripts/new-project.ps1',
            'scripts/new-plan.ps1',
            'scripts/verify-analysis.ps1',
            'scripts/verify-canon.ps1',
            'scripts/verify-plans.ps1',
            'scripts/update-knowledge-graph.ps1'
        )) {
            if (-not (Test-Path -LiteralPath (Join-Path $generatedBaseRoot $requiredPortablePath.Replace('/', '\')) -PathType Leaf)) {
                throw "RED: A02 missing portable v2 payload: $requiredPortablePath"
            }
        }
        foreach ($forbiddenGeneratedPath in @(
            '.agents/skills/bulletproof',
            '.agents/skills/frontend-design',
            'plans/2026-08-14-portable-analysis-control-plane.md',
            'docs/decisions/2026-08-14-portable-analysis-control-plane.md',
            'retrospectives/2026-08-15_13-05_portable-analysis-control-plane.md',
            'plans/2026-08-16-assisted-learning-knowledge-graph.md',
            'docs/decisions/2026-08-16-assisted-learning-knowledge-graph.md'
        )) {
            if (Test-Path -LiteralPath (Join-Path $generatedBaseRoot $forbiddenGeneratedPath.Replace('/', '\'))) {
                throw "RED: A02 generated project leaked source-only or owner path: $forbiddenGeneratedPath"
            }
        }
        $freshCopyResult = Invoke-PublicVerifier -Root $generatedBaseRoot
        Assert-Success -Result $freshCopyResult -Name 'A02 public new-project creates initialized + report-only with zero commits'

        $externalVerifierPath = Join-Path $generatedBaseRoot 'scripts\verify-knowledge.ps1'
        $externalGraphPath = Join-Path $generatedBaseRoot 'scripts\update-knowledge-graph.ps1'
        $externalModulePath = Join-Path $generatedBaseRoot 'scripts\lib\ModelProject.Knowledge.psm1'
        $externalVerifierBytes = [System.IO.File]::ReadAllBytes($externalVerifierPath)
        $externalGraphBytes = [System.IO.File]::ReadAllBytes($externalGraphPath)
        $externalModuleBytes = [System.IO.File]::ReadAllBytes($externalModulePath)
        try {
            [System.IO.File]::WriteAllText($externalVerifierPath, "throw 'external verifier must not execute'`n", $utf8NoBom)
            [System.IO.File]::WriteAllText($externalGraphPath, "throw 'external graph script must not execute'`n", $utf8NoBom)
            [System.IO.File]::WriteAllText($externalModulePath, "throw 'external module must not import'`n", $utf8NoBom)
            $trustedStructureResult = Invoke-CapturedProcess `
        -FilePath $powerShellHost `
                -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $sourceRoot 'scripts\verify-structure.ps1'),'-Root',$generatedBaseRoot,'-Mode','GeneratedProject') `
                -WorkingDirectory $sourceRoot
            if ($trustedStructureResult.TimedOut -or $trustedStructureResult.ExitCode -ne 0) {
                throw 'RED: A02 source structure gate executed verifier or module from external Root.'
            }
            Write-Host 'PASS: A02 source structure gate ignores fake verifier and module under external Root'
        }
        finally {
            [System.IO.File]::WriteAllBytes($externalVerifierPath, $externalVerifierBytes)
            [System.IO.File]::WriteAllBytes($externalGraphPath, $externalGraphBytes)
            [System.IO.File]::WriteAllBytes($externalModulePath, $externalModuleBytes)
        }

        $missingVerifierPath = $externalVerifierPath + '.missing'
        [System.IO.File]::Move($externalVerifierPath, $missingVerifierPath)
        try {
            $missingChildResult = Invoke-CapturedProcess `
        -FilePath $powerShellHost `
                -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $generatedBaseRoot 'scripts\verify-structure.ps1'),'-Mode','GeneratedProject') `
                -WorkingDirectory $sourceRoot
            $missingChildOutput = ([string]$missingChildResult.StdOut) + ([string]$missingChildResult.StdErr)
            if ($missingChildResult.TimedOut -or $missingChildResult.ExitCode -eq 0 -or $missingChildOutput -notmatch '(?i)trusted knowledge verifier') {
                throw 'RED: A02 missing trusted knowledge child did not fail closed.'
            }
            Write-Host 'PASS: A02 missing trusted knowledge child fails closed'
        }
        finally {
            [System.IO.File]::Move($missingVerifierPath, $externalVerifierPath)
        }

        $missingGraphPath = $externalGraphPath + '.missing'
        [System.IO.File]::Move($externalGraphPath, $missingGraphPath)
        try {
            $missingGraphChildResult = Invoke-CapturedProcess `
        -FilePath $powerShellHost `
                -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $generatedBaseRoot 'scripts\verify-structure.ps1'),'-Mode','GeneratedProject') `
                -WorkingDirectory $sourceRoot
            $missingGraphChildOutput = ([string]$missingGraphChildResult.StdOut) + ([string]$missingGraphChildResult.StdErr)
            if ($missingGraphChildResult.TimedOut -or $missingGraphChildResult.ExitCode -eq 0 -or $missingGraphChildOutput -notmatch '(?i)trusted knowledge-graph verifier') {
                throw 'RED: A02 missing trusted knowledge-graph child did not fail closed.'
            }
            Write-Host 'PASS: A02 missing trusted knowledge-graph child fails closed'
        }
        finally {
            [System.IO.File]::Move($missingGraphPath, $externalGraphPath)
        }

        $sourceOnlyProbe = Join-Path $generatedBaseRoot 'scripts\build-github-template.ps1'
        Write-Utf8Fixture -Path $sourceOnlyProbe -Content "# source-only boundary probe`n"
        try {
            $sourceOnlyResult = Invoke-CapturedProcess `
        -FilePath $powerShellHost `
                -ArgumentList @(
                    '-NoLogo',
                    '-NoProfile',
                    '-NonInteractive',
                    '-ExecutionPolicy',
                    'Bypass',
                    '-File',
                    (Join-Path $generatedBaseRoot 'scripts\verify-structure.ps1'),
                    '-Mode',
                    'GeneratedProject'
                ) `
                -WorkingDirectory $sourceRoot
            $sourceOnlyOutput = ([string]$sourceOnlyResult.StdOut) + ([string]$sourceOnlyResult.StdErr)
            $expectedSourceOnlyDiagnostic = [regex]::Escape('GeneratedProject: source-only manifest-путь существует: scripts/build-github-template.ps1')
            if ($sourceOnlyResult.TimedOut -or $sourceOnlyResult.ExitCode -eq 0 -or
                $sourceOnlyOutput -notmatch $expectedSourceOnlyDiagnostic) {
                throw 'RED: A02 GeneratedProject verifier не заблокировал exact source-only path.'
            }
            Write-Host 'PASS: A02 GeneratedProject rejects exact source-only path'
        }
        finally {
            if (Test-Path -LiteralPath $sourceOnlyProbe -PathType Leaf) {
                [System.IO.File]::Delete($sourceOnlyProbe)
            }
        }
    }

    if ($CaseId -contains 3) {
        $blankActiveRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'blank-active'
        $projectPath = Join-Path $blankActiveRoot 'PROJECT.md'
        $project = [System.IO.File]::ReadAllText($projectPath)
        if ($project -cnotmatch '(?m)^project_status: initialized$') {
            throw 'A03 fixture does not start from initialized state.'
        }
        $project = $project.Replace('project_status: initialized', 'project_status: active')
        Write-Utf8Fixture -Path $projectPath -Content $project
        $candidateCount = @(Get-CandidateFiles -Root $blankActiveRoot).Count
        $blankActive = Invoke-PublicVerifier -Root $blankActiveRoot
        Assert-Blocked `
            -Result $blankActive `
            -SafePattern 'PROJECT\.md:.*(?:activation|passport|placeholder)' `
            -Name 'A03 active project with blank passport is blocked'
        Assert-NoCandidateMutation -Root $blankActiveRoot -ExpectedCount $candidateCount -Name 'A03'
    }

    if ($CaseId -contains 4) {
        $activeReportOnlyRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'active-report-only'
        Set-ValidGeneratedProjectMode `
            -Root $activeReportOnlyRoot `
            -Status active `
            -CaptureMode report-only `
            -ProjectId ('44444444' + '-4444-4444-8444-' + '444444444444') `
            -Slug 'active-report-only-fixture'
        $activeReportOnly = Invoke-PublicVerifier -Root $activeReportOnlyRoot
        Assert-Success -Result $activeReportOnly -Name 'A04 filled active + report-only passes without HEAD'
    }

    if ($CaseId -contains 5) {
        $missingHeadRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'safe-local-without-head'
        Set-ValidGeneratedProjectMode `
            -Root $missingHeadRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('55555555' + '-5555-4555-8555-' + '555555555555') `
            -Slug 'safe-local-without-head-fixture'
        $candidateCount = @(Get-CandidateFiles -Root $missingHeadRoot).Count
        $safeLocalWithoutHead = Invoke-PublicVerifier -Root $missingHeadRoot
        Assert-Blocked `
            -Result $safeLocalWithoutHead `
            -SafePattern 'blocked: missing-git-baseline' `
            -Name 'A05 safe-local without Git HEAD is blocked'
        Assert-NoCandidateMutation -Root $missingHeadRoot -ExpectedCount $candidateCount -Name 'A05'
    }

    if ($CaseId -contains 6) {
        $baselineRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'safe-local-with-baseline'
        Set-ValidGeneratedProjectMode `
            -Root $baselineRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('66666666' + '-6666-4666-8666-' + '666666666666') `
            -Slug 'safe-local-with-baseline-fixture'
        New-FixtureBaselineCommit -Root $baselineRoot
        $safeLocalWithHead = Invoke-PublicVerifier -Root $baselineRoot
        Assert-Success -Result $safeLocalWithHead -Name 'A06 safe-local passes after a separate fixture baseline commit'

        $worktreeSourceRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'safe-worktree-source'
        Set-ValidGeneratedProjectMode `
            -Root $worktreeSourceRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('67676767' + '-6767-4767-8767-' + '676767676767') `
            -Slug 'safe-linked-worktree-fixture'
        New-FixtureBaselineCommit -Root $worktreeSourceRoot
        $worktreeRoot = Join-Path $temporaryRoot 'safe-linked-worktree'
        $worktreeAdd = Invoke-FixtureGit `
            -Root $worktreeSourceRoot `
            -Arguments @('worktree', 'add', '--detach', $worktreeRoot, 'HEAD')
        Assert-FixtureGitSuccess -Result $worktreeAdd -Operation 'create standard linked worktree'
        if (-not (Test-Path -LiteralPath (Join-Path $worktreeRoot '.git') -PathType Leaf)) {
            throw 'RED: A06 linked worktree does not expose the standard .git gitdir file.'
        }
        $worktreeVerifier = Invoke-PublicVerifier -Root $worktreeRoot
        Assert-Success -Result $worktreeVerifier -Name 'A06 standard linked worktree gitdir file passes public verifier'
        $worktreeCandidate = Invoke-PublicGenerator `
            -Root $worktreeRoot `
            -ClaimKey 'a06-standard-linked-worktree'
        $null = Assert-GeneratorReady `
            -Result $worktreeCandidate `
            -Root $worktreeRoot `
            -ExpectedCandidateCount 1 `
            -Name 'A06 standard linked worktree gitdir file passes public generator'

        $malformedMarkerRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'malformed-gitdir-marker'
        Set-ValidGeneratedProjectMode `
            -Root $malformedMarkerRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('68686868' + '-6868-4868-8868-' + '686868686868') `
            -Slug 'malformed-gitdir-marker-fixture'
        New-FixtureBaselineCommit -Root $malformedMarkerRoot
        $malformedGitDirectory = Move-FixtureGitDirectory `
            -Root $malformedMarkerRoot `
            -Destination (Join-Path $temporaryRoot 'malformed-gitdir-storage')
        Write-Utf8Fixture `
            -Path (Join-Path $malformedMarkerRoot '.git') `
            -Content ("gitdir: $malformedGitDirectory`ntrailing: rejected`n")
        $malformedVerifier = Invoke-PublicVerifier -Root $malformedMarkerRoot
        Assert-Blocked `
            -Result $malformedVerifier `
            -SafePattern 'blocked: missing-git-baseline' `
            -Name 'A06 malformed gitdir marker is blocked by public verifier'
        $malformedGenerator = Invoke-PublicGenerator `
            -Root $malformedMarkerRoot `
            -ClaimKey 'a06-malformed-gitdir-marker'
        Assert-GeneratorBlocked `
            -Result $malformedGenerator `
            -Root $malformedMarkerRoot `
            -ExpectedCandidateCount 0 `
            -SafePattern 'blocked: missing-git-baseline' `
            -Name 'A06 malformed gitdir marker is blocked by public generator'

        $reparseMarkerRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'reparse-git-marker'
        Set-ValidGeneratedProjectMode `
            -Root $reparseMarkerRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('69696969' + '-6969-4969-8969-' + '696969696969') `
            -Slug 'reparse-git-marker-fixture'
        New-FixtureBaselineCommit -Root $reparseMarkerRoot
        $reparseGitDirectory = Move-FixtureGitDirectory `
            -Root $reparseMarkerRoot `
            -Destination (Join-Path $temporaryRoot 'reparse-git-storage')
        $junction = New-Item `
            -ItemType Junction `
            -Path (Join-Path $reparseMarkerRoot '.git') `
            -Target $reparseGitDirectory
        if (($junction.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
            throw 'RED: A06 fixture .git junction is not a reparse point.'
        }
        $reparseVerifier = Invoke-PublicVerifier -Root $reparseMarkerRoot
        Assert-Blocked `
            -Result $reparseVerifier `
            -SafePattern 'blocked: missing-git-baseline' `
            -Name 'A06 reparse .git marker is blocked by public verifier'
        $reparseGenerator = Invoke-PublicGenerator `
            -Root $reparseMarkerRoot `
            -ClaimKey 'a06-reparse-git-marker'
        Assert-GeneratorBlocked `
            -Result $reparseGenerator `
            -Root $reparseMarkerRoot `
            -ExpectedCandidateCount 0 `
            -SafePattern 'blocked: missing-git-baseline' `
            -Name 'A06 reparse .git marker is blocked by public generator'
    }

    if ($CaseId -contains 7) {
        $diffRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'curator-diff-oracle'
        New-FixtureBaselineCommit -Root $diffRoot
        Assert-CuratorDiffOracle -Root $diffRoot
    }

    if ($CaseId -contains 8) {
        $missingSnapshotRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'missing-diff-baseline-contract'
        Assert-MissingDiffBaselineAgentContract -Root $missingSnapshotRoot
    }

    if ($CaseId -contains 9) {
        $reportOnlyCaptureRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'report-only-automatic-capture'
        Set-ValidGeneratedProjectMode `
            -Root $reportOnlyCaptureRoot `
            -Status active `
            -CaptureMode report-only `
            -ProjectId ('99999999' + '-9999-4999-8999-' + '999999999999') `
            -Slug 'report-only-capture-fixture'
        $candidateCount = @(Get-CandidateFiles -Root $reportOnlyCaptureRoot).Count
        $automaticCapture = Invoke-PublicGenerator `
            -Root $reportOnlyCaptureRoot `
            -ClaimKey 'a09-report-only-automatic'
        Assert-GeneratorBlocked `
            -Result $automaticCapture `
            -Root $reportOnlyCaptureRoot `
            -ExpectedCandidateCount $candidateCount `
            -SafePattern 'blocked: repository-mode' `
            -Name 'A09 automatic capture in report-only creates no file'

        $invalidBasisRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'automatic-explicit-user-capture'
        Set-ValidGeneratedProjectMode `
            -Root $invalidBasisRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('91919191' + '-9191-4919-8919-' + '919191919191') `
            -Slug 'automatic-explicit-user-capture-fixture'
        New-FixtureBaselineCommit -Root $invalidBasisRoot
        $invalidBasisCount = @(Get-CandidateFiles -Root $invalidBasisRoot).Count
        $invalidBasis = Invoke-PublicGenerator `
            -Root $invalidBasisRoot `
            -ClaimKey 'a09-automatic-explicit-user-capture' `
            -CaptureBasis explicit-user-capture
        Assert-GeneratorBlocked `
            -Result $invalidBasis `
            -Root $invalidBasisRoot `
            -ExpectedCandidateCount $invalidBasisCount `
            -SafePattern 'blocked: invalid-authority' `
            -Name 'A09 automatic capture with explicit-user-capture basis creates no file'

        $strictExistingRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'strict-existing-preflight'
        Set-ValidGeneratedProjectMode `
            -Root $strictExistingRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('92929292' + '-9292-4929-8929-' + '929292929292') `
            -Slug 'strict-existing-preflight-fixture'
        New-FixtureBaselineCommit -Root $strictExistingRoot
        $initialExisting = Invoke-PublicGenerator `
            -Root $strictExistingRoot `
            -ClaimKey 'a09-preexisting-exact-match'
        $null = Assert-GeneratorReady `
            -Result $initialExisting `
            -Root $strictExistingRoot `
            -ExpectedCandidateCount 1 `
            -Name 'A09 exact candidate fixture is created before malformed corpus injection'
        $malformedCandidateDirectory = Join-Path $strictExistingRoot 'knowledge\candidates\2026'
        if (-not (Test-Path -LiteralPath $malformedCandidateDirectory -PathType Container)) {
            [System.IO.Directory]::CreateDirectory($malformedCandidateDirectory) | Out-Null
        }
        $malformedCandidatePath = Join-Path $malformedCandidateDirectory 'KC-20260101-010101-deadbeef.md'
        Write-Utf8Fixture -Path $malformedCandidatePath -Content @'
---
id: KC-20260101-010101-deadbeef
state: ready
claim_key: unrelated-malformed-corpus-entry
---

# Deliberately incomplete fixture
'@
        $preexistingResult = Invoke-PublicGenerator `
            -Root $strictExistingRoot `
            -ClaimKey 'a09-preexisting-exact-match'
        if ((([string]$preexistingResult.StdOut) + ([string]$preexistingResult.StdErr)) -match '(?m)^EXISTING\b') {
            throw 'RED: A09 preexisting exact match bypassed strict full-corpus preflight.'
        }
        Assert-GeneratorBlocked `
            -Result $preexistingResult `
            -Root $strictExistingRoot `
            -ExpectedCandidateCount 2 `
            -SafePattern '(?im)^ERROR: blocked: repository-preflight\s*$' `
            -Name 'A09 preexisting exact match is blocked when unrelated corpus entry is malformed'
    }

    if ($CaseId -contains 10) {
        $explicitRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'report-only-explicit-promotion'
        Set-ValidGeneratedProjectMode `
            -Root $explicitRoot `
            -Status active `
            -CaptureMode report-only `
            -ProjectId ('10101010' + '-1010-4010-8010-' + '101010101010') `
            -Slug 'report-only-explicit-fixture'
        $beforeCount = @(Get-CandidateFiles -Root $explicitRoot).Count
        $explicit = Invoke-PublicGenerator `
            -Root $explicitRoot `
            -ClaimKey 'a10-explicit-promotion-authority' `
            -WriteIntent explicit-promotion `
            -AuthorityRef 'user-request:a10-explicit-promotion' `
            -CaptureBasis explicit-user-capture `
            -Title 'Explicit report-only fixture candidate'
        if ($explicit.TimedOut -or $explicit.ExitCode -ne 0 -or
            -not [string]::IsNullOrWhiteSpace($explicit.StdErr)) {
            throw 'RED: A10 explicit-promotion public generator route failed.'
        }
        $explicitOutcome = Get-RaceOutcome -StdOut $explicit.StdOut
        if ($null -eq $explicitOutcome -or $explicitOutcome.Outcome -cne 'READY') {
            throw 'RED: A10 explicit-promotion route did not return controlled READY.'
        }
        Assert-NoCandidateMutation -Root $explicitRoot -ExpectedCount ($beforeCount + 1) -Name 'A10'
        Complete-FixturePromotionChangeSet -Root $explicitRoot
        $explicitStrict = Invoke-PublicVerifier -Root $explicitRoot
        if ($explicitStrict.TimedOut -or $explicitStrict.ExitCode -ne 0) {
            throw 'RED: A10 strict verifier failed after the recoverable explicit promotion change set.'
        }
        Write-Host 'PASS: A10 agent-driven explicit promotion in active + report-only accepts authority and passes public strict verification'
    }

    if ($CaseId -contains 11) {
        $templateCandidateCount = @(Get-CandidateFiles -Root $templateFixtureRoot).Count
        $templatePromotion = Invoke-PublicGenerator `
            -Root $templateFixtureRoot `
            -ClaimKey 'a11-template-promotion' `
            -WriteIntent explicit-promotion `
            -AuthorityRef 'user-request:a11-template-promotion' `
            -CaptureBasis explicit-user-capture
        Assert-GeneratorBlocked `
            -Result $templatePromotion `
            -Root $templateFixtureRoot `
            -ExpectedCandidateCount $templateCandidateCount `
            -SafePattern 'blocked: repository-mode' `
            -Name 'A11 template promotion is blocked'

        $archivedRoot = Copy-GeneratedFixtureRoot -BaseRoot $generatedBaseRoot -Name 'archived-promotion'
        Set-ValidGeneratedProjectMode `
            -Root $archivedRoot `
            -Status archived `
            -CaptureMode disabled `
            -ProjectId ('11111111' + '-1111-4111-8111-' + '111111111111') `
            -Slug 'archived-promotion-fixture'
        $archivedVerifier = Invoke-PublicVerifier -Root $archivedRoot
        if ($archivedVerifier.TimedOut -or $archivedVerifier.ExitCode -ne 0) {
            throw 'RED: A11 archived fixture is not valid before the promotion attempt.'
        }
        $archivedCandidateCount = @(Get-CandidateFiles -Root $archivedRoot).Count
        $archivedPromotion = Invoke-PublicGenerator `
            -Root $archivedRoot `
            -ClaimKey 'a11-archived-promotion' `
            -WriteIntent explicit-promotion `
            -AuthorityRef 'user-request:a11-archived-promotion' `
            -CaptureBasis explicit-user-capture
        Assert-GeneratorBlocked `
            -Result $archivedPromotion `
            -Root $archivedRoot `
            -ExpectedCandidateCount $archivedCandidateCount `
            -SafePattern 'blocked: repository-mode' `
            -Name 'A11 archived promotion is blocked'
    }

    $sameKeyCases = @($CaseId | Where-Object { $_ -in 12..17 })
    if ($sameKeyCases.Count -gt 0) {
        $repeatCount = if ($CaseId -contains 13) { $RaceRepeats } else { 1 }
        for ($repeat = 1; $repeat -le $repeatCount; $repeat++) {
            $raceRoot = New-RaceFixtureRoot -Name ('same-key-{0}' -f $repeat)
            $sameClaim = 'parallel-same-claim'
            $results = @(Invoke-BarrierRace -Root $raceRoot -ClaimKeys @(0..7 | ForEach-Object { $sameClaim }))
            Assert-SameKeyRace -Root $raceRoot -Results $results -SelectedCases $sameKeyCases
        }
        if ($CaseId -contains 13) {
            Write-Host "PASS: A13 start-barrier race repeated $repeatCount times"
        }
    }

    if ($CaseId -contains 18) {
        $differentKeyRoot = New-RaceFixtureRoot -Name 'different-keys'
        Assert-DifferentKeyRace -Root $differentKeyRoot
    }

    if ($CaseId -contains 19) {
        $foreignRoot = New-ForeignGitRepository -Name 'foreign-git-environment-sentinel'
        $foreignEnvironment = Get-ForeignGitEnvironment -Root $foreignRoot
        $foreignBefore = Get-DirectoryFingerprint -Root $foreignRoot

        $inheritedRoot = Copy-GeneratedFixtureRoot `
            -BaseRoot $generatedBaseRoot `
            -Name 'inherited-git-environment-safe-local'
        Set-ValidGeneratedProjectMode `
            -Root $inheritedRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('19191919' + '-1919-4919-8919-' + '191919191919') `
            -Slug 'inherited-git-environment-fixture'
        $inheritedVerifier = Invoke-PublicVerifier `
            -Root $inheritedRoot `
            -EnvironmentVariables $foreignEnvironment
        if ($inheritedVerifier.Output -notmatch 'blocked: missing-git-baseline') {
            throw 'RED: A19 inherited Git environment did not produce missing-git-baseline.'
        }
        Assert-SafePublicFailure `
            -Result $inheritedVerifier `
            -ForbiddenText @($foreignRoot) `
            -Name 'A19 verifier ignores inherited foreign Git repository with HEAD'
        $inheritedGenerator = Invoke-PublicGenerator `
            -Root $inheritedRoot `
            -ClaimKey 'a19-inherited-foreign-git-environment' `
            -EnvironmentVariables $foreignEnvironment
        Assert-GeneratorBlocked `
            -Result $inheritedGenerator `
            -Root $inheritedRoot `
            -ExpectedCandidateCount 0 `
            -SafePattern 'blocked: missing-git-baseline' `
            -Name 'A19 generator ignores inherited foreign Git repository with HEAD'
        $inheritedGeneratorOutput = ([string]$inheritedGenerator.StdOut) + ([string]$inheritedGenerator.StdErr)
        if ($inheritedGeneratorOutput.IndexOf($foreignRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw 'RED: A19 generator diagnostic exposed the foreign repository path.'
        }
        Assert-ForeignRepositoryUnchanged `
            -Root $foreignRoot `
            -Before $foreignBefore `
            -Name 'A19 inherited Git environment isolation'

        $forgedMarkerRoot = Copy-GeneratedFixtureRoot `
            -BaseRoot $generatedBaseRoot `
            -Name 'forged-foreign-gitdir-marker'
        Set-ValidGeneratedProjectMode `
            -Root $forgedMarkerRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('19292929' + '-2929-4929-8929-' + '292929292929') `
            -Slug 'forged-foreign-gitdir-marker-fixture'
        $null = Move-FixtureGitDirectory `
            -Root $forgedMarkerRoot `
            -Destination (Join-Path $temporaryRoot 'forged-marker-original-git-storage')
        Write-Utf8Fixture `
            -Path (Join-Path $forgedMarkerRoot '.git') `
            -Content ("gitdir: $([System.IO.Path]::GetFullPath((Join-Path $foreignRoot '.git')))`n")
        $cleanGitEnvironment = @{
            GIT_DIR = $null
            GIT_WORK_TREE = $null
            GIT_INDEX_FILE = $null
        }
        $forgedVerifier = Invoke-PublicVerifier `
            -Root $forgedMarkerRoot `
            -EnvironmentVariables $cleanGitEnvironment
        if ($forgedVerifier.Output -notmatch 'blocked: missing-git-baseline') {
            throw 'RED: A19 forged foreign gitdir marker did not produce missing-git-baseline.'
        }
        Assert-SafePublicFailure `
            -Result $forgedVerifier `
            -ForbiddenText @($foreignRoot) `
            -Name 'A19 forged gitdir marker without exact backlink is blocked by verifier'
        $forgedGenerator = Invoke-PublicGenerator `
            -Root $forgedMarkerRoot `
            -ClaimKey 'a19-forged-foreign-gitdir-marker' `
            -EnvironmentVariables $cleanGitEnvironment
        Assert-GeneratorBlocked `
            -Result $forgedGenerator `
            -Root $forgedMarkerRoot `
            -ExpectedCandidateCount 0 `
            -SafePattern 'blocked: missing-git-baseline' `
            -Name 'A19 forged gitdir marker without exact backlink is blocked by generator'
        $forgedGeneratorOutput = ([string]$forgedGenerator.StdOut) + ([string]$forgedGenerator.StdErr)
        if ($forgedGeneratorOutput.IndexOf($foreignRoot, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw 'RED: A19 forged-marker generator diagnostic exposed the foreign repository path.'
        }
        Assert-ForeignRepositoryUnchanged `
            -Root $foreignRoot `
            -Before $foreignBefore `
            -Name 'A19 forged gitdir marker isolation'

        $linkedSourceRoot = Copy-GeneratedFixtureRoot `
            -BaseRoot $generatedBaseRoot `
            -Name 'a19-linked-worktree-source'
        Set-ValidGeneratedProjectMode `
            -Root $linkedSourceRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('19393939' + '-3939-4939-8939-' + '393939393939') `
            -Slug 'a19-valid-linked-worktree-fixture'
        New-FixtureBaselineCommit -Root $linkedSourceRoot
        $linkedRoot = Join-Path $temporaryRoot 'a19-valid-linked-worktree'
        $linkedAdd = Invoke-FixtureGit `
            -Root $linkedSourceRoot `
            -Arguments @('worktree', 'add', '--detach', $linkedRoot, 'HEAD')
        Assert-FixtureGitSuccess -Result $linkedAdd -Operation 'create A19 valid linked worktree'
        $linkedVerifier = Invoke-PublicVerifier `
            -Root $linkedRoot `
            -EnvironmentVariables $cleanGitEnvironment
        Assert-Success `
            -Result $linkedVerifier `
            -Name 'A19 valid linked worktree with exact backlink still passes verifier'
        $linkedGenerator = Invoke-PublicGenerator `
            -Root $linkedRoot `
            -ClaimKey 'a19-valid-linked-worktree' `
            -EnvironmentVariables $cleanGitEnvironment
        $null = Assert-GeneratorReady `
            -Result $linkedGenerator `
            -Root $linkedRoot `
            -ExpectedCandidateCount 1 `
            -Name 'A19 valid linked worktree with exact backlink still passes generator'
    }

    if ($CaseId -contains 20) {
        $foreignRoot = New-ForeignGitRepository -Name 'initializer-foreign-git-environment-sentinel'
        $foreignEnvironment = Get-ForeignGitEnvironment -Root $foreignRoot
        $foreignBefore = Get-DirectoryFingerprint -Root $foreignRoot
        $destination = Join-Path $temporaryRoot 'inherited-git-new-project-destination'
        $newProjectResult = Invoke-PublicNewProject `
            -Destination $destination `
            -EnvironmentVariables $foreignEnvironment
        Assert-Success `
            -Result $newProjectResult `
            -Name 'A20 new-project ignores inherited Git redirection variables'
        if (-not (Test-Path -LiteralPath (Join-Path $destination '.git') -PathType Container)) {
            throw 'RED: A20 initializer did not create destination-local .git metadata.'
        }
        $absoluteGitDirectory = Invoke-FixtureGit `
            -Root $destination `
            -Arguments @('rev-parse', '--absolute-git-dir')
        Assert-FixtureGitSuccess -Result $absoluteGitDirectory -Operation 'resolve A20 destination Git directory'
        $expectedGitDirectory = [System.IO.Path]::GetFullPath((Join-Path $destination '.git')).TrimEnd([char[]]'\/')
        $actualGitDirectory = [System.IO.Path]::GetFullPath($absoluteGitDirectory.StdOut.Trim()).TrimEnd([char[]]'\/')
        if (-not $actualGitDirectory.Equals($expectedGitDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'RED: A20 git init was redirected away from the generated project.'
        }
        Assert-ZeroCommitGeneratedProject -Root $destination
        Assert-ForeignRepositoryUnchanged `
            -Root $foreignRoot `
            -Before $foreignBefore `
            -Name 'A20 inherited initializer Git environment isolation'
        Assert-NoNewProjectStagingArtifacts `
            -Parent $temporaryRoot `
            -Name 'A20'
    }

    if ($CaseId -contains 21) {
        $rollbackRoot = New-PortableTemplateFixtureRoot -Name 'initializer-rollback-portable-template'
        $projectPath = Join-Path $rollbackRoot 'PROJECT.md'
        $readmePath = Join-Path $rollbackRoot 'README.md'
        $originPath = Join-Path $rollbackRoot 'TEMPLATE-ORIGIN.md'
        $diagnosticFixturePath = Join-Path $rollbackRoot 'docs\INDEX.md'
        $projectBefore = Get-FileBytesFingerprint -Path $projectPath
        $readmeBefore = Get-FileBytesFingerprint -Path $readmePath
        $diagnosticFixtureBefore = [System.IO.File]::ReadAllText($diagnosticFixturePath)
        $diagnosticSentinel = 'Password=InitializerRollbackSentinel123456!'
        Write-Utf8Fixture `
            -Path $diagnosticFixturePath `
            -Content ($diagnosticFixtureBefore.TrimEnd() + "`n`n- [Late failure](../../$diagnosticSentinel)`n")

        $lateFailure = Invoke-PublicInitializer -Root $rollbackRoot
        Assert-SafePublicFailure `
            -Result $lateFailure `
            -ForbiddenText @($rollbackRoot, $diagnosticSentinel) `
            -RequiredPattern '(?im)^ERROR: initialization-rolled-back\s*$' `
            -Name 'A21 direct initializer late failure returns a safe diagnostic'
        if ((Get-FileBytesFingerprint -Path $projectPath) -cne $projectBefore -or
            (Get-FileBytesFingerprint -Path $readmePath) -cne $readmeBefore -or
            (Test-Path -LiteralPath $originPath) -or
            (Test-Path -LiteralPath (Join-Path $rollbackRoot '.git'))) {
            throw 'RED: A21 direct initializer late failure did not restore PROJECT.md, README.md, TEMPLATE-ORIGIN.md, and .git.'
        }
        Assert-NoInitializerArtifacts -Root $rollbackRoot -Name 'A21 rollback'

        Write-Utf8Fixture -Path $diagnosticFixturePath -Content $diagnosticFixtureBefore
        $retry = Invoke-PublicInitializer -Root $rollbackRoot
        Assert-Success -Result $retry -Name 'A21 direct initializer retry succeeds after rollback'
        if (-not (Test-Path -LiteralPath $originPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath (Join-Path $rollbackRoot '.git') -PathType Container)) {
            throw 'RED: A21 successful retry did not create origin and local Git metadata.'
        }
        Assert-InitializedReportOnlyProject -Root $rollbackRoot
        Assert-ZeroCommitGeneratedProject -Root $rollbackRoot
        Assert-NoInitializerArtifacts -Root $rollbackRoot -Name 'A21 retry'
    }

    if ($CaseId -contains 22) {
        $oversizedRoot = Copy-GeneratedFixtureRoot `
            -BaseRoot $generatedBaseRoot `
            -Name 'oversized-trusted-head-blob'
        Set-ValidGeneratedProjectMode `
            -Root $oversizedRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('22222222' + '-2222-4222-8222-' + '222222222222') `
            -Slug 'oversized-trusted-head-blob-fixture'
        New-FixtureBaselineCommit -Root $oversizedRoot
        $projectPath = Join-Path $oversizedRoot 'PROJECT.md'
        $validProject = [System.IO.File]::ReadAllText($projectPath)
        $oversizedSentinel = 'Password=OversizedTrustedHeadSentinel123456!'
        $oversizedProject = $validProject.TrimEnd() +
            "`n`n## Oversized historical payload`n`n" +
            ('x' * (2 * 1024 * 1024)) +
            "`n$oversizedSentinel`n"
        Write-Utf8Fixture -Path $projectPath -Content $oversizedProject
        Add-FixtureGitPaths -Root $oversizedRoot -RelativePaths @('PROJECT.md')
        $oversizedCommit = Invoke-FixtureGit `
            -Root $oversizedRoot `
            -Arguments @('commit', '-m', 'oversized trusted HEAD blob fixture')
        Assert-FixtureGitSuccess -Result $oversizedCommit -Operation 'commit oversized trusted HEAD blob'
        Write-Utf8Fixture -Path $projectPath -Content $validProject
        $blobSize = Invoke-FixtureGit `
            -Root $oversizedRoot `
            -Arguments @('cat-file', '-s', 'HEAD:PROJECT.md')
        Assert-FixtureGitSuccess -Result $blobSize -Operation 'measure oversized trusted HEAD blob'
        [long]$blobBytes = 0
        if (-not [long]::TryParse($blobSize.StdOut.Trim(), [ref]$blobBytes) -or $blobBytes -le 1MB) {
            throw 'RED: A22 fixture did not create an oversized trusted HEAD blob.'
        }

        $oversizedVerifier = Invoke-PublicVerifier -Root $oversizedRoot
        Assert-SafePublicFailure `
            -Result $oversizedVerifier `
            -ForbiddenText @($oversizedRoot, $oversizedSentinel) `
            -RequiredPattern 'Git HEAD blob size отклонен bounded reader' `
            -Name 'A22 verifier bounds and fails closed on oversized trusted HEAD blob'
        $oversizedGenerator = Invoke-PublicGenerator `
            -Root $oversizedRoot `
            -ClaimKey 'a22-oversized-trusted-head-blob'
        Assert-SafePublicFailure `
            -Result $oversizedGenerator `
            -ForbiddenText @($oversizedRoot, $oversizedSentinel) `
            -RequiredPattern '(?im)^ERROR: blocked: repository-preflight\s*$' `
            -Name 'A22 generator preflight fails closed on oversized trusted HEAD blob'
        Assert-NoCandidateMutation `
            -Root $oversizedRoot `
            -ExpectedCount 0 `
            -Name 'A22'
    }

    if ($CaseId -contains 23) {
        $boundedTreeRoot = Copy-GeneratedFixtureRoot `
            -BaseRoot $generatedBaseRoot `
            -Name 'bounded-git-head-tree-inventory'
        Set-ValidGeneratedProjectMode `
            -Root $boundedTreeRoot `
            -Status active `
            -CaptureMode safe-local `
            -ProjectId ('23232323' + '-2323-4323-8323-' + '232323232323') `
            -Slug 'bounded-git-head-tree-inventory-fixture'
        New-FixtureBaselineCommit -Root $boundedTreeRoot
        $boundedTreeSentinel = 'Password=BoundedGitHeadTreeSentinel123456!'
        Add-OversizedCandidateTreeCommit `
            -Root $boundedTreeRoot `
            -EntryCount 10001 `
            -Sentinel $boundedTreeSentinel
        if (@(Get-CandidateFiles -Root $boundedTreeRoot).Count -ne 0) {
            throw 'RED: A23 bounded Git tree fixture materialized candidate files in the worktree.'
        }

        $boundedTreeVerifier = Invoke-PublicVerifier -Root $boundedTreeRoot
        Assert-SafePublicFailure `
            -Result $boundedTreeVerifier `
            -ForbiddenText @($boundedTreeRoot, $boundedTreeSentinel) `
            -RequiredPattern 'bounded inventory limit \(10000 entries\)' `
            -Name 'A23 verifier streams and bounds trusted HEAD tree inventory'

        $boundedTreeGenerator = Invoke-PublicGenerator `
            -Root $boundedTreeRoot `
            -ClaimKey 'a23-bounded-git-head-tree-inventory'
        $boundedTreeGeneratorOutput = (
            ([string]$boundedTreeGenerator.StdOut) + ([string]$boundedTreeGenerator.StdErr)
        ).Trim()
        Assert-SafePublicFailure `
            -Result $boundedTreeGenerator `
            -ForbiddenText @($boundedTreeRoot, $boundedTreeSentinel) `
            -RequiredPattern '(?im)^ERROR: blocked: repository-preflight\s*$' `
            -Name 'A23 generator fails closed when bounded HEAD tree preflight fails'
        if ($boundedTreeGeneratorOutput -cne 'ERROR: blocked: repository-preflight') {
            throw 'RED: A23 generator returned an unexpected public diagnostic.'
        }
        Assert-NoCandidateMutation `
            -Root $boundedTreeRoot `
            -ExpectedCount 0 `
            -Name 'A23'
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        $resolved = (Resolve-Path -LiteralPath $temporaryRoot).Path
        if (-not $resolved.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing unsafe fixture cleanup: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
        if (Test-Path -LiteralPath $resolved) {
            throw 'Fixture cleanup did not remove the exact temporary root.'
        }
    }
}

Write-Host 'KNOWLEDGE CONTROL PLANE P0 PASS'
