[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ifc = Join-Path $PSScriptRoot 'Stats_Interface_Docker.ps1'

if (-not (Test-Path $ifc)) {
    Write-Host "ERREUR: $ifc introuvable." -ForegroundColor Red
    exit 1
}

# Verifie rapidement que le conteneur tourne
$state = & docker inspect --format '{{.State.Running}}' nx_licenses_db 2>$null
if ($LASTEXITCODE -ne 0 -or $state -ne 'true') {
    Write-Host "Le conteneur 'nx_licenses_db' n'est pas demarre." -ForegroundColor Yellow
    Write-Host "Lance d'abord: .\Setup_DockerDB.ps1" -ForegroundColor Yellow
    exit 1
}

& powershell -ExecutionPolicy Bypass -File $ifc
