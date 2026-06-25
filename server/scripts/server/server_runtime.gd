extends RefCounted
class_name ServerRuntime

const Protocol = preload("res://scripts/network/protocol.gd")
const RoomManager = preload("res://scripts/lobby/room_manager.gd")
const ServerConfig = preload("res://scripts/server/server_config.gd")
const ServerDebugContext = preload("res://scripts/server/server_debug_context.gd")
const RoomBroadcaster = preload("res://scripts/server/room_broadcaster.gd")
const MatchCoordinator = preload("res://scripts/server/match_coordinator.gd")
const MessageRouter = preload("res://scripts/server/message_router.gd")

var _config: ServerConfig
var _scene_multiplayer: SceneMultiplayer
var _debug: ServerDebugContext
var _started_at_ms := 0
var _startup_error := ""
var _network_peer := ENetMultiplayerPeer.new()
var _room_manager := RoomManager.new()
var _room_broadcaster: RoomBroadcaster
var _match_coordinator: MatchCoordinator
var _message_router: MessageRouter


func start(scene_multiplayer: SceneMultiplayer, config: ServerConfig, debug: ServerDebugContext) -> bool:
	_config = config
	_scene_multiplayer = scene_multiplayer
	_debug = debug
	_started_at_ms = Time.get_ticks_msec()
	_startup_error = ""

	if _scene_multiplayer == null:
		_startup_error = "Default multiplayer interface is not SceneMultiplayer."
		return false

	var create_error: int = _network_peer.create_server(_config.port, _config.max_clients)
	if create_error != OK:
		_startup_error = "Could not start ENet server on port %d (error %d)." % [_config.port, create_error]
		return false

	_scene_multiplayer.multiplayer_peer = _network_peer
	_scene_multiplayer.peer_connected.connect(_on_peer_connected)
	_scene_multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_scene_multiplayer.peer_packet.connect(_on_peer_packet)
	_wire_runtime_services()

	_debug.info("listening port=%d max_clients=%d protocol=%d" % [
		_config.port,
		_config.max_clients,
		Protocol.SERVER_PROTOCOL_VERSION
	])
	return true


func startup_error_message() -> String:
	return _startup_error


func process_frame() -> bool:
	if _match_coordinator == null:
		return false
	for room_change in _room_manager.expire_disconnected_sessions():
		_room_broadcaster.publish_room_change(room_change)

	if _config.exit_after_ms <= 0:
		_match_coordinator.poll_level_failures()
		return false

	if Time.get_ticks_msec() - _started_at_ms >= _config.exit_after_ms:
		_debug.info("shutdown reason=exit_timer elapsed_ms=%d" % (Time.get_ticks_msec() - _started_at_ms))
		return true

	_match_coordinator.poll_level_failures()
	return false


func _on_peer_connected(peer_id: int) -> void:
	_message_router.handle_peer_connected(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	_message_router.handle_peer_disconnected(peer_id)


func _on_peer_packet(peer_id: int, packet: PackedByteArray) -> void:
	_message_router.handle_peer_packet(peer_id, packet)


func _wire_runtime_services() -> void:
	_room_broadcaster = RoomBroadcaster.new()
	_room_broadcaster.setup(_scene_multiplayer, _room_manager, _debug)

	_match_coordinator = MatchCoordinator.new()
	_match_coordinator.setup(_room_manager, _room_broadcaster, _debug)

	_message_router = MessageRouter.new()
	_message_router.setup(
		_room_manager,
		_room_broadcaster,
		_match_coordinator,
		_config.port,
		_debug
	)
