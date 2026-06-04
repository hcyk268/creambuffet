extends SceneTree

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const GameIds = preload("res://scripts/catalog/game_ids.gd")
const SyncedNodeRegistry = preload("res://scripts/online/synced_node_registry.gd")


func _init() -> void:
	var errors: Array[String] = []
	var validated_levels: Dictionary = {}

	for map_id in GameCatalog.get_map_ids():
		for level_id in GameCatalog.get_level_ids(map_id):
			if validated_levels.has(level_id):
				continue
			validated_levels[level_id] = true
			_validate_level(level_id, errors)

	if errors.is_empty():
		print("Sync ID validation passed.")
		quit(0)
		return

	for error in errors:
		push_error(error)
	quit(1)


func _validate_level(level_id: String, errors: Array[String]) -> void:
	var level_definition := GameCatalog.get_level(level_id)
	if level_definition.is_empty():
		errors.append("Level %s is missing from GameCatalog." % level_id)
		return

	var scene_path := String(level_definition.get("scene_path", "")).strip_edges()
	if scene_path.is_empty():
		errors.append("Level %s is missing scene_path." % level_id)
		return
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		errors.append("Level %s scene_path does not resolve to a PackedScene: %s." % [level_id, scene_path])
		return

	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		errors.append("Level %s could not load scene %s." % [level_id, scene_path])
		return

	var level_root := packed_scene.instantiate()
	if level_root == null:
		errors.append("Level %s could not instantiate scene %s." % [level_id, scene_path])
		return

	var sync_id_paths: Dictionary = {}
	_collect_sync_coverage(level_root, level_id, sync_id_paths, errors)
	_validate_catalog_object_sync_ids(level_id, scene_path, level_definition, sync_id_paths, errors)
	level_root.free()


func _collect_sync_coverage(node: Node, level_id: String, sync_id_paths: Dictionary, errors: Array[String], parent_path: String = "") -> void:
	var sync_id := SyncedNodeRegistry.node_sync_id(node)
	var node_path := _node_path_label(node, parent_path)

	if not sync_id.is_empty():
		if sync_id_paths.has(sync_id):
			errors.append(
				"Level %s has duplicate sync_id %s on %s and %s." %
				[level_id, sync_id, String(sync_id_paths[sync_id]), node_path]
			)
		else:
			sync_id_paths[sync_id] = node_path

	if _node_requires_sync_id(node) and sync_id.is_empty():
		errors.append("Level %s network-relevant node %s is missing sync_id." % [level_id, node_path])

	for child in node.get_children():
		if child is Node:
			_collect_sync_coverage(child, level_id, sync_id_paths, errors, node_path)


func _validate_catalog_object_sync_ids(
	level_id: String,
	scene_path: String,
	level_definition: Dictionary,
	sync_id_paths: Dictionary,
	errors: Array[String]
) -> void:
	var objects_raw: Variant = level_definition.get("objects", {})
	if typeof(objects_raw) != TYPE_DICTIONARY:
		return

	var objects: Dictionary = objects_raw
	for raw_target_id in objects.keys():
		var target_id := String(raw_target_id)
		var object_data_raw: Variant = objects.get(raw_target_id, {})
		if typeof(object_data_raw) != TYPE_DICTIONARY:
			continue

		var object_data: Dictionary = object_data_raw
		var kind := String(object_data.get("kind", "")).strip_edges()
		if not _object_kind_requires_sync_id(kind):
			continue
		if not sync_id_paths.has(target_id):
			errors.append(
				"Level %s catalog object %s (%s) has no matching sync_id in %s." %
				[level_id, target_id, kind, scene_path]
			)


func _node_requires_sync_id(node: Node) -> bool:
	for raw_group_name in SyncedNodeRegistry.NETWORK_GROUPS:
		var group_name := StringName(String(raw_group_name))
		if node.is_in_group(group_name):
			return true
	return false


func _object_kind_requires_sync_id(kind: String) -> bool:
	if kind == GameIds.OBJECT_KIND_KEY:
		return true
	if GameIds.is_door_kind(kind):
		return true
	if kind == GameIds.OBJECT_KIND_GOAL:
		return true
	if kind == GameIds.OBJECT_KIND_PUSH_BOX:
		return true
	if kind == GameIds.OBJECT_KIND_MOVING_PLATFORM:
		return true
	if GameIds.is_button_kind(kind):
		return true
	if GameIds.is_oxygen_source_kind(kind):
		return true
	if GameIds.is_water_jet_kind(kind):
		return true
	if GameIds.is_barrier_kind(kind):
		return true
	if GameIds.is_hazard_kind(kind):
		return true
	return false


func _node_path_label(node: Node, parent_path: String) -> String:
	if parent_path.is_empty():
		return str(node.name)
	return "%s/%s" % [parent_path, node.name]
