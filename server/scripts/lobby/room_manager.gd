extends RefCounted
class_name RoomManager

const PlayerSession = preload("res://scripts/lobby/player_session.gd")
const Room = preload("res://scripts/lobby/room.gd")

const ROOM_CODE_ALPHABET := [
	"A", "B", "C", "D", "E", "F", "G", "H",
	"J", "K", "L", "M", "N", "P", "Q", "R",
	"S", "T", "U", "V", "W", "X", "Y", "Z",
	"2", "3", "4", "5", "6", "7", "8", "9",
]
const ROOM_CODE_LENGTH := 6
const MAX_ROOM_ID_ATTEMPTS := 32

const MIN_PLAYERS := 1
const MAX_PLAYERS := 4
const MIN_WORLDS := 1
const MAX_WORLDS := 5

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
		if room != null and room.is_public:
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
	var world_count := _clamp_int(options.get("world_count", MIN_WORLDS), MIN_WORLDS, MAX_WORLDS)
	var randomized := bool(options.get("randomized", false))

	var room := Room.new(room_id, peer_id, is_public, max_players, world_count, randomized)
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

	room.start_match()
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


func _error(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
	}
