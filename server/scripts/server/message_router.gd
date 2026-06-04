extends RefCounted
class_name MessageRouter

const Protocol = preload("res://scripts/network/protocol.gd")
const ProtocolConstants = preload("res://scripts/network/protocol_constants.gd")
const RoomBroadcaster = preload("res://scripts/server/room_broadcaster.gd")
const MatchCoordinator = preload("res://scripts/server/match_coordinator.gd")
const ServerDebugContext = preload("res://scripts/server/server_debug_context.gd")
const LobbyMessageHandler = preload("res://scripts/server/lobby_message_handler.gd")
const MatchMessageHandler = preload("res://scripts/server/match_message_handler.gd")

var _broadcaster: RoomBroadcaster
var _debug: ServerDebugContext
var _lobby_handler: LobbyMessageHandler
var _match_handler: MatchMessageHandler


func setup(
	room_manager,
	broadcaster: RoomBroadcaster,
	coordinator: MatchCoordinator,
	port: int,
	debug: ServerDebugContext
) -> void:
	_broadcaster = broadcaster
	_debug = debug
	_lobby_handler = LobbyMessageHandler.new()
	_lobby_handler.setup(room_manager, broadcaster, port, debug)
	_match_handler = MatchMessageHandler.new()
	_match_handler.setup(room_manager, broadcaster, coordinator, debug)


func handle_peer_connected(peer_id: int) -> void:
	_lobby_handler.handle_peer_connected(peer_id)


func handle_peer_disconnected(peer_id: int) -> void:
	_lobby_handler.handle_peer_disconnected(peer_id)


func handle_peer_packet(peer_id: int, packet: PackedByteArray) -> void:
	var decoded: Dictionary = Protocol.decode_packet(packet)
	if not bool(decoded.get("ok", false)):
		_debug.warn("packet_decode_failed peer=%d bytes=%d code=%s message=%s" % [
			peer_id,
			packet.size(),
			String(decoded.get("code", "bad_packet")),
			String(decoded.get("message", "Packet could not be decoded."))
		])
		_broadcaster.send_error(
			peer_id,
			String(decoded.get("code", "bad_packet")),
			String(decoded.get("message", "Packet could not be decoded."))
		)
		return

	var message_type := String(decoded.get("type", ""))
	var request_id = decoded.get("request_id", null)
	var payload: Dictionary = decoded.get("payload", {})

	match message_type:
		ProtocolConstants.MESSAGE_HELLO:
			_lobby_handler.handle_hello(peer_id, request_id, payload)
		ProtocolConstants.MESSAGE_PING:
			_lobby_handler.handle_ping(peer_id, request_id)
		ProtocolConstants.MESSAGE_LIST_ROOMS:
			_lobby_handler.handle_list_rooms(peer_id, request_id)
		ProtocolConstants.MESSAGE_CREATE_ROOM:
			_lobby_handler.handle_create_room(peer_id, request_id, payload)
		ProtocolConstants.MESSAGE_JOIN_ROOM:
			_lobby_handler.handle_join_room(peer_id, request_id, payload)
		ProtocolConstants.MESSAGE_LEAVE_ROOM:
			_lobby_handler.handle_leave_room(peer_id, request_id)
		ProtocolConstants.MESSAGE_START_MATCH:
			_lobby_handler.handle_start_match(peer_id, request_id)
		ProtocolConstants.MESSAGE_SET_ROOM_MAP:
			_lobby_handler.handle_set_room_map(peer_id, request_id, payload)
		ProtocolConstants.MESSAGE_PLAYER_STATE:
			_match_handler.handle_player_state(peer_id, payload)
		ProtocolConstants.MESSAGE_LEVEL_CHANGED:
			_match_handler.handle_level_changed(peer_id, request_id)
		ProtocolConstants.MESSAGE_LEVEL_COMPLETE:
			_match_handler.handle_level_complete(peer_id, request_id)
		ProtocolConstants.MESSAGE_WORLD_EVENT_REQUEST:
			_match_handler.handle_world_action_request(peer_id, request_id, payload, true)
		ProtocolConstants.MESSAGE_WORLD_ACTION_REQUEST:
			_match_handler.handle_world_action_request(peer_id, request_id, payload)
		_:
			_debug.warn("unsupported_message peer=%d type=%s request=%s" % [
				peer_id,
				message_type,
				_debug.request_label(request_id)
			])
			_broadcaster.send_error(peer_id, "unsupported_type", "Unsupported message type: %s" % message_type, request_id)
