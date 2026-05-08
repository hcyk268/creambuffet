# Catalog Authoring Guide

This project treats the gameplay catalog as the main authoring surface for
online maps and levels:

- `client/data/game_catalog.json`
- `server/data/game_catalog.json`

Keep both files identical.

## Mental Model

Author gameplay data in three layers:

1. `map`: the ordered level list and shared defaults.
2. `level`: scene path, objects, completion, and only the differences from the
   map.
3. `ruleset`: reusable mechanics such as key/door, hazards, buttons, and moving
   platforms.

At runtime, `GameCatalog.get_level()` resolves map defaults and level overrides
into one final level definition.

## Rulesets

Use map defaults for rules that most levels in the map share:

```json
"maps": {
  "beginner": {
    "map_id": "beginner",
    "title": "Beginner",
    "default_rulesets": [
      "key_door_v1",
      "goal_all_v1",
      "hazard_respawn_v1"
    ],
    "allowed_rulesets": [
      "key_door_v1",
      "goal_all_v1",
      "hazard_respawn_v1",
      "push_box_v1",
      "button_platform_v1",
      "moving_platform_v1"
    ],
    "levels": ["beginner_01", "beginner_02"]
  }
}
```

Add level-specific mechanics with `extra_rulesets`:

```json
"levels": {
  "beginner_02": {
    "level_id": "beginner_02",
    "map_id": "beginner",
    "extra_rulesets": [
      "push_box_v1",
      "button_platform_v1",
      "moving_platform_v1"
    ]
  }
}
```

Remove a shared map ruleset for one level with `removed_rulesets`:

```json
"levels": {
  "stealth_01": {
    "level_id": "stealth_01",
    "map_id": "advanced",
    "removed_rulesets": ["hazard_respawn_v1"]
  }
}
```

## Player State Defaults

Maps and levels can now seed additional per-player runtime state without
hardcoding level IDs in `MatchState`.

Shared player defaults for a map:

```json
"maps": {
  "combat": {
    "map_id": "combat",
    "title": "Combat",
    "player_state_defaults": {
      "hp": 3,
      "max_hp": 3
    }
  }
}
```

Override that state for a specific level:

```json
"levels": {
  "combat_03": {
    "level_id": "combat_03",
    "map_id": "combat",
    "player_state_overrides": {
      "hp": 5,
      "max_hp": 5,
      "double_jump": true
    }
  }
}
```

Remove a shared player-state field from one level:

```json
"levels": {
  "timed_escape": {
    "level_id": "timed_escape",
    "map_id": "combat",
    "removed_player_state_fields": ["double_jump"]
  }
}
```

Current behavior:

- The server resolves `player_state_defaults` into the level definition.
- `MatchState` uses that data when creating each player runtime state.
- This seeds runtime state for future mechanics such as HP, timers, stamina, or
  level-specific abilities.

Important:

- Seeding `hp` in data does not automatically create HP gameplay by itself.
- A mechanic still needs to read and update that state.
- The benefit is that the state shape is now data-driven and level-aware.

## Recommended Workflow

To add a new map:

1. Create a new entry in `maps`.
2. Set `default_rulesets` for the mechanics most levels will share.
3. Add the ordered `levels` list.

To add a new level:

1. Create the scene.
2. Add the level definition in `levels`.
3. Add objects, completion rules, and links.
4. Only use `extra_rulesets` or `removed_rulesets` when the level differs from
   the map defaults.

To add a new gameplay mechanic later:

1. Add a new ruleset and mechanic definition in the catalog.
2. Add the corresponding server mechanic handler.
3. Enable it through `default_rulesets` or `extra_rulesets`.

## Current Example

The `beginner` map already uses this structure:

- shared rules live in `default_rulesets`
- platform, box, and button levels only opt into their extra rules
- levels that only use the map defaults do not need a local ruleset array
