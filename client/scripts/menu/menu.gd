extends Control

const ONLINE_NAME_HELP_TEXT := "Enter a name for online rooms."

@onready var online_name_overlay: ColorRect = $OnlineNameOverlay
@onready var online_name_input: LineEdit = $OnlineNameOverlay/PromptPanel/MarginContainer/VBoxContainer/NameInput
@onready var online_name_status: Label = $OnlineNameOverlay/PromptPanel/MarginContainer/VBoxContainer/StatusLabel


func _ready() -> void:
	online_name_overlay.visible = false
	if _network_client().has_method("get_max_display_name_length"):
		online_name_input.max_length = int(_network_client().get_max_display_name_length())


func _on_offline_butt_pressed() -> void:
	SceneTransition.change_scene("res://scenes/offline/offline_game.tscn")


func _on_start_butt_pressed() -> void:
	_show_online_name_prompt()


func _on_quit_butt_pressed() -> void:
	get_tree().quit()


func _on_name_confirm_pressed() -> void:
	_submit_online_name()


func _on_name_cancel_pressed() -> void:
	_hide_online_name_prompt()


func _on_name_input_text_submitted(_new_text: String) -> void:
	_submit_online_name()


func _show_online_name_prompt() -> void:
	var current_name := ""
	if _network_client().has_method("get_display_name"):
		current_name = String(_network_client().get_display_name())

	online_name_input.text = current_name
	online_name_status.text = ONLINE_NAME_HELP_TEXT
	online_name_overlay.visible = true
	online_name_input.grab_focus()
	online_name_input.select_all()


func _hide_online_name_prompt() -> void:
	online_name_overlay.visible = false
	online_name_status.text = ONLINE_NAME_HELP_TEXT


func _submit_online_name() -> void:
	var player_name := online_name_input.text.strip_edges()
	if player_name.is_empty():
		online_name_status.text = "Enter a name to play online."
		online_name_input.grab_focus()
		return

	if _network_client().has_method("set_display_name"):
		_network_client().set_display_name(player_name)
	_hide_online_name_prompt()
	SceneTransition.change_scene("res://scenes/online_menu.tscn")


func _network_client() -> Node:
	return get_node("/root/NetworkClient")
