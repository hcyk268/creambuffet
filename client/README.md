# CreamBuffet Client

This is the playable Godot 4.6 client for CreamBuffet. It contains the offline
game, the online menus, the ENet client autoload, and the online level scenes
that sync with the dedicated server.

## Entry Points

- Main scene: `scenes/start_menu.tscn`
- Offline game scene: `scenes/offline/offline_game.tscn`
- Online menu scene: `scenes/online_menu.tscn`
- Online match scene: `scenes/online/online_game.tscn`
- Network autoload: `scripts/network/network_client.gd`

Run from the repository root:

```bash
godot --path client
```

Or open `client/project.godot` in the Godot editor.

## Controls

Input actions are defined in `project.godot`:

- Move left/right: arrow keys
- Jump: `Z` or `Space`
- Dash: `C`
- Attack action: `X`
- Pause/back: Godot `ui_cancel`

## Online Server Config

Client network settings live in:

```text
config/client_network.cfg
```

Default local configuration:

```ini
[server]
host="127.0.0.1"
port=7000

[client]
display_name=""

[dev]
allow_env_overrides=true
```

When `allow_env_overrides=true`, these environment variables override the file:

```text
CREAMBUFFET_SERVER_HOST
CREAMBUFFET_SERVER_PORT
CREAMBUFFET_PLAYER_NAME
```

For local online testing, start the server first and keep `host="127.0.0.1"`.
For LAN or VPS testing, set `host` to the server machine IP address or domain.

## Online Flow

The client connects through the `NetworkClient` autoload. Public rooms, private
room joining, room creation, lobby updates, and match startup are all routed
through that autoload.

During an online match:

- Local player state is sent every `0.05` seconds with unreliable ordered ENet
  packets.
- Remote player state is displayed from server relays.
- World interactions are sent as `world_action_request` packets.
- The server validates catalog targets and broadcasts `world_event`,
  `pushable_control`, `room_updated`, and `level_transition` messages.
- Client-driven `level_changed` and `level_complete` are not part of the active
  online flow; the server advances levels from completion rules.

## Catalog And Sync IDs

Online gameplay data lives in:

```text
data/game_catalog.json
```

The server has its own copy at `server/data/game_catalog.json`. Keep both files
identical for online play.

Network-relevant level nodes need a `sync_id` that matches a catalog
`target_id`. This currently applies to keys, doors, goals, hazards or fall
reset triggers, push boxes, buttons, pressure plates, and linked moving
platforms.

The online game warns at runtime when a catalog target is missing from the
loaded scene or a network-relevant node has no `sync_id`.

## Project Layout

```text
assets/                 Sprites, fonts, and backgrounds.
config/                 Client network configuration.
data/game_catalog.json  Online maps, levels, objects, rulesets, and actions.
prefabs/                Shared gameplay prefabs.
scenes/                 Menus, offline scenes, online scenes, and levels.
scripts/                Player, UI, menu, offline, online, catalog, and network code.
Terrain/                Tile terrain scene.
```

## Export Notes

If a custom export preset uses non-resource filters, include:

```text
data/game_catalog.json
config/client_network.cfg
```

Online builds must ship with the intended server host and port in
`config/client_network.cfg`, unless the target platform supplies environment
overrides.
