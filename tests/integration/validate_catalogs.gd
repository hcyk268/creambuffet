extends SceneTree

const CLIENT_CATALOG_PATH := "client/data/game_catalog.json"
const SERVER_CATALOG_PATH := "server/data/game_catalog.json"
const PLAYER_SCENE_PATH := "client/scenes/player_soda.tscn"
const PLAYER_COLLISION_SHAPE_ID := "RectangleShape2D_r0uhu"
const MIRRORED_SCRIPT_PAIRS := [
	[
		"client/scripts/catalog/catalog_contract.gd",
		"server/scripts/catalog/catalog_contract.gd",
	],
	[
		"client/scripts/catalog/game_ids.gd",
		"server/scripts/catalog/game_ids.gd",
	],
	[
		"client/scripts/network/packet_codec.gd",
		"server/scripts/network/packet_codec.gd",
	],
	[
		"client/scripts/network/protocol_constants.gd",
		"server/scripts/network/protocol_constants.gd",
	],
]
const SUPPORTED_LINK_OPERATIONS := {
	"set": true,
	"toggle": true,
	"increment": true,
	"decrement": true,
}


func _init() -> void:
	var errors: Array[String] = []
	var client_text := _read_text(CLIENT_CATALOG_PATH, errors)
	var server_text := _read_text(SERVER_CATALOG_PATH, errors)

	_validate_mirrored_scripts(errors)

	var client_catalog := _parse_json(CLIENT_CATALOG_PATH, client_text, errors)
	var catalog := _parse_json(SERVER_CATALOG_PATH, server_text, errors)
	if not client_catalog.is_empty() and not catalog.is_empty() and client_catalog != catalog:
		errors.append("client/server catalogs differ; keep %s and %s identical." % [CLIENT_CATALOG_PATH, SERVER_CATALOG_PATH])
	if not catalog.is_empty():
		_validate_catalog(catalog, errors)
		_validate_player_template_against_scene(catalog, errors)

	if errors.is_empty():
		print("Catalog validation passed.")
		quit(0)
		return

	for error in errors:
		push_error(error)
	quit(1)


func _read_text(path: String, errors: Array[String]) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Cannot open catalog file: %s" % path)
		return ""
	return file.get_as_text()


func _validate_mirrored_scripts(errors: Array[String]) -> void:
	for raw_pair in MIRRORED_SCRIPT_PAIRS:
		if typeof(raw_pair) != TYPE_ARRAY or raw_pair.size() != 2:
			continue
		var left_path := String(raw_pair[0])
		var right_path := String(raw_pair[1])
		var left_text := _read_text(left_path, errors)
		var right_text := _read_text(right_path, errors)
		if not left_text.is_empty() and not right_text.is_empty() and left_text != right_text:
			errors.append("Mirrored shared script drift: %s differs from %s." % [left_path, right_path])


func _parse_json(path: String, text: String, errors: Array[String]) -> Dictionary:
	if text.is_empty():
		return {}

	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		errors.append("Invalid JSON in %s at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("Catalog root must be a dictionary: %s" % path)
		return {}
	return Dictionary(json.data)


func _validate_catalog(catalog: Dictionary, errors: Array[String]) -> void:
	var maps := _dictionary_field(catalog, "maps", "catalog", errors)
	var levels := _dictionary_field(catalog, "levels", "catalog", errors)
	var global_rulesets := _dictionary_field(catalog, "global_rulesets", "catalog", errors)
	var mechanic_definitions := _dictionary_field(catalog, "mechanic_definitions", "catalog", errors)
	var object_kind_rulesets := _object_kind_ruleset_lookup(mechanic_definitions, errors)

	for raw_map_id in maps.keys():
		var map_id := String(raw_map_id)
		var map_data := _dictionary_value(maps, raw_map_id, "map %s" % map_id, errors)
		if map_data.is_empty():
			continue
		_validate_map(map_id, map_data, levels, global_rulesets, mechanic_definitions, errors)

	for raw_level_id in levels.keys():
		var level_id := String(raw_level_id)
		var level := _dictionary_value(levels, raw_level_id, "level %s" % level_id, errors)
		if level.is_empty():
			continue
		_validate_level(level_id, level, maps, global_rulesets, mechanic_definitions, object_kind_rulesets, errors)


func _validate_map(
	map_id: String,
	map_data: Dictionary,
	levels: Dictionary,
	global_rulesets: Dictionary,
	mechanic_definitions: Dictionary,
	errors: Array[String]
) -> void:
	var raw_levels: Variant = map_data.get("levels", [])
	if typeof(raw_levels) != TYPE_ARRAY:
		errors.append("Map %s must define levels as an array." % map_id)
	else:
		for raw_level_id in raw_levels:
			var level_id := String(raw_level_id)
			if not levels.has(level_id):
				errors.append("Map %s references unknown level %s." % [map_id, level_id])

	for field_name in ["default_rulesets", "allowed_rulesets"]:
		var raw_rulesets: Variant = map_data.get(field_name, [])
		if typeof(raw_rulesets) != TYPE_ARRAY:
			errors.append("Map %s field %s must be an array." % [map_id, field_name])
			continue
		for raw_ruleset_id in raw_rulesets:
			_validate_ruleset_id(String(raw_ruleset_id), "map %s %s" % [map_id, field_name], global_rulesets, mechanic_definitions, errors)


func _validate_level(
	level_id: String,
	level: Dictionary,
	maps: Dictionary,
	global_rulesets: Dictionary,
	mechanic_definitions: Dictionary,
	object_kind_rulesets: Dictionary,
	errors: Array[String]
) -> void:
	var map_id := String(level.get("map_id", ""))
	if map_id.is_empty() or not maps.has(map_id):
		errors.append("Level %s references unknown map_id %s." % [level_id, map_id])

	var scene_path := String(level.get("scene_path", "")).strip_edges()
	if scene_path.is_empty():
		errors.append("Level %s is missing scene_path." % level_id)

	var enabled_rulesets := _merged_level_rulesets(level, _dictionary_value(maps, map_id, "map %s" % map_id, errors))
	var allowed_rulesets := _string_lookup(_dictionary_value(maps, map_id, "map %s" % map_id, errors).get("allowed_rulesets", []))
	for ruleset_id in enabled_rulesets:
		_validate_ruleset_id(ruleset_id, "level %s" % level_id, global_rulesets, mechanic_definitions, errors)
		if not allowed_rulesets.is_empty() and not allowed_rulesets.has(ruleset_id):
			errors.append("Level %s enables ruleset %s outside map allowed_rulesets." % [level_id, ruleset_id])

	var objects := _dictionary_field(level, "objects", "level %s" % level_id, errors)
	var enabled_lookup := _string_lookup(enabled_rulesets)
	_validate_objects(level_id, objects, enabled_lookup, object_kind_rulesets, errors)
	_validate_links(level_id, level.get("links", []), objects, errors)
	_validate_completion_rules(level_id, level.get("completion_rules", []), objects, errors)
	_validate_action_handlers(mechanic_definitions, errors)


func _validate_objects(
	level_id: String,
	objects: Dictionary,
	enabled_rulesets: Dictionary,
	object_kind_rulesets: Dictionary,
	errors: Array[String]
) -> void:
	for raw_target_id in objects.keys():
		var target_id := String(raw_target_id)
		var object_data := _dictionary_value(objects, raw_target_id, "object %s in level %s" % [target_id, level_id], errors)
		if object_data.is_empty():
			continue

		var kind := String(object_data.get("kind", "")).strip_edges()
		if kind.is_empty():
			errors.append("Object %s in level %s is missing kind." % [target_id, level_id])
			continue

		var kind_rulesets := _string_array(object_kind_rulesets.get(kind, []))
		if kind_rulesets.is_empty():
			errors.append("Object %s in level %s uses unsupported kind %s." % [target_id, level_id, kind])
			continue

		var enabled := false
		for ruleset_id in kind_rulesets:
			if enabled_rulesets.has(ruleset_id):
				enabled = true
				break
		if not enabled:
			errors.append("Object %s kind %s in level %s has no enabled ruleset." % [target_id, kind, level_id])


func _validate_links(level_id: String, raw_links: Variant, objects: Dictionary, errors: Array[String]) -> void:
	if typeof(raw_links) != TYPE_ARRAY:
		errors.append("Level %s links must be an array." % level_id)
		return

	for index in range(raw_links.size()):
		var raw_link: Variant = raw_links[index]
		if typeof(raw_link) != TYPE_DICTIONARY:
			errors.append("Level %s link %d must be a dictionary." % [level_id, index])
			continue

		var link: Dictionary = raw_link
		var source_id := String(link.get("source_target_id", "")).strip_edges()
		var target_id := String(link.get("target_id", "")).strip_edges()
		if source_id.is_empty() or not objects.has(source_id):
			errors.append("Level %s link %d references missing source_target_id %s." % [level_id, index, source_id])
		if target_id.is_empty() or not objects.has(target_id):
			errors.append("Level %s link %d references missing target_id %s." % [level_id, index, target_id])
		if String(link.get("source_field", "")).strip_edges().is_empty():
			errors.append("Level %s link %d is missing source_field." % [level_id, index])
		if String(link.get("target_field", "")).strip_edges().is_empty():
			errors.append("Level %s link %d is missing target_field." % [level_id, index])

		var operation := String(link.get("target_operation", link.get("operation", "set"))).strip_edges().to_lower()
		if not SUPPORTED_LINK_OPERATIONS.has(operation):
			errors.append("Level %s link %d uses unsupported operation %s." % [level_id, index, operation])


func _validate_completion_rules(level_id: String, raw_rules: Variant, objects: Dictionary, errors: Array[String]) -> void:
	if typeof(raw_rules) != TYPE_ARRAY:
		errors.append("Level %s completion_rules must be an array." % level_id)
		return

	for index in range(raw_rules.size()):
		var raw_rule: Variant = raw_rules[index]
		if typeof(raw_rule) != TYPE_DICTIONARY:
			errors.append("Level %s completion rule %d must be a dictionary." % [level_id, index])
			continue

		var rule: Dictionary = raw_rule
		var target_id := String(rule.get("target_id", "")).strip_edges()
		if not target_id.is_empty() and not objects.has(target_id):
			errors.append("Level %s completion rule %d references missing target_id %s." % [level_id, index, target_id])


func _validate_action_handlers(mechanic_definitions: Dictionary, errors: Array[String]) -> void:
	for raw_ruleset_id in mechanic_definitions.keys():
		var ruleset_id := String(raw_ruleset_id)
		var mechanic := _dictionary_value(mechanic_definitions, raw_ruleset_id, "mechanic %s" % ruleset_id, errors)
		if mechanic.is_empty():
			continue
		var actions_raw: Variant = mechanic.get("actions", {})
		if typeof(actions_raw) != TYPE_DICTIONARY:
			errors.append("Mechanic %s actions must be a dictionary." % ruleset_id)
			continue
		var actions: Dictionary = actions_raw
		for raw_action in actions.keys():
			var action := String(raw_action)
			var action_def := _dictionary_value(actions, raw_action, "action %s.%s" % [ruleset_id, action], errors)
			if action_def.is_empty():
				continue
			var handler := String(action_def.get("server_handler", "")).strip_edges()
			if handler.is_empty():
				errors.append("Action %s.%s is missing server_handler." % [ruleset_id, action])


func _object_kind_ruleset_lookup(mechanic_definitions: Dictionary, errors: Array[String]) -> Dictionary:
	var lookup: Dictionary = {}
	for raw_ruleset_id in mechanic_definitions.keys():
		var ruleset_id := String(raw_ruleset_id)
		var mechanic := _dictionary_value(mechanic_definitions, raw_ruleset_id, "mechanic %s" % ruleset_id, errors)
		if mechanic.is_empty():
			continue

		var kinds_raw: Variant = mechanic.get("object_kinds", [])
		if typeof(kinds_raw) != TYPE_ARRAY:
			errors.append("Mechanic %s object_kinds must be an array." % ruleset_id)
			continue
		for raw_kind in kinds_raw:
			var kind := String(raw_kind)
			var rulesets := _string_array(lookup.get(kind, []))
			rulesets.append(ruleset_id)
			lookup[kind] = rulesets
	return lookup


func _merged_level_rulesets(level: Dictionary, map_data: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	var removed := _string_lookup(level.get("removed_rulesets", []))
	_append_rulesets(result, seen, removed, map_data.get("default_rulesets", []))
	_append_rulesets(result, seen, removed, level.get("rulesets", []))
	_append_rulesets(result, seen, removed, level.get("extra_rulesets", []))
	return result


func _append_rulesets(result: Array[String], seen: Dictionary, removed: Dictionary, raw_rulesets: Variant) -> void:
	if typeof(raw_rulesets) != TYPE_ARRAY:
		return
	for raw_ruleset in raw_rulesets:
		var ruleset_id := String(raw_ruleset)
		if ruleset_id.is_empty() or removed.has(ruleset_id) or seen.has(ruleset_id):
			continue
		seen[ruleset_id] = true
		result.append(ruleset_id)


func _validate_ruleset_id(
	ruleset_id: String,
	context: String,
	global_rulesets: Dictionary,
	mechanic_definitions: Dictionary,
	errors: Array[String]
) -> void:
	if ruleset_id.is_empty():
		errors.append("%s contains an empty ruleset id." % context)
		return
	if not global_rulesets.has(ruleset_id):
		errors.append("%s references unknown global ruleset %s." % [context, ruleset_id])
	if not mechanic_definitions.has(ruleset_id):
		errors.append("%s references missing mechanic definition %s." % [context, ruleset_id])


func _dictionary_field(source: Dictionary, field_name: String, context: String, errors: Array[String]) -> Dictionary:
	var raw_value: Variant = source.get(field_name, {})
	if typeof(raw_value) != TYPE_DICTIONARY:
		errors.append("%s field %s must be a dictionary." % [context, field_name])
		return {}
	return Dictionary(raw_value)


func _dictionary_value(source: Dictionary, key, context: String, errors: Array[String]) -> Dictionary:
	if not source.has(key):
		return {}
	var raw_value: Variant = source[key]
	if typeof(raw_value) != TYPE_DICTIONARY:
		errors.append("%s must be a dictionary." % context)
		return {}
	return Dictionary(raw_value)


func _string_lookup(raw_values: Variant) -> Dictionary:
	var lookup: Dictionary = {}
	if typeof(raw_values) != TYPE_ARRAY:
		return lookup
	for raw_value in raw_values:
		lookup[String(raw_value)] = true
	return lookup


func _string_array(raw_values: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(raw_values) != TYPE_ARRAY:
		return result
	for raw_value in raw_values:
		result.append(String(raw_value))
	return result


func _validate_player_template_against_scene(catalog: Dictionary, errors: Array[String]) -> void:
	var templates_raw: Variant = catalog.get("player_templates", {})
	if typeof(templates_raw) != TYPE_DICTIONARY:
		errors.append("Catalog player_templates must be a dictionary.")
		return

	var default_template := _dictionary_value(templates_raw, "default", "player_templates.default", errors)
	if default_template.is_empty():
		errors.append("Catalog player_templates.default is missing.")
		return

	var shape := _dictionary_value(default_template, "shape", "player_templates.default.shape", errors)
	if shape.is_empty():
		return

	if String(shape.get("type", "")) != "rectangle":
		errors.append("player_templates.default.shape.type must be rectangle.")
		return

	var catalog_offset := _dictionary_value(shape, "offset", "player_templates.default.shape.offset", errors)
	var catalog_size := _dictionary_value(shape, "size", "player_templates.default.shape.size", errors)
	if catalog_offset.is_empty() or catalog_size.is_empty():
		return

	var scene_text := _read_text(PLAYER_SCENE_PATH, errors)
	if scene_text.is_empty():
		return

	var scene_size := _parse_tscn_rect_size(scene_text, PLAYER_COLLISION_SHAPE_ID)
	var scene_offset := _parse_tscn_collision_position(scene_text)
	if scene_size.is_empty() or scene_offset.is_empty():
		errors.append("Could not parse player collision shape from %s." % PLAYER_SCENE_PATH)
		return

	if not _approx_vec2(catalog_offset, scene_offset):
		errors.append(
			"player_templates.default.shape.offset %s does not match %s CollisionShape2D position %s."
			% [catalog_offset, PLAYER_SCENE_PATH, scene_offset]
		)
	if not _approx_vec2(catalog_size, scene_size):
		errors.append(
			"player_templates.default.shape.size %s does not match %s collision size %s."
			% [catalog_size, PLAYER_SCENE_PATH, scene_size]
		)


func _parse_tscn_rect_size(scene_text: String, sub_resource_id: String) -> Dictionary:
	var pattern := (
		'\\[sub_resource type="RectangleShape2D" id="%s"\\][\\s\\S]*?size = Vector2\\(([^,]+), ([^)]+)\\)'
		% sub_resource_id
	)
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return {}
	var match_result := regex.search(scene_text)
	if match_result == null:
		return {}
	return {
		"x": float(match_result.get_string(1)),
		"y": float(match_result.get_string(2)),
	}


func _parse_tscn_collision_position(scene_text: String) -> Dictionary:
	var pattern := (
		'\\[node name="CollisionShape2D" type="CollisionShape2D" parent="\\."[\\s\\S]*?position = Vector2\\(([^,]+), ([^)]+)\\)'
	)
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return {}
	var match_result := regex.search(scene_text)
	if match_result == null:
		return {}
	return {
		"x": float(match_result.get_string(1)),
		"y": float(match_result.get_string(2)),
	}


func _approx_vec2(left: Dictionary, right: Dictionary, epsilon: float = 0.01) -> bool:
	return (
		absf(float(left.get("x", 0.0)) - float(right.get("x", 0.0))) <= epsilon
		and absf(float(left.get("y", 0.0)) - float(right.get("y", 0.0))) <= epsilon
	)
