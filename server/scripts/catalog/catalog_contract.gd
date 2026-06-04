extends RefCounted


static func get_allowed_actions(level: Dictionary, object_data: Dictionary, mechanic_definitions: Dictionary) -> Array[String]:
	var kind := String(object_data.get("kind", ""))
	var level_rulesets := _string_lookup(level.get("rulesets", []))
	var result: Array[String] = []

	for ruleset_id in _rulesets_for_object_kind(kind, mechanic_definitions):
		if not level_rulesets.has(ruleset_id):
			continue

		var mechanic_raw: Variant = mechanic_definitions.get(ruleset_id, {})
		if typeof(mechanic_raw) != TYPE_DICTIONARY:
			continue

		var mechanic: Dictionary = mechanic_raw
		var actions_raw: Variant = mechanic.get("actions", {})
		if typeof(actions_raw) != TYPE_DICTIONARY:
			continue

		var actions: Dictionary = actions_raw
		for raw_action in actions.keys():
			var action := String(raw_action)
			var action_def: Dictionary = Dictionary(actions[action])
			if not _action_supports_kind(action_def, kind):
				continue

			result.append(action)
			var aliases_raw: Variant = action_def.get("aliases", [])
			if typeof(aliases_raw) == TYPE_ARRAY:
				for alias in aliases_raw:
					result.append(String(alias))

	return result


static func normalize_world_action(action: String, mechanic_definitions: Dictionary) -> String:
	var raw_action := action.strip_edges().to_lower()
	for mechanic_raw in mechanic_definitions.values():
		if typeof(mechanic_raw) != TYPE_DICTIONARY:
			continue

		var mechanic: Dictionary = mechanic_raw
		var actions_raw: Variant = mechanic.get("actions", {})
		if typeof(actions_raw) != TYPE_DICTIONARY:
			continue

		var actions: Dictionary = actions_raw
		if actions.has(raw_action):
			return raw_action

		for raw_canonical in actions.keys():
			var canonical := String(raw_canonical)
			var action_def_raw: Variant = actions.get(canonical, {})
			if typeof(action_def_raw) != TYPE_DICTIONARY:
				continue

			var action_def: Dictionary = action_def_raw
			var aliases_raw: Variant = action_def.get("aliases", [])
			if typeof(aliases_raw) == TYPE_ARRAY and aliases_raw.has(raw_action):
				return canonical

	return raw_action


static func validate_world_action(
	level_id: String,
	target_id: String,
	action: String,
	level: Dictionary,
	object_data: Dictionary,
	mechanic_definitions: Dictionary,
	payload: Dictionary = {}
) -> Dictionary:
	if level.is_empty():
		return _error("unknown_level", "Level is not defined: %s" % level_id)
	if target_id.strip_edges().is_empty():
		return _error("missing_target_id", "World action requires a target_id.")
	if object_data.is_empty():
		return _error("unknown_target", "Target does not exist in the current level: %s" % target_id)

	var object_kind := String(object_data.get("kind", ""))
	var normalized_action := normalize_world_action(action, mechanic_definitions)
	var level_rulesets := _string_lookup(level.get("rulesets", []))
	for ruleset_id in _rulesets_for_object_kind(object_kind, mechanic_definitions):
		if not level_rulesets.has(ruleset_id):
			continue

		var mechanic_raw: Variant = mechanic_definitions.get(ruleset_id, {})
		if typeof(mechanic_raw) != TYPE_DICTIONARY:
			continue

		var mechanic: Dictionary = mechanic_raw
		var actions_raw: Variant = mechanic.get("actions", {})
		if typeof(actions_raw) != TYPE_DICTIONARY:
			continue

		var actions: Dictionary = actions_raw
		if not actions.has(normalized_action):
			continue

		var action_def: Dictionary = Dictionary(actions[normalized_action]).duplicate(true)
		if not _action_supports_kind(action_def, object_kind):
			continue

		var payload_validation := _validate_required_payload(action_def, payload)
		if not bool(payload_validation.get("ok", false)):
			return payload_validation

		return {
			"ok": true,
			"action": normalized_action,
			"target_id": target_id,
			"object_kind": object_kind,
			"ruleset_id": ruleset_id,
			"mechanic": mechanic,
			"action_definition": action_def,
			"server_handler": String(action_def.get("server_handler", "")),
		}

	return _error(
		"unsupported_world_action",
		"Action %s is not allowed for object kind %s in level %s." % [normalized_action, object_kind, level_id]
	)


static func validate_level_rulesets(
	_map_id: String,
	normalized_map_id: String,
	level_id: String,
	level: Dictionary,
	allowed_rulesets: Dictionary,
	known_rulesets: Dictionary,
	mechanic_definitions: Dictionary
) -> Dictionary:
	if level.is_empty():
		return _error("unknown_level", "Level is not defined: %s" % level_id)

	var level_rulesets := _string_array(level.get("rulesets", []))
	for ruleset_id in level_rulesets:
		if not known_rulesets.has(ruleset_id):
			return _error("unknown_ruleset", "Unknown ruleset %s in level %s." % [ruleset_id, level_id])
		if not allowed_rulesets.has(ruleset_id):
			return _error(
				"ruleset_not_allowed",
				"Level %s uses ruleset %s outside map %s." % [level_id, ruleset_id, normalized_map_id]
			)

	var level_ruleset_lookup := _string_lookup(level_rulesets)
	var raw_objects: Variant = level.get("objects", {})
	if typeof(raw_objects) != TYPE_DICTIONARY:
		return {"ok": true}

	var objects: Dictionary = raw_objects
	for raw_target_id in objects.keys():
		var target_id := String(raw_target_id)
		var object_raw: Variant = objects.get(target_id, {})
		if typeof(object_raw) != TYPE_DICTIONARY:
			return _error("bad_object_definition", "Object %s must be a dictionary." % target_id)

		var object_kind := String(Dictionary(object_raw).get("kind", ""))
		var object_rulesets := _rulesets_for_object_kind(object_kind, mechanic_definitions)
		if object_rulesets.is_empty():
			return _error("unknown_object_kind", "Object %s uses unknown kind %s." % [target_id, object_kind])

		var is_enabled := false
		for candidate_ruleset_id in object_rulesets:
			if level_ruleset_lookup.has(candidate_ruleset_id):
				is_enabled = true
				break
		if not is_enabled:
			return _error("object_ruleset_not_enabled", "Object %s kind %s is not enabled by level rulesets." % [target_id, object_kind])

	return {"ok": true}


static func _rulesets_for_object_kind(object_kind: String, mechanic_definitions: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_ruleset_id in mechanic_definitions.keys():
		var ruleset_id := String(raw_ruleset_id)
		var mechanic_raw: Variant = mechanic_definitions.get(ruleset_id, {})
		if typeof(mechanic_raw) != TYPE_DICTIONARY:
			continue

		var mechanic: Dictionary = mechanic_raw
		var kinds_raw: Variant = mechanic.get("object_kinds", [])
		if typeof(kinds_raw) == TYPE_ARRAY and kinds_raw.has(object_kind):
			result.append(ruleset_id)
	return result


static func _action_supports_kind(action_def: Dictionary, object_kind: String) -> bool:
	var kinds_raw: Variant = action_def.get("object_kinds", [])
	return typeof(kinds_raw) == TYPE_ARRAY and kinds_raw.has(object_kind)


static func _validate_required_payload(action_def: Dictionary, payload: Dictionary) -> Dictionary:
	if bool(payload.get("legacy", false)):
		return {"ok": true}

	var required_raw: Variant = action_def.get("required_payload", [])
	if typeof(required_raw) != TYPE_ARRAY:
		return {"ok": true}

	for raw_requirement in required_raw:
		if typeof(raw_requirement) != TYPE_DICTIONARY:
			continue

		var requirement: Dictionary = raw_requirement
		var field_name := String(requirement.get("field", ""))
		var value = null
		var has_value := false
		if payload.has(field_name):
			value = payload[field_name]
			has_value = true
		else:
			var aliases_raw: Variant = requirement.get("aliases", [])
			if typeof(aliases_raw) == TYPE_ARRAY:
				for alias in aliases_raw:
					var alias_name := String(alias)
					if payload.has(alias_name):
						value = payload[alias_name]
						has_value = true
						break

		if not has_value:
			return _error("missing_required_payload", "Action requires payload field: %s." % field_name)

		var expected_type := String(requirement.get("type", ""))
		if not _payload_type_matches(value, expected_type):
			return _error("bad_payload_field", "Payload field %s must be %s." % [field_name, expected_type])

	return {"ok": true}


static func _payload_type_matches(value, expected_type: String) -> bool:
	match expected_type:
		"bool":
			return typeof(value) == TYPE_BOOL
		"dictionary":
			return typeof(value) == TYPE_DICTIONARY
		"string":
			return typeof(value) == TYPE_STRING
		"number":
			return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
		_:
			return true


static func _string_array(raw_values: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(raw_values) != TYPE_ARRAY:
		return result

	for raw_value in raw_values:
		result.append(String(raw_value))
	return result


static func _string_lookup(raw_values: Variant) -> Dictionary:
	var lookup: Dictionary = {}
	for value in _string_array(raw_values):
		lookup[value] = true
	return lookup


static func _error(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
	}
