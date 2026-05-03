extends Control

const STATUS_FONT = preload("res://assets/fonts/EXEPixelPerfect.ttf")

@onready var enter_id_panel = $EnterIdPanel
@onready var create_room_panel = $CreateRoomPanel
@onready var option_panel = $OptionPanel

var _status_label: Label


func _ready() -> void:
	_status_label = _create_status_label()
	_bind_network_signals()
	_refresh_status_label()


func _exit_tree() -> void:
	_unbind_network_signals()


func _on_public_butt_pressed() -> void:
	_network_client().request_public_rooms()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_private_butt_pressed() -> void:
	_network_client().ensure_connected()
	enter_id_panel.show()


func _on_host_butt_pressed() -> void:
	_network_client().ensure_connected()
	create_room_panel.show()


func _on_option_butt_pressed() -> void:
	option_panel.show()


func _bind_network_signals() -> void:
	var on_state := Callable(self, "_on_connection_state_changed")
	if not _network_client().connection_state_changed.is_connected(on_state):
		_network_client().connection_state_changed.connect(on_state)

	var on_error := Callable(self, "_on_network_error")
	if not _network_client().error_received.is_connected(on_error):
		_network_client().error_received.connect(on_error)


func _unbind_network_signals() -> void:
	var on_state := Callable(self, "_on_connection_state_changed")
	if _network_client().connection_state_changed.is_connected(on_state):
		_network_client().connection_state_changed.disconnect(on_state)

	var on_error := Callable(self, "_on_network_error")
	if _network_client().error_received.is_connected(on_error):
		_network_client().error_received.disconnect(on_error)


func _on_connection_state_changed(_state: String, details: String) -> void:
	_set_status(details)


func _on_network_error(_code: String, message: String) -> void:
	_set_status(message)


func _refresh_status_label() -> void:
	_set_status(_network_client().get_status_text())


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
	label.offset_top = -120.0
	label.offset_right = 650.0
	label.offset_bottom = -35.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var settings := LabelSettings.new()
	settings.font = STATUS_FONT
	settings.font_size = 32
	settings.font_color = Color(0.17, 0.14, 0.09)
	label.label_settings = settings

	add_child(label)
	return label


func _network_client() -> Node:
	return get_node("/root/NetworkClient")
