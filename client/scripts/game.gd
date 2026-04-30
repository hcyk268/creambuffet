extends Node2D

const PLAYER_SCENE := preload("res://scenes/player_soda.tscn")
const NETWORK_SEND_INTERVAL := 0.05

@export var levels: Array[PackedScene] = []
@export var start_level_index := 0

@onready var player: CharacterBody2D = $Player
@onready var level_container: Node2D = $LevelContainer
@onready var level_label: Label = $CanvasLayer/LevelLabel

var _current_level: Node
var _current_level_index := -1
var _network_client: Node
var _is_online_session := false
var _remote_container: Node2D
var _remote_players: Dictionary = {}
var _send_timer := 0.0
var _match_complete := false
var _applying_remote_world_event := false


func _ready() -> void:
	_network_client = get_node_or_null("/root/NetworkClient")
	_is_online_session = _network_client != null and not _network_client.get_current_room().is_empty()
	_remote_container = Node2D.new()
	_remote_container.name = "RemotePlayers"
	add_child(_remote_container)
	move_child(_remote_container, player.get_index())

	if levels.is_empty():
		push_warning("Game has no levels configured.")
		return

	if _is_online_session:
		_bind_network_signals()
		_setup_local_network_identity()

	var safe_start_index := clampi(start_level_index, 0, levels.size() - 1)
	if _is_online_session:
		var room: Dictionary = _network_client.get_current_room()
		safe_start_index = clampi(int(room.get("current_level_index", safe_start_index)), 0, levels.size() - 1)

	load_level(safe_start_index)
	_sync_remote_roster()


func _exit_tree() -> void:
	_unbind_network_signals()


func _physics_process(delta: float) -> void:
	if not _is_online_session or _match_complete or _current_level_index < 0:
		return

	_send_timer += delta
	if _send_timer < NETWORK_SEND_INTERVAL:
		return

	_send_timer = 0.0
	if player.has_method("get_network_state"):
		var state: Dictionary = player.get_network_state(_current_level_index)
		var pushable_states := _collect_pushable_states()
		if not pushable_states.is_empty():
			state["pushables"] = pushable_states
		_network_client.send_player_state(state)


func load_level(index: int, broadcast_change := false) -> void:
	if index < 0 or index >= levels.size():
		push_warning("Invalid level index: %d" % index)
		return

	if is_instance_valid(_current_level):
		_current_level.queue_free()

	_current_level = levels[index].instantiate()
	level_container.add_child(_current_level)
	_current_level_index = index
	_match_complete = false

	_setup_player_spawn(_current_level)
	_reset_remote_players_to_spawn()
	_connect_level_goals(_current_level)
	_connect_world_events(_current_level)
	_update_level_label(false)

	if broadcast_change and _is_online_session:
		_network_client.send_level_changed(index)


func next_level() -> void:
	if _current_level_index + 1 >= levels.size():
		_match_complete = true
		_update_level_label(true)
		if _is_online_session:
			_network_client.send_level_complete()
		return

	load_level(_current_level_index + 1, _is_online_session)


func restart_level() -> void:
	if _current_level_index < 0:
		return

	load_level(_current_level_index)


func _setup_player_spawn(level_root: Node) -> void:
	var spawn_point := level_root.get_node_or_null("SpawnPoint")
	if spawn_point is Node2D:
		player.global_position = spawn_point.global_position
	else:
		player.global_position = Vector2.ZERO

	player.velocity = Vector2.ZERO
	player.spawn_position = player.global_position
	player.key_count = 0


func _connect_level_goals(level_root: Node) -> void:
	var callback := Callable(self, "_on_goal_reached")
	for node in _find_nodes_in_group(level_root, "level_goal"):
		if node.has_signal("goal_reached") and not node.is_connected("goal_reached", callback):
			node.connect("goal_reached", callback)


func _find_nodes_in_group(root: Node, group_name: StringName) -> Array[Node]:
	var result: Array[Node] = []
	_collect_group_nodes(root, group_name, result)
	return result


func _collect_group_nodes(node: Node, group_name: StringName, out_nodes: Array[Node]) -> void:
	if node.is_in_group(group_name):
		out_nodes.append(node)

	for child in node.get_children():
		if child is Node:
			_collect_group_nodes(child, group_name, out_nodes)


func _on_goal_reached(_body: Node) -> void:
	if _match_complete:
		return

	next_level()


func _update_level_label(game_complete: bool) -> void:
	if game_complete:
		level_label.text = "All levels cleared!"
		return

	var suffix := ""
	if _is_online_session:
		var room: Dictionary = _network_client.get_current_room()
		suffix = " | Room %s" % String(room.get("room_id", ""))

	level_label.text = "Level %d / %d%s" % [_current_level_index + 1, levels.size(), suffix]


func _bind_network_signals() -> void:
	var on_state := Callable(self, "_on_remote_player_state")
	if not _network_client.remote_player_state.is_connected(on_state):
		_network_client.remote_player_state.connect(on_state)

	var on_room := Callable(self, "_on_current_room_changed")
	if not _network_client.current_room_changed.is_connected(on_room):
		_network_client.current_room_changed.connect(on_room)

	var on_level := Callable(self, "_on_level_changed")
	if not _network_client.level_changed.is_connected(on_level):
		_network_client.level_changed.connect(on_level)

	var on_complete := Callable(self, "_on_level_complete")
	if not _network_client.level_complete.is_connected(on_complete):
		_network_client.level_complete.connect(on_complete)

	var on_world_event := Callable(self, "_on_world_event_received")
	if not _network_client.world_event_received.is_connected(on_world_event):
		_network_client.world_event_received.connect(on_world_event)


func _unbind_network_signals() -> void:
	if _network_client == null:
		return

	var on_state := Callable(self, "_on_remote_player_state")
	if _network_client.remote_player_state.is_connected(on_state):
		_network_client.remote_player_state.disconnect(on_state)

	var on_room := Callable(self, "_on_current_room_changed")
	if _network_client.current_room_changed.is_connected(on_room):
		_network_client.current_room_changed.disconnect(on_room)

	var on_level := Callable(self, "_on_level_changed")
	if _network_client.level_changed.is_connected(on_level):
		_network_client.level_changed.disconnect(on_level)

	var on_complete := Callable(self, "_on_level_complete")
	if _network_client.level_complete.is_connected(on_complete):
		_network_client.level_complete.disconnect(on_complete)

	var on_world_event := Callable(self, "_on_world_event_received")
	if _network_client.world_event_received.is_connected(on_world_event):
		_network_client.world_event_received.disconnect(on_world_event)


func _setup_local_network_identity() -> void:
	var peer_id: int = _network_client.get_local_peer_id()
	var player_name := _player_name_for_peer(peer_id)
	if player.has_method("set_network_identity"):
		player.set_network_identity(peer_id, player_name)
	if player.has_method("set_network_remote"):
		player.set_network_remote(false)


func _sync_remote_roster(room: Dictionary = {}) -> void:
	if not _is_online_session or _remote_container == null:
		return

	var room_data := room
	if room_data.is_empty():
		room_data = _network_client.get_current_room()

	var local_peer_id: int = _network_client.get_local_peer_id()
	var seen: Dictionary = {}
	var players = room_data.get("players", [])
	if typeof(players) == TYPE_ARRAY:
		for raw_player in players:
			if typeof(raw_player) != TYPE_DICTIONARY:
				continue

			var player_data: Dictionary = raw_player
			var peer_id := int(player_data.get("peer_id", 0))
			if peer_id <= 0 or peer_id == local_peer_id:
				continue

			seen[peer_id] = true
			_ensure_remote_player(peer_id, String(player_data.get("display_name", "Guest%d" % peer_id)))

	for raw_peer_id in _remote_players.keys().duplicate():
		var peer_id := int(raw_peer_id)
		if seen.has(peer_id):
			continue

		var remote := _remote_players.get(peer_id) as Node
		if is_instance_valid(remote):
			remote.queue_free()
		_remote_players.erase(peer_id)


func _ensure_remote_player(peer_id: int, player_name: String = "") -> CharacterBody2D:
	var existing := _remote_players.get(peer_id) as CharacterBody2D
	if is_instance_valid(existing):
		return existing

	var remote := PLAYER_SCENE.instantiate() as CharacterBody2D
	remote.name = "RemotePlayer_%d" % peer_id
	if remote.has_method("set_network_identity"):
		remote.set_network_identity(peer_id, player_name)
	if remote.has_method("set_network_remote"):
		remote.set_network_remote(true)

	_remote_container.add_child(remote)
	remote.global_position = player.spawn_position
	_remote_players[peer_id] = remote
	return remote


func _reset_remote_players_to_spawn() -> void:
	for value in _remote_players.values():
		var remote := value as CharacterBody2D
		if is_instance_valid(remote):
			remote.global_position = player.spawn_position
			remote.velocity = Vector2.ZERO


func _remove_remote_players() -> void:
	for value in _remote_players.values():
		var remote := value as Node
		if is_instance_valid(remote):
			remote.queue_free()
	_remote_players.clear()


func _on_remote_player_state(peer_id: int, state: Dictionary) -> void:
	if not _is_online_session:
		return

	if int(state.get("level_index", _current_level_index)) != _current_level_index:
		return

	var remote := _ensure_remote_player(peer_id, String(state.get("display_name", "Guest%d" % peer_id)))
	if remote.has_method("apply_network_state"):
		remote.apply_network_state(state)

	_apply_pushable_states(state.get("pushables", []))


func _on_current_room_changed(room: Dictionary) -> void:
	if room.is_empty():
		_remove_remote_players()
		return

	_sync_remote_roster(room)
	_update_level_label(_match_complete)


func _on_level_changed(level_index: int, room: Dictionary) -> void:
	if level_index != _current_level_index:
		load_level(level_index)

	_sync_remote_roster(room)


func _on_level_complete(room: Dictionary) -> void:
	_match_complete = true
	_sync_remote_roster(room)
	_update_level_label(true)


func _player_name_for_peer(peer_id: int) -> String:
	var room: Dictionary = _network_client.get_current_room()
	var players = room.get("players", [])
	if typeof(players) != TYPE_ARRAY:
		return "Player"

	for raw_player in players:
		if typeof(raw_player) != TYPE_DICTIONARY:
			continue

		var player_data: Dictionary = raw_player
		if int(player_data.get("peer_id", 0)) == peer_id:
			return String(player_data.get("display_name", "Player"))

	return "Player"


func _connect_world_events(level_root: Node) -> void:
	_connect_world_event_nodes(level_root)


func _connect_world_event_nodes(node: Node) -> void:
	if node.has_signal("collected"):
		var on_collected := Callable(self, "_on_key_collected").bind(node)
		if not node.is_connected("collected", on_collected):
			node.connect("collected", on_collected)

	if node.has_signal("door_opened"):
		var on_door_opened := Callable(self, "_on_door_opened").bind(node)
		if not node.is_connected("door_opened", on_door_opened):
			node.connect("door_opened", on_door_opened)

	for child in node.get_children():
		if child is Node:
			_connect_world_event_nodes(child)


func _on_key_collected(_body: Node, key_node: Node) -> void:
	if not _is_online_session or _applying_remote_world_event:
		return

	_network_client.send_world_event({
		"kind": "key_collected",
		"level_index": _current_level_index,
		"node_name": key_node.name,
	})


func _on_door_opened(door_node: Node) -> void:
	if not _is_online_session or _applying_remote_world_event:
		return

	_network_client.send_world_event({
		"kind": "door_opened",
		"level_index": _current_level_index,
		"node_name": door_node.name,
	})


func _on_world_event_received(event: Dictionary) -> void:
	if int(event.get("level_index", _current_level_index)) != _current_level_index:
		return

	_applying_remote_world_event = true
	match String(event.get("kind", "")):
		"key_collected":
			_apply_key_collected(String(event.get("node_name", "")))
		"door_opened":
			_apply_door_opened(String(event.get("node_name", "")))
	_applying_remote_world_event = false


func _apply_key_collected(node_name: String) -> void:
	var key_node := _find_level_node(node_name)
	if is_instance_valid(key_node):
		key_node.queue_free()

	_open_all_doors()


func _apply_door_opened(node_name: String) -> void:
	var door_node := _find_level_node(node_name)
	if door_node != null and door_node.has_method("open"):
		door_node.open()


func _open_all_doors() -> void:
	if not is_instance_valid(_current_level):
		return

	for node in _find_nodes_in_group(_current_level, "level_door"):
		if node.has_method("open"):
			node.open()


func _collect_pushable_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	if not is_instance_valid(_current_level):
		return states

	for node in _find_nodes_in_group(_current_level, "pushable"):
		if not (node is Node2D):
			continue

		var body := node as Node2D
		if player.global_position.distance_to(body.global_position) > 96.0:
			continue

		var state := {
			"node_name": body.name,
			"position": _vector_to_packet(body.global_position),
			"rotation": body.rotation,
		}

		var rigid_body := body as RigidBody2D
		if rigid_body != null:
			state["linear_velocity"] = _vector_to_packet(rigid_body.linear_velocity)

		states.append(state)

	return states


func _apply_pushable_states(raw_states) -> void:
	if typeof(raw_states) != TYPE_ARRAY or not is_instance_valid(_current_level):
		return

	for raw_state in raw_states:
		if typeof(raw_state) != TYPE_DICTIONARY:
			continue

		var state: Dictionary = raw_state
		var body := _find_level_node(String(state.get("node_name", ""))) as Node2D
		if body == null:
			continue

		if player.global_position.distance_to(body.global_position) <= 96.0:
			continue

		body.global_position = _packet_to_vector(state.get("position", {}), body.global_position)
		body.rotation = float(state.get("rotation", body.rotation))

		var rigid_body := body as RigidBody2D
		if rigid_body != null:
			rigid_body.linear_velocity = _packet_to_vector(
				state.get("linear_velocity", {}),
				rigid_body.linear_velocity
			)


func _find_level_node(node_name: String) -> Node:
	if not is_instance_valid(_current_level) or node_name.is_empty():
		return null

	var direct := _current_level.get_node_or_null(NodePath(node_name))
	if direct != null:
		return direct

	return _current_level.find_child(node_name, true, false)


func _vector_to_packet(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _packet_to_vector(raw_value, fallback: Vector2) -> Vector2:
	if typeof(raw_value) == TYPE_DICTIONARY:
		var data: Dictionary = raw_value
		return Vector2(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)))

	if typeof(raw_value) == TYPE_ARRAY and raw_value.size() >= 2:
		return Vector2(float(raw_value[0]), float(raw_value[1]))

	return fallback
