Set-StrictMode -Version 2.0

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$script:PlatformModulePath = Join-Path $PSScriptRoot 'ModelProject.Platform.psm1'
$script:KnowledgeModulePath = Join-Path $PSScriptRoot 'ModelProject.Knowledge.psm1'
Import-Module $script:PlatformModulePath -Scope Local
Import-Module $script:KnowledgeModulePath -Force

function ConvertFrom-ModelProjectPlanScalar {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    $trimmed = $Value.Trim()
    if ($trimmed -ceq 'null' -or $trimmed -ceq '~') { return $null }
    if ($trimmed -ceq '[]') { return ,[string[]]@() }
    if (($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or
        ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'"))) {
        return $trimmed.Substring(1, $trimmed.Length - 2)
    }
    return $trimmed
}

function ConvertTo-ModelProjectPlanYamlScalar {
    param($Value)
    if ($null -eq $Value) { return 'null' }
    $text = [string]$Value
    if ($text -match '^[A-Za-z0-9][A-Za-z0-9._:/+-]*$') { return $text }
    return "'" + $text.Replace("'", "''") + "'"
}

function Get-ModelProjectPlanRoot {
    param([string]$Root = '')
    $candidate = if ([string]::IsNullOrWhiteSpace($Root)) {
        Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }
    else {
        $Root
    }
    return [System.IO.Path]::GetFullPath($candidate)
}

function Get-ModelProjectPlanRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )
    return [System.IO.Path]::GetRelativePath(
        [System.IO.Path]::GetFullPath($Root),
        [System.IO.Path]::GetFullPath($Path)
    ).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
}

function Read-ModelProjectPlanText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$MaxBytes = 2MB
    )
    $root = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))
    return Read-ModelProjectBoundedUtf8File -Root $root -Path $Path -MaxBytes $MaxBytes
}

function Read-ModelProjectPlanDocument {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Root = ''
    )
    $rootPath = Get-ModelProjectPlanRoot -Root $Root
    return Read-ModelProjectSimpleFrontMatterDocument -Root $rootPath -Path $Path
}

function Get-ModelProjectPlanFiles {
    param([string]$Root = '')
    $rootPath = Get-ModelProjectPlanRoot -Root $Root
    $plansPath = Join-Path $rootPath 'plans'
    if (-not (Test-Path -LiteralPath $plansPath -PathType Container)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $plansPath -File -Filter '*.md' |
            Where-Object { $_.Name -cnotin @('README.md', 'TEMPLATE.md', 'INDEX.md') } |
            Sort-Object -Property Name
    )
}

function Get-ModelProjectPlanHeading {
    param([Parameter(Mandatory = $true)][string]$Body)
    $match = [regex]::Match($Body, '(?m)^#\s+(?<title>.+?)\s*$')
    if ($match.Success) { return $match.Groups['title'].Value.Trim() }
    return 'Без названия'
}

function Get-ModelProjectPlanSummary {
    param([Parameter(Mandatory = $true)]$Document)
    $data = $Document.Data
    $isV2 = $data.Contains('plan_contract_version') -and [string]$data.plan_contract_version -ceq '2'
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Document.Path)
    $legacyTask = if ($name -match '^\d{4}-\d{2}-\d{2}-(?<slug>.+)$') { [string]$Matches['slug'] } else { $name }
    [pscustomobject]@{
        IsV2 = $isV2
        PlanId = if ($isV2 -and $data.Contains('plan_id')) { [string]$data.plan_id } else { 'legacy:' + $name }
        TaskKey = if ($isV2 -and $data.Contains('task_key')) { [string]$data.task_key } else { $legacyTask }
        Status = if ($data.Contains('status')) { [string]$data.status } else { 'unknown' }
        CurrentPhase = if ($isV2 -and $data.Contains('current_phase') -and $null -ne $data.current_phase) { [string]$data.current_phase } else { '-' }
        UpdatedAt = if ($isV2 -and $data.Contains('updated_at')) { [string]$data.updated_at } else { '-' }
        Title = Get-ModelProjectPlanHeading -Body $Document.Body
        RelativePath = $Document.RelativePath
    }
}

function Get-ModelProjectPlanIndexContent {
    param([string]$Root = '')
    $rootPath = Get-ModelProjectPlanRoot -Root $Root
    $groups = [ordered]@{
        planned = 'Новый'
        'in-progress' = 'В работе'
        complete = 'Сделано'
        blocked = 'Заблокирован'
    }
    $summaries = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ModelProjectPlanFiles -Root $rootPath)) {
        try {
            $document = Read-ModelProjectPlanDocument -Path $file.FullName -Root $rootPath
            $summaries.Add((Get-ModelProjectPlanSummary -Document $document))
        }
        catch {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $summaries.Add([pscustomobject]@{
                IsV2 = $false
                PlanId = 'invalid:' + $name
                TaskKey = $name
                Status = 'unknown'
                CurrentPhase = '-'
                UpdatedAt = '-'
                Title = 'Некорректный plan'
                RelativePath = 'plans/' + $file.Name
            })
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Индекс планов')
    $lines.Add('')
    $lines.Add('Этот файл создается детерминированно командой scripts/update-plan-index.ps1. Не редактируй его вручную.')
    $lines.Add('')
    foreach ($status in $groups.Keys) {
        $lines.Add('## ' + $groups[$status])
        $lines.Add('')
        $lines.Add('| Plan ID | Task key | Текущая фаза | Обновлено | План |')
        $lines.Add('|---|---|---|---|---|')
        $items = @($summaries | Where-Object { $_.Status -ceq $status } | Sort-Object -Property TaskKey, RelativePath)
        if ($items.Count -eq 0) {
            $lines.Add('| Пока нет | - | - | - | - |')
        }
        else {
            foreach ($item in $items) {
                $label = ([string]$item.Title).Replace('|', '\|')
                $target = [System.IO.Path]::GetFileName([string]$item.RelativePath)
                $lines.Add('| ' + $item.PlanId + ' | ' + $item.TaskKey + ' | ' + $item.CurrentPhase + ' | ' + $item.UpdatedAt + ' | [' + $label + '](' + $target + ') |')
            }
        }
        $lines.Add('')
    }
    $unknown = @($summaries | Where-Object { $_.Status -cnotin @($groups.Keys) })
    if ($unknown.Count -gt 0) {
        $lines.Add('## Требуют исправления')
        $lines.Add('')
        foreach ($item in ($unknown | Sort-Object -Property RelativePath)) {
            $target = [System.IO.Path]::GetFileName([string]$item.RelativePath)
            $lines.Add('- [' + $item.Title + '](' + $target + ') - status ' + $item.Status + '.')
        }
        $lines.Add('')
    }
    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ceq '') {
        $lines.RemoveAt($lines.Count - 1)
    }
    return (($lines -join "`n") + "`n")
}

function Write-ModelProjectAtomicText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content,
        [switch]$CreateNew
    )
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory)
    }
    $temporary = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($temporary, $Content, $script:Utf8NoBom)
        if ($CreateNew -and (Test-Path -LiteralPath $Path)) { throw "Файл уже существует: $Path" }
        [System.IO.File]::Move($temporary, $Path, -not $CreateNew)
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Update-ModelProjectPlanIndex {
    param(
        [string]$Root = '',
        [ValidateSet('Check', 'Write', 'Report')]
        [string]$Mode = 'Check'
    )
    $rootPath = Get-ModelProjectPlanRoot -Root $Root
    $indexPath = Join-Path $rootPath 'plans/INDEX.md'
    $expected = Get-ModelProjectPlanIndexContent -Root $rootPath
    if ($Mode -ceq 'Write') {
        Write-ModelProjectAtomicText -Path $indexPath -Content $expected
        return [pscustomobject]@{ Changed = $true; Path = $indexPath; Content = $expected }
    }
    $actual = if (Test-Path -LiteralPath $indexPath -PathType Leaf) { Read-ModelProjectPlanText -Path $indexPath } else { $null }
    $matches = $null -ne $actual -and $actual -ceq $expected
    if ($Mode -ceq 'Check' -and -not $matches) { throw 'plans/INDEX.md отсутствует или устарел.' }
    return [pscustomobject]@{ Changed = -not $matches; Path = $indexPath; Content = $expected }
}

function Set-ModelProjectPlanField {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Field,
        $Value
    )
    $replacement = $Field + ': ' + (ConvertTo-ModelProjectPlanYamlScalar -Value $Value)
    $pattern = '(?m)^' + [regex]::Escape($Field) + ':.*$'
    if (-not [regex]::IsMatch($Content, $pattern)) { throw "Plan не содержит поле '$Field'." }
    return [regex]::Replace($Content, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement }, 1)
}

function Get-ModelProjectPlanActiveByTaskKey {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$TaskKey
    )
    $matches = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ModelProjectPlanFiles -Root $Root)) {
        try { $document = Read-ModelProjectPlanDocument -Path $file.FullName -Root $Root } catch { continue }
        if (-not $document.Data.Contains('plan_contract_version') -or [string]$document.Data.plan_contract_version -cne '2') { continue }
        if ([string]$document.Data.task_key -ceq $TaskKey -and [string]$document.Data.status -cin @('planned', 'in-progress', 'blocked')) {
            $matches.Add($document)
        }
    }
    return @($matches)
}

function Invoke-ModelProjectPlanGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )
    $rootPath = ModelProject.Platform\Get-ModelProjectNormalizedFullPath -Path $Root
    $gitPath = ModelProject.Platform\Get-ModelProjectGitExecutable -ControlledRoots @($rootPath)
    $nullDevice = ModelProject.Platform\Get-ModelProjectNullDevice
    $result = ModelProject.Platform\Invoke-ModelProjectProcess `
        -Executable $gitPath `
        -GitEnvironment `
        -Arguments (@(
            '-c', "safe.directory=$rootPath",
            '-c', 'core.fsmonitor=false',
            '-c', "core.hooksPath=$nullDevice",
            '-c', 'core.quotePath=false',
            '-C', $rootPath
        ) + $Arguments)
    if ($result.LimitExceeded) { throw 'Git command output превысил лимит.' }
    if ($result.ExitCode -ne 0 -and -not $AllowFailure) {
        throw "Git command завершилась с кодом $($result.ExitCode)."
    }
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Output = $result.Stdout; Error = $result.Stderr }
}

function Get-ModelProjectPlanWorktreeFingerprint {
    param(
        [string]$Root = '',
        [Parameter(Mandatory = $true)][string]$PlanRef
    )
    $rootPath = Get-ModelProjectPlanRoot -Root $Root
    $normalizedPlanRef = $PlanRef.Replace('\', '/')
    if ($normalizedPlanRef -cnotmatch '^plans/[^/]+\.md$') { throw 'PlanRef должен находиться непосредственно в plans/.' }
    $headResult = Invoke-ModelProjectPlanGit -Root $rootPath -Arguments @('rev-parse', '--verify', 'HEAD') -AllowFailure
    $head = if ($headResult.ExitCode -eq 0) { $headResult.Output.Trim() } else { 'no-head' }
    $filesResult = Invoke-ModelProjectPlanGit -Root $rootPath -Arguments @('ls-files', '--cached', '--others', '--exclude-standard', '-z')
    $paths = @(
        $filesResult.Output.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries) |
            ForEach-Object { ([string]$_).Replace('\', '/') } |
            Where-Object { $_ -cne $normalizedPlanRef -and $_ -cne 'plans/INDEX.md' }
    )
    [Array]::Sort($paths, [System.StringComparer]::Ordinal)
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.AppendLine('fingerprint-contract:1')
    [void]$builder.AppendLine('head:' + $head)
    foreach ($relative in $paths) {
        if ($relative -match '(^|/)\.git(/|$)' -or $relative -match '(^|/)\.\.(/|$)' -or [System.IO.Path]::IsPathRooted($relative)) {
            throw "Git вернул небезопасный путь: $relative"
        }
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $rootPath $relative))
        if (-not (ModelProject.Platform\Test-ModelProjectPathWithinRoot -Root $rootPath -Path $fullPath)) {
            throw "Git path выходит за root: $relative"
        }
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            [void]$builder.AppendLine($relative + ':' + $hash)
        }
        else {
            [void]$builder.AppendLine($relative + ':missing')
        }
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
    $digest = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return 'v1:' + [Convert]::ToHexString($digest).ToLowerInvariant()
}

Microsoft.PowerShell.Core\Export-ModuleMember -Function @(
    'ConvertFrom-ModelProjectPlanScalar',
    'ConvertTo-ModelProjectPlanYamlScalar',
    'Get-ModelProjectPlanRoot',
    'Get-ModelProjectPlanRelativePath',
    'Read-ModelProjectPlanText',
    'Read-ModelProjectPlanDocument',
    'Get-ModelProjectPlanFiles',
    'Get-ModelProjectPlanSummary',
    'Get-ModelProjectPlanIndexContent',
    'Write-ModelProjectAtomicText',
    'Update-ModelProjectPlanIndex',
    'Set-ModelProjectPlanField',
    'Get-ModelProjectPlanActiveByTaskKey',
    'Get-ModelProjectPlanWorktreeFingerprint'
)
