extends Control

const STATUS_FONT = preload("res://assets/fonts/EXEPixelPerfect.ttf")

const MIN_PLAYERS = 2
const MAX_PLAYERS = 4

@onready var player_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox1/PlayerLineEdit
var current_players: int = MIN_PLAYERS
var _awaiting_create := false
var _status_label: Label
var _binder := NetworkSignalBinder.new()


func _ready() -> void:
	update_displays()
	player_input.editable = false
	_status_label = _create_status_label()
	_binder.bind(_network_client().connection_state_changed, _on_connection_state_changed)
	_binder.bind(_network_client().error_received, _on_network_error)
	_binder.bind(_network_client().current_room_changed, _on_current_room_changed)
	_set_status("Create a public room on %s." % _network_client().get_server_endpoint())


func _exit_tree() -> void:
	_binder.unbind_all()


func update_displays() -> void:
	player_input.text = str(current_players)


func _on_player_up_pressed() -> void:
	if current_players < MAX_PLAYERS:
		current_players += 1
		update_displays()


func _on_player_down_pressed() -> void:
	if current_players > MIN_PLAYERS:
		current_players -= 1
		update_displays()


func _on_back_butt_pressed() -> void:
	_awaiting_create = false
	_set_status("Create a public room on %s." % _network_client().get_server_endpoint())
	hide()


func _on_create_butt_pressed() -> void:
	if _awaiting_create:
		return

	_awaiting_create = true
	_set_status("Creating room...")
	_network_client().create_room(current_players, 0, false)


func _on_connection_state_changed(_state: String, details: String) -> void:
	if visible and not _awaiting_create:
		_set_status(details)


func _on_network_error(_code: String, message: String) -> void:
	if not visible:
		return

	if _awaiting_create:
		_awaiting_create = false
	_set_status(message)


func _on_current_room_changed(room: Dictionary) -> void:
	if not _awaiting_create or room.is_empty():
		return

	_awaiting_create = false
	hide()
	SceneTransition.change_scene("res://scenes/room.tscn")


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
	label.offset_top = -145.0
	label.offset_right = 620.0
	label.offset_bottom = -80.0
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
