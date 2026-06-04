extends Node

const ServerConfig = preload("res://scripts/server/server_config.gd")
const ServerDebugContext = preload("res://scripts/server/server_debug_context.gd")
const ServerRuntime = preload("res://scripts/server/server_runtime.gd")

var _runtime: ServerRuntime


func _ready() -> void:
	_runtime = ServerRuntime.new()
	var config: ServerConfig = ServerConfig.new().load_from_env()
	var debug: ServerDebugContext = ServerDebugContext.new()
	if not _runtime.start(multiplayer as SceneMultiplayer, config, debug):
		push_error(_runtime.startup_error_message())
		get_tree().quit(1)
		return


func _process(_delta: float) -> void:
	if _runtime != null and _runtime.process_frame():
		get_tree().quit()
