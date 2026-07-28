param(
    [string]$Workspace = "",
    [int]$Port = 8001,
    [string]$BootstrapInvite = "",
    [switch]$SingleProcess,
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

if (-not $Workspace) {
    $Workspace = Join-Path $projectRoot "workspace"
}
New-Item -ItemType Directory -Path $Workspace -Force | Out-Null

$env:AMPLICON_WORKSPACE = (Resolve-Path -LiteralPath $Workspace).Path
$env:WEB_PORT = [string]$Port
$env:PYTHONPATH = Join-Path $projectRoot "src"
if ($BootstrapInvite) {
    $env:AMPLICON_BOOTSTRAP_INVITE = $BootstrapInvite
}
if ($SingleProcess) {
    $env:CELERY_TASK_ALWAYS_EAGER = "true"
}

if (-not $SkipInstall) {
    python -m pip install -e ".[web]"
}

Write-Host "BioAgent Web"
Write-Host "Workspace: $env:AMPLICON_WORKSPACE"
Write-Host "Open: http://127.0.0.1:$Port"
if ($SingleProcess) {
    Write-Host "Local single-process mode: analysis runs without Redis and is only for development."
} else {
    Write-Host "Redis and a Celery worker must already be running. Docker Compose is recommended."
}
python -m amplicon_agent.web
