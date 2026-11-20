# Dot-source this file before using an existing CEF binary distribution.
function Assert-CefCacheVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$CefDirectory,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ExpectedVersion
    )

    $dll = Join-Path $CefDirectory 'Release\libcef.dll'
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) {
        # fetch-deps will download a distribution when there is no cached DLL.
        return
    }

    $header = Join-Path $CefDirectory 'include\cef_version.h'
    $remedy = "Clear the cached CEF directory '$CefDirectory' and rerun Windows/scripts/fetch-deps.ps1 to fetch expected CEF '$ExpectedVersion'."
    if (-not (Test-Path -LiteralPath $header -PathType Leaf)) {
        throw "Cached CEF version header '$header' is missing. $remedy"
    }
    try {
        $content = [IO.File]::ReadAllText($header)
    } catch {
        throw "Cannot read cached CEF version header '$header': $($_.Exception.Message) $remedy"
    }

    # Compare the entire string, including CEF commit and Chromium metadata.
    # A numeric Version cast or the CEF_VERSION_MAJOR macro loses that identity.
    $definitions = [regex]::Matches($content, '(?m)^[ \t]*#[ \t]*define[ \t]+CEF_VERSION(?=[ \t\r\n]|$)[^\r\n]*')
    if ($definitions.Count -ne 1) {
        throw "Cached CEF version header '$header' is malformed: expected one quoted CEF_VERSION definition. $remedy"
    }
    $version = [regex]::Match($definitions[0].Value, '^[ \t]*#[ \t]*define[ \t]+CEF_VERSION[ \t]+"([^"\r\n]+)"[ \t]*(?://[^\r\n]*|/\*[^\r\n]*\*/[ \t]*)?$')
    if (-not $version.Success) {
        throw "Cached CEF version header '$header' is malformed: expected one quoted CEF_VERSION definition. $remedy"
    }
    $cachedVersion = $version.Groups[1].Value
    if ($cachedVersion -cne $ExpectedVersion) {
        throw "Cached CEF version '$cachedVersion' does not match expected '$ExpectedVersion'. $remedy"
    }
}
