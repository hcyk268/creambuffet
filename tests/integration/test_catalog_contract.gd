extends SceneTree

const CatalogContract = preload("res://server/scripts/catalog/catalog_contract.gd")


func _init() -> void:
	var mechanic_definitions := {
		"button_platform_v1": {
			"object_kinds": ["button", "pressure_plate"],
			"actions": {
				"button_state": {
					"aliases": ["button_press"],
					"object_kinds": ["button", "pressure_plate"],
					"required_payload": [
						{
							"field": "pressed",
							"type": "bool",
						}
					],
					"server_handler": "button_platform.button_state",
				}
			},
		},
		"goal_all_v1": {
			"object_kinds": ["goal"],
			"actions": {},
		},
	}

	var level := {
		"rulesets": ["button_platform_v1", "goal_all_v1"],
		"objects": {
			"button_a": {"kind": "button"},
			"goal_a": {"kind": "goal"},
		},
	}
	var object_data := {"kind": "button"}

	var failures: Array[String] = []

	var allowed_actions := CatalogContract.get_allowed_actions(level, object_data, mechanic_definitions)
	if not allowed_actions.has("button_state") or not allowed_actions.has("button_press"):
		failures.append("CatalogContract.get_allowed_actions() did not expose canonical action and alias.")

	var normalized_alias := CatalogContract.normalize_world_action("button_press", mechanic_definitions)
	if normalized_alias != "button_state":
		failures.append("CatalogContract.normalize_world_action() did not resolve aliases to the canonical action.")

	var valid_action := CatalogContract.validate_world_action(
		"beginner_01",
		"button_a",
		"button_press",
		level,
		object_data,
		mechanic_definitions,
		{"pressed": true}
	)
	if not bool(valid_action.get("ok", false)):
		failures.append("CatalogContract.validate_world_action() rejected a valid aliased action.")
	elif String(valid_action.get("action", "")) != "button_state":
		failures.append("CatalogContract.validate_world_action() did not normalize the returned action.")

	var invalid_action := CatalogContract.validate_world_action(
		"beginner_01",
		"button_a",
		"button_state",
		level,
		object_data,
		mechanic_definitions,
		{}
	)
	if bool(invalid_action.get("ok", false)) or String(invalid_action.get("code", "")) != "missing_required_payload":
		failures.append("CatalogContract.validate_world_action() did not enforce required payload fields.")

	var allowed_rulesets := {
		"button_platform_v1": true,
		"goal_all_v1": true,
	}
	var known_rulesets := allowed_rulesets.duplicate(true)
	var valid_level := CatalogContract.validate_level_rulesets(
		"beginner",
		"beginner",
		"beginner_01",
		level,
		allowed_rulesets,
		known_rulesets,
		mechanic_definitions
	)
	if not bool(valid_level.get("ok", false)):
		failures.append("CatalogContract.validate_level_rulesets() rejected a valid resolved level.")

	var bad_level := {
		"rulesets": ["goal_all_v1"],
		"objects": {
			"button_a": {"kind": "button"},
		},
	}
	var invalid_level := CatalogContract.validate_level_rulesets(
		"beginner",
		"beginner",
		"beginner_02",
		bad_level,
		allowed_rulesets,
		known_rulesets,
		mechanic_definitions
	)
	if bool(invalid_level.get("ok", false)) or String(invalid_level.get("code", "")) != "object_ruleset_not_enabled":
		failures.append("CatalogContract.validate_level_rulesets() did not catch objects without an enabled ruleset.")

	if failures.is_empty():
		print("Catalog contract tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)
