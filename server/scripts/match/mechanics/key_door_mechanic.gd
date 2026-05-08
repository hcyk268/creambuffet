extends RefCounted


func apply_collect(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	var object_state: Dictionary = match_state._get_required_object(target_id, ["key"], "collect")
	if not bool(object_state.get("ok", false)):
		return object_state
	if not match_state.can_player_interact_with_trigger(peer_id, target_id):
		return match_state._error("interaction_out_of_range", "Player must overlap the key trigger to collect it.")

	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})
	if bool(state.get("collected", false)):
		return match_state._error("world_action_rejected", "Key has already been collected.")

	state["collected"] = true
	state["collector_peer_id"] = peer_id
	object_data["state"] = state
	match_state.objects[target_id] = object_data

	var player_state: Dictionary = match_state.players[peer_id]
	player_state["key_count"] = int(player_state.get("key_count", 0)) + 1
	match_state.players[peer_id] = player_state

	var events: Array[Dictionary] = []
	events.append(match_state._event("key_collected", "collect", peer_id, target_id, {"state": state.duplicate(true)}))
	return match_state._ok(events)


func apply_open(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	var object_state: Dictionary = match_state._get_required_object(target_id, ["door", "exit_door"], "open")
	if not bool(object_state.get("ok", false)):
		return object_state
	if not match_state.can_player_interact_with_trigger(peer_id, target_id):
		return match_state._error("interaction_out_of_range", "Player must overlap the door trigger to open it.")

	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})
	if bool(state.get("opened", false)):
		return match_state._error("world_action_rejected", "Door is already open.")

	var player_state: Dictionary = match_state.players[peer_id]
	var requires: Dictionary = {}
	var raw_requires: Variant = object_data.get("requires", {})
	if typeof(raw_requires) == TYPE_DICTIONARY:
		requires = raw_requires

	var required_count := int(requires.get("count", 0))
	if required_count > 0 and int(player_state.get("key_count", 0)) < required_count:
		return match_state._error("missing_key", "Player does not have the required key.")

	if required_count > 0:
		player_state["key_count"] = int(player_state.get("key_count", 0)) - required_count
		match_state.players[peer_id] = player_state

	state["opened"] = true
	state["opened_by_peer_id"] = peer_id
	object_data["state"] = state
	match_state.objects[target_id] = object_data

	var events: Array[Dictionary] = []
	events.append(match_state._event("door_opened", "open", peer_id, target_id, {"state": state.duplicate(true)}))
	return match_state._ok(events)
