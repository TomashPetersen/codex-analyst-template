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

function Invoke-ScriptProcess {
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
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdoutTask.GetAwaiter().GetResult()
            Stderr = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
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
    Initialize-FixtureRepository -Root $sourceRoot -Branch 'source'
    Invoke-Git -Root $sourceRoot -Arguments @('remote', 'add', 'origin', $templateUrl) | Out-Null
    Invoke-Git -Root $sourceRoot -Arguments @('tag', $sourceTag) | Out-Null

    $payloadRoot = Join-Path $temporaryRoot 'payload'
    $builderResult = Invoke-ScriptProcess -ScriptPath (Join-Path $sourceRoot 'scripts\build-github-template.ps1') -Arguments @(
        '-Destination', $payloadRoot,
        '-SourceTag', $sourceTag,
        '-TemplateRepositoryUrl', $templateUrl
    )
    if ($builderResult.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $payloadRoot -PathType Container)) {
        throw 'Happy-path consumer build failed.'
    }
    Add-Pass 'exact tagged source builds DistributionTemplate payload'

    $roundtripSource = New-ConsumerFixture -Name 'git-roundtrip-source'
    $roundtripClone = Join-Path $temporaryRoot 'git-roundtrip-clone'
    & $gitExe -c "core.hooksPath=$nullDevice" clone --quiet --no-local $roundtripSource $roundtripClone
    if ($LASTEXITCODE -ne 0) { throw 'Git roundtrip clone failed.' }
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
    $headBefore = (Invoke-Git -Root $happyRoot -Arguments @('rev-parse', 'HEAD'))[0]
    $remoteBefore = (Invoke-Git -Root $happyRoot -Arguments @('remote', 'get-url', 'origin'))[0]
    $happyResult = Invoke-Initializer -Root $happyRoot
    if ($happyResult.ExitCode -ne 0) { throw 'GitHub-style initializer happy path failed.' }
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
