extends CanvasLayer

@export var main_menu_scene := "res://scenes/start_menu.tscn"
@export var pause_tree_on_open := true
@export var block_player_input_on_open := true

@onready var overlay: Control = $Overlay
@onready var title_label: Label = $Overlay/CenterContainer/Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var message_label: Label = $Overlay/CenterContainer/Panel/MarginContainer/VBoxContainer/MessageLabel
@onready var replay_button: Button = $Overlay/CenterContainer/Panel/MarginContainer/VBoxContainer/ButtonRow/ReplayButton
@onready var main_menu_button: Button = $Overlay/CenterContainer/Panel/MarginContainer/VBoxContainer/ButtonRow/MainMenuButton

var _is_open := false
var _previous_pause_state := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.visible = false

	replay_button.pressed.connect(_on_replay_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)


func _exit_tree() -> void:
	if _is_open:
		_set_game_input_enabled(true)
		if pause_tree_on_open:
			get_tree().paused = _previous_pause_state


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return

	if event is InputEventKey and event.pressed:
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _is_open


func open(title := "Level Clear!", message := "You reached the end.") -> void:
	if _is_open:
		return

	_is_open = true
	_previous_pause_state = get_tree().paused
	title_label.text = title
	message_label.text = message
	overlay.visible = true
	_set_game_input_enabled(false)

	if pause_tree_on_open:
		get_tree().paused = true

	replay_button.grab_focus()


func close() -> void:
	if not _is_open:
		return

	overlay.visible = false
	_is_open = false
	_set_game_input_enabled(true)

	if pause_tree_on_open:
		get_tree().paused = _previous_pause_state


func _on_replay_pressed() -> void:
	var game_root := get_parent()
	if game_root == null or not game_root.has_method("restart_level"):
		return

	close()
	game_root.restart_level()


func _on_main_menu_pressed() -> void:
	overlay.visible = false
	_is_open = false
	_set_game_input_enabled(true)
	get_tree().paused = false
	get_tree().change_scene_to_file(main_menu_scene)


func _set_game_input_enabled(enabled: bool) -> void:
	if not block_player_input_on_open:
		return

	var game_root := get_parent()
	if game_root == null:
		return

	var player := game_root.get_node_or_null("Player")
	if player != null and player.has_method("set_input_enabled"):
		player.set_input_enabled(enabled)
