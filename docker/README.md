# Dragonite on Windows with Docker Desktop

Everything in this folder runs Dragonite, the Admin UI and a MariaDB database as
containers. No Linux shell, `jq` or `pm2` needed — the upstream `run.sh` in the
repo root is for bare-metal Linux/macOS installs and does not work on Windows.

## 1. Prerequisites

- Windows 10/11 64-bit with [Docker Desktop](https://www.docker.com/products/docker-desktop/)
  installed and **running** (WSL2 backend, the default, is fine).
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
2. create `.env` with **randomly generated** DB passwords, admin password and JWT secret,
3. create `dragonite\config.toml` from the example, wired to the MariaDB container,
4. `docker compose pull` + `docker compose up -d`,
5. print the Admin URL and login.

It never overwrites an existing `.env` or `config.toml`, so re-running is safe.

Result on disk:

```
D:\PogoMapper\Dragonite-Public\docker\
├── docker-compose.yml
├── .env                      <- generated, gitignored, keep private
├── setup.ps1
├── dragonite\
│   ├── config.toml           <- generated, gitignored, edit this
│   └── logs\                 <- dragonite.log lands here
└── mariadb\data\             <- database files, gitignored
```

## 4. Wire up the rest of the stack

Dragonite is one piece of the Unown# stack and **will not scan anything on its
own**. It needs:

| Component | What it does | Where Dragonite expects it |
|-----------|--------------|----------------------------|
| **Rotom** | device controller the phones/emulators connect to | `[rotom] endpoint` in `dragonite\config.toml` |
| **Golbat** | data processor / raw parser, also needs its own DB | `[processors] golbat_endpoint` in `config.toml` **and** `GOLBAT_ENDPOINT` in `.env` |
| **Koji** | geofence / area manager | `[koji]` in `config.toml` |
| **Accounts** | PTC/NK accounts to scan with | Admin UI → Accounts (after first start) |

The generated config points all of them at `host.docker.internal:<port>`, which
means *"a program running directly on this Windows PC"*. If you later run Rotom /
Golbat / Koji as containers in the **same** compose project, replace
`host.docker.internal` with the service name (e.g. `http://golbat:9001`). If they
live in a different compose project, put them on a shared Docker network.

Tip: run `.\setup.ps1 -NoStart` to generate the files, edit them, then start with
`docker compose up -d`.

## 5. Day-to-day

```powershell
cd D:\PogoMapper\Dragonite-Public\docker

docker compose ps                     # what's running
docker compose logs -f dragonite      # follow Dragonite log (also in dragonite\logs\)
docker compose logs -f admin
docker compose restart dragonite      # after editing dragonite\config.toml
docker compose down                   # stop everything (data is kept)

.\setup.ps1 -Update                   # pull latest images + recreate = "Update" in the main README
```

Admin UI: <http://localhost:7273> — credentials are in `.env`
(`ADMIN_USERNAME` / `ADMIN_PASSWORD`).

## 6. Troubleshooting

- **`docker: error during connect` / "pipe not found"** — Docker Desktop isn't
  running. Start it and wait until the tray icon stops animating.
- **`dragonite` restarts in a loop, log says can't connect to DB** — MariaDB is
  still initialising on first start (can take ~30 s). `docker compose ps` should
  show `mariadb` as `healthy`; Dragonite waits for that automatically.
- **Admin UI shows backend errors** — Golbat isn't running / `GOLBAT_ENDPOINT`
  in `.env` is wrong. The UI still loads; account management works without Golbat.
- **Port already in use** — change `DRAGONITE_PORT` / `ADMIN_PORT` in `.env`,
  then `docker compose up -d`.
- **Want to reach MariaDB from HeidiSQL/DBeaver** — uncomment the `ports:` block
  under `mariadb` in `docker-compose.yml`, `docker compose up -d`, connect to
  `localhost:3306` with `DB_USER` / `DB_PASSWORD` from `.env`.
- **Start over** — `docker compose down -v`, delete `mariadb\data`, `.env` and
  `dragonite\config.toml`, run `.\setup.ps1` again. This wipes the database.

## 7. Testing images

The compose file tracks `:latest` for both images. To try a specific or testing
build, change the `image:` tags in `docker-compose.yml` to a tag from
<https://github.com/UnownHash/Dragonite-Public/pkgs/container/dragonite-public>
and run `docker compose up -d`.
