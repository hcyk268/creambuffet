## Requirements

- Git
- Godot 4.6
- Docker and Docker Compose for running or deploying the dedicated server

## Quick Start

Create the local environment file used by Docker:

```bash
cp .env.example .env
```

Start the multiplayer server container from the repository root:

```bash
docker compose up --build
```

Open the client project in Godot:

```bash
godot --path client
```

For online play, the client reads its server endpoint from:

```text
client/config/client_network.cfg
```

The default target is local development:

```ini
[server]
host="127.0.0.1"
port=7000
```

## Running Without Docker

Run the headless server directly with Godot:

```bash
godot --headless --path server
```

Run the client directly:

```bash
godot --path client
```

## Catalog Authoring

Online maps and levels are authored through the shared gameplay catalog.

- Authoring guide: `docs/CATALOG_AUTHORING.md`
- Client catalog: `client/data/game_catalog.json`
- Server catalog: `server/data/game_catalog.json`

The catalog now supports:

- map-level `default_rulesets`
- level-level `extra_rulesets` and `removed_rulesets`
- map/level `player_state_defaults` for seeding level-specific player state

Validate catalog drift and common authoring mistakes:

```bash
godot --headless --script tests/integration/validate_catalogs.gd
```

## Environment

Server runtime variables:

```env
CREAMBUFFET_SERVER_PORT=7000
CREAMBUFFET_SERVER_MAX_CLIENTS=32
```

Optional smoke-test helper:

```env
CREAMBUFFET_SERVER_EXIT_AFTER_MS=3000
```

Client environment overrides are enabled by default in
`client/config/client_network.cfg`:

```env
CREAMBUFFET_SERVER_HOST=127.0.0.1
CREAMBUFFET_SERVER_PORT=7000
CREAMBUFFET_PLAYER_NAME=Player
```

## Docker Server

Build and run:

```bash
docker compose up --build
```

Run in the background:

```bash
docker compose up -d --build
```

Show logs:

```bash
docker compose logs -f server
```

Stop:

```bash
docker compose down
```

Manual Docker commands:

```bash
docker build -t creambuffet-server .
docker run --rm --env-file .env -p 7000:7000/udp --name creambuffet-server creambuffet-server
```

The image copies only the `server/` project and runs it with the Godot Linux
binary in headless mode. The server listens on UDP port `7000` unless
`CREAMBUFFET_SERVER_PORT` overrides it.

## VPS Deployment

On the VPS, open the selected UDP server port in both the host firewall and any
cloud firewall/security group:

```bash
sudo ufw allow 7000/udp
```

For a manual source deployment:

```bash
git clone <repo-url>
cd creambuffet
cp .env.example .env
docker compose up -d --build
```

For the GitHub Actions CD workflow, prepare `/opt/creambuffet/.env`:

```env
CREAMBUFFET_SERVER_PORT=7000
CREAMBUFFET_SERVER_MAX_CLIENTS=32
```

And `/opt/creambuffet/compose.yaml`:

```yaml
services:
  server:
    image: ghcr.io/<github-owner>/creambuffet-server:production
    container_name: creambuffet-server
    env_file:
      - .env
    ports:
      - "${CREAMBUFFET_SERVER_PORT:-7000}:${CREAMBUFFET_SERVER_PORT:-7000}/udp"
    restart: unless-stopped
```

Client builds must point to the VPS public IP or domain:

```ini
[server]
host="game.example.com"
port=7000
```

## CI/CD

The repository includes two GitHub Actions workflows:

- `CI`: builds the Docker image, smoke-tests server boot with
  `CREAMBUFFET_SERVER_EXIT_AFTER_MS`, and publishes GHCR tags on `main`.
- `CD`: after a successful `CI` run on a `main` push, or after manual dispatch,
  SSHs into the VPS, runs `docker compose pull`, and restarts the service.

Required CD secrets:

```text
VPS_HOST
VPS_USER
VPS_PORT
VPS_SSH_KEY
```

If the GHCR package is private, the VPS Docker installation must be logged in to
`ghcr.io` with a token that can read the package.
