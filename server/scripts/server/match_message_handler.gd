extends RefCounted
class_name MatchMessageHandler

const ProtocolConstants = preload("res://scripts/network/protocol_constants.gd")
const PlayerSession = preload("res://scripts/lobby/player_session.gd")
const Room = preload("res://scripts/lobby/room.gd")
const RoomManager = preload("res://scripts/lobby/room_manager.gd")
const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const GameIds = preload("res://scripts/catalog/game_ids.gd")
const RoomBroadcaster = preload("res://scripts/server/room_broadcaster.gd")
const MatchCoordinator = preload("res://scripts/server/match_coordinator.gd")
const ServerDebugContext = preload("res://scripts/server/server_debug_context.gd")

var _room_manager: RoomManager
var _broadcaster: RoomBroadcaster
var _coordinator: MatchCoordinator
var _debug: ServerDebugContext


func setup(
	room_manager: RoomManager,
	broadcaster: RoomBroadcaster,
	coordinator: MatchCoordinator,
	debug: ServerDebugContext
) -> void:
	_room_manager = room_manager
	_broadcaster = broadcaster
	_coordinator = coordinator
	_debug = debug


func handle_player_state(peer_id: int, payload: Dictionary) -> void:
	var room: Room = _room_manager.get_room_for_peer(peer_id)
	if room == null or not room.has_player(peer_id):
		return

	var session: PlayerSession = _room_manager.get_session(peer_id)
	var state: Dictionary = payload.duplicate(true)
	state.erase("peer_id")
	state.erase("display_name")
	state.erase("key_count")
	state.erase("level_has_key")
	state.erase("level_has_door")
	state["peer_id"] = peer_id
	state["display_name"] = session.display_name if session != null else "Guest%d" % peer_id
	state["server_time_unix"] = Time.get_unix_time_from_system()
	state.erase("push_intents")
	state.erase("pushable_states")

	if not room.is_playing():
		state["room_status"] = room.status
		state["level_index"] = -1
		state.erase("level_id")
		_broadcaster.send_room_message(
			room,
			ProtocolConstants.MESSAGE_PLAYER_STATE,
			{"state": state},
			peer_id,
			null,
			MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
		)
		return

	if int(state.get("level_index", room.current_level_index)) != room.current_level_index:
		return

	state["room_status"] = room.status
	state["level_id"] = room.current_level_id

	var pushable_controls: Array[Dictionary] = []
	var push_box_events: Array[Dictionary] = []
	var hazard_events: Array[Dictionary] = []
	var timed_events: Array[Dictionary] = []
	if room.match_state != null:
		room.match_state.update_player_runtime(peer_id, payload)
		timed_events = room.match_state.advance_timed_mechanics()
		hazard_events = room.match_state.apply_automatic_fall_reset(peer_id)
		push_box_events = room.match_state.apply_push_box_observations(peer_id, payload.get("pushable_states", []))
		var server_player_state: Dictionary = room.match_state.get_player_state(peer_id)
		if not server_player_state.is_empty():
			state["alive"] = bool(server_player_state.get("alive", true))
			state["key_count"] = int(server_player_state.get("key_count", 0))
		pushable_controls = room.match_state.apply_push_intents(peer_id, payload.get("push_intents", []))

	_broadcaster.send_room_message(
		room,
		ProtocolConstants.MESSAGE_PLAYER_STATE,
		{"state": state},
		peer_id,
		null,
		MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	)

	_broadcaster.send_room_message(
		room,
		ProtocolConstants.MESSAGE_PUSHABLE_CONTROL,
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
		if event_kind == GameIds.EVENT_PUSH_BOX_STATE:
			transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
		_broadcaster.send_room_message(
			room,
			ProtocolConstants.MESSAGE_WORLD_EVENT,
			{"event": event},
			-1,
			null,
			transfer_mode
		)

	for event in hazard_events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		_broadcaster.send_room_message(
			room,
			ProtocolConstants.MESSAGE_WORLD_EVENT,
			{"event": event},
			-1,
			null,
			MultiplayerPeer.TRANSFER_MODE_RELIABLE
		)

	for event in timed_events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		_broadcaster.send_room_message(
			room,
			ProtocolConstants.MESSAGE_WORLD_EVENT,
			{"event": event},
			-1,
			null,
			MultiplayerPeer.TRANSFER_MODE_RELIABLE
		)

	if not hazard_events.is_empty():
		_broadcaster.publish_room_snapshot(room)

	_coordinator.maybe_reset_failed_level(room)


func handle_level_changed(peer_id: int, request_id) -> void:
	var room: Room = _room_manager.get_room_for_peer(peer_id)
	if room != null:
		_debug.warn("ignored_client_level_changed peer=%d %s" % [peer_id, _debug.room_label(room)])
	else:
		_debug.warn("ignored_client_level_changed peer=%d room=-" % peer_id)

	_broadcaster.send_error(peer_id, "level_change_blocked", "Client-driven level changes are disabled.", request_id)


func handle_level_complete(peer_id: int, request_id) -> void:
	var room: Room = _room_manager.get_room_for_peer(peer_id)
	if room != null:
		_debug.warn("ignored_client_level_complete peer=%d %s" % [peer_id, _debug.room_label(room)])
	else:
		_debug.warn("ignored_client_level_complete peer=%d room=-" % peer_id)

	_broadcaster.send_error(peer_id, "level_complete_blocked", "Client-driven level completion is disabled.", request_id)


func handle_world_action_request(peer_id: int, request_id, payload: Dictionary, legacy: bool = false) -> void:
	var room: Room = _room_manager.get_room_for_peer(peer_id)
	if room == null or not room.has_player(peer_id) or not room.is_playing():
		_debug.warn("[world_action_request] reject peer=%d request=%s action=- room=- reason=not_in_playing_room %s" % [
			peer_id,
			_debug.request_label(request_id),
			_debug.payload_label(payload)
		])
		_broadcaster.send_error(peer_id, "not_in_playing_room", "Peer must be in a playing room before sending world action requests.", request_id)
		return

	if room.match_state == null:
		_debug.warn("[world_action_request] reject peer=%d request=%s action=- %s reason=missing_match_state %s" % [
			peer_id,
			_debug.request_label(request_id),
			_debug.room_label(room),
			_debug.payload_label(payload)
		])
		_broadcaster.send_error(peer_id, "missing_match_state", "Room has no active match state.", request_id)
		return

	var requested_level_id := String(payload.get("level_id", ""))
	if requested_level_id.is_empty() and payload.has("level_index"):
		requested_level_id = GameCatalog.get_level_id_by_index(room.map_id, int(payload.get("level_index", room.current_level_index)))
	if requested_level_id.is_empty():
		requested_level_id = room.current_level_id

	if requested_level_id != room.current_level_id:
		_debug.warn("[world_action_request] reject peer=%d request=%s action=- %s reason=stale_level requested_level=%s current_level=%s %s" % [
			peer_id,
			_debug.request_label(request_id),
			_debug.room_label(room),
			requested_level_id,
			room.current_level_id,
			_debug.payload_label(payload)
		])
		_broadcaster.send_error(
			peer_id,
			"stale_level_request",
			"World event request was sent for a different level.",
			request_id
		)
		return

	var action := String(payload.get("action", payload.get("kind", ""))).strip_edges().to_lower()
	if action.is_empty():
		_debug.warn("[world_action_request] reject peer=%d request=%s action=- %s reason=missing_world_action %s" % [
			peer_id,
			_debug.request_label(request_id),
			_debug.room_label(room),
			_debug.payload_label(payload)
		])
		_broadcaster.send_error(peer_id, "missing_world_action", "World event request is missing an action.", request_id)
		return

	var target_id := String(payload.get("target_id", payload.get("sync_id", ""))).strip_edges()
	if target_id.is_empty() and (legacy or payload.has("node_name")):
		target_id = _infer_legacy_target_id(room.current_level_id, action)

	var normalized_payload: Dictionary = payload.duplicate(true)
	normalized_payload["level_id"] = requested_level_id
	normalized_payload["target_id"] = target_id
	normalized_payload["legacy"] = legacy
	_debug.info("[world_action_request] recv peer=%d request=%s action=%s target=%s legacy=%s %s %s" % [
		peer_id,
		_debug.request_label(request_id),
		action,
		target_id if not target_id.is_empty() else "-",
		str(legacy),
		_debug.room_label(room),
		_debug.payload_label(normalized_payload)
	])

	if normalized_payload.has("position") or normalized_payload.has("velocity"):
		room.match_state.update_player_runtime(peer_id, normalized_payload)

	var result: Dictionary = room.match_state.apply_world_action(peer_id, action, target_id, normalized_payload)
	if not bool(result.get("ok", false)):
		_debug.warn("[world_action_request] reject peer=%d request=%s action=%s target=%s %s reason=%s message=%s %s" % [
			peer_id,
			_debug.request_label(request_id),
			action,
			target_id if not target_id.is_empty() else "-",
			_debug.room_label(room),
			String(result.get("code", "world_action_rejected")),
			String(result.get("message", "World action rejected by server state.")),
			_debug.payload_label(normalized_payload)
		])
		_broadcaster.send_error(
			peer_id,
			String(result.get("code", "world_action_rejected")),
			String(result.get("message", "World action rejected by server state.")),
			request_id
		)
		return

	var events_to_broadcast: Array = result.get("events", [])
	var level_failed := false
	var should_publish_snapshot := false
	_debug.info("[world_action_request] accept peer=%d request=%s action=%s target=%s events=%d legacy=%s %s" % [
		peer_id,
		_debug.request_label(request_id),
		action,
		target_id if not target_id.is_empty() else "-",
		events_to_broadcast.size(),
		str(legacy),
		_debug.room_label(room)
	])
	for event in events_to_broadcast:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var event_dict: Dictionary = event
		var event_kind := String(event_dict.get("kind", ""))
		if event_kind == GameIds.EVENT_LEVEL_FAILED:
			level_failed = true
		if event_kind == GameIds.EVENT_PLAYER_DIED or event_kind == GameIds.EVENT_PLAYER_RESPAWNED:
			should_publish_snapshot = true
		_debug.info("[world_action_request] event peer=%d action=%s event=%s target=%s level=%s" % [
			peer_id,
			action,
			event_kind,
			String(event_dict.get("target_id", "")),
			room.current_level_id
		])
		_broadcaster.send_room_message(room, ProtocolConstants.MESSAGE_WORLD_EVENT, {
			"event": event_dict,
		})

	if level_failed:
		_coordinator.restart_current_level(room, GameIds.EVENT_LEVEL_FAILED)
		return

	if should_publish_snapshot:
		_broadcaster.publish_room_snapshot(room)

	_coordinator.try_level_transition(room)


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
