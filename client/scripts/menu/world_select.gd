extends Control

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const DISPLAY_MAP_IDS := ["beginner", "ice", "water", "dark", "lava"]
const MAP_BACKGROUNDS := {
	"beginner": preload("res://assets/sprites/UI-BackgroundMap1.png"),
	"ice": preload("res://assets/sprites/UI-BackgroundMap2.png"),
	"water": preload("res://assets/sprites/UI-BackgroundMap3.png"),
	"dark": preload("res://assets/sprites/UI-BackgroundMap4.png"),
}

@onready var _map_card: MapCard = $Content/NavRow/MapCard
@onready var _world_title: Label = $Content/WorldTitle
@onready var _option_panel: Control = $OptionPanel
@onready var _overlay_dim: ColorRect = $OverlayDim

var _map_ids: Array[String] = []
var _selected_index := 0


func _ready() -> void:
	var room: Dictionary = _network_client().get_current_room()
	if room.is_empty():
		SceneTransition.change_scene("res://scenes/online_menu.tscn")
		return

	if not _network_client().is_room_host():
		SceneTransition.change_scene("res://scenes/room.tscn")
		return

	_option_panel.visibility_changed.connect(_refresh_overlay_dim)
	_map_card.map_chosen.connect(_on_map_card_chosen)
	_build_map_list()
	_selected_index = _index_for_map(String(room.get("map_id", GameCatalog.DEFAULT_MAP_ID)))
	_refresh_selected_map()
	_refresh_overlay_dim()


func _unhandled_input(event: InputEvent) -> void:
	if _option_panel.visible:
		return

	if event.is_action_pressed("ui_left"):
		_select_previous_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_select_next_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_choose_selected_map()
		get_viewport().set_input_as_handled()


func _build_map_list() -> void:
	_map_ids.clear()
	for map_id in DISPLAY_MAP_IDS:
		if GameCatalog.has_map(map_id):
			_map_ids.append(map_id)

	if not _map_ids.is_empty():
		return

	for map_id in GameCatalog.get_map_ids():
		_map_ids.append(map_id)


func _refresh_selected_map() -> void:
	if _map_ids.is_empty():
		_map_card.configure({})
		_world_title.text = ""
		return

	var map_id := _map_ids[_selected_index]
	_map_card.configure(_map_card_entry(map_id))
	_world_title.text = GameCatalog.get_map_title(map_id)


func _select_previous_map() -> void:
	_set_selected_index(_selected_index - 1)


func _select_next_map() -> void:
	_set_selected_index(_selected_index + 1)


func _set_selected_index(index: int) -> void:
	if _map_ids.is_empty():
		return

	_selected_index = (index % _map_ids.size() + _map_ids.size()) % _map_ids.size()
	_refresh_selected_map()


func _choose_selected_map() -> void:
	if _map_ids.is_empty():
		return

	var map_id := _map_ids[_selected_index]
	_network_client().set_room_map(map_id)
	SceneTransition.change_scene("res://scenes/room.tscn")


func _on_left_arrow_pressed() -> void:
	_select_previous_map()


func _on_right_arrow_pressed() -> void:
	_select_next_map()


func _on_map_card_chosen(_map_id: String) -> void:
	_choose_selected_map()


func _on_back_butt_pressed() -> void:
	SceneTransition.change_scene("res://scenes/room.tscn")


func _on_option_butt_pressed() -> void:
	if _option_panel.has_method("reload_settings"):
		_option_panel.reload_settings()
	_option_panel.show()
	_refresh_overlay_dim()


func _refresh_overlay_dim() -> void:
	_overlay_dim.visible = _option_panel.visible


func _index_for_map(map_id: String) -> int:
	var normalized := GameCatalog.normalize_map_id(map_id)
	for index in range(_map_ids.size()):
		if _map_ids[index] == normalized:
			return index
	return 0


func _map_card_entry(map_id: String) -> Dictionary:
	var entry := GameCatalog.get_map_ui_entry(map_id)
	entry["thumbnail_texture"] = _texture_for_map(map_id)
	entry["selectable"] = true
	entry["wip"] = false
	return entry


func _texture_for_map(map_id: String) -> Texture2D:
	var texture: Texture2D = MAP_BACKGROUNDS.get(map_id, null)
	if texture != null:
		return texture

	var thumbnail_path := GameCatalog.get_map_thumbnail_path(map_id)
	if thumbnail_path.is_empty() or not ResourceLoader.exists(thumbnail_path):
		return null
	return load(thumbnail_path) as Texture2D


func _network_client() -> Node:
	return get_node("/root/NetworkClient")
