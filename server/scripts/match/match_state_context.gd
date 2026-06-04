extends RefCounted
class_name MatchStateContext

var match_state
var map_id := ""
var current_level := 0
var current_level_id := ""
var level_definition: Dictionary = {}
var HAZARD_RESPAWN_REARM_MS := 0
var OXYGEN_RESPAWN_REARM_MS := 0


func _init(source_match_state) -> void:
	match_state = source_match_state
	map_id = match_state.map_id
	current_level = match_state.current_level
	current_level_id = match_state.current_level_id
	level_definition = match_state.level_definition
	HAZARD_RESPAWN_REARM_MS = match_state.HAZARD_RESPAWN_REARM_MS
	OXYGEN_RESPAWN_REARM_MS = match_state.OXYGEN_RESPAWN_REARM_MS


func has_player(peer_id: int) -> bool:
	return match_state.has_player(peer_id)


func is_player_alive(peer_id: int) -> bool:
	return match_state.is_player_alive(peer_id)


func get_player_state(peer_id: int) -> Dictionary:
	return match_state.get_player_state(peer_id)


func get_player_runtime(peer_id: int) -> Dictionary:
	return match_state.get_player_runtime(peer_id)


func set_player_runtime(peer_id: int, player_state: Dictionary) -> void:
	match_state.set_player_state(peer_id, player_state)


func patch_player_runtime(peer_id: int, updates: Dictionary) -> Dictionary:
	return match_state.patch_player_state(peer_id, updates)


func player_ids() -> Array[int]:
	return match_state.player_ids()


func set_player_alive(peer_id: int, alive: bool) -> Dictionary:
	return match_state.set_player_alive(peer_id, alive)


func set_player_goal(peer_id: int, target_id: String) -> Dictionary:
	return match_state.set_player_goal(peer_id, target_id)


func clear_player_goal(peer_id: int) -> Dictionary:
	return match_state.clear_player_goal(peer_id)


func player_key_count(peer_id: int) -> int:
	return match_state.player_key_count(peer_id)


func add_player_keys(peer_id: int, amount: int) -> Dictionary:
	return match_state.add_player_keys(peer_id, amount)


func consume_player_keys(peer_id: int, amount: int) -> Dictionary:
	return match_state.consume_player_keys(peer_id, amount)


func set_player_oxygen(peer_id: int, oxygen: float) -> Dictionary:
	return match_state.set_player_oxygen(peer_id, oxygen)


func set_player_max_oxygen(peer_id: int, max_oxygen: float) -> Dictionary:
	return match_state.set_player_max_oxygen(peer_id, max_oxygen)


func can_player_interact_with_trigger(peer_id: int, target_id: String) -> bool:
	return match_state.can_player_interact_with_trigger(peer_id, target_id)


func did_player_cross_trigger_since_last_update(peer_id: int, target_id: String) -> bool:
	return match_state.did_player_cross_trigger_since_last_update(peer_id, target_id)


func can_player_exit_trigger(peer_id: int, target_id: String) -> bool:
	return match_state.can_player_exit_trigger(peer_id, target_id)


func can_player_observe_push_box(peer_id: int, target_id: String, observed_position: Dictionary = {}) -> bool:
	return match_state.can_player_observe_push_box(peer_id, target_id, observed_position)


func compute_button_pressed(target_id: String) -> bool:
	return match_state.compute_button_pressed(target_id)


func register_hazard_death() -> int:
	return match_state.register_hazard_death()


func pushable_control_snapshot() -> Array[Dictionary]:
	return match_state.pushable_control_snapshot()


func failure_state_snapshot(now_ms: int = Time.get_ticks_msec()) -> Dictionary:
	return match_state.failure_state_snapshot(now_ms)


func require_object(target_id: String, allowed_kinds: Array, action: String) -> Dictionary:
	return match_state.require_object(target_id, allowed_kinds, action)


func object_ids() -> Array[String]:
	return match_state.object_ids()


func get_object_data(target_id: String) -> Dictionary:
	return match_state.get_object_data(target_id)


func set_object_data(target_id: String, object_data: Dictionary) -> void:
	match_state.set_object_data(target_id, object_data)


func get_object_state(target_id: String) -> Dictionary:
	return match_state.get_object_state(target_id)


func set_object_state(target_id: String, state: Dictionary) -> Dictionary:
	return match_state.set_object_state(target_id, state)


func patch_object_state(target_id: String, updates: Dictionary) -> Dictionary:
	return match_state.patch_object_state(target_id, updates)


func sync_goal_object_states() -> void:
	match_state.sync_goal_object_states()


func players_inside_goal(target_id: String) -> Array:
	return match_state.players_inside_goal(target_id)


func event(kind: String, request_action: String, peer_id: int, target_id: String = "", extra: Dictionary = {}) -> Dictionary:
	return match_state.event(kind, request_action, peer_id, target_id, extra)


func ok(events: Array[Dictionary]) -> Dictionary:
	return match_state.ok(events)


func error(code: String, message: String) -> Dictionary:
	return match_state.error(code, message)
