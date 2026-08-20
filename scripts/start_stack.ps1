param(
    [switch]$Detach,
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

if (-not (Test-Path -LiteralPath ".env")) {
    throw "Missing .env. Copy .env.example to .env and configure the bootstrap invite code first."
}

& docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Docker Desktop is not running. Wait until Docker reports Engine running, then retry."
}

$standaloneCompose = Get-Command docker-compose -ErrorAction SilentlyContinue

if ($standaloneCompose) {
    $usePlugin = $false
} else {
    $usePlugin = $true
    $oldErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & docker compose version *> $null
    $composeAvailable = $LASTEXITCODE -eq 0
    $ErrorActionPreference = $oldErrorActionPreference

    if (-not $composeAvailable) {
        throw "Docker Compose was not found. Install the Compose plugin or docker-compose.exe."
    }
}

$arguments = @("up")
if (-not $NoBuild) {
    $arguments += "--build"
}
if ($Detach) {
    $arguments += "-d"
}

if ($usePlugin) {
    Write-Host "Using: docker compose $($arguments -join ' ')"
    & docker compose @arguments
} else {
    Write-Host "Using: docker-compose $($arguments -join ' ')"
    & docker-compose @arguments
}

if ($LASTEXITCODE -ne 0) {
    throw "Container startup failed. Keep the final error output shown above."
}
