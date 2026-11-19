# Filesystem contract tests; no CEF, applications, network or Pester required.
$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot 'cef-cache-version.ps1'
$buildRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\build'))
$testRoot = Join-Path $buildRoot ('cef-cache-version-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$passed = 0
$failed = 0
$version26 = '156.0.26+g8ea0c73+chromium-156.0.8078.88'
$version27 = '156.0.27+ga10dae3+chromium-156.0.8078.88'
$version31 = '156.0.31+ge603d97+chromium-156.0.8078.100'

function New-CefFixture {
    param([string]$Name, [string]$Header, [switch]$WithoutDll, [switch]$WithoutHeader)
    $directory = Join-Path $testRoot $Name
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    if (-not $WithoutDll) {
        [IO.Directory]::CreateDirectory((Join-Path $directory 'Release')) | Out-Null
        [IO.File]::WriteAllText((Join-Path $directory 'Release\libcef.dll'), 'fake cached DLL')
    }
    if (-not $WithoutHeader) {
        [IO.Directory]::CreateDirectory((Join-Path $directory 'include')) | Out-Null
        [IO.File]::WriteAllText((Join-Path $directory 'include\cef_version.h'), $Header)
    }
    return $directory
}

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:passed++
        Write-Host "PASS $Name"
    } catch {
        $script:failed++
        Write-Host "FAIL ${Name}: $($_.Exception.Message)"
    }
}

function Assert-Rejected {
    param([string]$Directory, [string]$ExpectedVersion, [string[]]$MessageParts, [string]$AcceptanceMessage)
    $message = $null
    try {
        Assert-CefCacheVersion -CefDirectory $Directory -ExpectedVersion $ExpectedVersion
    } catch {
        $message = $_.Exception.Message
    }
    if ($null -eq $message) { throw $AcceptanceMessage }
    foreach ($part in $MessageParts) {
        if (-not $message.Contains($part)) { throw "Error did not explain '$part': $message" }
    }
}

try {
    Test-Case 'import has no output, filesystem or preference side effects' {
        $preference = $ErrorActionPreference
        $before = @(Get-ChildItem -LiteralPath $testRoot -Force)
        $output = @(. $helper)
        if ($output.Count -ne 0 -or $ErrorActionPreference -ne $preference -or
            @(Get-ChildItem -LiteralPath $testRoot -Force).Count -ne $before.Count) {
            throw 'Import must only define Assert-CefCacheVersion.'
        }
    }
    # Import into script scope after checking the helper in the test's child scope.
    . $helper

    Test-Case 'exact .27 full metadata version is accepted without changes' {
        $header = "#define CEF_VERSION_MAJOR 156`r`n#define CEF_VERSION `"$version27`"`r`n"
        $directory = New-CefFixture -Name 'exact-27' -Header $header
        $output = @(Assert-CefCacheVersion -CefDirectory $directory -ExpectedVersion $version27)
        if ($output.Count -ne 0 -or [IO.File]::ReadAllText((Join-Path $directory 'include\cef_version.h')) -cne $header -or
            [IO.File]::ReadAllText((Join-Path $directory 'Release\libcef.dll')) -cne 'fake cached DLL') {
            throw 'Accepted cache was modified or emitted output.'
        }
    }
    Test-Case 'old .26 cache is rejected for expected .27' {
        $header = "#define CEF_VERSION `"$version26`""
        $directory = New-CefFixture -Name 'stale-26' -Header $header
        Assert-Rejected $directory $version27 @($version26, $version27, 'Clear', 'rerun') 'Old .26 cache was incorrectly accepted for expected .27.'
        if ([IO.File]::ReadAllText((Join-Path $directory 'include\cef_version.h')) -cne $header -or
            [IO.File]::ReadAllText((Join-Path $directory 'Release\libcef.dll')) -cne 'fake cached DLL') {
            throw 'Rejected cache was modified.'
        }
    }
    Test-Case 'same CEF number with different commit metadata is rejected' {
        $other = '156.0.27+g8ea0c73+chromium-156.0.8078.88'
        $directory = New-CefFixture -Name 'wrong-commit' -Header "#define CEF_VERSION `"$other`""
        Assert-Rejected $directory $version27 @($other, $version27) 'Commit metadata was ignored.'
    }
    Test-Case 'same CEF number with different Chromium metadata is rejected' {
        $other = '156.0.27+ga10dae3+chromium-156.0.8078.96'
        $directory = New-CefFixture -Name 'wrong-chromium' -Header "#define CEF_VERSION `"$other`""
        Assert-Rejected $directory $version27 @($other, $version27) 'Chromium metadata was ignored.'
    }
    Test-Case 'DLL with missing version header is rejected' {
        $directory = New-CefFixture -Name 'missing-header' -WithoutHeader
        Assert-Rejected $directory $version27 @('cef_version.h', 'missing', 'Clear', 'rerun') 'Cache without a version header was accepted.'
    }
    Test-Case 'unquoted version definition is rejected' {
        $directory = New-CefFixture -Name 'unquoted-header' -Header "#define CEF_VERSION $version27"
        Assert-Rejected $directory $version27 @('malformed', 'cef_version.h', 'Clear', 'rerun') 'Malformed version definition was accepted.'
    }
    Test-Case 'CEF_VERSION_MAJOR is not mistaken for the full version' {
        $directory = New-CefFixture -Name 'no-full-version' -Header '#define CEF_VERSION_MAJOR 156'
        Assert-Rejected $directory $version27 @('malformed', 'CEF_VERSION') 'Missing full version definition was accepted.'
    }
    Test-Case 'duplicate version definitions are rejected' {
        $definition = "#define CEF_VERSION `"$version27`""
        $directory = New-CefFixture -Name 'duplicate-version' -Header "$definition`n$definition"
        Assert-Rejected $directory $version27 @('malformed', 'CEF_VERSION') 'Ambiguous version definitions were accepted.'
    }
    Test-Case 'missing DLL permits dependency download without requiring a header' {
        $directory = New-CefFixture -Name 'missing-dll' -WithoutDll -WithoutHeader
        $output = @(Assert-CefCacheVersion -CefDirectory $directory -ExpectedVersion $version27)
        if ($output.Count -ne 0 -or @(Get-ChildItem -LiteralPath $directory -Force).Count -ne 0) {
            throw 'An absent cache was changed or emitted output.'
        }
    }
    Test-Case 'explicit .31 override accepts its own complete version' {
        $directory = New-CefFixture -Name 'override-31' -Header "#define CEF_VERSION `"$version31`""
        Assert-CefCacheVersion -CefDirectory $directory -ExpectedVersion $version31
    }
    Test-Case 'explicit .31 override rejects a cached .27' {
        $directory = New-CefFixture -Name 'override-stale-27' -Header "#define CEF_VERSION `"$version27`""
        Assert-Rejected $directory $version31 @($version27, $version31) 'Explicit override was ignored.'
    }
} finally {
    # Only remove this invocation's generated fixtures, after checking the resolved path.
    $resolvedRoot = (Resolve-Path -LiteralPath $testRoot).Path
    $expectedRoot = [IO.Path]::GetFullPath($testRoot)
    $buildPrefix = $buildRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedRoot.Equals($expectedRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not $resolvedRoot.StartsWith($buildPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolvedRoot) -notmatch '^cef-cache-version-tests-[0-9a-f]{32}$') {
        throw "Refusing to remove a directory outside the intended fixture root: $resolvedRoot"
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
}

Write-Host "$passed passed, $failed failed"
if ($failed -ne 0) { throw 'CEF cache version tests failed.' }
