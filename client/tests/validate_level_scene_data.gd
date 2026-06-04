extends SceneTree

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const GameIds = preload("res://scripts/catalog/game_ids.gd")
const SyncedNodeRegistry = preload("res://scripts/online/synced_node_registry.gd")

const POSITION_EPSILON := 0.05
const ROTATION_EPSILON := 0.001


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
		print("Level scene data validation passed.")
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

	_validate_spawn_point(level_id, level_root, level_definition, errors)
	var synced_nodes := _collect_synced_nodes(level_root)
	_validate_object_transforms(level_id, level_definition, synced_nodes, errors)
	level_root.free()


func _validate_spawn_point(level_id: String, level_root: Node, level_definition: Dictionary, errors: Array[String]) -> void:
	var spawn_point := level_root.get_node_or_null("SpawnPoint") as Node2D
	if spawn_point == null:
		errors.append("Level %s is missing SpawnPoint in scene." % level_id)
		return

	var spawn_raw: Variant = level_definition.get("spawn_point", {})
	if typeof(spawn_raw) != TYPE_DICTIONARY:
		errors.append("Level %s is missing catalog spawn_point." % level_id)
		return

	var expected := _vector_from_dictionary(Dictionary(spawn_raw))
	if not _positions_match(spawn_point.global_position, expected):
		errors.append(
			"Level %s SpawnPoint mismatch: scene=%s catalog=%s." %
			[level_id, _vector_label(spawn_point.global_position), _vector_label(expected)]
		)


func _collect_synced_nodes(level_root: Node) -> Dictionary:
	var synced_nodes: Dictionary = {}
	_collect_synced_nodes_recursive(level_root, synced_nodes)
	return synced_nodes


func _collect_synced_nodes_recursive(node: Node, synced_nodes: Dictionary) -> void:
	var sync_id := SyncedNodeRegistry.node_sync_id(node)
	if not sync_id.is_empty():
		synced_nodes[sync_id] = node

	for child in node.get_children():
		if child is Node:
			_collect_synced_nodes_recursive(child, synced_nodes)


func _validate_object_transforms(level_id: String, level_definition: Dictionary, synced_nodes: Dictionary, errors: Array[String]) -> void:
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
		if not _object_kind_requires_scene_alignment(kind):
			continue
		if not synced_nodes.has(target_id):
			continue

		var raw_node: Variant = synced_nodes[target_id]
		if not (raw_node is Node2D):
			errors.append("Level %s target %s is not a Node2D in scene." % [level_id, target_id])
			continue
		var node := raw_node as Node2D

		var transform_raw: Variant = object_data.get("transform", {})
		if typeof(transform_raw) != TYPE_DICTIONARY:
			continue
		var transform: Dictionary = transform_raw

		var expected_position_raw: Variant = transform.get("position", {})
		if typeof(expected_position_raw) == TYPE_DICTIONARY:
			var expected_position := _vector_from_dictionary(Dictionary(expected_position_raw))
			var actual_position := node.global_position
			if not _positions_match(actual_position, expected_position):
				errors.append(
					"Level %s target %s position mismatch: scene=%s catalog=%s." %
					[level_id, target_id, _vector_label(actual_position), _vector_label(expected_position)]
				)

		if transform.has("rotation"):
			var expected_rotation := float(transform.get("rotation", 0.0))
			var actual_rotation := node.global_rotation
			if not is_equal_approx(actual_rotation, expected_rotation) and absf(actual_rotation - expected_rotation) > ROTATION_EPSILON:
				errors.append(
					"Level %s target %s rotation mismatch: scene=%.5f catalog=%.5f." %
					[level_id, target_id, actual_rotation, expected_rotation]
				)


func _object_kind_requires_scene_alignment(kind: String) -> bool:
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


func _vector_from_dictionary(raw_vector: Dictionary) -> Vector2:
	return Vector2(float(raw_vector.get("x", 0.0)), float(raw_vector.get("y", 0.0)))


func _positions_match(actual: Vector2, expected: Vector2) -> bool:
	return actual.distance_to(expected) <= POSITION_EPSILON


func _vector_label(value: Vector2) -> String:
	return "(%.3f, %.3f)" % [value.x, value.y]
