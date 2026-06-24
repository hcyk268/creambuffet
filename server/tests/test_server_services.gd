extends SceneTree

const Protocol = preload("res://scripts/network/protocol.gd")
const ProtocolConstants = preload("res://scripts/network/protocol_constants.gd")
const PlayerSession = preload("res://scripts/lobby/player_session.gd")
const Room = preload("res://scripts/lobby/room.gd")
const RoomManager = preload("res://scripts/lobby/room_manager.gd")
const MessageRouter = preload("res://scripts/server/message_router.gd")
const MatchCoordinator = preload("res://scripts/server/match_coordinator.gd")
const MatchMessageHandler = preload("res://scripts/server/match_message_handler.gd")
const RoomBroadcaster = preload("res://scripts/server/room_broadcaster.gd")
const ServerConfig = preload("res://scripts/server/server_config.gd")
const ServerDebugContext = preload("res://scripts/server/server_debug_context.gd")
const GameIds = preload("res://scripts/catalog/game_ids.gd")


class RecordingBroadcaster:
	extends RoomBroadcaster

	var sent_messages: Array[Dictionary] = []
	var sent_errors: Array[Dictionary] = []
	var room_messages: Array[Dictionary] = []
	var room_snapshots: Array[Dictionary] = []
	var room_changes: Array[Dictionary] = []

	func send_message(
		peer_id: int,
		message_type: String,
		payload: Dictionary = {},
		request_id = null,
		transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	) -> void:
		sent_messages.append({
			"peer_id": peer_id,
			"type": message_type,
			"payload": payload.duplicate(true),
			"request_id": request_id,
			"transfer_mode": transfer_mode,
		})

	func send_error(peer_id: int, code: String, message: String, request_id = null) -> void:
		sent_errors.append({
			"peer_id": peer_id,
			"code": code,
			"message": message,
			"request_id": request_id,
		})

	func send_room_message(
		room: Room,
		message_type: String,
		payload: Dictionary = {},
		exclude_peer_id: int = -1,
		request_id = null,
		transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	) -> void:
		room_messages.append({
			"room_id": room.room_id if room != null else "",
			"type": message_type,
			"payload": payload.duplicate(true),
			"exclude_peer_id": exclude_peer_id,
			"request_id": request_id,
			"transfer_mode": transfer_mode,
		})

	func publish_room_snapshot(room: Room) -> void:
		room_snapshots.append(room.snapshot() if room != null else {})

	func publish_room_change(result: Dictionary) -> void:
		room_changes.append(result.duplicate(true))


class RecordingDebugContext:
	extends ServerDebugContext

	var info_messages: Array[String] = []
	var warn_messages: Array[String] = []

	func info(message: String) -> void:
		info_messages.append(message)

	func warn(message: String) -> void:
		warn_messages.append(message)


class DummyMatchCoordinator:
	extends MatchCoordinator

	var restart_calls: Array[Dictionary] = []
	var transition_calls: Array[Dictionary] = []
	var reset_calls: Array[Dictionary] = []

	func restart_current_level(room: Room, reason: String) -> void:
		restart_calls.append({
			"room_id": room.room_id if room != null else "",
			"reason": reason,
		})

	func try_level_transition(room: Room) -> void:
		transition_calls.append({
			"room_id": room.room_id if room != null else "",
		})

	func maybe_reset_failed_level(room: Room) -> void:
		reset_calls.append({
			"room_id": room.room_id if room != null else "",
		})


func _init() -> void:
	var failures: Array[String] = []
	_test_server_config_defaults(failures)
	_test_server_config_env_overrides(failures)
	_test_match_coordinator_level_transition(failures)
	_test_match_coordinator_match_complete(failures)
	_test_room_reconnect_restores_player_state(failures)
	_test_goal_exit_requires_current_goal_occupancy(failures)
	_test_message_router_peer_connected(failures)
	_test_message_router_bad_packet(failures)
	_test_message_router_ping_dispatch(failures)
	_test_message_router_unsupported_message(failures)

	if failures.is_empty():
		print("Server service tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_server_config_defaults(failures: Array[String]) -> void:
	OS.set_environment("CREAMBUFFET_SERVER_PORT", "")
	OS.set_environment("CREAMBUFFET_SERVER_MAX_CLIENTS", "")
	OS.set_environment("CREAMBUFFET_SERVER_EXIT_AFTER_MS", "")
	var config: ServerConfig = ServerConfig.new().load_from_env()
	if config.port != ServerConfig.DEFAULT_PORT:
		failures.append("ServerConfig.load_from_env() did not fall back to DEFAULT_PORT.")
	if config.max_clients != ServerConfig.DEFAULT_MAX_CLIENTS:
		failures.append("ServerConfig.load_from_env() did not fall back to DEFAULT_MAX_CLIENTS.")
	if config.exit_after_ms != ServerConfig.DEFAULT_EXIT_AFTER_MS:
		failures.append("ServerConfig.load_from_env() did not fall back to DEFAULT_EXIT_AFTER_MS.")


func _test_server_config_env_overrides(failures: Array[String]) -> void:
	OS.set_environment("CREAMBUFFET_SERVER_PORT", "7123")
	OS.set_environment("CREAMBUFFET_SERVER_MAX_CLIENTS", "12")
	OS.set_environment("CREAMBUFFET_SERVER_EXIT_AFTER_MS", "4567")
	var config: ServerConfig = ServerConfig.new().load_from_env()
	if config.port != 7123:
		failures.append("ServerConfig.load_from_env() did not read CREAMBUFFET_SERVER_PORT.")
	if config.max_clients != 12:
		failures.append("ServerConfig.load_from_env() did not read CREAMBUFFET_SERVER_MAX_CLIENTS.")
	if config.exit_after_ms != 4567:
		failures.append("ServerConfig.load_from_env() did not read CREAMBUFFET_SERVER_EXIT_AFTER_MS.")
	OS.set_environment("CREAMBUFFET_SERVER_PORT", "")
	OS.set_environment("CREAMBUFFET_SERVER_MAX_CLIENTS", "")
	OS.set_environment("CREAMBUFFET_SERVER_EXIT_AFTER_MS", "")


func _test_match_coordinator_level_transition(failures: Array[String]) -> void:
	var room_manager: Variant = RoomManager.new()
	var broadcaster := RecordingBroadcaster.new()
	var debug := RecordingDebugContext.new()
	var coordinator: Variant = MatchCoordinator.new()
	coordinator.setup(room_manager, broadcaster, debug)

	var room := _make_room("ROOM01", "water", ["water_01", "water_02"], [1])
	room.start_match()
	room.match_state.patch_object_state("water01_door", {"opened": true})
	room.match_state.set_player_goal(1, "water01_goal")
	coordinator.try_level_transition(room)

	if room.current_level_index != 1 or room.current_level_id != "water_02":
		failures.append("MatchCoordinator.try_level_transition() did not advance to the next level.")
	if broadcaster.room_messages.is_empty():
		failures.append("MatchCoordinator.try_level_transition() did not send a level_transition room message.")
	else:
		var payload: Dictionary = broadcaster.room_messages[0].get("payload", {})
		if int(payload.get("to_level_index", -1)) != 1:
			failures.append("MatchCoordinator.try_level_transition() sent an unexpected to_level_index.")
	if broadcaster.room_snapshots.is_empty():
		failures.append("MatchCoordinator.try_level_transition() did not publish a room snapshot.")


func _test_match_coordinator_match_complete(failures: Array[String]) -> void:
	var room_manager: Variant = RoomManager.new()
	var broadcaster := RecordingBroadcaster.new()
	var debug := RecordingDebugContext.new()
	var coordinator: Variant = MatchCoordinator.new()
	coordinator.setup(room_manager, broadcaster, debug)

	var room := _make_room("ROOM02", "water", ["water_01"], [1])
	room.start_match()
	room.match_state.patch_object_state("water01_door", {"opened": true})
	room.match_state.set_player_goal(1, "water01_goal")
	coordinator.try_level_transition(room)

	if not room.is_complete():
		failures.append("MatchCoordinator.try_level_transition() did not mark the room complete at the final level.")
	if broadcaster.room_messages.is_empty():
		failures.append("MatchCoordinator.try_level_transition() did not send a final level_transition message.")
	else:
		var payload: Dictionary = broadcaster.room_messages[0].get("payload", {})
		if not bool(payload.get("match_complete", false)):
			failures.append("MatchCoordinator.try_level_transition() did not flag match_complete in the final transition.")


func _test_room_reconnect_restores_player_state(failures: Array[String]) -> void:
	var room_manager := RoomManager.new()
	var create_result: Dictionary = room_manager.create_room(1, "Player1", {
		"max_players": 2,
		"map_id": "water",
		"is_public": false,
	})
	if not bool(create_result.get("ok", false)):
		failures.append("Reconnect setup could not create a room.")
		return

	var room: Room = create_result.get("room") as Room
	var join_result: Dictionary = room_manager.join_room(2, "Player2", room.room_id)
	if not bool(join_result.get("ok", false)) or not bool(room_manager.start_match(1).get("ok", false)):
		failures.append("Reconnect setup could not start a two-player match.")
		return

	room.match_state.patch_player_state(1, {
		"position": {"x": 123.0, "y": 45.0},
		"key_count": 2,
	})
	var reconnect_token := room_manager.get_session(1).reconnect_token
	var disconnected: Dictionary = room_manager.disconnect_peer(1, Time.get_ticks_msec())
	if not bool(disconnected.get("reconnect_pending", false)) or room.has_player(1):
		failures.append("RoomManager.disconnect_peer() did not reserve the disconnected match player for reconnect.")
		return

	var resumed: Dictionary = room_manager.authenticate_hello(9, "DifferentName", reconnect_token)
	if not bool(resumed.get("resumed", false)) or not room.has_player(9):
		failures.append("RoomManager.authenticate_hello() did not restore the disconnected player into the active room.")
		return

	var restored_state: Dictionary = room.match_state.get_player_state(9)
	if int(restored_state.get("key_count", 0)) != 2:
		failures.append("RoomManager reconnect did not restore the player key state.")
	var position: Dictionary = restored_state.get("position", {})
	if float(position.get("x", 0.0)) != 123.0 or float(position.get("y", 0.0)) != 45.0:
		failures.append("RoomManager reconnect did not restore the player position.")


func _test_goal_exit_requires_current_goal_occupancy(failures: Array[String]) -> void:
	var room_manager: Variant = RoomManager.new()
	var broadcaster := RecordingBroadcaster.new()
	var debug := RecordingDebugContext.new()
	var coordinator: Variant = MatchCoordinator.new()
	coordinator.setup(room_manager, broadcaster, debug)
	var handler: Variant = MatchMessageHandler.new()
	handler.setup(room_manager, broadcaster, coordinator, debug)

	var create_result: Dictionary = room_manager.create_room(1, "Player1", {
		"max_players": 2,
		"map_id": "water",
		"is_public": false,
	})
	if not bool(create_result.get("ok", false)):
		failures.append("MatchMessageHandler setup could not create a two-player water room.")
		return

	var room: Room = create_result.get("room") as Room
	var join_result: Dictionary = room_manager.join_room(2, "Player2", room.room_id)
	if not bool(join_result.get("ok", false)):
		failures.append("MatchMessageHandler setup could not join the second player to the room.")
		return

	var start_result: Dictionary = room_manager.start_match(1)
	if not bool(start_result.get("ok", false)):
		failures.append("MatchMessageHandler setup could not start the two-player water match.")
		return

	room = start_result.get("room") as Room
	room.match_state.patch_object_state("water01_door", {"opened": true})

	handler.handle_world_action_request(1, "req-enter-1", {
		"action": GameIds.ACTION_GOAL_ENTER,
		"level_id": "water_01",
		"target_id": "water01_goal",
		"position": {"x": 325.0, "y": -43.0},
		"velocity": {"x": 0.0, "y": 0.0},
	})
	if not bool(room.match_state.get_player_state(1).get("at_goal", false)):
		failures.append("MatchMessageHandler did not mark player 1 at the goal after goal_enter.")
		return

	handler.handle_world_action_request(1, "req-exit-1", {
		"action": GameIds.ACTION_GOAL_EXIT,
		"level_id": "water_01",
		"target_id": "water01_goal",
		"position": {"x": 240.0, "y": -43.0},
		"velocity": {"x": 0.0, "y": 0.0},
	})
	if bool(room.match_state.get_player_state(1).get("at_goal", false)):
		failures.append("MatchMessageHandler kept player 1 at the goal after goal_exit with an updated outside position.")
		return

	handler.handle_world_action_request(2, "req-enter-2", {
		"action": GameIds.ACTION_GOAL_ENTER,
		"level_id": "water_01",
		"target_id": "water01_goal",
		"position": {"x": 325.0, "y": -43.0},
		"velocity": {"x": 0.0, "y": 0.0},
	})

	if room.is_complete():
		failures.append("MatchMessageHandler completed the room even though player 1 had already left the goal.")
	if room.current_level_index != 0:
		failures.append("MatchMessageHandler advanced the level even though not all players were simultaneously inside the goal.")


func _test_message_router_peer_connected(failures: Array[String]) -> void:
	var room_manager: Variant = RoomManager.new()
	var broadcaster := RecordingBroadcaster.new()
	var debug := RecordingDebugContext.new()
	var coordinator := DummyMatchCoordinator.new()
	var router: Variant = MessageRouter.new()
	router.setup(room_manager, broadcaster, coordinator, 7000, debug)
	router.handle_peer_connected(4)

	if broadcaster.sent_messages.is_empty():
		failures.append("MessageRouter.handle_peer_connected() did not send a welcome message.")
	else:
		var message: Dictionary = broadcaster.sent_messages[0]
		if String(message.get("type", "")) != ProtocolConstants.MESSAGE_WELCOME:
			failures.append("MessageRouter.handle_peer_connected() sent the wrong message type.")
		var payload: Dictionary = message.get("payload", {})
		if int(payload.get("peer_id", -1)) != 4:
			failures.append("MessageRouter.handle_peer_connected() sent an unexpected peer_id.")


func _test_message_router_bad_packet(failures: Array[String]) -> void:
	var room_manager: Variant = RoomManager.new()
	var broadcaster := RecordingBroadcaster.new()
	var debug := RecordingDebugContext.new()
	var coordinator := DummyMatchCoordinator.new()
	var router: Variant = MessageRouter.new()
	router.setup(room_manager, broadcaster, coordinator, 7000, debug)
	router.handle_peer_packet(5, "{bad".to_utf8_buffer())

	if broadcaster.sent_errors.is_empty():
		failures.append("MessageRouter.handle_peer_packet() did not reject invalid JSON.")
	else:
		var error_payload: Dictionary = broadcaster.sent_errors[0]
		if String(error_payload.get("code", "")) != "bad_json":
			failures.append("MessageRouter.handle_peer_packet() returned the wrong bad-packet error code.")
	if debug.warn_messages.is_empty():
		failures.append("MessageRouter.handle_peer_packet() did not log a warning for invalid packets.")


func _test_message_router_ping_dispatch(failures: Array[String]) -> void:
	var room_manager: Variant = RoomManager.new()
	var broadcaster := RecordingBroadcaster.new()
	var debug := RecordingDebugContext.new()
	var coordinator := DummyMatchCoordinator.new()
	var router: Variant = MessageRouter.new()
	router.setup(room_manager, broadcaster, coordinator, 7000, debug)

	var packet: PackedByteArray = Protocol.encode_message(ProtocolConstants.MESSAGE_PING, {}, "req-ping")
	router.handle_peer_packet(6, packet)

	if broadcaster.sent_messages.is_empty():
		failures.append("MessageRouter.handle_peer_packet() did not dispatch ping to pong.")
	else:
		var message: Dictionary = broadcaster.sent_messages[0]
		if String(message.get("type", "")) != ProtocolConstants.MESSAGE_PONG:
			failures.append("MessageRouter.handle_peer_packet() did not return pong for ping.")
		if String(message.get("request_id", "")) != "req-ping":
			failures.append("MessageRouter.handle_peer_packet() did not preserve the ping request_id.")


func _test_message_router_unsupported_message(failures: Array[String]) -> void:
	var room_manager: Variant = RoomManager.new()
	var broadcaster := RecordingBroadcaster.new()
	var debug := RecordingDebugContext.new()
	var coordinator := DummyMatchCoordinator.new()
	var router: Variant = MessageRouter.new()
	router.setup(room_manager, broadcaster, coordinator, 7000, debug)

	var packet: PackedByteArray = Protocol.encode_message("mystery_type", {}, "req-unknown")
	router.handle_peer_packet(7, packet)

	if broadcaster.sent_errors.is_empty():
		failures.append("MessageRouter.handle_peer_packet() did not reject unsupported message types.")
	else:
		var error_payload: Dictionary = broadcaster.sent_errors[0]
		if String(error_payload.get("code", "")) != "unsupported_type":
			failures.append("MessageRouter.handle_peer_packet() returned the wrong unsupported-type error code.")
		if String(error_payload.get("request_id", "")) != "req-unknown":
			failures.append("MessageRouter.handle_peer_packet() did not preserve request_id for unsupported message errors.")


func _make_room(room_id: String, map_id: String, level_ids: Array[String], player_ids: Array[int]) -> Room:
	var room := Room.new(room_id, 1, true, maxi(player_ids.size(), 1), level_ids.size(), false, map_id, level_ids)
	for peer_id in player_ids:
		room.try_add_player(PlayerSession.new(peer_id, "Player%d" % peer_id))
	return room
