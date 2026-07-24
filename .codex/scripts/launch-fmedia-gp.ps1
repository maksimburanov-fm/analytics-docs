$ErrorActionPreference = "Stop"

$imageReference = "crystaldba/postgres-mcp@sha256:dbbd346860d29f1543e991f30f3284bf4ab5f096d049ecc3426528f20b1b6e6b"

function Stop-McpLaunch {
    param([Parameter(Mandatory = $true)][string]$Message)

    [Console]::Error.WriteLine("[fmedia_gp] $Message")
    exit 1
}

$databaseUri = [Environment]::GetEnvironmentVariable("DATABASE_URI", "User")
if ([string]::IsNullOrWhiteSpace($databaseUri)) {
    $databaseUri = [Environment]::GetEnvironmentVariable("DATABASE_URI", "Process")
}

if ([string]::IsNullOrWhiteSpace($databaseUri)) {
    Stop-McpLaunch "DATABASE_URI is missing. Set it as a Windows user environment variable; never put it in the repository."
}

if ($databaseUri -notmatch "^postgres(?:ql)?://") {
    Stop-McpLaunch "DATABASE_URI must start with postgres:// or postgresql://."
}

$dockerCommand = Get-Command "docker.exe" -ErrorAction SilentlyContinue
if ($null -eq $dockerCommand) {
    $defaultDockerPath = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
    if (Test-Path -LiteralPath $defaultDockerPath) {
        $dockerPath = $defaultDockerPath
    } else {
        Stop-McpLaunch "Docker CLI was not found. Install or start Docker Desktop."
    }
} else {
    $dockerPath = $dockerCommand.Source
}

$dockerInfo = & $dockerPath info --format "{{.ServerVersion}}" 2>&1
if ($LASTEXITCODE -ne 0) {
    Stop-McpLaunch "Docker Desktop is not ready. Start it and wait until the engine is running."
}

$imageInfo = & $dockerPath image inspect $imageReference 2>&1
if ($LASTEXITCODE -ne 0) {
    Stop-McpLaunch "The pinned postgres-mcp image is missing. Run .\.codex\scripts\check-fmedia-gp.cmd -PullImage from the project root."
}

$env:DATABASE_URI = $databaseUri

& $dockerPath run `
    --interactive `
    --rm `
    --pull=never `
    --env DATABASE_URI `
    $imageReference `
    --access-mode=restricted

exit $LASTEXITCODE
