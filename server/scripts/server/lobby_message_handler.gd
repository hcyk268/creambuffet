extends RefCounted
class_name LobbyMessageHandler

const Protocol = preload("res://scripts/network/protocol.gd")
const ProtocolConstants = preload("res://scripts/network/protocol_constants.gd")
const PlayerSession = preload("res://scripts/lobby/player_session.gd")
const Room = preload("res://scripts/lobby/room.gd")
const RoomManager = preload("res://scripts/lobby/room_manager.gd")
const RoomBroadcaster = preload("res://scripts/server/room_broadcaster.gd")
const ServerDebugContext = preload("res://scripts/server/server_debug_context.gd")

var _room_manager: RoomManager
var _broadcaster: RoomBroadcaster
var _debug: ServerDebugContext
var _port := 0


func setup(room_manager: RoomManager, broadcaster: RoomBroadcaster, port: int, debug: ServerDebugContext) -> void:
	_room_manager = room_manager
	_broadcaster = broadcaster
	_port = port
	_debug = debug


func handle_peer_connected(peer_id: int) -> void:
	var session: PlayerSession = _room_manager.ensure_session(peer_id)
	_debug.info("peer_connected peer=%d name=%s" % [peer_id, session.display_name])
	_broadcaster.send_message(peer_id, ProtocolConstants.MESSAGE_WELCOME, {
		"peer_id": peer_id,
		"protocol_version": Protocol.SERVER_PROTOCOL_VERSION,
		"server_port": _port,
	})


func handle_peer_disconnected(peer_id: int) -> void:
	_debug.info("peer_disconnected peer=%d" % peer_id)
	var result: Dictionary = _room_manager.unregister_peer(peer_id)
	_broadcaster.publish_room_change(result)


func handle_hello(peer_id: int, request_id, payload: Dictionary) -> void:
	var player_name := String(payload.get("player_name", ""))
	var session: PlayerSession = _room_manager.ensure_session(peer_id, player_name)
	_broadcaster.send_message(peer_id, ProtocolConstants.MESSAGE_WELCOME, {
		"peer_id": peer_id,
		"display_name": session.display_name,
		"protocol_version": Protocol.SERVER_PROTOCOL_VERSION,
		"server_port": _port,
	}, request_id)


func handle_ping(peer_id: int, request_id) -> void:
	_broadcaster.send_message(peer_id, ProtocolConstants.MESSAGE_PONG, {
		"server_time_unix": Time.get_unix_time_from_system(),
	}, request_id)


func handle_list_rooms(peer_id: int, request_id) -> void:
	_broadcaster.send_message(peer_id, ProtocolConstants.MESSAGE_ROOM_LIST, {
		"rooms": _room_manager.list_public_rooms(),
	}, request_id)


func handle_create_room(peer_id: int, request_id, payload: Dictionary) -> void:
	var result: Dictionary = _room_manager.create_room(peer_id, String(payload.get("player_name", "")), payload)
	if not bool(result.get("ok", false)):
		_broadcaster.send_error(peer_id, String(result.get("code", "create_failed")), String(result.get("message", "Room creation failed.")), request_id)
		return

	var room: Room = result.get("room") as Room
	if room == null:
		_broadcaster.send_error(peer_id, "create_failed", "Room creation returned no room object.", request_id)
		return

	_broadcaster.send_message(peer_id, ProtocolConstants.MESSAGE_ROOM_CREATED, {
		"room": room.snapshot(),
	}, request_id)
	_debug.info("room_created peer=%d %s public=%s max_players=%d level_count=%d" % [
		peer_id,
		_debug.room_label(room),
		str(room.is_public),
		room.max_players,
		room.level_ids.size()
	])
	_broadcaster.publish_room_snapshot(room)


func handle_join_room(peer_id: int, request_id, payload: Dictionary) -> void:
	var room_id := String(payload.get("room_id", ""))
	var player_name := String(payload.get("player_name", ""))
	var result: Dictionary = _room_manager.join_room(peer_id, player_name, room_id)
	if not bool(result.get("ok", false)):
		_broadcaster.send_error(peer_id, String(result.get("code", "join_failed")), String(result.get("message", "Join room failed.")), request_id)
		return

	var room: Room = result.get("room") as Room
	var session: PlayerSession = result.get("session") as PlayerSession
	if room == null or session == null:
		_broadcaster.send_error(peer_id, "join_failed", "Join room returned incomplete state.", request_id)
		return

	_broadcaster.send_message(peer_id, ProtocolConstants.MESSAGE_ROOM_JOINED, {
		"room": room.snapshot(),
		"player": session.snapshot(),
	}, request_id)
	_debug.info("room_joined peer=%d name=%s %s" % [peer_id, session.display_name, _debug.room_label(room)])
	_broadcaster.publish_room_snapshot(room)


func handle_leave_room(peer_id: int, request_id) -> void:
	var result: Dictionary = _room_manager.leave_room(peer_id)
	if not bool(result.get("ok", false)):
		_broadcaster.send_error(peer_id, String(result.get("code", "leave_failed")), String(result.get("message", "Leave room failed.")), request_id)
		return

	_broadcaster.send_message(peer_id, ProtocolConstants.MESSAGE_ROOM_LEFT, {
		"room_id": String(result.get("removed_room_id", "")),
	}, request_id)
	var room: Room = result.get("room") as Room
	_debug.info("room_left peer=%d room=%s removed_room=%s remaining_players=%d" % [
		peer_id,
		String(result.get("removed_room_id", "")),
		str(bool(result.get("removed_room", false))),
		room.player_ids().size() if room != null else 0
	])
	_broadcaster.publish_room_change(result)


func handle_start_match(peer_id: int, request_id) -> void:
	var result: Dictionary = _room_manager.start_match(peer_id)
	if not bool(result.get("ok", false)):
		_broadcaster.send_error(peer_id, String(result.get("code", "start_failed")), String(result.get("message", "Start match failed.")), request_id)
		return

	var room: Room = result.get("room") as Room
	if room == null:
		_broadcaster.send_error(peer_id, "start_failed", "Start match returned no room object.", request_id)
		return

	_broadcaster.send_room_message(room, ProtocolConstants.MESSAGE_MATCH_STARTED, {
		"room": room.snapshot(),
	}, -1, request_id)
	_debug.info("match_started by_peer=%d %s" % [peer_id, _debug.room_label(room)])
	_broadcaster.publish_room_snapshot(room)


func handle_set_room_map(peer_id: int, request_id, payload: Dictionary) -> void:
	var map_id := String(payload.get("map_id", ""))
	var result: Dictionary = _room_manager.set_room_map(peer_id, map_id)
	if not bool(result.get("ok", false)):
		_broadcaster.send_error(
			peer_id,
			String(result.get("code", "set_map_failed")),
			String(result.get("message", "Could not update room map.")),
			request_id
		)
		return

	var room: Room = result.get("room") as Room
	if room == null:
		_broadcaster.send_error(peer_id, "set_map_failed", "Set room map returned no room object.", request_id)
		return

	_broadcaster.send_message(peer_id, ProtocolConstants.MESSAGE_ROOM_MAP_UPDATED, {
		"room": room.snapshot(),
	}, request_id)
	_debug.info("room_map_updated by_peer=%d %s level_count=%d" % [peer_id, _debug.room_label(room), room.level_ids.size()])
	_broadcaster.publish_room_snapshot(room)
