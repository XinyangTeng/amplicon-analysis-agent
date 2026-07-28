param(
    [string]$Workspace = "",
    [int]$Port = 8000,
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

if (-not $SkipInstall) {
    python -m pip install ".[web]"
}

Write-Host "Amplicon Analysis Agent Web"
Write-Host "Workspace: $env:AMPLICON_WORKSPACE"
Write-Host "Open: http://127.0.0.1:$Port"
python -m amplicon_agent.web
