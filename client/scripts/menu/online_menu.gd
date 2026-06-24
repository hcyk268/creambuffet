extends Control

const STATUS_FONT = preload("res://assets/fonts/EXEPixelPerfect.ttf")
const GameIds = preload("res://scripts/catalog/game_ids.gd")

@onready var enter_id_panel = $EnterIdPanel
@onready var create_room_panel = $CreateRoomPanel
@onready var option_panel = $OptionPanel
@onready var overlay_dim: ColorRect = $OverlayDim

var _status_label: Label
var _binder := NetworkSignalBinder.new()


func _ready() -> void:
	_status_label = _create_status_label()
	_binder.bind(_network_client().connection_state_changed, _on_connection_state_changed)
	_binder.bind(_network_client().error_received, _on_network_error)
	enter_id_panel.visibility_changed.connect(_refresh_overlay_dim)
	create_room_panel.visibility_changed.connect(_refresh_overlay_dim)
	option_panel.visibility_changed.connect(_refresh_overlay_dim)
	_refresh_status_label()
	_refresh_overlay_dim()


func _exit_tree() -> void:
	_binder.unbind_all()


func _on_public_butt_pressed() -> void:
	_network_client().request_public_rooms()
	SceneTransition.change_scene("res://scenes/lobby.tscn")


func _on_private_butt_pressed() -> void:
	_network_client().ensure_connected()
	_show_overlay_panel(enter_id_panel)


func _on_host_butt_pressed() -> void:
	_network_client().ensure_connected()
	if create_room_panel.has_method("set_room_visibility"):
		create_room_panel.set_room_visibility(GameIds.ROOM_VISIBILITY_PUBLIC)
	_show_overlay_panel(create_room_panel)


func _on_option_butt_pressed() -> void:
	if option_panel.has_method("reload_settings"):
		option_panel.reload_settings()
	_show_overlay_panel(option_panel)


func _on_back_butt_pressed() -> void:
	SceneTransition.change_scene("res://scenes/start_menu.tscn")


func _on_connection_state_changed(_state: String, details: String) -> void:
	_set_status(details)


func _on_network_error(_code: String, message: String) -> void:
	_set_status(message)


func _refresh_status_label() -> void:
	_set_status(_network_client().get_status_text())


func _show_overlay_panel(panel: Control) -> void:
	panel.show()
	_refresh_overlay_dim()


func _refresh_overlay_dim() -> void:
	overlay_dim.visible = enter_id_panel.visible or create_room_panel.visible or option_panel.visible


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
	move_child(label, overlay_dim.get_index())
	return label


func _network_client() -> Node:
	return get_node("/root/NetworkClient")
