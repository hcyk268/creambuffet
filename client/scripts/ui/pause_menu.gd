extends CanvasLayer

@export var main_menu_scene := "res://scenes/start_menu.tscn"
@export var pause_tree_on_open := true
@export var allow_restart := true
@export var block_player_input_on_open := true
@export var leave_room_on_main_menu := true

@onready var overlay: Control = $Overlay
@onready var resume_button: Button = $Overlay/CenterContainer/MenuPanel/MarginContainer/VBoxContainer/ResumeButton
@onready var restart_button: Button = $Overlay/CenterContainer/MenuPanel/MarginContainer/VBoxContainer/RestartButton
@onready var main_menu_button: Button = $Overlay/CenterContainer/MenuPanel/MarginContainer/VBoxContainer/MainMenuButton

var _is_open := false
var _previous_pause_state := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.visible = false

	resume_button.pressed.connect(close)
	restart_button.pressed.connect(_on_restart_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)

	_refresh_buttons()


func _exit_tree() -> void:
	if _is_open:
		_set_game_input_enabled(true)
		if pause_tree_on_open:
			get_tree().paused = _previous_pause_state


func _unhandled_input(event: InputEvent) -> void:
	var completion_screen := get_parent().get_node_or_null("CompletionScreen") if get_parent() != null else null
	if completion_screen != null and completion_screen.has_method("is_open") and completion_screen.is_open():
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	if _is_open:
		return

	_is_open = true
	_previous_pause_state = get_tree().paused
	overlay.visible = true
	_refresh_buttons()
	_set_game_input_enabled(false)

	if pause_tree_on_open:
		get_tree().paused = true

	resume_button.grab_focus()


func close() -> void:
	if not _is_open:
		return

	overlay.visible = false
	_is_open = false
	_set_game_input_enabled(true)

	if pause_tree_on_open:
		get_tree().paused = _previous_pause_state


func _refresh_buttons() -> void:
	var game_root := get_parent()
	restart_button.visible = allow_restart and game_root != null and game_root.has_method("restart_level")


func _on_restart_pressed() -> void:
	var game_root := get_parent()
	if game_root == null or not game_root.has_method("restart_level"):
		return

	close()
	game_root.restart_level()


func _on_main_menu_pressed() -> void:
	_prepare_to_leave_game()
	SceneTransition.change_scene(main_menu_scene)


func _prepare_to_leave_game() -> void:
	overlay.visible = false
	_is_open = false
	_set_game_input_enabled(true)
	get_tree().paused = false

	if not leave_room_on_main_menu:
		return

	var network_client := get_node_or_null("/root/NetworkClient")
	if network_client != null and network_client.has_method("get_current_room") and network_client.has_method("leave_room"):
		var room: Dictionary = network_client.get_current_room()
		if not room.is_empty():
			network_client.leave_room()


func _set_game_input_enabled(enabled: bool) -> void:
	if not block_player_input_on_open:
		return

	var game_root := get_parent()
	if game_root == null:
		return

	var player := game_root.get_node_or_null("Player")
	if player != null and player.has_method("set_input_enabled"):
		player.set_input_enabled(enabled)
