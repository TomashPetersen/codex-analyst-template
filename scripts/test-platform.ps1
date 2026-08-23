[CmdletBinding()]
param([string]$Root = '')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$sourceRoot = if ([string]::IsNullOrWhiteSpace($Root)) { Split-Path -Parent $PSScriptRoot } else { [System.IO.Path]::GetFullPath($Root) }
$modulePath = Join-Path $sourceRoot 'scripts/lib/ModelProject.Platform.psm1'
Import-Module $modulePath -Force

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]'\/')
$tempComparison = Get-ModelProjectPathComparison -Path $tempBase
$fixtureRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('model-project-platform-' + [guid]::NewGuid().ToString('N'))))
$linkPath = $null
$trustedAppLinkPath = $null
$lockPath = $null

function Assert-Blocked {
    param([Parameter(Mandatory = $true)][scriptblock]$Action, [Parameter(Mandatory = $true)][string]$Label)
    $blocked = $false
    try { & $Action }
    catch { $blocked = $true }
    if (-not $blocked) { throw "$Label не был заблокирован." }
}

try {
    if (-not $fixtureRoot.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, $tempComparison) -or
        [System.IO.Path]::GetFileName($fixtureRoot) -cnotmatch '^model-project-platform-[a-f0-9]{32}$') {
        throw 'Unsafe platform fixture root.'
    }
    [void][System.IO.Directory]::CreateDirectory($fixtureRoot)
    $inside = Join-Path $fixtureRoot 'inside'
    [void][System.IO.Directory]::CreateDirectory($inside)
    $sibling = Join-Path (Split-Path -Parent $fixtureRoot) ([System.IO.Path]::GetFileName($fixtureRoot) + '-sibling')
    if (-not (Test-ModelProjectPathWithinRoot -Root $fixtureRoot -Path $inside) -or
        (Test-ModelProjectPathWithinRoot -Root $fixtureRoot -Path $sibling)) {
        throw 'Path containment semantics нарушены.'
    }

    $comparison = Get-ModelProjectPathComparison -Path $fixtureRoot
    if ((Test-ModelProjectIsWindows) -and $comparison -ne [System.StringComparison]::OrdinalIgnoreCase) {
        throw 'Windows filesystem comparison должен быть OrdinalIgnoreCase.'
    }
    $caseProbe = Join-Path $fixtureRoot 'CaseProbe.txt'
    [System.IO.File]::WriteAllText($caseProbe, "probe`n", $utf8NoBom)
    $caseVariant = Join-Path $fixtureRoot 'caseProbe.txt'
    $variantExists = Test-Path -LiteralPath $caseVariant
    if (($comparison -eq [System.StringComparison]::OrdinalIgnoreCase) -ne $variantExists) {
        throw 'Filesystem case semantics определены неверно.'
    }

    $target = Join-Path $fixtureRoot 'link-target'
    [void][System.IO.Directory]::CreateDirectory($target)
    $linkPath = Join-Path $fixtureRoot 'link-path'
    $linkCreated = $false
    try {
        [void](New-Item -ItemType SymbolicLink -Path $linkPath -Target $target -ErrorAction Stop)
        $linkCreated = $true
    }
    catch {
        if (Test-ModelProjectIsWindows) {
            try {
                [void](New-Item -ItemType Junction -Path $linkPath -Target $target -ErrorAction Stop)
                $linkCreated = $true
            }
            catch { }
        }
    }
    if ($linkCreated) {
        $linkedChild = Join-Path $linkPath 'child.txt'
        if ($null -eq (Get-ModelProjectLinkInFullChain -Path $linkedChild)) {
            throw 'Symlink/reparse chain не обнаружен.'
        }
        Assert-Blocked -Label 'Assert no-link' -Action { Assert-ModelProjectNoLinkInFullChain -Path $linkedChild }
        [System.IO.Directory]::Delete($linkPath, $false)
        $linkPath = $null
    }
    elseif (-not (Test-ModelProjectIsWindows)) {
        throw 'Unix platform должна поддерживать symlink fixture.'
    }

    $nullDevice = Get-ModelProjectNullDevice
    if ((Test-ModelProjectIsWindows) -and $nullDevice -cne 'NUL') { throw 'Windows null device неверен.' }
    if (-not (Test-ModelProjectIsWindows) -and $nullDevice -cne '/dev/null') { throw 'Unix null device неверен.' }

    $pwsh = Get-ModelProjectPowerShellHost -ControlledRoots @($sourceRoot, $fixtureRoot)
    $git = Get-ModelProjectGitExecutable -ControlledRoots @($sourceRoot, $fixtureRoot)
    $trustedAppLinkLeaf = 'trusted-' + [System.IO.Path]::GetFileName($pwsh)
    $trustedAppLinkPath = Join-Path $fixtureRoot $trustedAppLinkLeaf
    $trustedAppLinkCreated = $false
    try {
        [void](New-Item -ItemType SymbolicLink -Path $trustedAppLinkPath -Target $pwsh -ErrorAction Stop)
        $trustedAppLinkCreated = $true
    }
    catch { }
    if ($trustedAppLinkCreated) {
        $trustedApp = Get-ModelProjectTrustedApplication `
            -Names @($trustedAppLinkPath) `
            -AllowedLeaves @($trustedAppLinkLeaf, [System.IO.Path]::GetFileName($pwsh)) `
            -ControlledRoots @($sourceRoot)
        if (([System.IO.Path]::GetFullPath($trustedApp)) -cne ([System.IO.Path]::GetFullPath($pwsh))) {
            throw 'Trusted application symlink не разрешен до конечного target.'
        }
        [System.IO.File]::Delete($trustedAppLinkPath)
        $trustedAppLinkPath = $null
    }
    elseif (-not (Test-ModelProjectIsWindows)) {
        throw 'Unix platform должна поддерживать trusted application symlink fixture.'
    }
    $probe = 'argument with spaces "quotes" and \slashes'
    $argumentProbeScript = Join-Path $fixtureRoot 'argument-probe.ps1'
    [System.IO.File]::WriteAllText(
        $argumentProbeScript,
        "param([string]`$Value)`n[Console]::Write(`$Value)`n",
        $utf8NoBom
    )
    $processResult = Invoke-ModelProjectProcess -Executable $pwsh -Arguments @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-File', $argumentProbeScript, '-Value', $probe
    )
    if ($processResult.ExitCode -ne 0 -or $processResult.Stdout -cne $probe -or $processResult.LimitExceeded) {
        throw 'ArgumentList process roundtrip failed.'
    }
    $gitResult = Invoke-ModelProjectProcess -Executable $git -Arguments @('--version') -GitEnvironment -MaxLines 10 -MaxCharacters 4096
    if ($gitResult.ExitCode -ne 0 -or $gitResult.Stdout -cnotmatch '^git version ' -or $gitResult.LimitExceeded) {
        throw 'Sanitized Git process failed.'
    }

    $environmentProbe = [System.Diagnostics.ProcessStartInfo]::new().Environment
    $environmentProbe['GIT_DIR'] = 'poison'
    $environmentProbe['GCM_INTERACTIVE'] = 'poison'
    Set-ModelProjectSanitizedGitEnvironment -Environment $environmentProbe
    if ($environmentProbe.ContainsKey('GIT_DIR') -or
        [string]$environmentProbe['GIT_CONFIG_NOSYSTEM'] -cne '1' -or
        [string]$environmentProbe['GIT_CONFIG_GLOBAL'] -cne $nullDevice -or
        [string]$environmentProbe['GIT_CONFIG_SYSTEM'] -cne $nullDevice -or
        [string]$environmentProbe['GIT_TERMINAL_PROMPT'] -cne '0' -or
        [string]$environmentProbe['GCM_INTERACTIVE'] -cne 'Never') {
        throw 'Sanitized Git environment contract нарушен.'
    }

    Assert-ModelProjectInputText -Value 'project-owner' -Field Owner -MaxLength 80 -Pattern '^[\p{L}\p{N}][\p{L}\p{N} ._+\-]{0,79}$'
    Assert-Blocked -Label 'CR/LF input' -Action { Assert-ModelProjectInputText -Value "bad`nvalue" -Field Value }
    Assert-Blocked -Label 'NUL input' -Action { Assert-ModelProjectInputText -Value ("bad" + [char]0 + 'value') -Field Value }
    Assert-Blocked -Label 'ANSI input' -Action { Assert-ModelProjectInputText -Value ([char]27 + '[31mred') -Field Value }
    Assert-Blocked -Label 'format-control input' -Action { Assert-ModelProjectInputText -Value ('bad' + [char]0x200B + 'value') -Field Value }
    Assert-Blocked -Label 'overlong input' -Action { Assert-ModelProjectInputText -Value ('a' * 81) -Field Value -MaxLength 80 }

    $resourceKey = 'platform-' + [guid]::NewGuid().ToString('N')
    $lock = Enter-ModelProjectFileLock -RepositoryRoot $fixtureRoot -ResourceKey $resourceKey -TimeoutSeconds 1
    $lockPath = [string]$lock.Path
    try {
        Assert-Blocked -Label 'Concurrent lock' -Action {
            $second = Enter-ModelProjectFileLock -RepositoryRoot $fixtureRoot -ResourceKey $resourceKey -TimeoutSeconds 1
            try { } finally { Exit-ModelProjectFileLock -Lock $second }
        }
    }
    finally { Exit-ModelProjectFileLock -Lock $lock }
    if ($lockPath -notlike (Join-Path ([System.IO.Path]::GetTempPath()) 'model-project-locks/*')) {
        throw 'Lock file находится вне system temp.'
    }
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
        [System.IO.File]::Delete($lockPath)
        $lockPath = $null
    }

    Write-Host "PASS: platform primitives; comparison=$comparison; symlink_fixture=$linkCreated; pwsh=$([System.IO.Path]::GetFileName($pwsh)); git=$([System.IO.Path]::GetFileName($git))."
}
finally {
    if ($null -ne $linkPath -and (Test-Path -LiteralPath $linkPath)) {
        try { [System.IO.Directory]::Delete($linkPath, $false) } catch { }
    }
    if ($null -ne $trustedAppLinkPath -and (Test-Path -LiteralPath $trustedAppLinkPath)) {
        try { [System.IO.File]::Delete($trustedAppLinkPath) } catch { }
    }
    if ($null -ne $lockPath -and (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        try { [System.IO.File]::Delete($lockPath) } catch { }
    }
    if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
        $full = [System.IO.Path]::GetFullPath($fixtureRoot)
        if (-not $full.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, $tempComparison) -or
            [System.IO.Path]::GetFileName($full) -cnotmatch '^model-project-platform-[a-f0-9]{32}$') {
            throw 'Unsafe platform fixture cleanup target.'
        }
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
