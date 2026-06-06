extends Control

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const MAP_CARD_SCENE := preload("res://prefabs/ui/map_card.tscn")

@onready var _maps_container: VBoxContainer = $Margin/Vbox/Scroll/Worlds
@onready var _title: Label = $Margin/Vbox/Title


func _ready() -> void:
	if _network_client().get_current_room().is_empty():
		SceneTransition.change_scene("res://scenes/online_menu.tscn")
		return

	if not _network_client().is_room_host():
		SceneTransition.change_scene("res://scenes/room.tscn")
		return

	_title.text = "SELECT MAP"
	_build_map_grid()


func _build_map_grid() -> void:
	while _maps_container.get_child_count() > 0:
		var old: Node = _maps_container.get_child(0)
		_maps_container.remove_child(old)
		old.free()

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 32)
	grid.add_theme_constant_override("v_separation", 32)

	for map_id in GameCatalog.get_map_ids():
		var card: MapCard = MAP_CARD_SCENE.instantiate() as MapCard
		grid.add_child(card)
		card.configure(GameCatalog.get_map_ui_entry(map_id))
		card.map_chosen.connect(_on_map_card_pressed)

	center.add_child(grid)
	_maps_container.add_child(center)


func _on_map_card_pressed(map_id: String) -> void:
	if not GameCatalog.is_map_selectable(map_id):
		return

	_network_client().set_room_map(map_id)
	SceneTransition.change_scene("res://scenes/room.tscn")


func _on_back_butt_pressed() -> void:
	SceneTransition.change_scene("res://scenes/room.tscn")


func _network_client() -> Node:
	return get_node("/root/NetworkClient")
