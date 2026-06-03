extends RefCounted


func apply_player_death(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	var player_state: Dictionary = match_state.players[peer_id]
	if Time.get_ticks_msec() < int(player_state.get("hazard_rearm_at_ms", 0)):
		return match_state._error("death_rejected", "Hazard respawn is waiting for rearm.")

	if not target_id.is_empty():
		var object_state: Dictionary = match_state._get_required_object(target_id, ["hazard", "fall_reset"], "player_death")
		if not bool(object_state.get("ok", false)):
			return object_state
		var object_data: Dictionary = object_state["object"]
		var object_kind := String(object_data.get("kind", ""))
		if object_kind == "fall_reset" and not match_state.can_player_interact_with_trigger(peer_id, target_id):
			return match_state._error("death_rejected", "Player is not inside the hazard trigger.")

	if not bool(player_state.get("alive", true)):
		return match_state._error("world_action_rejected", "Player is already dead.")

	player_state["alive"] = false
	player_state["at_goal"] = false
	player_state["goal_target_id"] = ""
	match_state.players[peer_id] = player_state
	match_state.players_at_goal.erase(peer_id)
	match_state._sync_goal_object_states()
	match_state.register_hazard_death()

	var events: Array[Dictionary] = []
	events.append(match_state._event("player_died", "player_death", peer_id, target_id))
	player_state["alive"] = true
	player_state["hazard_rearm_at_ms"] = Time.get_ticks_msec() + match_state.HAZARD_RESPAWN_REARM_MS
	match_state.players[peer_id] = player_state
	events.append(match_state._event("player_respawned", "player_death", peer_id, target_id))
	return match_state._ok(events)
