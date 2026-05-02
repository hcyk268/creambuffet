extends RefCounted
class_name Room

const PlayerSession = preload("res://scripts/lobby/player_session.gd")
const MatchState = preload("res://scripts/match/match_state.gd")

const STATUS_LOBBY := "lobby"
const STATUS_PLAYING := "playing"
const STATUS_COMPLETE := "complete"

var room_id := ""
var host_peer_id := 0
var is_public := true
var max_players := 4
var world_count := 1
var randomized := false
var status := STATUS_LOBBY
var current_level_index := 0
var players: Dictionary = {}
var match_state: MatchState


func _init(
	initial_room_id: String = "",
	initial_host_peer_id: int = 0,
	initial_is_public: bool = true,
	initial_max_players: int = 4,
	initial_world_count: int = 1,
	initial_randomized: bool = false
) -> void:
	room_id = initial_room_id
	host_peer_id = initial_host_peer_id
	is_public = initial_is_public
	max_players = initial_max_players
	world_count = initial_world_count
	randomized = initial_randomized


func has_player(peer_id: int) -> bool:
	return players.has(peer_id)


func is_full() -> bool:
	return players.size() >= max_players


func is_empty() -> bool:
	return players.is_empty()


func is_playing() -> bool:
	return status == STATUS_PLAYING


func try_add_player(session: PlayerSession) -> Error:
	if has_player(session.peer_id):
		return ERR_ALREADY_EXISTS

	if is_full():
		return ERR_CANT_ACQUIRE_RESOURCE

	players[session.peer_id] = session
	session.attach_room(room_id)
	if match_state != null:
		match_state.add_player(session.peer_id)

	if host_peer_id == 0:
		host_peer_id = session.peer_id

	return OK


func remove_player(peer_id: int) -> bool:
	if not has_player(peer_id):
		return false

	var session := players.get(peer_id) as PlayerSession
	if session != null:
		session.detach_room()

	players.erase(peer_id)
	if match_state != null:
		match_state.remove_player(peer_id)

	if host_peer_id == peer_id:
		host_peer_id = 0
		for value in players.values():
			var remaining := value as PlayerSession
			if remaining == null:
				continue

			if host_peer_id == 0 or remaining.peer_id < host_peer_id:
				host_peer_id = remaining.peer_id

	return true


func player_ids() -> Array[int]:
	var ids: Array[int] = []
	var raw_ids := players.keys()
	raw_ids.sort()

	for raw_id in raw_ids:
		ids.append(int(raw_id))

	return ids


func player_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for peer_id in player_ids():
		var session := players.get(peer_id) as PlayerSession
		if session != null:
			snapshots.append(session.snapshot())

	return snapshots


func start_match() -> void:
	status = STATUS_PLAYING
	current_level_index = 0
	match_state = MatchState.new(player_ids(), current_level_index)


func set_level_index(level_index: int) -> void:
	current_level_index = 0 if level_index < 0 else level_index
	if status != STATUS_COMPLETE:
		status = STATUS_PLAYING
	if match_state != null:
		match_state.set_level(current_level_index)


func mark_complete() -> void:
	status = STATUS_COMPLETE


func snapshot() -> Dictionary:
	return {
		"room_id": room_id,
		"host_peer_id": host_peer_id,
		"is_public": is_public,
		"max_players": max_players,
		"world_count": world_count,
		"randomized": randomized,
		"status": status,
		"current_level_index": current_level_index,
		"player_count": players.size(),
		"players": player_snapshots(),
		"match_state": match_state.snapshot() if match_state != null else {},
	}
