extends RefCounted


func apply_button_state(match_state, peer_id: int, target_id: String, payload: Dictionary) -> Dictionary:
	var object_state: Dictionary = match_state._get_required_object(target_id, ["button", "pressure_plate"], "button_state")
	if not bool(object_state.get("ok", false)):
		return object_state

	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})
	var pressed := match_state.compute_button_pressed(target_id)
	if bool(state.get("pressed", false)) == pressed:
		var no_events: Array[Dictionary] = []
		return match_state._ok(no_events)

	state["pressed"] = pressed
	state["updated_by_peer_id"] = peer_id
	object_data["state"] = state
	match_state.objects[target_id] = object_data

	var events: Array[Dictionary] = []
	events.append(match_state._event("button_state", "button_state", peer_id, target_id, {
		"pressed": pressed,
		"state": state.duplicate(true),
	}))
	events.append_array(_apply_links_for_source(match_state, peer_id, target_id, "pressed", pressed))
	return match_state._ok(events)


func _apply_links_for_source(match_state, peer_id: int, source_target_id: String, source_field: String, source_value) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var raw_links: Variant = match_state.level_definition.get("links", [])
	if typeof(raw_links) != TYPE_ARRAY:
		return events

	for raw_link in raw_links:
		if typeof(raw_link) != TYPE_DICTIONARY:
			continue

		var link: Dictionary = raw_link
		if String(link.get("source_target_id", "")) != source_target_id:
			continue
		if String(link.get("source_field", "")) != source_field:
			continue
		if link.get("source_value", null) != source_value:
			continue

		var target_id := String(link.get("target_id", ""))
		var target: Dictionary = match_state._get_object(target_id)
		if target.is_empty():
			continue

		var target_state: Dictionary = target.get("state", {})
		var target_field := String(link.get("target_field", ""))
		target_state[target_field] = link.get("target_value", true)
		target["state"] = target_state
		match_state.objects[target_id] = target
		events.append(match_state._event("object_state_changed", "linked_state", peer_id, target_id, {
			"state": target_state.duplicate(true),
			"source_target_id": source_target_id,
		}))

	return events
