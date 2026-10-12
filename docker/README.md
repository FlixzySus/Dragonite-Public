# Unown# scanner stack on Windows with Docker Desktop

This folder runs the **whole** scanner backend as containers, with one script:

| Container | What it is | Web UI / port on your PC |
|-----------|------------|--------------------------|
| `mariadb` | one MariaDB server with the `dragonite`, `golbat` and `koji` databases | not published (see troubleshooting) |
| `rotom` | device controller — your phones / emulators connect to it | UI <http://localhost:7072>, devices → `:7070` |
| `golbat` | data processor — parses what the devices see, feeds maps/webhooks | API `:9001` |
| `koji` | geofence / area manager — draw the areas to scan | UI <http://localhost:8080> |
| `dragonite` | the scanner controller — tells devices where to go | API `:7272` |
| `admin` | Dragonite's web UI — accounts, areas, workers, status | UI <http://localhost:7273> |

No Linux shell, `jq` or `pm2` needed. The upstream `run.sh` in the repo root is for
bare-metal Linux/macOS installs and does not work on Windows.

## 1. Prerequisites

- Windows 10/11 64-bit with [Docker Desktop](https://www.docker.com/products/docker-desktop/)
  installed and **running** (WSL2 backend, the default, is fine). Give it at least
  4 GB RAM in *Settings → Resources* if you plan to scan more than a small area.
- [Git for Windows](https://git-scm.com/download/win).

## 2. Clone into `D:\PogoMapper`

Open **PowerShell** (not CMD):

```powershell
New-Item -ItemType Directory -Force D:\PogoMapper | Out-Null
cd D:\PogoMapper
git clone https://github.com/FlixzySus/Dragonite-Public.git
cd Dragonite-Public\docker
```

## 3. Run the setup script

```powershell
.\setup.ps1
```

If PowerShell refuses to run scripts, allow it for this one session only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup.ps1
```

The script will:

1. check Docker Desktop is up,
2. create `.env` with **randomly generated** passwords and secrets for everything,
3. create `dragonite\config.toml` and `rotom\config\local.json` from their examples,
   already wired to the other containers and to those secrets,
4. `docker compose pull` + `docker compose up -d`,
5. print every URL and login.

It never overwrites an existing `.env` or config file, so re-running is safe.
Use `.\setup.ps1 -NoStart` if you want to edit the files before the first start.

Result on disk:

```
D:\PogoMapper\Dragonite-Public\docker\
├── docker-compose.yml
├── setup.ps1
├── .env                            <- generated, gitignored, ALL secrets live here
├── dragonite\
│   ├── config.toml                 <- generated, gitignored
│   └── logs\
├── rotom\
│   ├── config\local.json           <- generated, gitignored
│   ├── logs\
│   └── jobs\
├── golbat\
│   ├── cache\
│   └── logs\
└── mariadb\
    ├── init\01-create-databases.sh <- creates golbat + koji DBs on first start
    └── data\                       <- database files, gitignored
```

## 4. First-time configuration (in this order)

Everything below happens in the web UIs; no files to edit.

1. **Koji** — <http://localhost:8080>, password = `KOJI_SECRET` from `.env`.
   - Draw or import the geofence(s) you want to scan.
   - Create a **project** named `golbat` (or whatever `KOJI_GOLBAT_PROJECT` is in
     `.env`) and assign your geofences to it. Golbat reloads areas from that project.
   - Create a second project for Dragonite (e.g. `dragonite`) with the same fences;
     Dragonite pulls its areas from Koji projects via the Admin UI.
   - Optional: set `KOJI_START_LAT` / `KOJI_START_LON` in `.env` so the map opens on
     your town, then `docker compose up -d koji`.
2. **Dragonite Admin** — <http://localhost:7273>, login from `.env`.
   - *Accounts*: import your PTC/NK accounts.
   - *Areas*: import from Koji, enable the modes you want (pokemon, quests, forts…).
   - Restart Dragonite after enabling an auth provider in `dragonite\config.toml`
     (`[auth.ptc] enable = true` / `[auth.nk]`): `docker compose restart dragonite`.
3. **Devices** — point your phones / emulators at Rotom:
   `ws://<your PC's LAN IP>:7070` (the setup script prints it). They show up in the
   Rotom UI <http://localhost:7072> and then in Dragonite Admin → Workers.
   Windows Firewall will ask to allow Docker on first inbound connection — allow it
   on *Private* networks.
4. **A map / notifier** (ReactMap, Poracle, …) is *not* included. Point it at the
   Golbat API `http://localhost:9001` with `GOLBAT_API_SECRET`, or add it as a
   webhook consumer under `golbat.environment` in `docker-compose.yml`
   (commented example is there).

Dragonite logs *"connected to rotom"* and *"golbat … ok"* once everything is wired.

## 5. Day-to-day

```powershell
cd D:\PogoMapper\Dragonite-Public\docker

docker compose ps                     # what's running / health
docker compose logs -f dragonite      # follow a service (dragonite / golbat / koji / rotom / admin)
docker compose restart dragonite      # after editing dragonite\config.toml
docker compose down                   # stop everything (data is kept)
docker compose up -d                  # start again

.\setup.ps1 -Update                   # pull latest images for everything + recreate
```

## 6. Troubleshooting

- **`docker: error during connect` / "pipe not found"** — Docker Desktop isn't
  running. Start it and wait until the tray icon stops animating.
- **Containers restart in a loop right after first start** — MariaDB is still
  initialising (~30 s). `docker compose ps` shows `mariadb` as `healthy` when done;
  Dragonite/Golbat/Koji wait for that automatically.
- **Golbat log: can't fetch Koji geofences / 404** — the Koji project named in
  `KOJI_GOLBAT_PROJECT` doesn't exist yet (step 4.1). Golbat keeps running and
  retries.
- **Koji log: table doesn't exist** — Golbat hasn't finished creating its tables
  yet. Harmless on first boot; `docker compose restart koji` if it persists.
- **Devices can't connect to Rotom** — use the PC's LAN IP, not `localhost`; allow
  Docker through Windows Firewall; check `ROTOM_DEVICE_PORT` isn't changed in `.env`.
- **Port already in use** — change the matching `*_PORT` in `.env`, then
  `docker compose up -d`.
- **Want to reach MariaDB from HeidiSQL/DBeaver** — uncomment the `ports:` block
  under `mariadb` in `docker-compose.yml`, `docker compose up -d`, connect to
  `localhost:3306` with `DB_USER` / `DB_PASSWORD` from `.env`.
- **Changed `DB_*` or `*_DB_NAME` in `.env` after first start** — the init script
  only runs on an empty data dir, so the change won't apply. Either edit the DB by
  hand or start over.
- **Start over** — `docker compose down`, delete `mariadb\data`, `.env`,
  `dragonite\config.toml` and `rotom\config\local.json`, run `.\setup.ps1` again.
  **This wipes all databases.**

## 7. Pinning versions

`docker-compose.yml` tracks `:latest` for Dragonite/Admin and `:main` for Rotom,
Golbat and Koji (their upstream defaults). To pin or test a build, change the
`image:` tag and run `docker compose up -d`:

- <https://github.com/UnownHash/Dragonite-Public/pkgs/container/dragonite-public>
- <https://github.com/UnownHash/Golbat/pkgs/container/golbat>
- <https://github.com/UnownHash/Rotom/pkgs/container/rotom>
- <https://github.com/TurtIeSocks/Koji/pkgs/container/koji>
