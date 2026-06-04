extends RefCounted

const GameIds = preload("res://scripts/catalog/game_ids.gd")
const LinkApplier = preload("res://scripts/match/link_applier.gd")


func apply_button_state(match_state, peer_id: int, target_id: String, payload: Dictionary) -> Dictionary:
	var object_state: Dictionary = match_state.require_object(target_id, GameIds.BUTTON_KINDS, GameIds.ACTION_BUTTON_STATE)
	if not bool(object_state.get("ok", false)):
		return object_state

	var object_data: Dictionary = object_state["object"]
	return _apply_button_state_for_object(match_state, peer_id, target_id, object_data, payload)


func refresh_button_states(match_state, peer_id: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for target_id in match_state.object_ids():
		var object_data: Dictionary = match_state.get_object_data(target_id)
		if object_data.is_empty():
			continue
		var kind := String(object_data.get("kind", ""))
		if not GameIds.is_button_kind(kind):
			continue

		var result: Dictionary = _apply_button_state_for_object(match_state, peer_id, target_id, object_data)
		var raw_events: Variant = result.get("events", [])
		if typeof(raw_events) == TYPE_ARRAY:
			events.append_array(raw_events)
	return events


func _apply_button_state_for_object(match_state, peer_id: int, target_id: String, object_data: Dictionary, payload: Dictionary = {}) -> Dictionary:
	var state: Dictionary = object_data.get("state", {})
	var computed_pressed: bool = match_state.compute_button_pressed(target_id)
	var pressed: bool = computed_pressed
	if bool(payload.get("pressed", false)):
		pressed = true
	if bool(state.get("pressed", false)) == pressed:
		var no_events: Array[Dictionary] = []
		return match_state.ok(no_events)

	state["pressed"] = pressed
	state["updated_by_peer_id"] = peer_id
	object_data["state"] = state
	match_state.set_object_data(target_id, object_data)

	var events: Array[Dictionary] = []
	events.append(match_state.event(GameIds.EVENT_BUTTON_STATE, GameIds.ACTION_BUTTON_STATE, peer_id, target_id, {
		"pressed": pressed,
		"state": state.duplicate(true),
	}))
	events.append_array(LinkApplier.apply_links_for_source(match_state, peer_id, target_id, "pressed", pressed))
	return match_state.ok(events)
