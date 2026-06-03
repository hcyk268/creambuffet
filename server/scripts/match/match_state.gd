extends RefCounted
class_name MatchState

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const KeyDoorMechanic = preload("res://scripts/match/mechanics/key_door_mechanic.gd")
const GoalMechanic = preload("res://scripts/match/mechanics/goal_mechanic.gd")
const HazardRespawnMechanic = preload("res://scripts/match/mechanics/hazard_respawn_mechanic.gd")
const PushBoxMechanic = preload("res://scripts/match/mechanics/push_box_mechanic.gd")
const ButtonPlatformMechanic = preload("res://scripts/match/mechanics/button_platform_mechanic.gd")

const PUSH_BOX_OBSERVE_PADDING := 24.0
const PUSH_BOX_SYNC_EPSILON := 0.5
const HAZARD_RESPAWN_REARM_MS := 250

var map_id := GameCatalog.DEFAULT_MAP_ID
var current_level := 0
var current_level_id := ""
var level_definition: Dictionary = {}
var objects: Dictionary = {}
var players: Dictionary = {}
var players_at_goal: Dictionary = {}
var push_intents: Dictionary = {}
var _mechanics: Dictionary = {}
var _mechanic_handlers: Dictionary = {}
var level_started_at_ms := 0
var failure_state: Dictionary = {}
var _level_reset_pending := false


func _init(peer_ids: Array[int] = [], start_level: int = 0, start_level_id: String = "", initial_map_id: String = GameCatalog.DEFAULT_MAP_ID) -> void:
	map_id = GameCatalog.normalize_map_id(initial_map_id)
	current_level = maxi(start_level, 0)
	current_level_id = start_level_id if not start_level_id.is_empty() else GameCatalog.get_level_id_by_index(map_id, current_level)
	_register_mechanic_handlers()
	_register_players(peer_ids)
	_reset_level_state()


func has_player(peer_id: int) -> bool:
	return players.has(peer_id)


func is_player_alive(peer_id: int) -> bool:
	if not has_player(peer_id):
		return false

	var player_state: Dictionary = players[peer_id]
	return bool(player_state.get("alive", true))


func add_player(peer_id: int) -> void:
	if has_player(peer_id):
		return

	players[peer_id] = _new_player_state()


func remove_player(peer_id: int) -> void:
	if not has_player(peer_id):
		return

	players.erase(peer_id)
	players_at_goal.erase(peer_id)
	push_intents.erase(peer_id)
	_sync_goal_object_states()


func get_player_state(peer_id: int) -> Dictionary:
	if not has_player(peer_id):
		return {}

	return Dictionary(players[peer_id]).duplicate(true)


func set_level(level_index: int, level_id: String = "") -> void:
	current_level = maxi(level_index, 0)
	current_level_id = level_id if not level_id.is_empty() else GameCatalog.get_level_id_by_index(map_id, current_level)
	_reset_level_state()
	for raw_peer_id in players.keys():
		var peer_id := int(raw_peer_id)
		players[peer_id] = _new_player_state()


func update_player_runtime(peer_id: int, payload: Dictionary) -> void:
	if not has_player(peer_id):
		return

	var player_state: Dictionary = players[peer_id]
	var previous_position: Dictionary = {}
	var previous_position_raw = player_state.get("position", {})
	if typeof(previous_position_raw) == TYPE_DICTIONARY:
		previous_position = Dictionary(previous_position_raw).duplicate(true)
	player_state["previous_position"] = previous_position
	player_state["position"] = _packet_vector(payload.get("position", player_state.get("position", {})))
	player_state["velocity"] = _packet_vector(payload.get("velocity", player_state.get("velocity", {})))
	player_state["updated_at_ms"] = Time.get_ticks_msec()
	players[peer_id] = player_state


func apply_automatic_fall_reset(peer_id: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not has_player(peer_id):
		return events
	if not is_player_alive(peer_id):
		return events

	var player_state: Dictionary = players[peer_id]
	if Time.get_ticks_msec() < int(player_state.get("hazard_rearm_at_ms", 0)):
		return events

	var hazard_handler: Callable = _mechanic_handlers.get("hazard_respawn.player_death", Callable())
	if not hazard_handler.is_valid():
		return events

	for raw_target_id in objects.keys():
		var target_id := String(raw_target_id)
		var object_data := _get_object(target_id)
		if object_data.is_empty():
			continue
		var object_kind := String(object_data.get("kind", ""))
		if object_kind != "fall_reset" and object_kind != "hazard":
			continue
		if object_kind == "hazard" and not bool(object_data.get("automatic", true)):
			continue
		if not can_player_interact_with_trigger(peer_id, target_id) and not did_player_cross_trigger_since_last_update(peer_id, target_id):
			continue

		var result = hazard_handler.call(self, peer_id, target_id, {})
		if typeof(result) != TYPE_DICTIONARY or not bool(result.get("ok", false)):
			return events

		var hazard_events_raw = result.get("events", [])
		if typeof(hazard_events_raw) == TYPE_ARRAY:
			events.assign(hazard_events_raw)
		return events

	return events


func apply_push_box_observations(peer_id: int, raw_states) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not has_player(peer_id) or typeof(raw_states) != TYPE_ARRAY:
		return events

	for raw_state in raw_states:
		if typeof(raw_state) != TYPE_DICTIONARY:
			continue

		var state: Dictionary = Dictionary(raw_state).duplicate(true)
		var target_id := String(state.get("target_id", state.get("node_name", ""))).strip_edges()
		if target_id.is_empty():
			continue

		var object_state := _get_object(target_id)
		if object_state.is_empty() or String(object_state.get("kind", "")) != "push_box":
			continue

		var raw_position = state.get("position", {})
		if typeof(raw_position) != TYPE_DICTIONARY:
			continue

		var observed_position := _packet_vector(raw_position)
		var object_data: Dictionary = object_state
		var object_runtime_state: Dictionary = object_data.get("state", {})
		var previous_position: Dictionary = {}
		var raw_previous_position: Variant = object_runtime_state.get("position", {})
		if typeof(raw_previous_position) == TYPE_DICTIONARY:
			previous_position = Dictionary(raw_previous_position).duplicate(true)
		if not _positions_match(previous_position, observed_position, PUSH_BOX_SYNC_EPSILON):
			object_runtime_state["position"] = observed_position
			object_runtime_state["updated_by_peer_id"] = peer_id
			object_data["state"] = object_runtime_state
			objects[target_id] = object_data

			events.append(_event("push_box_state", "push_box_state", peer_id, target_id, {
				"position": observed_position.duplicate(true),
			}))
		var button_platform = _mechanics.get("button_platform", null)
		if button_platform != null and button_platform.has_method("refresh_button_states"):
			events.append_array(button_platform.refresh_button_states(self, peer_id))

	return events


func apply_world_action(peer_id: int, action: String, target_id: String, payload: Dictionary) -> Dictionary:
	if not has_player(peer_id):
		return _error("unknown_peer", "Peer is not part of this match.")

	var validation := GameCatalog.validate_world_action(current_level_id, target_id, action, payload)
	if not bool(validation.get("ok", false)):
		return validation

	var handler_id := String(validation.get("server_handler", ""))
	var handler: Callable = _mechanic_handlers.get(handler_id, Callable())
	if handler_id.is_empty() or not handler.is_valid():
		return _error("missing_world_action_handler", "No server handler registered for action: %s" % action)

	var result = handler.call(self, peer_id, target_id, payload)
	if typeof(result) != TYPE_DICTIONARY:
		return _error("bad_world_action_handler", "World action handler did not return a dictionary: %s" % handler_id)

	return result


func can_complete_level() -> bool:
	var raw_rules: Variant = level_definition.get("completion_rules", [])
	if typeof(raw_rules) != TYPE_ARRAY:
		return _all_players_at_goal()

	var rules: Array = raw_rules
	if rules.is_empty():
		return _all_players_at_goal()

	for raw_rule in rules:
		if typeof(raw_rule) != TYPE_DICTIONARY:
			return false
		if not _evaluate_completion_rule(raw_rule):
			return false

	return true


func snapshot() -> Dictionary:
	var completion_rules: Array = []
	var raw_completion_rules: Variant = level_definition.get("completion_rules", [])
	if typeof(raw_completion_rules) == TYPE_ARRAY:
		completion_rules = raw_completion_rules.duplicate(true)

	return {
		"map_id": map_id,
		"current_level": current_level,
		"current_level_id": current_level_id,
		"level_definition": level_definition.duplicate(true),
		"completion_rules": completion_rules,
		"failure_state": failure_state_snapshot(),
		"objects": objects.duplicate(true),
		"key_collected": _any_object_state("key", "collected", true),
		"door_opened": _any_object_state("door", "opened", true) or _any_object_state("exit_door", "opened", true),
		"goal_requires_opened_door": _has_door_completion_rule(),
		"pushables": pushable_control_snapshot(),
		"players": players.duplicate(true),
		"players_at_goal": players_at_goal.keys(),
		"can_complete_level": can_complete_level(),
	}


func apply_push_intents(peer_id: int, raw_intents) -> Array[Dictionary]:
	if not has_player(peer_id):
		return pushable_control_snapshot()

	var next_peer_intents: Dictionary = {}
	if typeof(raw_intents) == TYPE_ARRAY:
		for raw_intent in raw_intents:
			if typeof(raw_intent) != TYPE_DICTIONARY:
				continue

			var intent: Dictionary = Dictionary(raw_intent).duplicate(true)
			var target_id := String(intent.get("target_id", intent.get("node_name", ""))).strip_edges()
			if target_id.is_empty():
				continue

			var object_state := _get_object(target_id)
			if object_state.is_empty():
				continue
			if not object_state.is_empty() and String(object_state.get("kind", "")) != "push_box":
				continue
			if not can_player_observe_push_box(peer_id, target_id):
				continue

			next_peer_intents[target_id] = {
				"target_id": target_id,
				"node_name": String(intent.get("node_name", target_id)),
				"direction": clampf(float(intent.get("direction", 0.0)), -1.0, 1.0),
				"strength": clampf(float(intent.get("strength", 1.0)), 0.0, 1.0),
				"updated_at_ms": Time.get_ticks_msec(),
			}

	push_intents[peer_id] = next_peer_intents
	return pushable_control_snapshot()


func pushable_control_snapshot() -> Array[Dictionary]:
	var controls_by_target: Dictionary = {}
	var now_ms := Time.get_ticks_msec()

	for raw_peer_id in push_intents.keys():
		var peer_id := int(raw_peer_id)
		if not has_player(peer_id):
			continue

		var peer_intents_raw: Variant = push_intents.get(peer_id, {})
		if typeof(peer_intents_raw) != TYPE_DICTIONARY:
			continue

		var peer_intents: Dictionary = peer_intents_raw
		for raw_target in peer_intents.keys():
			var target_id := String(raw_target)
			var intent_raw: Variant = peer_intents.get(target_id, {})
			if typeof(intent_raw) != TYPE_DICTIONARY:
				continue

			var intent: Dictionary = intent_raw
			if now_ms - int(intent.get("updated_at_ms", 0)) > 160:
				continue

			var drive_x := float(controls_by_target.get(target_id, 0.0))
			drive_x += float(intent.get("direction", 0.0)) * float(intent.get("strength", 1.0))
			controls_by_target[target_id] = clampf(drive_x, -1.0, 1.0)

	var states: Array[Dictionary] = []
	var targets := controls_by_target.keys()
	targets.sort()

	for raw_target in targets:
		var target_id := String(raw_target)
		states.append({
			"target_id": target_id,
			"node_name": target_id,
			"drive_x": float(controls_by_target.get(target_id, 0.0)),
		})

	return states


func can_player_interact_with_trigger(peer_id: int, target_id: String) -> bool:
	return _player_shape_overlaps_target_shape(peer_id, target_id, "trigger")


func can_player_exit_trigger(peer_id: int, target_id: String) -> bool:
	return not can_player_interact_with_trigger(peer_id, target_id)


func can_player_observe_push_box(peer_id: int, target_id: String, observed_position: Dictionary = {}) -> bool:
	if not has_player(peer_id):
		return false
	if not is_player_alive(peer_id):
		return false

	var object_data := _get_object(target_id)
	if object_data.is_empty() or String(object_data.get("kind", "")) != "push_box":
		return false

	var body_rect := _shape_rect_for_object(target_id, "body", observed_position)
	if body_rect.size == Vector2.ZERO:
		return false

	var player_rect := _player_bounding_rect(peer_id)
	if player_rect.size == Vector2.ZERO:
		return false

	return player_rect.grow(PUSH_BOX_OBSERVE_PADDING).intersects(body_rect)


func compute_button_pressed(target_id: String) -> bool:
	var object_data := _get_object(target_id)
	if object_data.is_empty():
		return false

	for raw_peer_id in players.keys():
		var peer_id := int(raw_peer_id)
		if not is_player_alive(peer_id):
			continue
		if can_player_interact_with_trigger(peer_id, target_id):
			return true

	for raw_target_id in objects.keys():
		var candidate_id := String(raw_target_id)
		var candidate := _get_object(candidate_id)
		if candidate.is_empty() or String(candidate.get("kind", "")) != "push_box":
			continue
		if _object_shape_overlaps_target_shape(candidate_id, "body", target_id, "trigger"):
			return true

	return false


func _evaluate_completion_rule(rule: Dictionary) -> bool:
	match String(rule.get("type", "")):
		"all_players_at_goal":
			return _all_players_at_goal(String(rule.get("target_id", "")))
		"object_state_equals":
			var target_id := String(rule.get("target_id", ""))
			var object_state := _get_object(target_id)
			if object_state.is_empty():
				return false
			var state: Dictionary = object_state.get("state", {})
			return state.get(String(rule.get("field", "")), null) == rule.get("value", null)
		"exit_door_open":
			return _any_object_state("door", "opened", true) or _any_object_state("exit_door", "opened", true)
		_:
			return false


func _all_players_at_goal(target_id: String = "") -> bool:
	if players.is_empty():
		return false

	for raw_peer_id in players.keys():
		var peer_id := int(raw_peer_id)
		var player_state: Dictionary = players[peer_id]
		if not bool(player_state.get("at_goal", false)):
			return false
		if not target_id.is_empty() and String(player_state.get("goal_target_id", "")) != target_id:
			return false

	return true


func _players_inside_goal(target_id: String) -> Array:
	var result := []
	for raw_peer_id in players.keys():
		var peer_id := int(raw_peer_id)
		var player_state: Dictionary = players[peer_id]
		if bool(player_state.get("at_goal", false)) and String(player_state.get("goal_target_id", "")) == target_id:
			result.append(peer_id)
	return result


func _register_mechanic_handlers() -> void:
	var key_door := KeyDoorMechanic.new()
	var goal := GoalMechanic.new()
	var hazard_respawn := HazardRespawnMechanic.new()
	var push_box := PushBoxMechanic.new()
	var button_platform := ButtonPlatformMechanic.new()

	_mechanics = {
		"key_door": key_door,
		"goal": goal,
		"hazard_respawn": hazard_respawn,
		"push_box": push_box,
		"button_platform": button_platform,
	}

	_mechanic_handlers = {
		"key_door.collect": Callable(key_door, "apply_collect"),
		"key_door.open": Callable(key_door, "apply_open"),
		"goal.enter": Callable(goal, "apply_enter"),
		"goal.exit": Callable(goal, "apply_exit"),
		"hazard_respawn.player_death": Callable(hazard_respawn, "apply_player_death"),
		"push_box.state": Callable(push_box, "apply_state"),
		"button_platform.button_state": Callable(button_platform, "apply_button_state"),
	}


func _sync_goal_object_states() -> void:
	for raw_target_id in objects.keys():
		var target_id := String(raw_target_id)
		var object_data: Dictionary = objects[target_id]
		if String(object_data.get("kind", "")) != "goal":
			continue

		var state: Dictionary = object_data.get("state", {})
		state["players_inside"] = _players_inside_goal(target_id)
		object_data["state"] = state
		objects[target_id] = object_data


func _register_players(peer_ids: Array[int]) -> void:
	players.clear()
	players_at_goal.clear()
	for peer_id in peer_ids:
		players[int(peer_id)] = _new_player_state()


func _reset_level_state() -> void:
	level_definition = GameCatalog.get_level(current_level_id)
	objects.clear()
	players_at_goal.clear()
	push_intents.clear()
	_configure_failure_state()

	var raw_objects: Variant = level_definition.get("objects", {})
	if typeof(raw_objects) != TYPE_DICTIONARY:
		return

	var object_defs: Dictionary = raw_objects
	for raw_target_id in object_defs.keys():
		var target_id := String(raw_target_id)
		var object_def: Dictionary = Dictionary(object_defs[target_id]).duplicate(true)
		var state: Dictionary = {}
		var raw_state: Variant = object_def.get("state", {})
		if typeof(raw_state) == TYPE_DICTIONARY:
			state = raw_state.duplicate(true)
		if String(object_def.get("kind", "")) == "push_box" and not state.has("position"):
			var transform: Dictionary = object_def.get("transform", {})
			var position_raw: Variant = transform.get("position", {})
			if typeof(position_raw) == TYPE_DICTIONARY:
				state["position"] = Dictionary(position_raw).duplicate(true)
		object_def["target_id"] = target_id
		object_def["state"] = state
		objects[target_id] = object_def


func _new_player_state() -> Dictionary:
	var player_state := {
		"alive": true,
		"at_goal": false,
		"goal_target_id": "",
		"hazard_rearm_at_ms": 0,
		"key_count": 0,
		"previous_position": {},
		"position": {},
		"velocity": {},
		"updated_at_ms": 0,
	}
	return _merge_state_defaults(player_state, level_definition.get("player_state_defaults", {}))


func _merge_state_defaults(base: Dictionary, defaults_raw: Variant) -> Dictionary:
	var result := base.duplicate(true)
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


func _get_required_object(target_id: String, allowed_kinds: Array, action: String) -> Dictionary:
	if target_id.strip_edges().is_empty():
		return _error("missing_target_id", "%s requires a target_id." % action)

	var object_data := _get_object(target_id)
	if object_data.is_empty():
		return _error("unknown_target", "Target does not exist in the current level: %s" % target_id)

	var kind := String(object_data.get("kind", ""))
	if not allowed_kinds.has(kind):
		return _error("wrong_target_kind", "Action %s cannot target object kind %s." % [action, kind])

	return {
		"ok": true,
		"object": object_data,
	}


func register_hazard_death() -> int:
	var death_limit: Dictionary = failure_state.get("death_limit", {})
	if death_limit.is_empty() or not bool(death_limit.get("enabled", false)):
		return -1

	var hearts_remaining := maxi(int(death_limit.get("hearts_remaining", 0)) - 1, 0)
	death_limit["hearts_remaining"] = hearts_remaining
	failure_state["death_limit"] = death_limit
	return hearts_remaining


func consume_level_failure(now_ms: int = Time.get_ticks_msec()) -> Dictionary:
	if _level_reset_pending:
		return {}

	var time_limit: Dictionary = failure_state.get("time_limit", {})
	if not time_limit.is_empty() and _failure_time_remaining_ms(now_ms) <= 0:
		_level_reset_pending = true
		return {
			"reason": "time_limit",
		}

	var death_limit: Dictionary = failure_state.get("death_limit", {})
	if not death_limit.is_empty() and int(death_limit.get("hearts_remaining", 0)) <= 0 and _all_players_dead():
		_level_reset_pending = true
		return {
			"reason": "death_limit",
		}

	return {}


func failure_state_snapshot(now_ms: int = Time.get_ticks_msec()) -> Dictionary:
	var snapshot := {
		"time_limit": {
			"enabled": false,
			"duration_ms": 0,
			"started_at_ms": level_started_at_ms,
			"remaining_ms": 0,
		},
		"death_limit": {
			"enabled": false,
			"hearts_max": 0,
			"hearts_remaining": 0,
			"shared": true,
		},
	}

	var time_limit: Dictionary = failure_state.get("time_limit", {})
	if not time_limit.is_empty():
		snapshot["time_limit"] = {
			"enabled": true,
			"duration_ms": int(time_limit.get("duration_ms", 0)),
			"started_at_ms": int(time_limit.get("started_at_ms", level_started_at_ms)),
			"remaining_ms": _failure_time_remaining_ms(now_ms),
		}

	var death_limit: Dictionary = failure_state.get("death_limit", {})
	if not death_limit.is_empty():
		snapshot["death_limit"] = {
			"enabled": true,
			"hearts_max": int(death_limit.get("hearts_max", 0)),
			"hearts_remaining": int(death_limit.get("hearts_remaining", 0)),
			"shared": bool(death_limit.get("shared", true)),
		}

	return snapshot


func _get_object(target_id: String) -> Dictionary:
	if not objects.has(target_id):
		return {}
	return Dictionary(objects[target_id]).duplicate(true)


func _configure_failure_state() -> void:
	level_started_at_ms = Time.get_ticks_msec()
	_level_reset_pending = false
	failure_state = {
		"time_limit": {},
		"death_limit": {},
	}

	var raw_failure_rules: Variant = level_definition.get("failure_rules", [])
	if typeof(raw_failure_rules) != TYPE_ARRAY:
		return

	for raw_rule in raw_failure_rules:
		if typeof(raw_rule) != TYPE_DICTIONARY:
			continue

		var rule: Dictionary = raw_rule
		match String(rule.get("type", "")):
			"time_limit":
				var seconds := maxf(float(rule.get("seconds", 0.0)), 0.0)
				if seconds <= 0.0:
					continue
				failure_state["time_limit"] = {
					"enabled": true,
					"duration_ms": int(round(seconds * 1000.0)),
					"started_at_ms": level_started_at_ms,
				}
			"death_limit":
				var hearts := maxi(int(rule.get("hearts", rule.get("max_deaths", 0))), 0)
				if hearts <= 0:
					continue
				failure_state["death_limit"] = {
					"enabled": true,
					"hearts_max": hearts,
					"hearts_remaining": hearts,
					"shared": bool(rule.get("shared", true)),
				}


func _all_players_dead() -> bool:
	if players.is_empty():
		return false

	for raw_peer_id in players.keys():
		var peer_id := int(raw_peer_id)
		if is_player_alive(peer_id):
			return false

	return true


func _failure_time_remaining_ms(now_ms: int) -> int:
	var time_limit: Dictionary = failure_state.get("time_limit", {})
	if time_limit.is_empty():
		return 0

	var duration_ms := int(time_limit.get("duration_ms", 0))
	var started_at_ms := int(time_limit.get("started_at_ms", level_started_at_ms))
	return maxi(duration_ms - (now_ms - started_at_ms), 0)


func _any_object_state(kind: String, field: String, expected) -> bool:
	for raw_object in objects.values():
		if typeof(raw_object) != TYPE_DICTIONARY:
			continue
		var object_data: Dictionary = raw_object
		if String(object_data.get("kind", "")) != kind:
			continue
		var state: Dictionary = object_data.get("state", {})
		if state.get(field, null) == expected:
			return true
	return false


func _has_door_completion_rule() -> bool:
	var raw_rules: Variant = level_definition.get("completion_rules", [])
	if typeof(raw_rules) != TYPE_ARRAY:
		return false

	for raw_rule in raw_rules:
		if typeof(raw_rule) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = raw_rule
		if String(rule.get("type", "")) == "object_state_equals" and String(rule.get("field", "")) == "opened":
			return true
	return false


func _player_shape_overlaps_target_shape(peer_id: int, target_id: String, target_shape_field: String) -> bool:
	var player_shape := _player_shape(peer_id)
	if player_shape.is_empty():
		return false

	var target_shape := _shape_for_object(target_id, target_shape_field)
	if target_shape.is_empty():
		return false

	return _shape_overlap(player_shape, target_shape)


func _object_shape_overlaps_target_shape(source_id: String, source_shape_field: String, target_id: String, target_shape_field: String) -> bool:
	var source_shape := _shape_for_object(source_id, source_shape_field)
	if source_shape.is_empty():
		return false

	var target_shape := _shape_for_object(target_id, target_shape_field)
	if target_shape.is_empty():
		return false

	return _shape_overlap(source_shape, target_shape)


func _player_shape(peer_id: int) -> Dictionary:
	var player_state := get_player_state(peer_id)
	if player_state.is_empty():
		return {}

	var raw_position: Variant = player_state.get("position", {})
	if typeof(raw_position) != TYPE_DICTIONARY:
		return {}

	var template := GameCatalog.get_player_template()
	var shape: Dictionary = template.get("shape", {})
	if shape.is_empty():
		return {}

	var base_position: Dictionary = raw_position
	var offset: Dictionary = shape.get("offset", {})
	return {
		"type": String(shape.get("type", "")),
		"center": _packet_vec(
			float(base_position.get("x", 0.0)) + float(offset.get("x", 0.0)),
			float(base_position.get("y", 0.0)) + float(offset.get("y", 0.0))
		),
		"radius": float(shape.get("radius", 0.0)),
	}


func _player_bounding_rect(peer_id: int) -> Rect2:
	var player_state := get_player_state(peer_id)
	if player_state.is_empty():
		return Rect2()
	return _player_bounding_rect_for_position(player_state.get("position", {}))


func did_player_cross_trigger_since_last_update(peer_id: int, target_id: String) -> bool:
	if not has_player(peer_id):
		return false

	var player_state := get_player_state(peer_id)
	if player_state.is_empty():
		return false

	var current_rect := _player_bounding_rect_for_position(player_state.get("position", {}))
	if current_rect.size == Vector2.ZERO:
		return false

	var previous_rect := _player_bounding_rect_for_position(player_state.get("previous_position", {}))
	if previous_rect.size == Vector2.ZERO:
		return false

	var trigger_shape := _shape_for_object(target_id, "trigger")
	if trigger_shape.is_empty():
		return false

	var trigger_rect := _shape_rect(trigger_shape).grow(float(trigger_shape.get("margin", 0.0)))
	return previous_rect.merge(current_rect).intersects(trigger_rect)


func _player_bounding_rect_for_position(raw_position: Variant) -> Rect2:
	var shape := _player_shape_for_position(raw_position)
	if shape.is_empty():
		return Rect2()

	if String(shape.get("type", "")) != "circle":
		return Rect2()

	var center: Dictionary = shape.get("center", {})
	var radius := float(shape.get("radius", 0.0))
	return Rect2(
		Vector2(float(center.get("x", 0.0)) - radius, float(center.get("y", 0.0)) - radius),
		Vector2(radius * 2.0, radius * 2.0)
	)


func _player_shape_for_position(raw_position: Variant) -> Dictionary:
	if typeof(raw_position) != TYPE_DICTIONARY:
		return {}

	var template := GameCatalog.get_player_template()
	var shape: Dictionary = template.get("shape", {})
	if shape.is_empty():
		return {}

	var base_position: Dictionary = Dictionary(raw_position).duplicate(true)
	var offset: Dictionary = Dictionary(shape.get("offset", {})).duplicate(true)
	return {
		"type": String(shape.get("type", "")),
		"center": _packet_vec(
			float(base_position.get("x", 0.0)) + float(offset.get("x", 0.0)),
			float(base_position.get("y", 0.0)) + float(offset.get("y", 0.0))
		),
		"radius": float(shape.get("radius", 0.0)),
	}


func _shape_for_object(target_id: String, shape_field: String) -> Dictionary:
	var object_data := _get_object(target_id)
	if object_data.is_empty():
		return {}

	var shape_data: Variant = object_data.get(shape_field, {})
	if typeof(shape_data) != TYPE_DICTIONARY:
		return {}

	var transform: Dictionary = object_data.get("transform", {})
	var base_position: Dictionary = transform.get("position", {})
	if shape_field == "body":
		var state: Dictionary = object_data.get("state", {})
		var state_position: Variant = state.get("position", null)
		if typeof(state_position) == TYPE_DICTIONARY:
			base_position = state_position

	if typeof(base_position) != TYPE_DICTIONARY:
		base_position = {}

	var offset: Dictionary = Dictionary(shape_data.get("offset", {})).duplicate(true)
	return {
		"type": String(shape_data.get("shape", "")),
		"center": _packet_vec(
			float(base_position.get("x", 0.0)) + float(offset.get("x", 0.0)),
			float(base_position.get("y", 0.0)) + float(offset.get("y", 0.0))
		),
		"size": Dictionary(shape_data.get("size", {})).duplicate(true),
		"radius": float(shape_data.get("radius", 0.0)),
		"margin": float(shape_data.get("margin", 0.0)),
	}


func _shape_overlap(first: Dictionary, second: Dictionary) -> bool:
	var first_type := String(first.get("type", ""))
	var second_type := String(second.get("type", ""))
	if first_type == "circle" and second_type == "rectangle":
		return _circle_intersects_rect(first, second)
	if first_type == "rectangle" and second_type == "rectangle":
		return _rectangle_intersects_rect(first, second)
	if first_type == "rectangle" and second_type == "circle":
		return _circle_intersects_rect(second, first)
	if first_type == "circle" and second_type == "circle":
		return _circle_intersects_circle(first, second)
	return false


func _circle_intersects_rect(circle_shape: Dictionary, rect_shape: Dictionary) -> bool:
	var center: Dictionary = circle_shape.get("center", {})
	var radius := float(circle_shape.get("radius", 0.0))
	var rect := _shape_rect(rect_shape)
	var margin := float(rect_shape.get("margin", 0.0))
	rect = rect.grow(margin)
	var circle_position := Vector2(float(center.get("x", 0.0)), float(center.get("y", 0.0)))
	var closest_x := clampf(circle_position.x, rect.position.x, rect.end.x)
	var closest_y := clampf(circle_position.y, rect.position.y, rect.end.y)
	return circle_position.distance_squared_to(Vector2(closest_x, closest_y)) <= radius * radius


func _rectangle_intersects_rect(first: Dictionary, second: Dictionary) -> bool:
	var first_rect := _shape_rect(first).grow(float(first.get("margin", 0.0)))
	var second_rect := _shape_rect(second).grow(float(second.get("margin", 0.0)))
	return first_rect.intersects(second_rect)


func _circle_intersects_circle(first: Dictionary, second: Dictionary) -> bool:
	var first_center: Dictionary = first.get("center", {})
	var second_center: Dictionary = second.get("center", {})
	var first_position := Vector2(float(first_center.get("x", 0.0)), float(first_center.get("y", 0.0)))
	var second_position := Vector2(float(second_center.get("x", 0.0)), float(second_center.get("y", 0.0)))
	var max_distance := float(first.get("radius", 0.0)) + float(second.get("radius", 0.0))
	return first_position.distance_squared_to(second_position) <= max_distance * max_distance


func _shape_rect(shape_data: Dictionary) -> Rect2:
	var size: Dictionary = shape_data.get("size", {})
	if typeof(size) != TYPE_DICTIONARY:
		return Rect2()
	var center: Dictionary = shape_data.get("center", {})
	var width := float(size.get("x", 0.0))
	var height := float(size.get("y", 0.0))
	return Rect2(
		Vector2(float(center.get("x", 0.0)) - (width * 0.5), float(center.get("y", 0.0)) - (height * 0.5)),
		Vector2(width, height)
	)


func _shape_rect_for_object(target_id: String, shape_field: String, override_position: Dictionary = {}) -> Rect2:
	var shape := _shape_for_object(target_id, shape_field)
	if shape.is_empty():
		return Rect2()
	if typeof(override_position) == TYPE_DICTIONARY and not override_position.is_empty():
		var object_data := _get_object(target_id)
		var shape_data: Dictionary = object_data.get(shape_field, {})
		var offset: Dictionary = Dictionary(shape_data.get("offset", {})).duplicate(true)
		shape["center"] = _packet_vec(
			float(override_position.get("x", 0.0)) + float(offset.get("x", 0.0)),
			float(override_position.get("y", 0.0)) + float(offset.get("y", 0.0))
		)
	return _shape_rect(shape)


func _packet_vector(raw_value) -> Dictionary:
	if typeof(raw_value) == TYPE_DICTIONARY:
		return {
			"x": float(Dictionary(raw_value).get("x", 0.0)),
			"y": float(Dictionary(raw_value).get("y", 0.0)),
		}
	if typeof(raw_value) == TYPE_ARRAY and raw_value.size() >= 2:
		return {
			"x": float(raw_value[0]),
			"y": float(raw_value[1]),
		}
	return {
		"x": 0.0,
		"y": 0.0,
	}


func _packet_vec(x: float, y: float) -> Dictionary:
	return {
		"x": x,
		"y": y,
	}


func _positions_match(first: Dictionary, second: Dictionary, epsilon: float) -> bool:
	if first.is_empty() or second.is_empty():
		return false

	var dx := float(first.get("x", 0.0)) - float(second.get("x", 0.0))
	var dy := float(first.get("y", 0.0)) - float(second.get("y", 0.0))
	return (dx * dx) + (dy * dy) <= epsilon * epsilon


func _event(kind: String, request_action: String, peer_id: int, target_id: String = "", extra: Dictionary = {}) -> Dictionary:
	var event := {
		"kind": kind,
		"request_action": request_action,
		"peer_id": peer_id,
		"level_index": current_level,
		"level_id": current_level_id,
	}
	if not target_id.is_empty():
		event["target_id"] = target_id
		event["sync_id"] = target_id

	for key in extra.keys():
		event[key] = extra[key]

	return event


func _ok(events: Array[Dictionary]) -> Dictionary:
	return {
		"ok": true,
		"events": events,
	}


func _error(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
	}
