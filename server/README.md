# CreamBuffet Server

Initial dedicated server scaffold for the CreamBuffet online game.

## Current scope

- Headless Godot server project
- ENet transport with JSON packets
- Lobby flow:
  - welcome
  - list public rooms
  - create room
  - join room by room id
  - leave room
  - disconnect cleanup
- Match flow:
  - host starts a room match
  - room level changes are broadcast to all players
  - player transforms/animations are relayed inside the room
  - key, door, and lightweight push-box state events are relayed inside the room

## Project layout

- `project.godot`: Godot project entrypoint
- `scenes/server_main.tscn`: root scene for the headless server
- `scripts/server_main.gd`: boot, networking, packet routing
- `scripts/network/protocol.gd`: packet validation and encoding
- `scripts/lobby/player_session.gd`: connected peer metadata
- `scripts/lobby/room.gd`: room state
- `scripts/lobby/room_manager.gd`: room/session registry

## Run locally

From the repo root:

```powershell
..\godot.exe --headless --path .\server
```

Optional environment variables:

- `CREAMBUFFET_SERVER_PORT`
- `CREAMBUFFET_SERVER_MAX_CLIENTS`
- `CREAMBUFFET_SERVER_EXIT_AFTER_MS`

Example smoke test that exits after 2 seconds:

```powershell
$env:CREAMBUFFET_SERVER_EXIT_AFTER_MS='2000'
..\godot.exe --headless --path .\server
```

## Run with Docker

From the repo root:

```powershell
Copy-Item .env.example .env
docker compose up --build
```

Manual Docker commands:

```powershell
docker build -t creambuffet-server .
docker run --rm --env-file .env -p 7000:7000/udp --name creambuffet-server creambuffet-server
```

The Docker image is Linux-based and supports `amd64` and `arm64`. Use Docker Desktop Linux containers for Windows development, and Docker Engine on Ubuntu/Linux VPS for deployment.

The runtime image uses Debian slim, runs as a non-root `godot` user, and keeps only the Godot binary plus the server project.

## Packet format

The server uses reliable ENet packets containing UTF-8 JSON:

```json
{
  "type": "create_room",
  "request_id": "req-1",
  "payload": {
    "player_name": "Host",
    "visibility": "public",
    "max_players": 4,
    "world_count": 2,
    "randomized": false
  }
}
```

## Supported client message types

- `hello`
- `ping`
- `list_rooms`
- `create_room`
- `join_room`
- `leave_room`
- `start_match`
- `player_state`
- `level_changed`
- `level_complete`
- `world_event`

## Supported server message types

- `welcome`
- `pong`
- `room_list`
- `room_created`
- `room_joined`
- `room_left`
- `room_updated`
- `match_started`
- `player_state`
- `level_changed`
- `level_complete`
- `world_event`
- `error`

## Next implementation steps

1. Move gameplay authority into the server:
   - player spawn and peer ownership
   - level selection and progression
   - key and door state
   - push box physics replication
   - death and respawn
2. Add snapshot/input reconciliation for in-level simulation.
3. Add dedicated integration tests for two clients in one room.
