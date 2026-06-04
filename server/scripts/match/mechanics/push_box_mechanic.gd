extends RefCounted

const GameIds = preload("res://scripts/catalog/game_ids.gd")

func apply_state(match_state, peer_id: int, target_id: String, payload: Dictionary) -> Dictionary:
	var object_state: Dictionary = match_state.require_object(target_id, [GameIds.OBJECT_KIND_PUSH_BOX], GameIds.ACTION_PUSH_BOX_STATE)
	if not bool(object_state.get("ok", false)):
		return object_state

	var raw_position = payload.get("position", {})
	if typeof(raw_position) != TYPE_DICTIONARY:
		return match_state.error("bad_position", "Push box state requires a position object.")
	if not match_state.can_player_observe_push_box(peer_id, target_id, raw_position):
		return match_state.error("push_box_out_of_range", "Player must stay close to the push box to update its state.")

	var position: Dictionary = raw_position
	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})
	state["position"] = {
		"x": float(position.get("x", 0.0)),
		"y": float(position.get("y", 0.0)),
	}
	state["updated_by_peer_id"] = peer_id
	object_data["state"] = state
	match_state.set_object_data(target_id, object_data)

	var events: Array[Dictionary] = []
	events.append(match_state.event(GameIds.EVENT_PUSH_BOX_STATE, GameIds.ACTION_PUSH_BOX_STATE, peer_id, target_id, {"position": state["position"]}))
	return match_state.ok(events)
