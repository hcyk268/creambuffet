extends RefCounted

const GameIds = preload("res://scripts/catalog/game_ids.gd")

func apply_automatic_fall_reset(match_state, peer_id: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not match_state.has_player(peer_id):
		return events
	if not match_state.is_player_alive(peer_id):
		return events

	var player_state: Dictionary = match_state.get_player_runtime(peer_id)
	if Time.get_ticks_msec() < int(player_state.get("hazard_rearm_at_ms", 0)):
		return events

	for target_id in match_state.object_ids():
		var object_data: Dictionary = match_state.get_object_data(target_id)
		if object_data.is_empty():
			continue
		var object_kind := String(object_data.get("kind", ""))
		if not GameIds.is_hazard_kind(object_kind):
			continue
		if object_kind == GameIds.OBJECT_KIND_HAZARD and not bool(object_data.get("automatic", true)):
			continue
		if object_kind == GameIds.OBJECT_KIND_CHAINSAW:
			continue
		if not match_state.can_player_interact_with_trigger(peer_id, target_id) and not match_state.did_player_cross_trigger_since_last_update(peer_id, target_id):
			continue

		var result := apply_player_death(match_state, peer_id, target_id, {})
		if not bool(result.get("ok", false)):
			return events

		var raw_events: Variant = result.get("events", [])
		if typeof(raw_events) == TYPE_ARRAY:
			events.assign(raw_events)
		return events

	return events


func apply_player_death(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	var player_state: Dictionary = match_state.get_player_runtime(peer_id)
	if Time.get_ticks_msec() < int(player_state.get("hazard_rearm_at_ms", 0)):
		return match_state.error("death_rejected", "Hazard respawn is waiting for rearm.")

	if not target_id.is_empty():
		var object_state: Dictionary = match_state.require_object(target_id, GameIds.HAZARD_KINDS, GameIds.ACTION_PLAYER_DEATH)
		if not bool(object_state.get("ok", false)):
			return object_state
		var object_data: Dictionary = object_state["object"]
		var object_kind := String(object_data.get("kind", ""))
		if object_kind == GameIds.OBJECT_KIND_FALL_RESET and not match_state.can_player_interact_with_trigger(peer_id, target_id):
			return match_state.error("death_rejected", "Player is not inside the hazard trigger.")

	if not bool(player_state.get("alive", true)):
		return match_state.error("world_action_rejected", "Player is already dead.")

	player_state = match_state.clear_player_goal(peer_id)
	player_state["alive"] = false
	match_state.set_player_runtime(peer_id, player_state)
	match_state.sync_goal_object_states()
	var hearts_remaining: int = match_state.register_hazard_death()
	var has_death_limit := hearts_remaining >= 0

	var events: Array[Dictionary] = []
	events.append(match_state.event(GameIds.EVENT_PLAYER_DIED, GameIds.ACTION_PLAYER_DEATH, peer_id, target_id, {
		"eliminated": has_death_limit and hearts_remaining <= 0,
	}))

	if not has_death_limit or hearts_remaining > 0:
		player_state["alive"] = true
		player_state["hazard_rearm_at_ms"] = Time.get_ticks_msec() + match_state.HAZARD_RESPAWN_REARM_MS
		match_state.set_player_runtime(peer_id, player_state)
		events.append(match_state.event(GameIds.EVENT_PLAYER_RESPAWNED, GameIds.ACTION_PLAYER_DEATH, peer_id, target_id))

	return match_state.ok(events)
