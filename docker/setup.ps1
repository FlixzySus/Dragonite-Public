<#
.SYNOPSIS
    Bootstraps the full Unown# scanner stack (MariaDB, Rotom, Golbat, Koji, Dragonite, Admin)
    on Windows with Docker Desktop.

.DESCRIPTION
    - Checks that Docker Desktop is installed and running
    - Creates .env from .env.example with randomly generated passwords/secrets (first run only)
    - Creates dragonite/config.toml and golbat/config.toml from their examples, wired to those secrets (first run only)
    - Creates rotom/config/local.json from its example (first run only)
    - Pulls the images and starts the stack
    - Run .\check.ps1 afterwards to verify the database, migrations and services

    Safe to re-run: existing .env / config files are never overwritten.

.PARAMETER Update
    Pull the latest images and recreate the containers (what the README calls "Update").

.PARAMETER NoStart
    Only generate the config files, don't pull or start anything.

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
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function New-Secret {
    param([int]$Bytes = 24)
    $buf = New-Object byte[] $Bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
    # hex keeps it safe for .env, TOML, JSON, mysql:// URLs and MariaDB without quoting headaches
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

function Get-Or {
    param($Value, $Default)
    if ([string]::IsNullOrEmpty($Value)) { return $Default } else { return $Value }
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
    $envText = Get-Content -Raw '.env.example'
    $generated = @{
        DB_ROOT_PASSWORD  = New-Secret
        DB_PASSWORD       = New-Secret
        ADMIN_PASSWORD    = New-Secret -Bytes 9
        ADMIN_JWT_SECRET  = New-Secret -Bytes 32
        GOLBAT_API_SECRET = New-Secret
        GOLBAT_RAW_BEARER = New-Secret
        KOJI_SECRET       = New-Secret
    }
    foreach ($key in $generated.Keys) {
        $envText = $envText -replace "(?m)^$key=.*$", "$key=$($generated[$key])"
    }
    [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot '.env'), $envText, $utf8NoBom)
} else {
    Write-Host ".env already exists, keeping it." -ForegroundColor DarkGray
}
$dotenv = Read-DotEnv '.env'

# --- 3. dragonite/config.toml -----------------------------------------------
$cfg = Join-Path $PSScriptRoot 'dragonite\config.toml'
if (-not (Test-Path $cfg)) {
    Write-Host "Creating dragonite/config.toml from example ..." -ForegroundColor Cyan
    $toml = Get-Content -Raw 'dragonite\config.toml.example'
    $toml = $toml.Replace('__DB_USER__',           (Get-Or $dotenv.DB_USER 'dragonite'))
    $toml = $toml.Replace('__DB_PASSWORD__',       $dotenv.DB_PASSWORD)
    $toml = $toml.Replace('__DB_NAME__',           (Get-Or $dotenv.DB_NAME 'dragonite'))
    $toml = $toml.Replace('__KOJI_SECRET__',       $dotenv.KOJI_SECRET)
    $toml = $toml.Replace('__GOLBAT_API_SECRET__', $dotenv.GOLBAT_API_SECRET)
    $toml = $toml.Replace('__GOLBAT_RAW_BEARER__', $dotenv.GOLBAT_RAW_BEARER)
    [System.IO.File]::WriteAllText($cfg, $toml, $utf8NoBom)
} else {
    Write-Host "dragonite/config.toml already exists, keeping it." -ForegroundColor DarkGray
}

# --- 4. golbat/config.toml --------------------------------------------------
$golbatCfg = Join-Path $PSScriptRoot 'golbat\config.toml'
if (-not (Test-Path $golbatCfg)) {
    Write-Host "Creating golbat/config.toml from example ..." -ForegroundColor Cyan
    $toml = Get-Content -Raw 'golbat\config.toml.example'
    $toml = $toml.Replace('__DB_USER__',             (Get-Or $dotenv.DB_USER 'dragonite'))
    $toml = $toml.Replace('__DB_PASSWORD__',         $dotenv.DB_PASSWORD)
    $toml = $toml.Replace('__GOLBAT_DB_NAME__',      (Get-Or $dotenv.GOLBAT_DB_NAME 'golbat'))
    $toml = $toml.Replace('__GOLBAT_API_SECRET__',   $dotenv.GOLBAT_API_SECRET)
    $toml = $toml.Replace('__GOLBAT_RAW_BEARER__',   $dotenv.GOLBAT_RAW_BEARER)
    $toml = $toml.Replace('__KOJI_SECRET__',         $dotenv.KOJI_SECRET)
    $toml = $toml.Replace('__KOJI_GOLBAT_PROJECT__', (Get-Or $dotenv.KOJI_GOLBAT_PROJECT 'golbat'))
    [System.IO.File]::WriteAllText($golbatCfg, $toml, $utf8NoBom)
} else {
    Write-Host "golbat/config.toml already exists, keeping it." -ForegroundColor DarkGray
}

# --- 5. rotom/config/local.json ---------------------------------------------
$rotomCfg = Join-Path $PSScriptRoot 'rotom\config\local.json'
if (-not (Test-Path $rotomCfg)) {
    Write-Host "Creating rotom/config/local.json from example ..." -ForegroundColor Cyan
    Copy-Item 'rotom\config\local.json.example' $rotomCfg
} else {
    Write-Host "rotom/config/local.json already exists, keeping it." -ForegroundColor DarkGray
}

# Bind-mount targets must exist as the right type before compose starts, otherwise
# Docker creates them as directories and the containers fail to start.
New-Item -ItemType Directory -Force -Path `
    'dragonite\logs', 'golbat\cache', 'golbat\logs', 'rotom\logs', 'rotom\jobs' | Out-Null

if ($NoStart) {
    Write-Host "Done (-NoStart). Review .env, dragonite\config.toml, golbat\config.toml and rotom\config\local.json, then run: docker compose up -d" -ForegroundColor Green
    exit 0
}

# --- 6. Pull + start ---------------------------------------------------------
Write-Host "Pulling images (first time this downloads a few hundred MB) ..." -ForegroundColor Cyan
docker compose pull
if ($LASTEXITCODE -ne 0) { Write-Error "docker compose pull failed" }

Write-Host ($(if ($Update) { "Recreating containers ..." } else { "Starting stack ..." })) -ForegroundColor Cyan
docker compose up -d
if ($LASTEXITCODE -ne 0) { Write-Error "docker compose up failed" }

$adminPort  = Get-Or $dotenv.ADMIN_PORT '7273'
$kojiPort   = Get-Or $dotenv.KOJI_PORT '8080'
$rotomPort  = Get-Or $dotenv.ROTOM_UI_PORT '7072'
$devicePort = Get-Or $dotenv.ROTOM_DEVICE_PORT '7070'
$golbatPort = Get-Or $dotenv.GOLBAT_PORT '9001'
$lanIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
          Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
          Select-Object -First 1 -ExpandProperty IPAddress)

Write-Host ""
Write-Host "Stack is starting (MariaDB needs ~30 s on the very first run)." -ForegroundColor Green
Write-Host "  Dragonite Admin:  http://localhost:$adminPort   login $($dotenv.ADMIN_USERNAME) / $($dotenv.ADMIN_PASSWORD)"
Write-Host "  Koji:             http://localhost:$kojiPort   password $($dotenv.KOJI_SECRET)"
Write-Host "  Rotom:            http://localhost:$rotomPort"
Write-Host "  Golbat API:       http://localhost:$golbatPort   secret $($dotenv.GOLBAT_API_SECRET)"
if ($lanIp) {
Write-Host "  Devices connect to Rotom at:  ws://${lanIp}:$devicePort"
}
Write-Host ""
Write-Host "All secrets are in .env."
Write-Host "Verify the database and services:  .\check.ps1   (wait ~60 s after first start)"
Write-Host "Then follow README.md 'Next steps'. Logs: docker compose logs -f dragonite   (or golbat / koji / rotom / admin)"
