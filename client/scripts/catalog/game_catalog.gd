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
