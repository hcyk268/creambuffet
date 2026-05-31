extends RefCounted
class_name Room

const PlayerSession = preload("res://scripts/lobby/player_session.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")

const STATUS_LOBBY := "lobby"
const STATUS_PLAYING := "playing"
const STATUS_COMPLETE := "complete"

var room_id := ""
var host_peer_id := 0
var is_public := true
var max_players := 4
var world_count := 1
var randomized := false
var map_id := GameCatalog.DEFAULT_MAP_ID
var level_ids: Array[String] = []
var status := STATUS_LOBBY
var current_level_index := 0
var current_level_id := ""
var players: Dictionary = {}
var match_state: MatchState


func _init(
	initial_room_id: String = "",
	initial_host_peer_id: int = 0,
	initial_is_public: bool = true,
	initial_max_players: int = 4,
	initial_world_count: int = 1,
	initial_randomized: bool = false,
	initial_map_id: String = GameCatalog.DEFAULT_MAP_ID,
	initial_level_ids: Array[String] = []
) -> void:
	room_id = initial_room_id
	host_peer_id = initial_host_peer_id
	is_public = initial_is_public
	max_players = initial_max_players
	randomized = initial_randomized
	map_id = GameCatalog.normalize_map_id(initial_map_id)
	level_ids = initial_level_ids.duplicate()
	if level_ids.is_empty():
		level_ids = GameCatalog.get_level_ids(map_id)
	world_count = level_ids.size() if not level_ids.is_empty() else initial_world_count
	current_level_id = _level_id_for_index(current_level_index)


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


func set_map(new_map_id: String, level_ids_for_map: Array[String]) -> void:
	map_id = GameCatalog.normalize_map_id(new_map_id)
	level_ids = level_ids_for_map.duplicate()
	world_count = level_ids.size()
	current_level_index = 0
	current_level_id = _level_id_for_index(current_level_index)


func start_match() -> void:
	status = STATUS_PLAYING
	current_level_index = 0
	current_level_id = _level_id_for_index(current_level_index)
	match_state = MatchState.new(player_ids(), current_level_index, current_level_id, map_id)


func set_level_index(level_index: int) -> void:
	current_level_index = clampi(level_index, 0, maxi(level_ids.size() - 1, 0))
	current_level_id = _level_id_for_index(current_level_index)
	if status != STATUS_COMPLETE:
		status = STATUS_PLAYING
	if match_state != null:
		match_state.set_level(current_level_index, current_level_id)


func mark_complete() -> void:
	status = STATUS_COMPLETE


func snapshot() -> Dictionary:
	return {
		"room_id": room_id,
		"host_peer_id": host_peer_id,
		"is_public": is_public,
		"max_players": max_players,
		"world_count": world_count,
		"map_id": map_id,
		"level_ids": level_ids.duplicate(),
		"randomized": randomized,
		"status": status,
		"current_level_index": current_level_index,
		"current_level_id": current_level_id,
		"player_count": players.size(),
		"players": player_snapshots(),
		"match_state": match_state.snapshot() if match_state != null else {},
	}


func _level_id_for_index(level_index: int) -> String:
	if level_ids.is_empty():
		return GameCatalog.get_level_id_by_index(map_id, level_index)
	var safe_index := clampi(level_index, 0, level_ids.size() - 1)
	return level_ids[safe_index]
