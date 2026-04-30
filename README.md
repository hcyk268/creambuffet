## Requirements

- Git
- Godot 4.6 or newer 
- Docker and Docker Compose for running the server in a container


## Project Layout

```text
client/   Godot game client project
server/   Godot headless multiplayer server project
```


## Environment

Create a local environment file from the example:

```bash
cp .env.example .env
```

Default values:

```env
CREAMBUFFET_SERVER_PORT=7000
CREAMBUFFET_SERVER_MAX_CLIENTS=32
```


## Run Server With Docker

Build and run the server:

```bash
docker compose up --build
```

Run in the background:

```bash
docker compose up -d --build
```

Stop the server:

```bash
docker compose down
```

Show logs:

```bash
docker compose logs -f server
```

Manual Docker commands are also supported:

```bash
docker build -t creambuffet-server .
docker run --rm --env-file .env -p 7000:7000/udp --name creambuffet-server creambuffet-server
```

## VPS Deployment

On a Linux VPS:

```bash
git clone <repo-url>
cd creambuffet
cp .env.example .env
docker compose up -d --build
```

Open the server UDP port in the VPS firewall and any cloud firewall/security group:

```bash
sudo ufw allow 7000/udp
```

Client builds must connect to the VPS public IP or domain. Update:

```text
client/config/client_network.cfg
```

Example:

```ini
[server]
host="game.example.com"
port=7000
```

## Network Config

The server defaults to UDP port `7000`.

Server environment variables:

- `CREAMBUFFET_SERVER_PORT`
- `CREAMBUFFET_SERVER_MAX_CLIENTS`
- `CREAMBUFFET_SERVER_EXIT_AFTER_MS` for smoke tests

Client config:

```text
client/config/client_network.cfg
```

For LAN testing, set the client host to the LAN IP of the machine running the server.
