# CreamBuffet Client

## Network config

Client server settings live in `config/client_network.cfg`.

```ini
[server]
host="127.0.0.1"
port=7000

[client]
display_name=""

[dev]
allow_env_overrides=true
```

For local development, keep `host="127.0.0.1"`.

For deployment, change `host` to the public server IP or domain, for example:

```ini
[server]
host="game.example.com"
port=7000
```

When `allow_env_overrides=true`, these environment variables can override the file:

- `CREAMBUFFET_SERVER_HOST`
- `CREAMBUFFET_SERVER_PORT`
- `CREAMBUFFET_PLAYER_NAME`
