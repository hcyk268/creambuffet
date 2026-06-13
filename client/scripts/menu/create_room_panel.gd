extends Control

const STATUS_FONT = preload("res://assets/fonts/EXEPixelPerfect.ttf")
const GameIds = preload("res://scripts/catalog/game_ids.gd")

const MIN_PLAYERS = 2
const MAX_PLAYERS = 4

@onready var player_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox1/PlayerLineEdit
@onready var visibility_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBoxVisibility/VisibilityLineEdit
@onready var create_button: Button = $TextureRect2/MarginContainer/VBoxContainer/HBoxContainer/CreateButt
@onready var content_box: VBoxContainer = $TextureRect2/MarginContainer/VBoxContainer
var current_players: int = MIN_PLAYERS
var room_visibility := GameIds.ROOM_VISIBILITY_PUBLIC
var _awaiting_create := false
var _status_label: Label
var _binder := NetworkSignalBinder.new()


func _ready() -> void:
	update_displays()
	player_input.editable = false
	visibility_input.editable = false
	_status_label = _create_status_label()
	_binder.bind(_network_client().connection_state_changed, _on_connection_state_changed)
	_binder.bind(_network_client().error_received, _on_network_error)
	_binder.bind(_network_client().current_room_changed, _on_current_room_changed)
	_set_status(_default_status_message())


func _exit_tree() -> void:
	_binder.unbind_all()


func update_displays() -> void:
	player_input.text = str(current_players)
	if visibility_input != null:
		visibility_input.text = _visibility_label()
	if create_button != null:
		create_button.text = "Create"


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
	_set_status(_default_status_message())
	hide()


func _on_create_butt_pressed() -> void:
	if _awaiting_create:
		return

	_awaiting_create = true
	_set_status("Creating %s room..." % room_visibility)
	_network_client().create_room(current_players, 0, false, room_visibility)


func _on_visibility_up_pressed() -> void:
	_cycle_room_visibility(1)


func _on_visibility_down_pressed() -> void:
	_cycle_room_visibility(-1)


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


func set_room_visibility(visibility: String) -> void:
	var normalized := visibility.strip_edges().to_lower()
	if normalized != GameIds.ROOM_VISIBILITY_PRIVATE:
		normalized = GameIds.ROOM_VISIBILITY_PUBLIC
	room_visibility = normalized
	update_displays()
	if visible and not _awaiting_create:
		_set_status(_default_status_message())


func _set_status(message: String) -> void:
	if _status_label == null:
		return

	_status_label.text = message


func _visibility_label() -> String:
	if room_visibility == GameIds.ROOM_VISIBILITY_PRIVATE:
		return "Private"
	return "Public"


func _default_status_message() -> String:
	return "Ready to create a %s room." % room_visibility


func _cycle_room_visibility(_direction: int) -> void:
	if room_visibility == GameIds.ROOM_VISIBILITY_PUBLIC:
		set_room_visibility(GameIds.ROOM_VISIBILITY_PRIVATE)
	else:
		set_room_visibility(GameIds.ROOM_VISIBILITY_PUBLIC)


func _create_status_label() -> Label:
	var label := Label.new()
	label.name = "StatusLabel"
	label.layout_mode = 2
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(0, 48)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var settings := LabelSettings.new()
	settings.font = STATUS_FONT
	settings.font_size = 28
	settings.font_color = Color(0.96, 0.95, 0.92)
	settings.shadow_color = Color(0.14, 0.12, 0.2, 0.85)
	settings.shadow_offset = Vector2(0, 2)
	settings.shadow_size = 2
	label.label_settings = settings

	content_box.add_child(label)
	return label


func _network_client() -> Node:
	return get_node("/root/NetworkClient")
