extends RefCounted
class_name ObjectStateQuery


static func any_object_state(objects: Dictionary, kind: String, field: String, expected) -> bool:
	for raw_object in objects.values():
		if typeof(raw_object) != TYPE_DICTIONARY:
			continue
		var object_data: Dictionary = raw_object
		if String(object_data.get("kind", "")) != kind:
			continue
		var raw_state: Variant = object_data.get("state", {})
		if typeof(raw_state) != TYPE_DICTIONARY:
			continue
		var state: Dictionary = raw_state
		if state.get(field, null) == expected:
			return true
	return false


static func object_state_field_equals(objects: Dictionary, target_id: String, field: String, expected) -> bool:
	if not objects.has(target_id):
		return false

	var raw_object: Variant = objects[target_id]
	if typeof(raw_object) != TYPE_DICTIONARY:
		return false

	var object_data: Dictionary = raw_object
	var raw_state: Variant = object_data.get("state", {})
	if typeof(raw_state) != TYPE_DICTIONARY:
		return false

	var state: Dictionary = raw_state
	return state.get(field, null) == expected
