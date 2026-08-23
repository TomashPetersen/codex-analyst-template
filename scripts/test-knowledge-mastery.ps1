[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$repositoryRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$sourceManifestPath = Join-Path $repositoryRoot '.template-manifest.json'
$sourceNewProjectPath = Join-Path $PSScriptRoot 'new-project.ps1'
$temporaryPrefix = 'ModelProjectMasteryHarness-'
$requiredPublicPaths = @(
    'scripts/initialize-project.ps1',
    'scripts/new-project.ps1',
    'scripts/new-knowledge-candidate.ps1',
    'scripts/verify-knowledge.ps1',
    'mastery/INDEX.md',
    'mastery/local/INDEX.md',
    '.agents/skills/startup-researcher/SKILL.md',
    '.agents/skills/startup-researcher/assets/run-template/brief.md',
    '.agents/skills/startup-researcher/assets/run-template/queries.md',
    '.agents/skills/startup-researcher/assets/run-template/evidence.jsonl',
    '.agents/skills/startup-researcher/assets/run-template/candidates.md',
    '.agents/skills/startup-researcher/assets/run-template/red-team.md',
    '.agents/skills/startup-researcher/assets/run-template/decision.md'
)
$requiredSourceOnlyPaths = @(
    'TEMPLATE.md',
    'TEMPLATE-CHANGELOG.md',
    'docs/decisions/2026-08-20-codex-analyst-template-v1.md',
    'plans/2026-08-20-codex-analyst-template-v1.md'
)
$requiredRunTemplateNames = @(
    'brief.md',
    'queries.md',
    'evidence.jsonl',
    'candidates.md',
    'red-team.md',
    'decision.md'
)
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$caseMatrix = [System.Collections.Generic.List[string]]::new()
$harnessParent = $null
$seedRoot = $null

function Get-RelativeHarnessPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    $rootWithSeparator = $Root.TrimEnd([char[]]'\/') + [System.IO.Path]::DirectorySeparatorChar
    $rootUri = [System.Uri]::new($rootWithSeparator)
    $pathUri = [System.Uri]::new($FullPath)
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function Assert-HarnessOwnedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($null -eq $harnessParent) { throw 'Harness parent еще не создан.' }
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    $parent = [System.IO.Path]::GetFullPath($harnessParent).TrimEnd([char[]]'\/')
    if (-not $full.StartsWith($parent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path находится вне harness parent: $full"
    }
}

function Write-FixtureText {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    Assert-HarnessOwnedPath $Root
    $fullPath = Join-Path $Root $RelativePath.Replace('/', '\')
    $parent = Split-Path -Parent $fullPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($fullPath, $Content, $utf8NoBom)
}

function Get-TreeFingerprint {
    param([Parameter(Mandatory = $true)][string]$Root)

    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd([char[]]'\/')
    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($item in (Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force)) {
        $relative = Get-RelativeHarnessPath -Root $resolvedRoot -FullPath $item.FullName
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Hash oracle отказался читать reparse point: $relative"
        }
        if ($item.PSIsContainer) {
            $rows.Add("D|$relative") | Out-Null
            continue
        }
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $rows.Add("F|$relative|$($item.Length)|$hash") | Out-Null
    }
    $ordered = $rows.ToArray()
    [array]::Sort($ordered, [System.StringComparer]::Ordinal)
    $payload = [string]::Join("`n", $ordered)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash($utf8NoBom.GetBytes($payload))
        return ([System.BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-FileHashSnapshot {
    param([Parameter(Mandatory = $true)][string]$Root)

    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd([char[]]'\/')
    $snapshot = @{}
    foreach ($file in (Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Force)) {
        if (($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "File snapshot отказался читать reparse point: $($file.FullName)"
        }
        $relative = Get-RelativeHarnessPath -Root $resolvedRoot -FullPath $file.FullName
        $snapshot[$relative] = '{0}|{1}' -f $file.Length, (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $snapshot
}

function Copy-TreeExact {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Assert-HarnessOwnedPath $Destination
    if (Test-Path -LiteralPath $Destination) { throw "Destination уже существует: $Destination" }
    New-Item -ItemType Directory -Path $Destination | Out-Null
    $resolvedSource = (Resolve-Path -LiteralPath $Source).Path.TrimEnd([char[]]'\/')
    foreach ($item in (Get-ChildItem -LiteralPath $resolvedSource -Recurse -Force)) {
        $relative = Get-RelativeHarnessPath -Root $resolvedSource -FullPath $item.FullName
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Seed содержит reparse point: $relative"
        }
        $target = Join-Path $Destination $relative.Replace('/', '\')
        if ($item.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $target -PathType Container)) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
            }
            continue
        }
        $targetParent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }
        [System.IO.File]::WriteAllBytes($target, [System.IO.File]::ReadAllBytes($item.FullName))
    }
    $sourceHash = Get-TreeFingerprint -Root $resolvedSource
    $destinationHash = Get-TreeFingerprint -Root $Destination
    if ($sourceHash -cne $destinationHash) {
        throw "Seed copy SHA tree mismatch: expected=$sourceHash actual=$destinationHash"
    }
}

function Get-PowerShellExecutable {
    $current = (Get-Process -Id $PID).Path
    if (-not [string]::IsNullOrWhiteSpace($current) -and (Test-Path -LiteralPath $current -PathType Leaf)) {
        return $current
    }
    foreach ($name in @('pwsh', 'powershell')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
    }
    throw 'Не найден PowerShell executable.'
}

function ConvertTo-NativeArgumentString {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    return (($Arguments | ForEach-Object {
        if ($_ -notmatch '[\s"]') { return $_ }
        $escaped = [regex]::Replace($_, '(\\*)"', '$1$1\"')
        $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
        return '"' + $escaped + '"'
    }) -join ' ')
}

function Invoke-ChildProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FileName
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ([System.IO.Path]::GetFileName($FileName) -ieq 'powershell.exe') {
        $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    }
    if ($null -ne $startInfo.ArgumentList) {
        foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    }
    else {
        $startInfo.Arguments = ConvertTo-NativeArgumentString -Arguments $Arguments
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw "Не удалось запустить child process: $FileName" }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdoutTask.GetAwaiter().GetResult()
            Stderr = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally { $process.Dispose() }
}

function Invoke-PowerShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments
    )

    $childArguments = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $ScriptPath
    ) + @($Arguments)
    return Invoke-ChildProcess -FileName (Get-PowerShellExecutable) -Arguments $childArguments
}

function Invoke-PowerShellScriptWithParameterMap {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][hashtable]$Parameters
    )

    $payload = [ordered]@{
        script_path = $ScriptPath
        parameters = $Parameters
    } | ConvertTo-Json -Depth 8 -Compress
    $payloadBase64 = [System.Convert]::ToBase64String($utf8NoBom.GetBytes($payload))
    $bootstrap = @"
`$ErrorActionPreference = 'Stop'
`$payloadJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$payloadBase64'))
`$payload = `$payloadJson | ConvertFrom-Json
`$invokeParameters = @{}
foreach (`$property in `$payload.parameters.PSObject.Properties) {
    `$value = `$property.Value
    if (`$value -is [System.Array]) {
        `$invokeParameters[[string]`$property.Name] = @(`$value | ForEach-Object { [string]`$_ })
    }
    else {
        `$invokeParameters[[string]`$property.Name] = [string]`$value
    }
}
& ([string]`$payload.script_path) @invokeParameters
if (-not `$?) { exit 1 }
"@
    $encodedCommand = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($bootstrap))
    return Invoke-ChildProcess -FileName (Get-PowerShellExecutable) -Arguments @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-OutputFormat',
        'Text',
        '-EncodedCommand',
        $encodedCommand
    )
}

function Assert-PortableManifestSeed {
    if (-not (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf)) {
        throw '.template-manifest.json отсутствует.'
    }
    $manifestText = [System.IO.File]::ReadAllText($sourceManifestPath, $utf8Strict)
    try { $manifest = $manifestText | ConvertFrom-Json }
    catch { throw '.template-manifest.json не является valid JSON.' }
    $portable = @($manifest.portable_files | ForEach-Object { [string]$_ })
    $sourceOnly = @($manifest.source_only_paths | ForEach-Object { [string]$_ })
    foreach ($required in $requiredPublicPaths) {
        if ($portable -cnotcontains $required) {
            throw "Manifest portability preflight: отсутствует $required"
        }
        $absolute = Join-Path $repositoryRoot $required.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
            throw "Manifest portability preflight: source file отсутствует: $required"
        }
    }
    foreach ($required in $requiredSourceOnlyPaths) {
        if ($sourceOnly -cnotcontains $required) {
            throw "Manifest source-only preflight: отсутствует $required"
        }
        if ($portable -ccontains $required) {
            throw "Manifest source-only preflight: path одновременно portable: $required"
        }
        $absolute = Join-Path $repositoryRoot $required.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
            throw "Manifest source-only preflight: source file отсутствует: $required"
        }
    }
    if ($portable -ccontains '.template-version' -or $sourceOnly -ccontains '.template-version' -or
        (Test-Path -LiteralPath (Join-Path $repositoryRoot '.template-version'))) {
        throw 'Manifest source-only preflight: legacy .template-version должен отсутствовать.'
    }

    $assetRoot = Join-Path $repositoryRoot '.agents\skills\startup-researcher\assets\run-template'
    $actualAssetNames = @(Get-ChildItem -LiteralPath $assetRoot -File -Force | ForEach-Object { $_.Name })
    $expectedAssetNames = @($requiredRunTemplateNames)
    [array]::Sort($actualAssetNames, [System.StringComparer]::Ordinal)
    [array]::Sort($expectedAssetNames, [System.StringComparer]::Ordinal)
    if ($actualAssetNames.Count -ne $expectedAssetNames.Count -or
        [string]::Join("`n", $actualAssetNames) -cne [string]::Join("`n", $expectedAssetNames)) {
        throw 'Manifest portability preflight: run-template inventory не равен exact six files.'
    }

    $baselineFiles = @($manifest.mastery_baseline.files)
    if ($baselineFiles.Count -eq 0) { throw 'Manifest portability preflight: mastery baseline пуст.' }
    foreach ($entry in $baselineFiles) {
        $relative = [string]$entry.path
        if ($portable -cnotcontains $relative) {
            throw "Manifest portability preflight: baseline не portable: $relative"
        }
        $absolute = Join-Path $repositoryRoot $relative.Replace('/', '\')
        $actualHash = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -cne ([string]$entry.sha256).ToLowerInvariant()) {
            throw "Manifest portability preflight: baseline SHA mismatch: $relative"
        }
    }
    Write-Host ("PASS portable manifest seed: public={0}, baseline={1}, assets={2}" -f $requiredPublicPaths.Count, $baselineFiles.Count, $actualAssetNames.Count)
    return $manifest
}

function New-PublicGeneratedSeed {
    $result = Invoke-PowerShellScript -ScriptPath $sourceNewProjectPath -Arguments @(
        '-Destination', $seedRoot,
        '-ProjectName', 'Mastery Harness Fixture',
        '-ProjectSlug', 'mastery-harness-fixture',
        '-Description', 'Изолированная проверка mastery knowledge control plane.',
        '-Owner', 'fixture-owner'
    )
    if ($result.ExitCode -ne 0 -or -not [string]::IsNullOrEmpty($result.Stderr)) {
        throw "Public new-project/initializer seed failed: exit=$($result.ExitCode) stdout=$($result.Stdout) stderr=$($result.Stderr)"
    }
    foreach ($relative in $requiredPublicPaths) {
        $copyPath = Join-Path $seedRoot $relative.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $copyPath -PathType Leaf)) {
            throw "Generated seed потерял portable path: $relative"
        }
    }
    foreach ($relative in @($requiredSourceOnlyPaths + '.template-version')) {
        $copyPath = Join-Path $seedRoot $relative.Replace('/', '\')
        if (Test-Path -LiteralPath $copyPath) {
            throw "Generated seed содержит source-only path: $relative"
        }
    }
    $projectText = [System.IO.File]::ReadAllText((Join-Path $seedRoot 'PROJECT.md'), $utf8Strict)
    if ($projectText -notmatch '(?m)^repository_kind: generated-project$' -or
        $projectText -notmatch '(?m)^project_status: initialized$' -or
        $projectText -notmatch '(?m)^knowledge_capture_mode: report-only$') {
        throw 'Public initializer не создал expected initialized/report-only PROJECT.md.'
    }
    $originPath = Join-Path $seedRoot 'TEMPLATE-ORIGIN.md'
    if (-not (Test-Path -LiteralPath $originPath -PathType Leaf)) {
        throw 'Public initializer не создал TEMPLATE-ORIGIN.md.'
    }

    $actualPortableFiles = @(
        Get-ChildItem -LiteralPath $seedRoot -Recurse -File -Force | ForEach-Object {
            Get-RelativeHarnessPath -Root $seedRoot -FullPath $_.FullName
        } | Where-Object {
            $_ -cne 'TEMPLATE-ORIGIN.md' -and -not $_.StartsWith('.git/', [System.StringComparison]::Ordinal)
        }
    )
    $renameMap = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($rename in @($sourceManifest.initialization_renames)) {
        $renameMap.Add([string]$rename.from, [string]$rename.to)
    }
    $expectedPortableFiles = @($sourceManifest.portable_files | ForEach-Object {
        $path = [string]$_
        if ($renameMap.ContainsKey($path)) { $renameMap[$path] }
        else { $path }
    })
    $actualPortableSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $expectedPortableSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($path in $actualPortableFiles) { $actualPortableSet.Add($path) | Out-Null }
    foreach ($path in $expectedPortableFiles) { $expectedPortableSet.Add($path) | Out-Null }
    if ($actualPortableFiles.Count -ne $expectedPortableFiles.Count -or
        -not $actualPortableSet.SetEquals($expectedPortableSet)) {
        $missing = @($expectedPortableFiles | Where-Object { -not $actualPortableSet.Contains($_) })
        $unexpected = @($actualPortableFiles | Where-Object { -not $expectedPortableSet.Contains($_) })
        throw "Generated seed inventory не совпадает с post-init manifest contract: missing=$($missing -join ','); unexpected=$($unexpected -join ',')"
    }
    foreach ($relative in @($sourceManifest.portable_empty_directories | ForEach-Object { [string]$_ })) {
        $emptyDirectory = Join-Path $seedRoot $relative.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $emptyDirectory -PathType Container) -or
            @(Get-ChildItem -LiteralPath $emptyDirectory -Force).Count -ne 0) {
            throw "Generated seed потерял portable empty directory: $relative"
        }
    }
    $gitCommand = Get-Command git -ErrorAction Stop
    $head = Invoke-ChildProcess -FileName $gitCommand.Source -Arguments @('-C', $seedRoot, 'rev-parse', '--verify', 'HEAD')
    if ($head.ExitCode -eq 0) { throw 'Public initializer неожиданно создал Git commit.' }
    Write-Host 'PASS public new-project + initializer seed: initialized/report-only, Git HEAD absent.'
}

function New-CaseRoot {
    param([Parameter(Mandatory = $true)][string]$Name)

    $safeName = [regex]::Replace($Name.ToLowerInvariant(), '[^a-z0-9]+', '-').Trim('-')
    $caseRoot = Join-Path $harnessParent ($safeName + '-' + [guid]::NewGuid().ToString('N'))
    Copy-TreeExact -Source $seedRoot -Destination $caseRoot
    return $caseRoot
}

function Remove-CaseRoot {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    Assert-HarnessOwnedPath $Root
    $resolved = (Resolve-Path -LiteralPath $Root).Path
    if ($resolved -ceq (Resolve-Path -LiteralPath $seedRoot).Path) {
        throw 'Отказ от удаления seed как обычного case root.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}

function Add-CasePass {
    param([Parameter(Mandatory = $true)][string]$Name)
    $passes.Add($Name) | Out-Null
    $caseMatrix.Add("PASS $Name") | Out-Null
    Write-Host "PASS $Name"
}

function Add-CaseFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Message,
        $Result = $null
    )
    $failures.Add("$Name`: $Message") | Out-Null
    $caseMatrix.Add("FAIL $Name") | Out-Null
    Write-Host "FAIL $Name`: $Message"
    if ($null -ne $Result) {
        $stdout = ([string]$Result.Stdout).Trim()
        $stderr = ([string]$Result.Stderr).Trim()
        if (-not [string]::IsNullOrWhiteSpace($stdout)) { Write-Host "  stdout: $stdout" }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Host "  stderr: $stderr" }
    }
}

function Assert-CapturedResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][int]$ExpectedExitCode,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$StdoutPatterns,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$StderrPatterns,
        [switch]$RequireEmptyStdout,
        [switch]$RequireEmptyStderr
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $normalizedStdout = ([string]$Result.Stdout).Replace("`r`n", "`n")
    $normalizedStderr = ([string]$Result.Stderr).Replace("`r`n", "`n")
    if ($Result.ExitCode -ne $ExpectedExitCode) { $issues.Add("exit=$($Result.ExitCode), ожидался $ExpectedExitCode") | Out-Null }
    if ($RequireEmptyStdout -and -not [string]::IsNullOrEmpty($normalizedStdout)) { $issues.Add('stdout должен быть пустым') | Out-Null }
    if ($RequireEmptyStderr -and -not [string]::IsNullOrEmpty($normalizedStderr)) { $issues.Add('stderr должен быть пустым') | Out-Null }
    foreach ($pattern in $StdoutPatterns) {
        if ($normalizedStdout -notmatch $pattern) { $issues.Add("stdout не содержит /$pattern/") | Out-Null }
    }
    foreach ($pattern in $StderrPatterns) {
        if ($normalizedStderr -notmatch $pattern) { $issues.Add("stderr не содержит /$pattern/") | Out-Null }
    }
    return @($issues)
}

function Invoke-Verifier {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$Report
    )
    $arguments = @('-Root', $Root)
    if ($Report) { $arguments += '-Report' }
    return Invoke-PowerShellScript -ScriptPath (Join-Path $Root 'scripts\verify-knowledge.ps1') -Arguments $arguments
}

function Invoke-VerifierCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Arrange,
        [Parameter(Mandatory = $true)][int]$ExpectedExitCode,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$StdoutPatterns,
        [switch]$Report
    )

    $root = $null
    try {
        $root = New-CaseRoot -Name $Name
        & $Arrange $root
        $before = Get-TreeFingerprint -Root $root
        $result = Invoke-Verifier -Root $root -Report:$Report
        $after = Get-TreeFingerprint -Root $root
        $issues = [System.Collections.Generic.List[string]]::new()
        foreach ($issue in (Assert-CapturedResult -Name $Name -Result $result -ExpectedExitCode $ExpectedExitCode -StdoutPatterns $StdoutPatterns -StderrPatterns @() -RequireEmptyStderr)) {
            $issues.Add($issue) | Out-Null
        }
        if ($before -cne $after) { $issues.Add('public verifier изменил SHA tree fixture') | Out-Null }
        if ($ExpectedExitCode -eq 0 -and $result.Stdout -match '(?m)^FAIL:') { $issues.Add('positive case содержит FAIL') | Out-Null }
        if ($ExpectedExitCode -ne 0 -and $result.Stdout -match '(?m)^PASS:') { $issues.Add('negative case содержит PASS') | Out-Null }
        if ($issues.Count -eq 0) { Add-CasePass -Name $Name }
        else { Add-CaseFailure -Name $Name -Message ($issues -join '; ') -Result $result }
    }
    catch { Add-CaseFailure -Name $Name -Message ("harness exception: " + $_.Exception.Message) }
    finally { if ($null -ne $root) { Remove-CaseRoot -Root $root } }
}

function Read-FixtureManifest {
    param([Parameter(Mandatory = $true)][string]$Root)
    $text = [System.IO.File]::ReadAllText((Join-Path $Root '.template-manifest.json'), $utf8Strict)
    return ($text | ConvertFrom-Json)
}

function Write-FixtureManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Manifest
    )
    $json = $Manifest | ConvertTo-Json -Depth 32
    Write-FixtureText -Root $Root -RelativePath '.template-manifest.json' -Content ($json + "`n")
}

function Get-NextPatchVersion {
    param([Parameter(Mandatory = $true)][string]$Version)
    if ($Version -cnotmatch '^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)$') {
        throw "Baseline version не strict SemVer: $Version"
    }
    return '{0}.{1}.{2}' -f $Matches.major, $Matches.minor, ([int]$Matches.patch + 1)
}

function Set-TemplateSourceMode {
    param([Parameter(Mandatory = $true)][string]$Root)
    $path = Join-Path $Root 'PROJECT.md'
    $text = [System.IO.File]::ReadAllText($path, $utf8Strict)
    $text = $text.Replace('repository_kind: generated-project', 'repository_kind: template-source')
    $text = $text.Replace('project_status: initialized', 'project_status: template')
    $text = [regex]::Replace($text, '(?m)^project_id: .+$', 'project_id: ''{{PROJECT_ID}}''')
    $text = $text.Replace('knowledge_capture_mode: report-only', 'knowledge_capture_mode: disabled')
    [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
}

function New-TrustedFixtureHead {
    param([Parameter(Mandatory = $true)][string]$Root)

    Assert-HarnessOwnedPath $Root
    $git = (Get-Command git -ErrorAction Stop).Source
    $commands = @(
        @('-C', $Root, 'config', '--local', 'user.email', 'mastery-harness@example.invalid'),
        @('-C', $Root, 'config', '--local', 'user.name', 'Mastery Harness'),
        @('-C', $Root, 'add', '--', '.template-manifest.json', 'PROJECT.md'),
        @('-C', $Root, 'commit', '-m', 'fixture baseline')
    )
    foreach ($arguments in $commands) {
        $result = Invoke-ChildProcess -FileName $git -Arguments $arguments
        if ($result.ExitCode -ne 0) {
            throw "Git fixture baseline failed: git $($arguments -join ' '): $($result.Stderr)"
        }
    }
    $head = Invoke-ChildProcess -FileName $git -Arguments @('-C', $Root, 'rev-parse', '--verify', 'HEAD')
    if ($head.ExitCode -ne 0 -or $head.Stdout -notmatch '^[0-9a-f]{40,64}\s*$') {
        throw 'Trusted Git baseline commit не создан.'
    }
}

function Set-BaselineMutation {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$BumpVersion,
        [switch]$ChangeFingerprint
    )

    $manifest = Read-FixtureManifest -Root $Root
    if ($BumpVersion) {
        $manifest.mastery_baseline.bundle_version = Get-NextPatchVersion ([string]$manifest.mastery_baseline.bundle_version)
    }
    if ($ChangeFingerprint) {
        $entry = @($manifest.mastery_baseline.files)[0]
        $relative = [string]$entry.path
        $path = Join-Path $Root $relative.Replace('/', '\')
        $content = [System.IO.File]::ReadAllText($path, $utf8Strict)
        [System.IO.File]::WriteAllText($path, $content.TrimEnd() + "`n`n<!-- mastery harness fingerprint change -->`n", $utf8NoBom)
        $entry.sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    Write-FixtureManifest -Root $Root -Manifest $manifest
}

function Add-BaselineIndexDrift {
    param(
        [Parameter(Mandatory = $true)][string]$Root
    )

    $relative = 'mastery/researcher/INDEX.md'
    $path = Join-Path $Root $relative.Replace('/', '\')
    $content = [System.IO.File]::ReadAllText($path, $utf8Strict).TrimEnd()
    [System.IO.File]::WriteAllText(
        $path,
        $content + "`n`n<!-- mastery harness direct INDEX drift -->`n",
        $utf8NoBom
    )
}

function Register-LocalMethod {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$CandidateRelative
    )
    $path = Join-Path $Root 'mastery\local\INDEX.md'
    $text = [System.IO.File]::ReadAllText($path, $utf8Strict).TrimEnd()
    [System.IO.File]::WriteAllText(
        $path,
        $text + "`n`n- [Harness method $FileName]($FileName)`n- [Harness candidate](../../$CandidateRelative)`n",
        $utf8NoBom
    )
}

function Write-LocalMethod {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$MethodId,
        [ValidateSet('active', 'deprecated', 'superseded')][string]$Status = 'active',
        [string]$VerifiedAt = '2026-07-01',
        [string]$ReviewDue = '2099-12-31',
        [AllowNull()][string]$Supersedes = $null,
        [string[]]$AppliesTo = @('planning'),
        [switch]$Register,
        [switch]$MissingMetadata
    )

    $candidateHashBytes = [System.Security.Cryptography.SHA256]::HashData(
        $utf8NoBom.GetBytes("$MethodId|$FileName")
    )
    $candidateSuffix = [Convert]::ToHexString($candidateHashBytes).Substring(0, 8).ToLowerInvariant()
    $candidateId = "KC-20260820-120000-$candidateSuffix"
    $candidateRelative = "knowledge/candidates/2026/$candidateId.md"
    $appliesToYaml = [string]::Join("`n", @($AppliesTo | ForEach-Object { "  - $_" }))
    $summary = "Fixture method $MethodId."
    Write-FixtureText -Root $Root -RelativePath $candidateRelative -Content @"
---
id: '$candidateId'
state: applied
type: method
owner_scope: project
domain: mastery
method_kind: checklist
method_summary: '$summary'
method_applies_to:
$appliesToYaml
claim_key: 'method.$MethodId'
target_ref: 'mastery/local/INDEX.md#зарегистрированные-расширения'
source_refs:
  - PROJECT.md
conflict_refs: []
confidence: high
capture_basis: explicit-user-capture
data_class: internal
created_at: '2026-08-19T00:00:00+00:00'
review_due: '$ReviewDue'
authority_ref: 'user-request:mastery-harness-$candidateSuffix'
applied_at: '2026-08-19T00:00:01+00:00'
dismiss_reason: null
supersedes: null
---

# Fixture method $MethodId

## Основание

Прямая коррекция владельца подтверждает повторяемый fixture method.

## Предлагаемое изменение

Применить один bounded шаг и проверить результат.

## Проверка дублей и противоречий

Совпадающий active method отсутствует.

## Обоснование lifecycle

Candidate применен с прямым authority владельца.
"@

    if ($MissingMetadata) {
        $content = @"
---
method_id: $MethodId
owner_scope: project
---

# Incomplete local method

Fixture intentionally omits required metadata.
"@
    }
    else {
        $supersedesYaml = if ($null -eq $Supersedes) { 'null' } else { $Supersedes }
        $content = @"
---
mastery_contract_version: 2
method_id: $MethodId
method_kind: checklist
summary: '$summary'
owner_scope: project
applies_to:
$appliesToYaml
status: $Status
source_refs:
  - $candidateRelative
verified_at: '$VerifiedAt'
review_due: '$ReviewDue'
supersedes: $supersedesYaml
---

# Local method $MethodId

Use one bounded observation and record the result.
"@
    }
    Write-FixtureText -Root $Root -RelativePath "mastery/local/$FileName" -Content $content
    if ($Register) {
        Register-LocalMethod -Root $Root -FileName $FileName -CandidateRelative $candidateRelative
    }
}

function Write-OverdueResearchRun {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$MethodId,
        [Parameter(Mandatory = $true)][string]$MethodFileName
    )

    $runRelative = 'research/runs/2026-08-01-overdue-method'
    $baselineProfile = 'mastery/researcher/steve-blank.md'
    $baselineMethod = 'mastery/researcher/steve-blank.md#метод-2-hypotheses---experiments---tests---insights'
    Write-FixtureText -Root $Root -RelativePath "$runRelative/brief.md" -Content @"
# Brief

- Основной baseline profile ref: `$baselineProfile`
- Основной baseline method ref: `$baselineMethod`
- Дополняющий baseline profile ref: не применимо
- Дополняющий baseline method ref: `не применимо`
- Local method IDs: [$MethodId]
- Local method refs: [mastery/local/$MethodFileName]
"@
    Write-FixtureText -Root $Root -RelativePath "$runRelative/decision.md" -Content @"
# Decision

- Основной baseline method ref: `$baselineMethod`
- Дополняющий baseline method ref: `не применимо`
- Local method IDs: [$MethodId]
- Local method refs: [mastery/local/$MethodFileName]

## Knowledge outcome

- Основной результат closeout: none
- Central candidate IDs в порядке влияния на решение: []
"@
    Write-FixtureText -Root $Root -RelativePath "$runRelative/queries.md" -Content "# Queries`n`nне применимо: источники не запрашивались.`n"
    Write-FixtureText -Root $Root -RelativePath "$runRelative/evidence.jsonl" -Content ''
    Write-FixtureText -Root $Root -RelativePath "$runRelative/candidates.md" -Content "# Candidates`n`nне применимо: candidates не создавались.`n"
    Write-FixtureText -Root $Root -RelativePath "$runRelative/red-team.md" -Content "# Red team`n`nне применимо: fixture проверяет только overdue method gate.`n"
}

function Write-ComplementaryMismatchResearchRun {
    param([Parameter(Mandatory = $true)][string]$Root)

    $runRelative = 'research/runs/2026-08-01-complementary-mismatch'
    $mainProfile = 'mastery/researcher/steve-blank.md'
    $mainMethod = 'mastery/researcher/steve-blank.md#метод-2-hypotheses---experiments---tests---insights'
    $complementaryMethod = 'mastery/researcher/bill-aulet.md#метод-1-market-segmentation-и-выбор-beachhead'
    Write-FixtureText -Root $Root -RelativePath "$runRelative/brief.md" -Content @"
# Brief

- Основной baseline profile ref: $mainProfile
- Основной baseline method ref: $mainMethod
- Дополняющий baseline profile ref: `не применимо`
- Дополняющий baseline method ref: $complementaryMethod
- Local method IDs: []
- Local method refs: []
"@
    Write-FixtureText -Root $Root -RelativePath "$runRelative/decision.md" -Content @"
# Decision

- Основной baseline method ref: $mainMethod
- Дополняющий baseline method ref: $complementaryMethod
- Local method IDs: []
- Local method refs: []

## Knowledge outcome

- Основной результат closeout: none
- Write intent: none
- Authority ref: null
- Причина ``blocked``: не применимо
- Central candidate IDs в порядке влияния на решение: []
- Затронутый канон: нет
"@
    Write-FixtureText -Root $Root -RelativePath "$runRelative/queries.md" -Content "# Queries`n`nне применимо: fixture не обращается к внешним источникам.`n"
    Write-FixtureText -Root $Root -RelativePath "$runRelative/evidence.jsonl" -Content ''
    Write-FixtureText -Root $Root -RelativePath "$runRelative/candidates.md" -Content "# Candidates`n`nне применимо: candidates не создавались.`n"
    Write-FixtureText -Root $Root -RelativePath "$runRelative/red-team.md" -Content "# Red team`n`nне применимо: fixture проверяет только complementary pair gate.`n"
}

function Add-CanonicalHarnessTarget {
    param([Parameter(Mandatory = $true)][string]$Root)
    Write-FixtureText -Root $Root -RelativePath 'docs/mastery-harness-target.md' -Content "# Mastery harness target`n"
    $indexPath = Join-Path $Root 'INDEX.md'
    $index = [System.IO.File]::ReadAllText($indexPath, $utf8Strict).TrimEnd()
    [System.IO.File]::WriteAllText(
        $indexPath,
        $index + "`n`n- [Mastery harness target](docs/mastery-harness-target.md)`n",
        $utf8NoBom
    )
}

function Invoke-CandidateGenerator {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$CaseId,
        [Parameter(Mandatory = $true)][string]$TargetRef,
        [Parameter(Mandatory = $true)][string[]]$SourceRef
    )

    $generator = Join-Path $Root 'scripts\new-knowledge-candidate.ps1'
    $parameters = @{
        Root = $Root
        Type = 'method'
        Domain = 'mastery'
        ClaimKey = "method.mastery-harness-$CaseId"
        TargetRef = $TargetRef
        SourceRefs = @($SourceRef)
        Confidence = 'high'
        CaptureBasis = 'explicit-user-capture'
        DataClass = 'internal'
        Title = "Mastery harness $CaseId"
        Basis = 'Проверяемый synthetic fixture без чувствительных данных.'
        ProposedChange = 'Зафиксировать безопасный project-local метод.'
        DuplicateCheck = 'Совпадающий claim key отсутствует.'
        MethodKind = 'checklist'
        MethodSummary = 'Проверяемый project-local checklist для fixture.'
        MethodAppliesTo = @('planning')
        ReviewDue = '2099-12-31'
        AuthorityRef = "user-request:mastery-harness-$CaseId"
        WriteIntent = 'explicit-promotion'
    }
    return Invoke-PowerShellScriptWithParameterMap -ScriptPath $generator -Parameters $parameters
}

function Invoke-GeneratorCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$CaseId,
        [Parameter(Mandatory = $true)][string]$TargetRef,
        [Parameter(Mandatory = $true)][string[]]$SourceRef,
        [Parameter(Mandatory = $true)][int]$ExpectedExitCode,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$StdoutPatterns,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$StderrPatterns,
        [switch]$ExpectCandidate
    )

    $root = $null
    try {
        $root = New-CaseRoot -Name $Name
        if ($TargetRef -ceq 'docs/mastery-harness-target.md') { Add-CanonicalHarnessTarget -Root $root }
        $beforeTree = Get-TreeFingerprint -Root $root
        $beforeFiles = Get-FileHashSnapshot -Root $root
        $result = Invoke-CandidateGenerator -Root $root -CaseId $CaseId -TargetRef $TargetRef -SourceRef $SourceRef
        $afterTree = Get-TreeFingerprint -Root $root
        $afterFiles = Get-FileHashSnapshot -Root $root
        $issues = [System.Collections.Generic.List[string]]::new()
        foreach ($issue in (Assert-CapturedResult `
            -Name $Name `
            -Result $result `
            -ExpectedExitCode $ExpectedExitCode `
            -StdoutPatterns $StdoutPatterns `
            -StderrPatterns $StderrPatterns `
            -RequireEmptyStdout:($ExpectedExitCode -ne 0) `
            -RequireEmptyStderr:($ExpectedExitCode -eq 0))) {
            $issues.Add($issue) | Out-Null
        }

        if ($ExpectCandidate) {
            if ($beforeTree -ceq $afterTree) { $issues.Add('generator не изменил tree для expected candidate') | Out-Null }
            $added = @($afterFiles.Keys | Where-Object { -not $beforeFiles.ContainsKey($_) })
            $removed = @($beforeFiles.Keys | Where-Object { -not $afterFiles.ContainsKey($_) })
            $modified = @($beforeFiles.Keys | Where-Object { $afterFiles.ContainsKey($_) -and $beforeFiles[$_] -cne $afterFiles[$_] })
            if ($added.Count -ne 1 -or $added[0] -cnotmatch '^knowledge/candidates/\d{4}/KC-\d{8}-\d{6}-[0-9a-f]{8}\.md$') {
                $issues.Add("generator post-state ожидает ровно один candidate, added=[$($added -join ', ')]") | Out-Null
            }
            if ($removed.Count -ne 0 -or $modified.Count -ne 0) {
                $issues.Add("generator изменил existing files: removed=[$($removed -join ', ')] modified=[$($modified -join ', ')]") | Out-Null
            }
            if ($added.Count -eq 1) {
                $candidatePath = Join-Path $root $added[0].Replace('/', '\')
                $candidateText = [System.IO.File]::ReadAllText($candidatePath, $utf8Strict)
                if ($candidateText -notmatch '(?m)^target_ref:[ \t]+[''\"]?mastery/local/INDEX\.md#зарегистрированные-расширения[''\"]?[ \t]*$') {
                    $issues.Add('candidate target_ref не совпадает с project-local target') | Out-Null
                }
            }
        }
        else {
            if ($beforeTree -cne $afterTree) { $issues.Add('rejected generator изменил SHA tree') | Out-Null }
        }

        $transient = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Where-Object {
            $_.Name -match '(?i)(?:\.tmp|\.draft|\.lock)$'
        })
        if ($transient.Count -gt 0) { $issues.Add('generator оставил temp/draft/lock artifact') | Out-Null }

        $beforeVerify = Get-TreeFingerprint -Root $root
        $verify = Invoke-Verifier -Root $root
        $afterVerify = Get-TreeFingerprint -Root $root
        foreach ($issue in (Assert-CapturedResult `
            -Name "$Name post-verifier" `
            -Result $verify `
            -ExpectedExitCode 0 `
            -StdoutPatterns @('(?m)^PASS: semantic knowledge gate\.\r?$') `
            -StderrPatterns @() `
            -RequireEmptyStderr)) {
            $issues.Add("post-verifier $issue") | Out-Null
        }
        if ($beforeVerify -cne $afterVerify) { $issues.Add('post-verifier изменил SHA tree') | Out-Null }
        if ($issues.Count -eq 0) { Add-CasePass -Name $Name }
        else { Add-CaseFailure -Name $Name -Message ($issues -join '; ') -Result $result }
    }
    catch { Add-CaseFailure -Name $Name -Message ("harness exception: " + $_.Exception.Message) }
    finally { if ($null -ne $root) { Remove-CaseRoot -Root $root } }
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$seedFingerprint = ''
try {
    $sourceManifest = Assert-PortableManifestSeed
    $tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]'\/')
    $harnessParent = Join-Path $tempParent ($temporaryPrefix + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $harnessParent | Out-Null
    $seedRoot = Join-Path $harnessParent 'seed'
    New-PublicGeneratedSeed
    $seedFingerprint = Get-TreeFingerprint -Root $seedRoot

    Invoke-VerifierCase -Name 'A65 current mastery baseline passes' -ExpectedExitCode 0 -StdoutPatterns @(
        '(?m)^PASS: semantic knowledge gate\.\r?$'
    ) -Arrange { param($root) }

    Invoke-VerifierCase -Name 'A66 baseline fingerprint change without version bump blocks' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?i)Mastery baseline fingerprint'
    ) -Arrange {
        param($root)
        Set-TemplateSourceMode -Root $root
        New-TrustedFixtureHead -Root $root
        Set-BaselineMutation -Root $root -ChangeFingerprint
    }

    Invoke-VerifierCase -Name 'A67 fake baseline version bump blocks' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?i)version-only bump'
    ) -Arrange {
        param($root)
        Set-TemplateSourceMode -Root $root
        New-TrustedFixtureHead -Root $root
        Set-BaselineMutation -Root $root -BumpVersion
    }

    Invoke-VerifierCase -Name 'A68 matching baseline fingerprint and version bump passes' -ExpectedExitCode 0 -StdoutPatterns @(
        '(?m)^PASS: semantic knowledge gate\.\r?$'
    ) -Arrange {
        param($root)
        Set-TemplateSourceMode -Root $root
        New-TrustedFixtureHead -Root $root
        Set-BaselineMutation -Root $root -BumpVersion -ChangeFingerprint
    }

    Invoke-VerifierCase -Name 'A69 generated baseline INDEX hash drift blocks without manifest update' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?m)^- Mastery baseline drift: mastery/researcher/INDEX\.md '
    ) -Arrange {
        param($root)
        $manifestPath = Join-Path $root '.template-manifest.json'
        $manifestHashBefore = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
        Add-BaselineIndexDrift -Root $root
        $manifestHashAfter = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
        if ($manifestHashBefore -cne $manifestHashAfter) {
            throw 'A69 oracle: baseline INDEX drift не должен изменять manifest.'
        }
    }

    Invoke-VerifierCase -Name 'A69 traversal in analyst baseline path blocks' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?i)traversal или недопустимый относительный путь'
    ) -Arrange {
        param($root)
        $manifest = Read-FixtureManifest -Root $root
        $manifest.mastery_baseline.files[0].path = 'mastery/analyst/../researcher/INDEX.md'
        Write-FixtureManifest -Root $root -Manifest $manifest
    }

    Invoke-VerifierCase -Name 'A69 unknown baseline root blocks' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?i)unsafe mastery baseline path'
    ) -Arrange {
        param($root)
        $manifest = Read-FixtureManifest -Root $root
        $manifest.mastery_baseline.files[0].path = 'mastery/unknown/INDEX.md'
        Write-FixtureManifest -Root $root -Manifest $manifest
    }

    Invoke-VerifierCase -Name 'A70 unregistered local mastery file blocks' -ExpectedExitCode 1 -Report -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?m)^  - unregistered local: mastery/local/unregistered\.md$'
    ) -Arrange {
        param($root)
        Write-LocalMethod -Root $root -FileName 'unregistered.md' -MethodId 'fixture-unregistered-method'
    }

    Invoke-VerifierCase -Name 'A71 local mastery missing metadata blocks' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?m)^- mastery/local/missing-metadata\.md:.*''applies_to''\.$'
    ) -Arrange {
        param($root)
        Write-LocalMethod -Root $root -FileName 'missing-metadata.md' -MethodId 'fixture-missing-metadata' -Register -MissingMetadata
    }

    Invoke-VerifierCase -Name 'A72 duplicate local method ID blocks' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?i)Duplicate local method_id'
    ) -Arrange {
        param($root)
        Write-LocalMethod -Root $root -FileName 'duplicate-one.md' -MethodId 'fixture-duplicate-method' -Register
        Write-LocalMethod -Root $root -FileName 'duplicate-two.md' -MethodId 'fixture-duplicate-method' -Register
    }

    Invoke-VerifierCase -Name 'A73 cyclic local supersedes blocks' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?i)local-mastery-supersedes-cycle'
    ) -Arrange {
        param($root)
        Write-LocalMethod -Root $root -FileName 'cycle-one.md' -MethodId 'fixture-cycle-one' -Status superseded -Supersedes 'fixture-cycle-two' -Register
        Write-LocalMethod -Root $root -FileName 'cycle-two.md' -MethodId 'fixture-cycle-two' -Status superseded -Supersedes 'fixture-cycle-one' -Register
    }

    Invoke-VerifierCase -Name 'A74 valid local extension passes' -ExpectedExitCode 0 -StdoutPatterns @(
        '(?m)^PASS: semantic knowledge gate\.\r?$'
    ) -Arrange {
        param($root)
        $verified = [datetime]::Today.AddDays(-1).ToString('yyyy-MM-dd')
        $due = [datetime]::Today.AddYears(1).ToString('yyyy-MM-dd')
        Write-LocalMethod -Root $root -FileName 'fixture-valid-method.md' -MethodId 'fixture-valid-method' -VerifiedAt $verified -ReviewDue $due -Register
    }

    Invoke-VerifierCase -Name 'A74 all catalog applies_to intents pass' -ExpectedExitCode 0 -StdoutPatterns @(
        '(?m)^PASS: semantic knowledge gate\.\r?$'
    ) -Arrange {
        param($root)
        $catalog = Get-Content -LiteralPath (Join-Path $root 'mastery/INTENTS.json') -Raw | ConvertFrom-Json
        $catalogIntents = @($catalog.intents | ForEach-Object { [string]$_.id })
        Write-LocalMethod -Root $root -FileName 'fixture-all-intents.md' -MethodId 'fixture-all-intents' -AppliesTo $catalogIntents -Register
    }

    Invoke-VerifierCase -Name 'A74 near-miss catalog applies_to intent blocks' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        "(?i)unknown applies_to 'planning-near-miss'"
    ) -Arrange {
        param($root)
        Write-LocalMethod -Root $root -FileName 'fixture-near-miss.md' -MethodId 'fixture-near-miss' -AppliesTo @('planning-near-miss') -Register
    }

    Invoke-VerifierCase -Name 'A74 one-way local replacement passes' -ExpectedExitCode 0 -StdoutPatterns @(
        '(?m)^PASS: semantic knowledge gate\.\r?$'
    ) -Arrange {
        param($root)
        Write-LocalMethod -Root $root -FileName 'fixture-method-v1.md' -MethodId 'fixture-method-v1' -Status superseded -Register
        Write-LocalMethod -Root $root -FileName 'fixture-method-v2.md' -MethodId 'fixture-method-v2' -Status active -Supersedes 'fixture-method-v1' -Register
    }

    Invoke-VerifierCase -Name 'A74 one-way local replacement chain passes' -ExpectedExitCode 0 -StdoutPatterns @(
        '(?m)^PASS: semantic knowledge gate\.\r?$'
    ) -Arrange {
        param($root)
        Write-LocalMethod -Root $root -FileName 'fixture-chain-v1.md' -MethodId 'fixture-chain-v1' -Status superseded -Register
        Write-LocalMethod -Root $root -FileName 'fixture-chain-v2.md' -MethodId 'fixture-chain-v2' -Status superseded -Supersedes 'fixture-chain-v1' -Register
        Write-LocalMethod -Root $root -FileName 'fixture-chain-v3.md' -MethodId 'fixture-chain-v3' -Status active -Supersedes 'fixture-chain-v2' -Register
    }

    Invoke-VerifierCase -Name 'A74 superseded method without replacement blocks' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?i)superseded method требует incoming replacement edge\.'
    ) -Arrange {
        param($root)
        Write-LocalMethod -Root $root -FileName 'orphan.md' -MethodId 'fixture-orphan-superseded' -Status superseded -Register
    }

    Invoke-VerifierCase -Name 'A74 supersedes target must be superseded' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?i)supersedes target должен иметь status superseded'
    ) -Arrange {
        param($root)
        Write-LocalMethod -Root $root -FileName 'still-active.md' -MethodId 'fixture-still-active' -Status active -Register
        Write-LocalMethod -Root $root -FileName 'replacement.md' -MethodId 'fixture-replacement' -Status active -Supersedes 'fixture-still-active' -Register
    }

    Invoke-VerifierCase -Name 'A74 complementary profile and method applicability mismatch blocks' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?m)^- research/runs/2026-08-01-complementary-mismatch: complementary baseline profile .+ method ref .+$'
    ) -Arrange {
        param($root)
        Write-ComplementaryMismatchResearchRun -Root $root
    }

    Invoke-VerifierCase -Name 'A75 overdue local extension appears in report' -ExpectedExitCode 0 -Report -StdoutPatterns @(
        '(?m)^- overdue: 2$',
        '(?m)^  - mastery/local/fixture-overdue-method\.md -> \d{4}-\d{2}-\d{2}$',
        '(?m)^PASS: semantic knowledge gate\.\r?$'
    ) -Arrange {
        param($root)
        $verified = [datetime]::Today.AddDays(-10).ToString('yyyy-MM-dd')
        $due = [datetime]::Today.AddDays(-1).ToString('yyyy-MM-dd')
        Write-LocalMethod -Root $root -FileName 'fixture-overdue-method.md' -MethodId 'fixture-overdue-method' -VerifiedAt $verified -ReviewDue $due -Register
    }

    Invoke-VerifierCase -Name 'A75 overdue local extension cannot be used by researcher' -ExpectedExitCode 1 -StdoutPatterns @(
        '(?m)^FAIL: semantic knowledge gate',
        '(?i)local method overdue'
    ) -Arrange {
        param($root)
        $verified = [datetime]::Today.AddDays(-10).ToString('yyyy-MM-dd')
        $due = [datetime]::Today.AddDays(-1).ToString('yyyy-MM-dd')
        Write-LocalMethod -Root $root -FileName 'fixture-overdue-method.md' -MethodId 'fixture-overdue-method' -VerifiedAt $verified -ReviewDue $due -Register
        Write-OverdueResearchRun -Root $root -MethodId 'fixture-overdue-method' -MethodFileName 'fixture-overdue-method.md'
    }

    Invoke-GeneratorCase `
        -Name 'A76 shared mastery logical source blocks' `
        -CaseId 'a76' `
        -TargetRef 'mastery/local/INDEX.md#зарегистрированные-расширения' `
        -SourceRef @('logical:shared-mastery/external', 'PROJECT.md') `
        -ExpectedExitCode 1 `
        -StdoutPatterns @() `
        -StderrPatterns @('(?m)^ERROR: blocked: shared-owner\s*$')

    Invoke-GeneratorCase `
        -Name 'A77 shared mastery logical target blocks' `
        -CaseId 'a77' `
        -TargetRef 'logical:shared-mastery/external' `
        -SourceRef 'https://example.com/method-source' `
        -ExpectedExitCode 1 `
        -StdoutPatterns @() `
        -StderrPatterns @('(?m)^ERROR: blocked: shared-owner\s*$')

    Invoke-GeneratorCase `
        -Name 'A78 unknown shared mastery logical source blocks' `
        -CaseId 'a78' `
        -TargetRef 'docs/mastery-harness-target.md' `
        -SourceRef 'logical:shared-mastery/unknown' `
        -ExpectedExitCode 1 `
        -StdoutPatterns @() `
        -StderrPatterns @('(?m)^ERROR: blocked: shared-owner\s*$')
}
catch {
    $failures.Add("HARNESS SETUP: $($_.Exception.Message)") | Out-Null
    Write-Host "FAIL HARNESS SETUP: $($_.Exception.Message)"
}
finally {
    $stopwatch.Stop()
    if ($null -ne $harnessParent -and (Test-Path -LiteralPath $harnessParent -PathType Container)) {
        $resolved = (Resolve-Path -LiteralPath $harnessParent).Path
        $expectedParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]'\/')
        $leaf = Split-Path -Leaf $resolved
        $parent = Split-Path -Parent $resolved
        if ($parent -cne $expectedParent -or -not $leaf.StartsWith($temporaryPrefix, [System.StringComparison]::Ordinal)) {
            throw "Отказ от очистки небезопасного harness parent: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

$harnessHash = (Get-FileHash -LiteralPath $MyInvocation.MyCommand.Path -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host ("Mastery harness: pass={0}, fail={1}, elapsed_ms={2}." -f $passes.Count, $failures.Count, $stopwatch.ElapsedMilliseconds)
Write-Host "Seed SHA tree: $seedFingerprint"
Write-Host "Harness SHA256: $harnessHash"
if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "- $failure" }
    exit 1
}
exit 0
