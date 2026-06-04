extends RefCounted

const GameIds = preload("res://scripts/catalog/game_ids.gd")

func apply_enter(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	return _apply_goal(match_state, peer_id, target_id, true)


func apply_exit(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	return _apply_goal(match_state, peer_id, target_id, false)


func _apply_goal(match_state, peer_id: int, target_id: String, inside: bool) -> Dictionary:
	var goal_actions := [GameIds.ACTION_GOAL_ENTER, GameIds.ACTION_GOAL_EXIT]
	var object_state: Dictionary = match_state.require_object(target_id, [GameIds.OBJECT_KIND_GOAL], goal_actions[0] if inside else goal_actions[1])
	if not bool(object_state.get("ok", false)):
		return object_state
	if not match_state.is_player_alive(peer_id):
		return match_state.error("goal_blocked", "Dead players cannot enter or exit the goal.")
	if inside and not match_state.can_player_interact_with_trigger(peer_id, target_id):
		return match_state.error("goal_blocked", "Player must overlap the goal trigger before entering it.")
	if not inside and not match_state.can_player_exit_trigger(peer_id, target_id):
		return match_state.error("goal_blocked", "Player must leave the goal trigger before exiting it.")

	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})
	var player_state: Dictionary = match_state.get_player_runtime(peer_id)
	var previous_inside := bool(player_state.get("at_goal", false))
	if previous_inside == inside:
		return match_state.error("world_action_rejected", "Goal occupancy did not change.")

	if inside:
		match_state.set_player_goal(peer_id, target_id)
	else:
		match_state.clear_player_goal(peer_id)

	state["players_inside"] = match_state.players_inside_goal(target_id)
	object_data["state"] = state
	match_state.set_object_data(target_id, object_data)

	var event_kind := GameIds.EVENT_GOAL_ENTERED if inside else GameIds.EVENT_GOAL_EXITED
	var action := GameIds.ACTION_GOAL_ENTER if inside else GameIds.ACTION_GOAL_EXIT
	var events: Array[Dictionary] = []
	events.append(match_state.event(event_kind, action, peer_id, target_id, {"state": state.duplicate(true)}))
	return match_state.ok(events)
