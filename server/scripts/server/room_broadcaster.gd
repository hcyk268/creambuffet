extends RefCounted
class_name RoomBroadcaster

const Protocol = preload("res://scripts/network/protocol.gd")
const ProtocolConstants = preload("res://scripts/network/protocol_constants.gd")
const Room = preload("res://scripts/lobby/room.gd")
const RoomManager = preload("res://scripts/lobby/room_manager.gd")
const ServerDebugContext = preload("res://scripts/server/server_debug_context.gd")

var _scene_multiplayer: SceneMultiplayer
var _room_manager: RoomManager
var _debug: ServerDebugContext


func setup(scene_multiplayer: SceneMultiplayer, room_manager: RoomManager, debug: ServerDebugContext) -> void:
	_scene_multiplayer = scene_multiplayer
	_room_manager = room_manager
	_debug = debug


func publish_room_change(result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return

	var room: Room = result.get("room") as Room
	if room != null:
		publish_room_snapshot(room)
	else:
		broadcast_public_room_list()


func publish_room_snapshot(room: Room) -> void:
	var snapshot := room.snapshot()
	for peer_id in room.player_ids():
		send_message(peer_id, ProtocolConstants.MESSAGE_ROOM_UPDATED, {
			"room": snapshot,
		})

	broadcast_public_room_list()


func broadcast_public_room_list() -> void:
	var payload := {
		"rooms": _room_manager.list_public_rooms(),
	}

	for raw_peer_id in _room_manager.sessions.keys():
		send_message(int(raw_peer_id), ProtocolConstants.MESSAGE_ROOM_LIST, payload)


func send_room_message(
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

		send_message(target_peer_id, message_type, payload, request_id, transfer_mode)


func send_message(
	peer_id: int,
	message_type: String,
	payload: Dictionary = {},
	request_id = null,
	transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
) -> void:
	var packet := Protocol.encode_message(message_type, payload, request_id)
	var send_error := _scene_multiplayer.send_bytes(packet, peer_id, transfer_mode)
	if send_error != OK:
		_debug.warn("send_failed type=%s peer=%d error=%d" % [message_type, peer_id, send_error])


func send_error(peer_id: int, code: String, message: String, request_id = null) -> void:
	var packet := Protocol.encode_error(code, message, request_id)
	var send_error := _scene_multiplayer.send_bytes(
		packet,
		peer_id,
		MultiplayerPeer.TRANSFER_MODE_RELIABLE
	)
	if send_error != OK:
		_debug.warn("send_error_failed code=%s peer=%d error=%d" % [code, peer_id, send_error])
