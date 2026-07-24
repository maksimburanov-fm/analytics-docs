[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$jiraBaseUrl = "https://project.ffin.kz"
$jiraProjectKey = "FMAP"

function Write-Ok {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Stop-Check {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

function Invoke-JiraGet {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        Invoke-RestMethod `
            -Uri ($jiraBaseUrl + $Path) `
            -Headers $script:jiraHeaders `
            -Method Get `
            -TimeoutSec 30
    } catch {
        $status = "no HTTP status"
        if ($null -ne $_.Exception.Response) {
            try {
                $status = [int]$_.Exception.Response.StatusCode
            } catch {
                $status = "unknown HTTP status"
            }
        }
        Stop-Check "GET $Path failed ($status). Check VPN, Jira availability, and JIRA_PAT."
    }
}

$jiraPat = [Environment]::GetEnvironmentVariable("JIRA_PAT", "User")
if ([string]::IsNullOrWhiteSpace($jiraPat)) {
    Stop-Check "JIRA_PAT is not set at Windows user level. See docs/08_jira_api.md."
}
Write-Ok "JIRA_PAT is present at Windows user level (value not displayed)."

$script:jiraHeaders = @{
    Authorization = "Bearer $jiraPat"
    Accept = "application/json"
}

$serverInfo = Invoke-JiraGet "/rest/api/2/serverInfo"
Write-Ok "Jira is reachable (version $($serverInfo.version))."

$null = Invoke-JiraGet "/rest/api/2/myself"
Write-Ok "Jira PAT authentication succeeded."

$null = Invoke-JiraGet "/rest/api/2/project/$jiraProjectKey"
Write-Ok "Project $jiraProjectKey is readable."

$permissionNames = @(
    "BROWSE_PROJECTS",
    "CREATE_ISSUES",
    "EDIT_ISSUES",
    "DELETE_ISSUES"
)
$permissionQuery = $permissionNames -join ","
$permissionResult = Invoke-JiraGet (
    "/rest/api/2/mypermissions?projectKey=$jiraProjectKey&permissions=$permissionQuery"
)

foreach ($permissionName in $permissionNames) {
    $permission = $permissionResult.permissions.$permissionName
    if ($null -eq $permission) {
        Stop-Check "Jira did not return permission $permissionName."
    }
    if (-not [bool]$permission.havePermission) {
        Stop-Check "The current Jira account does not have $permissionName in $jiraProjectKey."
    }
    Write-Ok "$permissionName is granted in $jiraProjectKey."
}

Remove-Variable jiraPat -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "Jira preflight passed. New chats can use docs/08_jira_api.md."
