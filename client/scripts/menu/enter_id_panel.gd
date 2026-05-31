extends Control

const STATUS_FONT = preload("res://assets/fonts/EXEPixelPerfect.ttf")

@onready var id_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/LineEdit

var _awaiting_join := false
var _status_label: Label


func _ready() -> void:
	id_input.clear()
	_status_label = _create_status_label()
	_bind_network_signals()
	_set_status("Join a room on %s." % _network_client().get_server_endpoint())


func _exit_tree() -> void:
	_unbind_network_signals()


func _on_back_butt_pressed() -> void:
	_awaiting_join = false
	hide()
	id_input.clear()
	_set_status("Join a room on %s." % _network_client().get_server_endpoint())


func _on_join_butt_pressed() -> void:
	var room_id: String = id_input.text.strip_edges()
	if room_id.is_empty():
		_set_status("Please enter a room id.")
		return

	_awaiting_join = true
	_set_status("Joining room %s..." % room_id.to_upper())
	_network_client().join_room(room_id)


func _bind_network_signals() -> void:
	var on_state := Callable(self, "_on_connection_state_changed")
	if not _network_client().connection_state_changed.is_connected(on_state):
		_network_client().connection_state_changed.connect(on_state)

	var on_error := Callable(self, "_on_network_error")
	if not _network_client().error_received.is_connected(on_error):
		_network_client().error_received.connect(on_error)

	var on_room := Callable(self, "_on_current_room_changed")
	if not _network_client().current_room_changed.is_connected(on_room):
		_network_client().current_room_changed.connect(on_room)


func _unbind_network_signals() -> void:
	var on_state := Callable(self, "_on_connection_state_changed")
	if _network_client().connection_state_changed.is_connected(on_state):
		_network_client().connection_state_changed.disconnect(on_state)

	var on_error := Callable(self, "_on_network_error")
	if _network_client().error_received.is_connected(on_error):
		_network_client().error_received.disconnect(on_error)

	var on_room := Callable(self, "_on_current_room_changed")
	if _network_client().current_room_changed.is_connected(on_room):
		_network_client().current_room_changed.disconnect(on_room)


func _on_connection_state_changed(_state: String, details: String) -> void:
	if visible and not _awaiting_join:
		_set_status(details)


func _on_network_error(_code: String, message: String) -> void:
	if not visible:
		return

	if _awaiting_join:
		_awaiting_join = false
	_set_status(message)


func _on_current_room_changed(room: Dictionary) -> void:
	if not _awaiting_join or room.is_empty():
		return

	_awaiting_join = false
	hide()
	id_input.clear()
	get_tree().change_scene_to_file("res://scenes/room.tscn")


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
	label.offset_left = -620.0
	label.offset_top = -170.0
	label.offset_right = 620.0
	label.offset_bottom = -95.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var settings := LabelSettings.new()
	settings.font = STATUS_FONT
	settings.font_size = 28
	settings.font_color = Color(0.17, 0.14, 0.09)
	label.label_settings = settings

	add_child(label)
	return label


func _network_client() -> Node:
	return get_node("/root/NetworkClient")
