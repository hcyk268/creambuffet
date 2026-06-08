extends Control

const OptionsState = preload("res://scripts/menu/options_state.gd")

@onready var music_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox1/PlayerLineEdit
@onready var sfx_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox2/WorldLineEdit
@onready var window_mode_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox3/WorldLineEdit
@onready var window_size_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox4/WorldLineEdit
@onready var show_fps_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox5/WorldLineEdit

const STEP := 10

var music_volume := 100
var sfx_volume := 100
var window_mode_index := 0
var window_size_index := 0
var show_fps := false


func _ready() -> void:
	music_input.editable = false
	sfx_input.editable = false
	window_mode_input.editable = false
	window_size_input.editable = false
	show_fps_input.editable = false
	_load_settings()
	_apply_settings()
	_update_displays()


func reload_settings() -> void:
	_load_settings()
	_apply_settings()
	_update_displays()


func _update_displays() -> void:
	music_input.text = "%d%%" % music_volume
	sfx_input.text = "%d%%" % sfx_volume
	window_mode_input.text = OptionsState.window_mode_text(window_mode_index)
	window_size_input.text = OptionsState.window_size_text(window_size_index)
	show_fps_input.text = "Enabled" if show_fps else "Disabled"


func _change_music(delta: int) -> void:
	music_volume = clampi(music_volume + delta, OptionsState.MIN_VOLUME, OptionsState.MAX_VOLUME)
	_update_displays()


func _change_sfx(delta: int) -> void:
	sfx_volume = clampi(sfx_volume + delta, OptionsState.MIN_VOLUME, OptionsState.MAX_VOLUME)
	_update_displays()


func _change_window_mode(delta: int) -> void:
	window_mode_index = _wrap_index(window_mode_index + delta, OptionsState.WINDOW_MODES.size())
	_update_displays()
	OptionsState.apply_display(_current_settings())


func _change_window_size(delta: int) -> void:
	window_size_index = _wrap_index(window_size_index + delta, OptionsState.WINDOW_SIZES.size())
	_update_displays()


func _change_show_fps(delta: int) -> void:
	if delta == 0:
		return
	show_fps = delta > 0
	_update_displays()


func _on_music_up_pressed() -> void:
	_change_music(STEP)


func _on_music_down_pressed() -> void:
	_change_music(-STEP)


func _on_sfx_up_pressed() -> void:
	_change_sfx(STEP)


func _on_sfx_down_pressed() -> void:
	_change_sfx(-STEP)


func _on_join_up_pressed() -> void:
	_change_window_mode(1)


func _on_join_down_pressed() -> void:
	_change_window_mode(-1)


func _on_window_size_up_pressed() -> void:
	_change_window_size(1)


func _on_window_size_down_pressed() -> void:
	_change_window_size(-1)


func _on_show_fps_up_pressed() -> void:
	_change_show_fps(1)


func _on_show_fps_down_pressed() -> void:
	_change_show_fps(-1)


func _on_apply_butt_pressed() -> void:
	_apply_settings()
	_save_settings()
	_refresh_fps_displays()
	hide()


func _on_reset_butt_pressed() -> void:
	_set_defaults()
	_apply_settings()
	_save_settings()
	_refresh_fps_displays()


func _on_back_butt_pressed() -> void:
	_load_settings()
	_apply_settings()
	_update_displays()
	hide()


func _apply_settings() -> void:
	OptionsState.apply_runtime(_current_settings())


func _save_settings() -> void:
	OptionsState.save_settings(_current_settings())


func _load_settings() -> void:
	var settings := OptionsState.load_settings()
	music_volume = int(settings["music_volume"])
	sfx_volume = int(settings["sfx_volume"])
	window_mode_index = int(settings["window_mode_index"])
	window_size_index = int(settings["window_size_index"])
	show_fps = bool(settings["show_fps"])


func _set_defaults() -> void:
	var defaults := OptionsState.default_settings()
	music_volume = int(defaults["music_volume"])
	sfx_volume = int(defaults["sfx_volume"])
	window_mode_index = int(defaults["window_mode_index"])
	window_size_index = int(defaults["window_size_index"])
	show_fps = bool(defaults["show_fps"])
	_update_displays()


func _current_settings() -> Dictionary:
	return {
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"window_mode_index": window_mode_index,
		"window_size_index": window_size_index,
		"show_fps": show_fps,
	}


func _refresh_fps_displays() -> void:
	get_tree().call_group("fps_display", "refresh_settings")


func _wrap_index(value: int, size: int) -> int:
	if size <= 0:
		return 0
	return (value % size + size) % size
