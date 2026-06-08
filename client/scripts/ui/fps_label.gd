extends Label

const OptionsState = preload("res://scripts/menu/options_state.gd")

var _show_fps := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("fps_display")
	refresh_settings()


func _process(_delta: float) -> void:
	if not _show_fps:
		return

	text = "FPS: %d" % Engine.get_frames_per_second()


func refresh_settings() -> void:
	var settings := OptionsState.load_settings()
	_show_fps = bool(settings["show_fps"])
	visible = _show_fps
	set_process(_show_fps)

	if _show_fps:
		text = "FPS: %d" % Engine.get_frames_per_second()
