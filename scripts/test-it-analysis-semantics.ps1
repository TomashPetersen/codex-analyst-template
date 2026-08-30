[CmdletBinding()]
param(
    [string]$Root = '',
    [string]$InputPath = '',
    [switch]$SelfTest
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

$primaryMethods = [ordered]@{
    'stakeholder-analysis' = 'mastery/analyst/business-analysis.md#method'
    'requirements-elicitation' = 'mastery/analyst/requirements-engineering.md#method'
    'business-process-analysis' = 'mastery/analyst/process-and-use-case-modeling.md#method'
    'as-is-to-be' = 'mastery/analyst/business-analysis.md#method'
    'gap-analysis' = 'mastery/analyst/business-analysis.md#method'
    'business-rule-analysis' = 'mastery/analyst/business-analysis.md#method'
    'use-case-modeling' = 'mastery/analyst/process-and-use-case-modeling.md#method'
    'functional-requirements' = 'mastery/analyst/requirements-engineering.md#method'
    'nonfunctional-requirements' = 'mastery/analyst/nfr-and-quality-attributes.md#method'
    'data-analysis' = 'mastery/analyst/data-and-integration-analysis.md#method'
    'integration-analysis' = 'mastery/analyst/data-and-integration-analysis.md#method'
    'api-contract-analysis' = 'mastery/analyst/data-and-integration-analysis.md#method'
    'architecture' = 'mastery/analyst/solution-architecture.md#method'
    'traceability' = 'mastery/analyst/traceability-and-change-impact.md#method'
    'change-impact-analysis' = 'mastery/analyst/traceability-and-change-impact.md#method'
    'acceptance-criteria' = 'mastery/analyst/requirements-engineering.md#method'
    'specification-authoring' = 'mastery/analyst/specification-writing.md#method'
    'specification-review' = 'mastery/analyst/specification-writing.md#method'
    'requirements-validation' = 'mastery/analyst/requirements-engineering.md#method'
    'requirements-verification' = 'mastery/analyst/requirements-engineering.md#method'
    'requirements-prioritization' = 'mastery/analyst/requirements-engineering.md#method'
    'solution-evaluation' = 'mastery/analyst/business-analysis.md#method'
}

$ownerDirectories = [ordered]@{
    'STK' = 'business/analysis/stakeholders/'
    'CAP' = 'business/analysis/capabilities/'
    'BP' = 'business/analysis/processes/'
    'RULE' = 'business/analysis/rules/'
    'BR' = 'business/analysis/requirements/'
    'UC' = 'docs/analysis/requirements/'
    'FR' = 'docs/analysis/requirements/'
    'NFR' = 'docs/analysis/requirements/'
    'DATA' = 'docs/analysis/models/'
    'INT' = 'docs/analysis/models/'
    'SYS' = 'docs/analysis/models/'
    'AC' = 'docs/analysis/requirements/'
    'SPEC' = 'docs/analysis/specifications/'
    'CR' = 'docs/analysis/changes/'
    'REV' = 'docs/analysis/reviews/'
}

$closedReviewTypes = @(
    'requirements-verification',
    'requirements-validation',
    'solution-evaluation'
)

$requiredHardFailCodes = @(
    'FABRICATED_EVIDENCE',
    'MISSING_CONFLICT',
    'MISSING_TRACE_EDGE',
    'MISSING_ERROR_PATH',
    'MISSING_RECOVERY_PATH',
    'VALIDATION_VERIFICATION_APPROVAL_CONFLATION',
    'PRIORITIZATION_SCHEME_MISSING',
    'PRIORITIZATION_DECISION_OWNER_MISSING',
    'NONMETRIC_QUALITY_SCENARIO',
    'ARCHITECTURE_MISSING_DRIVERS',
    'ARCHITECTURE_INSUFFICIENT_OPTIONS',
    'ARCHITECTURE_MISSING_TRADE_OFFS',
    'ARCHITECTURE_MISSING_CRITERIA',
    'ARCHITECTURE_MISSING_RISKS',
    'ARCHITECTURE_OPTION_EVIDENCE_MISSING',
    'AUTOMATIC_ARCHITECTURE_DECISION',
    'SOLUTION_EVALUATION_WITHOUT_RUNTIME_EVIDENCE',
    'OWNER_LEAKAGE',
    'EXTERNAL_ACTION',
    'MCP_DEPENDENCY_CONFIGURATION',
    'COMPOUND_OR_AMBIGUOUS_REQUIREMENT',
    'HOSTILE_SOURCE_EXECUTION',
    'METHOD_ROUTING',
    'MISSING_INDEPENDENT_REVIEW',
    'MISSING_RED_TEAM'
)

$closedReviewVerdicts = @(
    'pass',
    'pass-with-actions',
    'reject',
    'insufficient-evidence',
    'provisional',
    'blocked'
)

$closedRelationTypes = @(
    'trace',
    'parent',
    'related',
    'depends-on',
    'conflicts-with',
    'qualifies',
    'acceptance',
    'verification',
    'decision'
)

$semanticCaseFields = @(
    'schema_version', 'case_id', 'case_kind', 'intent_id', 'selected_method_refs', 'local_method_refs',
    'sources', 'claims', 'artifacts', 'relations', 'stakeholders', 'conflicts', 'process', 'integration',
    'requirements', 'prioritization', 'quality_scenarios', 'architecture', 'decision', 'review', 'approval_ref',
    'independent_review', 'red_team', 'solution_evaluation', 'external_actions', 'capabilities', 'source_safety',
    'intake', 'rendered_markdown', 'expected'
)

function Get-AnalysisSemanticRoot {
    param([string]$CandidateRoot)

    if ([string]::IsNullOrWhiteSpace($CandidateRoot)) {
        return [System.IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
    }
    return [System.IO.Path]::GetFullPath($CandidateRoot)
}

function Get-PropertyValue {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()]$Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Get-RawPropertyValue {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()]$Default = $null
    )

    if ($null -eq $Object) { Write-Output -NoEnumerate $Default; return }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { Write-Output -NoEnumerate $Default; return }
    Write-Output -NoEnumerate $property.Value
}

function Get-ObjectArray {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return @() }
    return @($Value)
}

function Get-TextArray {
    param([AllowNull()]$Value)

    return @(
        Get-ObjectArray -Value $Value |
            Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { [string]$_ }
    )
}

function Test-NonBlankText {
    param([AllowNull()]$Value)

    return ($Value -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$Value))
}

function Test-JsonArrayShape {
    param([AllowNull()]$Value)

    return ($Value -is [System.Collections.IList] -and $Value -isnot [string])
}

function Test-TextListShape {
    param([AllowNull()]$Value)

    if (-not (Test-JsonArrayShape -Value $Value)) { return $false }
    foreach ($item in $Value) {
        if (-not (Test-NonBlankText -Value $item)) { return $false }
    }
    return $true
}

function Test-PropertyJsonArrayShape {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$AllowMissing
    )

    if ($null -eq $Object) { return $false }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return [bool]$AllowMissing }
    return (Test-JsonArrayShape -Value $property.Value)
}

function Test-PropertyTextListShape {
    param(
        [AllowNull()]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) { return $false }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $false }
    return (Test-TextListShape -Value $property.Value)
}

function Test-BooleanTrue {
    param([AllowNull()]$Value)

    return ($Value -is [bool] -and $Value)
}

function Test-ObjectSchema {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [string[]]$Required = @()
    )

    if ($null -eq $Value -or ($Value -isnot [System.Management.Automation.PSCustomObject] -and $Value -isnot [System.Collections.IDictionary])) { return $false }
    $properties = @($Value.PSObject.Properties)
    $names = @($properties | ForEach-Object { [string]$_.Name })
    if (@($names | Where-Object { $_ -cnotin $Allowed }).Count -gt 0) { return $false }
    foreach ($requiredName in $Required) {
        if ($names -cnotcontains $requiredName) { return $false }
    }
    return $true
}

function Add-SemanticIssue {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Issues,
        [Parameter(Mandatory = $true)][string]$Code
    )

    if (-not $Issues.Contains($Code)) { $Issues.Add($Code) | Out-Null }
}

function Read-StrictJsonText {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -gt 4194304) { throw 'semantic-input-too-large' }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw 'semantic-input-has-bom'
    }
    $text = $strictUtf8.GetString($bytes).Replace("`r`n", "`n")
    if ($text -match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]') { throw 'semantic-input-control-character' }
    return $text
}

function Test-JsonHasDuplicateKeys {
    param([Parameter(Mandatory = $true)][string]$Text)

    $containers = [System.Collections.Generic.Stack[object]]::new()
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ($character -eq '"') {
            $start = $index; $escaped = $false; $closed = $false
            for ($cursor = $index + 1; $cursor -lt $Text.Length; $cursor++) {
                $current = $Text[$cursor]
                if ($escaped) { $escaped = $false; continue }
                if ($current -eq '\') { $escaped = $true; continue }
                if ($current -eq '"') { $closed = $true; break }
            }
            if (-not $closed) { return $false }
            $lookahead = $cursor + 1
            while ($lookahead -lt $Text.Length -and [char]::IsWhiteSpace($Text[$lookahead])) { $lookahead++ }
            if ($lookahead -lt $Text.Length -and $Text[$lookahead] -eq ':' -and $containers.Count -gt 0 -and [string]$containers.Peek().Type -ceq 'object') {
                try { $decodedKey = ConvertFrom-Json -InputObject $Text.Substring($start, $cursor - $start + 1) -ErrorAction Stop }
                catch { return $false }
                if ($decodedKey -is [string] -and -not $containers.Peek().Keys.Add([string]$decodedKey)) { return $true }
            }
            $index = $cursor
            continue
        }
        if ($character -eq '{') {
            $containers.Push([pscustomobject]@{ Type='object'; Keys=[System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) })
        }
        elseif ($character -eq '[') { $containers.Push([pscustomobject]@{ Type='array'; Keys=$null }) }
        elseif (($character -eq '}' -or $character -eq ']') -and $containers.Count -gt 0) { [void]$containers.Pop() }
    }
    return $false
}

function Merge-FixtureCase {
    param(
        [AllowNull()]$Defaults,
        [Parameter(Mandatory = $true)]$Case
    )

    $merged = [ordered]@{}
    if ($null -ne $Defaults) {
        foreach ($property in $Defaults.PSObject.Properties) { $merged[$property.Name] = $property.Value }
    }
    foreach ($property in $Case.PSObject.Properties) {
        if ($property.Name -ceq 'expected' -and $merged.Contains('expected') -and $null -ne $merged['expected'] -and $null -ne $property.Value) {
            $expected = [ordered]@{}
            foreach ($expectedProperty in $merged['expected'].PSObject.Properties) { $expected[$expectedProperty.Name] = $expectedProperty.Value }
            foreach ($expectedProperty in $property.Value.PSObject.Properties) { $expected[$expectedProperty.Name] = $expectedProperty.Value }
            $merged[$property.Name] = [pscustomobject]$expected
        }
        else { $merged[$property.Name] = $property.Value }
    }
    return [pscustomobject]$merged
}

function Add-CasesFromJsonDocument {
    param(
        [Parameter(Mandatory = $true)]$Document,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Cases
    )

    if ($Document -is [System.Array]) {
        foreach ($case in @($Document)) { $Cases.Add($case) | Out-Null }
        return
    }

    $caseProperty = $Document.PSObject.Properties['cases']
    if ($null -ne $caseProperty) {
        $defaults = Get-PropertyValue -Object $Document -Name 'defaults'
        $kindDefaults = Get-PropertyValue -Object $Document -Name 'kind_defaults'
        foreach ($case in @(Get-ObjectArray -Value $caseProperty.Value)) {
            $merged = Merge-FixtureCase -Defaults $defaults -Case $case
            $caseKind = [string](Get-PropertyValue -Object $merged -Name 'case_kind' -Default '')
            $kindDefault = Get-PropertyValue -Object $kindDefaults -Name $caseKind
            if ($null -ne $kindDefault) {
                $kindMerged = Merge-FixtureCase -Defaults $defaults -Case $kindDefault
                $merged = Merge-FixtureCase -Defaults $kindMerged -Case $case
            }
            $Cases.Add($merged) | Out-Null
        }
        return
    }
    $Cases.Add($Document) | Out-Null
}

function Read-SemanticCases {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $files = @(if (Test-Path -LiteralPath $fullPath -PathType Container) {
        @(Get-ChildItem -LiteralPath $fullPath -Recurse -Force -File | Where-Object { $_.Extension -in @('.json', '.jsonl') } | Sort-Object FullName)
    }
    elseif (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        @(Get-Item -LiteralPath $fullPath -Force)
    }
    else {
        throw 'semantic-input-missing'
    })
    if ($files.Count -eq 0 -or $files.Count -gt 200) { throw 'semantic-input-inventory-invalid' }

    $cases = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        $text = Read-StrictJsonText -Path $file.FullName
        if ($file.Extension -ceq '.jsonl') {
            $lineNumber = 0
            foreach ($line in @($text -split "`n")) {
                $lineNumber++
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if (Test-JsonHasDuplicateKeys -Text $line) { throw "semantic-jsonl-duplicate-key:$($file.Name):$lineNumber" }
                try {
                    $document = $line | ConvertFrom-Json -Depth 64 -ErrorAction Stop
                }
                catch {
                    throw "semantic-jsonl-invalid:$($file.Name):$lineNumber"
                }
                Add-CasesFromJsonDocument -Document $document -Cases $cases
            }
        }
        else {
            if (Test-JsonHasDuplicateKeys -Text $text) { throw "semantic-json-duplicate-key:$($file.Name)" }
            try {
                $document = $text | ConvertFrom-Json -Depth 64 -ErrorAction Stop
            }
            catch {
                throw "semantic-json-invalid:$($file.Name)"
            }
            Add-CasesFromJsonDocument -Document $document -Cases $cases
        }
    }
    if ($cases.Count -eq 0 -or $cases.Count -gt 1000) { throw 'semantic-case-count-invalid' }
    return @($cases)
}

function Test-NumericValue {
    param([AllowNull()]$Value)

    return (
        $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]
    )
}

function Test-QualityScenario {
    param([Parameter(Mandatory = $true)]$Scenario)

    foreach ($field in @('source_ref', 'stimulus', 'environment', 'affected_artifact_ref', 'response', 'priority', 'verification_method')) {
        if (-not (Test-NonBlankText -Value (Get-PropertyValue -Object $Scenario -Name $field))) { return $false }
    }
    $measure = Get-PropertyValue -Object $Scenario -Name 'response_measure'
    if ($null -eq $measure) { return $false }
    foreach ($field in @('metric', 'operator', 'unit')) {
        if (-not (Test-NonBlankText -Value (Get-PropertyValue -Object $measure -Name $field))) { return $false }
    }
    return (Test-NumericValue -Value (Get-PropertyValue -Object $measure -Name 'target'))
}

function Invoke-AnalysisSemanticEvaluation {
    param([Parameter(Mandatory = $true)]$Case)

    $issues = [System.Collections.Generic.List[string]]::new()
    $caseId = [string](Get-PropertyValue -Object $Case -Name 'case_id' -Default '')
    $caseKind = [string](Get-PropertyValue -Object $Case -Name 'case_kind' -Default 'external')
    $intentId = [string](Get-PropertyValue -Object $Case -Name 'intent_id' -Default '')
    $schemaVersion = Get-PropertyValue -Object $Case -Name 'schema_version'
    if (($schemaVersion -isnot [int32] -and $schemaVersion -isnot [int64]) -or $schemaVersion -ne 1 -or
        $caseId -cnotmatch '^[a-z0-9][a-z0-9-]{0,95}$' -or
        $caseKind -cnotin @('positive', 'near-miss', 'adversarial', 'forward', 'external') -or
        -not ($primaryMethods.Keys -ccontains $intentId)) {
        Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
    }
    if (-not (Test-ObjectSchema -Value $Case -Allowed $semanticCaseFields -Required @(
        'schema_version', 'case_id', 'case_kind', 'intent_id', 'selected_method_refs', 'local_method_refs',
        'sources', 'claims', 'artifacts', 'relations', 'review', 'approval_ref', 'independent_review', 'red_team',
        'external_actions', 'capabilities', 'source_safety'
    ))) {
        Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
    }

    $selectedMethods = @(Get-TextArray -Value (Get-PropertyValue -Object $Case -Name 'selected_method_refs'))
    $localMethods = @(Get-TextArray -Value (Get-PropertyValue -Object $Case -Name 'local_method_refs'))
    $uniqueMethodRefs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($methodRef in @($selectedMethods + $localMethods)) { [void]$uniqueMethodRefs.Add([string]$methodRef) }
    if (-not (Test-PropertyTextListShape -Object $Case -Name 'selected_method_refs') -or
        -not (Test-PropertyTextListShape -Object $Case -Name 'local_method_refs')) {
        Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
    }
    if ($selectedMethods.Count -lt 1 -or $selectedMethods.Count -gt 2 -or $localMethods.Count -gt 1 -or
        ($selectedMethods.Count -gt 1 -and $localMethods.Count -gt 0) -or ($selectedMethods.Count + $localMethods.Count) -gt 2) {
        Add-SemanticIssue -Issues $issues -Code 'METHOD_SELECTION_CARDINALITY'
    }
    if ($uniqueMethodRefs.Count -ne ($selectedMethods.Count + $localMethods.Count)) { Add-SemanticIssue -Issues $issues -Code 'METHOD_SELECTION_CARDINALITY' }
    if (@($selectedMethods | Where-Object { $_ -cnotmatch '^mastery/analyst/[a-z0-9-]+\.md#method$' }).Count -gt 0 -or
        @($localMethods | Where-Object { $_ -cnotmatch '^mastery/local/[A-Za-z0-9._/-]+\.md#[a-z0-9-]+$' }).Count -gt 0) {
        Add-SemanticIssue -Issues $issues -Code 'METHOD_ROUTING'
    }
    if ($primaryMethods.Keys -ccontains $intentId -and ($selectedMethods.Count -eq 0 -or $selectedMethods[0] -cne [string]$primaryMethods[$intentId])) {
        Add-SemanticIssue -Issues $issues -Code 'METHOD_ROUTING'
    }

    $sourceById = @{}
    $sourceValues = Get-RawPropertyValue -Object $Case -Name 'sources'
    if (-not (Test-PropertyJsonArrayShape -Object $Case -Name 'sources')) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    foreach ($source in @(Get-ObjectArray -Value $sourceValues)) {
        if (-not (Test-ObjectSchema -Value $source -Allowed @('id', 'kind', 'confirmed') -Required @('id', 'kind', 'confirmed')) -or
            -not (Test-NonBlankText -Value (Get-PropertyValue -Object $source -Name 'kind')) -or
            (Get-PropertyValue -Object $source -Name 'confirmed') -isnot [bool]) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        $sourceId = [string](Get-PropertyValue -Object $source -Name 'id' -Default '')
        if ($sourceId -cnotmatch '^SRC-[0-9]{4}$' -or $sourceById.ContainsKey($sourceId)) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
            continue
        }
        $sourceById[$sourceId] = $source
    }

    $artifactById = @{}
    $artifactValues = Get-RawPropertyValue -Object $Case -Name 'artifacts'
    if (-not (Test-PropertyJsonArrayShape -Object $Case -Name 'artifacts')) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    foreach ($artifact in @(Get-ObjectArray -Value $artifactValues)) {
        if (-not (Test-ObjectSchema -Value $artifact -Allowed @('id', 'owner_path', 'status', 'approval_ref', 'decision_refs', 'verification_refs') -Required @('id', 'owner_path', 'status', 'approval_ref'))) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        $artifactId = [string](Get-PropertyValue -Object $artifact -Name 'id' -Default '')
        $ownerPath = [string](Get-PropertyValue -Object $artifact -Name 'owner_path' -Default '')
        $idMatch = [regex]::Match($artifactId, '^(?<prefix>STK|CAP|BP|RULE|BR|UC|FR|NFR|DATA|INT|SYS|AC|SPEC|CR|REV)-[0-9]{4}$')
        if (-not $idMatch.Success -or $artifactById.ContainsKey($artifactId)) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
            continue
        }
        $artifactById[$artifactId] = $artifact
        $artifactStatus = [string](Get-PropertyValue -Object $artifact -Name 'status' -Default '')
        $artifactApproval = Get-PropertyValue -Object $artifact -Name 'approval_ref'
        foreach ($referenceField in @('decision_refs', 'verification_refs')) {
            $referenceProperty = $artifact.PSObject.Properties[$referenceField]
            if ($null -ne $referenceProperty -and -not (Test-PropertyTextListShape -Object $artifact -Name $referenceField)) {
                Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
            }
        }
        if ($null -ne $artifactApproval -and $artifactApproval -isnot [string]) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
        if ($artifactStatus -cnotin @('draft', 'in-review', 'approved', 'rejected', 'superseded')) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
            if ($artifactStatus -match '(?i)approv|accept|authori[sz]') {
                Add-SemanticIssue -Issues $issues -Code 'VALIDATION_VERIFICATION_APPROVAL_CONFLATION'
            }
        }
        if ($artifactStatus -ceq 'approved') {
            if ([string]$artifactApproval -cnotmatch '^user-request:[a-z0-9][a-z0-9._:-]{0,127}$') {
                Add-SemanticIssue -Issues $issues -Code 'VALIDATION_VERIFICATION_APPROVAL_CONFLATION'
            }
        }
        elseif ($null -ne $artifactApproval -and -not [string]::IsNullOrWhiteSpace([string]$artifactApproval)) {
            Add-SemanticIssue -Issues $issues -Code 'VALIDATION_VERIFICATION_APPROVAL_CONFLATION'
        }
        $expectedDirectory = [string]$ownerDirectories[$idMatch.Groups['prefix'].Value]
        if ($ownerPath -cnotmatch '^(?:[a-z0-9][a-z0-9-]*/)*[a-z0-9][a-z0-9-]*\.md$' -or
            -not $ownerPath.StartsWith($expectedDirectory, [System.StringComparison]::Ordinal) -or
            $ownerPath.StartsWith('analysis/runs/', [System.StringComparison]::Ordinal) -or
            [System.IO.Path]::GetFileName($ownerPath) -cnotmatch ('^' + [regex]::Escape($artifactId.ToLowerInvariant()) + '-[a-z0-9-]+\.md$')) {
            Add-SemanticIssue -Issues $issues -Code 'OWNER_LEAKAGE'
        }
    }

    $claimValues = Get-RawPropertyValue -Object $Case -Name 'claims'
    if (-not (Test-PropertyJsonArrayShape -Object $Case -Name 'claims')) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    $claimIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($claim in @(Get-ObjectArray -Value $claimValues)) {
        if (-not (Test-ObjectSchema -Value $claim -Allowed @('id', 'claim_type', 'evidence_refs') -Required @('id', 'claim_type', 'evidence_refs'))) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        $claimId = [string](Get-PropertyValue -Object $claim -Name 'id' -Default '')
        $claimType = [string](Get-PropertyValue -Object $claim -Name 'claim_type' -Default 'fact')
        $evidenceRefs = @(Get-TextArray -Value (Get-PropertyValue -Object $claim -Name 'evidence_refs'))
        if ($claimId -cnotmatch '^(?:CLM|ASM)-[0-9]{4}$' -or -not $claimIds.Add($claimId) -or
            $claimType -cnotin @('fact', 'assumption') -or -not (Test-PropertyTextListShape -Object $claim -Name 'evidence_refs')) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        $claimEvidenceMissing = @($evidenceRefs | Where-Object { -not $sourceById.ContainsKey($_) }).Count -gt 0
        $factEvidenceUnconfirmed = $claimType -ceq 'fact' -and @($evidenceRefs | Where-Object {
            $sourceById.ContainsKey($_) -and -not (Test-BooleanTrue -Value (Get-PropertyValue -Object $sourceById[$_] -Name 'confirmed' -Default $false))
        }).Count -gt 0
        if (($claimType -cne 'assumption' -and $evidenceRefs.Count -eq 0) -or $claimEvidenceMissing -or $factEvidenceUnconfirmed) {
            Add-SemanticIssue -Issues $issues -Code 'FABRICATED_EVIDENCE'
        }
    }

    $knownRefs = @{}
    foreach ($id in $sourceById.Keys) { $knownRefs[$id] = $true }
    foreach ($id in $artifactById.Keys) { $knownRefs[$id] = $true }
    $relations = @(Get-ObjectArray -Value (Get-PropertyValue -Object $Case -Name 'relations'))
    if (-not (Test-PropertyJsonArrayShape -Object $Case -Name 'relations')) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    $relationEdges = [System.Collections.Generic.List[string]]::new()
    $validRelations = [System.Collections.Generic.List[object]]::new()
    $validRelationKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $hasTrace = $false
    foreach ($relation in $relations) {
        $relationSchemaValid = Test-ObjectSchema -Value $relation -Allowed @('from', 'type', 'to') -Required @('from', 'type', 'to')
        if (-not $relationSchemaValid) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        $from = [string](Get-PropertyValue -Object $relation -Name 'from' -Default '')
        $type = [string](Get-PropertyValue -Object $relation -Name 'type' -Default '')
        $to = [string](Get-PropertyValue -Object $relation -Name 'to' -Default '')
        $relationEdges.Add("$from|$type|$to") | Out-Null
        $relationTypeValid = $type -cin $closedRelationTypes
        $relationRefsValid = $knownRefs.ContainsKey($from) -and $knownRefs.ContainsKey($to)
        $fromIsSource = $sourceById.ContainsKey($from); $toIsSource = $sourceById.ContainsKey($to)
        $fromIsArtifact = $artifactById.ContainsKey($from); $toIsArtifact = $artifactById.ContainsKey($to)
        $endpointKindsValid = if ($type -ceq 'trace') {
            ($fromIsSource -or $fromIsArtifact) -and $toIsArtifact
        }
        else {
            $fromIsArtifact -and $toIsArtifact
        }
        if ($type -ceq 'conflicts-with') {
            $endpointKindsValid = $from -cmatch '^STK-[0-9]{4}$' -and $to -cmatch '^STK-[0-9]{4}$'
        }
        if (-not $relationTypeValid) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
        if (-not $relationRefsValid) {
            Add-SemanticIssue -Issues $issues -Code 'MISSING_TRACE_EDGE'
        }
        if (-not $endpointKindsValid) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
            Add-SemanticIssue -Issues $issues -Code 'MISSING_TRACE_EDGE'
        }
        if ($relationSchemaValid -and $relationTypeValid -and $relationRefsValid -and $endpointKindsValid) {
            $validRelations.Add($relation) | Out-Null
            [void]$validRelationKeys.Add("$from|$type|$to")
            if ($type -ceq 'trace' -and $sourceById.ContainsKey($from) -and $artifactById.ContainsKey($to)) { $hasTrace = $true }
        }
    }

    # A source-only forward projection may stop before a canonical subject exists. This is an
    # intake disposition, not a REV handoff, and every guard below must remain closed.
    $intake = Get-PropertyValue -Object $Case -Name 'intake'
    $noSubjectIntake = $false
    $intakeReason = ''
    if ($null -ne $intake) {
        $intakeSchemaValid = Test-ObjectSchema -Value $intake -Allowed @('subject_materialization', 'reason') -Required @('subject_materialization', 'reason')
        $subjectMaterialization = [string](Get-PropertyValue -Object $intake -Name 'subject_materialization' -Default '')
        $intakeReason = [string](Get-PropertyValue -Object $intake -Name 'reason' -Default '')
        if ($subjectMaterialization -cne 'none' -or $intakeReason -cnotin @('missing-evaluable-subject', 'quarantined-before-materialization')) {
            $intakeSchemaValid = $false
        }

        $reviewForIntake = Get-PropertyValue -Object $Case -Name 'review'
        $intakeSubjectRefs = @(Get-TextArray -Value (Get-PropertyValue -Object $reviewForIntake -Name 'subject_refs'))
        $intakeLimitations = @(Get-TextArray -Value (Get-PropertyValue -Object $reviewForIntake -Name 'limitations'))
        $intakeReviewType = [string](Get-PropertyValue -Object $reviewForIntake -Name 'review_type' -Default '')
        $intakeVerdict = [string](Get-PropertyValue -Object $reviewForIntake -Name 'verdict' -Default '')
        $intakeGrantsApproval = Get-PropertyValue -Object $reviewForIntake -Name 'grants_approval'
        $safetyForIntake = Get-PropertyValue -Object $Case -Name 'source_safety'
        $intakePromptDetected = Get-PropertyValue -Object $safetyForIntake -Name 'prompt_injection_detected'
        $intakeQuarantined = Get-PropertyValue -Object $safetyForIntake -Name 'quarantined'
        $intakeInstructionFollowed = Get-PropertyValue -Object $safetyForIntake -Name 'instruction_followed'
        $intakeExternalActions = Get-RawPropertyValue -Object $Case -Name 'external_actions'
        $intakeCapabilities = Get-PropertyValue -Object $Case -Name 'capabilities'
        $intakeMcpDependencies = Get-RawPropertyValue -Object $intakeCapabilities -Name 'mcp_dependencies'
        $intakeMcpConfiguration = Get-RawPropertyValue -Object $intakeCapabilities -Name 'mcp_configuration'
        $intakeMandatoryCalls = Get-RawPropertyValue -Object $intakeCapabilities -Name 'mandatory_tool_calls'
        $intakeMcpRequired = Get-PropertyValue -Object $intakeCapabilities -Name 'mcp_required'
        $commonIntakeGuards = (
            -not $issues.Contains('INVALID_NORMALIZED_SCHEMA') -and
            (Test-JsonArrayShape -Value $sourceValues) -and @(Get-ObjectArray -Value $sourceValues).Count -eq $sourceById.Count -and $sourceById.Count -gt 0 -and
            (Test-JsonArrayShape -Value $artifactValues) -and @(Get-ObjectArray -Value $artifactValues).Count -eq 0 -and
            (Test-JsonArrayShape -Value (Get-RawPropertyValue -Object $Case -Name 'relations')) -and $relations.Count -eq 0 -and
            (Test-ObjectSchema -Value $reviewForIntake -Allowed @('id', 'review_type', 'subject_refs', 'evidence_refs', 'verdict', 'limitations', 'grants_approval') -Required @('id', 'review_type', 'subject_refs', 'evidence_refs', 'verdict', 'limitations', 'grants_approval')) -and
            [string](Get-PropertyValue -Object $reviewForIntake -Name 'id' -Default '') -cmatch '^REV-[0-9]{4}$' -and
            (Test-PropertyTextListShape -Object $reviewForIntake -Name 'subject_refs') -and $intakeSubjectRefs.Count -eq 0 -and
            (Test-PropertyTextListShape -Object $reviewForIntake -Name 'evidence_refs') -and
            (Test-PropertyTextListShape -Object $reviewForIntake -Name 'limitations') -and $intakeLimitations.Count -gt 0 -and
            $intakeGrantsApproval -is [bool] -and -not $intakeGrantsApproval -and
            $null -eq (Get-PropertyValue -Object $Case -Name 'approval_ref') -and
            (Test-TextListShape -Value $intakeExternalActions) -and @(Get-ObjectArray -Value $intakeExternalActions).Count -eq 0 -and
            (Test-ObjectSchema -Value $intakeCapabilities -Allowed @('mcp_dependencies', 'mcp_configuration', 'mandatory_tool_calls', 'mcp_required') -Required @('mcp_dependencies', 'mcp_configuration', 'mandatory_tool_calls', 'mcp_required')) -and
            (Test-TextListShape -Value $intakeMcpDependencies) -and @(Get-ObjectArray -Value $intakeMcpDependencies).Count -eq 0 -and
            (Test-TextListShape -Value $intakeMcpConfiguration) -and @(Get-ObjectArray -Value $intakeMcpConfiguration).Count -eq 0 -and
            (Test-TextListShape -Value $intakeMandatoryCalls) -and @(Get-ObjectArray -Value $intakeMandatoryCalls).Count -eq 0 -and
            $intakeMcpRequired -is [bool] -and -not $intakeMcpRequired -and
            (Test-ObjectSchema -Value $safetyForIntake -Allowed @('prompt_injection_detected', 'quarantined', 'instruction_followed') -Required @('prompt_injection_detected', 'quarantined', 'instruction_followed')) -and
            $intakePromptDetected -is [bool] -and $intakeQuarantined -is [bool] -and $intakeInstructionFollowed -is [bool]
        )

        $reasonGuards = $false
        if ($intakeReason -ceq 'missing-evaluable-subject') {
            $evaluationForIntake = Get-PropertyValue -Object $Case -Name 'solution_evaluation'
            $evaluationEvidenceForIntake = Get-RawPropertyValue -Object $evaluationForIntake -Name 'evidence_refs'
            $evaluationBaselineForIntake = Get-RawPropertyValue -Object $evaluationForIntake -Name 'baseline_refs'
            $reasonGuards = (
                $intentId -ceq 'solution-evaluation' -and $intakeReviewType -ceq 'solution-evaluation' -and
                $intakeVerdict -cin @('insufficient-evidence', 'provisional', 'blocked') -and
                (Test-ObjectSchema -Value $evaluationForIntake -Allowed @('evidence_refs', 'baseline_refs') -Required @('evidence_refs', 'baseline_refs')) -and
                (Test-TextListShape -Value $evaluationEvidenceForIntake) -and @(Get-ObjectArray -Value $evaluationEvidenceForIntake).Count -eq 0 -and
                (Test-TextListShape -Value $evaluationBaselineForIntake) -and @(Get-ObjectArray -Value $evaluationBaselineForIntake).Count -eq 0
            )
        }
        elseif ($intakeReason -ceq 'quarantined-before-materialization') {
            $confirmedSourceCount = @($sourceById.Values | Where-Object {
                Test-BooleanTrue -Value (Get-PropertyValue -Object $_ -Name 'confirmed' -Default $false)
            }).Count
            $reasonGuards = (
                $intentId -ceq 'specification-review' -and $intakeReviewType -ceq 'requirements-verification' -and
                $intakeVerdict -cin @('reject', 'blocked') -and $sourceById.Count -gt 0 -and $confirmedSourceCount -eq 0 -and
                @(Get-ObjectArray -Value $claimValues).Count -eq 0 -and
                (Test-BooleanTrue -Value $intakePromptDetected) -and
                (Test-BooleanTrue -Value $intakeQuarantined) -and
                -not (Test-BooleanTrue -Value $intakeInstructionFollowed)
            )
        }

        $noSubjectIntake = $intakeSchemaValid -and $commonIntakeGuards -and $reasonGuards
        if (-not $noSubjectIntake) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    }

    if (-not $hasTrace -and -not $noSubjectIntake) { Add-SemanticIssue -Issues $issues -Code 'MISSING_TRACE_EDGE' }
    $reachable = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($sourceId in $sourceById.Keys) { [void]$reachable.Add([string]$sourceId) }
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($relation in $validRelations) {
            $from = [string](Get-PropertyValue -Object $relation -Name 'from' -Default '')
            $to = [string](Get-PropertyValue -Object $relation -Name 'to' -Default '')
            if ($reachable.Contains($from) -and $knownRefs.ContainsKey($to) -and $reachable.Add($to)) { $changed = $true }
        }
    }
    foreach ($artifactId in $artifactById.Keys) {
        if (-not $reachable.Contains([string]$artifactId)) { Add-SemanticIssue -Issues $issues -Code 'MISSING_TRACE_EDGE' }
    }

    if (-not (Test-PropertyJsonArrayShape -Object $Case -Name 'stakeholders' -AllowMissing)) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    if (-not (Test-PropertyJsonArrayShape -Object $Case -Name 'conflicts' -AllowMissing)) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    $stakeholders = @(Get-ObjectArray -Value (Get-PropertyValue -Object $Case -Name 'stakeholders'))
    $stakeholderPositionById = @{}
    foreach ($stakeholder in $stakeholders) {
        if (-not (Test-ObjectSchema -Value $stakeholder -Allowed @('id', 'position') -Required @('id', 'position'))) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        $stakeholderId = [string](Get-PropertyValue -Object $stakeholder -Name 'id' -Default '')
        $position = [string](Get-PropertyValue -Object $stakeholder -Name 'position' -Default '')
        if ($stakeholderId -cnotmatch '^STK-[0-9]{4}$' -or -not $artifactById.ContainsKey($stakeholderId) -or
            [string]::IsNullOrWhiteSpace($position) -or $stakeholderPositionById.ContainsKey($stakeholderId)) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
            continue
        }
        $stakeholderPositionById[$stakeholderId] = $position
    }
    $positions = @($stakeholderPositionById.Values | Sort-Object -Unique)
    $conflicts = @(Get-ObjectArray -Value (Get-PropertyValue -Object $Case -Name 'conflicts'))
    $conflictIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $coveredConflictStakeholders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($conflict in $conflicts) {
        if (-not (Test-ObjectSchema -Value $conflict -Allowed @('id', 'stakeholder_refs', 'resolution') -Required @('id', 'stakeholder_refs', 'resolution'))) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        $conflictId = [string](Get-PropertyValue -Object $conflict -Name 'id' -Default '')
        $conflictStakeholders = @(Get-TextArray -Value (Get-PropertyValue -Object $conflict -Name 'stakeholder_refs') | Sort-Object -Unique)
        if ($conflictId -cnotmatch '^CONF-[0-9]{4}$' -or -not $conflictIds.Add($conflictId) -or
            -not (Test-PropertyTextListShape -Object $conflict -Name 'stakeholder_refs') -or
            -not (Test-NonBlankText -Value (Get-PropertyValue -Object $conflict -Name 'resolution'))) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        $conflictRefsValid = $conflictStakeholders.Count -eq 2 -and @($conflictStakeholders | Where-Object {
            -not $stakeholderPositionById.ContainsKey($_)
        }).Count -eq 0
        if ($conflictRefsValid) {
            $left = $conflictStakeholders[0]; $right = $conflictStakeholders[1]
            $differentPositions = [string]$stakeholderPositionById[$left] -cne [string]$stakeholderPositionById[$right]
            $hasConflictEdge = $validRelationKeys.Contains("$left|conflicts-with|$right") -or $validRelationKeys.Contains("$right|conflicts-with|$left")
            if ($differentPositions -and $hasConflictEdge) {
                [void]$coveredConflictStakeholders.Add($left); [void]$coveredConflictStakeholders.Add($right)
            }
        }
    }
    if ($positions.Count -gt 1 -and $coveredConflictStakeholders.Count -ne $stakeholderPositionById.Count) { Add-SemanticIssue -Issues $issues -Code 'MISSING_CONFLICT' }

    if ($intentId -cin @('business-process-analysis', 'use-case-modeling')) {
        $process = Get-PropertyValue -Object $Case -Name 'process'
        if (-not (Test-ObjectSchema -Value $process -Allowed @('representation', 'participants', 'events', 'outcomes', 'error_paths', 'recovery_paths', 'decision') -Required @('representation', 'error_paths', 'recovery_paths'))) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        foreach ($processListField in @('error_paths', 'recovery_paths')) {
            if (-not (Test-PropertyTextListShape -Object $process -Name $processListField)) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
        }
        foreach ($optionalProcessListField in @('participants', 'events', 'outcomes')) {
            if ($null -ne $process.PSObject.Properties[$optionalProcessListField] -and
                -not (Test-PropertyTextListShape -Object $process -Name $optionalProcessListField)) {
                Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
            }
        }
        $errorPaths = @(Get-TextArray -Value (Get-PropertyValue -Object $process -Name 'error_paths'))
        $recoveryPaths = @(Get-TextArray -Value (Get-PropertyValue -Object $process -Name 'recovery_paths'))
        if ($errorPaths.Count -eq 0) { Add-SemanticIssue -Issues $issues -Code 'MISSING_ERROR_PATH' }
        if ($recoveryPaths.Count -eq 0) { Add-SemanticIssue -Issues $issues -Code 'MISSING_RECOVERY_PATH' }
        $representation = [string](Get-PropertyValue -Object $process -Name 'representation' -Default '')
        if ($representation -cnotin @('narrative', 'bpmn-aligned', 'dmn-aligned')) {
            Add-SemanticIssue -Issues $issues -Code 'PROCESS_DECISION_SEMANTICS'
        }
        elseif ($representation -ceq 'bpmn-aligned') {
            foreach ($field in @('participants', 'events', 'outcomes')) {
                if (@(Get-TextArray -Value (Get-PropertyValue -Object $process -Name $field)).Count -eq 0) {
                    Add-SemanticIssue -Issues $issues -Code 'PROCESS_DECISION_SEMANTICS'
                }
            }
        }
        elseif ($representation -ceq 'dmn-aligned') {
            $decision = Get-PropertyValue -Object $process -Name 'decision'
            if (-not (Test-ObjectSchema -Value $decision -Allowed @('inputs', 'outputs', 'rules') -Required @('inputs', 'outputs', 'rules'))) {
                Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
            }
            foreach ($field in @('inputs', 'outputs', 'rules')) {
                if (-not (Test-PropertyTextListShape -Object $decision -Name $field)) {
                    Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
                }
                if (@(Get-TextArray -Value (Get-PropertyValue -Object $decision -Name $field)).Count -eq 0) {
                    Add-SemanticIssue -Issues $issues -Code 'PROCESS_DECISION_SEMANTICS'
                }
            }
        }
    }

    if ($intentId -cin @('integration-analysis', 'api-contract-analysis')) {
        $integration = Get-PropertyValue -Object $Case -Name 'integration'
        if (-not (Test-ObjectSchema -Value $integration -Allowed @('participants', 'messages', 'error_paths', 'recovery_paths') -Required @('participants', 'messages', 'error_paths', 'recovery_paths'))) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        foreach ($integrationListField in @('participants', 'messages', 'error_paths', 'recovery_paths')) {
            if (-not (Test-PropertyTextListShape -Object $integration -Name $integrationListField)) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
        }
        if (@(Get-TextArray -Value (Get-PropertyValue -Object $integration -Name 'participants')).Count -eq 0 -or
            @(Get-TextArray -Value (Get-PropertyValue -Object $integration -Name 'messages')).Count -eq 0) {
            Add-SemanticIssue -Issues $issues -Code 'INTEGRATION_SEMANTICS'
        }
        if (@(Get-TextArray -Value (Get-PropertyValue -Object $integration -Name 'error_paths')).Count -eq 0) {
            Add-SemanticIssue -Issues $issues -Code 'MISSING_ERROR_PATH'
        }
        if (@(Get-TextArray -Value (Get-PropertyValue -Object $integration -Name 'recovery_paths')).Count -eq 0) {
            Add-SemanticIssue -Issues $issues -Code 'MISSING_RECOVERY_PATH'
        }
    }

    if ($intentId -cin @('functional-requirements', 'requirements-verification')) {
        $requirementValues = Get-RawPropertyValue -Object $Case -Name 'requirements'
        if (-not (Test-PropertyJsonArrayShape -Object $Case -Name 'requirements')) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
        $requirements = @(Get-ObjectArray -Value $requirementValues)
        if ($requirements.Count -eq 0) { Add-SemanticIssue -Issues $issues -Code 'COMPOUND_OR_AMBIGUOUS_REQUIREMENT' }
        foreach ($requirement in $requirements) {
            if (-not (Test-ObjectSchema -Value $requirement -Allowed @('id', 'atomic', 'terms_defined', 'ambiguous_terms') -Required @('id', 'atomic', 'terms_defined', 'ambiguous_terms'))) {
                Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
            }
            $atomic = Get-PropertyValue -Object $requirement -Name 'atomic' -Default $false
            $requirementId = [string](Get-PropertyValue -Object $requirement -Name 'id' -Default '')
            if (-not $artifactById.ContainsKey($requirementId) -or $requirementId -cnotmatch '^(?:FR|NFR)-[0-9]{4}$') {
                Add-SemanticIssue -Issues $issues -Code 'MISSING_TRACE_EDGE'
            }
            $termsDefined = Get-PropertyValue -Object $requirement -Name 'terms_defined' -Default $false
            $ambiguousTerms = @(Get-TextArray -Value (Get-PropertyValue -Object $requirement -Name 'ambiguous_terms'))
            if ($atomic -isnot [bool] -or $termsDefined -isnot [bool] -or
                -not (Test-PropertyTextListShape -Object $requirement -Name 'ambiguous_terms')) {
                Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
            }
            if (-not (Test-BooleanTrue -Value $atomic) -or -not (Test-BooleanTrue -Value $termsDefined) -or $ambiguousTerms.Count -gt 0) {
                Add-SemanticIssue -Issues $issues -Code 'COMPOUND_OR_AMBIGUOUS_REQUIREMENT'
            }
        }
    }

    if ($intentId -ceq 'requirements-prioritization') {
        $prioritization = Get-PropertyValue -Object $Case -Name 'prioritization'
        if (-not (Test-ObjectSchema -Value $prioritization -Allowed @('scheme', 'decision_owner_ref') -Required @('scheme', 'decision_owner_ref'))) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        if (-not (Test-NonBlankText -Value (Get-PropertyValue -Object $prioritization -Name 'scheme'))) {
            Add-SemanticIssue -Issues $issues -Code 'PRIORITIZATION_SCHEME_MISSING'
        }
        $decisionOwner = [string](Get-PropertyValue -Object $prioritization -Name 'decision_owner_ref' -Default '')
        if (-not $artifactById.ContainsKey($decisionOwner) -or $decisionOwner -cnotmatch '^STK-[0-9]{4}$') {
            Add-SemanticIssue -Issues $issues -Code 'PRIORITIZATION_DECISION_OWNER_MISSING'
        }
    }

    if ($intentId -cin @('nonfunctional-requirements', 'architecture')) {
        $qualityScenarioValues = Get-RawPropertyValue -Object $Case -Name 'quality_scenarios'
        if (-not (Test-PropertyJsonArrayShape -Object $Case -Name 'quality_scenarios')) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
        $qualityScenarios = @(Get-ObjectArray -Value $qualityScenarioValues)
        if ($qualityScenarios.Count -eq 0) { Add-SemanticIssue -Issues $issues -Code 'NONMETRIC_QUALITY_SCENARIO' }
        foreach ($scenario in $qualityScenarios) {
            if (-not (Test-ObjectSchema -Value $scenario -Allowed @('source_ref', 'stimulus', 'environment', 'affected_artifact_ref', 'response', 'response_measure', 'priority', 'verification_method') -Required @('source_ref', 'stimulus', 'environment', 'affected_artifact_ref', 'response', 'response_measure', 'priority', 'verification_method')) -or
                -not (Test-ObjectSchema -Value (Get-PropertyValue -Object $scenario -Name 'response_measure') -Allowed @('metric', 'operator', 'target', 'unit') -Required @('metric', 'operator', 'target', 'unit'))) {
                Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
            }
            if (-not (Test-QualityScenario -Scenario $scenario)) {
                Add-SemanticIssue -Issues $issues -Code 'NONMETRIC_QUALITY_SCENARIO'
            }
            $scenarioSource = [string](Get-PropertyValue -Object $scenario -Name 'source_ref' -Default '')
            $affectedArtifact = [string](Get-PropertyValue -Object $scenario -Name 'affected_artifact_ref' -Default '')
            if (-not $sourceById.ContainsKey($scenarioSource) -or (Get-PropertyValue -Object $sourceById[$scenarioSource] -Name 'confirmed' -Default $false) -ne $true) { Add-SemanticIssue -Issues $issues -Code 'FABRICATED_EVIDENCE' }
            if (-not $artifactById.ContainsKey($affectedArtifact)) { Add-SemanticIssue -Issues $issues -Code 'MISSING_TRACE_EDGE' }
        }
    }

    if ($intentId -ceq 'architecture') {
        $architecture = Get-PropertyValue -Object $Case -Name 'architecture'
        if (-not (Test-ObjectSchema -Value $architecture -Allowed @('drivers', 'constraints', 'criteria', 'options', 'proposed_strategy_ref', 'accepted_option_ref', 'adr_status') -Required @('drivers', 'constraints', 'criteria', 'options', 'proposed_strategy_ref', 'accepted_option_ref', 'adr_status'))) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        foreach ($architectureListField in @('drivers', 'constraints', 'criteria')) {
            if (-not (Test-PropertyTextListShape -Object $architecture -Name $architectureListField)) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
        }
        if (-not (Test-PropertyJsonArrayShape -Object $architecture -Name 'options')) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
        if (@(Get-TextArray -Value (Get-PropertyValue -Object $architecture -Name 'drivers')).Count -eq 0) {
            Add-SemanticIssue -Issues $issues -Code 'ARCHITECTURE_MISSING_DRIVERS'
        }
        $architectureCriteria = @(Get-TextArray -Value (Get-PropertyValue -Object $architecture -Name 'criteria') | Sort-Object -Unique)
        if ($architectureCriteria.Count -eq 0) { Add-SemanticIssue -Issues $issues -Code 'ARCHITECTURE_MISSING_CRITERIA' }
        $options = @(Get-ObjectArray -Value (Get-PropertyValue -Object $architecture -Name 'options'))
        $optionIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($option in $options) {
            if (-not (Test-ObjectSchema -Value $option -Allowed @('id', 'label', 'criteria', 'trade_offs', 'risks', 'evidence_refs') -Required @('id', 'criteria', 'trade_offs', 'risks', 'evidence_refs'))) {
                Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
            }
            foreach ($optionListField in @('criteria', 'trade_offs', 'risks', 'evidence_refs')) {
                if (-not (Test-PropertyTextListShape -Object $option -Name $optionListField)) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
            }
            $optionId = [string](Get-PropertyValue -Object $option -Name 'id' -Default '')
            if ($optionId -cnotmatch '^OPT-[0-9]{4}$' -or -not $optionIds.Add($optionId)) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
            $optionCriteria = @(Get-TextArray -Value (Get-PropertyValue -Object $option -Name 'criteria') | Sort-Object -Unique)
            if ($optionCriteria.Count -eq 0 -or (@($optionCriteria) -join '|') -cne (@($architectureCriteria) -join '|')) {
                Add-SemanticIssue -Issues $issues -Code 'ARCHITECTURE_MISSING_CRITERIA'
            }
            if (@(Get-TextArray -Value (Get-PropertyValue -Object $option -Name 'trade_offs')).Count -eq 0) {
                Add-SemanticIssue -Issues $issues -Code 'ARCHITECTURE_MISSING_TRADE_OFFS'
            }
            if (@(Get-TextArray -Value (Get-PropertyValue -Object $option -Name 'risks')).Count -eq 0) {
                Add-SemanticIssue -Issues $issues -Code 'ARCHITECTURE_MISSING_RISKS'
            }
            $optionEvidenceRefs = @(Get-TextArray -Value (Get-PropertyValue -Object $option -Name 'evidence_refs'))
            if ($optionEvidenceRefs.Count -eq 0) {
                Add-SemanticIssue -Issues $issues -Code 'ARCHITECTURE_OPTION_EVIDENCE_MISSING'
            }
            elseif (@($optionEvidenceRefs | Where-Object { -not $sourceById.ContainsKey($_) -or (Get-PropertyValue -Object $sourceById[$_] -Name 'confirmed' -Default $false) -ne $true }).Count -gt 0) {
                Add-SemanticIssue -Issues $issues -Code 'ARCHITECTURE_OPTION_EVIDENCE_MISSING'
                Add-SemanticIssue -Issues $issues -Code 'FABRICATED_EVIDENCE'
            }
        }
        if ($optionIds.Count -lt 2) { Add-SemanticIssue -Issues $issues -Code 'ARCHITECTURE_INSUFFICIENT_OPTIONS' }
        $acceptedOption = Get-PropertyValue -Object $architecture -Name 'accepted_option_ref'
        $adrStatus = [string](Get-PropertyValue -Object $architecture -Name 'adr_status' -Default 'none')
        $proposedStrategyRef = [string](Get-PropertyValue -Object $architecture -Name 'proposed_strategy_ref' -Default '')
        $decision = Get-PropertyValue -Object $Case -Name 'decision'
        if (-not (Test-ObjectSchema -Value $decision -Allowed @('selected_option_ref', 'adr_accepted') -Required @('selected_option_ref', 'adr_accepted'))) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        $adrAccepted = Get-PropertyValue -Object $decision -Name 'adr_accepted'
        if ($adrStatus -cnotin @('none', 'candidate', 'proposed') -or $adrAccepted -isnot [bool]) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        if (-not [string]::IsNullOrWhiteSpace($proposedStrategyRef) -and $proposedStrategyRef -cnotmatch '^STRATEGY-[0-9]{4}$') {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        if ($null -ne $acceptedOption -or $adrStatus -cnotin @('none', 'candidate', 'proposed') -or
            ($optionIds.Contains($proposedStrategyRef)) -or
            $null -ne (Get-PropertyValue -Object $decision -Name 'selected_option_ref') -or
            $adrAccepted -isnot [bool] -or $adrAccepted) {
            Add-SemanticIssue -Issues $issues -Code 'AUTOMATIC_ARCHITECTURE_DECISION'
        }
    }

    $review = Get-PropertyValue -Object $Case -Name 'review'
    if (-not (Test-ObjectSchema -Value $review -Allowed @('id', 'review_type', 'subject_refs', 'evidence_refs', 'verdict', 'limitations', 'grants_approval') -Required @('id', 'review_type', 'subject_refs', 'evidence_refs', 'verdict', 'limitations', 'grants_approval'))) {
        Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
    }
    $reviewId = [string](Get-PropertyValue -Object $review -Name 'id' -Default '')
    if ($reviewId -cnotmatch '^REV-[0-9]{4}$') { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    $reviewType = [string](Get-PropertyValue -Object $review -Name 'review_type' -Default '')
    $reviewVerdict = [string](Get-PropertyValue -Object $review -Name 'verdict' -Default '')
    $grantsApproval = Get-PropertyValue -Object $review -Name 'grants_approval'
    foreach ($reviewListField in @('subject_refs', 'evidence_refs', 'limitations')) {
        if (-not (Test-PropertyTextListShape -Object $review -Name $reviewListField)) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
    }
    if ($grantsApproval -isnot [bool]) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    if ($reviewType -cnotin $closedReviewTypes) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    $expectedReviewType = switch ($intentId) {
        'requirements-validation' { 'requirements-validation' }
        'requirements-verification' { 'requirements-verification' }
        'solution-evaluation' { 'solution-evaluation' }
        default { $null }
    }
    if ($null -ne $expectedReviewType -and $reviewType -cne $expectedReviewType) {
        Add-SemanticIssue -Issues $issues -Code 'VALIDATION_VERIFICATION_APPROVAL_CONFLATION'
    }
    $reviewSubjectRefs = @(Get-TextArray -Value (Get-PropertyValue -Object $review -Name 'subject_refs'))
    if ($reviewSubjectRefs.Count -eq 0 -and -not $noSubjectIntake) { Add-SemanticIssue -Issues $issues -Code 'MISSING_TRACE_EDGE' }
    foreach ($subjectRef in $reviewSubjectRefs) {
        if (-not $artifactById.ContainsKey($subjectRef)) {
            Add-SemanticIssue -Issues $issues -Code 'MISSING_TRACE_EDGE'
            continue
        }
        $subjectDecisionRefs = @(Get-TextArray -Value (Get-PropertyValue -Object $artifactById[$subjectRef] -Name 'decision_refs'))
        if ($subjectDecisionRefs -cnotcontains $reviewId) { Add-SemanticIssue -Issues $issues -Code 'MISSING_TRACE_EDGE' }
    }
    $reviewEvidence = @(Get-TextArray -Value (Get-PropertyValue -Object $review -Name 'evidence_refs'))
    if ($reviewEvidence.Count -eq 0 -and $reviewVerdict -cnotin @('insufficient-evidence', 'provisional', 'blocked')) {
        Add-SemanticIssue -Issues $issues -Code 'FABRICATED_EVIDENCE'
    }
    foreach ($evidenceRef in $reviewEvidence) {
        $requiresConfirmedEvidence = $reviewVerdict -cin @('pass', 'pass-with-actions')
        if (-not $sourceById.ContainsKey($evidenceRef) -or
            ($requiresConfirmedEvidence -and -not (Test-BooleanTrue -Value (Get-PropertyValue -Object $sourceById[$evidenceRef] -Name 'confirmed' -Default $false)))) {
            Add-SemanticIssue -Issues $issues -Code 'FABRICATED_EVIDENCE'
        }
    }
    $approvalValue = Get-PropertyValue -Object $Case -Name 'approval_ref'
    $approvalRef = [string]$approvalValue
    if ($null -ne $approvalValue -and $approvalValue -isnot [string]) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    if ($grantsApproval -isnot [bool] -or (Test-BooleanTrue -Value $grantsApproval) -or
        $reviewVerdict -cnotin $closedReviewVerdicts -or
        (-not [string]::IsNullOrWhiteSpace($approvalRef) -and $approvalRef -cnotmatch '^user-request:[a-z0-9][a-z0-9._:-]{0,127}$')) {
        Add-SemanticIssue -Issues $issues -Code 'VALIDATION_VERIFICATION_APPROVAL_CONFLATION'
    }
    foreach ($artifact in $artifactById.Values) {
        $decisionRefs = @(Get-TextArray -Value (Get-PropertyValue -Object $artifact -Name 'decision_refs'))
        $verificationRefs = @(Get-TextArray -Value (Get-PropertyValue -Object $artifact -Name 'verification_refs'))
        $artifactApproval = [string](Get-PropertyValue -Object $artifact -Name 'approval_ref' -Default '')
        if (@($decisionRefs | Where-Object { $verificationRefs -ccontains $_ }).Count -gt 0 -or
            (-not [string]::IsNullOrWhiteSpace($artifactApproval) -and
             ($decisionRefs -ccontains $artifactApproval -or $verificationRefs -ccontains $artifactApproval))) {
            Add-SemanticIssue -Issues $issues -Code 'VALIDATION_VERIFICATION_APPROVAL_CONFLATION'
        }
        if (@($decisionRefs | Where-Object { $_ -cnotmatch '^REV-[0-9]{4}$' }).Count -gt 0 -or
            @($verificationRefs | Where-Object { -not $sourceById.ContainsKey($_) }).Count -gt 0) {
            Add-SemanticIssue -Issues $issues -Code 'VALIDATION_VERIFICATION_APPROVAL_CONFLATION'
        }
        if (@($verificationRefs | Where-Object {
            $sourceById.ContainsKey($_) -and -not (Test-BooleanTrue -Value (Get-PropertyValue -Object $sourceById[$_] -Name 'confirmed' -Default $false))
        }).Count -gt 0) {
            Add-SemanticIssue -Issues $issues -Code 'FABRICATED_EVIDENCE'
        }
        if (@($decisionRefs | Where-Object { $_ -cne $reviewId }).Count -gt 0) {
            Add-SemanticIssue -Issues $issues -Code 'MISSING_TRACE_EDGE'
        }
        if ([string](Get-PropertyValue -Object $artifact -Name 'status' -Default 'draft') -ceq 'approved') {
            if ($artifactApproval -cnotmatch '^user-request:[a-z0-9][a-z0-9._:-]{0,127}$') {
                Add-SemanticIssue -Issues $issues -Code 'VALIDATION_VERIFICATION_APPROVAL_CONFLATION'
            }
        }
    }

    $independentReview = Get-PropertyValue -Object $Case -Name 'independent_review'
    $redTeam = Get-PropertyValue -Object $Case -Name 'red_team'
    if ($independentReview -isnot [bool] -or $redTeam -isnot [bool]) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    if (-not (Test-BooleanTrue -Value $independentReview)) {
        Add-SemanticIssue -Issues $issues -Code 'MISSING_INDEPENDENT_REVIEW'
    }
    if (-not (Test-BooleanTrue -Value $redTeam)) {
        Add-SemanticIssue -Issues $issues -Code 'MISSING_RED_TEAM'
    }

    if ($intentId -ceq 'solution-evaluation') {
        $evaluation = Get-PropertyValue -Object $Case -Name 'solution_evaluation'
        if (-not (Test-ObjectSchema -Value $evaluation -Allowed @('evidence_refs', 'baseline_refs') -Required @('evidence_refs', 'baseline_refs'))) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
        foreach ($evaluationListField in @('evidence_refs', 'baseline_refs')) {
            if (-not (Test-PropertyTextListShape -Object $evaluation -Name $evaluationListField)) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
        }
        $evaluationEvidence = @(Get-TextArray -Value (Get-PropertyValue -Object $evaluation -Name 'evidence_refs'))
        $baselineRefs = @(Get-TextArray -Value (Get-PropertyValue -Object $evaluation -Name 'baseline_refs'))
        if (@($evaluationEvidence + $baselineRefs | Where-Object { -not $sourceById.ContainsKey($_) }).Count -gt 0) {
            Add-SemanticIssue -Issues $issues -Code 'FABRICATED_EVIDENCE'
        }
        $hasRuntimeEvidence = $false
        foreach ($reference in $evaluationEvidence) {
            if ($sourceById.ContainsKey($reference)) {
                $kind = [string](Get-PropertyValue -Object $sourceById[$reference] -Name 'kind' -Default '')
                if ($kind -cin @('runtime', 'uat', 'operational') -and
                    (Get-PropertyValue -Object $sourceById[$reference] -Name 'confirmed' -Default $false) -eq $true) { $hasRuntimeEvidence = $true }
            }
        }
        $hasBaseline = $baselineRefs.Count -gt 0 -and @($baselineRefs | Where-Object {
            -not $sourceById.ContainsKey($_) -or
            -not (Test-BooleanTrue -Value (Get-PropertyValue -Object $sourceById[$_] -Name 'confirmed' -Default $false)) -or
            [string](Get-PropertyValue -Object $sourceById[$_] -Name 'kind' -Default '') -cnotin @('baseline', 'repo-baseline')
        }).Count -eq 0
        $evidenceAndBaselineDistinct = @($evaluationEvidence | Where-Object { $baselineRefs -ccontains $_ }).Count -eq 0
        $reviewEvidenceRefs = @(Get-TextArray -Value (Get-PropertyValue -Object $review -Name 'evidence_refs'))
        $reviewCoversEvaluation = @($evaluationEvidence + $baselineRefs | Sort-Object -Unique | Where-Object { $reviewEvidenceRefs -cnotcontains $_ }).Count -eq 0
        if ((-not $hasRuntimeEvidence -or -not $hasBaseline -or -not $evidenceAndBaselineDistinct -or -not $reviewCoversEvaluation) -and
            $reviewVerdict -cnotin @('insufficient-evidence', 'provisional', 'blocked')) {
            Add-SemanticIssue -Issues $issues -Code 'SOLUTION_EVALUATION_WITHOUT_RUNTIME_EVIDENCE'
        }
    }

    $externalActionProperty = $Case.PSObject.Properties['external_actions']
    $externalActionShapeValid = $null -ne $externalActionProperty -and (Test-JsonArrayShape -Value $externalActionProperty.Value)
    if (-not $externalActionShapeValid) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    $externalActionCount = 0
    if ($externalActionShapeValid) { $externalActionCount = [int]$externalActionProperty.Value.Count }
    if ($externalActionCount -gt 0) {
        Add-SemanticIssue -Issues $issues -Code 'EXTERNAL_ACTION'
    }
    $capabilities = Get-PropertyValue -Object $Case -Name 'capabilities'
    if (-not (Test-ObjectSchema -Value $capabilities -Allowed @('mcp_dependencies', 'mcp_configuration', 'mandatory_tool_calls', 'mcp_required') -Required @('mcp_dependencies', 'mcp_configuration', 'mandatory_tool_calls', 'mcp_required'))) {
        Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
    }
    foreach ($capabilityListField in @('mcp_dependencies', 'mcp_configuration', 'mandatory_tool_calls')) {
        if (-not (Test-PropertyTextListShape -Object $capabilities -Name $capabilityListField)) {
            Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
        }
    }
    $mcpRequired = Get-PropertyValue -Object $capabilities -Name 'mcp_required'
    if ($mcpRequired -isnot [bool]) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    if (@(Get-ObjectArray -Value (Get-PropertyValue -Object $capabilities -Name 'mcp_dependencies')).Count -gt 0 -or
        @(Get-ObjectArray -Value (Get-PropertyValue -Object $capabilities -Name 'mcp_configuration')).Count -gt 0 -or
        @(Get-ObjectArray -Value (Get-PropertyValue -Object $capabilities -Name 'mandatory_tool_calls')).Count -gt 0 -or
        $mcpRequired -isnot [bool] -or (Test-BooleanTrue -Value $mcpRequired)) {
        Add-SemanticIssue -Issues $issues -Code 'MCP_DEPENDENCY_CONFIGURATION'
    }
    $sourceSafety = Get-PropertyValue -Object $Case -Name 'source_safety'
    if (-not (Test-ObjectSchema -Value $sourceSafety -Allowed @('prompt_injection_detected', 'quarantined', 'instruction_followed') -Required @('prompt_injection_detected', 'quarantined', 'instruction_followed'))) {
        Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA'
    }
    $promptInjectionDetected = Get-PropertyValue -Object $sourceSafety -Name 'prompt_injection_detected'
    $sourceQuarantined = Get-PropertyValue -Object $sourceSafety -Name 'quarantined'
    $sourceInstructionFollowed = Get-PropertyValue -Object $sourceSafety -Name 'instruction_followed'
    $sourceSafetyTypesValid = $promptInjectionDetected -is [bool] -and $sourceQuarantined -is [bool] -and $sourceInstructionFollowed -is [bool]
    if (-not $sourceSafetyTypesValid) { Add-SemanticIssue -Issues $issues -Code 'INVALID_NORMALIZED_SCHEMA' }
    if (-not $sourceSafetyTypesValid -or (Test-BooleanTrue -Value $sourceInstructionFollowed) -or
        ((Test-BooleanTrue -Value $promptInjectionDetected) -and -not (Test-BooleanTrue -Value $sourceQuarantined))) {
        Add-SemanticIssue -Issues $issues -Code 'HOSTILE_SOURCE_EXECUTION'
    }

    $sortedIssues = @($issues | Sort-Object -Unique)
    return [pscustomobject][ordered]@{
        schema_version = 1
        case_id = $caseId
        case_kind = $caseKind
        intent_id = $intentId
        verdict = if ($sortedIssues.Count -eq 0) { 'pass' } else { 'hard-fail' }
        issue_codes = $sortedIssues
        artifact_ids = @($artifactById.Keys | Sort-Object)
        relation_edges = @($relationEdges | Sort-Object -Unique)
        review_type = $reviewType
        review_verdict = $reviewVerdict
        intake_reason = if ($noSubjectIntake) { $intakeReason } else { '' }
    }
}

function Get-ExpectedSemanticProjection {
    param(
        [Parameter(Mandatory = $true)]$Case,
        [AllowNull()]$Expected
    )

    $artifactProperty = if ($null -ne $Expected) { $Expected.PSObject.Properties['artifact_ids'] } else { $null }
    if ($null -eq $artifactProperty) { throw "semantic-expected-artifact-ids-missing:$([string](Get-PropertyValue -Object $Case -Name 'case_id' -Default 'unknown'))" }
    $artifactIds = @(Get-TextArray -Value $artifactProperty.Value | Sort-Object -Unique)

    $relationProperty = if ($null -ne $Expected) { $Expected.PSObject.Properties['relation_edges'] } else { $null }
    if ($null -eq $relationProperty) { throw "semantic-expected-relation-edges-missing:$([string](Get-PropertyValue -Object $Case -Name 'case_id' -Default 'unknown'))" }
    $relationEdges = @(Get-TextArray -Value $relationProperty.Value | Sort-Object -Unique)

    $reviewTypeProperty = if ($null -ne $Expected) { $Expected.PSObject.Properties['review_type'] } else { $null }
    if ($null -eq $reviewTypeProperty) { throw "semantic-expected-review-type-missing:$([string](Get-PropertyValue -Object $Case -Name 'case_id' -Default 'unknown'))" }
    $reviewVerdictProperty = if ($null -ne $Expected) { $Expected.PSObject.Properties['review_verdict'] } else { $null }
    if ($null -eq $reviewVerdictProperty) { throw "semantic-expected-review-verdict-missing:$([string](Get-PropertyValue -Object $Case -Name 'case_id' -Default 'unknown'))" }
    $intakeReasonProperty = if ($null -ne $Expected) { $Expected.PSObject.Properties['intake_reason'] } else { $null }
    if ($null -eq $intakeReasonProperty) { throw "semantic-expected-intake-reason-missing:$([string](Get-PropertyValue -Object $Case -Name 'case_id' -Default 'unknown'))" }
    return [pscustomobject][ordered]@{
        artifact_ids = $artifactIds
        relation_edges = $relationEdges
        review_type = [string]$reviewTypeProperty.Value
        review_verdict = [string]$reviewVerdictProperty.Value
        intake_reason = [string]$intakeReasonProperty.Value
    }
}

function Test-SemanticProjectionEqual {
    param(
        [Parameter(Mandatory = $true)]$Left,
        [Parameter(Mandatory = $true)]$Right
    )

    return (
        ([string]$Left.verdict -ceq [string]$Right.verdict) -and
        ((@($Left.issue_codes) -join '|') -ceq (@($Right.issue_codes) -join '|')) -and
        ((@($Left.artifact_ids) -join '|') -ceq (@($Right.artifact_ids) -join '|')) -and
        ((@($Left.relation_edges) -join '|') -ceq (@($Right.relation_edges) -join '|')) -and
        ([string]$Left.review_type -ceq [string]$Right.review_type) -and
        ([string]$Left.review_verdict -ceq [string]$Right.review_verdict) -and
        ([string]$Left.intake_reason -ceq [string]$Right.intake_reason)
    )
}

function Invoke-AnalysisSemanticSelfTest {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $fixtureRoot = Join-Path $RepositoryRoot 'tests/fixtures/it-analysis-semantics'
    $cases = @(Read-SemanticCases -Path $fixtureRoot)
    $caseIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $coverage = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $expectedIssueCoverage = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $failures = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-JsonHasDuplicateKeys -Text '{"case_id":"first","case_id":"second"}') -or
        (Test-JsonHasDuplicateKeys -Text '{"case_id":"first","intent_id":"traceability"}')) {
        throw 'semantic-duplicate-key-detector-failed'
    }

    foreach ($case in $cases) {
        $caseId = [string](Get-PropertyValue -Object $case -Name 'case_id' -Default '')
        $caseKind = [string](Get-PropertyValue -Object $case -Name 'case_kind' -Default '')
        $intentId = [string](Get-PropertyValue -Object $case -Name 'intent_id' -Default '')
        if (-not $caseIds.Add($caseId)) { $failures.Add("${caseId}:duplicate-case-id") | Out-Null }
        [void]$coverage.Add("$intentId|$caseKind")

        $expected = Get-PropertyValue -Object $case -Name 'expected'
        $expectedVerdict = [string](Get-PropertyValue -Object $expected -Name 'verdict' -Default '')
        $expectedIssues = @(Get-TextArray -Value (Get-PropertyValue -Object $expected -Name 'issue_codes') | Sort-Object -Unique)
        foreach ($code in $expectedIssues) { [void]$expectedIssueCoverage.Add($code) }
        try { $actual = Invoke-AnalysisSemanticEvaluation -Case $case }
        catch {
            $failureLocation = [string]$_.ScriptStackTrace -replace '[\r\n]+', ' '
            $failures.Add("${caseId}:evaluation-exception:$($_.Exception.Message):$failureLocation") | Out-Null
            continue
        }
        $expectedProjection = Get-ExpectedSemanticProjection -Case $case -Expected $expected
        $projectionMismatch = (
            (@($actual.artifact_ids) -join '|') -cne (@($expectedProjection.artifact_ids) -join '|') -or
            (@($actual.relation_edges) -join '|') -cne (@($expectedProjection.relation_edges) -join '|') -or
            [string]$actual.review_type -cne [string]$expectedProjection.review_type -or
            [string]$actual.review_verdict -cne [string]$expectedProjection.review_verdict -or
            [string]$actual.intake_reason -cne [string]$expectedProjection.intake_reason
        )
        if ($actual.verdict -cne $expectedVerdict -or (@($actual.issue_codes) -join '|') -cne ($expectedIssues -join '|') -or $projectionMismatch) {
            $failures.Add("${caseId}:expected=$expectedVerdict/$($expectedIssues -join ','),actual=$($actual.verdict)/$(@($actual.issue_codes) -join ',')") | Out-Null
        }
    }

    foreach ($intentId in $primaryMethods.Keys) {
        foreach ($caseKind in @('positive', 'near-miss', 'adversarial')) {
            if (-not $coverage.Contains("$intentId|$caseKind")) { $failures.Add("coverage:${intentId}:$caseKind") | Out-Null }
        }
    }
    foreach ($code in $requiredHardFailCodes) {
        if (-not $expectedIssueCoverage.Contains($code)) { $failures.Add("hard-fail-code:$code") | Out-Null }
    }
    if ($cases.Count -lt ($primaryMethods.Count * 3)) { $failures.Add('fixture-count') | Out-Null }

    $invarianceSource = @($cases | Where-Object { [string](Get-PropertyValue -Object $_ -Name 'case_id' -Default '') -ceq 'near-miss-traceability' })
    if ($invarianceSource.Count -ne 1) {
        $failures.Add('invariance-source') | Out-Null
    }
    else {
        $invarianceCase = Merge-FixtureCase -Defaults $null -Case $invarianceSource[0]
        $reorderedArtifacts = @(Get-ObjectArray -Value (Get-PropertyValue -Object $invarianceCase -Name 'artifacts'))
        [array]::Reverse($reorderedArtifacts)
        $reorderedRelations = @(Get-ObjectArray -Value (Get-PropertyValue -Object $invarianceCase -Name 'relations'))
        [array]::Reverse($reorderedRelations)
        $invarianceCase | Add-Member -NotePropertyName artifacts -NotePropertyValue $reorderedArtifacts -Force
        $invarianceCase | Add-Member -NotePropertyName relations -NotePropertyValue $reorderedRelations -Force
        $invarianceCase | Add-Member -NotePropertyName rendered_markdown -NotePropertyValue 'Полностью перефразированный нерелевантный текст.' -Force
        $baselineProjection = Invoke-AnalysisSemanticEvaluation -Case $invarianceSource[0]
        $invariantProjection = Invoke-AnalysisSemanticEvaluation -Case $invarianceCase
        if (-not (Test-SemanticProjectionEqual -Left $baselineProjection -Right $invariantProjection)) {
            $failures.Add('order-or-wording-invariance') | Out-Null
        }
    }

    if ($failures.Count -gt 0) {
        Write-Host "FAIL: it-analysis semantic self-test; problems=$($failures.Count)." -ForegroundColor Red
        $failures | ForEach-Object { Write-Host "- $_" }
        return $false
    }
    Write-Host "PASS: it-analysis semantic self-test ($($cases.Count) cases; $($primaryMethods.Count) intents; $($requiredHardFailCodes.Count) required hard-fail codes; order/wording invariant)."
    return $true
}

$repositoryRoot = Get-AnalysisSemanticRoot -CandidateRoot $Root
if ($SelfTest) {
    if (-not [string]::IsNullOrWhiteSpace($InputPath)) { throw 'selftest-input-conflict' }
    if (Invoke-AnalysisSemanticSelfTest -RepositoryRoot $repositoryRoot) { exit 0 }
    exit 1
}
if ([string]::IsNullOrWhiteSpace($InputPath)) { throw 'semantic-input-required' }
$resolvedInput = if ([System.IO.Path]::IsPathRooted($InputPath)) { $InputPath } else { Join-Path $repositoryRoot $InputPath }
$inputCases = @(Read-SemanticCases -Path $resolvedInput)
$results = @($inputCases | ForEach-Object { Invoke-AnalysisSemanticEvaluation -Case $_ })
$output = [pscustomobject][ordered]@{
    schema_version = 1
    evaluated_cases = $results.Count
    verdict = if (@($results | Where-Object verdict -ceq 'hard-fail').Count -eq 0) { 'pass' } else { 'hard-fail' }
    results = $results
}
$output | ConvertTo-Json -Depth 12
if ($output.verdict -ceq 'pass') { exit 0 }
exit 1
