extends Node
class_name PlayerNameplate

const NAME_LABEL_OFFSET := Vector2(-120.0, -80.0)

var display_name := ""
var is_remote_player := false

var _owner: CharacterBody2D
var _name_label: Label


func setup(owner: CharacterBody2D, name_label: Label) -> void:
	_owner = owner
	_name_label = name_label
	if _name_label != null:
		_name_label.top_level = true


func set_display_name(player_name: String) -> void:
	display_name = player_name
	_update_name_label()


func set_remote_player(remote: bool) -> void:
	is_remote_player = remote
	_update_name_label()


func process_frame() -> void:
	_update_name_label_position()


func _update_name_label() -> void:
	if _name_label == null:
		return

	var cleaned_name := display_name.strip_edges()
	var should_show := _should_show_online_name() and not cleaned_name.is_empty()
	_name_label.visible = should_show
	if not should_show:
		_name_label.text = ""
		return

	_name_label.text = cleaned_name
	_name_label.modulate = Color(0.82, 0.95, 1.0) if is_remote_player else Color.WHITE
	_update_name_label_position()


func _update_name_label_position() -> void:
	if _name_label == null or not _name_label.visible or _owner == null:
		return

	_name_label.global_position = _owner.global_position + NAME_LABEL_OFFSET


func _should_show_online_name() -> bool:
	var network_client := get_node_or_null("/root/NetworkClient")
	if network_client == null or not network_client.has_method("get_current_room"):
		return false

	var current_room = network_client.get_current_room()
	if typeof(current_room) != TYPE_DICTIONARY or current_room.is_empty():
		return false

	return true
