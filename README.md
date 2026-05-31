# SealRoute self-host package

Everything you need to self-host [SealRoute](https://www.sealroute.com) on your own server with Docker.

This directory is mirrored to [github.com/sealroute/sealroute](https://github.com/sealroute/sealroute) so you can pull it directly without cloning the full source tree.

## Contents

| File | Purpose |
| --- | --- |
| `deploy.sh` | Wrapper around `docker compose` for the usual lifecycle commands |
| `docker-compose.yml` | Production stack: SealRoute + PostgreSQL + Caddy (auto HTTPS) |
| `docker-compose.dokploy.yml` | Variant for [Dokploy](https://dokploy.com) / Traefik-based hosts |
| `.env.example` | Environment template (copy to `.env`) |

## Quickstart (5 steps)

### 1. Prerequisites

- A Linux host (Ubuntu 22.04+ or similar) with **2 GB RAM** and **10 GB disk** minimum.
- **Docker Engine 24+** and the **Docker Compose v2** plugin:
  ```sh
  docker --version
  docker compose version
  ```
- A public domain pointing at the server (DNS A record), or just localhost for a quick trial.

### 2. Grab this package

```sh
mkdir sealroute && cd sealroute
curl -L https://raw.githubusercontent.com/sealroute/sealroute/main/docker-compose.yml -o docker-compose.yml
curl -L https://raw.githubusercontent.com/sealroute/sealroute/main/deploy.sh         -o deploy.sh
curl -L https://raw.githubusercontent.com/sealroute/sealroute/main/.env.example       -o .env.example
chmod +x deploy.sh
```

Or clone the whole repo: `git clone https://github.com/sealroute/sealroute.git && cd sealroute`.

### 3. Configure

```sh
cp .env.example .env
$EDITOR .env   # set HOST, APP_URL, etc. (SECRET_KEY_BASE auto-fills on first run)
```

Key variables:

- `HOST` — your public domain (e.g. `app.example.com`). Caddy uses this to bind and issue TLS.
- `APP_URL` — public URL (e.g. `https://app.example.com`). Used in outbound email links.

See `.env.example` for the full list with comments.

### 4. Start the stack

```sh
./deploy.sh up
```

This pulls `sealroute/sealroute:latest`, brings up Postgres, SealRoute, and Caddy in the background, and Caddy will issue a Let's Encrypt certificate for `HOST` automatically.

Tail the logs while it boots:

```sh
./deploy.sh logs
```

You're ready when you see Puma listening on `tcp://0.0.0.0:3000`.

### 5. Initial setup in the browser

1. Open `https://your.domain` — first visit redirects you to `/setup` to create the first admin.
2. After setup, you land on `/license`. Buy a license (or click "Buy license" from `/pricing` / `/` — no login required for the buy flow) and activate the key Aplindo emails you.
3. That's it. The full walkthrough with screenshots lives at `/install` inside the running app.

## Common operations

| Command | What it does |
| --- | --- |
| `./deploy.sh up` | Pull (if needed) and start the stack |
| `./deploy.sh down` | Stop the stack |
| `./deploy.sh restart` | `down` + `up` |
| `./deploy.sh pull` | Refresh the app image |
| `./deploy.sh logs [service]` | Tail logs (default: `app`) |
| `./deploy.sh sh` | Shell inside the app container |
| `./deploy.sh psql` | Open `psql` in the Postgres container |
| `./deploy.sh status` | `docker compose ps` |
| `./deploy.sh rm` | Force-remove containers (volumes preserved) |
| `./deploy.sh reset` | Destroy containers **and** data volumes (irreversible) |

### Updating to a new release

```sh
./deploy.sh pull
./deploy.sh restart
# Database migrations run automatically on container start.
```

## Dokploy / Traefik deployments

If you run on [Dokploy](https://dokploy.com) or any other Traefik-based host, use `docker-compose.dokploy.yml` instead and let Traefik handle TLS / routing. The image and env semantics are identical; the difference is in the labels and the absence of port bindings.

## Links

- Marketing site: [sealroute.com](https://www.sealroute.com)
- Docker Hub: [hub.docker.com/r/sealroute/sealroute](https://hub.docker.com/r/sealroute/sealroute)
- In-app install guide: `/install` (rendered by SealRoute once it boots)
