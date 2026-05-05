param(
    [switch]$Reset,
    [switch]$Stop
)

# =========================================================
#  BTS SIO - Setup base MySQL via Docker
#  -Reset : detruit le volume puis recree (donnees factices regenerees)
#  -Stop  : arrete simplement les conteneurs
# =========================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$dockerDir    = Join-Path $PSScriptRoot 'docker'
$container    = 'nx_licenses_db'

function Test-DockerAvailable {
    try {
        $null = & docker version --format '{{.Server.Version}}' 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

if (-not (Test-DockerAvailable)) {
    Write-Host "ERREUR: Docker n'est pas disponible." -ForegroundColor Red
    Write-Host "Verifie que Docker Desktop est installe et demarre." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $dockerDir)) {
    Write-Host "ERREUR: dossier '$dockerDir' introuvable." -ForegroundColor Red
    exit 1
}

Push-Location $dockerDir
try {
    if ($Stop) {
        Write-Host "Arret du conteneur..." -ForegroundColor Cyan
        & docker compose down
        exit 0
    }

    if ($Reset) {
        Write-Host "Mode RESET: arret + suppression du volume..." -ForegroundColor Yellow
        & docker compose down -v
    }

    Write-Host "Demarrage du conteneur MySQL..." -ForegroundColor Cyan
    & docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERREUR: 'docker compose up' a echoue." -ForegroundColor Red
        exit 1
    }
}
finally {
    Pop-Location
}

# Attente healthcheck
Write-Host "Attente que MySQL soit pret..." -ForegroundColor Cyan
$maxWait = 180
$waited  = 0
$ready   = $false
while ($waited -lt $maxWait) {
    $health = & docker inspect --format '{{.State.Health.Status}}' $container 2>$null
    if ($health -eq 'healthy') {
        $ready = $true
        break
    }
    Start-Sleep -Seconds 2
    $waited += 2
    Write-Host ("  ...etat = {0} ({1}s)" -f $health, $waited) -ForegroundColor Gray
}

if (-not $ready) {
    Write-Host "ERREUR: timeout en attendant MySQL." -ForegroundColor Red
    Write-Host "Logs du conteneur :" -ForegroundColor Yellow
    & docker logs --tail 30 $container
    exit 1
}

Write-Host ""
Write-Host "MySQL est pret." -ForegroundColor Green
Write-Host ""
Write-Host "Connexion :" -ForegroundColor Cyan
Write-Host "  Host     : localhost"        -ForegroundColor Gray
Write-Host "  Port     : 3307"             -ForegroundColor Gray
Write-Host "  Database : nx_licenses_stats" -ForegroundColor Gray
Write-Host "  User     : nx_app / nx_app_pwd" -ForegroundColor Gray
Write-Host ""

# Petit recap des donnees
$recapSql = @"
SELECT
    (SELECT COUNT(*) FROM pays)                AS nb_pays,
    (SELECT COUNT(*) FROM site)                AS nb_sites,
    (SELECT COUNT(*) FROM utilisateur)         AS nb_users,
    (SELECT COUNT(*) FROM licence)             AS nb_licences,
    (SELECT COUNT(*) FROM utilisation_licence) AS nb_utilisations;
"@

$recap = $recapSql | & docker exec -i `
    -e MYSQL_PWD=nx_app_pwd `
    $container mysql -u nx_app nx_licenses_stats --batch --table 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "Contenu de la base :" -ForegroundColor Cyan
    $recap | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
} else {
    Write-Host "Avertissement: lecture du recap impossible." -ForegroundColor Yellow
    Write-Host $recap -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Tu peux lancer .\Runner_Docker.ps1 (interface WinForms)." -ForegroundColor Cyan
Write-Host "Pour arreter :    .\Setup_DockerDB.ps1 -Stop" -ForegroundColor DarkGray
Write-Host "Pour repartir a zero : .\Setup_DockerDB.ps1 -Reset" -ForegroundColor DarkGray
