extends RefCounted
class_name RemotePlayerRegistry

const PLAYER_SCENE := preload("res://scenes/player_soda.tscn")
const PlayerCapabilities = preload("res://scripts/player/player_capabilities.gd")

var _owner: Node
var _local_player: CharacterBody2D
var _remote_container: Node2D
var _remote_players: Dictionary = {}
var _player_colors: Dictionary = {}


func setup(owner: Node, local_player: CharacterBody2D) -> void:
	_owner = owner
	_local_player = local_player
	_remote_container = Node2D.new()
	_remote_container.name = "RemotePlayers"
	_owner.add_child(_remote_container)
	if _local_player != null:
		_owner.move_child(_remote_container, _local_player.get_index())


func sync_roster(room: Dictionary, local_peer_id: int) -> void:
	if _remote_container == null:
		return

	var seen: Dictionary = {}
	var players = room.get("players", [])
	if typeof(players) == TYPE_ARRAY:
		for raw_player in players:
			if typeof(raw_player) != TYPE_DICTIONARY:
				continue

			var player_data: Dictionary = raw_player
			var peer_id := int(player_data.get("peer_id", 0))
			if peer_id <= 0 or peer_id == local_peer_id:
				continue

			seen[peer_id] = true
			_player_colors[peer_id] = player_color_from_data(player_data)
			var remote := ensure(peer_id, String(player_data.get("display_name", "Guest%d" % peer_id)))
			if remote != null:
				remote.modulate = _player_colors[peer_id]

	for raw_peer_id in _remote_players.keys().duplicate():
		var peer_id := int(raw_peer_id)
		if seen.has(peer_id):
			continue

		var remote = _remote_players.get(peer_id)
		if is_instance_valid(remote) and remote is Node:
			(remote as Node).queue_free()
		_remote_players.erase(peer_id)
		_player_colors.erase(peer_id)


func ensure(peer_id: int, player_name: String = "") -> CharacterBody2D:
	var existing = _remote_players.get(peer_id)
	if is_instance_valid(existing) and existing is CharacterBody2D:
		return existing as CharacterBody2D
	_remote_players.erase(peer_id)

	if _remote_container == null:
		return null

	var remote := PLAYER_SCENE.instantiate() as PlayerSoda
	remote.name = "RemotePlayer_%d" % peer_id
	_remote_container.add_child(remote)
	PlayerCapabilities.configure_network_player(remote, peer_id, player_name, true)
	var player_color: Color = _player_colors.get(peer_id, Color.WHITE)
	remote.modulate = player_color
	if _local_player != null:
		remote.global_position = _local_player.spawn_position
	_remote_players[peer_id] = remote
	return remote


func apply_state(peer_id: int, state: Dictionary, current_level_index: int) -> void:
	if int(state.get("level_index", current_level_index)) != current_level_index:
		return

	var remote := ensure(peer_id, String(state.get("display_name", "Guest%d" % peer_id)))
	if remote is PlayerSoda:
		PlayerCapabilities.apply_network_state(remote as PlayerSoda, state)


func reset_to_spawn() -> void:
	if _local_player == null:
		return

	for value in _remote_players.values():
		if is_instance_valid(value) and value is CharacterBody2D:
			var remote := value as CharacterBody2D
			remote.global_position = _local_player.spawn_position
			remote.velocity = Vector2.ZERO


func remove_all() -> void:
	for value in _remote_players.values():
		if is_instance_valid(value) and value is Node:
			var remote := value as Node
			remote.queue_free()
	_remote_players.clear()
	_player_colors.clear()


func player_for_peer(peer_id: int, local_peer_id: int, local_player: CharacterBody2D) -> CharacterBody2D:
	if peer_id == local_peer_id:
		return local_player

	var remote = _remote_players.get(peer_id)
	if is_instance_valid(remote) and remote is CharacterBody2D:
		return remote as CharacterBody2D
	_remote_players.erase(peer_id)
	return null


static func player_color_for_peer(room: Dictionary, peer_id: int, fallback: Color = Color.WHITE) -> Color:
	var players = room.get("players", [])
	if typeof(players) != TYPE_ARRAY:
		return fallback

	for raw_player in players:
		if typeof(raw_player) != TYPE_DICTIONARY:
			continue

		var player_data: Dictionary = raw_player
		if int(player_data.get("peer_id", 0)) == peer_id:
			return player_color_from_data(player_data, fallback)

	return fallback


static func player_color_from_data(player_data: Dictionary, fallback: Color = Color.WHITE) -> Color:
	var color_hex := String(player_data.get("player_color", "")).strip_edges().trim_prefix("#")
	if color_hex.length() != 6:
		return fallback
	return Color.html("#%s" % color_hex)


static func player_name_for_peer(room: Dictionary, peer_id: int, fallback: String = "Player") -> String:
	var players = room.get("players", [])
	if typeof(players) != TYPE_ARRAY:
		return fallback

	for raw_player in players:
		if typeof(raw_player) != TYPE_DICTIONARY:
			continue

		var player_data: Dictionary = raw_player
		if int(player_data.get("peer_id", 0)) == peer_id:
			return String(player_data.get("display_name", fallback))

	return fallback
