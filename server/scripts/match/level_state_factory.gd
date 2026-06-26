extends RefCounted
class_name LevelStateFactory

const GameIds = preload("res://scripts/catalog/game_ids.gd")


static func build_objects(level_definition: Dictionary) -> Dictionary:
	var objects: Dictionary = {}
	var raw_objects: Variant = level_definition.get("objects", {})
	if typeof(raw_objects) != TYPE_DICTIONARY:
		return objects

	var object_defs: Dictionary = raw_objects
	for raw_target_id in object_defs.keys():
		var target_id := String(raw_target_id)
		var object_def: Dictionary = Dictionary(object_defs[target_id]).duplicate(true)
		var state := _object_initial_state(object_def)
		object_def["target_id"] = target_id
		object_def["state"] = state
		objects[target_id] = object_def

	return objects


static func new_player_state(level_definition: Dictionary) -> Dictionary:
	var player_state := {
		"alive": true,
		"at_goal": false,
		"goal_target_id": "",
		"hazard_rearm_at_ms": 0,
		"key_count": 0,
		"max_oxygen": 10.0,
		"oxygen": 10.0,
		"oxygen_depleted_rearm_at_ms": 0,
		"previous_position": {},
		"position": {},
		"velocity": {},
		"updated_at_ms": 0,
	}
	return _merge_state_defaults(player_state, level_definition.get("player_state_defaults", {}))


static func _object_initial_state(object_def: Dictionary) -> Dictionary:
	var state: Dictionary = {}
	var raw_state: Variant = object_def.get("state", {})
	if typeof(raw_state) == TYPE_DICTIONARY:
		state = raw_state.duplicate(true)

	if String(object_def.get("kind", "")) == GameIds.OBJECT_KIND_PUSH_BOX and not state.has("position"):
		var transform: Dictionary = object_def.get("transform", {})
		var position_raw: Variant = transform.get("position", {})
		if typeof(position_raw) == TYPE_DICTIONARY:
			state["position"] = Dictionary(position_raw).duplicate(true)

	_seed_object_state(object_def, state)
	return state


static func _seed_object_state(object_def: Dictionary, state: Dictionary) -> void:
	var kind := String(object_def.get("kind", ""))
	match kind:
		GameIds.OBJECT_KIND_TEAM_RESPAWN_BUDGET:
			if not state.has("max"):
				state["max"] = int(object_def.get("max_respawns", 3))
			if not state.has("used"):
				state["used"] = 0
			if not state.has("failed"):
				state["failed"] = false
		GameIds.OBJECT_KIND_OXYGEN_TANK, GameIds.OBJECT_KIND_OXYGEN_STATION:
			if not state.has("remaining_uses"):
				state["remaining_uses"] = _default_oxygen_uses(object_def)
			if not state.has("claimed_peer_ids"):
				state["claimed_peer_ids"] = []
			if not state.has("collected"):
				state["collected"] = int(state.get("remaining_uses", 0)) <= 0
		GameIds.OBJECT_KIND_WATER_JET_NOZZLE, GameIds.OBJECT_KIND_WATER_JET:
			if not state.has("active"):
				state["active"] = bool(object_def.get("active", true))
		GameIds.OBJECT_KIND_MOVING_PLATFORM:
			if bool(state.get("active", false)) and not state.has("active_started_at_ms"):
				var now_ms := Time.get_ticks_msec()
				state["active_started_at_ms"] = now_ms
				state["updated_at_ms"] = now_ms
		GameIds.OBJECT_KIND_EXTENDABLE_BARRIER, GameIds.OBJECT_KIND_WATER_BARRIER, GameIds.OBJECT_KIND_BARRIER:
			if not state.has("open"):
				state["open"] = bool(object_def.get("open", false))
			if not state.has("active"):
				state["active"] = not bool(state.get("open", false))


static func _default_oxygen_uses(object_def: Dictionary) -> int:
	var oxygen_data: Dictionary = {}
	var raw_oxygen: Variant = object_def.get("oxygen", {})
	if typeof(raw_oxygen) == TYPE_DICTIONARY:
		oxygen_data = raw_oxygen
	return maxi(int(oxygen_data.get("uses", object_def.get("uses", 1))), 1)


static func _merge_state_defaults(base: Dictionary, defaults_raw: Variant) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	if typeof(defaults_raw) != TYPE_DICTIONARY:
		return result

	var defaults: Dictionary = defaults_raw
	for raw_key in defaults.keys():
		var key := String(raw_key)
		var value = defaults[raw_key]
		if typeof(value) == TYPE_DICTIONARY and typeof(result.get(key, null)) == TYPE_DICTIONARY:
			result[key] = _merge_state_defaults(Dictionary(result[key]), value)
		else:
			result[key] = value
	return result
