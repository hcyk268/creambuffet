extends RefCounted


func apply_enter(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	return _apply_goal(match_state, peer_id, target_id, true)


func apply_exit(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	return _apply_goal(match_state, peer_id, target_id, false)


func _apply_goal(match_state, peer_id: int, target_id: String, inside: bool) -> Dictionary:
	var object_state: Dictionary = match_state._get_required_object(target_id, ["goal"], "goal")
	if not bool(object_state.get("ok", false)):
		return object_state
	if not match_state.is_player_alive(peer_id):
		return match_state._error("goal_blocked", "Dead players cannot enter or exit the goal.")
	if inside and not match_state.can_player_interact_with_trigger(peer_id, target_id):
		return match_state._error("goal_blocked", "Player must overlap the goal trigger before entering it.")
	if not inside and not match_state.can_player_exit_trigger(peer_id, target_id):
		return match_state._error("goal_blocked", "Player must leave the goal trigger before exiting it.")

	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})
	var player_state: Dictionary = match_state.players[peer_id]
	var previous_inside := bool(player_state.get("at_goal", false))
	if previous_inside == inside:
		return match_state._error("world_action_rejected", "Goal occupancy did not change.")

	player_state["at_goal"] = inside
	player_state["goal_target_id"] = target_id if inside else ""
	match_state.players[peer_id] = player_state

	if inside:
		match_state.players_at_goal[peer_id] = true
	else:
		match_state.players_at_goal.erase(peer_id)

	state["players_inside"] = match_state._players_inside_goal(target_id)
	object_data["state"] = state
	match_state.objects[target_id] = object_data

	var event_kind := "goal_entered" if inside else "goal_exited"
	var action := "goal_enter" if inside else "goal_exit"
	var events: Array[Dictionary] = []
	events.append(match_state._event(event_kind, action, peer_id, target_id, {"state": state.duplicate(true)}))
	return match_state._ok(events)
