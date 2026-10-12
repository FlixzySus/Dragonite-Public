# Unown# scanner stack on Windows with Docker Desktop

This folder is the [Unown# Docker setup](https://unownhash.com/docs/setup/docker) and
[Database setup](https://unownhash.com/docs/other/database) packaged for Docker Desktop,
plus Koji. One script creates every config with generated secrets, a second script
proves the database and services are working. Follow the sections in order — it is the
same order as the official docs.

| Container | What it is | On your PC |
|-----------|------------|------------|
| `mariadb` | MariaDB 10.11 with the `dragonite`, `golbat` and `koji` databases | not published (see troubleshooting) |
| `rotom` | device controller — MITM clients on phones connect to it | UI <http://localhost:7072>, devices → `:7070` |
| `golbat` | data processor — parses what devices see, feeds maps/webhooks | API `:9001`, gRPC `:50001` |
| `koji` | geofence / area manager — draw the areas to scan | UI <http://localhost:8080> |
| `dragonite` | scanner controller — tells devices where to go | API `:7272` |
| `admin` | Dragonite's web UI — accounts, areas, proxies, workers | UI <http://localhost:7273> |

The upstream `run.sh` in the repo root is for bare-metal Linux/macOS installs
([Standard setup](https://unownhash.com/docs/setup/standard)) and does not work on Windows.

## 1. Prerequisites

- Windows 10/11 64-bit with [Docker Desktop](https://www.docker.com/products/docker-desktop/)
  installed and **running** (WSL2 backend). Give it ≥ 4 GB RAM in *Settings → Resources*.
- [Git for Windows](https://git-scm.com/download/win).
- A MITM client for your devices (the Unown# docs list the supported ones under
  [Rotom](https://unownhash.com/docs/rotom)); it is third-party and not part of this stack.

## 2. Clone into `D:\PogoMapper`

PowerShell (not CMD):

```powershell
New-Item -ItemType Directory -Force D:\PogoMapper | Out-Null
cd D:\PogoMapper
git clone https://github.com/FlixzySus/Dragonite-Public.git
cd Dragonite-Public\docker
```

## 3. Database setup

> "Make sure to have a functional Database Setup prior to starting the Unown# installation."
> — <https://unownhash.com/docs>

The docs want MariaDB 10.6+ (10.11 used here), `utf8mb4` / `utf8mb4_unicode_ci`, and one
database each for Dragonite and Golbat. `docker-compose.yml` implements exactly that:

- `mariadb:10.11` started with the docs' server flags
  (`--character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci --binlog-expire-logs-seconds=86400`).
- `mariadb/init/01-create-databases.sh` runs **once, on the first start**, and creates the
  `golbat` and `koji` databases next to `dragonite`, all `utf8mb4_unicode_ci`, and grants the
  app user (`DB_USER` in `.env`) on all three. The docs do this step by hand in TablePlus /
  Workbench; here it is automated.
- Data lives in a Docker **named volume** (`docker_mariadb_data`), not in this folder. InnoDB
  does not work on a Windows-shared bind mount (`Got error N from storage engine` during
  `ALTER TABLE`), and the volume is much faster. `docker volume ls` shows it; it survives
  `docker compose down`.
- Optional tuning per the docs' *Optimizing MariaDB* section: create `mariadb\my.cnf` and
  uncomment the matching volume line in `docker-compose.yml`. Scale the values to your PC
  (the docs' example is for a 128 GB server); `DB_BUFFER_POOL` in `.env` already sets the
  buffer pool.

You start it together with everything else in the next step and **verify it in step 5**.

## 4. Install and start the services

```powershell
.\setup.ps1
```

If PowerShell refuses to run scripts: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` first.

What it does (each file only if it does not exist yet, so re-running is safe):

1. checks Docker Desktop is up;
2. `.env` ← `.env.example` with **random** DB passwords, admin password/JWT secret,
   Golbat `api_secret` + `raw_bearer`, Koji secret;
3. `dragonite\config.toml` ← its example, wired to `mariadb`, `rotom:7071`, `golbat:9001`
   (API) + `golbat:50001` (gRPC raws, as the docs recommend), `koji:8080`, with the secrets;
4. `golbat\config.toml` ← its example, wired to `mariadb:3306` and the Koji project URL;
5. `rotom\config\local.json` ← its example (`client.host` = `0.0.0.0` so the UI is reachable);
6. `docker compose pull` + `docker compose up -d`;
7. prints every URL and login.

Use `.\setup.ps1 -NoStart` to generate the files and review them before the first start.

Result on disk:

```
D:\PogoMapper\Dragonite-Public\docker\
├── docker-compose.yml
├── setup.ps1 / check.ps1
├── .env                            <- generated, gitignored, ALL secrets live here
├── dragonite\config.toml           <- generated, gitignored      + logs\
├── golbat\config.toml              <- generated, gitignored      + cache\ logs\
├── rotom\config\local.json         <- generated, gitignored      + logs\ jobs\
└── mariadb\init\01-create-databases.sh
```

## 5. Verify the database and services

Wait ~60 s after the first start (MariaDB initialises, then each service creates its tables), then:

```powershell
.\check.ps1
```

It prints PASS/FAIL for: Docker running · all six containers running · MariaDB healthy ·
login with the `.env` credentials · the three databases exist with `utf8mb4_unicode_ci` ·
each has tables (= its service's migrations ran) · grants · Dragonite "Migration completed" ·
Golbat migration clean · Koji "Migrations successful" · every published port listening.
Every FAIL comes with the command to look at. **Do not continue until it is all green.**

## 6. Next steps (https://unownhash.com/docs/setup/next-steps)

Everything below happens in the web UIs.

### 6.1 Accounts — Dragonite Admin

1. `dragonite\config.toml` → set `enable = true` under `[auth.ptc]` and/or `[auth.nk]`
   (at least one provider must be enabled), then `docker compose restart dragonite`.
   The other keys in that block (`login_delay`, `remote_auth_url`, `token_*`) are described in
   the [Dragonite config docs](https://unownhash.com/docs/dragonite/config).
2. <http://localhost:7273> (login in `.env`) → **Accounts** → add one or batch-import, one
   per line `username,password`, with the matching provider.

### 6.2 Proxies — Dragonite Admin

The docs: "required if you have more than one or two devices". **Proxies** →
`http://USERNAME:PASSWORD@HOST:PORT`, one per line. Dragonite logs in through them itself;
no HAProxy/Squid needed.

### 6.3 Koji — areas and routes

<http://localhost:8080>, password = `KOJI_SECRET`. Dragonite's and Golbat's configs are already
pointed at Koji; you only need projects and a fence
([Koji docs — Dragonite quick start](https://koji.vercel.app/client/getting-started#dragonite-quick-start)):

1. **Admin → Projects → Create** twice:

   | | Name | Scanner | API Endpoint | API Key |
   |---|---|---|---|---|
   | Dragonite | `dragonite` | **on** | `http://dragonite:7272/reload` | *(empty)* |
   | Golbat | `golbat` (= `KOJI_GOLBAT_PROJECT` in `.env`) | off | `http://golbat:9001/api/reload-geojson` | `x-golbat-secret:<GOLBAT_API_SECRET>` |

2. **Map** → draw a polygon (or Import Wizard → Nominatim / GeoJSON) → name it → save to Kōji.
   Start small; a few km² is plenty for a first run.
3. **Admin → Geofences** → edit → **Projects** → tick both → Save.
4. **Map** → Import from Kōji → load the fence → **Calculations**: Mode *Bootstrap*, Strategy
   *Radius*, Radius *70*, Save to Kōji Db ✔, Save to Scanner Db ✔, Skip rendering ✔ → **Update**.
5. **Admin → Geofences → Sync** the fence; **Admin → Routes → Sync** the route.
6. `docker compose restart golbat` (or Admin → Projects → Sync `golbat`) so Golbat loads the fence.

Dragonite Admin → **Areas** now lists the fence with a route. Open it: Enabled, Pokemon mode
with the bootstrap route, workers = number of devices, Quest/Fort off for now.

### 6.4 Devices — MITM client

Point each device's MITM client at Rotom: `ws://<your PC's LAN IPv4>:7070`
(`ipconfig`; `setup.ps1` prints it), Rotom secret empty (matches `rotom\config\local.json`).
Windows Firewall will ask on the first inbound connection — allow Docker Desktop on **Private**
networks, or add the rule yourself:

```powershell
New-NetFirewallRule -DisplayName "Rotom devices 7070" -Direction Inbound -Protocol TCP -LocalPort 7070 -Action Allow -Profile Private
```

Devices appear in Rotom (<http://localhost:7072>), then in Dragonite Admin → **Workers**, and
the area starts getting jobs. Once the bootstrap has run a day, replace the route in Koji with
*Cluster / Spawnpoint / Radius 70 / Sort TSP* (and a *Pokestop* route for quests) and sync again.

## 7. Day-to-day

```powershell
cd D:\PogoMapper\Dragonite-Public\docker

docker compose ps                     # health
.\check.ps1                           # full verification any time
docker compose logs -f dragonite      # follow a service (dragonite / golbat / koji / rotom / admin)
docker compose restart dragonite      # after editing dragonite\config.toml (golbat likewise)
docker compose down                   # stop everything (data is kept)
docker compose up -d                  # start again

.\setup.ps1 -Update                   # pull latest images for everything + recreate
```

## 8. Troubleshooting

- **`docker: error during connect` / "pipe not found"** — Docker Desktop isn't running.
- **Docker Desktop itself fails with `wsl-bootstrap … mkfs … No such device`** — the WSL data
  disk could not be attached. `wsl --update`, `wsl --shutdown`, confirm *Virtual Machine
  Platform* is enabled, then `wsl --unregister docker-desktop` and relaunch Docker Desktop.
- **Containers restart in a loop right after first start** — MariaDB is still initialising
  (~30 s). `docker compose ps` shows `mariadb` as `healthy` when done.
- **`check.ps1` says a database is missing** — the init script only runs on an empty volume:
  `docker compose down -v` then `docker compose up -d`.
- **Koji: `500 Server Error … Unknown column 'geofence.parent'`, or Koji log says
  `Migration Error … Got error 41 from storage engine InnoDB` / `Duplicate column name
  'geometry'`** — MariaDB's data directory was on a Windows bind mount (older version of this
  compose file) and an `ALTER TABLE` half-applied. Koji logs the failure and keeps running with
  a broken schema, so it never recovers on its own. `git pull`, then **Start over**.
- **Golbat log: can't fetch Koji geofences / 404** — the Koji project named in
  `KOJI_GOLBAT_PROJECT` doesn't exist yet (step 6.3). Golbat keeps running and retries.
- **Devices can't connect to Rotom** — use the PC's LAN IP, not `localhost`; allow Docker
  through Windows Firewall; same Wi-Fi (not a guest network).
- **Port already in use** — change the matching `*_PORT` in `.env`, then `docker compose up -d`.
- **Reach MariaDB from HeidiSQL / DBeaver / TablePlus** — uncomment the `ports:` block under
  `mariadb` in `docker-compose.yml`, `docker compose up -d`, connect to `localhost:3306` with
  `DB_USER` / `DB_PASSWORD` from `.env`.
- **Changed `DB_*` or `*_DB_NAME` in `.env` after first start** — won't apply to the existing
  volume; edit the DB by hand or start over.
- **Start over (wipes all databases)** —
  ```powershell
  docker compose down -v          # -v deletes the mariadb_data volume
  docker compose up -d
  Start-Sleep 60; .\check.ps1
  ```
  Keep `.env` and the config files unless you also want new secrets; delete them too and run
  `.\setup.ps1` for a completely clean slate.

## 9. Pinning versions

`docker-compose.yml` tracks `:latest` for Dragonite/Admin and `:main` for Rotom, Golbat and Koji
(their upstream defaults). To pin or test a build, change the `image:` tag and run
`docker compose up -d`:

- <https://github.com/UnownHash/Dragonite-Public/pkgs/container/dragonite-public>
- <https://github.com/UnownHash/Golbat/pkgs/container/golbat>
- <https://github.com/UnownHash/Rotom/pkgs/container/rotom>
- <https://github.com/TurtIeSocks/Koji/pkgs/container/koji>
