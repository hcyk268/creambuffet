extends RefCounted

const SETTINGS_PATH := "user://settings.cfg"

const MIN_VOLUME := 0
const MAX_VOLUME := 100

const WINDOW_MODE_WINDOWED := 0
const WINDOW_MODE_FULLSCREEN := 1
const WINDOW_MODE_BORDERLESS := 2

const WINDOW_MODES := ["Windowed", "Fullscreen", "Borderless"]
const WINDOW_SIZES := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

const DEFAULT_SETTINGS := {
	"music_volume": 100,
	"sfx_volume": 100,
	"window_mode_index": WINDOW_MODE_WINDOWED,
	"window_size_index": 0,
	"show_fps": false,
}


static func default_settings() -> Dictionary:
	return DEFAULT_SETTINGS.duplicate(true)


static func load_settings() -> Dictionary:
	var settings := default_settings()
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return settings

	settings["music_volume"] = config.get_value("audio", "music_volume", settings["music_volume"])
	settings["sfx_volume"] = config.get_value("audio", "sfx_volume", settings["sfx_volume"])
	settings["window_mode_index"] = config.get_value("display", "window_mode_index", settings["window_mode_index"])
	settings["window_size_index"] = config.get_value("display", "window_size_index", settings["window_size_index"])
	settings["show_fps"] = config.get_value("display", "show_fps", settings["show_fps"])
	return normalize_settings(settings)


static func save_settings(settings: Dictionary) -> void:
	var normalized := normalize_settings(settings)
	var config := ConfigFile.new()
	config.set_value("audio", "music_volume", normalized["music_volume"])
	config.set_value("audio", "sfx_volume", normalized["sfx_volume"])
	config.set_value("display", "window_mode_index", normalized["window_mode_index"])
	config.set_value("display", "window_size_index", normalized["window_size_index"])
	config.set_value("display", "show_fps", normalized["show_fps"])
	config.save(SETTINGS_PATH)


static func apply_runtime(settings: Dictionary) -> void:
	var normalized := normalize_settings(settings)
	_apply_audio(normalized)
	_apply_display(normalized)


static func apply_display(settings: Dictionary) -> void:
	_apply_display(normalize_settings(settings))


static func normalize_settings(raw_settings: Dictionary) -> Dictionary:
	var settings := default_settings()
	for key in raw_settings.keys():
		settings[key] = raw_settings[key]

	settings["music_volume"] = clampi(int(settings["music_volume"]), MIN_VOLUME, MAX_VOLUME)
	settings["sfx_volume"] = clampi(int(settings["sfx_volume"]), MIN_VOLUME, MAX_VOLUME)
	settings["window_mode_index"] = clampi(int(settings["window_mode_index"]), 0, WINDOW_MODES.size() - 1)
	settings["window_size_index"] = clampi(int(settings["window_size_index"]), 0, WINDOW_SIZES.size() - 1)
	settings["show_fps"] = bool(settings["show_fps"])
	return settings


static func window_mode_text(index: int) -> String:
	var safe_index := clampi(index, 0, WINDOW_MODES.size() - 1)
	return WINDOW_MODES[safe_index]


static func window_size_text(index: int) -> String:
	var safe_index := clampi(index, 0, WINDOW_SIZES.size() - 1)
	var window_size: Vector2i = WINDOW_SIZES[safe_index]
	return "%dx%d" % [window_size.x, window_size.y]


static func is_fps_enabled(settings: Dictionary) -> bool:
	return bool(normalize_settings(settings)["show_fps"])


static func _apply_audio(settings: Dictionary) -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus != -1:
		AudioServer.set_bus_volume_db(master_bus, _volume_to_db(int(settings["music_volume"])))

	var sfx_bus := AudioServer.get_bus_index("SFX")
	if sfx_bus != -1:
		AudioServer.set_bus_volume_db(sfx_bus, _volume_to_db(int(settings["sfx_volume"])))


static func _apply_display(settings: Dictionary) -> void:
	var window_mode_index := int(settings["window_mode_index"])
	var window_size_index := clampi(int(settings["window_size_index"]), 0, WINDOW_SIZES.size() - 1)
	var window_size: Vector2i = WINDOW_SIZES[window_size_index]

	match window_mode_index:
		WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, false)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
			DisplayServer.window_set_size(window_size)
		WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WINDOW_MODE_BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(window_size)


static func _volume_to_db(volume: int) -> float:
	if volume <= 0:
		return -80.0
	return linear_to_db(float(volume) / 100.0)
