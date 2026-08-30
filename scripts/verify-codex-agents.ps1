[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$Report,
    [switch]$SelfTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

$expectedAgentNames = @(
    'analysis_red_team',
    'analysis_reviewer',
    'business_analyst',
    'requirements_analyst',
    'system_analyst'
)

function Get-CodexAgentRoot {
    param([string]$CandidateRoot)

    if ([string]::IsNullOrWhiteSpace($CandidateRoot)) {
        return [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
    }
    return [System.IO.Path]::GetFullPath($CandidateRoot)
}

function Read-StrictText {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt 32768) { throw 'codex-agent-file-too-large' }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw 'codex-agent-file-has-bom'
    }
    return $strictUtf8.GetString($bytes).Replace("`r`n", "`n")
}

function Get-ReparsePointInChain {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    $current = $root
    foreach ($segment in (($full.Substring($root.Length) -split '[\\/]') | Where-Object { $_ })) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { break }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $current }
    }
    return $null
}

$trustedAgentScriptsRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char[]]'\/')
$trustedAgentPlatformPath = [System.IO.Path]::GetFullPath((Join-Path $trustedAgentScriptsRoot 'lib/ModelProject.Platform.psm1'))
if (-not (Test-Path -LiteralPath $trustedAgentPlatformPath -PathType Leaf) -or
    $null -ne (Get-ReparsePointInChain -Path $trustedAgentPlatformPath)) {
    throw 'Trusted Codex agent platform module failed integrity check.'
}
$trustedAgentPlatform = Import-Module -Name $trustedAgentPlatformPath -Scope Local -Force -PassThru -ErrorAction Stop
$script:agentResolvePhysicalPath = $trustedAgentPlatform.ExportedCommands['Resolve-ModelProjectFileSystemLinkPath']
$script:agentGetPathComparison = $trustedAgentPlatform.ExportedCommands['Get-ModelProjectPathComparison']
foreach ($trustedAgentCommand in @($script:agentResolvePhysicalPath, $script:agentGetPathComparison)) {
    if ($null -eq $trustedAgentCommand -or
        $trustedAgentCommand.CommandType -ne [System.Management.Automation.CommandTypes]::Function -or
        $null -eq $trustedAgentCommand.Module -or
        -not [System.IO.Path]::GetFullPath([string]$trustedAgentCommand.Module.Path).Equals(
            $trustedAgentPlatformPath,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw 'Trusted Codex agent platform command failed origin check.'
    }
}

function Test-AgentDocument {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedName,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues
    )

    try { $text = Read-StrictText -Path $Path } catch { $Issues.Add("$($ExpectedName):$($_.Exception.Message)") | Out-Null; return }
    if ($text -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]') { $Issues.Add("$($ExpectedName):control-character") | Out-Null }
    if ($text -match '(?im)^\s*(?:model|model_reasoning_effort|approval_policy|network_access)\s*=' -or
        $text -match '(?im)^\s*\[(?:mcp_servers|hooks|skills\.config)' -or
        $text -match '(?i)\b(?:mcp_servers|hooks)\b') {
        $Issues.Add("$($ExpectedName):forbidden-capability") | Out-Null
    }

    $match = [regex]::Match(
        $text,
        '\Aname = "(?<name>[a-z][a-z0-9_]*)"\ndescription = "(?<description>[^"\r\n]+)"\nsandbox_mode = "(?<sandbox>[^"]+)"\ndeveloper_instructions = """\n(?<instructions>[\s\S]+?)\n"""\n?\z',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if (-not $match.Success) { $Issues.Add("$($ExpectedName):invalid-schema") | Out-Null; return }
    if ($match.Groups['name'].Value -cne $ExpectedName) { $Issues.Add("$($ExpectedName):name-mismatch") | Out-Null }
    if ($match.Groups['sandbox'].Value -cne 'read-only') { $Issues.Add("$($ExpectedName):not-read-only") | Out-Null }
    if ($match.Groups['description'].Value.Length -gt 240) { $Issues.Add("$($ExpectedName):description-too-long") | Out-Null }

    $instructions = $match.Groups['instructions'].Value
    foreach ($required in @('read-only', 'Не создавай subagents', 'Не создавай и не изменяй файлы')) {
        if ($instructions.IndexOf($required, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $Issues.Add("$($ExpectedName):missing-instruction") | Out-Null
            break
        }
    }
    if ($ExpectedName -ceq 'system_analyst' -and
        $instructions.IndexOf('mastery/analyst/solution-architecture.md#method', [System.StringComparison]::Ordinal) -lt 0) {
        $Issues.Add('system_analyst:missing-solution-method-ref') | Out-Null
    }
}

function Test-ItAnalysisSkillUi {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues
    )

    try { $text = Read-StrictText -Path $Path } catch { $Issues.Add("it-analysis-openai:$($_.Exception.Message)") | Out-Null; return }
    if ($text -match '(?im)^\s*(?:dependencies|mcp_servers|mcp|connectors|tools|tool_calls|requires|requirements)\s*:') {
        $Issues.Add('it-analysis-openai:forbidden-capability') | Out-Null
    }
    $match = [regex]::Match(
        $text,
        '\Ainterface:\n  display_name: "(?<display>[^"\r\n]{1,80})"\n  short_description: "(?<short>[^"\r\n]{1,160})"\n  default_prompt: "(?<prompt>[^"\r\n]{1,1024})"\n?\z',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if (-not $match.Success) {
        $Issues.Add('it-analysis-openai:invalid-schema') | Out-Null
        return
    }
    if ($match.Groups['display'].Value -cne 'IT-анализ') {
        $Issues.Add('it-analysis-openai:display-name-mismatch') | Out-Null
    }
}

function Invoke-CodexAgentVerification {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $issues = [System.Collections.Generic.List[string]]::new()
    $codexRoot = Join-Path $RepositoryRoot '.codex'
    $configPath = Join-Path $codexRoot 'config.toml'
    $agentsRoot = Join-Path $codexRoot 'agents'
    $skillUiPath = Join-Path $RepositoryRoot '.agents/skills/it-analysis/agents/openai.yaml'
    foreach ($path in @($codexRoot, $configPath, $agentsRoot)) {
        if (-not (Test-Path -LiteralPath $path)) { $issues.Add('missing-codex-contract') | Out-Null; continue }
        if ($null -ne (Get-ReparsePointInChain -Path $path)) { $issues.Add('codex-reparse-point') | Out-Null }
    }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf) -or -not (Test-Path -LiteralPath $agentsRoot -PathType Container)) {
        return [pscustomobject]@{ Issues = @($issues); AgentCount = 0 }
    }

    $expectedConfig = "[agents]`nenabled = true`nmax_concurrent_threads_per_session = 3`ninterrupt_message = true`n"
    try {
        $actualConfig = Read-StrictText -Path $configPath
        if (($actualConfig.TrimEnd("`n") + "`n") -cne $expectedConfig) { $issues.Add('invalid-codex-config') | Out-Null }
    }
    catch { $issues.Add($_.Exception.Message) | Out-Null }

    $files = @(Get-ChildItem -LiteralPath $agentsRoot -Force -File | Sort-Object Name)
    $directories = @(Get-ChildItem -LiteralPath $agentsRoot -Force -Directory)
    if ($directories.Count -gt 0) { $issues.Add('unexpected-agent-directory') | Out-Null }
    $actualNames = @($files | ForEach-Object { $_.BaseName })
    if (@($files | Where-Object Extension -cne '.toml').Count -gt 0 -or
        @(Compare-Object -ReferenceObject $expectedAgentNames -DifferenceObject $actualNames -CaseSensitive).Count -gt 0) {
        $issues.Add('agent-inventory-mismatch') | Out-Null
    }
    foreach ($name in $expectedAgentNames) {
        $path = Join-Path $agentsRoot ($name + '.toml')
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Test-AgentDocument -Path $path -ExpectedName $name -Issues $issues
        }
    }
    if (-not (Test-Path -LiteralPath $skillUiPath -PathType Leaf) -or $null -ne (Get-ReparsePointInChain -Path $skillUiPath)) {
        $issues.Add('it-analysis-openai:missing-or-reparse') | Out-Null
    }
    else {
        Test-ItAnalysisSkillUi -Path $skillUiPath -Issues $issues
    }
    return [pscustomobject]@{ Issues = @($issues | Sort-Object -Unique); AgentCount = $files.Count }
}

function Invoke-SelfTest {
    $tempBase = [System.IO.Path]::GetFullPath((& $script:agentResolvePhysicalPath -Path ([System.IO.Path]::GetTempPath()))).TrimEnd([char[]]'\/')
    $tempComparison = & $script:agentGetPathComparison -Path $tempBase
    $base = Join-Path $tempBase ('codex-agent-selftest-' + [guid]::NewGuid().ToString('N'))
    $baseFull = [System.IO.Path]::GetFullPath($base)
    $tempPrefix = $tempBase + [System.IO.Path]::DirectorySeparatorChar
    if (-not $baseFull.StartsWith($tempPrefix, $tempComparison) -or
        [System.IO.Path]::GetFileName($baseFull) -cnotmatch '^codex-agent-selftest-[0-9a-f]{32}$') {
        throw 'unsafe-selftest-path'
    }
    New-Item -ItemType Directory -Path $baseFull | Out-Null
    try {
        Copy-Item -LiteralPath (Join-Path (Get-CodexAgentRoot -CandidateRoot $Root) '.codex') -Destination $baseFull -Recurse
        $skillUiFixtureRoot = Join-Path $baseFull '.agents/skills/it-analysis/agents'
        [System.IO.Directory]::CreateDirectory($skillUiFixtureRoot) | Out-Null
        Copy-Item `
            -LiteralPath (Join-Path (Get-CodexAgentRoot -CandidateRoot $Root) '.agents/skills/it-analysis/agents/openai.yaml') `
            -Destination (Join-Path $skillUiFixtureRoot 'openai.yaml')
        $passed = [System.Collections.Generic.List[string]]::new()
        $result = Invoke-CodexAgentVerification -RepositoryRoot $baseFull
        if ($result.Issues.Count -ne 0 -or $result.AgentCount -ne 5) { throw 'positive-fixture-failed' }
        $passed.Add('positive-contract') | Out-Null

        $businessPath = Join-Path $baseFull '.codex/agents/business_analyst.toml'
        $originalBusiness = [System.IO.File]::ReadAllText($businessPath, $utf8NoBom)
        [System.IO.File]::WriteAllText($businessPath, ($originalBusiness + "model = `"example`"`n"), $utf8NoBom)
        if ((Invoke-CodexAgentVerification -RepositoryRoot $baseFull).Issues -notcontains 'business_analyst:forbidden-capability') { throw 'model-fixture-failed' }
        [System.IO.File]::WriteAllText($businessPath, $originalBusiness, $utf8NoBom)
        $passed.Add('negative-model') | Out-Null

        $systemPath = Join-Path $baseFull '.codex/agents/system_analyst.toml'
        $originalSystem = [System.IO.File]::ReadAllText($systemPath, $utf8NoBom)
        [System.IO.File]::WriteAllText($systemPath, $originalSystem.Replace('sandbox_mode = "read-only"', 'sandbox_mode = "workspace-write"'), $utf8NoBom)
        if ((Invoke-CodexAgentVerification -RepositoryRoot $baseFull).Issues -notcontains 'system_analyst:not-read-only') { throw 'sandbox-fixture-failed' }
        [System.IO.File]::WriteAllText($systemPath, $originalSystem, $utf8NoBom)
        $passed.Add('negative-sandbox') | Out-Null

        [System.IO.File]::WriteAllText(
            $systemPath,
            $originalSystem.Replace('mastery/analyst/solution-architecture.md#method', 'mastery/analyst/solution-architecture.md'),
            $utf8NoBom
        )
        if ((Invoke-CodexAgentVerification -RepositoryRoot $baseFull).Issues -notcontains 'system_analyst:missing-solution-method-ref') {
            throw 'solution-method-ref-fixture-failed'
        }
        [System.IO.File]::WriteAllText($systemPath, $originalSystem, $utf8NoBom)
        $passed.Add('negative-solution-method-ref') | Out-Null

        $configPath = Join-Path $baseFull '.codex/config.toml'
        $originalConfig = [System.IO.File]::ReadAllText($configPath, $utf8NoBom)
        [System.IO.File]::WriteAllText($configPath, $originalConfig.Replace(' = 3', ' = 4'), $utf8NoBom)
        if ((Invoke-CodexAgentVerification -RepositoryRoot $baseFull).Issues -notcontains 'invalid-codex-config') { throw 'concurrency-fixture-failed' }
        [System.IO.File]::WriteAllText($configPath, $originalConfig, $utf8NoBom)
        $passed.Add('negative-concurrency') | Out-Null

        [System.IO.File]::WriteAllText((Join-Path $baseFull '.codex/agents/extra.toml'), 'name = "extra"', $utf8NoBom)
        if ((Invoke-CodexAgentVerification -RepositoryRoot $baseFull).Issues -notcontains 'agent-inventory-mismatch') { throw 'inventory-fixture-failed' }
        $passed.Add('negative-inventory') | Out-Null

        Remove-Item -LiteralPath (Join-Path $baseFull '.codex/agents/extra.toml') -Force
        $skillUiPath = Join-Path $baseFull '.agents/skills/it-analysis/agents/openai.yaml'
        $originalSkillUi = [System.IO.File]::ReadAllText($skillUiPath, $utf8NoBom)
        [System.IO.File]::WriteAllText($skillUiPath, ($originalSkillUi.TrimEnd() + "`ndependencies:`n  - mcp: context7`n"), $utf8NoBom)
        if ((Invoke-CodexAgentVerification -RepositoryRoot $baseFull).Issues -notcontains 'it-analysis-openai:forbidden-capability') {
            throw 'skill-ui-mcp-fixture-failed'
        }
        $passed.Add('negative-skill-ui-mcp') | Out-Null
        Write-Host "PASS: codex agents self-test ($($passed.Count) scenarios)."
    }
    finally {
        if (Test-Path -LiteralPath $baseFull) {
            $resolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $baseFull).Path)
            if (-not $resolved.StartsWith($tempPrefix, $tempComparison) -or
                [System.IO.Path]::GetFileName($resolved) -cnotmatch '^codex-agent-selftest-[0-9a-f]{32}$') {
                throw 'unsafe-selftest-cleanup'
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

if ($SelfTest) { Invoke-SelfTest; exit 0 }
$repositoryRoot = Get-CodexAgentRoot -CandidateRoot $Root
$verification = Invoke-CodexAgentVerification -RepositoryRoot $repositoryRoot
if ($verification.Issues.Count -gt 0) {
    Write-Host "FAIL: Codex agent contract problems - $($verification.Issues.Count)." -ForegroundColor Red
    $verification.Issues | ForEach-Object { Write-Host "- $_" }
    exit 1
}
if ($Report) { Write-Host "REPORT: $($verification.AgentCount) read-only project agents; concurrency cap 3." }
Write-Host 'PASS: Codex agent contract корректен.'
exit 0
