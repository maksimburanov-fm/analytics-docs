[CmdletBinding()]
param(
    [ValidateSet("GET", "POST", "PUT", "DELETE")]
    [string]$Method = "GET",

    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$Body,

    [string]$BodyFile,

    [string]$BodyBase64,

    [switch]$AllowWrite
)

$ErrorActionPreference = "Stop"
$jiraBaseUrl = "https://project.ffin.kz"

if ($Path -notmatch "^/rest/api/" -or $Path -match "://|[\r\n]") {
    throw "Path must start with /rest/api/ and must not contain a host or line break."
}

if ($Method -ne "GET" -and -not $AllowWrite) {
    throw "$Method is blocked. Use -AllowWrite only after the user explicitly requests the Jira change."
}

$bodySourceCount = @(
    -not [string]::IsNullOrWhiteSpace($Body),
    -not [string]::IsNullOrWhiteSpace($BodyFile),
    -not [string]::IsNullOrWhiteSpace($BodyBase64)
).Where({ $_ }).Count
if ($bodySourceCount -gt 1) {
    throw "Use only one of -Body, -BodyFile, or -BodyBase64."
}

if (-not [string]::IsNullOrWhiteSpace($BodyFile)) {
    $resolvedBodyFile = Resolve-Path -LiteralPath $BodyFile -ErrorAction Stop
    $Body = Get-Content -LiteralPath $resolvedBodyFile -Raw
}

if (-not [string]::IsNullOrWhiteSpace($BodyBase64)) {
    try {
        $Body = [System.Text.Encoding]::UTF8.GetString(
            [System.Convert]::FromBase64String($BodyBase64)
        )
    } catch {
        throw "BodyBase64 is not valid Base64-encoded UTF-8."
    }
}

if ($Method -eq "GET" -and -not [string]::IsNullOrWhiteSpace($Body)) {
    throw "GET requests must not include a body."
}

$jiraPat = [Environment]::GetEnvironmentVariable("JIRA_PAT", "User")
if ([string]::IsNullOrWhiteSpace($jiraPat)) {
    throw "JIRA_PAT is not set at Windows user level. See docs/08_jira_api.md."
}

$headers = @{
    Authorization = "Bearer $jiraPat"
    Accept = "application/json"
}

$requestParameters = @{
    Uri = $jiraBaseUrl + $Path
    Headers = $headers
    Method = $Method
    TimeoutSec = 60
    UseBasicParsing = $true
    MaximumRedirection = 0
}

if (-not [string]::IsNullOrWhiteSpace($Body)) {
    $requestParameters.ContentType = "application/json; charset=utf-8"
    $requestParameters.Body = [System.Text.Encoding]::UTF8.GetBytes($Body)
}

try {
    $response = Invoke-WebRequest @requestParameters
} catch {
    $status = "no HTTP status"
    if ($null -ne $_.Exception.Response) {
        try {
            $status = [int]$_.Exception.Response.StatusCode
        } catch {
            $status = "unknown HTTP status"
        }
    }
    throw "Jira request failed: $Method $Path ($status)."
} finally {
    Remove-Variable jiraPat -ErrorAction SilentlyContinue
}

if ([string]::IsNullOrWhiteSpace([string]$response.Content)) {
    Write-Output ('{"status":' + [int]$response.StatusCode + "}")
} else {
    Write-Output $response.Content
}
