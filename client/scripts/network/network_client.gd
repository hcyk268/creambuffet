extends Node

signal connection_state_changed(state, details)
signal room_list_updated(rooms)
signal current_room_changed(room)
signal error_received(code, message)
signal match_started(room)
signal remote_player_state(peer_id, state)
signal pushable_control_received(level_index, controls)
signal level_transition(from_level_index, to_level_index, match_complete, room)
signal world_event_received(event)

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const GameIds = preload("res://scripts/catalog/game_ids.gd")
const ProtocolConstants = preload("res://scripts/network/protocol_constants.gd")

const PROTOCOL_VERSION := ProtocolConstants.PROTOCOL_VERSION
const STATE_DISCONNECTED := "disconnected"
const STATE_CONNECTING := "connecting"
const STATE_CONNECTED := "connected"

const DEFAULT_SERVER_HOST := "127.0.0.1"
const DEFAULT_SERVER_PORT := 7000
const CONFIG_PATH := "res://config/client_network.cfg"
const SERVER_PEER_ID := 1
const MAX_DISPLAY_NAME_LENGTH := 24

var server_host := DEFAULT_SERVER_HOST
var server_port := DEFAULT_SERVER_PORT
var connection_state := STATE_DISCONNECTED
var connection_details := ""
var local_peer_id := 0

var _display_name := ""
var _configured_display_name := ""
var _allow_env_overrides := true
var _request_counter := 0
var _scene_multiplayer: SceneMultiplayer
var _peer: ENetMultiplayerPeer
var _pending_packets: Array[Dictionary] = []
var _current_room: Dictionary = {}
var _public_rooms: Array[Dictionary] = []


func _ready() -> void:
	_load_runtime_config()
	var initial_display_name := _configured_display_name if not _configured_display_name.is_empty() else _guess_display_name()
	_display_name = _sanitize_display_name(initial_display_name)
	connection_details = _offline_status_text()

	_scene_multiplayer = get_tree().get_multiplayer() as SceneMultiplayer
	if _scene_multiplayer == null:
		push_error("Client networking requires SceneMultiplayer.")
		return

	_bind_multiplayer_signals()
	connection_state_changed.emit(connection_state, connection_details)


func ensure_connected() -> void:
	if _scene_multiplayer == null:
		return

	if connection_state == STATE_CONNECTED or connection_state == STATE_CONNECTING:
		return

	_peer = ENetMultiplayerPeer.new()
	var connect_error := _peer.create_client(server_host, server_port)
	if connect_error != OK:
		_peer = null
		_set_connection_state(
			STATE_DISCONNECTED,
			_connection_failed_status_text()
		)
		error_received.emit("connection_failed", connection_details)
		return

	_scene_multiplayer.multiplayer_peer = _peer
	_set_connection_state(STATE_CONNECTING, _connecting_status_text())


func disconnect_from_server() -> void:
	_pending_packets.clear()
	local_peer_id = 0

	if _peer != null:
		_peer.close()
		_peer = null

	if _scene_multiplayer != null:
		_scene_multiplayer.multiplayer_peer = null

	_set_current_room({})
	_set_public_rooms([])
	_set_connection_state(STATE_DISCONNECTED, _offline_status_text())


func get_status_text() -> String:
	return connection_details


func get_server_endpoint() -> String:
	return "%s:%d" % [server_host, server_port]


func get_current_room() -> Dictionary:
	return _current_room.duplicate(true)


func get_local_peer_id() -> int:
	return local_peer_id


func get_display_name() -> String:
	return _display_name


func get_max_display_name_length() -> int:
	return MAX_DISPLAY_NAME_LENGTH


func set_display_name(requested_name: String) -> void:
	_display_name = _sanitize_display_name(requested_name)


func is_room_host() -> bool:
	return not _current_room.is_empty() and int(_current_room.get("host_peer_id", -1)) == local_peer_id


func is_match_active() -> bool:
	return String(_current_room.get("status", "")) == GameIds.ROOM_STATUS_PLAYING


func get_public_rooms() -> Array[Dictionary]:
	return _public_rooms.duplicate(true)


func request_public_rooms() -> void:
	_queue_or_send(ProtocolConstants.MESSAGE_LIST_ROOMS, {})


func create_room(max_players: int, world_count: int, randomized: bool, visibility: String = GameIds.ROOM_VISIBILITY_PUBLIC, map_id: String = "beginner") -> void:
	_queue_or_send(ProtocolConstants.MESSAGE_CREATE_ROOM, {
		"player_name": _display_name,
		"visibility": visibility,
		"max_players": max_players,
		"world_count": world_count,
		"map_id": map_id,
		"randomized": randomized,
	})


func join_room(room_id: String) -> void:
	_queue_or_send(ProtocolConstants.MESSAGE_JOIN_ROOM, {
		"player_name": _display_name,
		"room_id": room_id.strip_edges().to_upper(),
	})


func leave_room() -> void:
	if connection_state == STATE_DISCONNECTED:
		_set_current_room({})
		return

	_queue_or_send(ProtocolConstants.MESSAGE_LEAVE_ROOM, {})


func start_match() -> void:
	_queue_or_send(ProtocolConstants.MESSAGE_START_MATCH, {})


func set_room_map(map_id: String) -> void:
	var normalized := map_id.strip_edges().to_lower()
	if normalized.is_empty():
		error_received.emit("missing_map_id", "Map id is required.")
		return

	_queue_or_send(ProtocolConstants.MESSAGE_SET_ROOM_MAP, {
		"map_id": normalized,
	})


func send_player_state(state: Dictionary) -> void:
	if connection_state != STATE_CONNECTED:
		return

	_send_packet(ProtocolConstants.MESSAGE_PLAYER_STATE, state, "", MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED)


func send_world_event(event: Dictionary) -> void:
	var action := String(event.get("action", event.get("kind", ""))).strip_edges()
	var target_id := String(event.get("target_id", event.get("sync_id", ""))).strip_edges()
	var payload: Dictionary = event.duplicate(true)
	if target_id.is_empty():
		target_id = _infer_legacy_target_id(action, payload)
	payload.erase("kind")
	payload.erase("sync_id")
	payload.erase("node_name")
	payload.erase("peer_id")
	payload.erase("level_has_key")
	payload.erase("level_has_door")
	payload.erase("key_count")
	send_world_action(action, target_id, payload)


func send_world_action(action: String, target_id: String = "", extra: Dictionary = {}) -> void:
	if connection_state != STATE_CONNECTED:
		return

	var payload: Dictionary = extra.duplicate(true)
	payload["action"] = action
	if not target_id.strip_edges().is_empty():
		payload["target_id"] = target_id.strip_edges()

	if not payload.has("level_id"):
		var level_id := String(_current_room.get("current_level_id", ""))
		if not level_id.is_empty():
			payload["level_id"] = level_id

	_send_packet(ProtocolConstants.MESSAGE_WORLD_ACTION_REQUEST, payload, _next_request_id(ProtocolConstants.REQUEST_PREFIX_ACTION))


func _bind_multiplayer_signals() -> void:
	var on_connected := Callable(self, "_on_connected_to_server")
	if not _scene_multiplayer.connected_to_server.is_connected(on_connected):
		_scene_multiplayer.connected_to_server.connect(on_connected)

	var on_failed := Callable(self, "_on_connection_failed")
	if not _scene_multiplayer.connection_failed.is_connected(on_failed):
		_scene_multiplayer.connection_failed.connect(on_failed)

	var on_disconnected := Callable(self, "_on_server_disconnected")
	if not _scene_multiplayer.server_disconnected.is_connected(on_disconnected):
		_scene_multiplayer.server_disconnected.connect(on_disconnected)

	var on_packet := Callable(self, "_on_peer_packet")
	if not _scene_multiplayer.peer_packet.is_connected(on_packet):
		_scene_multiplayer.peer_packet.connect(on_packet)


func _on_connected_to_server() -> void:
	_set_connection_state(STATE_CONNECTED, "Connected")
	_send_packet(ProtocolConstants.MESSAGE_HELLO, {
		"player_name": _display_name,
	})
	_flush_pending_packets()


func _on_connection_failed() -> void:
	var failed_message := _connection_failed_status_text()
	_clear_network_state(failed_message)
	error_received.emit("connection_failed", failed_message)


func _on_server_disconnected() -> void:
	var disconnected_message := "Server disconnected."
	_clear_network_state(disconnected_message)
	error_received.emit("server_disconnected", disconnected_message)


func _on_peer_packet(peer_id: int, packet: PackedByteArray) -> void:
	if peer_id != SERVER_PEER_ID:
		return

	var decoded := _decode_packet(packet)
	if not bool(decoded.get("ok", false)):
		var bad_packet_message := String(decoded.get("message", "Received an invalid packet from the server."))
		error_received.emit(String(decoded.get("code", "bad_packet")), bad_packet_message)
		return

	var message_type := String(decoded.get("type", ""))
	var payload: Dictionary = decoded.get("payload", {})

	match message_type:
		ProtocolConstants.MESSAGE_WELCOME:
			_handle_welcome(payload)
		ProtocolConstants.MESSAGE_PONG:
			pass
		ProtocolConstants.MESSAGE_ROOM_LIST:
			_set_public_rooms(payload.get("rooms", []))
		ProtocolConstants.MESSAGE_ROOM_CREATED, ProtocolConstants.MESSAGE_ROOM_JOINED, ProtocolConstants.MESSAGE_ROOM_UPDATED, ProtocolConstants.MESSAGE_ROOM_MAP_UPDATED:
			_set_current_room(payload.get("room", {}))
		ProtocolConstants.MESSAGE_ROOM_LEFT:
			_set_current_room({})
		ProtocolConstants.MESSAGE_MATCH_STARTED:
			_handle_match_started(payload)
		ProtocolConstants.MESSAGE_PLAYER_STATE:
			_handle_player_state(payload)
		ProtocolConstants.MESSAGE_PUSHABLE_CONTROL:
			_handle_pushable_control(payload)
		ProtocolConstants.MESSAGE_LEVEL_TRANSITION:
			_handle_level_transition(payload)
		# Sprint 1 restores world state through room snapshots in room/match messages.
		# There is intentionally no dedicated world_snapshot message flow on the client.
		ProtocolConstants.MESSAGE_WORLD_EVENT:
			_handle_world_event(payload)
		ProtocolConstants.MESSAGE_ERROR:
			_handle_server_error(payload)
		_:
			error_received.emit("unsupported_server_message", "Unsupported server message type: %s" % message_type)


func _handle_welcome(payload: Dictionary) -> void:
	if payload.has("peer_id"):
		local_peer_id = int(payload["peer_id"])

	if payload.has("display_name"):
		_display_name = String(payload["display_name"])

	var label_name := _display_name if not _display_name.is_empty() else "Player"
	_set_connection_state(STATE_CONNECTED, "Connected as %s" % label_name)


func _handle_match_started(payload: Dictionary) -> void:
	var room = payload.get("room", {})
	if typeof(room) == TYPE_DICTIONARY:
		_set_current_room(room)
		match_started.emit(get_current_room())


func _handle_player_state(payload: Dictionary) -> void:
	var state = payload.get("state", {})
	if typeof(state) != TYPE_DICTIONARY:
		return

	var state_dict: Dictionary = Dictionary(state).duplicate(true)
	var peer_id := int(state_dict.get("peer_id", 0))
	if peer_id <= 0 or peer_id == local_peer_id:
		return

	remote_player_state.emit(peer_id, state_dict.duplicate(true))


func _handle_pushable_control(payload: Dictionary) -> void:
	var level_index := int(payload.get("level_index", -1))
	var controls: Variant = payload.get("controls", [])
	if typeof(controls) != TYPE_ARRAY:
		return

	pushable_control_received.emit(level_index, Array(controls).duplicate(true))


func _handle_level_transition(payload: Dictionary) -> void:
	var room = payload.get("room", {})
	if typeof(room) == TYPE_DICTIONARY:
		if bool(payload.get("restart", false)):
			room["_restart_level"] = true
			room["_transition_reason"] = String(payload.get("reason", ""))
		_set_current_room(room)

	var from_level_index := int(payload.get("from_level_index", _current_room.get("current_level_index", 0)))
	var to_level_index := int(payload.get("to_level_index", from_level_index))
	var match_complete := bool(payload.get("match_complete", false))
	level_transition.emit(from_level_index, to_level_index, match_complete, get_current_room())


func _handle_world_event(payload: Dictionary) -> void:
	var event = payload.get("event", {})
	if typeof(event) != TYPE_DICTIONARY:
		return

	world_event_received.emit(Dictionary(event).duplicate(true))
	
func _handle_server_error(payload: Dictionary) -> void:
	var code := String(payload.get("code", "server_error"))
	var message := String(payload.get("message", "The server returned an unknown error."))
	error_received.emit(code, message)


func _queue_or_send(message_type: String, payload: Dictionary) -> void:
	ensure_connected()
	if connection_state == STATE_DISCONNECTED:
		return

	var packet := {
		ProtocolConstants.FIELD_VERSION: PROTOCOL_VERSION,
		ProtocolConstants.FIELD_TYPE: message_type,
		ProtocolConstants.FIELD_PAYLOAD: payload,
		ProtocolConstants.FIELD_REQUEST_ID: _next_request_id(message_type),
	}

	if connection_state == STATE_CONNECTED:
		_send_packet_dict(packet)
	else:
		_pending_packets.append(packet)


func _flush_pending_packets() -> void:
	if connection_state != STATE_CONNECTED:
		return

	var queued_packets: Array[Dictionary] = _pending_packets.duplicate(true)
	_pending_packets.clear()

	for packet in queued_packets:
		_send_packet_dict(packet)


func _send_packet(
	message_type: String,
	payload: Dictionary = {},
	request_id: String = "",
	transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
) -> void:
	var packet := {
		ProtocolConstants.FIELD_VERSION: PROTOCOL_VERSION,
		ProtocolConstants.FIELD_TYPE: message_type,
		ProtocolConstants.FIELD_PAYLOAD: payload,
	}

	if not request_id.is_empty():
		packet[ProtocolConstants.FIELD_REQUEST_ID] = request_id

	_send_packet_dict(packet, transfer_mode)


func _send_packet_dict(packet: Dictionary, transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE) -> void:
	if _scene_multiplayer == null or connection_state != STATE_CONNECTED:
		return

	if not packet.has(ProtocolConstants.FIELD_VERSION):
		packet[ProtocolConstants.FIELD_VERSION] = PROTOCOL_VERSION

	var send_error := _scene_multiplayer.send_bytes(
		JSON.stringify(packet).to_utf8_buffer(),
		SERVER_PEER_ID,
		transfer_mode
	)

	if send_error != OK:
		var message := "Failed to send %s (error %d)." % [String(packet.get(ProtocolConstants.FIELD_TYPE, "packet")), send_error]
		error_received.emit("send_failed", message)


func _decode_packet(packet: PackedByteArray) -> Dictionary:
	var text := packet.get_string_from_utf8()
	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		return {
			"ok": false,
			"code": "bad_json",
			"message": "Server packet is not valid JSON.",
		}

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"code": "bad_packet",
			"message": "Server packet root must be an object.",
		}

	var decoded: Dictionary = data
	var version = decoded.get(ProtocolConstants.FIELD_VERSION, null)
	if version == null:
		return {
			"ok": false,
			"code": "missing_protocol_version",
			"message": "Server packet is missing protocol version.",
		}

	if version != null and int(version) != PROTOCOL_VERSION:
		return {
			"ok": false,
			"code": "unsupported_protocol_version",
			"message": "Server packet used an unsupported protocol version.",
		}

	var message_type := String(decoded.get(ProtocolConstants.FIELD_TYPE, "")).strip_edges()
	if message_type.is_empty():
		return {
			"ok": false,
			"code": "missing_type",
			"message": "Server packet is missing a type.",
		}

	var payload = decoded.get(ProtocolConstants.FIELD_PAYLOAD, {})
	if typeof(payload) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"code": "bad_payload",
			"message": "Server packet payload must be an object.",
		}

	return {
		"ok": true,
		"v": int(version),
		"type": message_type,
		"payload": payload,
		"request_id": decoded.get(ProtocolConstants.FIELD_REQUEST_ID, null),
	}


func _set_connection_state(next_state: String, details: String) -> void:
	connection_state = next_state
	connection_details = details
	connection_state_changed.emit(connection_state, connection_details)


func _set_current_room(room_data) -> void:
	if typeof(room_data) != TYPE_DICTIONARY:
		_current_room = {}
	else:
		_current_room = Dictionary(room_data).duplicate(true)

	current_room_changed.emit(get_current_room())


func _set_public_rooms(room_list) -> void:
	_public_rooms.clear()
	if typeof(room_list) == TYPE_ARRAY:
		for raw_room in room_list:
			if typeof(raw_room) == TYPE_DICTIONARY:
				_public_rooms.append(Dictionary(raw_room).duplicate(true))

	room_list_updated.emit(get_public_rooms())


func _clear_network_state(details: String) -> void:
	_pending_packets.clear()
	_peer = null
	local_peer_id = 0
	if _scene_multiplayer != null:
		_scene_multiplayer.multiplayer_peer = null

	_set_current_room({})
	_set_public_rooms([])
	_set_connection_state(STATE_DISCONNECTED, details)


func _offline_status_text() -> String:
	return "Offline"


func _connecting_status_text() -> String:
	return "Connecting..."


func _connection_failed_status_text() -> String:
	return "Unable to connect. Please try again."


func _load_runtime_config() -> void:
	var config := ConfigFile.new()
	var load_error := config.load(CONFIG_PATH)
	if load_error == OK:
		server_host = String(config.get_value("server", "host", DEFAULT_SERVER_HOST)).strip_edges()
		if server_host.is_empty():
			server_host = DEFAULT_SERVER_HOST

		server_port = int(config.get_value("server", "port", DEFAULT_SERVER_PORT))
		_configured_display_name = String(config.get_value("client", "display_name", "")).strip_edges()
		_allow_env_overrides = bool(config.get_value("dev", "allow_env_overrides", true))
	else:
		push_warning("Could not load client network config at %s (error %d). Using defaults." % [CONFIG_PATH, load_error])

	if not _allow_env_overrides:
		return

	var host_from_env := OS.get_environment("CREAMBUFFET_SERVER_HOST").strip_edges()
	if not host_from_env.is_empty():
		server_host = host_from_env

	var port_from_env := OS.get_environment("CREAMBUFFET_SERVER_PORT").strip_edges()
	if not port_from_env.is_empty():
		server_port = int(port_from_env)

	var display_name_from_env := OS.get_environment("CREAMBUFFET_PLAYER_NAME").strip_edges()
	if not display_name_from_env.is_empty():
		_configured_display_name = display_name_from_env


func _guess_display_name() -> String:
	var username := OS.get_environment("USERNAME").strip_edges()
	if username.is_empty():
		username = OS.get_environment("USER").strip_edges()
	if username.is_empty():
		return "Player"
	return username


func _sanitize_display_name(requested_name: String) -> String:
	var cleaned := requested_name.strip_edges()
	cleaned = cleaned.replace("\r", " ")
	cleaned = cleaned.replace("\n", " ")
	cleaned = cleaned.replace("\t", " ")
	if cleaned.length() > MAX_DISPLAY_NAME_LENGTH:
		cleaned = cleaned.substr(0, MAX_DISPLAY_NAME_LENGTH)
	return cleaned


func _next_request_id(prefix: String) -> String:
	_request_counter += 1
	return "%s-%d" % [prefix, _request_counter]


func _infer_legacy_target_id(action: String, payload: Dictionary) -> String:
	var level_id := String(payload.get("level_id", ""))
	if level_id.is_empty():
		var map_id := String(_current_room.get("map_id", GameCatalog.DEFAULT_MAP_ID))
		if payload.has("level_index"):
			level_id = GameCatalog.get_level_id_by_index(map_id, int(payload.get("level_index", 0)))
		else:
			level_id = String(_current_room.get("current_level_id", ""))

	if level_id.is_empty():
		return ""

	var normalized_action := GameCatalog.normalize_world_action(action)
	var level_def := GameCatalog.get_level(level_id)
	var objects_raw = level_def.get("objects", {})
	if typeof(objects_raw) != TYPE_DICTIONARY:
		return ""

	var objects: Dictionary = objects_raw
	for raw_target_id in objects.keys():
		var target_id := String(raw_target_id)
		var allowed_actions := GameCatalog.get_allowed_actions(level_id, target_id)
		if allowed_actions.has(normalized_action) or allowed_actions.has(action.strip_edges().to_lower()):
			return target_id

	return ""
