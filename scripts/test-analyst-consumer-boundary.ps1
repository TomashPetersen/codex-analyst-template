[CmdletBinding()]
param([string]$Root = '')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$sourceRoot = if ([string]::IsNullOrWhiteSpace($Root)) { Split-Path -Parent $PSScriptRoot } else { [System.IO.Path]::GetFullPath($Root) }
Import-Module (Join-Path $sourceRoot 'scripts/lib/ModelProject.Platform.psm1') -Force
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$pwshPath = (Get-Process -Id $PID).Path
$tempBase = [System.IO.Path]::GetFullPath((Resolve-ModelProjectFileSystemLinkPath -Path ([System.IO.Path]::GetTempPath()))).TrimEnd([char[]]'\/')
$tempComparison = Get-ModelProjectPathComparison -Path $tempBase
$fixtureRoot = [System.IO.Path]::GetFullPath((Join-Path $tempBase ('codex-analyst-consumer-' + [guid]::NewGuid().ToString('N'))))
$generatedRoot = $fixtureRoot + '-generated'
$rejectedRoot = $fixtureRoot + '-rejected-generated-source'

function Copy-PortableFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $source = Join-Path $sourceRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Portable source отсутствует: $RelativePath" }
    $target = Join-Path $fixtureRoot $RelativePath
    $parent = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [System.IO.Directory]::CreateDirectory($parent) | Out-Null }
    [System.IO.File]::Copy($source, $target, $false)
}

function Invoke-ChildScript {
    param([Parameter(Mandatory = $true)][string]$Script, [Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = @(& $pwshPath -NoProfile -File $Script @Arguments 2>&1)
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "Child script failed: $([System.IO.Path]::GetFileName($Script)). Output: $($output -join ' | ')" }
    return @($output | ForEach-Object { [string]$_ })
}

function Assert-NoDataArtifacts {
    param([Parameter(Mandatory = $true)][string]$RelativeRoot, [string[]]$AllowedLeaves = @())
    $path = Join-Path $fixtureRoot $RelativeRoot
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Отсутствует обязательная пустая зона: $RelativeRoot" }
    $unexpected = @(Get-ChildItem -LiteralPath $path -Recurse -Force -File | Where-Object {
        $relative = [System.IO.Path]::GetRelativePath($path, $_.FullName).Replace('\', '/')
        $AllowedLeaves -cnotcontains $relative
    })
    if ($unexpected.Count -gt 0) { throw "Consumer содержит заполненную data zone: $RelativeRoot" }
}

try {
    if (-not $fixtureRoot.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, $tempComparison)) { throw 'Unsafe consumer fixture root.' }
    [System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    $manifest = [System.IO.File]::ReadAllText((Join-Path $sourceRoot '.template-manifest.json')) | ConvertFrom-Json -ErrorAction Stop
    $portable = @($manifest.portable_files | ForEach-Object { [string]$_ })
    foreach ($relative in $portable) { Copy-PortableFile -RelativePath $relative }
    foreach ($relative in @($manifest.portable_empty_directories)) {
        [System.IO.Directory]::CreateDirectory((Join-Path $fixtureRoot ([string]$relative))) | Out-Null
    }

    $actual = @(Get-ChildItem -LiteralPath $fixtureRoot -Recurse -File -Force | ForEach-Object {
        [System.IO.Path]::GetRelativePath($fixtureRoot, $_.FullName).Replace('\', '/')
    })
    $missing = @($portable | Where-Object { $actual -cnotcontains $_ })
    $extra = @($actual | Where-Object { $portable -cnotcontains $_ })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) { throw 'Consumer inventory не совпадает с portable allowlist.' }

    $required = @(
        '.agents/skills/it-analysis/SKILL.md',
        '.agents/skills/knowledge-curator/SKILL.md',
        '.agents/skills/project-delivery/SKILL.md',
        '.agents/skills/startup-researcher/SKILL.md',
        '.codex/config.toml',
        '.codex/agents/business_analyst.toml',
        '.codex/agents/system_analyst.toml',
        '.codex/agents/requirements_analyst.toml',
        '.codex/agents/analysis_reviewer.toml',
        '.codex/agents/analysis_red_team.toml',
        'analysis/CONTRACT.md',
        'analysis/runs/.gitkeep',
        'business/analysis/INDEX.md',
        'docs/analysis/INDEX.md',
        'mastery/analyst/INDEX.md',
        'prompts/analysis-run.md',
        'prompts/analysis-program.md',
        'prompts/analysis-review.md',
        'prompts/analysis-handoff.md',
        'scripts/new-project.ps1',
        'scripts/new-analysis-run.ps1',
        'scripts/verify-analysis.ps1',
        'scripts/verify-codex-agents.ps1',
        'scripts/verify-template-sanitization.ps1'
    )
    foreach ($relative in $required) {
        if ($actual -cnotcontains $relative) { throw "Consumer не содержит обязательный analyst path: $relative" }
    }
    foreach ($sourceOnly in @($manifest.source_only_paths)) {
        if ($actual -ccontains [string]$sourceOnly) { throw "Consumer содержит source-only path: $sourceOnly" }
    }

    $consumerReadme = [System.IO.File]::ReadAllText((Join-Path $fixtureRoot 'README.md'))
    $shortInstallCommand = 'Установи этот шаблон на мой компьютер по ссылке <URL>. Сначала прочитай README.md и выполни раздел «URL-first контракт для Codex».'
    $urlFirstPosition = $consumerReadme.IndexOf($shortInstallCommand, [System.StringComparison]::Ordinal)
    $githubTemplatePosition = $consumerReadme.IndexOf('## Дополнительный путь через GitHub Template', [System.StringComparison]::Ordinal)
    if ($urlFirstPosition -lt 0 -or $githubTemplatePosition -le $urlFirstPosition) {
        throw 'Consumer README не делает URL-first prompt основным install route.'
    }
    $installPrompt = [System.IO.File]::ReadAllText((Join-Path $fixtureRoot 'CODEX-INSTALL-PROMPT.md'))
    foreach ($requiredPromptFragment in @(
        'Заменить нужно только `<URL>`.',
        'git clone --branch main --single-branch --depth 1 <URL> <TEMP_CLONE>',
        'pwsh -NoProfile -File ./scripts/new-project.ps1 -Destination "<ABSOLUTE_TARGET_PATH>"',
        'независимый Git main без remote и без commit',
        'Если trust gate не проходит'
    )) {
        if (-not $installPrompt.Contains($requiredPromptFragment)) {
            throw "Consumer install prompt потерял URL-first fragment: $requiredPromptFragment"
        }
    }
    if ($installPrompt.Contains('<NEW_REPOSITORY_URL>') -or
        $installPrompt.StartsWith('Сначала создай новый repository кнопкой GitHub', [System.StringComparison]::Ordinal)) {
        throw 'Consumer install prompt сохранил обязательный pre-created GitHub Template route.'
    }

    Assert-NoDataArtifacts -RelativeRoot 'analysis/runs' -AllowedLeaves @('.gitkeep')
    Assert-NoDataArtifacts -RelativeRoot 'research/runs' -AllowedLeaves @('.gitkeep')
    Assert-NoDataArtifacts -RelativeRoot 'knowledge/candidates' -AllowedLeaves @('TEMPLATE.md')
    Assert-NoDataArtifacts -RelativeRoot 'inbox/raw' -AllowedLeaves @('README.md', 'TEMPLATE.md')
    Assert-NoDataArtifacts -RelativeRoot 'mastery/local' -AllowedLeaves @('INDEX.md', 'TEMPLATE.md')

    $projectPath = Join-Path $fixtureRoot 'PROJECT.md'
    $project = [System.IO.File]::ReadAllText($projectPath)
    if (-not $project.Contains('repository_kind: template-source')) { throw 'PROJECT.md не содержит source marker.' }
    [System.IO.File]::WriteAllText($projectPath, $project.Replace('repository_kind: template-source', 'repository_kind: distribution-template'), $utf8NoBom)

    [void](Invoke-ChildScript -Script (Join-Path $fixtureRoot 'scripts/update-plan-index.ps1') -Arguments @('-Root', $fixtureRoot, '-Mode', 'Write'))
    $planIndex = [System.IO.File]::ReadAllText((Join-Path $fixtureRoot 'plans/INDEX.md'))
    if ($planIndex -match 'PLAN-[0-9]|legacy:') { throw 'Consumer plan index содержит source-only plans.' }

    $payloadHashes = [System.Collections.Generic.List[object]]::new()
    foreach ($relative in @($portable | Where-Object { $_ -cne 'TEMPLATE-DISTRIBUTION.json' } | Sort-Object)) {
        $hash = (Get-FileHash -LiteralPath (Join-Path $fixtureRoot $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
        $payloadHashes.Add([ordered]@{ path = $relative; sha256 = $hash }) | Out-Null
    }
    $descriptor = [ordered]@{
        schema_version = 1
        distribution_kind = 'github-template'
        template_version = [string]$manifest.template_version
        source_tag = 'v' + [string]$manifest.template_version
        source_commit = ('0' * 40)
        template_repository_url = 'https://github.com/example/codex-analyst-template'
        built_at = '2026-08-20T00:00:00Z'
        payload_sha256 = $payloadHashes.ToArray()
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $fixtureRoot 'TEMPLATE-DISTRIBUTION.json'),
        (($descriptor | ConvertTo-Json -Depth 6) + [Environment]::NewLine),
        $utf8NoBom
    )

    $verifyOutput = Invoke-ChildScript -Script (Join-Path $fixtureRoot 'scripts/verify-structure.ps1') -Arguments @('-Root', $fixtureRoot, '-Mode', 'DistributionTemplate')
    if (($verifyOutput -join [Environment]::NewLine) -notmatch 'PASS \[DistributionTemplate\]') { throw 'DistributionTemplate gate не вернул PASS.' }
    [void](Invoke-ChildScript -Script (Join-Path $fixtureRoot 'scripts/verify-template-sanitization.ps1') -Arguments @('-Root', $fixtureRoot, '-Scope', 'Consumer'))

    $installOutput = Invoke-ChildScript `
        -Script (Join-Path $fixtureRoot 'scripts/new-project.ps1') `
        -Arguments @('-Destination', $generatedRoot)
    if (($installOutput -join [Environment]::NewLine) -notmatch 'Новый проект создан атомарным rename') {
        throw 'URL-first distribution copy не вернул успешный installation result.'
    }
    $generatedProject = [System.IO.File]::ReadAllText((Join-Path $generatedRoot 'PROJECT.md'))
    if ($generatedProject -cnotmatch '(?m)^repository_kind: generated-project\s*$' -or
        $generatedProject -cnotmatch '(?m)^project_status: initialized\s*$' -or
        $generatedProject -cnotmatch '(?m)^knowledge_capture_mode: report-only\s*$' -or
        $generatedProject -cnotmatch '(?m)^# Аналитический проект\s*$' -or
        $generatedProject -cnotmatch '(?m)^- Slug: `analyst-workspace`\s*$') {
        throw 'URL-first generated project не получил neutral defaults или expected mode.'
    }
    foreach ($sourceOnly in @($manifest.source_only_paths)) {
        if (Test-Path -LiteralPath (Join-Path $generatedRoot ([string]$sourceOnly))) {
            throw "URL-first generated project содержит source-only path: $sourceOnly"
        }
    }
    $originText = [System.IO.File]::ReadAllText((Join-Path $generatedRoot 'TEMPLATE-ORIGIN.md'))
    if ($originText -cnotmatch '(?m)^- Канал распространения: github-template\s*$' -or
        $originText -cnotmatch '(?m)^- Template repository: https://github\.com/example/codex-analyst-template\s*$') {
        throw 'URL-first generated project потерял provenance distribution template.'
    }
    $gitExe = Get-ModelProjectGitExecutable -ControlledRoots @($sourceRoot, $fixtureRoot, $generatedRoot)
    $branchResult = Invoke-ModelProjectProcess `
        -Executable $gitExe `
        -Arguments @('-C', $generatedRoot, 'branch', '--show-current') `
        -GitEnvironment
    if ($branchResult.ExitCode -ne 0 -or @($branchResult.Output).Count -ne 1 -or [string]$branchResult.Output[0] -cne 'main') {
        throw 'URL-first generated project не получил independent Git main.'
    }
    $remoteResult = Invoke-ModelProjectProcess `
        -Executable $gitExe `
        -Arguments @('-C', $generatedRoot, 'remote') `
        -GitEnvironment
    if ($remoteResult.ExitCode -ne 0 -or @($remoteResult.Output).Count -ne 0) {
        throw 'URL-first generated project унаследовал template remote.'
    }

    $rejectedOutput = @(& $pwshPath -NoProfile -File (Join-Path $generatedRoot 'scripts/new-project.ps1') -Destination $rejectedRoot 2>&1)
    $rejectedCode = $LASTEXITCODE
    if ($rejectedCode -eq 0 -or (Test-Path -LiteralPath $rejectedRoot)) {
        throw 'Portable new-project принял generated project как template source.'
    }
    Write-Host "PASS: analyst consumer boundary; portable=$($portable.Count); URL-first independent install, formal-analysis and read-only agents present."
}
finally {
    if (Test-Path -LiteralPath $rejectedRoot -PathType Container) {
        $fullRejected = [System.IO.Path]::GetFullPath($rejectedRoot)
        if (-not $fullRejected.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, $tempComparison) -or
            [System.IO.Path]::GetFileName($fullRejected) -cnotmatch '^codex-analyst-consumer-[a-f0-9]{32}-rejected-generated-source$') {
            throw 'Unsafe rejected fixture cleanup target.'
        }
        Remove-Item -LiteralPath $fullRejected -Recurse -Force
    }
    if (Test-Path -LiteralPath $generatedRoot -PathType Container) {
        $fullGenerated = [System.IO.Path]::GetFullPath($generatedRoot)
        if (-not $fullGenerated.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, $tempComparison) -or
            [System.IO.Path]::GetFileName($fullGenerated) -cnotmatch '^codex-analyst-consumer-[a-f0-9]{32}-generated$') {
            throw 'Unsafe generated fixture cleanup target.'
        }
        Remove-Item -LiteralPath $fullGenerated -Recurse -Force
    }
    if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
        $full = [System.IO.Path]::GetFullPath($fixtureRoot)
        if (-not $full.StartsWith($tempBase + [System.IO.Path]::DirectorySeparatorChar, $tempComparison) -or
            [System.IO.Path]::GetFileName($full) -cnotmatch '^codex-analyst-consumer-[a-f0-9]{32}$') {
            throw 'Unsafe consumer fixture cleanup target.'
        }
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
