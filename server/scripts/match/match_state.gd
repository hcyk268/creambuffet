extends RefCounted
class_name MatchState

var current_level := 0
var players: Dictionary = {}
var key_collected := false
var door_opened := false
var goal_requires_opened_door := false
var players_at_goal: Dictionary = {}
var push_intents: Dictionary = {}


func _init(peer_ids: Array[int] = [], start_level: int = 0) -> void:
	current_level = max(start_level, 0)
	_register_players(peer_ids)
	_reset_level_flags()


func has_player(peer_id: int) -> bool:
	return players.has(peer_id)


func is_player_alive(peer_id: int) -> bool:
	if not has_player(peer_id):
		return false

	var player_state: Dictionary = players[peer_id]
	return bool(player_state.get("alive", true))


func collect_key(peer_id: int) -> bool:
	if not has_player(peer_id):
		return false

	if key_collected:
		return false

	var player_state: Dictionary = players[peer_id]
	key_collected = true
	player_state["key_count"] = int(player_state.get("key_count", 0)) + 1
	players[peer_id] = player_state
	return true


func open_door(peer_id: int) -> bool:
	if not has_player(peer_id):
		return false

	if door_opened:
		return false

	var player_state: Dictionary = players[peer_id]
	if int(player_state.get("key_count", 0)) <= 0:
		return false

	player_state["key_count"] = int(player_state.get("key_count", 0)) - 1
	players[peer_id] = player_state
	door_opened = true
	return true


func set_goal(peer_id: int, inside: bool) -> bool:
	if not has_player(peer_id):
		return false

	var player_state: Dictionary = players[peer_id]
	var next_inside := bool(inside)
	var previous_inside := bool(player_state.get("at_goal", false))
	if previous_inside == next_inside:
		return false

	player_state["at_goal"] = next_inside
	players[peer_id] = player_state

	if next_inside:
		players_at_goal[peer_id] = true
	else:
		players_at_goal.erase(peer_id)

	return true


func configure_level_requirements(has_key: bool, has_door: bool) -> void:
	goal_requires_opened_door = goal_requires_opened_door or (has_key and has_door)


func respawn_player(peer_id: int) -> bool:
	if not has_player(peer_id):
		return false

	var player_state: Dictionary = players[peer_id]
	player_state["alive"] = true
	player_state["at_goal"] = false
	players[peer_id] = player_state
	players_at_goal.erase(peer_id)
	return true


func set_player_alive(peer_id: int, alive: bool) -> bool:
	if not has_player(peer_id):
		return false

	var player_state: Dictionary = players[peer_id]
	var next_alive := bool(alive)
	var previous_alive := bool(player_state.get("alive", true))
	if previous_alive == next_alive:
		return false

	player_state["alive"] = next_alive
	if not next_alive:
		player_state["at_goal"] = false
		players_at_goal.erase(peer_id)
	players[peer_id] = player_state
	return true


func can_complete_level() -> bool:
	if goal_requires_opened_door and not door_opened:
		return false

	if players.is_empty():
		return false

	for raw_peer_id in players.keys():
		var peer_id := int(raw_peer_id)
		var player_state: Dictionary = players[peer_id]
		if not bool(player_state.get("at_goal", false)):
			return false

	return true


func set_level(level_index: int) -> void:
	current_level = max(level_index, 0)
	_reset_level_flags()
	for raw_peer_id in players.keys():
		var peer_id := int(raw_peer_id)
		var player_state: Dictionary = players[peer_id]
		player_state["alive"] = true
		player_state["at_goal"] = false
		player_state["key_count"] = 0
		players[peer_id] = player_state


func add_player(peer_id: int) -> void:
	if has_player(peer_id):
		return

	players[peer_id] = {
		"alive": true,
		"at_goal": false,
		"key_count": 0,
	}


func remove_player(peer_id: int) -> void:
	if not has_player(peer_id):
		return

	players.erase(peer_id)
	players_at_goal.erase(peer_id)
	push_intents.erase(peer_id)


func snapshot() -> Dictionary:
	return {
		"current_level": current_level,
		"key_collected": key_collected,
		"door_opened": door_opened,
		"goal_requires_opened_door": goal_requires_opened_door,
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
			var node_name := String(intent.get("node_name", "")).strip_edges()
			if node_name.is_empty():
				continue

			next_peer_intents[node_name] = {
				"node_name": node_name,
				"direction": clampf(float(intent.get("direction", 0.0)), -1.0, 1.0),
				"strength": clampf(float(intent.get("strength", 1.0)), 0.0, 1.0),
				"updated_at_ms": Time.get_ticks_msec(),
			}

	push_intents[peer_id] = next_peer_intents
	return pushable_control_snapshot()


func pushable_control_snapshot() -> Array[Dictionary]:
	var controls_by_name: Dictionary = {}
	var now_ms := Time.get_ticks_msec()

	for raw_peer_id in push_intents.keys():
		var peer_id := int(raw_peer_id)
		if not has_player(peer_id):
			continue

		var peer_intents_raw: Variant = push_intents.get(peer_id, {})
		if typeof(peer_intents_raw) != TYPE_DICTIONARY:
			continue

		var peer_intents: Dictionary = peer_intents_raw
		for raw_name in peer_intents.keys():
			var node_name := String(raw_name)
			var intent_raw: Variant = peer_intents.get(node_name, {})
			if typeof(intent_raw) != TYPE_DICTIONARY:
				continue

			var intent: Dictionary = intent_raw
			if now_ms - int(intent.get("updated_at_ms", 0)) > 160:
				continue

			var drive_x := float(controls_by_name.get(node_name, 0.0))
			drive_x += float(intent.get("direction", 0.0)) * float(intent.get("strength", 1.0))
			controls_by_name[node_name] = clampf(drive_x, -1.0, 1.0)

	var states: Array[Dictionary] = []
	var names := controls_by_name.keys()
	names.sort()

	for raw_name in names:
		var node_name := String(raw_name)
		states.append({
			"node_name": node_name,
			"drive_x": float(controls_by_name.get(node_name, 0.0)),
		})

	return states


func _register_players(peer_ids: Array[int]) -> void:
	players.clear()
	players_at_goal.clear()
	for peer_id in peer_ids:
		players[int(peer_id)] = {
			"alive": true,
			"at_goal": false,
			"key_count": 0,
		}


func _reset_level_flags() -> void:
	key_collected = false
	door_opened = false
	goal_requires_opened_door = false
	players_at_goal.clear()
	push_intents.clear()
