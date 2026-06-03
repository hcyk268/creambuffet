extends Node

const Protocol = preload("res://scripts/network/protocol.gd")
const PlayerSession = preload("res://scripts/lobby/player_session.gd")
const Room = preload("res://scripts/lobby/room.gd")
const RoomManager = preload("res://scripts/lobby/room_manager.gd")
const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")

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
		"set_room_map":
			_handle_set_room_map(peer_id, request_id, payload)
		"player_state":
			_handle_player_state(peer_id, payload)
		"level_changed":
			_handle_level_changed(peer_id, request_id, payload)
		"level_complete":
			_handle_level_complete(peer_id, request_id)
		"world_event_request":
			_handle_world_action_request(peer_id, request_id, payload, true)
		"world_action_request":
			_handle_world_action_request(peer_id, request_id, payload)
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


func _handle_set_room_map(peer_id: int, request_id, payload: Dictionary) -> void:
	var map_id := String(payload.get("map_id", ""))
	var result := _room_manager.set_room_map(peer_id, map_id)
	if not bool(result.get("ok", false)):
		_send_error(
			peer_id,
			String(result.get("code", "set_map_failed")),
			String(result.get("message", "Could not update room map.")),
			request_id
		)
		return

	var room := result.get("room") as Room
	if room == null:
		_send_error(peer_id, "set_map_failed", "Set room map returned no room object.", request_id)
		return

	_send_message(peer_id, "room_map_updated", {
		"room": room.snapshot(),
	}, request_id)
	_publish_room_snapshot(room)


func _handle_player_state(peer_id: int, payload: Dictionary) -> void:
	var room := _room_manager.get_room_for_peer(peer_id)
	if room == null or not room.has_player(peer_id) or not room.is_playing():
		return

	var session := _room_manager.get_session(peer_id)
	var state := payload.duplicate(true)
	if int(state.get("level_index", room.current_level_index)) != room.current_level_index:
		return

	state.erase("peer_id")
	state.erase("display_name")
	state.erase("key_count")
	state.erase("level_has_key")
	state.erase("level_has_door")
	state["peer_id"] = peer_id
	state["display_name"] = session.display_name if session != null else "Guest%d" % peer_id
	state["server_time_unix"] = Time.get_unix_time_from_system()
	state["level_id"] = room.current_level_id
	state.erase("push_intents")
	state.erase("pushable_states")

	var pushable_controls: Array[Dictionary] = []
	var push_box_events: Array[Dictionary] = []
	var hazard_events: Array[Dictionary] = []
	var timed_events: Array[Dictionary] = []
	if room.match_state != null:
		room.match_state.update_player_runtime(peer_id, payload)
		timed_events = room.match_state.advance_timed_mechanics()
		hazard_events = room.match_state.apply_automatic_fall_reset(peer_id)
		push_box_events = room.match_state.apply_push_box_observations(peer_id, payload.get("pushable_states", []))
		var server_player_state := room.match_state.get_player_state(peer_id)
		if not server_player_state.is_empty():
			state["key_count"] = int(server_player_state.get("key_count", 0))
		pushable_controls = room.match_state.apply_push_intents(peer_id, payload.get("push_intents", []))

	_send_room_message(
		room,
		"player_state",
		{"state": state},
		peer_id,
		null,
		MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	)

	_send_room_message(
		room,
		"pushable_control",
		{
			"level_index": room.current_level_index,
			"level_id": room.current_level_id,
			"controls": pushable_controls,
		},
		-1,
		null,
		MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	)

	for event in push_box_events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var event_kind := String(Dictionary(event).get("kind", ""))
		var transfer_mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
		if event_kind == "push_box_state":
			transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
		_send_room_message(
			room,
			"world_event",
			{"event": event},
			-1,
			null,
			transfer_mode
		)

	for event in hazard_events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		_send_room_message(
			room,
			"world_event",
			{"event": event},
			-1,
			null,
			MultiplayerPeer.TRANSFER_MODE_RELIABLE
		)

	for event in timed_events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		_send_room_message(
			room,
			"world_event",
			{"event": event},
			-1,
			null,
			MultiplayerPeer.TRANSFER_MODE_RELIABLE
		)


func _handle_level_changed(peer_id: int, request_id, payload: Dictionary) -> void:
	var room := _room_manager.get_room_for_peer(peer_id)
	if room != null:
		push_warning(
			"Ignored client level_changed from peer %d in room %s. Level transition is server-authoritative." % [
				peer_id,
				room.room_id
			]
		)
	else:
		push_warning("Ignored client level_changed from peer %d (not in room)." % peer_id)

	_send_error(peer_id, "level_change_blocked", "Client-driven level changes are disabled.", request_id)


func _handle_level_complete(peer_id: int, request_id) -> void:
	var room := _room_manager.get_room_for_peer(peer_id)
	if room != null:
		push_warning(
			"Ignored client level_complete from peer %d in room %s. Completion is server-authoritative." % [
				peer_id,
				room.room_id
			]
		)
	else:
		push_warning("Ignored client level_complete from peer %d (not in room)." % peer_id)

	_send_error(peer_id, "level_complete_blocked", "Client-driven level completion is disabled.", request_id)


func _handle_world_action_request(peer_id: int, request_id, payload: Dictionary, legacy: bool = false) -> void:
	var room := _room_manager.get_room_for_peer(peer_id)
	if room == null or not room.has_player(peer_id) or not room.is_playing():
		print("[world_action_request] reject peer=%d action=- reason=not_in_playing_room" % peer_id)
		_send_error(peer_id, "not_in_playing_room", "Peer must be in a playing room before sending world action requests.", request_id)
		return

	if room.match_state == null:
		print("[world_action_request] reject peer=%d action=- room=%s reason=missing_match_state" % [peer_id, room.room_id])
		_send_error(peer_id, "missing_match_state", "Room has no active match state.", request_id)
		return

	var requested_level_id := String(payload.get("level_id", ""))
	if requested_level_id.is_empty() and payload.has("level_index"):
		requested_level_id = GameCatalog.get_level_id_by_index(room.map_id, int(payload.get("level_index", room.current_level_index)))
	if requested_level_id.is_empty():
		requested_level_id = room.current_level_id

	if requested_level_id != room.current_level_id:
		print("[world_action_request] reject peer=%d action=- room=%s reason=stale_level req=%s room=%s" % [peer_id, room.room_id, requested_level_id, room.current_level_id])
		_send_error(
			peer_id,
			"stale_level_request",
			"World event request was sent for a different level.",
			request_id
		)
		return

	var action := String(payload.get("action", payload.get("kind", ""))).strip_edges().to_lower()
	if action.is_empty():
		print("[world_action_request] reject peer=%d action=- room=%s reason=missing_world_action" % [peer_id, room.room_id])
		_send_error(peer_id, "missing_world_action", "World event request is missing an action.", request_id)
		return

	var target_id := String(payload.get("target_id", payload.get("sync_id", ""))).strip_edges()
	if target_id.is_empty() and (legacy or payload.has("node_name")):
		target_id = _infer_legacy_target_id(room.current_level_id, action)

	var normalized_payload := payload.duplicate(true)
	normalized_payload["level_id"] = requested_level_id
	normalized_payload["target_id"] = target_id
	normalized_payload["legacy"] = legacy

	# World action requests for overlap-driven mechanics can arrive before the
	# next player_state packet. Apply any embedded runtime snapshot first so the
	# server evaluates the action against the caller's latest known position.
	if normalized_payload.has("position") or normalized_payload.has("velocity"):
		room.match_state.update_player_runtime(peer_id, normalized_payload)

	var result := room.match_state.apply_world_action(peer_id, action, target_id, normalized_payload)
	if not bool(result.get("ok", false)):
		print("[world_action_request] reject peer=%d action=%s room=%s target=%s reason=%s" % [
			peer_id,
			action,
			room.room_id,
			target_id,
			String(result.get("code", "world_action_rejected"))
		])
		_send_error(
			peer_id,
			String(result.get("code", "world_action_rejected")),
			String(result.get("message", "World action rejected by server state.")),
			request_id
		)
		return

	var events_to_broadcast: Array = result.get("events", [])
	var level_failed := false
	for event in events_to_broadcast:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var event_dict: Dictionary = event
		if String(event_dict.get("kind", "")) == "level_failed":
			level_failed = true
		print("[world_action_request] accept peer=%d action=%s room=%s event=%s level=%s target=%s" % [
			peer_id,
			action,
			room.room_id,
			String(event_dict.get("kind", "")),
			room.current_level_id,
			String(event_dict.get("target_id", ""))
		])
		_send_room_message(room, "world_event", {
			"event": event_dict,
		})

	if level_failed:
		_restart_current_level(room, "level_failed")
		return

	_try_level_transition(room)


func _infer_legacy_target_id(level_id: String, action: String) -> String:
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


func _try_level_transition(room: Room) -> void:
	if room == null or room.match_state == null:
		return

	if not room.match_state.can_complete_level():
		return

	var from_level_index := room.current_level_index
	var next_level_index := from_level_index + 1
	var match_complete := next_level_index >= room.level_ids.size()
	if match_complete:
		next_level_index = from_level_index
		room.mark_complete()
	else:
		room.set_level_index(next_level_index)

	_send_room_message(room, "level_transition", {
		"from_level_index": from_level_index,
		"to_level_index": next_level_index,
		"from_level_id": GameCatalog.get_level_id_by_index(room.map_id, from_level_index),
		"to_level_id": room.current_level_id,
		"match_complete": match_complete,
		"room": room.snapshot(),
	})
	_publish_room_snapshot(room)


func _restart_current_level(room: Room, reason: String) -> void:
	if room == null:
		return

	var level_index := room.current_level_index
	var from_level_id := room.current_level_id
	room.set_level_index(level_index)
	_send_room_message(room, "level_transition", {
		"from_level_index": level_index,
		"to_level_index": level_index,
		"from_level_id": from_level_id,
		"to_level_id": room.current_level_id,
		"match_complete": false,
		"restart": true,
		"reason": reason,
		"room": room.snapshot(),
	})
	_publish_room_snapshot(room)


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
