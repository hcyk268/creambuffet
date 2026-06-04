extends RefCounted
class_name ObjectStateStore

var _objects: Dictionary


func _init(objects: Dictionary) -> void:
	_objects = objects


func clear() -> void:
	_objects.clear()


func has(target_id: String) -> bool:
	return _objects.has(target_id)


func ids() -> Array[String]:
	var result: Array[String] = []
	for raw_target_id in _objects.keys():
		result.append(String(raw_target_id))
	return result


func get_object(target_id: String) -> Dictionary:
	if not has(target_id):
		return {}
	return Dictionary(_objects[target_id]).duplicate(true)


func set_object(target_id: String, object_data: Dictionary) -> void:
	_objects[target_id] = object_data.duplicate(true)


func kind(target_id: String) -> String:
	return String(get_object(target_id).get("kind", ""))


func get_state(target_id: String) -> Dictionary:
	var object_data := get_object(target_id)
	if object_data.is_empty():
		return {}

	var raw_state: Variant = object_data.get("state", {})
	if typeof(raw_state) != TYPE_DICTIONARY:
		return {}
	return Dictionary(raw_state).duplicate(true)


func set_state(target_id: String, state: Dictionary) -> Dictionary:
	var object_data := get_object(target_id)
	if object_data.is_empty():
		return {}

	object_data["state"] = state.duplicate(true)
	set_object(target_id, object_data)
	return object_data


func patch_state(target_id: String, updates: Dictionary) -> Dictionary:
	var state := get_state(target_id)
	if state.is_empty() and updates.is_empty():
		return {}

	for raw_key in updates.keys():
		state[String(raw_key)] = updates[raw_key]
	set_state(target_id, state)
	return state
