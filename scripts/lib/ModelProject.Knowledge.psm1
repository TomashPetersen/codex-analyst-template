Set-StrictMode -Version 2.0

$script:PlatformModulePath = Join-Path $PSScriptRoot 'ModelProject.Platform.psm1'
Import-Module $script:PlatformModulePath -Scope Local

function Test-ModelProjectFrontMatterScalarValue {
    param(
        $Value,
        [switch]$AllowNull
    )

    if ($null -eq $Value) { return $AllowNull.IsPresent }
    return ($Value -is [string] -or $Value -is [ValueType])
}

function ConvertFrom-ModelProjectSimpleYamlScalar {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    $trimmed = $Value.Trim()
    if ($trimmed -ceq 'null' -or $trimmed -ceq '~') { return $null }
    if ($trimmed -ceq '[]') { return ,[string[]]@() }
    if ($trimmed.Length -ge 2 -and $trimmed.StartsWith("'") -and $trimmed.EndsWith("'")) {
        return $trimmed.Substring(1, $trimmed.Length - 2).Replace("''", "'")
    }
    if ($trimmed.Length -ge 2 -and $trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) {
        return $trimmed.Substring(1, $trimmed.Length - 2).Replace('\"', '"').Replace('\\', '\')
    }
    return $trimmed
}

function Read-ModelProjectSimpleFrontMatterDocument {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path,
        [long]$MaxBytes = 2MB
    )
    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $content = Read-ModelProjectBoundedUtf8File -Root $rootPath -Path $fullPath -MaxBytes $MaxBytes
    $match = [regex]::Match($content, '\A---\r?\n(?<front>.*?)\r?\n---(?:\r?\n|\z)', 'Singleline')
    if (-not $match.Success) { throw "Отсутствует корректный YAML frontmatter: $fullPath" }
    $data = [ordered]@{}
    $currentList = $null
    foreach ($rawLine in ($match.Groups['front'].Value -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }
        if ($rawLine -cmatch '^(?<key>[a-z][a-z0-9_]*)\s*:\s*(?<value>.*)$') {
            $key = [string]$Matches['key']
            if ($data.Contains($key)) { throw "Duplicate frontmatter field '$key': $fullPath" }
            $value = [string]$Matches['value']
            if ([string]::IsNullOrWhiteSpace($value)) {
                $data[$key] = [System.Collections.Generic.List[string]]::new()
                $currentList = $key
            }
            else {
                $data[$key] = ConvertFrom-ModelProjectSimpleYamlScalar -Value $value
                $currentList = $null
            }
            continue
        }
        if ($null -ne $currentList -and $rawLine -cmatch '^\s{2}-\s+(?<value>.+?)\s*$') {
            $data[$currentList].Add([string](ConvertFrom-ModelProjectSimpleYamlScalar -Value $Matches['value']))
            continue
        }
        throw "Неподдерживаемая строка frontmatter: $fullPath"
    }
    foreach ($key in @($data.Keys)) {
        if ($data[$key] -is [System.Collections.Generic.List[string]]) { $data[$key] = @($data[$key]) }
    }
    return [pscustomobject]@{
        Path = $fullPath
        RelativePath = Get-ModelProjectRepositoryRelativePath -Root $rootPath -Path $fullPath
        Content = $content
        Body = $content.Substring($match.Index + $match.Length)
        Data = $data
    }
}

function Test-ModelProjectJsonScalar {
    param($Value)
    return (
        $null -eq $Value -or
        $Value -is [string] -or
        $Value -is [bool] -or
        ($Value -is [ValueType] -and $Value -isnot [datetime] -and $Value -isnot [System.DateTimeOffset])
    )
}

function ConvertTo-ModelProjectPercentDecodedText {
    param([Parameter(Mandatory = $true)][string]$Value)

    $current = [System.Net.WebUtility]::HtmlDecode($Value)
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try {
            $decoded = [System.Uri]::UnescapeDataString($current)
        }
        catch {
            return $current
        }
        if ($decoded -ceq $current) { break }
        $current = $decoded
    }
    return $current
}

function Test-ModelProjectHttpsUrlHasSensitiveQuery {
    param([Parameter(Mandatory = $true)][string]$Value)

    $uri = $null
    if (-not [System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ine 'https') {
        return $false
    }
    $query = [System.Net.WebUtility]::HtmlDecode($uri.Query.TrimStart('?'))
    foreach ($pair in @($query -split '[&;]')) {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $rawName = $pair.Split('=', 2)[0].Replace('+', ' ')
        $decodedName = ConvertTo-ModelProjectPercentDecodedText $rawName
        $normalizedName = ($decodedName.ToLowerInvariant() -replace '[^a-z0-9]', '')
        if ($normalizedName -match '^(?:token|accesstoken|idtoken|refreshtoken|secret|signature|sig|key|apikey|password|passwd|credential|auth|authorization|proxyauthorization|sharedaccesssignature|expires|xamzsignature|xamzcredential|xamzexpires|xamzsecuritytoken|xgoogsignature|xgoogcredential|xgoogexpires|awsaccesskeyid|googleaccessid|policy)$') {
            return $true
        }
    }
    return $false
}

function Get-ModelProjectHttpsUrlSafetyFinding {
    param([Parameter(Mandatory = $true)][string]$Value)

    $uri = $null
    if (-not [System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ine 'https' -or
        [string]::IsNullOrWhiteSpace($uri.Host)) {
        return 'invalid-https-url'
    }
    if (-not [string]::IsNullOrWhiteSpace($uri.UserInfo)) {
        return 'https-url-userinfo'
    }
    if (Test-ModelProjectHttpsUrlHasSensitiveQuery $Value) {
        return 'signed-url'
    }
    return $null
}

function Get-ModelProjectHttpsUrlsFromText {
    param([Parameter(Mandatory = $true)][string]$Text)

    $urls = [System.Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($Text, '(?i)https://[^\s<>"''\)\]\}]+')) {
        $value = $match.Value.TrimEnd([char[]]'.,;:!?')
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $urls.Add($value) | Out-Null
        }
    }
    return @($urls)
}

function Get-ModelProjectSensitiveTextFindings {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    # Shared heuristic denylist for common secret and PII disclosures. It is not
    # a proof that arbitrary obfuscated sensitive data is absent.
    $patterns = [ordered]@{
        'absolute-local-path' = '(?i)(?:(?<![A-Za-z0-9])[A-Z]:[\\/]|(?<![A-Za-z0-9])file:/{0,2}|\\\\[A-Za-z0-9_.-]+[\\/]|(?:^|[\s(\x27\x22])/(?:Users|home|tmp|var/tmp)/)'
        'email-or-pii' = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
        'private-key' = '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
        'bearer-token' = '(?i)\bBearer\s+[A-Za-z0-9._~+/-]{12,}=*'
        'credential-like-token-prefix' = '(?:\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9]{20,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b|\bxox[a-z]-[A-Za-z0-9-]{10,}\b|\bAIza[0-9A-Za-z_-]{35}\b|\b(?:sk|rk)_(?:live|test)_[0-9A-Za-z]{16,}\b|\bsk-[A-Za-z0-9_-]{20,}\b)'
        'jwt' = '\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b'
        'credential-value' = '(?i)\b(?:password|passwd|secret|api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*[\x22\x27]?[A-Za-z0-9._~+/-]{8,}'
        'phone-or-contact' = '(?i)(?:\b(?:phone|mobile|\u0442\u0435\u043b\u0435\u0444\u043e\u043d|\u043c\u043e\u0431\u0438\u043b\u044c\u043d\u044b\u0439|\u043a\u043e\u043d\u0442\u0430\u043a\u0442)\s*[:=]\s*\+?[0-9][0-9 ()-]{6,}[0-9]|(?<![0-9])\+[1-9][0-9 ()-]{7,}[0-9])'
        'full-name-or-pii' = '(?i)\b(?:full[ _-]?legal[ _-]?name|full[ _-]?name|\u0444\u0438\u043e|\u043f\u043e\u043b\u043d\u043e\u0435[ _-]?\u0438\u043c\u044f)\s*(?:/[^:=\r\n]{1,40})?\s*[:=]\s*[\p{L}][\p{L}''-]+(?:\s+[\p{L}][\p{L}''-]+){1,3}\b'
        'home-address-or-pii' = '(?i)\b(?:home[ _-]?address|\u0434\u043e\u043c\u0430\u0448\u043d\u0438\u0439[ _-]?\u0430\u0434\u0440\u0435\u0441|\u0430\u0434\u0440\u0435\u0441[ _-]?\u043f\u0440\u043e\u0436\u0438\u0432\u0430\u043d\u0438\u044f)\s*(?:/[^:=\r\n]{1,40})?\s*[:=]\s*[^\r\n]{8,}'
        'date-of-birth-or-pii' = '(?i)\b(?:date[ _-]?of[ _-]?birth|dob|\u0434\u0430\u0442\u0430[ _-]?\u0440\u043e\u0436\u0434\u0435\u043d\u0438\u044f)\s*(?:/[^:=\r\n]{1,40})?\s*[:=]\s*(?:19|20)\d{2}[-/.](?:0?[1-9]|1[0-2])[-/.](?:0?[1-9]|[12]\d|3[01])\b'
        'cookie-credential' = '(?i)\b(?:cookie|set-cookie)\s*:\s*[^\r\n=;]{1,80}=[^\s;\r\n]{8,}|\b(?:sessionid|session[_-]?token|auth[_-]?cookie)\s*[:=]\s*[A-Za-z0-9._~+/-]{8,}'
        'full-transcript' = '(?i)\b(?:full[ _-]?(?:interview[ _-]?)?transcript|verbatim[ _-]?(?:interview[ _-]?)?transcript|\u043f\u043e\u043b\u043d(?:\u0430\u044f|\u044b\u0439)[ _-]?(?:\u0440\u0430\u0441\u0448\u0438\u0444\u0440\u043e\u0432\u043a\u0430|\u0442\u0440\u0430\u043d\u0441\u043a\u0440\u0438\u043f\u0442)(?:[ _-]?\u0438\u043d\u0442\u0435\u0440\u0432\u044c\u044e)?)\b'
    }
    $findings = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $patterns.GetEnumerator()) {
        if ($Text -match $entry.Value -and $seen.Add([string]$entry.Key)) {
            $findings.Add([string]$entry.Key) | Out-Null
        }
    }
    $speakerTurnCount = @([regex]::Matches(
        $Text,
        '(?im)^[ \t]*(?:interviewer|participant|moderator|respondent|\u0438\u043d\u0442\u0435\u0440\u0432\u044c\u044e\u0435\u0440|\u0443\u0447\u0430\u0441\u0442\u043d\u0438\u043a|\u043c\u043e\u0434\u0435\u0440\u0430\u0442\u043e\u0440|\u0440\u0435\u0441\u043f\u043e\u043d\u0434\u0435\u043d\u0442)[ \t]*:'
    )).Count
    if ($speakerTurnCount -ge 8 -and $seen.Add('full-transcript')) {
        $findings.Add('full-transcript') | Out-Null
    }
    foreach ($url in (Get-ModelProjectHttpsUrlsFromText -Text $Text)) {
        $urlFinding = Get-ModelProjectHttpsUrlSafetyFinding -Value $url
        if ($null -ne $urlFinding -and $seen.Add([string]$urlFinding)) {
            $findings.Add([string]$urlFinding) | Out-Null
        }
    }
    return @($findings)
}

function Remove-ModelProjectCommonMarkContainerPrefixes {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Line)

    $remaining = $Line
    for ($depth = 0; $depth -lt 32; $depth++) {
        if ($remaining -match '^ {0,3}>[ \t]?(?<rest>.*)$') {
            $remaining = [string]$Matches['rest']
            continue
        }
        if ($remaining -match '^ {0,3}(?:[-+*]|\d{1,9}[.)])(?<padding>[ \t]+)(?<rest>.*)$') {
            $padding = [string]$Matches['padding']
            $paddingLength = if ($padding.Contains("`t")) {
                1
            }
            elseif ($padding.Length -le 4) {
                $padding.Length
            }
            else {
                1
            }
            $remaining = $padding.Substring($paddingLength) + [string]$Matches['rest']
            continue
        }
        break
    }
    return $remaining
}

function Test-ModelProjectMarkdownEscaped {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][ValidateRange(0, [int]::MaxValue)][int]$Index
    )

    $backslashCount = 0
    for ($position = $Index - 1; $position -ge 0 -and $Text[$position] -eq [char]'\'; $position--) {
        $backslashCount++
    }
    return ($backslashCount % 2) -eq 1
}

function Get-ModelProjectMarkdownLinkOpenerIndex {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$CloseBracketIndex
    )

    $depth = 0
    for ($cursor = $CloseBracketIndex - 1; $cursor -ge 0; $cursor--) {
        if ($Content[$cursor] -eq ']' -and -not (Test-ModelProjectMarkdownEscaped -Text $Content -Index $cursor)) {
            $depth++
        }
        elseif ($Content[$cursor] -eq '[' -and -not (Test-ModelProjectMarkdownEscaped -Text $Content -Index $cursor)) {
            if ($depth -eq 0) { return $cursor }
            $depth--
        }
    }
    return -1
}

function Move-ModelProjectPastMarkdownLinkWhitespace {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][int]$StartIndex
    )

    $cursor = $StartIndex
    $lineBreaks = 0
    while ($cursor -lt $Content.Length) {
        if ($Content[$cursor] -eq ' ' -or $Content[$cursor] -eq "`t") {
            $cursor++
            continue
        }
        if ($Content[$cursor] -eq "`r" -or $Content[$cursor] -eq "`n") {
            $lineBreaks++
            if ($lineBreaks -gt 1) {
                return [pscustomobject]@{ Valid = $false; Index = $cursor; HadWhitespace = $true }
            }
            if ($Content[$cursor] -eq "`r" -and $cursor + 1 -lt $Content.Length -and
                $Content[$cursor + 1] -eq "`n") {
                $cursor += 2
            }
            else {
                $cursor++
            }
            continue
        }
        break
    }
    return [pscustomobject]@{
        Valid = $true
        Index = $cursor
        HadWhitespace = ($cursor -gt $StartIndex)
    }
}

function Test-ModelProjectInlineMarkdownClosure {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)]$Destination
    )

    if (-not $Destination.Balanced) { return $false }
    $spacing = Move-ModelProjectPastMarkdownLinkWhitespace -Content $Content -StartIndex $Destination.EndIndex
    if (-not $spacing.Valid -or $spacing.Index -ge $Content.Length) { return $false }
    $cursor = $spacing.Index
    if ($Content[$cursor] -eq ')') { return $true }

    if (-not $spacing.HadWhitespace -and $Destination.Target.Length -gt 0) { return $false }
    $opener = $Content[$cursor]
    if ($opener -ne '"' -and $opener -ne "'" -and $opener -ne '(') { return $false }
    $closer = if ($opener -eq '(') { ')' } else { $opener }
    $cursor++
    $titleClosed = $false
    while ($cursor -lt $Content.Length) {
        if ($Content[$cursor] -eq $closer -and -not (Test-ModelProjectMarkdownEscaped -Text $Content -Index $cursor)) {
            $titleClosed = $true
            $cursor++
            break
        }
        $cursor++
    }
    if (-not $titleClosed) { return $false }

    $spacing = Move-ModelProjectPastMarkdownLinkWhitespace -Content $Content -StartIndex $cursor
    return ($spacing.Valid -and $spacing.Index -lt $Content.Length -and $Content[$spacing.Index] -eq ')')
}

function Test-ModelProjectPathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    return (ModelProject.Platform\Test-ModelProjectPathWithinRoot -Root $Root -Path $Path -AllowEqual)
}

function Get-ModelProjectReparsePointInFullChain {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootFull = ModelProject.Platform\Get-ModelProjectNormalizedFullPath -Path $Root
    $pathFull = ModelProject.Platform\Get-ModelProjectNormalizedFullPath -Path $Path
    if (-not (Test-ModelProjectPathWithinRoot -Root $rootFull -Path $pathFull)) {
        throw 'Path is outside Root.'
    }
    return (ModelProject.Platform\Get-ModelProjectLinkInFullChain -Path $pathFull)
}

function Get-ModelProjectRepositoryRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootFull = ModelProject.Platform\Get-ModelProjectNormalizedFullPath -Path $Root
    $pathFull = ModelProject.Platform\Get-ModelProjectNormalizedFullPath -Path $Path
    if (-not (Test-ModelProjectPathWithinRoot -Root $rootFull -Path $pathFull)) {
        throw 'Path is outside Root.'
    }
    $comparison = ModelProject.Platform\Get-ModelProjectPathComparison -Path $rootFull
    if ($pathFull.Equals($rootFull, $comparison)) { return '' }
    return [System.IO.Path]::GetRelativePath($rootFull, $pathFull).Replace('\', '/')
}

function Test-ModelProjectExactPathCase {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootFull = ModelProject.Platform\Get-ModelProjectNormalizedFullPath -Path $Root
    $pathFull = ModelProject.Platform\Get-ModelProjectNormalizedFullPath -Path $Path
    if (-not (Test-ModelProjectPathWithinRoot -Root $rootFull -Path $pathFull)) { return $false }
    if (-not (Test-Path -LiteralPath $pathFull)) { return $false }
    $comparison = ModelProject.Platform\Get-ModelProjectPathComparison -Path $rootFull
    if ($pathFull.Equals($rootFull, $comparison)) {
        return $pathFull -ceq (Get-Item -LiteralPath $pathFull -Force).FullName.TrimEnd([char[]]'\/')
    }

    $relative = Get-ModelProjectRepositoryRelativePath -Root $rootFull -Path $pathFull
    $cursor = $rootFull
    foreach ($segment in @($relative -split '/')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { return $false }
        $matches = @(
            Get-ChildItem -LiteralPath $cursor -Force -ErrorAction Stop |
                Where-Object { $_.Name.Equals($segment, [System.StringComparison]::OrdinalIgnoreCase) }
        )
        if ($matches.Count -ne 1 -or $matches[0].Name -cne $segment) { return $false }
        $cursor = $matches[0].FullName
    }
    return $true
}

function Read-ModelProjectBoundedUtf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateRange(0, [long]::MaxValue)][long]$MaxBytes
    )

    $pathFull = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-ModelProjectPathWithinRoot -Root $Root -Path $pathFull)) {
        throw 'Path is outside Root.'
    }
    if (-not (Test-Path -LiteralPath $pathFull -PathType Leaf)) { throw 'File not found.' }
    if ($null -ne (Get-ModelProjectReparsePointInFullChain -Root $Root -Path $pathFull)) {
        throw 'Read crosses a reparse point.'
    }
    $item = Get-Item -LiteralPath $pathFull -Force -ErrorAction Stop
    if ($item.Length -gt $MaxBytes) { throw 'File exceeds byte limit.' }
    $stream = $null; $memory = $null
    try {
        $stream = [System.IO.FileStream]::new($pathFull, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        if ($stream.Length -gt $MaxBytes) { throw 'File exceeds byte limit after open.' }
        $memory = [System.IO.MemoryStream]::new()
        $buffer = New-Object byte[] 65536
        [long]$total = 0
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $total += $read
            if ($total -gt $MaxBytes) { throw 'File exceeds byte limit during read.' }
            $memory.Write($buffer, 0, $read)
        }
        $bytes = $memory.ToArray()
    }
    finally {
        if ($null -ne $memory) { $memory.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
    $utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
    $text = $utf8Strict.GetString($bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return $text
}

function ConvertTo-ModelProjectMarkdownAnchor {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Heading)

    $value = $Heading.Trim().ToLowerInvariant()
    $value = [regex]::Replace($value, '<[^>]+>', '')
    $value = [regex]::Replace($value, '[^\p{L}\p{N}\s_-]', '')
    $value = [regex]::Replace($value, '\s+', '-')
    return $value.Trim('-')
}

function Test-ModelProjectMarkdownAnchorExists {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Anchor
    )

    $text = Read-ModelProjectBoundedUtf8File -Root $Root -Path $Path -MaxBytes 2MB
    $seen = @{}
    foreach ($line in @($text -split "\r?\n")) {
        if ($line -cnotmatch '^ {0,3}#{1,6}[ \t]+(?<heading>.+?)[ \t]*#*[ \t]*$') { continue }
        $base = ConvertTo-ModelProjectMarkdownAnchor -Heading ([string]$Matches['heading'])
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        $count = if ($seen.ContainsKey($base)) { [int]$seen[$base] } else { 0 }
        $candidate = if ($count -eq 0) { $base } else { "$base-$count" }
        $seen[$base] = $count + 1
        if ($candidate -ceq $Anchor) { return $true }
    }
    return $false
}

function Resolve-ModelProjectSafeReference {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Reference,
        [Parameter(Mandatory = $true)][ValidateSet('Repository', 'File')][string]$ReferenceBase,
        [switch]$AllowHttps,
        [switch]$AllowLogical
    )

    $result = [ordered]@{
        Kind = 'invalid'; FullPath = $null; RepositoryPath = $null; Anchor = $null
        Exists = $false; ExactCase = $false; AnchorExists = $false; Error = $null
    }
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]'\/')
    $sourceFull = [System.IO.Path]::GetFullPath($SourcePath)
    if (-not (Test-ModelProjectPathWithinRoot -Root $rootFull -Path $sourceFull)) {
        throw 'SourcePath is outside Root.'
    }
    $value = $Reference.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { $result.Error = 'empty-reference'; return [pscustomobject]$result }

    if ($value -match '^(?i:https://)') {
        if (-not $AllowHttps) { $result.Error = 'https-not-allowed'; return [pscustomobject]$result }
        $finding = Get-ModelProjectHttpsUrlSafetyFinding -Value $value
        if ($null -ne $finding) { $result.Error = $finding; return [pscustomobject]$result }
        $result.Kind = 'https'; $result.Exists = $true; $result.ExactCase = $true; $result.AnchorExists = $true
        return [pscustomobject]$result
    }
    if ($value -match '^logical:[A-Za-z0-9][A-Za-z0-9._:/-]{0,255}$') {
        if (-not $AllowLogical) { $result.Error = 'logical-not-allowed'; return [pscustomobject]$result }
        $result.Kind = 'logical'; $result.Exists = $true; $result.ExactCase = $true; $result.AnchorExists = $true
        return [pscustomobject]$result
    }
    if ($value -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or
        $value -match '^[A-Za-z]:[\\/]' -or
        $value -match '^[\\/]' -or
        $value -match '^\\\\[?.]\\') {
        $result.Error = 'absolute-or-unsafe-uri'; return [pscustomobject]$result
    }

    $parts = $value.Split('#', 2)
    $pathPart = ConvertTo-ModelProjectPercentDecodedText -Value $parts[0]
    $anchor = if ($parts.Count -eq 2) { ConvertTo-ModelProjectPercentDecodedText -Value $parts[1] } else { $null }
    if ([string]::IsNullOrWhiteSpace($pathPart) -or $pathPart.Contains('\')) {
        $result.Error = 'unsafe-relative-path'; return [pscustomobject]$result
    }
    if ($ReferenceBase -ceq 'Repository' -and (
        $pathPart.StartsWith('./') -or
        $pathPart -match '(?:^|/)\.\.(?:/|$)' -or
        $pathPart -match '(?:^|/)\.(?:/|$)'
    )) {
        $result.Error = 'unsafe-repository-relative-path'; return [pscustomobject]$result
    }
    if ($null -ne $anchor -and ($anchor.Length -eq 0 -or $anchor.Contains('#'))) {
        $result.Error = 'invalid-anchor'; return [pscustomobject]$result
    }
    $base = if ($ReferenceBase -ceq 'Repository') { $rootFull } else { Split-Path -Parent $sourceFull }
    try { $full = [System.IO.Path]::GetFullPath((Join-Path $base $pathPart)) }
    catch { $result.Error = 'invalid-path'; return [pscustomobject]$result }
    if (-not (Test-ModelProjectPathWithinRoot -Root $rootFull -Path $full)) {
        $result.Error = 'path-outside-root'; return [pscustomobject]$result
    }
    if ($null -ne (Get-ModelProjectReparsePointInFullChain -Root $rootFull -Path $full)) {
        $result.Error = 'reparse-point'; return [pscustomobject]$result
    }

    $result.Kind = 'internal'
    $result.FullPath = $full
    $result.RepositoryPath = Get-ModelProjectRepositoryRelativePath -Root $rootFull -Path $full
    $result.Anchor = $anchor
    $result.Exists = Test-Path -LiteralPath $full -PathType Leaf
    if ($result.Exists) {
        $result.ExactCase = Test-ModelProjectExactPathCase -Root $rootFull -Path $full
        $result.AnchorExists = if ($null -eq $anchor) { $true } else {
            Test-ModelProjectMarkdownAnchorExists -Root $rootFull -Path $full -Anchor $anchor
        }
    }
    return [pscustomobject]$result
}

Microsoft.PowerShell.Core\Export-ModuleMember -Function @(
    'Test-ModelProjectFrontMatterScalarValue',
    'ConvertFrom-ModelProjectSimpleYamlScalar',
    'Read-ModelProjectSimpleFrontMatterDocument',
    'Test-ModelProjectJsonScalar',
    'ConvertTo-ModelProjectPercentDecodedText',
    'Get-ModelProjectHttpsUrlSafetyFinding',
    'Get-ModelProjectHttpsUrlsFromText',
    'Get-ModelProjectSensitiveTextFindings',
    'Remove-ModelProjectCommonMarkContainerPrefixes',
    'Test-ModelProjectMarkdownEscaped',
    'Get-ModelProjectMarkdownLinkOpenerIndex',
    'Test-ModelProjectInlineMarkdownClosure',
    'Test-ModelProjectPathWithinRoot',
    'Get-ModelProjectReparsePointInFullChain',
    'Get-ModelProjectRepositoryRelativePath',
    'Test-ModelProjectExactPathCase',
    'Read-ModelProjectBoundedUtf8File',
    'ConvertTo-ModelProjectMarkdownAnchor',
    'Test-ModelProjectMarkdownAnchorExists',
    'Resolve-ModelProjectSafeReference'
)
