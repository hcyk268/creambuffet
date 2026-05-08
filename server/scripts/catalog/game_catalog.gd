extends RefCounted
class_name GameCatalog

const DEFAULT_MAP_ID := "beginner"
const DEFAULT_PLAYER_TEMPLATE_ID := "default"
const CATALOG_PATH := "res://data/game_catalog.json"

static var _catalog_cache: Dictionary = {}
static var _catalog_loaded := false


static func normalize_map_id(map_id: String) -> String:
	var normalized := map_id.strip_edges().to_lower()
	return DEFAULT_MAP_ID if normalized.is_empty() else normalized


static func has_map(map_id: String) -> bool:
	return _maps().has(normalize_map_id(map_id))


static func get_map(map_id: String = DEFAULT_MAP_ID) -> Dictionary:
	var maps := _maps()
	var normalized := normalize_map_id(map_id)
	if not maps.has(normalized):
		normalized = DEFAULT_MAP_ID
	return Dictionary(maps.get(normalized, {})).duplicate(true)


static func get_level_ids(map_id: String = DEFAULT_MAP_ID) -> Array[String]:
	var result: Array[String] = []
	var map_data := get_map(map_id)
	var raw_levels: Variant = map_data.get("levels", [])
	if typeof(raw_levels) == TYPE_ARRAY:
		for raw_level_id in raw_levels:
			result.append(String(raw_level_id))
	return result


static func get_level(level_id: String) -> Dictionary:
	var levels := _levels()
	if not levels.has(level_id):
		return {}
	return Dictionary(levels[level_id]).duplicate(true)


static func get_level_by_index(map_id: String, level_index: int) -> Dictionary:
	var level_ids := get_level_ids(map_id)
	if level_ids.is_empty():
		return {}
	var safe_index := clampi(level_index, 0, level_ids.size() - 1)
	return get_level(level_ids[safe_index])


static func get_level_id_by_index(map_id: String, level_index: int) -> String:
	var level_ids := get_level_ids(map_id)
	if level_ids.is_empty():
		return ""
	var safe_index := clampi(level_index, 0, level_ids.size() - 1)
	return level_ids[safe_index]


static func get_level_index(map_id: String, level_id: String) -> int:
	var level_ids := get_level_ids(map_id)
	for index in range(level_ids.size()):
		if level_ids[index] == level_id:
			return index
	return -1


static func get_object(level_id: String, target_id: String) -> Dictionary:
	var level := get_level(level_id)
	var objects: Variant = level.get("objects", {})
	if typeof(objects) != TYPE_DICTIONARY:
		return {}
	var object_map: Dictionary = objects
	if not object_map.has(target_id):
		return {}
	return Dictionary(object_map[target_id]).duplicate(true)


static func get_player_template(template_id: String = DEFAULT_PLAYER_TEMPLATE_ID) -> Dictionary:
	var templates_raw: Variant = _catalog().get("player_templates", {})
	if typeof(templates_raw) != TYPE_DICTIONARY:
		return {}
	var templates: Dictionary = templates_raw
	var normalized := template_id.strip_edges().to_lower()
	if normalized.is_empty():
		normalized = DEFAULT_PLAYER_TEMPLATE_ID
	if not templates.has(normalized):
		normalized = DEFAULT_PLAYER_TEMPLATE_ID
	return Dictionary(templates.get(normalized, {})).duplicate(true)


static func get_global_rulesets() -> Dictionary:
	var rulesets: Variant = _catalog().get("global_rulesets", {})
	if typeof(rulesets) != TYPE_DICTIONARY:
		return {}
	return Dictionary(rulesets).duplicate(true)


static func get_mechanic_definitions() -> Dictionary:
	var mechanics: Variant = _catalog().get("mechanic_definitions", {})
	if typeof(mechanics) != TYPE_DICTIONARY:
		return {}
	return Dictionary(mechanics).duplicate(true)


static func get_mechanic_definition(ruleset_id: String) -> Dictionary:
	var mechanics := get_mechanic_definitions()
	if not mechanics.has(ruleset_id):
		return {}
	return Dictionary(mechanics[ruleset_id]).duplicate(true)


static func get_allowed_actions(level_id: String, target_id: String) -> Array[String]:
	var object_data := get_object(level_id, target_id)
	var kind := String(object_data.get("kind", ""))
	var level_rulesets := _level_ruleset_lookup(get_level(level_id))
	var result: Array[String] = []

	for ruleset_id in _rulesets_for_object_kind(kind):
		if not level_rulesets.has(ruleset_id):
			continue

		var mechanic := get_mechanic_definition(ruleset_id)
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


static func normalize_world_action(action: String) -> String:
	var raw_action := action.strip_edges().to_lower()
	for mechanic_raw in get_mechanic_definitions().values():
		if typeof(mechanic_raw) != TYPE_DICTIONARY:
			continue

		var mechanic: Dictionary = Dictionary(mechanic_raw)
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

			var action_def: Dictionary = Dictionary(action_def_raw)
			var aliases_raw: Variant = action_def.get("aliases", [])
			if typeof(aliases_raw) == TYPE_ARRAY and aliases_raw.has(raw_action):
				return canonical

	return raw_action


static func validate_world_action(level_id: String, target_id: String, action: String, payload: Dictionary = {}) -> Dictionary:
	var level := get_level(level_id)
	if level.is_empty():
		return _error("unknown_level", "Level is not defined: %s" % level_id)
	if target_id.strip_edges().is_empty():
		return _error("missing_target_id", "World action requires a target_id.")

	var object_data := get_object(level_id, target_id)
	if object_data.is_empty():
		return _error("unknown_target", "Target does not exist in the current level: %s" % target_id)

	var object_kind := String(object_data.get("kind", ""))
	var normalized_action := normalize_world_action(action)
	var level_rulesets := _level_ruleset_lookup(level)
	for ruleset_id in _rulesets_for_object_kind(object_kind):
		if not level_rulesets.has(ruleset_id):
			continue

		var mechanic := get_mechanic_definition(ruleset_id)
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


static func validate_level_rulesets(map_id: String, level_id: String) -> Dictionary:
	var map_data := get_map(map_id)
	var level := get_level(level_id)
	if level.is_empty():
		return _error("unknown_level", "Level is not defined: %s" % level_id)

	var allowed_lookup := {}
	var raw_allowed: Variant = map_data.get("allowed_rulesets", [])
	if typeof(raw_allowed) == TYPE_ARRAY:
		for ruleset in raw_allowed:
			allowed_lookup[String(ruleset)] = true

	var known_rulesets := get_global_rulesets()
	var raw_rulesets: Variant = level.get("rulesets", [])
	if typeof(raw_rulesets) == TYPE_ARRAY:
		for ruleset in raw_rulesets:
			var ruleset_id := String(ruleset)
			if not known_rulesets.has(ruleset_id):
				return _error("unknown_ruleset", "Unknown ruleset %s in level %s." % [ruleset_id, level_id])
			if not allowed_lookup.has(ruleset_id):
				return _error(
					"ruleset_not_allowed",
					"Level %s uses ruleset %s outside map %s." % [level_id, ruleset_id, normalize_map_id(map_id)]
				)

	var level_rulesets := _level_ruleset_lookup(level)
	var raw_objects: Variant = level.get("objects", {})
	if typeof(raw_objects) == TYPE_DICTIONARY:
		var objects: Dictionary = raw_objects
		for raw_target_id in objects.keys():
			var target_id := String(raw_target_id)
			var object_raw: Variant = objects.get(target_id, {})
			if typeof(object_raw) != TYPE_DICTIONARY:
				return _error("bad_object_definition", "Object %s must be a dictionary." % target_id)

			var object_kind := String(Dictionary(object_raw).get("kind", ""))
			var object_rulesets := _rulesets_for_object_kind(object_kind)
			if object_rulesets.is_empty():
				return _error("unknown_object_kind", "Object %s uses unknown kind %s." % [target_id, object_kind])

			var is_enabled := false
			for candidate_ruleset_id in object_rulesets:
				if level_rulesets.has(candidate_ruleset_id):
					is_enabled = true
					break
			if not is_enabled:
				return _error("object_ruleset_not_enabled", "Object %s kind %s is not enabled by level rulesets." % [target_id, object_kind])

	return {"ok": true}


static func _catalog() -> Dictionary:
	if _catalog_loaded:
		return _catalog_cache

	_catalog_loaded = true
	_catalog_cache = {}

	var file_path := _catalog_file_path()
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("GameCatalog could not open catalog at %s." % file_path)
		return _catalog_cache

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		push_error("GameCatalog failed to parse catalog JSON at %s (error %d)." % [file_path, parse_error])
		return _catalog_cache

	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("GameCatalog JSON root must be a dictionary: %s" % file_path)
		return _catalog_cache

	_catalog_cache = Dictionary(json.data).duplicate(true)
	return _catalog_cache


static func _catalog_file_path() -> String:
	return CATALOG_PATH


static func _maps() -> Dictionary:
	var maps_raw: Variant = _catalog().get("maps", {})
	if typeof(maps_raw) != TYPE_DICTIONARY:
		return {}
	return Dictionary(maps_raw)


static func _levels() -> Dictionary:
	var levels_raw: Variant = _catalog().get("levels", {})
	if typeof(levels_raw) != TYPE_DICTIONARY:
		return {}
	return Dictionary(levels_raw)


static func _level_ruleset_lookup(level: Dictionary) -> Dictionary:
	var lookup := {}
	var raw_rulesets: Variant = level.get("rulesets", [])
	if typeof(raw_rulesets) == TYPE_ARRAY:
		for ruleset in raw_rulesets:
			lookup[String(ruleset)] = true
	return lookup


static func _rulesets_for_object_kind(object_kind: String) -> Array[String]:
	var result: Array[String] = []
	for raw_ruleset_id in get_mechanic_definitions().keys():
		var ruleset_id := String(raw_ruleset_id)
		var mechanic: Dictionary = Dictionary(get_mechanic_definitions()[ruleset_id])
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


static func _error(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
	}
