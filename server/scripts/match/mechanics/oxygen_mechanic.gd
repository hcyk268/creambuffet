extends RefCounted


func apply_collect(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	var object_state: Dictionary = match_state._get_required_object(target_id, ["oxygen_tank", "oxygen_station"], "collect")
	if not bool(object_state.get("ok", false)):
		return object_state
	if not match_state.can_player_interact_with_trigger(peer_id, target_id):
		return match_state._error("interaction_out_of_range", "Player must overlap the oxygen trigger to collect it.")

	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})
	var claimed_peer_ids := _int_array(state.get("claimed_peer_ids", []))
	if claimed_peer_ids.has(peer_id):
		return match_state._error("oxygen_already_claimed", "Player already claimed this oxygen pickup.")

	var remaining_uses := int(state.get("remaining_uses", _default_uses(object_data)))
	if remaining_uses <= 0:
		return match_state._error("oxygen_empty", "Oxygen pickup has no uses left.")

	remaining_uses -= 1
	claimed_peer_ids.append(peer_id)
	state["remaining_uses"] = remaining_uses
	state["claimed_peer_ids"] = claimed_peer_ids
	state["collected"] = remaining_uses <= 0
	state["last_collector_peer_id"] = peer_id
	object_data["state"] = state
	match_state.objects[target_id] = object_data

	var oxygen_amount := _oxygen_amount(object_data)
	var player_state: Dictionary = match_state.players[peer_id]
	var max_oxygen := float(player_state.get("max_oxygen", object_data.get("max_oxygen", 10.0)))
	var current_oxygen := float(player_state.get("oxygen", max_oxygen))
	player_state["max_oxygen"] = max_oxygen
	player_state["oxygen"] = clampf(current_oxygen + oxygen_amount, 0.0, max_oxygen)
	player_state["oxygen_depleted_rearm_at_ms"] = 0
	match_state.players[peer_id] = player_state

	var events: Array[Dictionary] = []
	events.append(match_state._event("oxygen_collected", "collect", peer_id, target_id, {
		"oxygen_amount": oxygen_amount,
		"remaining_uses": remaining_uses,
		"state": state.duplicate(true),
		"player_state": player_state.duplicate(true),
	}))
	return match_state._ok(events)


func apply_oxygen_depleted(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	var object_state: Dictionary = match_state._get_required_object(target_id, ["team_respawn_budget"], "oxygen_depleted")
	if not bool(object_state.get("ok", false)):
		return object_state

	var player_state: Dictionary = match_state.players[peer_id]
	if Time.get_ticks_msec() < int(player_state.get("oxygen_depleted_rearm_at_ms", 0)):
		return match_state._error("oxygen_depleted_rearming", "Oxygen depleted event is waiting for rearm.")
	if not bool(player_state.get("alive", true)):
		return match_state._error("world_action_rejected", "Player is already dead.")

	var budget: Dictionary = object_state["object"]
	var state: Dictionary = budget.get("state", {})
	var max_respawns := int(state.get("max", budget.get("max_respawns", 3)))
	var used_respawns := int(state.get("used", 0))

	player_state["alive"] = false
	player_state["at_goal"] = false
	player_state["goal_target_id"] = ""
	player_state["oxygen"] = 0.0
	match_state.players[peer_id] = player_state
	match_state.players_at_goal.erase(peer_id)
	match_state._sync_goal_object_states()

	var events: Array[Dictionary] = []
	events.append(match_state._event("player_died", "oxygen_depleted", peer_id, target_id, {
		"reason": "oxygen_depleted",
	}))

	if used_respawns >= max_respawns:
		state["failed"] = true
		state["failed_by_peer_id"] = peer_id
		state["used"] = used_respawns
		state["max"] = max_respawns
		budget["state"] = state
		match_state.objects[target_id] = budget
		events.append(match_state._event("team_respawn_budget_changed", "oxygen_depleted", peer_id, target_id, {
			"state": state.duplicate(true),
		}))
		events.append(match_state._event("level_failed", "oxygen_depleted", peer_id, target_id, {
			"reason": "team_respawn_budget_exhausted",
			"state": state.duplicate(true),
		}))
		return match_state._ok(events)

	used_respawns += 1
	state["used"] = used_respawns
	state["max"] = max_respawns
	state["failed"] = false
	state["last_respawn_peer_id"] = peer_id
	budget["state"] = state
	match_state.objects[target_id] = budget

	player_state["alive"] = true
	player_state["oxygen"] = float(player_state.get("max_oxygen", 10.0))
	player_state["oxygen_depleted_rearm_at_ms"] = Time.get_ticks_msec() + match_state.OXYGEN_RESPAWN_REARM_MS
	match_state.players[peer_id] = player_state

	events.append(match_state._event("team_respawn_budget_changed", "oxygen_depleted", peer_id, target_id, {
		"state": state.duplicate(true),
	}))
	events.append(match_state._event("player_respawned", "oxygen_depleted", peer_id, target_id, {
		"reason": "oxygen_depleted",
		"player_state": player_state.duplicate(true),
	}))
	return match_state._ok(events)


func _default_uses(object_data: Dictionary) -> int:
	var oxygen_data: Dictionary = {}
	var raw_oxygen: Variant = object_data.get("oxygen", {})
	if typeof(raw_oxygen) == TYPE_DICTIONARY:
		oxygen_data = raw_oxygen
	return maxi(int(oxygen_data.get("uses", object_data.get("uses", 1))), 1)


func _oxygen_amount(object_data: Dictionary) -> float:
	var oxygen_data: Dictionary = {}
	var raw_oxygen: Variant = object_data.get("oxygen", {})
	if typeof(raw_oxygen) == TYPE_DICTIONARY:
		oxygen_data = raw_oxygen
	return maxf(float(oxygen_data.get("amount", object_data.get("oxygen_amount", 5.0))), 0.0)


func _int_array(raw_values: Variant) -> Array[int]:
	var result: Array[int] = []
	if typeof(raw_values) != TYPE_ARRAY:
		return result

	for raw_value in raw_values:
		var value := int(raw_value)
		if not result.has(value):
			result.append(value)
	return result
