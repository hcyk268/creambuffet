extends RefCounted
class_name ServerConfig

const DEFAULT_PORT := 7000
const DEFAULT_MAX_CLIENTS := 32
const DEFAULT_EXIT_AFTER_MS := 0

var port := DEFAULT_PORT
var max_clients := DEFAULT_MAX_CLIENTS
var exit_after_ms := DEFAULT_EXIT_AFTER_MS


func load_from_env() -> ServerConfig:
	port = _read_int_env("CREAMBUFFET_SERVER_PORT", DEFAULT_PORT)
	max_clients = _read_int_env("CREAMBUFFET_SERVER_MAX_CLIENTS", DEFAULT_MAX_CLIENTS)
	exit_after_ms = _read_int_env("CREAMBUFFET_SERVER_EXIT_AFTER_MS", DEFAULT_EXIT_AFTER_MS)
	return self


func _read_int_env(variable_name: String, fallback: int) -> int:
	var raw_value := OS.get_environment(variable_name).strip_edges()
	if raw_value.is_empty():
		return fallback

	return int(raw_value)
