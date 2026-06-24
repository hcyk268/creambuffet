extends Control

const STATUS_FONT = preload("res://assets/fonts/EXEPixelPerfect.ttf")
const TITLE_FONT = preload("res://assets/fonts/editundo.ttf")
const BODY_FONT = preload("res://assets/fonts/EXEPixelPerfect.ttf")

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const LobbyRoomCard = preload("res://scripts/menu/lobby_room_card.gd")

@onready var empty_state_panel: Control = $TextureRect2/MarginContainer/VBoxContainer/ContentArea/EmptyStatePanel
@onready var rooms_scroll: ScrollContainer = $TextureRect2/MarginContainer/VBoxContainer/ContentArea/RoomsScroll
@onready var rooms_list: VBoxContainer = $TextureRect2/MarginContainer/VBoxContainer/ContentArea/RoomsScroll/RoomsList

var _status_label: Label
var _public_rooms: Array[Dictionary] = []
var _current_room: Dictionary = {}
var _entering_match := false
var _joining_room := false
var _binder := NetworkSignalBinder.new()


func _ready() -> void:
	_status_label = _create_status_label()
	_binder.bind(_network_client().connection_state_changed, _on_connection_state_changed)
	_binder.bind(_network_client().error_received, _on_network_error)
	_binder.bind(_network_client().room_list_updated, _on_room_list_updated)
	_binder.bind(_network_client().current_room_changed, _on_current_room_changed)
	_binder.bind(_network_client().match_started, _on_match_started)
	var on_ping := Callable(self, "_on_ping_updated")
	if not _network_client().ping_updated.is_connected(on_ping):
		_network_client().ping_updated.connect(on_ping)
	_public_rooms = _network_client().get_public_rooms()
	_current_room = _network_client().get_current_room()

	if not _current_room.is_empty() and String(_current_room.get("status", "")) != "playing":
		SceneTransition.change_scene("res://scenes/room.tscn")
		return

	_render()
	_network_client().request_public_rooms()


func _exit_tree() -> void:
	var on_ping := Callable(self, "_on_ping_updated")
	if _network_client().ping_updated.is_connected(on_ping):
		_network_client().ping_updated.disconnect(on_ping)
	_binder.unbind_all()


func _on_back_butt_pressed() -> void:
	if not _current_room.is_empty():
		_network_client().leave_room()
	SceneTransition.change_scene("res://scenes/online_menu.tscn")


func _on_refresh_butt_pressed() -> void:
	_network_client().request_public_rooms()


func _on_connection_state_changed(_state: String, _details: String) -> void:
	pass


func _on_network_error(code: String, message: String) -> void:
	_joining_room = false
	_set_status(message)
	if code in ["room_not_found", "room_full", "room_in_progress", "room_closed"]:
		_network_client().request_public_rooms()


func _on_room_list_updated(rooms) -> void:
	_public_rooms.clear()
	for room in rooms:
		if typeof(room) == TYPE_DICTIONARY:
			_public_rooms.append(Dictionary(room).duplicate(true))
	_set_status("")
	_render()


func _on_current_room_changed(room: Dictionary) -> void:
	_current_room = room.duplicate(true)
	_joining_room = false

	if room.is_empty():
		_set_status("")
		_render()
		return

	if String(room.get("status", "")) == "playing":
		_maybe_enter_match(_current_room)
		return

	SceneTransition.change_scene("res://scenes/room.tscn")


func _on_match_started(room: Dictionary) -> void:
	_current_room = room.duplicate(true)
	_maybe_enter_match(_current_room)


func _on_ping_updated(_ping_ms: int) -> void:
	if _current_room.is_empty() and not _public_rooms.is_empty() and rooms_scroll.visible:
		_render_public_rooms()


func _render() -> void:
	_clear_container(rooms_list)

	if not _current_room.is_empty() and String(_current_room.get("status", "")) == "playing":
		_show_rooms_panel()
		_render_current_room()
		return

	if _public_rooms.is_empty():
		_show_empty_panel()
		return

	_show_rooms_panel()
	_render_public_rooms()


func _render_public_rooms() -> void:
	_clear_container(rooms_list)
	var ping_ms := _local_ping_ms()

	for room in _public_rooms:
		var row := CenterContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size.y = 120.0

		var card := LobbyRoomCard.new()
		card.setup(room, ping_ms)
		var room_id := String(room.get("room_id", ""))
		card.disabled = _joining_room
		card.pressed.connect(_on_join_public_room.bind(room_id))

		row.add_child(card)
		rooms_list.add_child(row)


func _show_empty_panel() -> void:
	empty_state_panel.visible = true
	rooms_scroll.visible = false


func _show_rooms_panel() -> void:
	empty_state_panel.visible = false
	rooms_scroll.visible = true


func _render_current_room() -> void:
	# Lobby browser only reaches here while match is starting (lobby rooms redirect to room.tscn).
	rooms_list.add_child(_make_heading_label("CURRENT ROOM"))
	rooms_list.add_child(_make_body_label(_room_summary(_current_room)))
	rooms_list.add_child(_make_body_label("Match is starting..."))

	var leave_button := Button.new()
	leave_button.text = "Leave Room"
	leave_button.add_theme_font_override("font", BODY_FONT)
	leave_button.add_theme_font_size_override("font_size", 48)
	leave_button.pressed.connect(_on_leave_room_pressed)
	rooms_list.add_child(leave_button)


func _local_ping_ms() -> int:
	if _network_client().has_method("get_ping_ms"):
		return int(_network_client().get_ping_ms())
	return -1


func _on_join_public_room(room_id: String) -> void:
	if _joining_room:
		return

	_joining_room = true
	_set_status("Joining room %s..." % room_id)
	_network_client().join_room(room_id)


func _on_leave_room_pressed() -> void:
	_set_status("Leaving room...")
	_network_client().leave_room()


func _maybe_enter_match(room: Dictionary) -> void:
	if _entering_match or room.is_empty():
		return

	if String(room.get("status", "")) != "playing":
		return

	_entering_match = true
	call_deferred("_change_to_game_scene")


func _change_to_game_scene() -> void:
	SceneTransition.change_scene("res://scenes/online/online_game.tscn")


func _room_summary(room: Dictionary) -> String:
	var map_id := String(room.get("map_id", GameCatalog.DEFAULT_MAP_ID))
	var map_title := GameCatalog.get_map_title(map_id)
	return "Room %s | %d/%d players | %s (%d levels)" % [
		String(room.get("room_id", "ROOM")),
		int(room.get("player_count", 0)),
		int(room.get("max_players", 1)),
		map_title,
		int(room.get("world_count", 0)),
	]


func _clear_container(container: VBoxContainer) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _make_heading_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var settings := LabelSettings.new()
	settings.font = TITLE_FONT
	settings.font_size = 52
	settings.font_color = Color(0.17, 0.14, 0.09)
	label.label_settings = settings

	return label


func _make_body_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var settings := LabelSettings.new()
	settings.font = BODY_FONT
	settings.font_size = 34
	settings.font_color = Color(0.17, 0.14, 0.09)
	label.label_settings = settings

	return label


func _set_status(message: String) -> void:
	if _status_label == null:
		return

	_status_label.text = message
	_status_label.visible = not message.is_empty()


func _create_status_label() -> Label:
	var label := Label.new()
	label.name = "StatusLabel"
	label.anchor_left = 0.5
	label.anchor_top = 1.0
	label.anchor_right = 0.5
	label.anchor_bottom = 1.0
	label.offset_left = -650.0
	label.offset_top = -150.0
	label.offset_right = 650.0
	label.offset_bottom = -70.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var settings := LabelSettings.new()
	settings.font = STATUS_FONT
	settings.font_size = 30
	settings.font_color = Color(0.17, 0.14, 0.09)
	label.label_settings = settings

	add_child(label)
	label.visible = false
	return label


func _network_client() -> Node:
	return get_node("/root/NetworkClient")
