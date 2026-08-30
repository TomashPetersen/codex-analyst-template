[CmdletBinding()]
param(
    [string]$Root = '',
    [ValidateSet('Source', 'Consumer')]
    [string]$Scope = 'Source',
    [switch]$Report,
    [switch]$SelfTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$maximumFileBytes = 8MB
$maximumFiles = 30000

function Convert-CharacterCodes {
    param([Parameter(Mandatory = $true)][int[]]$Codes)
    return -join @($Codes | ForEach-Object { [char]$_ })
}

function Get-AllowedThirdPartyGitCommit {
    # Split the public commit so this sanitizer does not allowlist its own source file.
    return ('02c6b27d4c942c9685c3' + '94cf85416c87151ebeac')
}

function Get-ProjectTraceTerms {
    return @(
        (Convert-CharacterCodes -Codes @(1040,1056,1052,32,1059,1087,1088,1072,1074,1083,1103,1102,1097,1077,1075,1086))
        (Convert-CharacterCodes -Codes @(1088,1077,1073,1072,1083,1072,1085,1089))
        (Convert-CharacterCodes -Codes @(114,101,98,97,108,97,110,99))
        (Convert-CharacterCodes -Codes @(65,103,101,110,116,32,67,111,110,116,114,111,108,32,80,108,97,110,101))
        (Convert-CharacterCodes -Codes @(68,111,99,108,105,110,103))
        (Convert-CharacterCodes -Codes @(76,105,116,101,76,76,77))
        (Convert-CharacterCodes -Codes @(65,73,80,114,111,120,121))
        (Convert-CharacterCodes -Codes @(80,114,101,116,114,97,100,101))
    )
}

function Get-SanitizationRoot {
    param([string]$CandidateRoot)
    if ([string]::IsNullOrWhiteSpace($CandidateRoot)) { return [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot)) }
    return [System.IO.Path]::GetFullPath($CandidateRoot)
}

function Get-RepositoryRelativePath {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot, [Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetRelativePath($RepositoryRoot, [System.IO.Path]::GetFullPath($Path)).Replace('\', '/')
}

function Read-StrictText {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Length -gt $maximumFileBytes) { throw 'file-size-limit' }
    $bytes = [System.IO.File]::ReadAllBytes($item.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return $strictUtf8.GetString($bytes, 3, $bytes.Length - 3)
    }
    return $strictUtf8.GetString($bytes)
}

function Get-ScopeFiles {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot, [Parameter(Mandatory = $true)][string]$SelectedScope)

    if ($SelectedScope -ceq 'Source') {
        $files = @(Get-ChildItem -LiteralPath $RepositoryRoot -Recurse -Force -File | Where-Object {
            $relative = Get-RepositoryRelativePath -RepositoryRoot $RepositoryRoot -Path $_.FullName
            $relative -cne '.git' -and -not $relative.StartsWith('.git/', [System.StringComparison]::Ordinal)
        } | Sort-Object FullName)
        if ($files.Count -gt $maximumFiles) { throw 'file-count-limit' }
        return $files
    }

    $manifestPath = Join-Path $RepositoryRoot '.template-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'missing-manifest' }
    try { $manifest = Read-StrictText -Path $manifestPath | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'invalid-manifest' }
    $renameMap = @{}
    foreach ($rename in @($manifest.initialization_renames)) {
        $renameMap[[string]$rename.from] = [string]$rename.to
    }
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($relative in @($manifest.portable_files | ForEach-Object { [string]$_ } | Sort-Object -Unique)) {
        if ($relative.Contains('\') -or $relative -match '^(?:[A-Za-z]:|/|\.\.?/)' -or $relative -match '(^|/)\.\.(/|$)') { throw 'unsafe-manifest-path' }
        $effectiveRelative = $relative
        $path = Join-Path $RepositoryRoot $effectiveRelative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf) -and $renameMap.ContainsKey($relative)) {
            $effectiveRelative = [string]$renameMap[$relative]
            $path = Join-Path $RepositoryRoot $effectiveRelative
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'missing-consumer-file' }
        $files.Add((Get-Item -LiteralPath $path -Force)) | Out-Null
        if ($files.Count -gt $maximumFiles) { throw 'file-count-limit' }
    }
    return @($files)
}

function Add-Finding {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Findings,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )
    $safePath = if ($RelativePath -cmatch '^[A-Za-z0-9._/-]{1,512}$') { $RelativePath } else { '<redacted-path>' }
    $Findings.Add("$Code [$safePath]") | Out-Null
}

function Invoke-SanitizationScan {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot, [Parameter(Mandatory = $true)][string]$SelectedScope)

    $findings = [System.Collections.Generic.List[string]]::new()
    $files = @(Get-ScopeFiles -RepositoryRoot $RepositoryRoot -SelectedScope $SelectedScope)
    $traceTerms = @(Get-ProjectTraceTerms)
    $projectPath = Join-Path $RepositoryRoot 'PROJECT.md'
    $projectText = if (Test-Path -LiteralPath $projectPath -PathType Leaf) { Read-StrictText -Path $projectPath } else { '' }
    $isGenerated = $projectText -match '(?m)^repository_kind:[ \t]*generated-project[ \t]*$'
    $generatedProjectId = if ($isGenerated) {
        $match = [regex]::Match($projectText, '(?m)^project_id:[ \t]*"?(?<value>[0-9a-fA-F-]+)"?[ \t]*$')
        if ($match.Success) { $match.Groups['value'].Value } else { '' }
    } else { '' }
    $generatedOwner = if ($isGenerated) {
        $match = [regex]::Match($projectText, '(?m)^-[ \t]*Владелец:[ \t]*`(?<value>[^`\r\n]+)`[ \t]*$')
        if ($match.Success) { $match.Groups['value'].Value } else { '' }
    } else { '' }
    foreach ($file in $files) {
        $relative = Get-RepositoryRelativePath -RepositoryRoot $RepositoryRoot -Path $file.FullName
        $pathProbe = $relative
        try { $text = Read-StrictText -Path $file.FullName }
        catch { Add-Finding -Findings $findings -Code $_.Exception.Message -RelativePath $relative; continue }
        $scanText = $text
        if ($isGenerated -and $relative -ceq 'PROJECT.md') {
            if (-not [string]::IsNullOrWhiteSpace($generatedProjectId)) { $scanText = $scanText.Replace($generatedProjectId, '{{PROJECT_ID}}') }
            if (-not [string]::IsNullOrWhiteSpace($generatedOwner)) { $scanText = $scanText.Replace("- Владелец: ``$generatedOwner``", '- Владелец: `<ROLE_OR_ALIAS>`') }
        }
        if ($relative -ceq 'TEMPLATE-DISTRIBUTION.json') {
            try {
                $descriptor = $text | ConvertFrom-Json -ErrorAction Stop
                $commit = [string]$descriptor.source_commit
                if ([string]$descriptor.distribution_kind -ceq 'github-template' -and
                    [string]$descriptor.source_tag -ceq ('v' + [string]$descriptor.template_version) -and
                    $commit -cmatch '^[0-9a-f]{40}$') {
                    $scanText = $scanText.Replace($commit, '{{SOURCE_COMMIT}}')
                }
            }
            catch { }
        }
        if ($relative -cin @('THIRD-PARTY-NOTICES.md', 'TEMPLATE-THIRD-PARTY-NOTICES.md', 'mastery/analyst/solution-architecture.md')) {
            $scanText = $scanText.Replace((Get-AllowedThirdPartyGitCommit), '{{THIRD_PARTY_COMMIT}}')
        }
        $probe = $pathProbe + "`n" + $scanText

        foreach ($term in $traceTerms) {
            if ($probe.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                Add-Finding -Findings $findings -Code 'project-trace' -RelativePath $relative
                break
            }
        }
        if ($probe -match '(?i)(?:[A-Z]:[\\/](?:Users|Documents and Settings)[\\/][^\\/\r\n]+|/(?:Users|home)/[^/\s]+)') {
            Add-Finding -Findings $findings -Code 'absolute-user-path' -RelativePath $relative
        }
        if ($probe -match '(?i)(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}(?![0-9a-f])') {
            Add-Finding -Findings $findings -Code 'literal-uuid' -RelativePath $relative
        }
        if ($probe -match '(?i)(?<![0-9a-f])[0-9a-f]{40}(?![0-9a-f])') {
            Add-Finding -Findings $findings -Code 'literal-git-sha' -RelativePath $relative
        }
        foreach ($match in [regex]::Matches($probe, '(?i)(?<![A-Z0-9._%+-])(?<local>[A-Z0-9._%+-]{1,64})@(?<domain>[A-Z0-9.-]+\.[A-Z]{2,63})(?![A-Z0-9.-])')) {
            $domain = $match.Groups['domain'].Value.ToLowerInvariant()
            if ($domain -notin @('example.com', 'example.org', 'example.net', 'example.test') -and -not $domain.EndsWith('.invalid', [System.StringComparison]::Ordinal)) {
                Add-Finding -Findings $findings -Code 'pii-email' -RelativePath $relative
                break
            }
        }
        if ($probe -match '(?<![0-9])\+[1-9][0-9 ()-]{7,20}[0-9](?![0-9])') {
            Add-Finding -Findings $findings -Code 'pii-phone' -RelativePath $relative
        }
        if ($probe -match '(?i)(?:\bsk-[A-Za-z0-9_-]{20,}\b|\bgh[pousr]_[A-Za-z0-9]{20,}\b|\bAKIA[0-9A-Z]{16}\b|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)') {
            Add-Finding -Findings $findings -Code 'credential-token' -RelativePath $relative
        }
        if ($file.Extension -cin @('.md', '.toml', '.yaml', '.yml')) {
        foreach ($ownerMatch in [regex]::Matches($scanText, '(?im)^[ \t]*(?:-[ \t]*)?(?:owner|author|approved_by|владелец)[ \t]*:[ \t]*(?<value>[^\r\n]+)$')) {
            $value = $ownerMatch.Groups['value'].Value.Trim().Trim('"').Trim("'").Trim('`')
            if ($value -notmatch '^(?:null|unknown|project-owner|role-or-alias|\{\{OWNER\}\}|<ROLE_OR_ALIAS>|<OWNER_ROLE_OR_ALIAS>)$') {
                Add-Finding -Findings $findings -Code 'nonplaceholder-owner' -RelativePath $relative
                break
            }
        }
        }
    }
    return [pscustomobject]@{ Findings = @($findings | Sort-Object -Unique); FileCount = $files.Count }
}

function Invoke-SelfTest {
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $base = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('analyst-sanitize-' + [guid]::NewGuid().ToString('N'))))
    if (-not $base.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'unsafe-selftest-root' }
    New-Item -ItemType Directory -Path $base | Out-Null
    try {
        [System.IO.File]::WriteAllText((Join-Path $base 'clean.md'), "# Clean`nowner: project-owner`ncontact: person@example.com`n", $utf8NoBom)
        $clean = Invoke-SanitizationScan -RepositoryRoot $base -SelectedScope Source
        if ($clean.Findings.Count -ne 0) { throw 'positive-selftest-failed' }
        $passed = [System.Collections.Generic.List[string]]::new()
        $passed.Add('positive') | Out-Null

        $thirdPartyNotice = Join-Path $base 'THIRD-PARTY-NOTICES.md'
        [System.IO.File]::WriteAllText($thirdPartyNotice, (Get-AllowedThirdPartyGitCommit), $utf8NoBom)
        $allowedThirdParty = Invoke-SanitizationScan -RepositoryRoot $base -SelectedScope Source
        if (@($allowedThirdParty.Findings | Where-Object { $_ -like 'literal-git-sha *' }).Count -ne 0) { throw 'third-party-commit-allowlist-failed' }
        $passed.Add('third-party-commit-allowlist') | Out-Null

        $renamedThirdPartyNotice = Join-Path $base 'TEMPLATE-THIRD-PARTY-NOTICES.md'
        [System.IO.File]::WriteAllText($renamedThirdPartyNotice, (Get-AllowedThirdPartyGitCommit), $utf8NoBom)
        $allowedRenamedThirdParty = Invoke-SanitizationScan -RepositoryRoot $base -SelectedScope Source
        if (@($allowedRenamedThirdParty.Findings | Where-Object { $_ -like 'literal-git-sha *' }).Count -ne 0) { throw 'renamed-third-party-commit-allowlist-failed' }
        Remove-Item -LiteralPath $renamedThirdPartyNotice -Force
        $passed.Add('renamed-third-party-commit-allowlist') | Out-Null

        [System.IO.File]::WriteAllText($thirdPartyNotice, ('a' * 40), $utf8NoBom)
        $randomThirdParty = Invoke-SanitizationScan -RepositoryRoot $base -SelectedScope Source
        if (@($randomThirdParty.Findings | Where-Object { $_ -like 'literal-git-sha *' }).Count -eq 0) { throw 'third-party-random-commit-selftest-failed' }
        Remove-Item -LiteralPath $thirdPartyNotice -Force
        $passed.Add('third-party-random-commit') | Out-Null

        [System.IO.File]::WriteAllText((Join-Path $base 'fixture.md'), (Get-AllowedThirdPartyGitCommit), $utf8NoBom)
        $wrongPathCommit = Invoke-SanitizationScan -RepositoryRoot $base -SelectedScope Source
        if (@($wrongPathCommit.Findings | Where-Object { $_ -like 'literal-git-sha *' }).Count -eq 0) { throw 'third-party-wrong-path-selftest-failed' }
        Remove-Item -LiteralPath (Join-Path $base 'fixture.md') -Force
        $passed.Add('third-party-wrong-path') | Out-Null

        $cases = @(
            @{ Name='project-trace'; Value=(Get-ProjectTraceTerms)[0] },
            @{ Name='literal-uuid'; Value=('12345678' + '-1234-4234-8234-' + '123456789012') },
            @{ Name='absolute-user-path'; Value=('C:' + '\Users\example\project') },
            @{ Name='pii-email'; Value=('person' + '@' + 'private' + '.biz') },
            @{ Name='credential-token'; Value=('sk-' + ('A' * 24)) }
        )
        foreach ($case in $cases) {
            [System.IO.File]::WriteAllText((Join-Path $base 'fixture.md'), [string]$case.Value, $utf8NoBom)
            $result = Invoke-SanitizationScan -RepositoryRoot $base -SelectedScope Source
            if (@($result.Findings | Where-Object { $_ -like "$($case.Name) *" }).Count -eq 0) { throw "negative-selftest-failed:$($case.Name)" }
            Remove-Item -LiteralPath (Join-Path $base 'fixture.md') -Force
            $passed.Add([string]$case.Name) | Out-Null
        }
        Write-Host "PASS: template sanitization self-test ($($passed.Count) scenarios)."
    }
    finally {
        if (Test-Path -LiteralPath $base -PathType Container) {
            $resolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $base).Path)
            if (-not $resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'unsafe-selftest-cleanup' }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

if ($SelfTest) { Invoke-SelfTest; exit 0 }
$repositoryRoot = Get-SanitizationRoot -CandidateRoot $Root
$result = Invoke-SanitizationScan -RepositoryRoot $repositoryRoot -SelectedScope $Scope
if ($result.Findings.Count -gt 0) {
    Write-Host "FAIL: sanitization findings - $($result.Findings.Count)." -ForegroundColor Red
    $result.Findings | ForEach-Object { Write-Host "- $_" }
    exit 1
}
if ($Report) { Write-Host "REPORT: sanitized files - $($result.FileCount); scope - $Scope." }
Write-Host "PASS: template sanitization ($Scope)."
exit 0
