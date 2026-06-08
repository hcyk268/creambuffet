extends Label

const OptionsState = preload("res://scripts/menu/options_state.gd")

const FPS_GREEN := Color(0.35, 1.0, 0.35, 1.0)
const FPS_YELLOW := Color(1.0, 0.9, 0.2, 1.0)
const FPS_RED := Color(1.0, 0.35, 0.35, 1.0)

var _show_fps := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 0.0
	offset_left = -180.0
	offset_top = 10.0
	offset_right = -10.0
	offset_bottom = 34.0
	add_theme_color_override("font_color", FPS_RED)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_to_group("fps_display")
	refresh_settings()


func _process(_delta: float) -> void:
	if not _show_fps:
		return

	var fps := Engine.get_frames_per_second()
	text = "FPS: %d" % fps
	add_theme_color_override("font_color", _fps_color(fps))


func refresh_settings() -> void:
	var settings := OptionsState.load_settings()
	_show_fps = bool(settings["show_fps"])
	visible = _show_fps
	set_process(_show_fps)

	if _show_fps:
		var fps := Engine.get_frames_per_second()
		text = "FPS: %d" % fps
		add_theme_color_override("font_color", _fps_color(fps))


func _fps_color(fps: int) -> Color:
	if fps >= 50:
		return FPS_GREEN
	if fps >= 20:
		return FPS_YELLOW
	return FPS_RED
