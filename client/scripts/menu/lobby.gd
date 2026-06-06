extends Control

const STATUS_FONT = preload("res://assets/fonts/EXEPixelPerfect.ttf")
const TITLE_FONT = preload("res://assets/fonts/editundo.ttf")
const BODY_FONT = preload("res://assets/fonts/EXEPixelPerfect.ttf")

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")

@onready var rooms_container: VBoxContainer = $TextureRect2/MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer

var _status_label: Label
var _public_rooms: Array[Dictionary] = []
var _current_room: Dictionary = {}
var _entering_match := false
var _binder := NetworkSignalBinder.new()


func _ready() -> void:
	_status_label = _create_status_label()
	_binder.bind(_network_client().connection_state_changed, _on_connection_state_changed)
	_binder.bind(_network_client().error_received, _on_network_error)
	_binder.bind(_network_client().room_list_updated, _on_room_list_updated)
	_binder.bind(_network_client().current_room_changed, _on_current_room_changed)
	_binder.bind(_network_client().match_started, _on_match_started)
	_public_rooms = _network_client().get_public_rooms()
	_current_room = _network_client().get_current_room()
	_set_status(_network_client().get_status_text())

	if not _current_room.is_empty() and String(_current_room.get("status", "")) != "playing":
		get_tree().change_scene_to_file("res://scenes/room.tscn")
		return

	_render()
	_network_client().request_public_rooms()


func _exit_tree() -> void:
	_binder.unbind_all()


func _on_back_butt_pressed() -> void:
	if not _current_room.is_empty():
		_network_client().leave_room()
	get_tree().change_scene_to_file("res://scenes/online_menu.tscn")


func _on_refresh_butt_pressed() -> void:
	_set_status("Refreshing rooms from %s..." % _network_client().get_server_endpoint())
	_network_client().request_public_rooms()


func _on_connection_state_changed(_state: String, details: String) -> void:
	_set_status(details)


func _on_network_error(code: String, message: String) -> void:
	_set_status(message)
	if code in ["room_not_found", "room_full", "room_in_progress", "room_closed"]:
		_network_client().request_public_rooms()


func _on_room_list_updated(rooms) -> void:
	_public_rooms.clear()
	for room in rooms:
		if typeof(room) == TYPE_DICTIONARY:
			_public_rooms.append(Dictionary(room).duplicate(true))
	_render()


func _on_current_room_changed(room: Dictionary) -> void:
	_current_room = room.duplicate(true)
	if not room.is_empty() and String(room.get("status", "")) != "playing":
		get_tree().change_scene_to_file("res://scenes/room.tscn")
		return

	_render()
	_maybe_enter_match(_current_room)


func _on_match_started(room: Dictionary) -> void:
	_current_room = room.duplicate(true)
	_maybe_enter_match(_current_room)


func _render() -> void:
	_clear_container(rooms_container)
	if not _current_room.is_empty():
		_render_current_room()
	else:
		_render_public_rooms()


func _render_current_room() -> void:
	# Lobby browser only reaches here while match is starting (lobby rooms redirect to room.tscn).
	rooms_container.add_child(_make_heading_label("CURRENT ROOM"))
	rooms_container.add_child(_make_body_label(_room_summary(_current_room)))
	rooms_container.add_child(_make_body_label("Match is starting..."))

	var leave_button := Button.new()
	leave_button.text = "Leave Room"
	leave_button.add_theme_font_override("font", BODY_FONT)
	leave_button.add_theme_font_size_override("font_size", 48)
	leave_button.pressed.connect(_on_leave_room_pressed)
	rooms_container.add_child(leave_button)


func _render_public_rooms() -> void:
	rooms_container.add_child(_make_heading_label("PUBLIC ROOMS"))

	if _public_rooms.is_empty():
		rooms_container.add_child(_make_body_label("No public rooms are available yet."))
		rooms_container.add_child(_make_body_label("Use Host to create one, then come back here."))
		return

	for room in _public_rooms:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 12)
		card.add_child(_make_body_label(_room_summary(room)))

		var join_button := Button.new()
		join_button.text = "Join %s" % String(room.get("room_id", "ROOM"))
		join_button.add_theme_font_override("font", BODY_FONT)
		join_button.add_theme_font_size_override("font_size", 42)
		join_button.disabled = not bool(room.get("joinable", true))
		join_button.pressed.connect(_on_join_public_room.bind(String(room.get("room_id", ""))))
		card.add_child(join_button)

		rooms_container.add_child(card)


func _on_join_public_room(room_id: String) -> void:
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
	get_tree().change_scene_to_file("res://scenes/online/online_game.tscn")


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
	return label


func _network_client() -> Node:
	return get_node("/root/NetworkClient")
