[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$repositoryRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$platformPath = Join-Path $PSScriptRoot 'lib/ModelProject.Platform.psm1'
Import-Module $platformPath -Force
$nullDevice = Get-ModelProjectNullDevice
$temporaryBase = [System.IO.Path]::GetFullPath((Resolve-ModelProjectFileSystemLinkPath -Path ([System.IO.Path]::GetTempPath()))).TrimEnd([char[]]'\/')
$pathComparison = Get-ModelProjectPathComparison -Path $temporaryBase
$manifestPath = Join-Path $repositoryRoot '.template-manifest.json'
$temporaryPrefix = 'ModelProjectDistributionHarness-'
$temporaryRoot = Join-Path $temporaryBase ($temporaryPrefix + [guid]::NewGuid().ToString('N'))
$templateUrl = 'https://github.com/example/model-project-template'
$newRepositoryUrl = 'https://github.com/example/new-product'
$sourceTag = $null
$passes = [System.Collections.Generic.List[string]]::new()
$savedGitEnvironment = @{}
$expectedCodexConfig = "[agents]`nenabled = true`nmax_concurrent_threads_per_session = 3`ninterrupt_message = true`n`n[mcp_servers.codex_analyst_context7]`nurl = `"https://mcp.context7.com/mcp`"`nenabled = true`nrequired = false`nenabled_tools = [`"resolve-library-id`", `"query-docs`"]`n"

function Assert-TemporaryRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    $leaf = [System.IO.Path]::GetFileName($fullPath)
    if (-not $fullPath.StartsWith($temporaryBase + [System.IO.Path]::DirectorySeparatorChar, $pathComparison) -or
        -not $leaf.StartsWith($temporaryPrefix, [System.StringComparison]::Ordinal)) {
        throw 'Disposable harness root не прошел safety gate.'
    }
    return $fullPath
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    return [System.IO.Path]::GetRelativePath($Root, $FullPath).Replace('\', '/')
}

function Copy-FileExact {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $source = Join-Path $SourceRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Harness source file отсутствует: $RelativePath"
    }
    $destination = Join-Path $DestinationRoot $RelativePath
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::Copy($source, $destination, $false)
}

function Copy-TreeExact {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    New-Item -ItemType Directory -Path $DestinationRoot | Out-Null
    foreach ($directory in (Get-ChildItem -LiteralPath $SourceRoot -Directory -Recurse -Force)) {
        $relative = Get-RelativePath -Root $SourceRoot -FullPath $directory.FullName
        New-Item -ItemType Directory -Path (Join-Path $DestinationRoot $relative) -Force | Out-Null
    }
    foreach ($file in (Get-ChildItem -LiteralPath $SourceRoot -File -Recurse -Force)) {
        $relative = Get-RelativePath -Root $SourceRoot -FullPath $file.FullName
        Copy-FileExact -SourceRoot $SourceRoot -DestinationRoot $DestinationRoot -RelativePath $relative
    }
}

function Assert-ExactContext7Config {
    param(
        [Parameter(Mandatory = $true)][string]$CandidateRoot,
        [Parameter(Mandatory = $true)][string]$Label,
        [string]$ExpectedHash = ''
    )

    $path = Join-Path $CandidateRoot '.codex/config.toml'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "$Label не содержит .codex/config.toml."
    }
    $text = [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n")
    if (($text.TrimEnd("`n") + "`n") -cne $expectedCodexConfig) {
        throw "$Label содержит неразрешенную Context7 MCP configuration."
    }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($ExpectedHash) -and $hash -cne $ExpectedHash) {
        throw "$Label получил неидентичную .codex/config.toml."
    }
    return $hash
}

function Get-GitExecutable {
    $command = Get-Command -Name 'git.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        $command = Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($null -eq $command -or -not (Test-Path -LiteralPath $command.Source -PathType Leaf)) {
        throw 'Git executable не найден.'
    }
    return [System.IO.Path]::GetFullPath([string]$command.Source)
}

function Get-PowerShellExecutable {
    $path = (Get-Process -Id $PID).Path
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'PowerShell executable не найден.'
    }
    return [System.IO.Path]::GetFullPath($path)
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = & $script:gitExe -c "safe.directory=$Root" -c "core.hooksPath=$script:nullDevice" -C $Root @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Disposable Git command failed: $($Arguments[0])"
    }
    return @($output)
}

function Start-ScriptProcess {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:powerShellExe
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Не удалось запустить child PowerShell.' }
        return [pscustomobject]@{
            Process = $process
            StdoutTask = $process.StandardOutput.ReadToEndAsync()
            StderrTask = $process.StandardError.ReadToEndAsync()
        }
    }
    catch {
        $process.Dispose()
        throw
    }
}

function Complete-ScriptProcess {
    param([Parameter(Mandatory = $true)][object]$ActiveProcess)

    $process = $ActiveProcess.Process
    try {
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $ActiveProcess.StdoutTask.GetAwaiter().GetResult()
            Stderr = $ActiveProcess.StderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

function Invoke-ScriptProcess {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $activeProcess = Start-ScriptProcess -ScriptPath $ScriptPath -Arguments $Arguments
    return Complete-ScriptProcess -ActiveProcess $activeProcess
}

function Add-Pass {
    param([Parameter(Mandatory = $true)][string]$Name)
    $passes.Add($Name) | Out-Null
    Write-Host "PASS: $Name"
}

function Get-TreeFingerprint {
    param([Parameter(Mandatory = $true)][string]$Root)

    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($file in (Get-ChildItem -LiteralPath $Root -File -Recurse -Force)) {
        $relative = Get-RelativePath -Root $Root -FullPath $file.FullName
        if ($relative -ceq '.git' -or $relative.StartsWith('.git/', [System.StringComparison]::Ordinal)) { continue }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $rows.Add("$relative|$hash") | Out-Null
    }
    $ordered = $rows.ToArray()
    [array]::Sort($ordered, [System.StringComparer]::Ordinal)
    $payload = $utf8NoBom.GetBytes([string]::Join("`n", $ordered))
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Initialize-FixtureRepository {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Branch
    )

    & $script:gitExe -C $Root init -b $Branch --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось создать disposable Git repository.' }
    Invoke-Git -Root $Root -Arguments @('config', 'user.name', 'Template Harness') | Out-Null
    Invoke-Git -Root $Root -Arguments @('config', 'user.email', 'harness@example.invalid') | Out-Null
    $paths = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | ForEach-Object {
        $relative = Get-RelativePath -Root $Root -FullPath $_.FullName
        if (-not $relative.StartsWith('.git/', [System.StringComparison]::Ordinal)) { $relative }
    })
    Invoke-Git -Root $Root -Arguments (@('add', '--') + $paths) | Out-Null
    Invoke-Git -Root $Root -Arguments @('commit', '--quiet', '-m', 'fixture baseline') | Out-Null
}

function New-ConsumerFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$RemoteUrl = $newRepositoryUrl
    )

    $root = Join-Path $temporaryRoot $Name
    Copy-TreeExact -SourceRoot $script:payloadRoot -DestinationRoot $root
    Initialize-FixtureRepository -Root $root -Branch 'main'
    Invoke-Git -Root $root -Arguments @('remote', 'add', 'origin', $RemoteUrl) | Out-Null
    return $root
}

function Invoke-Initializer {
    param([Parameter(Mandatory = $true)][string]$Root)

    return Invoke-ScriptProcess -ScriptPath (Join-Path $Root 'scripts\initialize-project.ps1') -Arguments @(
        '-FromGitHubTemplate',
        '-ProjectName', 'Harness Product',
        '-ProjectSlug', 'harness-product',
        '-Description', 'Disposable distribution verification.',
        '-Owner', 'harness-owner'
    )
}

function Assert-RejectedWithoutTreeMutation {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $before = Get-TreeFingerprint -Root $Root
    $headBefore = (Invoke-Git -Root $Root -Arguments @('rev-parse', 'HEAD'))[0]
    $remoteBefore = (Invoke-Git -Root $Root -Arguments @('remote', 'get-url', 'origin'))[0]
    $result = Invoke-Initializer -Root $Root
    $after = Get-TreeFingerprint -Root $Root
    $headAfter = (Invoke-Git -Root $Root -Arguments @('rev-parse', 'HEAD'))[0]
    $remoteAfter = (Invoke-Git -Root $Root -Arguments @('remote', 'get-url', 'origin'))[0]
    if ($result.ExitCode -eq 0 -or $before -cne $after -or $headBefore -cne $headAfter -or $remoteBefore -cne $remoteAfter) {
        throw "Negative fixture failed: $Name"
    }
    Add-Pass $Name
}

$gitExe = Get-GitExecutable
$powerShellExe = Get-PowerShellExecutable
$temporaryRoot = Assert-TemporaryRoot -Path $temporaryRoot

try {
    foreach ($entry in @(Get-ChildItem Env: | Where-Object { $_.Name -cmatch '^GIT_' })) {
        $savedGitEnvironment[[string]$entry.Name] = [string]$entry.Value
        [System.Environment]::SetEnvironmentVariable([string]$entry.Name, $null, 'Process')
    }
    [System.Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM', '1', 'Process')
    [System.Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', $nullDevice, 'Process')
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    $manifest = (Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8) | ConvertFrom-Json
    if ($manifest.template_version -isnot [string] -or [string]$manifest.template_version -cnotmatch '^\d+\.\d+\.\d+$') {
        throw 'Harness manifest template_version не является release SemVer.'
    }
    if (@($manifest.portable_files | Where-Object { [string]$_ -ceq '.codex/config.toml' }).Count -ne 1 -or
        @($manifest.source_only_paths | Where-Object { [string]$_ -ceq '.codex/config.toml' }).Count -ne 0) {
        throw 'Manifest должен переносить .codex/config.toml ровно один раз.'
    }
    $sourceConfigHash = Assert-ExactContext7Config -CandidateRoot $repositoryRoot -Label 'Template source'
    $sourceTag = 'v' + [string]$manifest.template_version
    $sourceRoot = Join-Path $temporaryRoot 'source'
    New-Item -ItemType Directory -Path $sourceRoot | Out-Null
    $contractPaths = @($manifest.portable_files) + @($manifest.source_only_paths)
    foreach ($relativePath in ($contractPaths | Sort-Object -Unique)) {
        Copy-FileExact -SourceRoot $repositoryRoot -DestinationRoot $sourceRoot -RelativePath ([string]$relativePath)
    }
    foreach ($relativeDirectory in @($manifest.portable_empty_directories)) {
        New-Item -ItemType Directory -Path (Join-Path $sourceRoot ([string]$relativeDirectory)) -Force | Out-Null
    }
    $null = Assert-ExactContext7Config -CandidateRoot $sourceRoot -Label 'Tagged source fixture' -ExpectedHash $sourceConfigHash
    Initialize-FixtureRepository -Root $sourceRoot -Branch 'source'
    Invoke-Git -Root $sourceRoot -Arguments @('remote', 'add', 'origin', $templateUrl) | Out-Null
    Invoke-Git -Root $sourceRoot -Arguments @('tag', $sourceTag) | Out-Null
    $taggedSourceCommitLines = @(Invoke-Git -Root $sourceRoot -Arguments @('rev-parse', 'HEAD'))
    $taggedSourceCommit = [string]$taggedSourceCommitLines[0]
    $taggedReadmeHash = (Get-FileHash -LiteralPath (Join-Path $sourceRoot 'README.md') -Algorithm SHA256).Hash.ToLowerInvariant()
    Invoke-Git -Root $sourceRoot -Arguments @('checkout', '--quiet', '-b', 'replacement-object-fixture') | Out-Null
    [System.IO.File]::AppendAllText(
        (Join-Path $sourceRoot 'README.md'),
        "`nReplacement object fixture must never reach payload.`n",
        $utf8NoBom
    )
    Invoke-Git -Root $sourceRoot -Arguments @('add', '--', 'README.md') | Out-Null
    Invoke-Git -Root $sourceRoot -Arguments @('commit', '--quiet', '-m', 'replacement object fixture') | Out-Null
    $replacementCommitLines = @(Invoke-Git -Root $sourceRoot -Arguments @('rev-parse', 'HEAD'))
    $replacementCommit = [string]$replacementCommitLines[0]
    Invoke-Git -Root $sourceRoot -Arguments @('checkout', '--quiet', 'source') | Out-Null
    Invoke-Git -Root $sourceRoot -Arguments @('replace', '--force', $taggedSourceCommit, $replacementCommit) | Out-Null

    $payloadRoot = Join-Path $temporaryRoot 'payload'
    $builderResult = Invoke-ScriptProcess -ScriptPath (Join-Path $sourceRoot 'scripts\build-github-template.ps1') -Arguments @(
        '-Destination', $payloadRoot,
        '-SourceTag', $sourceTag,
        '-TemplateRepositoryUrl', $templateUrl
    )
    if ($builderResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $payloadRoot -PathType Container)) {
        throw 'Happy-path consumer build failed.'
    }
    $payloadReadmeHash = (Get-FileHash -LiteralPath (Join-Path $payloadRoot 'README.md') -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($payloadReadmeHash -cne $taggedReadmeHash) {
        throw 'Replacement object affected exact tagged payload provenance.'
    }
    Invoke-Git -Root $sourceRoot -Arguments @('replace', '--delete', $taggedSourceCommit) | Out-Null
    $null = Assert-ExactContext7Config -CandidateRoot $payloadRoot -Label 'Distribution payload' -ExpectedHash $sourceConfigHash
    Add-Pass 'exact raw tagged source builds DistributionTemplate payload'

    $concurrentDriftTarget = Join-Path $temporaryRoot 'concurrent-drift-build'
    $primaryReadmePath = Join-Path $sourceRoot 'README.md'
    $primaryReadmeBytes = [System.IO.File]::ReadAllBytes($primaryReadmePath)
    $activeDriftBuild = Start-ScriptProcess -ScriptPath (Join-Path $sourceRoot 'scripts\build-github-template.ps1') -Arguments @(
        '-Destination', $concurrentDriftTarget,
        '-SourceTag', $sourceTag,
        '-TemplateRepositoryUrl', $templateUrl
    )
    $driftBuildResult = $null
    $mutationApplied = $false
    try {
        $snapshotDeadline = [DateTime]::UtcNow.AddSeconds(30)
        while ([DateTime]::UtcNow -lt $snapshotDeadline) {
            $snapshotMarkers = @(Get-ChildItem -LiteralPath $temporaryRoot -Directory -Force | Where-Object {
                $_.Name -cmatch '^\.codex-github-template-snapshot-[0-9a-f]{32}$'
            })
            if ($snapshotMarkers.Count -eq 1) {
                [System.IO.File]::AppendAllText($primaryReadmePath, "`nConcurrent source drift fixture.`n", $utf8NoBom)
                $mutationApplied = $true
                break
            }
            if ($activeDriftBuild.Process.HasExited) { break }
            Start-Sleep -Milliseconds 10
        }
        if (-not $mutationApplied) {
            $driftBuildResult = Complete-ScriptProcess -ActiveProcess $activeDriftBuild
            $activeDriftBuild = $null
            throw "Concurrent drift fixture did not observe snapshot marker: exit=$($driftBuildResult.ExitCode)"
        }
        $driftBuildResult = Complete-ScriptProcess -ActiveProcess $activeDriftBuild
        $activeDriftBuild = $null
    }
    finally {
        [System.IO.File]::WriteAllBytes($primaryReadmePath, $primaryReadmeBytes)
        if ($null -ne $activeDriftBuild) {
            if (-not $activeDriftBuild.Process.HasExited) { $activeDriftBuild.Process.Kill($true) }
            $null = Complete-ScriptProcess -ActiveProcess $activeDriftBuild
        }
    }
    $temporaryBuildArtifacts = @(Get-ChildItem -LiteralPath $temporaryRoot -Directory -Force | Where-Object {
        $_.Name -cmatch '^\.codex-github-template(?:-snapshot)?-[0-9a-f]{32}$'
    })
    $driftDiagnostic = $driftBuildResult.Stdout + "`n" + $driftBuildResult.Stderr
    if ($driftBuildResult.ExitCode -eq 0 -or (Test-Path -LiteralPath $concurrentDriftTarget) -or
        $temporaryBuildArtifacts.Count -ne 0 -or
        -not $driftDiagnostic.Contains('Source HEAD, tag или worktree изменились во время build.')) {
        throw 'Concurrent primary source drift was not rejected with exact temporary cleanup.'
    }
    Add-Pass 'concurrent primary source drift is rejected after snapshot without destination'

    $mutatingIndexerSource = Join-Path $temporaryRoot 'mutating-indexer-source'
    New-Item -ItemType Directory -Path $mutatingIndexerSource | Out-Null
    foreach ($relativePath in ($contractPaths | Sort-Object -Unique)) {
        Copy-FileExact -SourceRoot $repositoryRoot -DestinationRoot $mutatingIndexerSource -RelativePath ([string]$relativePath)
    }
    foreach ($relativeDirectory in @($manifest.portable_empty_directories)) {
        New-Item -ItemType Directory -Path (Join-Path $mutatingIndexerSource ([string]$relativeDirectory)) -Force | Out-Null
    }
    $mutatingPlanIndexer = Join-Path $mutatingIndexerSource 'scripts/update-plan-index.ps1'
    $indexerText = [System.IO.File]::ReadAllText($mutatingPlanIndexer).Replace("`r`n", "`n")
    $indexerAnchor = '$ErrorActionPreference = ''Stop'''
    if ([regex]::Matches($indexerText, [regex]::Escape($indexerAnchor)).Count -ne 1) {
        throw 'Mutating indexer fixture не нашел exact injection anchor.'
    }
    $indexerInjection = @(
        $indexerAnchor,
        '',
        'if ($Mode -ceq ''Write'') {',
        '    $fixtureEncoding = [System.Text.UTF8Encoding]::new($false)',
        '    [System.IO.File]::AppendAllText((Join-Path $Root ''README.md''), "`nIndexer staging mutation fixture.`n", $fixtureEncoding)',
        '}'
    ) -join "`n"
    [System.IO.File]::WriteAllText(
        $mutatingPlanIndexer,
        $indexerText.Replace($indexerAnchor, $indexerInjection),
        $utf8NoBom
    )
    Initialize-FixtureRepository -Root $mutatingIndexerSource -Branch 'source'
    Invoke-Git -Root $mutatingIndexerSource -Arguments @('remote', 'add', 'origin', $templateUrl) | Out-Null
    Invoke-Git -Root $mutatingIndexerSource -Arguments @('tag', $sourceTag) | Out-Null
    $mutatingIndexerTarget = Join-Path $temporaryRoot 'mutating-indexer-build'
    $mutatingIndexerBuild = Invoke-ScriptProcess `
        -ScriptPath (Join-Path $mutatingIndexerSource 'scripts\build-github-template.ps1') `
        -Arguments @(
            '-Destination', $mutatingIndexerTarget,
            '-SourceTag', $sourceTag,
            '-TemplateRepositoryUrl', $templateUrl
        )
    $mutatingBuildArtifacts = @(Get-ChildItem -LiteralPath $temporaryRoot -Directory -Force | Where-Object {
        $_.Name -cmatch '^\.codex-github-template(?:-snapshot)?-[0-9a-f]{32}$'
    })
    $mutatingIndexerDiagnostic = $mutatingIndexerBuild.Stdout + "`n" + $mutatingIndexerBuild.Stderr
    if ($mutatingIndexerBuild.ExitCode -eq 0 -or (Test-Path -LiteralPath $mutatingIndexerTarget) -or
        $mutatingBuildArtifacts.Count -ne 0 -or
        -not $mutatingIndexerDiagnostic.Contains('Manifest file не совпадает с blob tagged source commit: README.md')) {
        throw 'Tagged indexer staging mutation was not rejected with exact temporary cleanup.'
    }
    Add-Pass 'tagged indexer cannot mutate non-derived staging payload'

    $roundtripSource = New-ConsumerFixture -Name 'git-roundtrip-source'
    $roundtripClone = Join-Path $temporaryRoot 'git-roundtrip-clone'
    & $gitExe -c "core.hooksPath=$nullDevice" clone --quiet --no-local $roundtripSource $roundtripClone
    if ($LASTEXITCODE -ne 0) { throw 'Git roundtrip clone failed.' }
    $null = Assert-ExactContext7Config -CandidateRoot $roundtripClone -Label 'Git roundtrip clone' -ExpectedHash $sourceConfigHash
    $roundtripVerify = Invoke-ScriptProcess `
        -ScriptPath (Join-Path $roundtripClone 'scripts\verify-structure.ps1') `
        -Arguments @('-Root', $roundtripClone, '-Mode', 'DistributionTemplate')
    $researchMarkerExists = Test-Path -LiteralPath (Join-Path $roundtripClone 'research/runs/.gitkeep') -PathType Leaf
    if ($roundtripVerify.ExitCode -ne 0 -or -not $researchMarkerExists) {
        $safeDiagnostic = (($roundtripVerify.Stdout + "`n" + $roundtripVerify.Stderr).Replace($temporaryRoot, '[temp]')).Trim()
        throw "Git roundtrip failed: verify-exit=$($roundtripVerify.ExitCode), research-marker=$researchMarkerExists, diagnostic=$safeDiagnostic"
    }
    Add-Pass 'committed consumer survives real Git clone with required run roots'

    [System.IO.File]::WriteAllText((Join-Path $sourceRoot 'dirty.txt'), 'dirty', $utf8NoBom)
    $dirtyBuildTarget = Join-Path $temporaryRoot 'dirty-build'
    $dirtyBuild = Invoke-ScriptProcess -ScriptPath (Join-Path $sourceRoot 'scripts\build-github-template.ps1') -Arguments @(
        '-Destination', $dirtyBuildTarget,
        '-SourceTag', $sourceTag,
        '-TemplateRepositoryUrl', $templateUrl
    )
    if ($dirtyBuild.ExitCode -eq 0 -or (Test-Path -LiteralPath $dirtyBuildTarget)) {
        throw 'Dirty source build was not rejected atomically.'
    }
    [System.IO.File]::Delete((Join-Path $sourceRoot 'dirty.txt'))
    Add-Pass 'dirty source build is rejected without destination'

    Invoke-Git -Root $sourceRoot -Arguments @('checkout', '--quiet', '-b', 'main') | Out-Null
    $wrongBranchTarget = Join-Path $temporaryRoot 'wrong-branch-build'
    $wrongBranchBuild = Invoke-ScriptProcess -ScriptPath (Join-Path $sourceRoot 'scripts\build-github-template.ps1') -Arguments @(
        '-Destination', $wrongBranchTarget,
        '-SourceTag', $sourceTag,
        '-TemplateRepositoryUrl', $templateUrl
    )
    if ($wrongBranchBuild.ExitCode -eq 0 -or (Test-Path -LiteralPath $wrongBranchTarget)) {
        throw 'Wrong source branch was not rejected atomically.'
    }
    Invoke-Git -Root $sourceRoot -Arguments @('checkout', '--quiet', 'source') | Out-Null
    Add-Pass 'tagged commit outside source branch is rejected without destination'

    $missingTagTarget = Join-Path $temporaryRoot 'missing-tag-build'
    $missingTagBuild = Invoke-ScriptProcess -ScriptPath (Join-Path $sourceRoot 'scripts\build-github-template.ps1') -Arguments @(
        '-Destination', $missingTagTarget,
        '-SourceTag', 'v9.9.9',
        '-TemplateRepositoryUrl', $templateUrl
    )
    if ($missingTagBuild.ExitCode -eq 0 -or (Test-Path -LiteralPath $missingTagTarget)) {
        throw 'Missing source tag was not rejected atomically.'
    }
    Add-Pass 'missing source tag is rejected without destination'

    $wrongRepositoryTarget = Join-Path $temporaryRoot 'wrong-repository-build'
    $wrongRepositoryBuild = Invoke-ScriptProcess -ScriptPath (Join-Path $sourceRoot 'scripts\build-github-template.ps1') -Arguments @(
        '-Destination', $wrongRepositoryTarget,
        '-SourceTag', $sourceTag,
        '-TemplateRepositoryUrl', 'https://github.com/example/wrong-template'
    )
    if ($wrongRepositoryBuild.ExitCode -eq 0 -or (Test-Path -LiteralPath $wrongRepositoryTarget)) {
        throw 'Mismatched source repository URL was not rejected atomically.'
    }
    Add-Pass 'mismatched source origin identity is rejected without destination'

    $ignoredSourceRoot = Join-Path $temporaryRoot 'ignored-portable-source'
    New-Item -ItemType Directory -Path $ignoredSourceRoot | Out-Null
    foreach ($relativePath in ($contractPaths | Sort-Object -Unique)) {
        Copy-FileExact -SourceRoot $repositoryRoot -DestinationRoot $ignoredSourceRoot -RelativePath ([string]$relativePath)
    }
    foreach ($relativeDirectory in @($manifest.portable_empty_directories)) {
        New-Item -ItemType Directory -Path (Join-Path $ignoredSourceRoot ([string]$relativeDirectory)) -Force | Out-Null
    }
    $ignoredManifestPath = Join-Path $ignoredSourceRoot '.template-manifest.json'
    $ignoredManifest = (Get-Content -Raw -LiteralPath $ignoredManifestPath -Encoding UTF8) | ConvertFrom-Json
    $ignoredManifest.portable_files = @($ignoredManifest.portable_files) + 'ignored-portable.txt'
    [System.IO.File]::WriteAllText(
        $ignoredManifestPath,
        (($ignoredManifest | ConvertTo-Json -Depth 8) + "`n"),
        $utf8NoBom
    )
    [System.IO.File]::AppendAllText((Join-Path $ignoredSourceRoot '.gitignore'), "`n/ignored-portable.txt`n", $utf8NoBom)
    Initialize-FixtureRepository -Root $ignoredSourceRoot -Branch 'source'
    Invoke-Git -Root $ignoredSourceRoot -Arguments @('remote', 'add', 'origin', $templateUrl) | Out-Null
    Invoke-Git -Root $ignoredSourceRoot -Arguments @('tag', $sourceTag) | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $ignoredSourceRoot 'ignored-portable.txt'), 'not present in tag', $utf8NoBom)
    $ignoredPortableTarget = Join-Path $temporaryRoot 'ignored-portable-build'
    $ignoredPortableBuild = Invoke-ScriptProcess -ScriptPath (Join-Path $ignoredSourceRoot 'scripts\build-github-template.ps1') -Arguments @(
        '-Destination', $ignoredPortableTarget,
        '-SourceTag', $sourceTag,
        '-TemplateRepositoryUrl', $templateUrl
    )
    if ($ignoredPortableBuild.ExitCode -eq 0 -or (Test-Path -LiteralPath $ignoredPortableTarget)) {
        throw 'Ignored untracked portable file was not rejected atomically.'
    }
    Add-Pass 'ignored untracked manifest file is rejected without destination'

    $happyRoot = New-ConsumerFixture -Name 'happy'
    $null = Assert-ExactContext7Config -CandidateRoot $happyRoot -Label 'GitHub Template consumer' -ExpectedHash $sourceConfigHash
    $headBefore = (Invoke-Git -Root $happyRoot -Arguments @('rev-parse', 'HEAD'))[0]
    $remoteBefore = (Invoke-Git -Root $happyRoot -Arguments @('remote', 'get-url', 'origin'))[0]
    $happyResult = Invoke-Initializer -Root $happyRoot
    if ($happyResult.ExitCode -ne 0) { throw 'GitHub-style initializer happy path failed.' }
    $null = Assert-ExactContext7Config -CandidateRoot $happyRoot -Label 'Initialized GitHub Template consumer' -ExpectedHash $sourceConfigHash
    $headAfter = (Invoke-Git -Root $happyRoot -Arguments @('rev-parse', 'HEAD'))[0]
    $remoteAfter = (Invoke-Git -Root $happyRoot -Arguments @('remote', 'get-url', 'origin'))[0]
    $commitCount = (Invoke-Git -Root $happyRoot -Arguments @('rev-list', '--count', 'HEAD'))[0]
    if ($headBefore -cne $headAfter -or $remoteBefore -cne $remoteAfter -or $commitCount -cne '1' -or
        (Test-Path -LiteralPath (Join-Path $happyRoot 'LICENSE')) -or
        -not (Test-Path -LiteralPath (Join-Path $happyRoot 'TEMPLATE-LICENSE.md') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $happyRoot 'TEMPLATE-ORIGIN.md') -PathType Leaf)) {
        throw 'GitHub-style initializer changed Git history/remote or violated license boundary.'
    }
    $generatedReadme = [System.IO.File]::ReadAllText((Join-Path $happyRoot 'README.md'))
    if (-not $generatedReadme.Contains('## Первый рабочий цикл') -or
        -not $generatedReadme.Contains('Работай с текущим локальным проектом, созданным из Codex Analyst Template.') -or
        $generatedReadme.Contains('## Как владельцу выпустить GitHub Template') -or
        $generatedReadme.Contains('build-github-template.ps1')) {
        throw 'Generated README не соответствует usage-only contract.'
    }
    Add-Pass 'GitHub-style initialization preserves HEAD and remote'
    Assert-RejectedWithoutTreeMutation -Name 'repeat initialization is rejected' -Root $happyRoot

    $canonicalRoot = New-ConsumerFixture -Name 'canonical' -RemoteUrl $templateUrl
    Assert-RejectedWithoutTreeMutation -Name 'canonical template remote is rejected' -Root $canonicalRoot

    $sourceRefRoot = New-ConsumerFixture -Name 'source-ref'
    Invoke-Git -Root $sourceRefRoot -Arguments @('branch', 'source') | Out-Null
    Assert-RejectedWithoutTreeMutation -Name 'source branch is rejected' -Root $sourceRefRoot

    $singleBranchRoot = New-ConsumerFixture -Name 'single-branch'
    Invoke-Git -Root $singleBranchRoot -Arguments @('config', '--replace-all', 'remote.origin.fetch', '+refs/heads/main:refs/remotes/origin/main') | Out-Null
    Assert-RejectedWithoutTreeMutation -Name 'single-branch fetch specification is rejected' -Root $singleBranchRoot

    $dirtyRoot = New-ConsumerFixture -Name 'dirty'
    [System.IO.File]::WriteAllText((Join-Path $dirtyRoot 'dirty.txt'), 'dirty', $utf8NoBom)
    Assert-RejectedWithoutTreeMutation -Name 'dirty consumer worktree is rejected' -Root $dirtyRoot

    $driftRoot = New-ConsumerFixture -Name 'descriptor-drift'
    [System.IO.File]::AppendAllText((Join-Path $driftRoot 'README.md'), "`nDescriptor drift fixture.`n", $utf8NoBom)
    Invoke-Git -Root $driftRoot -Arguments @('add', '--', 'README.md') | Out-Null
    Invoke-Git -Root $driftRoot -Arguments @('commit', '--quiet', '-m', 'tamper payload') | Out-Null
    Assert-RejectedWithoutTreeMutation -Name 'descriptor payload drift is rejected' -Root $driftRoot

    $context7DriftRoot = New-ConsumerFixture -Name 'context7-config-drift'
    [System.IO.File]::AppendAllText((Join-Path $context7DriftRoot '.codex/config.toml'), "`n[mcp_servers.other]`nenabled = true`n", $utf8NoBom)
    Invoke-Git -Root $context7DriftRoot -Arguments @('add', '--', '.codex/config.toml') | Out-Null
    Invoke-Git -Root $context7DriftRoot -Arguments @('commit', '--quiet', '-m', 'tamper Context7 contract') | Out-Null
    Assert-RejectedWithoutTreeMutation -Name 'Context7 descriptor drift is rejected' -Root $context7DriftRoot

    Write-Host "PASS: GitHub Template distribution harness завершен, checks=$($passes.Count)."
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        $safeRoot = Assert-TemporaryRoot -Path $temporaryRoot
        Remove-Item -LiteralPath $safeRoot -Recurse -Force
    }
    foreach ($entry in @(Get-ChildItem Env: | Where-Object { $_.Name -cmatch '^GIT_' })) {
        [System.Environment]::SetEnvironmentVariable([string]$entry.Name, $null, 'Process')
    }
    foreach ($name in $savedGitEnvironment.Keys) {
        [System.Environment]::SetEnvironmentVariable([string]$name, [string]$savedGitEnvironment[$name], 'Process')
    }
}
