extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const PlayerSession = preload("res://scripts/lobby/player_session.gd")
const Room = preload("res://scripts/lobby/room.gd")
const RoomManager = preload("res://scripts/lobby/room_manager.gd")

const DEFAULT_PORT := 7000
const DEFAULT_MAX_CLIENTS := 32

var port := DEFAULT_PORT
var max_clients := DEFAULT_MAX_CLIENTS
var exit_after_ms := 0

var _started_at_ms := 0
var _network_peer := ENetMultiplayerPeer.new()
var _room_manager := RoomManager.new()
var _scene_multiplayer: SceneMultiplayer


func _ready() -> void:
	_load_runtime_config()
	_started_at_ms = Time.get_ticks_msec()

	_scene_multiplayer = multiplayer as SceneMultiplayer
	if _scene_multiplayer == null:
		push_error("Default multiplayer interface is not SceneMultiplayer.")
		get_tree().quit(1)
		return

	var create_error := _network_peer.create_server(port, max_clients)
	if create_error != OK:
		push_error("Could not start ENet server on port %d (error %d)." % [port, create_error])
		get_tree().quit(1)
		return

	_scene_multiplayer.multiplayer_peer = _network_peer
	_scene_multiplayer.peer_connected.connect(_on_peer_connected)
	_scene_multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_scene_multiplayer.peer_packet.connect(_on_peer_packet)

	print("CreamBuffet server listening on port %d for up to %d clients." % [port, max_clients])


func _process(_delta: float) -> void:
	if exit_after_ms <= 0:
		return

	if Time.get_ticks_msec() - _started_at_ms >= exit_after_ms:
		print("Exit timer reached, shutting down server.")
		get_tree().quit()


func _on_peer_connected(peer_id: int) -> void:
	var session := _room_manager.ensure_session(peer_id)
	print("Peer connected: %d (%s)" % [peer_id, session.display_name])
	_send_message(peer_id, "welcome", {
		"peer_id": peer_id,
		"protocol_version": Protocol.SERVER_PROTOCOL_VERSION,
		"server_port": port,
	})


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected: %d" % peer_id)
	var result := _room_manager.unregister_peer(peer_id)
	_publish_room_change(result)


func _on_peer_packet(peer_id: int, packet: PackedByteArray) -> void:
	var decoded := Protocol.decode_packet(packet)
	if not bool(decoded.get("ok", false)):
		_send_error(
			peer_id,
			String(decoded.get("code", "bad_packet")),
			String(decoded.get("message", "Packet could not be decoded."))
		)
		return

	var message_type := String(decoded.get("type", ""))
	var request_id = decoded.get("request_id", null)
	var payload: Dictionary = decoded.get("payload", {})

	match message_type:
		"hello":
			_handle_hello(peer_id, request_id, payload)
		"ping":
			_send_message(peer_id, "pong", {
				"server_time_unix": Time.get_unix_time_from_system(),
			}, request_id)
		"list_rooms":
			_send_message(peer_id, "room_list", {
				"rooms": _room_manager.list_public_rooms(),
			}, request_id)
		"create_room":
			_handle_create_room(peer_id, request_id, payload)
		"join_room":
			_handle_join_room(peer_id, request_id, payload)
		"leave_room":
			_handle_leave_room(peer_id, request_id)
		"start_match":
			_handle_start_match(peer_id, request_id)
		"player_state":
			_handle_player_state(peer_id, payload)
		"level_changed":
			_handle_level_changed(peer_id, request_id, payload)
		"level_complete":
			_handle_level_complete(peer_id, request_id)
		"world_event":
			_handle_world_event(peer_id, payload)
		"world_event_request":
			_handle_world_event_request(peer_id, request_id, payload)
		_:
			_send_error(peer_id, "unsupported_type", "Unsupported message type: %s" % message_type, request_id)


func _handle_hello(peer_id: int, request_id, payload: Dictionary) -> void:
	var player_name := String(payload.get("player_name", ""))
	var session := _room_manager.ensure_session(peer_id, player_name)
	_send_message(peer_id, "welcome", {
		"peer_id": peer_id,
		"display_name": session.display_name,
		"protocol_version": Protocol.SERVER_PROTOCOL_VERSION,
		"server_port": port,
	}, request_id)


func _handle_create_room(peer_id: int, request_id, payload: Dictionary) -> void:
	var result := _room_manager.create_room(peer_id, String(payload.get("player_name", "")), payload)
	if not bool(result.get("ok", false)):
		_send_error(peer_id, String(result.get("code", "create_failed")), String(result.get("message", "Room creation failed.")), request_id)
		return

	var room := result.get("room") as Room
	if room == null:
		_send_error(peer_id, "create_failed", "Room creation returned no room object.", request_id)
		return

	_send_message(peer_id, "room_created", {
		"room": room.snapshot(),
	}, request_id)
	_publish_room_snapshot(room)


func _handle_join_room(peer_id: int, request_id, payload: Dictionary) -> void:
	var room_id := String(payload.get("room_id", ""))
	var player_name := String(payload.get("player_name", ""))
	var result := _room_manager.join_room(peer_id, player_name, room_id)
	if not bool(result.get("ok", false)):
		_send_error(peer_id, String(result.get("code", "join_failed")), String(result.get("message", "Join room failed.")), request_id)
		return

	var room := result.get("room") as Room
	var session := result.get("session") as PlayerSession
	if room == null or session == null:
		_send_error(peer_id, "join_failed", "Join room returned incomplete state.", request_id)
		return

	_send_message(peer_id, "room_joined", {
		"room": room.snapshot(),
		"player": session.snapshot(),
	}, request_id)
	_publish_room_snapshot(room)


func _handle_leave_room(peer_id: int, request_id) -> void:
	var result := _room_manager.leave_room(peer_id)
	if not bool(result.get("ok", false)):
		_send_error(peer_id, String(result.get("code", "leave_failed")), String(result.get("message", "Leave room failed.")), request_id)
		return

	_send_message(peer_id, "room_left", {
		"room_id": String(result.get("removed_room_id", "")),
	}, request_id)
	_publish_room_change(result)


func _handle_start_match(peer_id: int, request_id) -> void:
	var result := _room_manager.start_match(peer_id)
	if not bool(result.get("ok", false)):
		_send_error(peer_id, String(result.get("code", "start_failed")), String(result.get("message", "Start match failed.")), request_id)
		return

	var room := result.get("room") as Room
	if room == null:
		_send_error(peer_id, "start_failed", "Start match returned no room object.", request_id)
		return

	_send_room_message(room, "match_started", {
		"room": room.snapshot(),
	}, -1, request_id)
	_publish_room_snapshot(room)


func _handle_player_state(peer_id: int, payload: Dictionary) -> void:
	var room := _room_manager.get_room_for_peer(peer_id)
	if room == null or not room.has_player(peer_id) or not room.is_playing():
		return

	var session := _room_manager.get_session(peer_id)
	var state := payload.duplicate(true)
	state["peer_id"] = peer_id
	state["display_name"] = session.display_name if session != null else "Guest%d" % peer_id
	state["server_time_unix"] = Time.get_unix_time_from_system()

	_send_room_message(
		room,
		"player_state",
		{"state": state},
		peer_id,
		null,
		MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	)


func _handle_level_changed(peer_id: int, request_id, payload: Dictionary) -> void:
	var level_index := int(payload.get("level_index", 0))
	var result := _room_manager.set_room_level(peer_id, level_index)
	if not bool(result.get("ok", false)):
		_send_error(peer_id, String(result.get("code", "level_change_failed")), String(result.get("message", "Level change failed.")), request_id)
		return

	var room := result.get("room") as Room
	if room == null:
		_send_error(peer_id, "level_change_failed", "Level change returned no room object.", request_id)
		return

	_send_room_message(room, "level_changed", {
		"level_index": int(result.get("level_index", level_index)),
		"room": room.snapshot(),
	}, -1, request_id)
	_publish_room_snapshot(room)


func _handle_level_complete(peer_id: int, request_id) -> void:
	var result := _room_manager.mark_room_complete(peer_id)
	if not bool(result.get("ok", false)):
		_send_error(peer_id, String(result.get("code", "level_complete_failed")), String(result.get("message", "Level completion failed.")), request_id)
		return

	var room := result.get("room") as Room
	if room == null:
		_send_error(peer_id, "level_complete_failed", "Level completion returned no room object.", request_id)
		return

	_send_room_message(room, "level_complete", {
		"room": room.snapshot(),
	}, -1, request_id)
	_publish_room_snapshot(room)


func _handle_world_event(peer_id: int, payload: Dictionary) -> void:
	var room := _room_manager.get_room_for_peer(peer_id)
	if room == null or not room.has_player(peer_id) or not room.is_playing():
		return

	var event := payload.duplicate(true)
	event["peer_id"] = peer_id
	_send_room_message(room, "world_event", {
		"event": event,
	}, peer_id)


func _handle_world_event_request(peer_id: int, request_id, payload: Dictionary) -> void:
	var room := _room_manager.get_room_for_peer(peer_id)
	if room == null or not room.has_player(peer_id) or not room.is_playing():
		print("[world_event_request] reject peer=%d action=- reason=not_in_playing_room" % peer_id)
		_send_error(peer_id, "not_in_playing_room", "Peer must be in a playing room before sending world event requests.", request_id)
		return

	if room.match_state == null:
		print("[world_event_request] reject peer=%d action=- room=%s reason=missing_match_state" % [peer_id, room.room_id])
		_send_error(peer_id, "missing_match_state", "Room has no active match state.", request_id)
		return

	var requested_level_index := int(payload.get("level_index", room.current_level_index))
	if requested_level_index != room.current_level_index:
		print("[world_event_request] reject peer=%d action=- room=%s reason=stale_level req=%d room=%d" % [peer_id, room.room_id, requested_level_index, room.current_level_index])
		_send_error(
			peer_id,
			"stale_level_request",
			"World event request was sent for a different level.",
			request_id
		)
		return

	var action := String(payload.get("action", payload.get("kind", ""))).strip_edges().to_lower()
	if action.is_empty():
		print("[world_event_request] reject peer=%d action=- room=%s reason=missing_world_action" % [peer_id, room.room_id])
		_send_error(peer_id, "missing_world_action", "World event request is missing an action.", request_id)
		return

	var accepted := false
	var broadcast_kind := ""
	match action:
		"key_collect":
			accepted = room.match_state.collect_key(peer_id)
			broadcast_kind = "key_collected"
		"door_open":
			accepted = room.match_state.open_door(peer_id)
			broadcast_kind = "door_opened"
		"goal_enter":
			accepted = room.match_state.set_goal(peer_id, true)
			broadcast_kind = "goal_entered"
		"goal_exit":
			accepted = room.match_state.set_goal(peer_id, false)
			broadcast_kind = "goal_exited"
		"player_death":
			accepted = room.match_state.set_player_alive(peer_id, false)
			broadcast_kind = "player_died"
		_:
			print("[world_event_request] reject peer=%d action=%s room=%s reason=unsupported_world_action" % [peer_id, action, room.room_id])
			_send_error(peer_id, "unsupported_world_action", "Unsupported world event action: %s" % action, request_id)
			return

	if not accepted:
		print("[world_event_request] reject peer=%d action=%s room=%s reason=world_action_rejected" % [peer_id, action, room.room_id])
		_send_error(peer_id, "world_action_rejected", "World event request rejected by server state.", request_id)
		return

	var event := {
		"kind": broadcast_kind,
		"request_action": action,
		"peer_id": peer_id,
		"level_index": room.current_level_index,
	}

	if payload.has("node_name"):
		event["node_name"] = String(payload.get("node_name", ""))

	print("[world_event_request] accept peer=%d action=%s room=%s event=%s level=%d" % [
		peer_id,
		action,
		room.room_id,
		broadcast_kind,
		room.current_level_index
	])
	_send_room_message(room, "world_event", {
		"event": event,
	})


func _publish_room_change(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return

	var room := result.get("room") as Room
	if room != null:
		_publish_room_snapshot(room)
	else:
		_broadcast_public_room_list()


func _publish_room_snapshot(room: Room) -> void:
	var snapshot := room.snapshot()
	for peer_id in room.player_ids():
		_send_message(peer_id, "room_updated", {
			"room": snapshot,
		})

	_broadcast_public_room_list()


func _broadcast_public_room_list() -> void:
	var payload := {
		"rooms": _room_manager.list_public_rooms(),
	}

	for raw_peer_id in _room_manager.sessions.keys():
		_send_message(int(raw_peer_id), "room_list", payload)


func _send_room_message(
	room: Room,
	message_type: String,
	payload: Dictionary = {},
	exclude_peer_id: int = -1,
	request_id = null,
	transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
) -> void:
	for target_peer_id in room.player_ids():
		if target_peer_id == exclude_peer_id:
			continue

		_send_message(target_peer_id, message_type, payload, request_id, transfer_mode)


func _send_message(
	peer_id: int,
	message_type: String,
	payload: Dictionary = {},
	request_id = null,
	transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
) -> void:
	var packet := Protocol.encode_message(message_type, payload, request_id)
	var send_error := _scene_multiplayer.send_bytes(
		packet,
		peer_id,
		transfer_mode
	)

	if send_error != OK:
		push_warning("Failed to send %s to peer %d (error %d)." % [message_type, peer_id, send_error])


func _send_error(peer_id: int, code: String, message: String, request_id = null) -> void:
	var packet := Protocol.encode_error(code, message, request_id)
	var send_error := _scene_multiplayer.send_bytes(
		packet,
		peer_id,
		MultiplayerPeer.TRANSFER_MODE_RELIABLE
	)

	if send_error != OK:
		push_warning("Failed to send error %s to peer %d (error %d)." % [code, peer_id, send_error])


func _load_runtime_config() -> void:
	port = _read_int_env("CREAMBUFFET_SERVER_PORT", DEFAULT_PORT)
	max_clients = _read_int_env("CREAMBUFFET_SERVER_MAX_CLIENTS", DEFAULT_MAX_CLIENTS)
	exit_after_ms = _read_int_env("CREAMBUFFET_SERVER_EXIT_AFTER_MS", 0)


func _read_int_env(variable_name: String, fallback: int) -> int:
	var raw_value := OS.get_environment(variable_name).strip_edges()
	if raw_value.is_empty():
		return fallback

	return int(raw_value)
