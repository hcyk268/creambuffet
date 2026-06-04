extends RefCounted
class_name OnlineLevelResolver

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")


static func configure_online_levels(room: Dictionary) -> Dictionary:
	var map_id := String(room.get("map_id", GameCatalog.DEFAULT_MAP_ID))
	var level_ids := GameCatalog.get_level_ids(map_id)
	var runtime_levels: Array[PackedScene] = []
	var online_level_ids: Array[String] = []

	for level_id in level_ids:
		var level_def := GameCatalog.get_level(level_id)
		var scene_path := String(level_def.get("scene_path", "")).strip_edges()
		if scene_path.is_empty():
			push_warning("Skipping level %s because scene_path is missing." % level_id)
			continue

		var packed_scene := load(scene_path) as PackedScene
		if packed_scene == null:
			push_warning("Skipping level %s because scene could not be loaded: %s" % [level_id, scene_path])
			continue

		runtime_levels.append(packed_scene)
		online_level_ids.append(level_id)

	return {
		"levels": runtime_levels,
		"level_ids": online_level_ids,
		"map_id": map_id,
	}


static func scene_for_index(
	is_online_session: bool,
	levels: Array[PackedScene],
	online_level_ids: Array[String],
	index: int,
	room: Dictionary = {}
) -> PackedScene:
	if is_online_session:
		var level_id := level_id_for_index(is_online_session, online_level_ids, index, room)
		var level_def := GameCatalog.get_level(level_id)
		var scene_path := String(level_def.get("scene_path", "")).strip_edges()
		if not scene_path.is_empty():
			var loaded_scene := load(scene_path) as PackedScene
			if loaded_scene != null:
				return loaded_scene
			push_warning("Could not load catalog scene_path for %s: %s" % [level_id, scene_path])

	if index >= 0 and index < levels.size():
		return levels[index]

	return null


static func level_id_for_index(is_online_session: bool, online_level_ids: Array[String], index: int, room: Dictionary = {}) -> String:
	if is_online_session:
		if index >= 0 and index < online_level_ids.size():
			return online_level_ids[index]

		var level_ids = room.get("level_ids", [])
		if typeof(level_ids) == TYPE_ARRAY and index >= 0 and index < level_ids.size():
			return String(level_ids[index])

		var map_id := String(room.get("map_id", GameCatalog.DEFAULT_MAP_ID))
		var catalog_level_id := GameCatalog.get_level_id_by_index(map_id, index)
		if not catalog_level_id.is_empty():
			return catalog_level_id

	return GameCatalog.get_level_id_by_index(GameCatalog.DEFAULT_MAP_ID, index)


static func index_for_level_id(
	is_online_session: bool,
	online_level_ids: Array[String],
	level_id: String,
	fallback_index: int,
	room: Dictionary = {}
) -> int:
	if level_id.is_empty():
		return fallback_index

	if is_online_session:
		if level_id in online_level_ids:
			return online_level_ids.find(level_id)

		var level_ids = room.get("level_ids", [])
		if typeof(level_ids) == TYPE_ARRAY:
			for index in range(level_ids.size()):
				if String(level_ids[index]) == level_id:
					return index

		var catalog_index := GameCatalog.get_level_index(String(room.get("map_id", GameCatalog.DEFAULT_MAP_ID)), level_id)
		if catalog_index >= 0:
			return catalog_index

	return fallback_index
