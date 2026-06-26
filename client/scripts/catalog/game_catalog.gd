extends RefCounted
class_name GameCatalog

const CatalogContract = preload("res://scripts/catalog/catalog_contract.gd")

const DEFAULT_MAP_ID := "beginner"
const DEFAULT_PLAYER_TEMPLATE_ID := "default"
const CATALOG_PATH := "res://data/game_catalog.json"
const DEFAULT_ONLINE_PLAYER_COLORS := [
	"fff089",
	"fdc9c9",
	"97edca",
	"c9d4fd",
]

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


static func get_map_ids() -> Array[String]:
	var result: Array[String] = []
	var maps := _maps()
	var raw_ids := maps.keys()
	# raw_ids.sort()
	# No sorting is needed if you want to display in the order: beginner -> water -> dark
	for raw_id in raw_ids:
		result.append(String(raw_id))
	return result


static func get_map_title(map_id: String) -> String:
	var map_data := get_map(map_id)
	var title := String(map_data.get("title", "")).strip_edges()
	if title.is_empty():
		return normalize_map_id(map_id)
	return title


static func is_map_selectable(map_id: String) -> bool:
	var map_data := get_map(map_id)
	if map_data.is_empty():
		return false
	return bool(map_data.get("selectable", true))


static func is_map_wip(map_id: String) -> bool:
	return bool(get_map(map_id).get("wip", false))


static func get_map_thumbnail_path(map_id: String) -> String:
	return String(get_map(map_id).get("thumbnail_path", "")).strip_edges()


static func get_map_ui_entry(map_id: String) -> Dictionary:
	var map_data := get_map(map_id)
	if map_data.is_empty():
		return {}

	var level_count := get_level_ids(map_id).size()
	var subtitle := "%d levels" % level_count
	if is_map_wip(map_id):
		subtitle = "WIP placeholder"

	return {
		"map_id": normalize_map_id(map_id),
		"title": get_map_title(map_id),
		"subtitle": subtitle,
		"thumbnail_path": get_map_thumbnail_path(map_id),
		"selectable": is_map_selectable(map_id),
		"wip": is_map_wip(map_id),
	}


static func get_level_ids(map_id: String = DEFAULT_MAP_ID) -> Array[String]:
	var result: Array[String] = []
	var map_data := get_map(map_id)
	var raw_levels: Variant = map_data.get("levels", [])
	if typeof(raw_levels) == TYPE_ARRAY:
		for raw_level_id in raw_levels:
			result.append(String(raw_level_id))
	return result


static func get_level(level_id: String) -> Dictionary:
	var level := _raw_level(level_id)
	if level.is_empty():
		return {}
	return _resolve_level_definition(level)


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


static func get_online_player_color_palette() -> Array[String]:
	var palette: Array[String] = []
	var online_raw: Variant = _catalog().get("online", {})
	if typeof(online_raw) == TYPE_DICTIONARY:
		var online: Dictionary = online_raw
		var colors_raw: Variant = online.get("player_colors", [])
		if typeof(colors_raw) == TYPE_ARRAY:
			for raw_color in colors_raw:
				var normalized := _normalize_hex_color(String(raw_color))
				if not normalized.is_empty() and not palette.has(normalized):
					palette.append(normalized)

	if palette.is_empty():
		for color_hex in DEFAULT_ONLINE_PLAYER_COLORS:
			palette.append(color_hex)

	return palette


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
	return CatalogContract.get_allowed_actions(get_level(level_id), get_object(level_id, target_id), get_mechanic_definitions())


static func normalize_world_action(action: String) -> String:
	return CatalogContract.normalize_world_action(action, get_mechanic_definitions())


static func validate_world_action(level_id: String, target_id: String, action: String, payload: Dictionary = {}) -> Dictionary:
	return CatalogContract.validate_world_action(
		level_id,
		target_id,
		action,
		get_level(level_id),
		get_object(level_id, target_id),
		get_mechanic_definitions(),
		payload
	)


static func validate_level_rulesets(map_id: String, level_id: String) -> Dictionary:
	var map_data := get_map(map_id)
	var allowed_lookup := _string_lookup(map_data.get("allowed_rulesets", []))
	return CatalogContract.validate_level_rulesets(
		map_id,
		normalize_map_id(map_id),
		level_id,
		get_level(level_id),
		allowed_lookup,
		get_global_rulesets(),
		get_mechanic_definitions()
	)


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


static func _normalize_hex_color(color_hex: String) -> String:
	var normalized := color_hex.strip_edges().trim_prefix("#").to_lower()
	if normalized.length() != 6:
		return ""
	return normalized


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


static func _raw_level(level_id: String) -> Dictionary:
	var levels := _levels()
	if not levels.has(level_id):
		return {}
	return Dictionary(levels[level_id]).duplicate(true)


static func _resolve_level_definition(level: Dictionary) -> Dictionary:
	if level.is_empty():
		return {}

	var resolved: Dictionary = level.duplicate(true)
	resolved["rulesets"] = _merged_rulesets_for_level(level)
	resolved["player_state_defaults"] = _merged_player_state_defaults(level)
	return resolved


static func _level_ruleset_lookup(level: Dictionary) -> Dictionary:
	var lookup := {}
	for ruleset_id in _merged_rulesets_for_level(level):
		lookup[ruleset_id] = true
	return lookup


static func _merged_rulesets_for_level(level: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var seen := {}
	var map_id := normalize_map_id(String(level.get("map_id", DEFAULT_MAP_ID)))
	var removed_lookup := _string_lookup(level.get("removed_rulesets", []))

	_append_rulesets_unique(result, seen, _map_ruleset_array(map_id, "default_rulesets"), removed_lookup)
	_append_rulesets_unique(result, seen, level.get("rulesets", []), removed_lookup)
	_append_rulesets_unique(result, seen, level.get("extra_rulesets", []), removed_lookup)
	return result


static func _map_ruleset_array(map_id: String, field_name: String) -> Array[String]:
	var map_data := get_map(map_id)
	var result: Array[String] = []
	var raw_rulesets: Variant = map_data.get(field_name, [])
	if typeof(raw_rulesets) == TYPE_ARRAY:
		for raw_ruleset in raw_rulesets:
			result.append(String(raw_ruleset))
	return result


static func _append_rulesets_unique(result: Array[String], seen: Dictionary, raw_rulesets: Variant, removed_lookup: Dictionary) -> void:
	if typeof(raw_rulesets) != TYPE_ARRAY:
		return

	for raw_ruleset in raw_rulesets:
		var ruleset_id := String(raw_ruleset)
		if ruleset_id.is_empty() or removed_lookup.has(ruleset_id) or seen.has(ruleset_id):
			continue
		seen[ruleset_id] = true
		result.append(ruleset_id)


static func _string_lookup(raw_values: Variant) -> Dictionary:
	var lookup := {}
	if typeof(raw_values) != TYPE_ARRAY:
		return lookup

	for raw_value in raw_values:
		lookup[String(raw_value)] = true
	return lookup


static func _merged_player_state_defaults(level: Dictionary) -> Dictionary:
	var map_id := normalize_map_id(String(level.get("map_id", DEFAULT_MAP_ID)))
	var result := _map_dictionary_field(map_id, "player_state_defaults")
	result = _merge_dictionaries(result, level.get("player_state_defaults", {}))
	result = _merge_dictionaries(result, level.get("player_state_overrides", {}))
	_remove_dictionary_keys(result, level.get("removed_player_state_fields", []))
	return result


static func _map_dictionary_field(map_id: String, field_name: String) -> Dictionary:
	var map_data := get_map(map_id)
	var raw_value: Variant = map_data.get(field_name, {})
	if typeof(raw_value) != TYPE_DICTIONARY:
		return {}
	return Dictionary(raw_value).duplicate(true)


static func _merge_dictionaries(base: Dictionary, overrides_raw: Variant) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	if typeof(overrides_raw) != TYPE_DICTIONARY:
		return result

	var overrides: Dictionary = overrides_raw
	for raw_key in overrides.keys():
		var key := String(raw_key)
		var override_value = overrides[raw_key]
		if typeof(override_value) == TYPE_DICTIONARY and typeof(result.get(key, null)) == TYPE_DICTIONARY:
			result[key] = _merge_dictionaries(Dictionary(result[key]), override_value)
		else:
			result[key] = override_value
	return result


static func _remove_dictionary_keys(target: Dictionary, raw_keys: Variant) -> void:
	if typeof(raw_keys) != TYPE_ARRAY:
		return

	for raw_key in raw_keys:
		target.erase(String(raw_key))
