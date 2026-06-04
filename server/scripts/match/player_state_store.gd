extends RefCounted
class_name PlayerStateStore

var _players: Dictionary


func _init(players: Dictionary) -> void:
	_players = players


func clear() -> void:
	_players.clear()


func has(peer_id: int) -> bool:
	return _players.has(peer_id)


func ids() -> Array[int]:
	var result: Array[int] = []
	for raw_peer_id in _players.keys():
		result.append(int(raw_peer_id))
	return result


func get_state(peer_id: int) -> Dictionary:
	if not has(peer_id):
		return {}
	return Dictionary(_players[peer_id]).duplicate(true)


func set_state(peer_id: int, player_state: Dictionary) -> void:
	_players[peer_id] = player_state.duplicate(true)


func patch_state(peer_id: int, updates: Dictionary) -> Dictionary:
	var next_state := get_state(peer_id)
	if next_state.is_empty():
		return {}

	for raw_key in updates.keys():
		next_state[String(raw_key)] = updates[raw_key]
	set_state(peer_id, next_state)
	return next_state


func alive(peer_id: int) -> bool:
	return bool(get_state(peer_id).get("alive", false))


func set_alive(peer_id: int, alive_value: bool) -> Dictionary:
	return patch_state(peer_id, {"alive": alive_value})


func key_count(peer_id: int) -> int:
	return int(get_state(peer_id).get("key_count", 0))


func set_key_count(peer_id: int, next_key_count: int) -> Dictionary:
	return patch_state(peer_id, {"key_count": maxi(next_key_count, 0)})


func add_key_count(peer_id: int, amount: int) -> Dictionary:
	return set_key_count(peer_id, key_count(peer_id) + amount)


func consume_key_count(peer_id: int, amount: int) -> Dictionary:
	return set_key_count(peer_id, maxi(key_count(peer_id) - amount, 0))


func set_goal(peer_id: int, target_id: String) -> Dictionary:
	return patch_state(peer_id, {
		"at_goal": true,
		"goal_target_id": target_id,
	})


func clear_goal(peer_id: int) -> Dictionary:
	return patch_state(peer_id, {
		"at_goal": false,
		"goal_target_id": "",
	})


func set_oxygen(peer_id: int, oxygen: float) -> Dictionary:
	return patch_state(peer_id, {"oxygen": oxygen})


func set_max_oxygen(peer_id: int, max_oxygen: float) -> Dictionary:
	return patch_state(peer_id, {"max_oxygen": max_oxygen})
