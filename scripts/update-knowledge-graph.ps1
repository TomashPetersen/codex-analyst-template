[CmdletBinding()]
param(
    [string]$Root = '',

    [ValidateSet('Check', 'Write', 'Report', 'SelfTest')]
    [string]$Mode = 'Check'
)

trap {
    $message = [string]$_.Exception.Message
    $code = if ($message -cmatch '^GRAPH:(?<code>[a-z0-9-]+)$') { [string]$Matches['code'] } else { 'internal-validation-error' }
    try { [Console]::Error.WriteLine("FAIL [knowledge-graph]: blocked ($code).") } catch { }
    if ($code -ceq 'internal-validation-error' -and $VerbosePreference -ceq 'Continue') {
        try { [Console]::Error.WriteLine("DETAIL [knowledge-graph]: $message") } catch { }
    }
    exit 1
}

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$graphRelativePath = 'knowledge/graph/INDEX.md'
$maximumInputFiles = 4000
$maximumInputBytes = 48MB
$maximumFileBytes = 2MB
$maximumEdges = 50000

function Stop-Graph {
    param([Parameter(Mandatory = $true)][string]$Code)
    throw "GRAPH:$Code"
}

function Get-EarlyReparsePoint {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)
    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    $pathRoot = [System.IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($pathRoot)) { return $null }
    $current = $pathRoot
    if (Test-Path -LiteralPath $current) {
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $current }
    }
    foreach ($segment in (($full.Substring($pathRoot.Length) -split '[\\/]') | Where-Object { $_ -ne '' })) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { break }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $current }
    }
    return $null
}

function Test-EarlyExactPathCase {
    param([Parameter(Mandatory = $true)][string]$AbsolutePath)
    $full = [System.IO.Path]::GetFullPath($AbsolutePath)
    if (-not (Test-Path -LiteralPath $full)) { return $false }
    $parent = [System.IO.Path]::GetDirectoryName($full)
    $leaf = [System.IO.Path]::GetFileName($full)
    $matches = @([System.IO.Directory]::EnumerateFileSystemEntries($parent) | Where-Object {
        [System.IO.Path]::GetFileName($_).Equals($leaf, [System.StringComparison]::OrdinalIgnoreCase)
    })
    return ($matches.Count -eq 1 -and [System.IO.Path]::GetFileName($matches[0]) -ceq $leaf)
}

$trustedScriptsRoot = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char[]]'\/')
$trustedPlatformModulePath = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($trustedScriptsRoot, 'lib', 'ModelProject.Platform.psm1')
)
if (-not (Test-Path -LiteralPath $trustedPlatformModulePath -PathType Leaf) -or
    $null -ne (Get-EarlyReparsePoint -AbsolutePath $trustedPlatformModulePath) -or
    -not (Test-EarlyExactPathCase -AbsolutePath $trustedPlatformModulePath)) {
    Stop-Graph 'trusted-platform-integrity'
}
$trustedPlatformModule = Import-Module -Name $trustedPlatformModulePath -Scope Local -Force -PassThru -ErrorAction Stop
$trustedPlatformExportNames = @(
    'Get-ModelProjectNormalizedFullPath', 'Resolve-ModelProjectFileSystemLinkPath',
    'Test-ModelProjectIsWindows', 'Test-ModelProjectIsMacOS',
    'Get-ModelProjectNullDevice', 'Get-ModelProjectPathComparison', 'Test-ModelProjectPathWithinRoot',
    'Get-ModelProjectLinkInFullChain', 'Assert-ModelProjectNoLinkInFullChain',
    'Get-ModelProjectTrustedApplication', 'Get-ModelProjectGitExecutable', 'Get-ModelProjectPowerShellHost',
    'Set-ModelProjectSanitizedGitEnvironment', 'Invoke-ModelProjectProcess', 'Assert-ModelProjectInputText',
    'Enter-ModelProjectFileLock', 'Exit-ModelProjectFileLock'
)
if ($null -eq $trustedPlatformModule -or
    $trustedPlatformModule.ExportedCommands.Count -ne $trustedPlatformExportNames.Count) {
    Stop-Graph 'trusted-platform-exports'
}
$pathComparisonCommand = $trustedPlatformModule.ExportedCommands['Get-ModelProjectPathComparison']
if ($null -eq $pathComparisonCommand -or
    $null -eq $pathComparisonCommand.Module -or
    -not [System.IO.Path]::GetFullPath([string]$pathComparisonCommand.Module.Path).Equals(
        $trustedPlatformModulePath,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
    Stop-Graph 'trusted-platform-exports'
}
$script:mppGetPathComparison = $pathComparisonCommand
$bootstrapPathComparison = & $script:mppGetPathComparison -Path $trustedScriptsRoot
$trustedModulePath = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($trustedScriptsRoot, 'lib', 'ModelProject.Knowledge.psm1')
)
if (-not (Test-Path -LiteralPath $trustedModulePath -PathType Leaf) -or
    $null -ne (Get-EarlyReparsePoint -AbsolutePath $trustedModulePath) -or
    -not (Test-EarlyExactPathCase -AbsolutePath $trustedModulePath) -or
    -not (Test-EarlyExactPathCase -AbsolutePath ([System.IO.Path]::GetDirectoryName($trustedModulePath)))) {
    Stop-Graph 'trusted-module-integrity'
}
$trustedModule = Import-Module -Name $trustedModulePath -Scope Local -Force -PassThru -ErrorAction Stop
$requiredCommands = @(
    'Test-ModelProjectPathWithinRoot',
    'Get-ModelProjectReparsePointInFullChain',
    'Get-ModelProjectRepositoryRelativePath',
    'Test-ModelProjectExactPathCase',
    'Read-ModelProjectBoundedUtf8File',
    'Resolve-ModelProjectSafeReference',
    'Get-ModelProjectSensitiveTextFindings'
)
$trustedCommands = @{}
foreach ($commandName in $requiredCommands) {
    $command = $trustedModule.ExportedCommands[$commandName]
    if ($null -eq $command -or $command.CommandType -ne [System.Management.Automation.CommandTypes]::Function -or
        $null -eq $command.Module -or
        -not [System.IO.Path]::GetFullPath([string]$command.Module.Path).Equals($trustedModulePath, $bootstrapPathComparison)) {
        Stop-Graph 'trusted-module-exports'
    }
    $trustedCommands[$commandName] = $command
}

function Read-SafeText {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$Path,
        [long]$MaxBytes = $maximumFileBytes
    )
    try {
        return & $trustedCommands['Read-ModelProjectBoundedUtf8File'] -Root $RepositoryRoot -Path $Path -MaxBytes $MaxBytes
    }
    catch { Stop-Graph 'unsafe-or-unreadable-input' }
}

function Convert-ScalarText {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    $text = ([string]$Value).Trim()
    if ($text -ceq 'null' -or $text -ceq '') { return $null }
    if ($text.Length -ge 2 -and $text[0] -eq '"' -and $text[$text.Length - 1] -eq '"') {
        $inner = $text.Substring(1, $text.Length - 2)
        $slash = [string][char]92
        $inner = $inner.Replace($slash + '"', '"').Replace($slash + $slash, $slash)
        return $inner
    }
    if ($text.Length -ge 2 -and $text[0] -eq "'" -and $text[$text.Length - 1] -eq "'") {
        return $text.Substring(1, $text.Length - 2).Replace("''", "'")
    }
    return $text
}

function Read-FrontMatterMap {
    param([Parameter(Mandatory = $true)][string]$Text)
    $map = @{}
    $lines = @($Text -split "\r?\n")
    if ($lines.Count -lt 3 -or $lines[0] -cne '---') { return $map }
    $end = -1
    for ($i = 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -ceq '---') { $end = $i; break } }
    if ($end -lt 0) { return $map }
    $currentKey = $null
    for ($i = 1; $i -lt $end; $i++) {
        $line = $lines[$i]
        if ($line -cmatch '^(?<key>[a-z][a-z0-9_]*)[ \t]*:[ \t]*(?<value>.*)$') {
            $currentKey = [string]$Matches['key']
            $raw = [string]$Matches['value']
            if ($raw -ceq '[]') { $map[$currentKey] = @(); continue }
            if ($raw -cmatch '^\[(?<items>.*)\]$') {
                $items = @()
                foreach ($part in @([string]$Matches['items'] -split ',')) {
                    $item = Convert-ScalarText $part
                    if ($null -ne $item) { $items += [string]$item }
                }
                $map[$currentKey] = @($items)
                continue
            }
            if ([string]::IsNullOrWhiteSpace($raw)) { $map[$currentKey] = @(); continue }
            $map[$currentKey] = Convert-ScalarText $raw
            continue
        }
        if ($null -ne $currentKey -and $line -cmatch '^[ \t]+-[ \t]+(?<value>.+)$') {
            $item = Convert-ScalarText ([string]$Matches['value'])
            $existing = if ($map[$currentKey] -is [System.Array]) { @($map[$currentKey]) } elseif ($null -eq $map[$currentKey]) { @() } else { @([string]$map[$currentKey]) }
            if ($null -ne $item) { $existing += [string]$item }
            $map[$currentKey] = @($existing)
        }
    }
    return $map
}

function Get-FirstHeading {
    param([Parameter(Mandatory = $true)][string]$Text)
    $match = [regex]::Match($Text, '(?m)^# (?<heading>[^\r\n]+)$')
    if (-not $match.Success) { return 'Документ' }
    return [string]$match.Groups['heading'].Value.Trim()
}

function ConvertTo-SafeCell {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return '' }
    return ($Value.Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ').Trim())
}

function Get-WikilinkTarget {
    param([Parameter(Mandatory = $true)][string]$RepositoryPath)
    $value = if ($RepositoryPath.EndsWith('.md', [System.StringComparison]::Ordinal)) {
        $RepositoryPath.Substring(0, $RepositoryPath.Length - 3)
    } else { $RepositoryPath }
    return $value
}

function Get-GraphMarkdownLink {
    param([Parameter(Mandatory = $true)][string]$RepositoryPath, [Parameter(Mandatory = $true)][string]$Label)
    $relative = '../../' + $RepositoryPath
    return '[{0}]({1})' -f (ConvertTo-SafeCell $Label), $relative
}

function Get-GraphWikilink {
    param([Parameter(Mandatory = $true)][string]$RepositoryPath, [Parameter(Mandatory = $true)][string]$Label)
    return '[[{0}|{1}]]' -f (Get-WikilinkTarget $RepositoryPath), (ConvertTo-SafeCell $Label)
}

function Test-IsServiceMarkdown {
    param([Parameter(Mandatory = $true)][string]$Path)
    $leaf = [System.IO.Path]::GetFileName($Path)
    return $leaf -cin @('INDEX.md', 'README.md', 'TEMPLATE.md')
}

function Get-InputFiles {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot, [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$SourceOnly)
    $result = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new($script:graphPathComparer)
    foreach ($zone in @('product', 'business', 'docs/analysis', 'docs/architecture', 'docs/codebase', 'docs/decisions', 'mastery/local', 'knowledge/candidates')) {
        $directory = Join-Path $RepositoryRoot $zone
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        if ($null -ne (& $trustedCommands['Get-ModelProjectReparsePointInFullChain'] -Root $RepositoryRoot -Path $directory)) { Stop-Graph 'reparse-input-zone' }
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -Recurse -File -Filter '*.md' -Force | Sort-Object FullName)) {
            $relative = & $trustedCommands['Get-ModelProjectRepositoryRelativePath'] -Root $RepositoryRoot -Path $file.FullName
            if ($relative -ceq $graphRelativePath -or $SourceOnly.Contains($relative) -or $seen.Contains($relative)) { continue }
            if ($relative -cmatch '^knowledge/candidates/TEMPLATE\.md$') { continue }
            if (Test-IsServiceMarkdown -Path $relative) { continue }
            if (-not (& $trustedCommands['Test-ModelProjectExactPathCase'] -Root $RepositoryRoot -Path $file.FullName)) { Stop-Graph 'input-case-mismatch' }
            $result.Add($file) | Out-Null
            [void]$seen.Add($relative)
            if ($result.Count -gt $maximumInputFiles) { Stop-Graph 'input-file-count-limit' }
        }
    }
    return @($result)
}

function Get-FormalAnalysisExpectedKinds {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ($RelativePath -cmatch '^business/analysis/stakeholders/') { return @('stakeholder') }
    if ($RelativePath -cmatch '^business/analysis/capabilities/') { return @('capability') }
    if ($RelativePath -cmatch '^business/analysis/processes/') { return @('business-process') }
    if ($RelativePath -cmatch '^business/analysis/rules/') { return @('business-rule') }
    if ($RelativePath -cmatch '^business/analysis/requirements/') { return @('business-requirement') }
    if ($RelativePath -cmatch '^docs/analysis/requirements/') { return @('use-case', 'functional-requirement', 'nonfunctional-requirement', 'acceptance-criterion') }
    if ($RelativePath -cmatch '^docs/analysis/models/') { return @('data-model', 'integration-contract', 'system-model') }
    if ($RelativePath -cmatch '^docs/analysis/specifications/') { return @('specification') }
    if ($RelativePath -cmatch '^docs/analysis/changes/') { return @('change-request') }
    if ($RelativePath -cmatch '^docs/analysis/reviews/') { return @('review-decision') }
    return @()
}

function Test-IncludedNode {
    param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][hashtable]$Data)
    if ($RelativePath -cmatch '^docs/decisions/') { return ([string]$Data.artifact_kind -ceq 'decision' -and [string]$Data.status -ceq 'accepted') }
    if ($RelativePath -cmatch '^mastery/local/') { return ([string]$Data.status -ceq 'active') }
    if ($RelativePath -cmatch '^knowledge/candidates/[0-9]{4}/KC-') { return $true }
    $formalKinds = @(Get-FormalAnalysisExpectedKinds -RelativePath $RelativePath)
    if ($formalKinds.Count -gt 0) {
        return ([string]$Data.status -ceq 'approved' -and [string]$Data.artifact_kind -cin $formalKinds)
    }
    if ($RelativePath -cmatch '^(?:business|docs)/analysis/') { return $false }
    if ([string]$Data.artifact_kind -cne 'canon' -or [string]$Data.status -cne 'active') { return $false }
    $expectedDomain = if ($RelativePath -cmatch '^product/') { 'product' }
        elseif ($RelativePath -cmatch '^business/') { 'business' }
        elseif ($RelativePath -cmatch '^docs/architecture/') { 'architecture' }
        elseif ($RelativePath -cmatch '^docs/codebase/') { 'codebase' }
        else { '' }
    return -not [string]::IsNullOrWhiteSpace($expectedDomain) -and [string]$Data.domain -ceq $expectedDomain
}

function Get-NodeKind {
    param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][hashtable]$Data)
    if ($RelativePath -cmatch '^knowledge/candidates/') { return 'candidate' }
    if ($RelativePath -cmatch '^mastery/local/') { return 'local-method' }
    if ($RelativePath -cmatch '^docs/decisions/') { return 'decision' }
    if (-not [string]::IsNullOrWhiteSpace([string]$Data.artifact_kind)) { return [string]$Data.artifact_kind }
    return 'canon'
}

function Get-ReferenceValues {
    param([Parameter(Mandatory = $true)][hashtable]$Data)
    $referenceFields = @(
        'provenance_refs', 'source_refs', 'parent_refs', 'related_refs', 'decision_refs',
        'acceptance_refs', 'verification_refs', 'supersedes_ref', 'approval_ref', 'target_ref',
        'conflict_refs', 'supersedes', 'affected_canon', 'related'
    )
    $values = [System.Collections.Generic.List[object]]::new()
    foreach ($field in $referenceFields) {
        if (-not $Data.ContainsKey($field)) { continue }
        foreach ($value in @($Data[$field])) {
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                $values.Add([pscustomobject]@{ Relation = $field; Value = [string]$value }) | Out-Null
            }
        }
    }
    return @($values)
}

function Get-MarkdownTargets {
    param([Parameter(Mandatory = $true)][string]$Text)
    $targets = [System.Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches($Text, '(?m)(?<!!)\[[^\]\r\n]+\]\((?<target>[^)\r\n]+)\)')) {
        $raw = [string]$match.Groups['target'].Value.Trim()
        if ($raw.StartsWith('<') -and $raw.EndsWith('>')) { $raw = $raw.Substring(1, $raw.Length - 2) }
        if ($raw -cmatch '^(?<path>\S+)[ \t]+["'']') { $raw = [string]$Matches['path'] }
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $targets.Add([pscustomobject]@{ Target=$raw; ReferenceBase='File'; Relation='body-link' }) | Out-Null
        }
    }
    foreach ($match in [regex]::Matches($Text, '\[\[(?<target>[^\]|]+)(?:\|[^\]]+)?\]\]')) {
        $raw = [string]$match.Groups['target'].Value.Trim()
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $parts = $raw.Split('#', 2)
            if (-not $parts[0].EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) { $parts[0] += '.md' }
            $raw = if ($parts.Count -gt 1) { $parts[0] + '#' + $parts[1] } else { $parts[0] }
            $targets.Add([pscustomobject]@{ Target=$raw; ReferenceBase='Repository'; Relation='wikilink' }) | Out-Null
        }
    }
    return @($targets)
}

function Get-SafeEvidenceLabel {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -cmatch '^logical:[A-Za-z0-9._:/-]+$') { return $Value }
    if ($Value -cmatch '^(?i:https://)') {
        $uri = $null
        if ([System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$uri) -and $uri.Scheme -ieq 'https' -and [string]::IsNullOrWhiteSpace($uri.UserInfo)) {
            return 'https://' + $uri.Host.ToLowerInvariant() + '/'
        }
        return 'external-source'
    }
    $parts = $Value.Split('#', 2)
    return $parts[0]
}

function Build-KnowledgeGraph {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)
    $graphPathComparison = & $script:mppGetPathComparison -Path $RepositoryRoot
    $script:graphPathComparer = if ($graphPathComparison -eq [System.StringComparison]::OrdinalIgnoreCase) {
        [System.StringComparer]::OrdinalIgnoreCase
    }
    else {
        [System.StringComparer]::Ordinal
    }
    $manifestPath = Join-Path $RepositoryRoot '.template-manifest.json'
    $projectPath = Join-Path $RepositoryRoot 'PROJECT.md'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or -not (Test-Path -LiteralPath $projectPath -PathType Leaf)) { Stop-Graph 'missing-project-contract' }
    try { $manifest = Read-SafeText -RepositoryRoot $RepositoryRoot -Path $manifestPath -MaxBytes 1MB | ConvertFrom-Json -ErrorAction Stop }
    catch { Stop-Graph 'invalid-manifest' }
    $sourceOnly = [System.Collections.Generic.HashSet[string]]::new($script:graphPathComparer)
    foreach ($path in @($manifest.source_only_paths)) { [void]$sourceOnly.Add([string]$path) }

    $files = @(Get-InputFiles -RepositoryRoot $RepositoryRoot -SourceOnly $sourceOnly)
    $nodes = [System.Collections.Generic.List[object]]::new()
    $pathMap = @{}
    $idMap = @{}
    [long]$totalBytes = 0
    foreach ($file in $files) {
        $totalBytes += [long]$file.Length
        if ($file.Length -gt $maximumFileBytes -or $totalBytes -gt $maximumInputBytes) { Stop-Graph 'input-corpus-limit' }
        $relative = & $trustedCommands['Get-ModelProjectRepositoryRelativePath'] -Root $RepositoryRoot -Path $file.FullName
        $text = Read-SafeText -RepositoryRoot $RepositoryRoot -Path $file.FullName
        if (@(& $trustedCommands['Get-ModelProjectSensitiveTextFindings'] -Text $text).Count -gt 0) { Stop-Graph 'unsafe-input-content' }
        $data = Read-FrontMatterMap -Text $text
        if (-not (Test-IncludedNode -RelativePath $relative -Data $data)) { continue }
        $identifier = $null
        foreach ($field in @('id', 'method_id')) {
            if (-not [string]::IsNullOrWhiteSpace([string]$data[$field])) { $identifier = [string]$data[$field]; break }
        }
        $heading = Get-FirstHeading -Text $text
        $label = if ($null -ne $identifier) { $identifier } elseif ($relative -ceq 'PROJECT.md') { 'PROJECT' } else { $heading }
        $state = if (-not [string]::IsNullOrWhiteSpace([string]$data.state)) { [string]$data.state } else { [string]$data.status }
        $node = [pscustomobject]@{
            Key = if ($null -ne $identifier) { $identifier } else { $relative }
            Label = $label
            Kind = Get-NodeKind -RelativePath $relative -Data $data
            State = $state
            Path = $relative
            FullPath = $file.FullName
            Text = $text
            Data = $data
        }
        $nodes.Add($node) | Out-Null
        $pathMap[$relative.ToLowerInvariant()] = $node
        if ($null -ne $identifier) {
            $idKey = $identifier.ToUpperInvariant()
            if ($idMap.ContainsKey($idKey)) { Stop-Graph 'duplicate-node-id' }
            $idMap[$idKey] = $node
        }
    }

    $edges = [System.Collections.Generic.List[object]]::new()
    $evidence = [System.Collections.Generic.List[object]]::new()
    $edgeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $evidenceSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($node in $nodes) {
        foreach ($reference in @(Get-ReferenceValues -Data $node.Data)) {
            $targetNode = $null
            $value = [string]$reference.Value
            if ($idMap.ContainsKey($value.ToUpperInvariant())) { $targetNode = $idMap[$value.ToUpperInvariant()] }
            else {
                try {
                    $resolved = & $trustedCommands['Resolve-ModelProjectSafeReference'] -Root $RepositoryRoot -SourcePath $node.FullPath -Reference $value -ReferenceBase Repository -AllowHttps -AllowLogical
                    if ($resolved.Kind -ceq 'internal' -and $resolved.Exists -and $resolved.ExactCase) {
                        $pathKey = ([string]$resolved.RepositoryPath).ToLowerInvariant()
                        if ($pathMap.ContainsKey($pathKey)) { $targetNode = $pathMap[$pathKey] }
                    }
                }
                catch { Stop-Graph 'invalid-machine-reference' }
            }
            if ($null -ne $targetNode) {
                $edgeKey = "$($node.Path)`n$($reference.Relation)`n$($targetNode.Path)"
                if ($edgeSet.Add($edgeKey)) { $edges.Add([pscustomobject]@{ From=$node; Relation=[string]$reference.Relation; To=$targetNode }) | Out-Null }
            }
            else {
                $safeLabel = Get-SafeEvidenceLabel -Value $value
                $evidenceKey = "$($node.Path)`n$($reference.Relation)`n$safeLabel"
                if ($evidenceSet.Add($evidenceKey)) { $evidence.Add([pscustomobject]@{ From=$node; Relation=[string]$reference.Relation; Target=$safeLabel }) | Out-Null }
            }
        }
        foreach ($markdownReference in @(Get-MarkdownTargets -Text $node.Text)) {
            $target = [string]$markdownReference.Target
            if ($target.StartsWith('#') -or $target -cmatch '^(?i:https://|logical:)') { continue }
            try {
                $resolved = & $trustedCommands['Resolve-ModelProjectSafeReference'] -Root $RepositoryRoot -SourcePath $node.FullPath -Reference $target -ReferenceBase ([string]$markdownReference.ReferenceBase) -AllowHttps
                if ($resolved.Kind -ceq 'internal' -and $resolved.Exists -and $resolved.ExactCase) {
                    $pathKey = ([string]$resolved.RepositoryPath).ToLowerInvariant()
                    if ($pathMap.ContainsKey($pathKey)) {
                        $targetNode = $pathMap[$pathKey]
                        $relation = [string]$markdownReference.Relation
                        $edgeKey = "$($node.Path)`n$relation`n$($targetNode.Path)"
                        if ($edgeSet.Add($edgeKey)) { $edges.Add([pscustomobject]@{ From=$node; Relation=$relation; To=$targetNode }) | Out-Null }
                    }
                }
            }
            catch { Stop-Graph 'invalid-markdown-reference' }
        }
        if ($edges.Count -gt $maximumEdges) { Stop-Graph 'edge-count-limit' }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @(
        '# Граф знаний проекта', '',
        'Производное deterministic-представление canonical refs. Нормативный текст остается в owner artifacts.', '',
        '- [Knowledge contract](../INDEX.md)',
        '- [Root navigation](../../INDEX.md)', '',
        '## Узлы', '',
        '| Key | Kind | State | Document | Wikilink |',
        '|---|---|---|---|---|'
    )) { $lines.Add($line) | Out-Null }
    foreach ($node in @($nodes | Sort-Object @{Expression={$_.Key.ToLowerInvariant()}}, Path)) {
        $lines.Add(('| {0} | {1} | {2} | {3} | {4} |' -f
            (ConvertTo-SafeCell $node.Key), (ConvertTo-SafeCell $node.Kind), (ConvertTo-SafeCell $node.State),
            (Get-GraphMarkdownLink -RepositoryPath $node.Path -Label $node.Label),
            (Get-GraphWikilink -RepositoryPath $node.Path -Label $node.Label))) | Out-Null
    }
    foreach ($section in @('Исходящие связи', 'Обратные связи')) {
        $lines.Add('') | Out-Null; $lines.Add("## $section") | Out-Null; $lines.Add('') | Out-Null
        $lines.Add('| From | Relation | To | Wikilink |') | Out-Null; $lines.Add('|---|---|---|---|') | Out-Null
        $records = if ($section -ceq 'Исходящие связи') { @($edges | Sort-Object {$_.From.Key}, Relation, {$_.To.Key}) } else { @($edges | Sort-Object {$_.To.Key}, Relation, {$_.From.Key}) }
        foreach ($edge in $records) {
            $from = if ($section -ceq 'Исходящие связи') { $edge.From } else { $edge.To }
            $to = if ($section -ceq 'Исходящие связи') { $edge.To } else { $edge.From }
            $lines.Add(('| {0} | {1} | {2} | {3} |' -f
                (ConvertTo-SafeCell $from.Key), (ConvertTo-SafeCell $edge.Relation),
                (Get-GraphMarkdownLink -RepositoryPath $to.Path -Label $to.Label),
                (Get-GraphWikilink -RepositoryPath $to.Path -Label $to.Label))) | Out-Null
        }
    }
    $connected = [System.Collections.Generic.HashSet[string]]::new($script:graphPathComparer)
    foreach ($edge in $edges) { [void]$connected.Add($edge.From.Path); [void]$connected.Add($edge.To.Path) }
    $lines.Add('') | Out-Null; $lines.Add('## Orphans') | Out-Null; $lines.Add('') | Out-Null
    $orphans = @($nodes | Where-Object { $_.Path -cne 'PROJECT.md' -and -not $connected.Contains($_.Path) } | Sort-Object Key)
    if ($orphans.Count -eq 0) { $lines.Add('- Нет.') | Out-Null } else { foreach ($node in $orphans) { $lines.Add('- ' + (Get-GraphMarkdownLink -RepositoryPath $node.Path -Label $node.Label)) | Out-Null } }
    $lines.Add('') | Out-Null; $lines.Add('## Conflicts') | Out-Null; $lines.Add('') | Out-Null
    $conflicts = @($edges | Where-Object { $_.Relation -ceq 'conflict_refs' } | Sort-Object {$_.From.Key}, {$_.To.Key})
    if ($conflicts.Count -eq 0) { $lines.Add('- Нет.') | Out-Null } else { foreach ($edge in $conflicts) { $lines.Add(('- {0} -> {1}' -f (ConvertTo-SafeCell $edge.From.Key), (Get-GraphMarkdownLink -RepositoryPath $edge.To.Path -Label $edge.To.Label))) | Out-Null } }
    $lines.Add('') | Out-Null; $lines.Add('## Evidence refs') | Out-Null; $lines.Add('') | Out-Null
    $lines.Add('| From | Relation | Evidence |') | Out-Null; $lines.Add('|---|---|---|') | Out-Null
    foreach ($item in @($evidence | Sort-Object {$_.From.Key}, Relation, Target)) {
        $lines.Add(('| {0} | {1} | `{2}` |' -f (ConvertTo-SafeCell $item.From.Key), (ConvertTo-SafeCell $item.Relation), (ConvertTo-SafeCell $item.Target))) | Out-Null
    }
    if ($evidence.Count -eq 0) { $lines.Add('| - | - | - |') | Out-Null }
    $content = (($lines -join "`n").TrimEnd() + "`n")
    return [pscustomobject]@{ Content=$content; NodeCount=$nodes.Count; EdgeCount=$edges.Count; OrphanCount=$orphans.Count; ConflictCount=$conflicts.Count; EvidenceCount=$evidence.Count }
}

function Get-RepositoryRoot {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$InputRoot)
    $candidate = if ([string]::IsNullOrWhiteSpace($InputRoot)) { Split-Path -Parent $trustedScriptsRoot } else { $InputRoot }
    try { $full = [System.IO.Path]::GetFullPath($candidate).TrimEnd([char[]]'\/') } catch { Stop-Graph 'invalid-root' }
    if (-not (Test-Path -LiteralPath $full -PathType Container) -or $null -ne (Get-EarlyReparsePoint -AbsolutePath $full)) { Stop-Graph 'unsafe-root' }
    return $full
}

function Write-GraphAtomically {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot, [Parameter(Mandatory = $true)][string]$Content)
    $graphPath = Join-Path $RepositoryRoot $graphRelativePath
    $graphDirectory = Split-Path -Parent $graphPath
    if ($null -ne (& $trustedCommands['Get-ModelProjectReparsePointInFullChain'] -Root $RepositoryRoot -Path $graphDirectory)) { Stop-Graph 'reparse-graph-path' }
    if (-not (Test-Path -LiteralPath $graphDirectory -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($graphDirectory) | Out-Null
    }
    if ($null -ne (& $trustedCommands['Get-ModelProjectReparsePointInFullChain'] -Root $RepositoryRoot -Path $graphDirectory)) { Stop-Graph 'reparse-graph-path' }
    $temporaryPath = Join-Path $graphDirectory ('.knowledge-graph-{0}.tmp' -f [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $Content, $utf8NoBom)
        if (Test-Path -LiteralPath $graphPath -PathType Leaf) {
            $existing = Read-SafeText -RepositoryRoot $RepositoryRoot -Path $graphPath
            if ($existing -ceq $Content) { return $false }
            [System.IO.File]::Move($temporaryPath, $graphPath, $true)
        }
        else { [System.IO.File]::Move($temporaryPath, $graphPath) }
        return $true
    }
    finally { if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force } }
}

function Invoke-GraphMode {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot, [Parameter(Mandatory = $true)][string]$SelectedMode)
    $result = Build-KnowledgeGraph -RepositoryRoot $RepositoryRoot
    $graphPath = Join-Path $RepositoryRoot $graphRelativePath
    $fresh = $false
    if (Test-Path -LiteralPath $graphPath -PathType Leaf) {
        $fresh = (Read-SafeText -RepositoryRoot $RepositoryRoot -Path $graphPath) -ceq $result.Content
    }
    switch ($SelectedMode) {
        'Write' {
            $changed = Write-GraphAtomically -RepositoryRoot $RepositoryRoot -Content $result.Content
            Write-Host ("PASS [knowledge-graph]: write complete; changed={0}; nodes={1}; edges={2}." -f $changed.ToString().ToLowerInvariant(), $result.NodeCount, $result.EdgeCount)
        }
        'Report' {
            Write-Host 'KNOWLEDGE GRAPH REPORT'
            Write-Host "- fresh: $($fresh.ToString().ToLowerInvariant())"
            Write-Host "- nodes: $($result.NodeCount)"
            Write-Host "- edges: $($result.EdgeCount)"
            Write-Host "- orphans: $($result.OrphanCount)"
            Write-Host "- conflicts: $($result.ConflictCount)"
            Write-Host "- evidence_refs: $($result.EvidenceCount)"
            if (-not $fresh) { Stop-Graph 'stale-knowledge-graph' }
        }
        default {
            if (-not $fresh) { Stop-Graph 'stale-knowledge-graph' }
            Write-Host ("PASS [knowledge-graph]: graph is current; nodes={0}; edges={1}." -f $result.NodeCount, $result.EdgeCount)
        }
    }
}

function Invoke-GraphSelfTest {
    $base = Join-Path ([System.IO.Path]::GetTempPath()) ('ModelProjectGraphSelfTest-' + [guid]::NewGuid().ToString('N'))
    $expectedPrefix = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) 'ModelProjectGraphSelfTest-'))
    $tempComparison = & $script:mppGetPathComparison -Path ([System.IO.Path]::GetTempPath())
    if (-not [System.IO.Path]::GetFullPath($base).StartsWith($expectedPrefix, $tempComparison)) { Stop-Graph 'unsafe-selftest-root' }
    $junctionPath = $null
    try {
        [System.IO.Directory]::CreateDirectory($base) | Out-Null
        $fixtureFiles = [ordered]@{
            'PROJECT.md' = "---`nrepository_kind: generated-project`nproject_status: active`nproject_id: graph-fixture`nknowledge_contract_version: 1`nknowledge_capture_mode: report-only`n---`n`n# Graph fixture`n"
            '.template-manifest.json' = '{"schema_version":1,"template_version":"1.4.0","portable_files":[],"portable_empty_directories":[],"source_only_paths":[],"generated_forbidden_paths":[],"generated_extension_zones":[],"mastery_baseline":{"bundle_version":"1","verified_at":"2026-08-16","review_due":"2027-02-16","files":[]}}'
            'INDEX.md' = "# Fixture`n"
            'knowledge/INDEX.md' = "# Knowledge`n"
            'product/overview.md' = "---`nartifact_kind: canon`ncanon_contract_version: 1`ndomain: product`nstatus: active`nverified_at: 2026-08-20`nsource_refs: []`n---`n`n# Product`n`n[Business](../business/overview.md)`n"
            'business/overview.md' = "---`nartifact_kind: canon`ncanon_contract_version: 1`ndomain: business`nstatus: active`nverified_at: 2026-08-20`nsource_refs: []`n---`n`n# Business`n"
            'docs/analysis/requirements/fr-0001-example.md' = "---`nartifact_kind: functional-requirement`nid: FR-0001`nstatus: approved`nrelated_refs:`n  - product/overview.md`n---`n`n# Approved requirement`n"
            'docs/analysis/requirements/fr-0002-draft.md' = "---`nartifact_kind: functional-requirement`nid: FR-0002`nstatus: draft`nrelated_refs: []`n---`n`n# Draft requirement`n"
            'analysis/runs/RUN-20260820-120000-fixture-a1b2c3/analysis.md' = "---`nartifact_kind: analysis-run`nstatus: completed`n---`n`n# Run evidence`n"
            'plans/2026-08-20-fixture.md' = "---`nartifact_kind: plan`nstatus: complete`n---`n`n# Plan`n"
            'knowledge/candidates/TEMPLATE.md' = "# Candidate template`n"
        }
        foreach ($entry in $fixtureFiles.GetEnumerator()) {
            $path = Join-Path $base $entry.Key
            [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
            [System.IO.File]::WriteAllText($path, [string]$entry.Value, $utf8NoBom)
        }
        Invoke-GraphMode -RepositoryRoot $base -SelectedMode 'Write'
        Invoke-GraphMode -RepositoryRoot $base -SelectedMode 'Check'
        $graphPath = Join-Path $base 'knowledge/graph/INDEX.md'
        $graphText = [System.IO.File]::ReadAllText($graphPath, $utf8NoBom)
        if ($graphText -notmatch 'docs/analysis/requirements/fr-0001-example\.md' -or
            $graphText -match 'fr-0002-draft|analysis/runs/|plans/2026-08-20-fixture') {
            Stop-Graph 'formal-analysis-node-boundary-selftest-failed'
        }
        $first = [System.IO.File]::ReadAllBytes($graphPath)
        Invoke-GraphMode -RepositoryRoot $base -SelectedMode 'Write'
        $second = [System.IO.File]::ReadAllBytes($graphPath)
        if ([System.BitConverter]::ToString($first) -cne [System.BitConverter]::ToString($second)) { Stop-Graph 'nondeterministic-selftest' }
        [System.IO.File]::AppendAllText($graphPath, "tamper`n", $utf8NoBom)
        $staleBlocked = $false
        try { Invoke-GraphMode -RepositoryRoot $base -SelectedMode 'Check' } catch { if ([string]$_.Exception.Message -ceq 'GRAPH:stale-knowledge-graph') { $staleBlocked = $true } }
        if (-not $staleBlocked) { Stop-Graph 'stale-selftest-failed' }

        $unsafeRoot = Join-Path $base 'unsafe-root'
        $junctionTarget = Join-Path $base 'junction-target'
        [System.IO.Directory]::CreateDirectory($unsafeRoot) | Out-Null
        [System.IO.Directory]::CreateDirectory($junctionTarget) | Out-Null
        $junctionPath = Join-Path $unsafeRoot 'knowledge'
        New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget -ErrorAction Stop | Out-Null
        $reparseBlocked = $false
        try { [void](Write-GraphAtomically -RepositoryRoot $unsafeRoot -Content "# Unsafe fixture`n") }
        catch { if ([string]$_.Exception.Message -ceq 'GRAPH:reparse-graph-path') { $reparseBlocked = $true } }
        if (-not $reparseBlocked -or (Test-Path -LiteralPath (Join-Path $junctionTarget 'graph'))) {
            Stop-Graph 'prewrite-reparse-selftest-failed'
        }
        Remove-Item -LiteralPath $junctionPath -Force
        $junctionPath = $null
        Write-Host 'PASS: knowledge graph self-test (formal canon boundary, write, check, determinism, stale detection, pre-write reparse block).'
    }
    finally {
        if ($null -ne $junctionPath -and (Test-Path -LiteralPath $junctionPath)) { Remove-Item -LiteralPath $junctionPath -Force }
        if (Test-Path -LiteralPath $base -PathType Container) { Remove-Item -LiteralPath $base -Recurse -Force }
    }
}

if ($Mode -ceq 'SelfTest') { Invoke-GraphSelfTest; exit 0 }
$repositoryRoot = Get-RepositoryRoot -InputRoot $Root
Invoke-GraphMode -RepositoryRoot $repositoryRoot -SelectedMode $Mode
exit 0
