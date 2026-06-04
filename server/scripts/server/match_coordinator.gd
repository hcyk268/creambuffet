extends RefCounted
class_name MatchCoordinator

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const GameIds = preload("res://scripts/catalog/game_ids.gd")
const RoomManager = preload("res://scripts/lobby/room_manager.gd")
const ProtocolConstants = preload("res://scripts/network/protocol_constants.gd")
const Room = preload("res://scripts/lobby/room.gd")
const RoomBroadcaster = preload("res://scripts/server/room_broadcaster.gd")
const ServerDebugContext = preload("res://scripts/server/server_debug_context.gd")

var _room_manager: RoomManager
var _broadcaster: RoomBroadcaster
var _debug: ServerDebugContext


func setup(room_manager: RoomManager, broadcaster: RoomBroadcaster, debug: ServerDebugContext) -> void:
	_room_manager = room_manager
	_broadcaster = broadcaster
	_debug = debug


func try_level_transition(room: Room) -> void:
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

	_debug.info("level_transition %s from=%s(%d) to=%s(%d) match_complete=%s" % [
		_debug.room_label(room),
		GameCatalog.get_level_id_by_index(room.map_id, from_level_index),
		from_level_index,
		room.current_level_id,
		next_level_index,
		str(match_complete)
	])

	_broadcaster.send_room_message(room, ProtocolConstants.MESSAGE_LEVEL_TRANSITION, {
		"from_level_index": from_level_index,
		"to_level_index": next_level_index,
		"from_level_id": GameCatalog.get_level_id_by_index(room.map_id, from_level_index),
		"to_level_id": room.current_level_id,
		"match_complete": match_complete,
		"room": room.snapshot(),
	})
	_broadcaster.publish_room_snapshot(room)


func restart_current_level(room: Room, reason: String) -> void:
	if room == null:
		return

	var level_index := room.current_level_index
	var from_level_id := room.current_level_id
	room.set_level_index(level_index)
	_debug.info("level_restart %s level=%s(%d) reason=%s" % [
		_debug.room_label(room),
		from_level_id,
		level_index,
		reason
	])
	_broadcaster.send_room_message(room, ProtocolConstants.MESSAGE_LEVEL_TRANSITION, {
		"from_level_index": level_index,
		"to_level_index": level_index,
		"from_level_id": from_level_id,
		"to_level_id": room.current_level_id,
		"match_complete": false,
		"restart": true,
		"reason": reason,
		"room": room.snapshot(),
	})
	_broadcaster.publish_room_snapshot(room)


func maybe_reset_failed_level(room: Room) -> void:
	if room == null or room.match_state == null or not room.is_playing():
		return

	var failure: Dictionary = room.match_state.consume_level_failure(Time.get_ticks_msec())
	if failure.is_empty():
		return

	var from_level_index := room.current_level_index
	var failure_snapshot: Dictionary = room.match_state.failure_state_snapshot()
	var time_limit: Dictionary = failure_snapshot.get("time_limit", {})
	var death_limit: Dictionary = failure_snapshot.get("death_limit", {})
	_debug.info("level_reset_pending %s reason=%s hearts_remaining=%d time_remaining_ms=%d" % [
		_debug.room_label(room),
		String(failure.get("reason", "unknown")),
		int(death_limit.get("hearts_remaining", -1)),
		int(time_limit.get("remaining_ms", -1))
	])
	room.set_level_index(from_level_index)

	_broadcaster.send_room_message(room, ProtocolConstants.MESSAGE_LEVEL_TRANSITION, {
		"from_level_index": from_level_index,
		"to_level_index": room.current_level_index,
		"from_level_id": GameCatalog.get_level_id_by_index(room.map_id, from_level_index),
		"to_level_id": room.current_level_id,
		"match_complete": false,
		"room": room.snapshot(),
	})
	_broadcaster.publish_room_snapshot(room)


func poll_level_failures() -> void:
	for raw_room_id in _room_manager.rooms.keys():
		var room: Room = _room_manager.rooms.get(String(raw_room_id)) as Room
		if room == null or room.match_state == null or not room.is_playing():
			continue
		maybe_reset_failed_level(room)
