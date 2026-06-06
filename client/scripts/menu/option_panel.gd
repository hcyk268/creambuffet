extends Control

@onready var music_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox1/PlayerLineEdit
@onready var sfx_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox2/WorldLineEdit
@onready var window_mode_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox3/WorldLineEdit

const STEP := 10
const MIN_VOLUME := 0
const MAX_VOLUME := 100
const WINDOW_MODES := ["Windowed", "Fullscreen", "Borderless"]
const SETTINGS_PATH := "user://settings.cfg"

var music_volume := 100
var sfx_volume := 100
var window_mode_index := 0


func _ready() -> void:
	music_input.editable = false
	sfx_input.editable = false
	window_mode_input.editable = false
	_load_settings()
	_apply_settings()
	_update_displays()


func _update_displays() -> void:
	music_input.text = "%d%%" % music_volume
	sfx_input.text = "%d%%" % sfx_volume
	window_mode_input.text = WINDOW_MODES[window_mode_index]


func _change_music(delta: int) -> void:
	music_volume = clampi(music_volume + delta, MIN_VOLUME, MAX_VOLUME)
	_update_displays()


func _change_sfx(delta: int) -> void:
	sfx_volume = clampi(sfx_volume + delta, MIN_VOLUME, MAX_VOLUME)
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
	window_mode_index = (window_mode_index + 1) % WINDOW_MODES.size()
	_update_displays()


func _on_join_down_pressed() -> void:
	window_mode_index = (window_mode_index - 1 + WINDOW_MODES.size()) % WINDOW_MODES.size()
	_update_displays()


func _on_apply_butt_pressed() -> void:
	_apply_settings()
	_save_settings()
	hide()


func _on_back_butt_pressed() -> void:
	hide()


func _apply_settings() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus != -1:
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(float(music_volume) / 100.0))

	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus != -1:
		AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(float(sfx_volume) / 100.0))

	match WINDOW_MODES[window_mode_index]:
		"Windowed":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		"Fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		"Borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("display", "window_mode_index", window_mode_index)
	config.save(SETTINGS_PATH)


func _load_settings() -> void:
	var config := ConfigFile.new()
	var load_error := config.load(SETTINGS_PATH)
	if load_error != OK:
		return

	music_volume = clampi(int(config.get_value("audio", "music_volume", music_volume)), MIN_VOLUME, MAX_VOLUME)
	sfx_volume = clampi(int(config.get_value("audio", "sfx_volume", sfx_volume)), MIN_VOLUME, MAX_VOLUME)
	window_mode_index = clampi(int(config.get_value("display", "window_mode_index", window_mode_index)), 0, WINDOW_MODES.size() - 1)
