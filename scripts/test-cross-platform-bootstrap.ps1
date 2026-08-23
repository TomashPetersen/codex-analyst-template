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
$platformPath = Join-Path $sourceRoot 'scripts/lib/ModelProject.Platform.psm1'
Import-Module $platformPath -Force
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]'\/')
$tempComparison = Get-ModelProjectPathComparison -Path $tempBase
$fixtureRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $tempBase ('model-project-bootstrap-' + [guid]::NewGuid().ToString('N')))
)

function Invoke-CheckedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$WorkingDirectory = '',
        [switch]$Git,
        [int[]]$ExpectedExitCodes = @(0)
    )

    $result = Invoke-ModelProjectProcess `
        -Executable $Executable `
        -Arguments $Arguments `
        -WorkingDirectory $WorkingDirectory `
        -GitEnvironment:$Git `
        -MaxLines 20000 `
        -MaxCharacters 16MB
    if ($result.LimitExceeded -or $result.ExitCode -cnotin $ExpectedExitCodes) {
        $safeOutput = (@($result.Output) | Select-Object -First 20) -join ' | '
        throw "Unexpected child result exit=$($result.ExitCode): $safeOutput"
    }
    return $result
}

function Copy-PortablePayload {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    [void][System.IO.Directory]::CreateDirectory($Destination)
    foreach ($relative in @($Manifest.portable_files | ForEach-Object { [string]$_ })) {
        $source = Join-Path $sourceRoot $relative
        $target = Join-Path $Destination $relative
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            [void][System.IO.Directory]::CreateDirectory($parent)
        }
        [System.IO.File]::Copy($source, $target, $false)
    }
    foreach ($relative in @($Manifest.portable_empty_directories | ForEach-Object { [string]$_ })) {
        [void][System.IO.Directory]::CreateDirectory((Join-Path $Destination $relative))
    }
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

try {
    if (-not $fixtureRoot.StartsWith(
            $tempBase + [System.IO.Path]::DirectorySeparatorChar,
            $tempComparison
        ) -or
        [System.IO.Path]::GetFileName($fixtureRoot) -cnotmatch '^model-project-bootstrap-[a-f0-9]{32}$') {
        throw 'Unsafe bootstrap fixture root.'
    }
    [void][System.IO.Directory]::CreateDirectory($fixtureRoot)
    $pwsh = Get-ModelProjectPowerShellHost -ControlledRoots @($sourceRoot, $fixtureRoot)
    $git = Get-ModelProjectGitExecutable -ControlledRoots @($sourceRoot, $fixtureRoot)
    $newProjectScript = Join-Path $sourceRoot 'scripts/new-project.ps1'

    $localDestination = Join-Path $fixtureRoot 'local-project'
    $localResult = Invoke-CheckedProcess -Executable $pwsh -Arguments @(
        '-NoLogo', '-NoProfile', '-NonInteractive',
        '-File', $newProjectScript,
        '-Destination', $localDestination,
        '-ProjectName', 'Bootstrap Fixture',
        '-ProjectSlug', 'bootstrap-fixture',
        '-Description', 'Cross-platform local copy fixture.'
    )
    $null = $localResult
    $localProject = [System.IO.File]::ReadAllText((Join-Path $localDestination 'PROJECT.md'))
    if ($localProject -cnotmatch '(?m)^repository_kind: generated-project\s*$' -or
        $localProject -cnotmatch '(?m)^project_status: initialized\s*$' -or
        $localProject -cnotmatch '(?m)^- Владелец: `project-owner`\s*$' -or
        -not (Test-Path -LiteralPath (Join-Path $localDestination '.git') -PathType Container)) {
        throw 'Local bootstrap result contract нарушен.'
    }

    $manifest = Get-Content -LiteralPath (Join-Path $sourceRoot '.template-manifest.json') -Raw | ConvertFrom-Json
    $githubDestination = Join-Path $fixtureRoot 'github-project'
    Copy-PortablePayload -Manifest $manifest -Destination $githubDestination
    $githubProjectPath = Join-Path $githubDestination 'PROJECT.md'
    $githubProjectText = [System.IO.File]::ReadAllText($githubProjectPath)
    [System.IO.File]::WriteAllText(
        $githubProjectPath,
        $githubProjectText.Replace('repository_kind: template-source', 'repository_kind: distribution-template'),
        $utf8NoBom
    )

    foreach ($indexer in @(
        'scripts/update-plan-index.ps1',
        'scripts/update-mastery-index.ps1'
    )) {
        $null = Invoke-CheckedProcess -Executable $pwsh -Arguments @(
            '-NoLogo', '-NoProfile', '-NonInteractive',
            '-File', (Join-Path $githubDestination $indexer),
            '-Root', $githubDestination,
            '-Mode', 'Write'
        )
    }
    $hashEntries = @(
        $manifest.portable_files |
            ForEach-Object { [string]$_ } |
            Where-Object { $_ -cne 'TEMPLATE-DISTRIBUTION.json' } |
            Sort-Object |
            ForEach-Object {
                [ordered]@{
                    path = $_
                    sha256 = Get-Sha256Hex -Path (Join-Path $githubDestination $_)
                }
            }
    )
    $descriptor = [ordered]@{
        schema_version = 1
        distribution_kind = 'github-template'
        template_version = [string]$manifest.template_version
        source_tag = 'v' + [string]$manifest.template_version
        source_commit = ('1' * 40)
        template_repository_url = 'https://github.com/example/template-project.git'
        built_at = '2026-08-20T00:00:00Z'
        payload_sha256 = $hashEntries
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $githubDestination 'TEMPLATE-DISTRIBUTION.json'),
        (($descriptor | ConvertTo-Json -Depth 6) + "`n"),
        $utf8NoBom
    )

    $null = Invoke-CheckedProcess -Executable $git -Git -WorkingDirectory $githubDestination -Arguments @('init')
    $null = Invoke-CheckedProcess -Executable $git -Git -WorkingDirectory $githubDestination -Arguments @(
        'symbolic-ref', 'HEAD', 'refs/heads/main'
    )
    $null = Invoke-CheckedProcess -Executable $git -Git -WorkingDirectory $githubDestination -Arguments (
        @('add', '--') + @($manifest.portable_files | ForEach-Object { [string]$_ })
    )
    $null = Invoke-CheckedProcess -Executable $git -Git -WorkingDirectory $githubDestination -Arguments @(
        '-c', 'user.name=fixture-role',
        '-c', 'user.email=fixture@example.invalid',
        'commit', '--quiet', '-m', 'fixture'
    )
    $null = Invoke-CheckedProcess -Executable $git -Git -WorkingDirectory $githubDestination -Arguments @(
        'remote', 'add', 'origin', 'https://github.com/example/generated-project.git'
    )

    $initializer = Join-Path $githubDestination 'scripts/initialize-project.ps1'
    $null = Invoke-CheckedProcess -Executable $pwsh -WorkingDirectory $githubDestination -Arguments @(
        '-NoLogo', '-NoProfile', '-NonInteractive',
        '-File', $initializer,
        '-ProjectName', 'GitHub Fixture',
        '-ProjectSlug', 'github-fixture',
        '-Description', 'Cross-platform GitHub Template fixture.',
        '-FromGitHubTemplate'
    )
    $githubProject = [System.IO.File]::ReadAllText((Join-Path $githubDestination 'PROJECT.md'))
    if ($githubProject -cnotmatch '(?m)^repository_kind: generated-project\s*$' -or
        $githubProject -cnotmatch '(?m)^- Владелец: `project-owner`\s*$' -or
        -not (Test-Path -LiteralPath (Join-Path $githubDestination 'TEMPLATE-ORIGIN.md') -PathType Leaf)) {
        throw 'GitHub Template initialization result contract нарушен.'
    }

    $invalidWrapper = Join-Path $fixtureRoot 'invalid-input-wrapper.ps1'
    [System.IO.File]::WriteAllText(
        $invalidWrapper,
        @'
param([string]$ScriptPath, [string]$Destination, [string]$Case)
$arguments = @{
    Destination = $Destination
    ProjectName = 'Invalid Fixture'
    ProjectSlug = 'invalid-fixture'
    Description = 'Safe description.'
    Owner = 'project-owner'
}
switch ($Case) {
    'newline' { $arguments.ProjectName = "bad`nname" }
    'nul' { $arguments.Description = 'bad' + [char]0 + 'value' }
    'ansi' { $arguments.Owner = [char]27 + '[31mowner' }
    'overlong' { $arguments.Owner = 'a' * 81 }
    default { throw 'Unknown case.' }
}
& $ScriptPath @arguments
'@,
        $utf8NoBom
    )
    foreach ($case in @('newline', 'nul', 'ansi', 'overlong')) {
        $invalidDestination = Join-Path $fixtureRoot "invalid-$case"
        $null = Invoke-CheckedProcess -Executable $pwsh -ExpectedExitCodes @(1) -Arguments @(
            '-NoLogo', '-NoProfile', '-NonInteractive',
            '-File', $invalidWrapper,
            '-ScriptPath', $newProjectScript,
            '-Destination', $invalidDestination,
            '-Case', $case
        )
        if (Test-Path -LiteralPath $invalidDestination) {
            throw "Invalid input '$case' создал destination."
        }
    }

    Write-Host 'PASS: local copy, GitHub Template initialization, default owner and input rejection are cross-platform.'
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
        $full = [System.IO.Path]::GetFullPath($fixtureRoot)
        if (-not $full.StartsWith(
                $tempBase + [System.IO.Path]::DirectorySeparatorChar,
                $tempComparison
            ) -or
            [System.IO.Path]::GetFileName($full) -cnotmatch '^model-project-bootstrap-[a-f0-9]{32}$') {
            throw 'Unsafe bootstrap fixture cleanup target.'
        }
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
