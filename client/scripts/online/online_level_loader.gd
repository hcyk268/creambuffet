extends RefCounted
class_name OnlineLevelLoader

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const OnlineLevelResolver = preload("res://scripts/online/online_level_resolver.gd")
const OnlinePushableSync = preload("res://scripts/online/online_pushable_sync.gd")


func configure_online_levels(room: Dictionary) -> Dictionary:
	var resolved := OnlineLevelResolver.configure_online_levels(room)
	var runtime_levels: Array[PackedScene] = []
	var raw_levels: Variant = resolved.get("levels", [])
	if typeof(raw_levels) == TYPE_ARRAY:
		for raw_level in raw_levels:
			if raw_level is PackedScene:
				runtime_levels.append(raw_level)

	var online_level_ids: Array[String] = []
	var raw_level_ids: Variant = resolved.get("level_ids", [])
	if typeof(raw_level_ids) == TYPE_ARRAY:
		for raw_level_id in raw_level_ids:
			online_level_ids.append(String(raw_level_id))

	return {
		"levels": runtime_levels,
		"level_ids": online_level_ids,
		"map_id": String(resolved.get("map_id", GameCatalog.DEFAULT_MAP_ID)),
	}


func load_level(
	level_container: Node,
	previous_level: Node,
	player: CharacterBody2D,
	remote_registry,
	synced_node_registry,
	is_online_session: bool,
	levels: Array[PackedScene],
	online_level_ids: Array[String],
	index: int,
	room: Dictionary = {}
) -> Dictionary:
	if index < 0:
		return {
			"ok": false,
			"message": "Invalid level index: %d" % index,
		}

	var level_scene := OnlineLevelResolver.scene_for_index(is_online_session, levels, online_level_ids, index, room)
	if level_scene == null:
		return {
			"ok": false,
			"message": "No level scene found for index: %d" % index,
		}

	if is_instance_valid(previous_level):
		previous_level.queue_free()

	var level_root := level_scene.instantiate()
	level_container.add_child(level_root)

	var level_id := OnlineLevelResolver.level_id_for_index(is_online_session, online_level_ids, index, room)
	_setup_player_spawn(player, level_root)
	if remote_registry != null:
		remote_registry.reset_to_spawn()
	_register_synced_nodes(synced_node_registry, level_root, level_id)
	OnlinePushableSync.configure_pushables(level_root)
	OnlinePushableSync.configure_buttons(level_root)
	OnlinePushableSync.configure_water_objects(level_root)

	return {
		"ok": true,
		"level": level_root,
		"level_index": index,
		"level_id": level_id,
	}


func finalize_level_spawn(current_level: Node, player: CharacterBody2D, remote_registry) -> void:
	if not is_instance_valid(current_level):
		return

	if player != null and player.has_method("respawn"):
		player.respawn()
	if remote_registry != null:
		remote_registry.reset_to_spawn()


func _setup_player_spawn(player: CharacterBody2D, level_root: Node) -> void:
	if player == null:
		return

	var spawn_point := level_root.get_node_or_null("SpawnPoint")
	if spawn_point is Node2D:
		player.global_position = spawn_point.global_position
	else:
		player.global_position = Vector2.ZERO

	if player.has_method("set_input_enabled"):
		player.set_input_enabled(true)
	if player.has_method("set_eliminated"):
		player.set_eliminated(false)
	player.velocity = Vector2.ZERO
	player.spawn_position = player.global_position
	if player.has_method("reset_oxygen"):
		player.reset_oxygen()
	if player.has_method("set_key_count"):
		player.set_key_count(0)
	else:
		player.key_count = 0


func _register_synced_nodes(synced_node_registry, level_root: Node, level_id: String) -> void:
	if synced_node_registry == null:
		return

	var level_def := GameCatalog.get_level(level_id)
	synced_node_registry.register_level(level_root, level_id, level_def)
