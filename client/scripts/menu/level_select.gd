extends Control

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const LevelCardScene = preload("res://prefabs/ui/level_card.tscn")

const CARDS_PER_PAGE := 5

signal overlay_closed
signal level_change_confirmed(level_index: int)

@export var overlay_mode := false

@onready var _map_title: Label = $Content/MapTitle
@onready var _left_arrow: TextureButton = $Content/NavRow/LeftArrow
@onready var _right_arrow: TextureButton = $Content/NavRow/RightArrow
@onready var _cards_row: HBoxContainer = $Content/NavRow/CardsRow
@onready var _option_panel: Control = $OptionPanel
@onready var _overlay_dim: ColorRect = $OverlayDim

var _level_ids: Array[String] = []
var _map_id := GameCatalog.DEFAULT_MAP_ID
var _page_index := 0
var _selected_level_index := 0
var _level_cards: Array[LevelCard] = []
var _pending_level_change := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS if overlay_mode else process_mode
	if overlay_mode:
		visible = false

	_option_panel.visibility_changed.connect(_refresh_overlay_dim)
	_bind_network_signals()
	_load_from_current_room()


func open_overlay() -> void:
	if not overlay_mode:
		return

	if not _load_from_current_room():
		return

	_pending_level_change = false
	visible = true


func _load_from_current_room() -> bool:
	var room: Dictionary = _network_client().get_current_room()
	if room.is_empty():
		if not overlay_mode:
			SceneTransition.change_scene("res://scenes/online_menu.tscn")
		return false

	if not _network_client().is_room_host():
		if not overlay_mode:
			SceneTransition.change_scene(_return_scene_path())
		return false

	_map_id = String(room.get("map_id", GameCatalog.DEFAULT_MAP_ID))
	_level_ids = _level_ids_for_room(room)
	_selected_level_index = clampi(int(room.get("current_level_index", 0)), 0, maxi(_level_ids.size() - 1, 0))
	_page_index = _page_index_for_level(_selected_level_index)

	_build_level_cards()
	_refresh_page()
	_refresh_overlay_dim()
	return true


func _exit_tree() -> void:
	_unbind_network_signals()


func _unhandled_input(event: InputEvent) -> void:
	if overlay_mode and not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		if _option_panel.visible:
			_option_panel.hide()
		elif overlay_mode:
			_close_overlay()
		else:
			SceneTransition.change_scene(_return_scene_path())
		get_viewport().set_input_as_handled()
		return

	if _pending_level_change or _option_panel.visible or _level_ids.is_empty():
		return

	if event.is_action_pressed("ui_left"):
		_move_selection(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_move_selection(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_choose_selected_level()
		get_viewport().set_input_as_handled()


func _build_level_cards() -> void:
	_level_cards.clear()
	for child in _cards_row.get_children():
		_cards_row.remove_child(child)
		child.queue_free()

	for slot in range(CARDS_PER_PAGE):
		var card: LevelCard = LevelCardScene.instantiate() as LevelCard
		card.name = "LevelCard%d" % (slot + 1)
		card.level_chosen.connect(_on_level_card_chosen)
		_cards_row.add_child(card)
		_level_cards.append(card)


func _refresh_page() -> void:
	var map_title := GameCatalog.get_map_title(_map_id)
	_map_title.text = map_title

	var page_start := _page_index * CARDS_PER_PAGE
	var page_end := mini(page_start + CARDS_PER_PAGE, _level_ids.size())
	for slot in range(CARDS_PER_PAGE):
		var card := _level_cards[slot]
		var level_index := page_start + slot
		if level_index >= _level_ids.size():
			card.configure({
				"visible": false,
				"enabled": false,
				"level_index": -1,
				"selected": false,
			})
			continue

		card.configure({
			"visible": true,
			"enabled": true,
			"level_index": level_index,
			"level_id": _level_ids[level_index],
			"selected": level_index == _selected_level_index,
		})

	_left_arrow.disabled = _page_index <= 0
	_right_arrow.disabled = page_end >= _level_ids.size()


func _refresh_selection() -> void:
	var page_start := _page_index * CARDS_PER_PAGE
	for slot in range(CARDS_PER_PAGE):
		var card := _level_cards[slot]
		if not card.visible:
			continue
		card.set_highlighted(card.level_index == _selected_level_index)


func _move_selection(delta: int) -> void:
	if _level_ids.is_empty():
		return

	var next_index := clampi(_selected_level_index + delta, 0, _level_ids.size() - 1)
	if next_index == _selected_level_index:
		return

	_selected_level_index = next_index
	var next_page := _page_index_for_level(_selected_level_index)
	if next_page != _page_index:
		_page_index = next_page
		_refresh_page()
	else:
		_refresh_selection()


func _go_to_previous_page() -> void:
	if _page_index <= 0:
		return

	_page_index -= 1
	_selected_level_index = clampi(_page_index * CARDS_PER_PAGE, 0, _level_ids.size() - 1)
	_refresh_page()


func _go_to_next_page() -> void:
	if _page_index >= _max_page_index():
		return

	_page_index += 1
	_selected_level_index = clampi(_page_index * CARDS_PER_PAGE, 0, _level_ids.size() - 1)
	_refresh_page()


func _on_back_butt_pressed() -> void:
	if overlay_mode:
		_close_overlay()
		return

	SceneTransition.change_scene(_return_scene_path())


func _on_option_butt_pressed() -> void:
	if _option_panel.has_method("reload_settings"):
		_option_panel.reload_settings()
	_option_panel.show()
	_refresh_overlay_dim()


func _on_left_arrow_pressed() -> void:
	_go_to_previous_page()


func _on_right_arrow_pressed() -> void:
	_go_to_next_page()


func _on_level_card_chosen(level_index: int) -> void:
	_selected_level_index = level_index
	_refresh_selection()
	_choose_selected_level()


func _choose_selected_level() -> void:
	if _selected_level_index < 0 or _selected_level_index >= _level_ids.size():
		return

	if _is_match_active():
		_pending_level_change = true
		_network_client().set_room_level(_selected_level_index)
		return

	_refresh_selection()


func _refresh_overlay_dim() -> void:
	_overlay_dim.visible = _option_panel.visible


func _bind_network_signals() -> void:
	var network_client := _network_client()
	var on_transition := Callable(self, "_on_level_transition")
	if not network_client.level_transition.is_connected(on_transition):
		network_client.level_transition.connect(on_transition)

	var on_error := Callable(self, "_on_network_error")
	if not network_client.error_received.is_connected(on_error):
		network_client.error_received.connect(on_error)


func _unbind_network_signals() -> void:
	var network_client := _network_client()
	var on_transition := Callable(self, "_on_level_transition")
	if network_client.level_transition.is_connected(on_transition):
		network_client.level_transition.disconnect(on_transition)

	var on_error := Callable(self, "_on_network_error")
	if network_client.error_received.is_connected(on_error):
		network_client.error_received.disconnect(on_error)


func _on_level_transition(_from_level_index: int, to_level_index: int, _match_complete: bool, _room: Dictionary) -> void:
	if not _pending_level_change:
		return

	_pending_level_change = false
	_selected_level_index = to_level_index
	if overlay_mode:
		level_change_confirmed.emit(to_level_index)
		_close_overlay()
		return

	SceneTransition.change_scene("res://scenes/online/online_game.tscn")


func _on_network_error(_code: String, _message: String) -> void:
	_pending_level_change = false


func _close_overlay() -> void:
	_pending_level_change = false
	if _option_panel != null:
		_option_panel.hide()
	visible = false
	overlay_closed.emit()


func _level_ids_for_room(room: Dictionary) -> Array[String]:
	var raw_level_ids = room.get("level_ids", [])
	if typeof(raw_level_ids) == TYPE_ARRAY and not (raw_level_ids as Array).is_empty():
		var result: Array[String] = []
		for raw_level_id in raw_level_ids:
			result.append(String(raw_level_id))
		return result
	return GameCatalog.get_level_ids(_map_id)


func _page_index_for_level(level_index: int) -> int:
	if _level_ids.is_empty():
		return 0
	return level_index / CARDS_PER_PAGE


func _max_page_index() -> int:
	if _level_ids.is_empty():
		return 0
	return maxi(0, int(ceil(float(_level_ids.size()) / float(CARDS_PER_PAGE))) - 1)


func _return_scene_path() -> String:
	return "res://scenes/online/online_game.tscn" if _is_match_active() else "res://scenes/world_select.tscn"


func _is_match_active() -> bool:
	if _network_client().has_method("is_match_active"):
		return bool(_network_client().is_match_active())
	var room: Dictionary = _network_client().get_current_room()
	return String(room.get("status", "")) == "playing"


func _network_client() -> Node:
	return get_node("/root/NetworkClient")
