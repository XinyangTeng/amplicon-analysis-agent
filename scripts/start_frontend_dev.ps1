param(
    [switch]$Build
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

if (-not (Test-Path -LiteralPath ".env")) {
    throw "Missing .env. Copy .env.example to .env first."
}

& docker info *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Docker Desktop is not running."
}

$composeFiles = @(
    "-f", "docker-compose.yml",
    "-f", "docker-compose.dev.yml"
)
$upArguments = @("up", "-d")
if ($Build) {
    $upArguments += "--build"
}

$standaloneCompose = Get-Command docker-compose -ErrorAction SilentlyContinue
if ($standaloneCompose) {
    & docker-compose @composeFiles @upArguments
}
else {
    & docker compose @composeFiles @upArguments
}

if ($LASTEXITCODE -ne 0) {
    throw "Frontend development stack failed to start."
}

Write-Host "Frontend development mode is running."
Write-Host "Edit: src/amplicon_agent/web_static/"
Write-Host "Open: http://127.0.0.1:8001"
Write-Host "After saving HTML/CSS/JS, refresh the browser without rebuilding."
