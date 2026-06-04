# Catalog Authoring Guide

This project treats the gameplay catalog as the main authoring surface for
online maps and levels:

- `client/data/game_catalog.json`
- `server/data/game_catalog.json`

Keep both files identical.

Run the catalog guardrail before testing a changed catalog:

```bash
godot --headless --script tests/integration/validate_catalogs.gd
godot --headless --path client --script res://tests/validate_sync_ids.gd
```

The check compares the client/server JSON files and validates common authoring
mistakes: missing `scene_path`, missing object `kind`, object kinds without an
enabled ruleset, invalid link endpoints or operations, invalid completion-rule
targets, and actions without a `server_handler`. The client-side sync validator
instantiates each online level scene and fails when a catalog object that
should sync has no matching `sync_id`, when a network-relevant node is missing
`sync_id`, or when duplicate `sync_id` values exist in a level scene.

Shared gameplay-catalog contract logic now has one canonical mirrored helper:

- `client/scripts/catalog/catalog_contract.gd`
- `server/scripts/catalog/catalog_contract.gd`

Put shared action/ruleset/object-kind validation helpers there. Keep
`GameCatalog` focused on catalog loading, resolution, and side-specific helpers
such as UI metadata. `tests/integration/validate_catalogs.gd` drift-checks the mirrored
helper pair, and `tests/integration/test_catalog_contract.gd` runs deterministic logic
checks for it.

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

Oxygen example for water levels:

```json
"maps": {
  "water": {
    "map_id": "water",
    "player_state_defaults": {
      "max_oxygen": 10,
      "oxygen": 10
    }
  }
},
"levels": {
  "water_03": {
    "level_id": "water_03",
    "map_id": "water",
    "player_state_overrides": {
      "max_oxygen": 6,
      "oxygen": 6
    }
  }
}
```

With this setup, `water_03` starts each player with a smaller oxygen tank than
the other water levels.

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
4. Ensure every network-relevant node has a `sync_id` matching the catalog
   `target_id`.
5. Run both validation commands before playtesting.
6. Only use `extra_rulesets` or `removed_rulesets` when the level differs from
   the map defaults.

To add a new gameplay mechanic later:

1. Add a new ruleset and mechanic definition in the catalog.
2. Add the corresponding server mechanic handler.
3. Enable it through `default_rulesets` or `extra_rulesets`.

## Authoring Checklist

Use this checklist whenever a PR adds a new ruleset, object kind, action,
event kind, or scene-backed network object:

1. Add any new ids to the mirrored `client/scripts/catalog/game_ids.gd` and `server/scripts/catalog/game_ids.gd` helpers.
2. If the change affects shared validation or normalization rules, update the mirrored `catalog_contract.gd` helpers and keep `tests/integration/validate_catalogs.gd` drift checks green.
3. If the new object is network-relevant in a level scene, give it a `sync_id` and make sure the catalog `target_id` matches.
4. If the new object kind or ruleset needs server behavior, add the `server_handler` entry and the corresponding registry/mechanic wiring.
5. Add or update deterministic headless coverage for new validation logic, event shapes, or mechanic behavior before relying on manual playtesting.
6. Re-run the catalog guardrails and client sync validator before opening the level in the editor:

```bash
godot --headless --script tests/integration/validate_catalogs.gd
godot --headless --path client --script res://tests/validate_sync_ids.gd
```

7. Update this checklist if the project introduces a new authoring surface or a new class of runtime contract that level designers must keep in sync.

## Current Example

The `beginner` map already uses this structure:

- shared rules live in `default_rulesets`
- platform, box, and button levels only opt into their extra rules
- levels that only use the map defaults do not need a local ruleset array
