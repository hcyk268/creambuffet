extends RefCounted
class_name RoomManager

const PlayerSession = preload("res://scripts/lobby/player_session.gd")
const Room = preload("res://scripts/lobby/room.gd")
const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")

const ROOM_CODE_ALPHABET := [
	"A", "B", "C", "D", "E", "F", "G", "H",
	"J", "K", "L", "M", "N", "P", "Q", "R",
	"S", "T", "U", "V", "W", "X", "Y", "Z",
	"2", "3", "4", "5", "6", "7", "8", "9",
]
const ROOM_CODE_LENGTH := 6
const MAX_ROOM_ID_ATTEMPTS := 32

const MIN_PLAYERS := 2
const MAX_PLAYERS := 4
const MIN_WORLDS := 1
const MAX_WORLDS := 10

var rooms: Dictionary = {}
var sessions: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func ensure_session(peer_id: int, requested_name: String = "") -> PlayerSession:
	var session := sessions.get(peer_id) as PlayerSession
	if session == null:
		session = PlayerSession.new(peer_id, requested_name)
		sessions[peer_id] = session
	elif not requested_name.strip_edges().is_empty():
		session.set_display_name(requested_name)

	return session


func get_session(peer_id: int) -> PlayerSession:
	return sessions.get(peer_id) as PlayerSession


func get_room(room_id: String) -> Room:
	return rooms.get(room_id) as Room


func get_room_for_peer(peer_id: int) -> Room:
	var session := get_session(peer_id)
	if session == null or session.room_id.is_empty():
		return null

	return get_room(session.room_id)


func list_public_rooms() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	var room_ids := rooms.keys()
	room_ids.sort()

	for raw_room_id in room_ids:
		var room_id := String(raw_room_id)
		var room := rooms.get(room_id) as Room
		if room != null and room.is_public and room.is_in_lobby():
			snapshots.append(room.snapshot())

	return snapshots


func create_room(peer_id: int, requested_name: String, options: Dictionary) -> Dictionary:
	var session := ensure_session(peer_id, requested_name)
	if not session.room_id.is_empty():
		return _error("already_in_room", "Peer must leave the current room before creating a new one.")

	var room_id := _create_unique_room_id()
	if room_id.is_empty():
		return _error("room_id_exhausted", "Server could not allocate a unique room id.")

	var is_public := _read_visibility(options)
	var max_players := _clamp_int(options.get("max_players", MAX_PLAYERS), MIN_PLAYERS, MAX_PLAYERS)
	var map_id := GameCatalog.normalize_map_id(String(options.get("map_id", GameCatalog.DEFAULT_MAP_ID)))
	if not GameCatalog.has_map(map_id):
		return _error("unknown_map", "Map is not defined: %s" % map_id)

	if not GameCatalog.is_map_selectable(map_id):
		return _error("map_not_selectable", "Map is not available yet: %s" % map_id)

	var randomized := false
	var level_ids := _build_room_level_ids(map_id, 0, randomized)
	if level_ids.is_empty():
		return _error("empty_map", "Map has no playable levels: %s" % map_id)

	for level_id in level_ids:
		var validation := GameCatalog.validate_level_rulesets(map_id, level_id)
		if not bool(validation.get("ok", false)):
			return validation

	var world_count := level_ids.size()

	var room := Room.new(room_id, peer_id, is_public, max_players, world_count, randomized, map_id, level_ids)
	var add_error := room.try_add_player(session)
	if add_error != OK:
		return _error("room_create_failed", "Server could not add the host to the room.")

	rooms[room_id] = room

	return {
		"ok": true,
		"room": room,
		"session": session,
	}


func join_room(peer_id: int, requested_name: String, requested_room_id: String) -> Dictionary:
	var session := ensure_session(peer_id, requested_name)
	if not session.room_id.is_empty():
		return _error("already_in_room", "Peer must leave the current room before joining another room.")

	var room_id := requested_room_id.strip_edges().to_upper()
	if room_id.is_empty():
		return _error("missing_room_id", "Room id is required.")

	var room := get_room(room_id)
	if room == null:
		return _error("room_not_found", "Room id does not exist.")

	if not room.is_in_lobby():
		if room.is_playing():
			return _error("room_in_progress", "Room is already in progress.")
		return _error("room_closed", "Room is no longer accepting new players.")

	if room.is_full():
		return _error("room_full", "Room is already full.")

	var add_error := room.try_add_player(session)
	if add_error != OK:
		return _error("join_failed", "Server could not add the player to the room.")

	return {
		"ok": true,
		"room": room,
		"session": session,
	}


func leave_room(peer_id: int) -> Dictionary:
	var session := get_session(peer_id)
	if session == null:
		return _error("unknown_peer", "Peer is not registered.")

	if session.room_id.is_empty():
		return {
			"ok": true,
			"room": null,
			"removed_room_id": "",
			"removed_room": false,
			"session": session,
		}

	var room_id := session.room_id
	var room := get_room(room_id)
	if room == null:
		session.detach_room()
		return {
			"ok": true,
			"room": null,
			"removed_room_id": room_id,
			"removed_room": false,
			"session": session,
		}

	room.remove_player(peer_id)

	if room.is_empty():
		rooms.erase(room_id)
		return {
			"ok": true,
			"room": null,
			"removed_room_id": room_id,
			"removed_room": true,
			"session": session,
		}

	return {
		"ok": true,
		"room": room,
		"removed_room_id": room_id,
		"removed_room": false,
		"session": session,
	}


func unregister_peer(peer_id: int) -> Dictionary:
	var result := leave_room(peer_id)
	sessions.erase(peer_id)
	return result


func start_match(peer_id: int) -> Dictionary:
	var room := get_room_for_peer(peer_id)
	if room == null:
		return _error("not_in_room", "Peer must be in a room before starting a match.")

	if room.host_peer_id != peer_id:
		return _error("not_host", "Only the host can start the match.")

	if room.status != Room.STATUS_LOBBY:
		return _error("room_not_in_lobby", "Match can only start while the room is in lobby status.")

	if room.player_ids().size() < room.max_players:
		return _error("room_not_ready", "Waiting for all players to join before starting the match.")

	room.start_match()
	return {
		"ok": true,
		"room": room,
	}


func set_room_map(peer_id: int, requested_map_id: String) -> Dictionary:
	var room := get_room_for_peer(peer_id)
	if room == null:
		return _error("not_in_room", "Peer must be in a room before changing the map.")

	if room.host_peer_id != peer_id:
		return _error("not_host", "Only the host can change the room map.")

	if room.status != Room.STATUS_LOBBY:
		return _error("room_not_in_lobby", "Map can only be changed while the room is in lobby status.")

	var map_id := GameCatalog.normalize_map_id(requested_map_id)
	if not GameCatalog.has_map(map_id):
		return _error("unknown_map", "Map is not defined: %s" % map_id)

	if not GameCatalog.is_map_selectable(map_id):
		return _error("map_not_selectable", "Map is not available yet: %s" % map_id)

	var level_ids := _build_room_level_ids(map_id, 0, false)
	if level_ids.is_empty():
		return _error("empty_map", "Map has no playable levels: %s" % map_id)

	for level_id in level_ids:
		var validation := GameCatalog.validate_level_rulesets(map_id, level_id)
		if not bool(validation.get("ok", false)):
			return validation

	room.set_map(map_id, level_ids)
	return {
		"ok": true,
		"room": room,
	}


func set_room_level(peer_id: int, level_index: int) -> Dictionary:
	var room := get_room_for_peer(peer_id)
	if room == null:
		return _error("not_in_room", "Peer must be in a room before changing levels.")

	room.set_level_index(level_index)
	return {
		"ok": true,
		"room": room,
		"level_index": room.current_level_index,
	}


func mark_room_complete(peer_id: int) -> Dictionary:
	var room := get_room_for_peer(peer_id)
	if room == null:
		return _error("not_in_room", "Peer must be in a room before completing a match.")

	room.mark_complete()
	return {
		"ok": true,
		"room": room,
	}


func _read_visibility(options: Dictionary) -> bool:
	if options.has("is_public"):
		return bool(options["is_public"])

	var visibility := String(options.get("visibility", "public")).to_lower()
	return visibility != "private"


func _create_unique_room_id() -> String:
	for _attempt in range(MAX_ROOM_ID_ATTEMPTS):
		var candidate := ""
		for _index in range(ROOM_CODE_LENGTH):
			candidate += ROOM_CODE_ALPHABET[_rng.randi_range(0, ROOM_CODE_ALPHABET.size() - 1)]

		if not rooms.has(candidate):
			return candidate

	return ""


func _clamp_int(value, min_value: int, max_value: int) -> int:
	return clampi(int(value), min_value, max_value)


func _build_room_level_ids(map_id: String, requested_world_count: int, randomized: bool) -> Array[String]:
	var available_level_ids := GameCatalog.get_level_ids(map_id)
	if available_level_ids.is_empty():
		return []

	var effective_world_count := requested_world_count if requested_world_count > 0 else available_level_ids.size()
	var normalized_world_count := _clamp_int(
		effective_world_count,
		MIN_WORLDS,
		mini(MAX_WORLDS, available_level_ids.size())
	)
	var selected_level_ids := available_level_ids.duplicate()
	if randomized and selected_level_ids.size() > 1:
		_shuffle_level_ids(selected_level_ids)

	if normalized_world_count >= selected_level_ids.size():
		return selected_level_ids

	var trimmed_level_ids: Array[String] = []
	for index in range(normalized_world_count):
		trimmed_level_ids.append(selected_level_ids[index])

	return trimmed_level_ids


func _shuffle_level_ids(level_ids: Array[String]) -> void:
	for index in range(level_ids.size() - 1, 0, -1):
		var swap_index := _rng.randi_range(0, index)
		if swap_index == index:
			continue

		var current_level_id := level_ids[index]
		level_ids[index] = level_ids[swap_index]
		level_ids[swap_index] = current_level_id


func _error(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
	}
