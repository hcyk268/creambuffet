extends RefCounted
class_name LinkApplier

const GameIds = preload("res://scripts/catalog/game_ids.gd")

static func apply_links_for_source(match_state, peer_id: int, source_target_id: String, source_field: String, source_value) -> Array[Dictionary]:
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
		var target: Dictionary = match_state.get_object_data(target_id)
		if target.is_empty():
			continue

		var target_state: Dictionary = target.get("state", {})
		var target_field := String(link.get("target_field", ""))
		if target_field.is_empty():
			continue

		var operation := String(link.get("target_operation", link.get("operation", "set"))).strip_edges().to_lower()
		match operation:
			"toggle":
				target_state[target_field] = not bool(target_state.get(target_field, false))
			"increment":
				target_state[target_field] = int(target_state.get(target_field, 0)) + int(link.get("target_value", 1))
			"decrement":
				target_state[target_field] = int(target_state.get(target_field, 0)) - int(link.get("target_value", 1))
			_:
				target_state[target_field] = link.get("target_value", true)

		target["state"] = target_state
		match_state.set_object_data(target_id, target)
		events.append(match_state.event(GameIds.EVENT_OBJECT_STATE_CHANGED, "linked_state", peer_id, target_id, {
			"state": target_state.duplicate(true),
			"operation": operation,
			"source_target_id": source_target_id,
		}))

	return events
