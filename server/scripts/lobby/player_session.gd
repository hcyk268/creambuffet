extends RefCounted
class_name PlayerSession

const MAX_NAME_LENGTH := 24

var peer_id := 0
var display_name := ""
var room_id := ""
var reconnect_token := ""
var player_color_hex := ""


func _init(initial_peer_id: int = 0, initial_name: String = "") -> void:
	peer_id = initial_peer_id
	set_display_name(initial_name)


func set_display_name(requested_name: String) -> void:
	display_name = sanitize_display_name(requested_name, peer_id)


func set_peer_id(next_peer_id: int) -> void:
	peer_id = next_peer_id


func set_reconnect_token(next_token: String) -> void:
	reconnect_token = next_token


func set_player_color_hex(next_color_hex: String) -> void:
	player_color_hex = next_color_hex.strip_edges().trim_prefix("#").to_lower()


func attach_room(next_room_id: String) -> void:
	room_id = next_room_id


func detach_room() -> void:
	room_id = ""


func snapshot() -> Dictionary:
	return {
		"peer_id": peer_id,
		"display_name": display_name,
		"room_id": room_id,
		"player_color": player_color_hex,
	}


static func sanitize_display_name(requested_name: String, fallback_peer_id: int) -> String:
	var cleaned := requested_name.strip_edges()
	cleaned = cleaned.replace("\r", " ")
	cleaned = cleaned.replace("\n", " ")
	cleaned = cleaned.replace("\t", " ")

	if cleaned.is_empty():
		return "Guest%d" % fallback_peer_id

	if cleaned.length() > MAX_NAME_LENGTH:
		cleaned = cleaned.substr(0, MAX_NAME_LENGTH)

	return cleaned
