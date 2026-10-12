<#
.SYNOPSIS
    Bootstraps the Dragonite Docker stack (MariaDB + Dragonite + Admin) on Windows with Docker Desktop.

.DESCRIPTION
    - Checks that Docker Desktop is installed and running
    - Creates .env from .env.example with randomly generated passwords/secrets (first run only)
    - Creates dragonite/config.toml from config.toml.example wired to those DB credentials (first run only)
    - Pulls the images and starts the stack

    Safe to re-run: existing .env / config.toml are never overwritten.

.PARAMETER Update
    Pull the latest images and recreate the containers (what the README calls "Update").

.PARAMETER NoStart
    Only generate .env / config.toml, don't pull or start anything.

.EXAMPLE
    PS D:\PogoMapper\Dragonite-Public\docker> .\setup.ps1
    PS D:\PogoMapper\Dragonite-Public\docker> .\setup.ps1 -Update
#>
[CmdletBinding()]
param(
    [switch]$Update,
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

function New-Secret {
    param([int]$Bytes = 24)
    $buf = New-Object byte[] $Bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
    # hex keeps it safe for .env, TOML and MariaDB without quoting headaches
    return ($buf | ForEach-Object { $_.ToString('x2') }) -join ''
}

function Read-DotEnv {
    param([string]$Path)
    $map = @{}
    foreach ($line in Get-Content -Path $Path) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $map[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $map
}

# --- 1. Docker Desktop -------------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker is not installed. Install Docker Desktop from https://www.docker.com/products/docker-desktop/ and re-run this script."
}
try {
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "docker info failed" }
} catch {
    Write-Error "Docker Desktop is installed but not running. Start it from the Start menu, wait for the whale icon to settle, then re-run this script."
}

# --- 2. .env -----------------------------------------------------------------
if (-not (Test-Path '.env')) {
    Write-Host "Creating .env with generated secrets ..." -ForegroundColor Cyan
    $env_text = Get-Content -Raw '.env.example'
    $env_text = $env_text -replace '(?m)^DB_ROOT_PASSWORD=.*$',  ("DB_ROOT_PASSWORD=" + (New-Secret))
    $env_text = $env_text -replace '(?m)^DB_PASSWORD=.*$',       ("DB_PASSWORD=" + (New-Secret))
    $env_text = $env_text -replace '(?m)^ADMIN_PASSWORD=.*$',    ("ADMIN_PASSWORD=" + (New-Secret -Bytes 9))
    $env_text = $env_text -replace '(?m)^ADMIN_JWT_SECRET=.*$',  ("ADMIN_JWT_SECRET=" + (New-Secret -Bytes 32))
    # Write without BOM so docker compose parses it cleanly
    [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot '.env'), $env_text, (New-Object System.Text.UTF8Encoding $false))
} else {
    Write-Host ".env already exists, keeping it." -ForegroundColor DarkGray
}
$dotenv = Read-DotEnv '.env'

# --- 3. dragonite/config.toml -----------------------------------------------
$cfg = Join-Path $PSScriptRoot 'dragonite\config.toml'
if (-not (Test-Path $cfg)) {
    Write-Host "Creating dragonite/config.toml from example ..." -ForegroundColor Cyan
    $toml = Get-Content -Raw 'dragonite\config.toml.example'
    $toml = $toml.Replace('__DB_USER__',     $(if ($dotenv.DB_USER) { $dotenv.DB_USER } else { 'dragonite' }))
    $toml = $toml.Replace('__DB_PASSWORD__', $dotenv.DB_PASSWORD)
    $toml = $toml.Replace('__DB_NAME__',     $(if ($dotenv.DB_NAME) { $dotenv.DB_NAME } else { 'dragonite' }))
    [System.IO.File]::WriteAllText($cfg, $toml, (New-Object System.Text.UTF8Encoding $false))
} else {
    Write-Host "dragonite/config.toml already exists, keeping it." -ForegroundColor DarkGray
}

# Bind-mount targets must exist as the right type before compose starts, otherwise
# Docker creates them as directories and the containers fail to start.
New-Item -ItemType Directory -Force -Path 'dragonite\logs', 'mariadb\data' | Out-Null

if ($NoStart) {
    Write-Host "Done (-NoStart). Edit .env and dragonite/config.toml, then run: docker compose up -d" -ForegroundColor Green
    exit 0
}

# --- 4. Pull + start ---------------------------------------------------------
Write-Host "Pulling images ..." -ForegroundColor Cyan
docker compose pull
if ($LASTEXITCODE -ne 0) { Write-Error "docker compose pull failed" }

Write-Host ($(if ($Update) { "Recreating containers ..." } else { "Starting stack ..." })) -ForegroundColor Cyan
docker compose up -d
if ($LASTEXITCODE -ne 0) { Write-Error "docker compose up failed" }

$adminPort = if ($dotenv.ADMIN_PORT) { $dotenv.ADMIN_PORT } else { '7273' }
$dragPort  = if ($dotenv.DRAGONITE_PORT) { $dotenv.DRAGONITE_PORT } else { '7272' }

Write-Host ""
Write-Host "Dragonite stack is up." -ForegroundColor Green
Write-Host "  Admin UI:       http://localhost:$adminPort"
Write-Host "  Admin login:    $($dotenv.ADMIN_USERNAME) / $($dotenv.ADMIN_PASSWORD)"
Write-Host "  Dragonite API:  http://localhost:$dragPort"
Write-Host ""
Write-Host "Next: point [rotom], [koji] and [processors] in dragonite\config.toml at your Rotom / Koji / Golbat,"
Write-Host "      set GOLBAT_ENDPOINT in .env, then run:  docker compose up -d"
Write-Host "Logs: docker compose logs -f dragonite"
