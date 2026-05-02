extends RefCounted
class_name MatchState

var current_level := 0
var players: Dictionary = {}
var key_collected := false
var door_opened := false
var players_at_goal: Dictionary = {}


func _init(peer_ids: Array[int] = [], start_level: int = 0) -> void:
	current_level = max(start_level, 0)
	_register_players(peer_ids)
	_reset_level_flags()


func has_player(peer_id: int) -> bool:
	return players.has(peer_id)


func collect_key(peer_id: int) -> bool:
	if not has_player(peer_id):
		return false

	if key_collected:
		return false

	key_collected = true
	return true


func open_door(peer_id: int) -> bool:
	if not has_player(peer_id):
		return false

	if door_opened:
		return false

	if not key_collected:
		return false

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
	if not door_opened:
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
		players[peer_id] = player_state


func add_player(peer_id: int) -> void:
	if has_player(peer_id):
		return

	players[peer_id] = {
		"alive": true,
		"at_goal": false,
	}


func remove_player(peer_id: int) -> void:
	if not has_player(peer_id):
		return

	players.erase(peer_id)
	players_at_goal.erase(peer_id)


func snapshot() -> Dictionary:
	return {
		"current_level": current_level,
		"key_collected": key_collected,
		"door_opened": door_opened,
		"players": players.duplicate(true),
		"players_at_goal": players_at_goal.keys(),
		"can_complete_level": can_complete_level(),
	}


func _register_players(peer_ids: Array[int]) -> void:
	players.clear()
	players_at_goal.clear()
	for peer_id in peer_ids:
		players[int(peer_id)] = {
			"alive": true,
			"at_goal": false,
		}


func _reset_level_flags() -> void:
	key_collected = false
	door_opened = false
	players_at_goal.clear()
