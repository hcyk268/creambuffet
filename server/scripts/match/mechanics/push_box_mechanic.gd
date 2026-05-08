extends RefCounted


func apply_state(match_state, peer_id: int, target_id: String, payload: Dictionary) -> Dictionary:
	var object_state: Dictionary = match_state._get_required_object(target_id, ["push_box"], "push_box_state")
	if not bool(object_state.get("ok", false)):
		return object_state

	var raw_position = payload.get("position", {})
	if typeof(raw_position) != TYPE_DICTIONARY:
		return match_state._error("bad_position", "Push box state requires a position object.")
	if not match_state.can_player_observe_push_box(peer_id, target_id, raw_position):
		return match_state._error("push_box_out_of_range", "Player must stay close to the push box to update its state.")

	var position: Dictionary = raw_position
	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})
	state["position"] = {
		"x": float(position.get("x", 0.0)),
		"y": float(position.get("y", 0.0)),
	}
	state["updated_by_peer_id"] = peer_id
	object_data["state"] = state
	match_state.objects[target_id] = object_data

	var events: Array[Dictionary] = []
	events.append(match_state._event("push_box_state", "push_box_state", peer_id, target_id, {"position": state["position"]}))
	return match_state._ok(events)
