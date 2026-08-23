Set-StrictMode -Version 2.0

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:IsWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows
)
$script:IsMacOS = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::OSX
)

function Get-ModelProjectNormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $pathRoot = [System.IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $pathRoot.Length) {
        $full = $full.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
}

function Resolve-ModelProjectFileSystemLinkPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = Get-ModelProjectNormalizedFullPath -Path $Path
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    for ($hop = 0; $hop -lt 32; $hop++) {
        if (-not $visited.Add($resolved)) { throw 'Циклическая symlink-цепочка доверенного приложения.' }
        $linkPath = Get-ModelProjectLinkInFullChain -Path $resolved
        if ($null -eq $linkPath) { return $resolved }
        $linkItem = Get-Item -LiteralPath $linkPath -Force
        try { $targetItem = $linkItem.ResolveLinkTarget($true) }
        catch { throw 'Не удалось безопасно разрешить symlink доверенного приложения.' }
        if ($null -eq $targetItem -or [string]::IsNullOrWhiteSpace([string]$targetItem.FullName)) {
            throw 'Symlink доверенного приложения не имеет разрешимого target.'
        }
        $suffix = $resolved.Substring($linkPath.Length).TrimStart(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar
        )
        $resolved = Get-ModelProjectNormalizedFullPath -Path ([string]$targetItem.FullName)
        if (-not [string]::IsNullOrWhiteSpace($suffix)) { $resolved = Join-Path $resolved $suffix }
        $resolved = Get-ModelProjectNormalizedFullPath -Path $resolved
    }
    throw 'Symlink-цепочка доверенного приложения превышает безопасный лимит.'
}

function Test-ModelProjectIsWindows {
    return $script:IsWindows
}

function Test-ModelProjectIsMacOS {
    return $script:IsMacOS
}

function Get-ModelProjectNullDevice {
    if ($script:IsWindows) { return 'NUL' }
    return '/dev/null'
}

function Get-ModelProjectCaseVariantPath {
    param([Parameter(Mandatory = $true)][string]$ExistingPath)

    $full = Get-ModelProjectNormalizedFullPath -Path $ExistingPath
    $pathRoot = [System.IO.Path]::GetPathRoot($full)
    $relative = $full.Substring($pathRoot.Length)
    $segments = @($relative -split '[\\/]' | Where-Object { $_.Length -gt 0 })
    for ($segmentIndex = $segments.Count - 1; $segmentIndex -ge 0; $segmentIndex--) {
        $characters = $segments[$segmentIndex].ToCharArray()
        for ($characterIndex = 0; $characterIndex -lt $characters.Length; $characterIndex++) {
            $character = [string]$characters[$characterIndex]
            $upper = $character.ToUpperInvariant()
            $lower = $character.ToLowerInvariant()
            if ($upper -ceq $lower) { continue }
            $replacement = if ($character -ceq $upper) { $lower } else { $upper }
            $characters[$characterIndex] = [char]$replacement
            $variantSegments = @($segments)
            $variantSegments[$segmentIndex] = -join $characters
            $variant = $pathRoot
            foreach ($segment in $variantSegments) { $variant = Join-Path $variant $segment }
            if ($variant -cne $full) { return $variant }
        }
    }
    return $null
}

function Get-ModelProjectPathComparison {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($script:IsWindows) { return [System.StringComparison]::OrdinalIgnoreCase }
    $existing = Get-ModelProjectNormalizedFullPath -Path $Path
    while (-not (Test-Path -LiteralPath $existing)) {
        $parent = [System.IO.Path]::GetDirectoryName($existing)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $existing) { break }
        $existing = $parent
    }
    if (-not (Test-Path -LiteralPath $existing)) { return [System.StringComparison]::Ordinal }
    $variant = Get-ModelProjectCaseVariantPath -ExistingPath $existing
    if ($null -ne $variant -and (Test-Path -LiteralPath $variant)) {
        return [System.StringComparison]::OrdinalIgnoreCase
    }
    return [System.StringComparison]::Ordinal
}

function Test-ModelProjectPathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowEqual
    )

    $rootFull = Get-ModelProjectNormalizedFullPath -Path $Root
    $pathFull = Get-ModelProjectNormalizedFullPath -Path $Path
    $comparison = Get-ModelProjectPathComparison -Path $rootFull
    if ($AllowEqual -and $pathFull.Equals($rootFull, $comparison)) { return $true }
    $prefix = if ($rootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $rootFull
    }
    else {
        $rootFull + [System.IO.Path]::DirectorySeparatorChar
    }
    return $pathFull.StartsWith($prefix, $comparison)
}

function Get-ModelProjectLinkInFullChain {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = Get-ModelProjectNormalizedFullPath -Path $Path
    $pathRoot = [System.IO.Path]::GetPathRoot($full)
    $current = $pathRoot
    $relative = $full.Substring($pathRoot.Length)
    foreach ($segment in @($relative -split '[\\/]' | Where-Object { $_.Length -gt 0 })) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { break }
        $item = Get-Item -LiteralPath $current -Force
        $isReparse = ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        $isLink = $item.PSObject.Properties.Name -contains 'LinkType' -and
            [string]$item.LinkType -cin @('SymbolicLink', 'Junction')
        if ($isReparse -or $isLink) { return $current }
    }
    return $null
}

function Assert-ModelProjectNoLinkInFullChain {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($null -ne (Get-ModelProjectLinkInFullChain -Path $Path)) {
        throw 'Путь не может проходить через symlink или reparse point.'
    }
}

function Get-ModelProjectTrustedApplication {
    param(
        [Parameter(Mandatory = $true)][string[]]$Names,
        [Parameter(Mandatory = $true)][string[]]$AllowedLeaves,
        [string[]]$ControlledRoots = @()
    )

    $command = $null
    foreach ($name in $Names) {
        $command = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $command) { break }
    }
    if ($null -eq $command -or [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        throw 'Доверенное приложение не найдено.'
    }
    $commandPath = Get-ModelProjectNormalizedFullPath -Path ([string]$command.Source)
    $commandLeaf = [System.IO.Path]::GetFileName($commandPath)
    if ($commandLeaf -cnotin $AllowedLeaves -or -not (Test-Path -LiteralPath $commandPath -PathType Leaf)) {
        throw 'Доверенное приложение не прошло проверку имени и типа.'
    }
    $path = Resolve-ModelProjectFileSystemLinkPath -Path $commandPath
    $resolvedLeaf = [System.IO.Path]::GetFileName($path)
    if ($resolvedLeaf -cnotin $AllowedLeaves -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Target доверенного приложения не прошел проверку имени и типа.'
    }
    foreach ($controlledRoot in $ControlledRoots) {
        if ((Test-ModelProjectPathWithinRoot -Root $controlledRoot -Path $commandPath -AllowEqual) -or
            (Test-ModelProjectPathWithinRoot -Root $controlledRoot -Path $path -AllowEqual)) {
            throw 'Доверенное приложение не может находиться внутри управляемого корня.'
        }
    }
    return $path
}

function Get-ModelProjectGitExecutable {
    param([string[]]$ControlledRoots = @())

    return Get-ModelProjectTrustedApplication `
        -Names @('git', 'git.exe') `
        -AllowedLeaves @('git', 'git.exe') `
        -ControlledRoots $ControlledRoots
}

function Get-ModelProjectPowerShellHost {
    param([string[]]$ControlledRoots = @())

    try {
        $hostPath = Get-ModelProjectNormalizedFullPath -Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
    }
    catch { throw 'Не удалось определить текущий PowerShell 7 host.' }
    if ([System.IO.Path]::GetFileName($hostPath) -cnotin @('pwsh', 'pwsh.exe') -or
        -not (Test-Path -LiteralPath $hostPath -PathType Leaf)) {
        throw 'Для шаблона требуется PowerShell 7 host pwsh.'
    }
    $path = Resolve-ModelProjectFileSystemLinkPath -Path $hostPath
    if ([System.IO.Path]::GetFileName($path) -cnotin @('pwsh', 'pwsh.exe') -or
        -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'Target PowerShell 7 host не прошел проверку имени и типа.'
    }
    foreach ($controlledRoot in $ControlledRoots) {
        if ((Test-ModelProjectPathWithinRoot -Root $controlledRoot -Path $hostPath -AllowEqual) -or
            (Test-ModelProjectPathWithinRoot -Root $controlledRoot -Path $path -AllowEqual)) {
            throw 'PowerShell host не может находиться внутри управляемого корня.'
        }
    }
    return $path
}

function Set-ModelProjectSanitizedGitEnvironment {
    param([Parameter(Mandatory = $true)]$Environment)

    foreach ($name in @($Environment.Keys)) {
        if (([string]$name).StartsWith('GIT_', [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]$name -cin @('GCM_INTERACTIVE')) {
            [void]$Environment.Remove([string]$name)
        }
    }
    $nullDevice = Get-ModelProjectNullDevice
    $Environment['GIT_CONFIG_NOSYSTEM'] = '1'
    $Environment['GIT_CONFIG_GLOBAL'] = $nullDevice
    $Environment['GIT_CONFIG_SYSTEM'] = $nullDevice
    $Environment['GIT_TERMINAL_PROMPT'] = '0'
    $Environment['GCM_INTERACTIVE'] = 'Never'
}

function Invoke-ModelProjectProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
        [string]$WorkingDirectory = '',
        [switch]$GitEnvironment,
        [int]$MaxLines = 100000,
        [long]$MaxCharacters = 8MB
    )

    foreach ($argument in $Arguments) {
        $value = [string]$argument
        if ($value -match '[\r\n\x00]' -or $value.Length -gt 32768) {
            throw 'Аргумент дочернего процесса содержит запрещенный символ или превышает лимит.'
        }
    }
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = $script:Utf8NoBom
    $startInfo.StandardErrorEncoding = $script:Utf8NoBom
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startInfo.WorkingDirectory = Get-ModelProjectNormalizedFullPath -Path $WorkingDirectory
    }
    foreach ($argument in $Arguments) { [void]$startInfo.ArgumentList.Add([string]$argument) }
    foreach ($name in @($startInfo.Environment.Keys)) {
        if (([string]$name).StartsWith('GIT_', [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$startInfo.Environment.Remove([string]$name)
        }
    }
    if ($GitEnvironment) { Set-ModelProjectSanitizedGitEnvironment -Environment $startInfo.Environment }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Не удалось запустить доверенный дочерний процесс.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $stdoutLines = @($stdout -split '\r?\n' | Where-Object { $_.Length -gt 0 })
        $stderrLines = @($stderr -split '\r?\n' | Where-Object { $_.Length -gt 0 })
        $allLines = @($stdoutLines + $stderrLines)
        $characters = [long](($stdout.Length) + ($stderr.Length))
        $limitExceeded = ($MaxLines -gt 0 -and $allLines.Count -gt $MaxLines) -or
            ($MaxCharacters -gt 0 -and $characters -gt $MaxCharacters)
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = $stdout
            Stderr = $stderr
            StdoutLines = $stdoutLines
            StderrLines = $stderrLines
            Output = $allLines
            LimitExceeded = $limitExceeded
        }
    }
    finally { $process.Dispose() }
}

function Assert-ModelProjectInputText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$Field,
        [int]$MaxLength = 240,
        [string]$Pattern = '',
        [switch]$AllowEmpty
    )

    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value)) { throw "$Field не заполнено." }
    if ($Value.Length -gt $MaxLength -or
        $Value -cne $Value.Trim() -or
        $Value -match '[\p{Cc}\p{Cf}]' -or
        $Value -match '\x1B\[') {
        throw "$Field содержит control characters, внешние пробелы или превышает лимит."
    }
    if (-not [string]::IsNullOrWhiteSpace($Pattern) -and $Value -cnotmatch $Pattern) {
        throw "$Field не соответствует безопасному формату."
    }
}

function Enter-ModelProjectFileLock {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9._-]{0,127}$')][string]$ResourceKey,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 60
    )

    $rootPath = Get-ModelProjectNormalizedFullPath -Path $RepositoryRoot
    $comparison = Get-ModelProjectPathComparison -Path $rootPath
    $identityRoot = if ($comparison -eq [System.StringComparison]::OrdinalIgnoreCase) {
        $rootPath.ToLowerInvariant()
    }
    else { $rootPath }
    $identity = $identityRoot + "`n" + $ResourceKey
    $digest = [System.Security.Cryptography.SHA256]::HashData($script:Utf8NoBom.GetBytes($identity))
    $hash = [Convert]::ToHexString($digest).ToLowerInvariant()
    $systemTemp = Resolve-ModelProjectFileSystemLinkPath -Path ([System.IO.Path]::GetTempPath())
    $lockDirectory = Get-ModelProjectNormalizedFullPath -Path (Join-Path $systemTemp 'model-project-locks')
    if (-not (Test-Path -LiteralPath $lockDirectory -PathType Container)) {
        [void][System.IO.Directory]::CreateDirectory($lockDirectory)
    }
    Assert-ModelProjectNoLinkInFullChain -Path $lockDirectory
    $lockPath = Join-Path $lockDirectory ("$hash.lock")
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $lockPath) {
            $lockItem = Get-Item -LiteralPath $lockPath -Force
            if (($lockItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                ($lockItem.PSObject.Properties.Name -contains 'LinkType' -and
                    [string]$lockItem.LinkType -cin @('SymbolicLink', 'Junction'))) {
                throw 'Lock path не может быть symlink или reparse point.'
            }
        }
        try {
            $stream = [System.IO.FileStream]::new(
                $lockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
            return [pscustomobject]@{ Stream = $stream; Path = $lockPath; ResourceKey = $ResourceKey }
        }
        catch [System.IO.IOException] {
            if ([DateTimeOffset]::UtcNow -ge $deadline) { throw 'blocked: lock-timeout' }
            Start-Sleep -Milliseconds 50
        }
    } while ($true)
}

function Exit-ModelProjectFileLock {
    param([Parameter(Mandatory = $true)]$Lock)

    if ($null -ne $Lock.Stream) { $Lock.Stream.Dispose() }
}

Microsoft.PowerShell.Core\Export-ModuleMember -Function @(
    'Get-ModelProjectNormalizedFullPath',
    'Resolve-ModelProjectFileSystemLinkPath',
    'Test-ModelProjectIsWindows',
    'Test-ModelProjectIsMacOS',
    'Get-ModelProjectNullDevice',
    'Get-ModelProjectPathComparison',
    'Test-ModelProjectPathWithinRoot',
    'Get-ModelProjectLinkInFullChain',
    'Assert-ModelProjectNoLinkInFullChain',
    'Get-ModelProjectTrustedApplication',
    'Get-ModelProjectGitExecutable',
    'Get-ModelProjectPowerShellHost',
    'Set-ModelProjectSanitizedGitEnvironment',
    'Invoke-ModelProjectProcess',
    'Assert-ModelProjectInputText',
    'Enter-ModelProjectFileLock',
    'Exit-ModelProjectFileLock'
)
