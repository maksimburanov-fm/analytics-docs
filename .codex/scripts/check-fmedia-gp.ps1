[CmdletBinding()]
param(
    [switch]$PullImage
)

$ErrorActionPreference = "Stop"
$imageReference = "crystaldba/postgres-mcp@sha256:dbbd346860d29f1543e991f30f3284bf4ab5f096d049ecc3426528f20b1b6e6b"

function Write-Ok {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Stop-Check {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

$databaseUri = [Environment]::GetEnvironmentVariable("DATABASE_URI", "User")
if ([string]::IsNullOrWhiteSpace($databaseUri)) {
    Stop-Check "DATABASE_URI is not set at Windows user level. See docs/07_mcp_connections.md."
}
if ($databaseUri -notmatch "^postgres(?:ql)?://") {
    Stop-Check "DATABASE_URI has an unsupported format. It must start with postgres:// or postgresql://."
}
Write-Ok "DATABASE_URI is present at Windows user level (value not displayed)."

$dockerCommand = Get-Command "docker.exe" -ErrorAction SilentlyContinue
if ($null -eq $dockerCommand) {
    $defaultDockerPath = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
    if (Test-Path -LiteralPath $defaultDockerPath) {
        $dockerPath = $defaultDockerPath
    } else {
        Stop-Check "Docker CLI was not found."
    }
} else {
    $dockerPath = $dockerCommand.Source
}
Write-Ok "Docker CLI found: $dockerPath"

$dockerVersion = & $dockerPath info --format "{{.ServerVersion}}" 2>&1
if ($LASTEXITCODE -ne 0) {
    Stop-Check "Docker Desktop is installed but its engine is not ready. Start Docker Desktop and retry."
}
Write-Ok "Docker engine is ready (version $dockerVersion)."

$imageInfo = & $dockerPath image inspect $imageReference 2>&1
if ($LASTEXITCODE -ne 0) {
    if (-not $PullImage) {
        Stop-Check "Pinned postgres-mcp image is missing. Retry with -PullImage."
    }

    Write-Host "[INFO] Pulling the pinned postgres-mcp image..."
    & $dockerPath pull $imageReference
    if ($LASTEXITCODE -ne 0) {
        Stop-Check "Docker could not pull the postgres-mcp image."
    }
}
Write-Ok "Pinned postgres-mcp image is available."

Write-Host ""
Write-Host "Preflight passed. Restart Codex after config changes, then ask fmedia_gp to run:"
Write-Host "SELECT 1 AS test_connection;"
