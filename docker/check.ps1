<#
.SYNOPSIS
    Verifies the Unown# Docker stack: database, schemas/migrations, containers and ports.

.DESCRIPTION
    Run after setup.ps1 (give the stack ~60 s on first start). Every line is PASS or FAIL
    with a hint. Exit code 0 = all passed, 1 = something failed.

    "Make sure to have a functional Database Setup prior to starting the Unown# installation"
    (https://unownhash.com/docs) - the database checks here are that proof.

.EXAMPLE
    PS D:\PogoMapper\Dragonite-Public\docker> .\check.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
Set-Location -Path $PSScriptRoot
$script:failures = 0

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

function Report {
    param([string]$Name, [bool]$Ok, [string]$Hint = '')
    if ($Ok) {
        Write-Host ("[PASS] " + $Name) -ForegroundColor Green
    } else {
        Write-Host ("[FAIL] " + $Name) -ForegroundColor Red
        if ($Hint) { Write-Host ("       " + $Hint) -ForegroundColor DarkGray }
        $script:failures++
    }
}

# Runs a SQL statement inside the mariadb container as the application user.
# Password goes via MYSQL_PWD so no quoting is needed on the PowerShell side
# (Windows PowerShell 5.1 mangles nested quotes passed to native commands).
function Invoke-Sql {
    param([string]$Sql, [string]$Database = '')
    $args = @('compose', 'exec', '-T', '-e', "MYSQL_PWD=$($dotenv.DB_PASSWORD)", 'mariadb',
              'mariadb', "-u$dbUser", '-N', '-B', '-e', $Sql)
    if ($Database) { $args += $Database }
    $out = & docker @args 2>&1
    return @{ ok = ($LASTEXITCODE -eq 0); out = ($out | Out-String).Trim() }
}

if (-not (Test-Path '.env')) {
    Write-Host "No .env found - run .\setup.ps1 first." -ForegroundColor Red
    exit 1
}
$dotenv   = Read-DotEnv '.env'
$dbUser   = Get-Or $dotenv.DB_USER 'dragonite'
$dbNames  = @((Get-Or $dotenv.DB_NAME 'dragonite'), (Get-Or $dotenv.GOLBAT_DB_NAME 'golbat'), (Get-Or $dotenv.KOJI_DB_NAME 'koji'))

Write-Host ""
Write-Host "== Docker ==" -ForegroundColor Cyan
docker info 2>&1 | Out-Null
Report "Docker Desktop is running" ($LASTEXITCODE -eq 0) "Start Docker Desktop and wait for the whale icon to settle."
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host ""
Write-Host "== Containers ==" -ForegroundColor Cyan
foreach ($c in @('mariadb', 'rotom', 'golbat', 'koji', 'dragonite', 'dragonite-admin')) {
    $state = (docker inspect -f '{{.State.Status}}' $c 2>$null)
    Report ("container '$c' is running (state: $state)") ($state -eq 'running') "docker compose logs --tail 50 $c"
}
$health = (docker inspect -f '{{.State.Health.Status}}' mariadb 2>$null)
Report "mariadb healthcheck is 'healthy' (is: $health)" ($health -eq 'healthy') "First start takes ~30 s. Otherwise: docker compose logs mariadb"

Write-Host ""
Write-Host "== Database (as user '$dbUser') ==" -ForegroundColor Cyan
$r = Invoke-Sql "SELECT VERSION()"
Report "can connect to MariaDB with the credentials from .env (version: $($r.out))" $r.ok "DB_USER / DB_PASSWORD in .env must match what the volume was created with. Changed them? docker compose down -v and start over."

if ($r.ok) {
    $r = Invoke-Sql "SELECT schema_name, default_collation_name FROM information_schema.schemata WHERE schema_name IN ('$($dbNames -join "','")')"
    $found = @{}
    foreach ($line in ($r.out -split "`n")) {
        $parts = $line.Trim() -split "`t"
        if ($parts.Count -ge 2) { $found[$parts[0]] = $parts[1] }
    }
    foreach ($db in $dbNames) {
        Report "database '$db' exists (collation: $($found[$db]))" ($found.ContainsKey($db)) "Created by mariadb/init/01-create-databases.sh on the FIRST start only. Missing? docker compose down -v, then docker compose up -d."
        if ($found.ContainsKey($db) -and $found[$db] -ne 'utf8mb4_unicode_ci') {
            Write-Host "       note: Unown# docs recommend utf8mb4_unicode_ci" -ForegroundColor DarkYellow
        }
    }

    foreach ($db in $dbNames) {
        $r = Invoke-Sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db'"
        $n = 0; [void][int]::TryParse($r.out, [ref]$n)
        Report "database '$db' has tables = migrations ran ($n tables)" ($r.ok -and $n -gt 0) "The owning service creates its tables on first start. Check: docker compose logs $(if ($db -eq $dbNames[0]) {'dragonite'} elseif ($db -eq $dbNames[1]) {'golbat'} else {'koji'})"
    }

    $r = Invoke-Sql "SHOW GRANTS"
    $okGrants = $r.ok
    foreach ($db in $dbNames) { if ($r.out -notmatch [regex]::Escape($db)) { $okGrants = $false } }
    Report "user '$dbUser' has grants on all three databases" $okGrants "Grants are set by the init script on first start."
}

Write-Host ""
Write-Host "== Service logs ==" -ForegroundColor Cyan
$log = (docker compose logs --no-color --tail 500 dragonite 2>&1 | Out-String)
Report "dragonite: database migration completed" ($log -match 'Migration completed') "docker compose logs dragonite | Select-String DB"
Report "dragonite: no 'storage engine' / schema errors" (-not ($log -match 'storage engine|Unknown column|Duplicate column')) "Schema is broken - see README 'Start over'."

$log = (docker compose logs --no-color --tail 500 golbat 2>&1 | Out-String)
Report "golbat: started migration without errors" (($log -match 'Starting migration') -and -not ($log -match '(?i)migration.*(error|fail)')) "docker compose logs golbat"
if ($log -match 'KOJI: Response 200') {
    Report "golbat: loaded geofences from Koji" $true
} else {
    Write-Host "[INFO] golbat: Koji project not loaded yet (create the '$(Get-Or $dotenv.KOJI_GOLBAT_PROJECT 'golbat')' project in Koji, then docker compose restart golbat)" -ForegroundColor DarkYellow
}

$log = (docker compose logs --no-color --tail 500 koji 2>&1 | Out-String)
Report "koji: 'Migrations successful'" ($log -match 'Migrations successful') "docker compose logs koji | Select-String Migration"
Report "koji: no migration errors" (-not ($log -match 'Migration Error')) "Schema is broken - see README 'Start over'."

Write-Host ""
Write-Host "== Ports on localhost ==" -ForegroundColor Cyan
$ports = @{
    'dragonite API'   = Get-Or $dotenv.DRAGONITE_PORT '7272'
    'dragonite admin' = Get-Or $dotenv.ADMIN_PORT '7273'
    'golbat API'      = Get-Or $dotenv.GOLBAT_PORT '9001'
    'koji UI'         = Get-Or $dotenv.KOJI_PORT '8080'
    'rotom devices'   = Get-Or $dotenv.ROTOM_DEVICE_PORT '7070'
    'rotom UI'        = Get-Or $dotenv.ROTOM_UI_PORT '7072'
}
foreach ($name in ($ports.Keys | Sort-Object)) {
    $p = [int]$ports[$name]
    $ok = (Test-NetConnection -ComputerName 'localhost' -Port $p -InformationLevel Quiet -WarningAction SilentlyContinue)
    Report ("$name listening on localhost:$p") $ok "docker compose ps; port clash? change the *_PORT in .env"
}

Write-Host ""
if ($script:failures -eq 0) {
    Write-Host "All checks passed. Database and services are functional." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($script:failures) check(s) failed - see hints above." -ForegroundColor Red
    exit 1
}
