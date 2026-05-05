# BTS SIO - Projet SLAM (Stats Licences NX)

Version locale et transportable du projet stats licences, basee sur un conteneur Docker MySQL avec un jeu de donnees factices d'exemple.

Objectif :
- travailler en local
- sans authentification SQL utilisateur/mot de passe sur la machine hote
- avec une base MySQL conteneurisee et ~100 lignes d'exemple
- sans modifier le projet original

---

## Prerequis
- Windows + PowerShell 5+
- Docker Desktop installe et demarre

## Demarrage rapide

```powershell
# 1. Lance le conteneur MySQL et cree la base + donnees factices
powershell -ExecutionPolicy Bypass -File .\Setup_DockerDB.ps1

# 2. Lance l'interface
powershell -ExecutionPolicy Bypass -File .\Runner_Docker.ps1
```

Ou double-clic sur `Runner_Docker.bat`.

## Schema (5 tables)

```
pays  --<  site  --<  utilisation_licence  >--  utilisateur
                              |
                              +--  licence
```

- `pays` : referentiel des pays
- `site` : referentiel des sites (rattache au pays, code de 4 lettres)
- `utilisateur` : logins
- `licence` : catalogue des licences NX/CAO/etc.
- `utilisation_licence` : table de faits (1 ligne = 1 prise de licence)

## Connexion MySQL

| Param    | Valeur               |
|----------|----------------------|
| Host     | localhost            |
| Port     | 3307                 |
| Database | nx_licenses_stats    |
| User     | nx_app / nx_app_pwd  |

CLI rapide depuis le conteneur :
```powershell
docker exec -it nx_licenses_db mysql -u nx_app -pnx_app_pwd nx_licenses_stats
```

## Fichiers

- `docker/docker-compose.yml` : conteneur MySQL 8 + volume persistant.
- `docker/.env` : credentials et port (dev local uniquement).
- `docker/init/01_schema.sql` : creation des 5 tables.
- `docker/init/02_seed_referentiels.sql` : pays / sites / licences.
- `docker/init/03_seed_fake_data.sql` : 20 users + 100 lignes d'utilisation d'exemple.
- `Setup_DockerDB.ps1` : `up`, `-Reset` (regenere depuis zero), `-Stop`.
- `Stats_Interface_Docker.ps1` : interface WinForms branchee sur MySQL via `docker exec`.
- `Runner_Docker.ps1` / `Runner_Docker.bat` : lanceurs.

## Comportement de recherche

- Affichage en report agrege :
  - `hostname`
  - `login`
  - `lic_name`
  - `occurrence_count`
- Selection possible :
  - pays seul (tous les sites du pays)
  - un site
  - plusieurs sites
  - aucun pays (toutes donnees)

## Export CSV

Export uniquement :
- `hostname`
- `login`
- `lic_name`
