extends Node2D

const PLAYER_SCENE := preload("res://scenes/player_soda.tscn")
const CO_OP_MUSIC := preload("res://assets/sound/Co-op background.mp3")
const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const GameIds = preload("res://scripts/catalog/game_ids.gd")
const OptionsState = preload("res://scripts/menu/options_state.gd")
const RemotePlayerRegistry = preload("res://scripts/online/remote_player_registry.gd")
const BODY_FONT := preload("res://assets/fonts/EXEPixelPerfect.ttf")
const NETWORK_SEND_INTERVAL := 0.05

@export var is_host: bool = true
@export var max_players: int = 4
@export var current_players: int = 1

@onready var player: CharacterBody2D = $Player
@onready var player_spawn: Marker2D = $PlayerSpawn
@onready var host_banner: Label = $HUD/HostBanner
@onready var ping_label: Label = $HUD/LeftStatus/PingLabel
@onready var player_count_label: Label = $HUD/LeftStatus/PlayerRow/PlayerCount
@onready var room_title_label: Label = $HUD/RoomTitle
@onready var map_label: Label = $HUD/MapLabel
@onready var host_controls: HBoxContainer = $HUD/BottomBar/HostControls
@onready var start_game_button: Button = $HUD/BottomBar/HostControls/StartGameButt
@onready var pause_panel: CanvasLayer = $PausePanel
@onready var member_list: VBoxContainer = $PausePanel/Panel/MarginContainer/VBoxContainer/MemberList
@onready var option_panel: Control = $PausePanel/OptionPanel
@onready var music_player: AudioStreamPlayer = get_node_or_null("MusicPlayer") as AudioStreamPlayer

var _entering_match := false
var _remote_container: Node2D
var _remote_players: Dictionary = {}
var _send_timer := 0.0
var _lobby_spawn_initialized := false


func _ready() -> void:
	_configure_music()
	var room: Dictionary = _network_client().get_current_room()
	if room.is_empty():
		SceneTransition.change_scene("res://scenes/online_menu.tscn")
		return

	_remote_container = Node2D.new()
	_remote_container.name = "RemotePlayers"
	add_child(_remote_container)
	move_child(_remote_container, player.get_index())

	_configure_local_player(room)
	_sync_remote_roster(room)
	_apply_room_state(room)
	_bind_network_signals()
	_refresh_hud()
	_refresh_ping_label()
	pause_panel.visible = false
	get_tree().paused = false


func _exit_tree() -> void:
	_remove_remote_players()
	_unbind_network_signals()


func _apply_room_state(room: Dictionary) -> void:
	is_host = _network_client().is_room_host()
	max_players = int(room.get("max_players", max_players))
	var players_arr = room.get("players", [])
	if typeof(players_arr) == TYPE_ARRAY:
		current_players = (players_arr as Array).size()


func _refresh_hud() -> void:
	var room: Dictionary = _network_client().get_current_room()
	var room_id := String(room.get("room_id", ""))
	var map_id := String(room.get("map_id", GameCatalog.DEFAULT_MAP_ID))
	var map_title := GameCatalog.get_map_title(map_id)
	var room_status := String(room.get("status", ""))
	var room_full := current_players >= max_players

	room_title_label.text = "ROOM %s" % room_id if not room_id.is_empty() else "ROOM"
	player_count_label.text = "%d/%d" % [current_players, max_players]
	map_label.text = "Map: %s" % map_title
	host_banner.visible = false

	if room_status == GameIds.ROOM_STATUS_COMPLETE:
		host_banner.text = ""
		host_controls.visible = false
	elif is_host:
		host_banner.text = ""
		host_controls.visible = true
	else:
		host_banner.visible = room_status == GameIds.ROOM_STATUS_LOBBY
		host_banner.text = "Waiting for host to start the game"
		host_controls.visible = false

	if start_game_button != null:
		start_game_button.disabled = not room_full or room_status != GameIds.ROOM_STATUS_LOBBY

	_refresh_member_list()


func _refresh_member_list() -> void:
	var room: Dictionary = _network_client().get_current_room()
	_rebuild_member_list(member_list, room)


func _refresh_ping_label() -> void:
	if ping_label == null:
		return
	ping_label.text = "Ping: %s" % _ping_value_text()


func _ping_text() -> String:
	return "%s ms" % _ping_value_text()


func _local_ping_ms() -> int:
	if _network_client().has_method("get_ping_ms"):
		return int(_network_client().get_ping_ms())
	return -1


func _ping_value_text() -> String:
	var ping_ms := _local_ping_ms()
	return str(ping_ms) if ping_ms >= 0 else "--"


func _rebuild_member_list(target_list: VBoxContainer, room: Dictionary) -> void:
	if target_list == null:
		return

	for child in target_list.get_children():
		target_list.remove_child(child)
		child.queue_free()

	var players_arr = room.get("players", [])
	if typeof(players_arr) != TYPE_ARRAY:
		return

	var host_peer_id: int = int(room.get("host_peer_id", -1))
	var local_peer_id: int = int(_network_client().get_local_peer_id())
	for raw_player in players_arr:
		if typeof(raw_player) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = raw_player
		var peer_id := int(player.get("peer_id", 0))
		var is_host_player := peer_id == host_peer_id
		var is_local_player := peer_id == local_peer_id
		var role := "Host" if is_host_player else "Guest"
		var suffix := " (You)" if is_local_player else ""
		var ping_ms := _player_ping_ms(peer_id)
		var ping_text := _format_ping(ping_ms)
		_add_member_line(
			target_list,
			String(player.get("display_name", "Guest")),
			suffix,
			role,
			ping_text,
			_ping_color(ping_ms),
			RemotePlayerRegistry.player_color_from_data(player)
		)


func _add_member_line(
	target_list: VBoxContainer,
	player_name: String,
	suffix: String,
	role: String,
	ping_text: String,
	ping_color: Color,
	base_color: Color
) -> void:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.bbcode_enabled = false
	label.add_theme_font_override("normal_font", BODY_FONT)
	label.add_theme_font_size_override("normal_font_size", 100)
	label.push_color(base_color)
	label.append_text("%s%s  |  %s  |  " % [player_name, suffix, role])
	label.push_color(ping_color)
	label.append_text(ping_text)
	label.pop()
	label.pop()
	target_list.add_child(label)


func _player_ping_ms(peer_id: int) -> int:
	if _network_client().has_method("get_player_ping_ms"):
		return int(_network_client().get_player_ping_ms(peer_id))
	if peer_id == int(_network_client().get_local_peer_id()):
		return _local_ping_ms()
	return -1


func _format_ping(ping_ms: int) -> String:
	return "%d ms" % ping_ms if ping_ms >= 0 else "-- ms"


func _ping_color(ping_ms: int) -> Color:
	if ping_ms < 0:
		return Color(0.78, 0.78, 0.78)
	if ping_ms < 100:
		return Color(0.42, 0.78, 0.23)
	if ping_ms < 200:
		return Color(1.0, 0.78, 0.2)
	return Color(1.0, 0.24, 0.18)


func _physics_process(delta: float) -> void:
	if _entering_match:
		return

	var room: Dictionary = _network_client().get_current_room()
	if room.is_empty():
		return

	if String(room.get("status", "")) == GameIds.ROOM_STATUS_PLAYING:
		return

	_send_timer += delta
	if _send_timer < NETWORK_SEND_INTERVAL:
		return

	_send_timer = 0.0
	if player != null and player.has_method("get_network_state"):
		var state: Dictionary = player.get_network_state(-1)
		state["room_status"] = String(room.get("status", GameIds.ROOM_STATUS_LOBBY))
		state["ping_ms"] = _local_ping_ms()
		_network_client().send_player_state(state)


func _bind_network_signals() -> void:
	var on_state := Callable(self, "_on_remote_player_state")
	if not _network_client().remote_player_state.is_connected(on_state):
		_network_client().remote_player_state.connect(on_state)

	var on_room := Callable(self, "_on_current_room_changed")
	if not _network_client().current_room_changed.is_connected(on_room):
		_network_client().current_room_changed.connect(on_room)

	var on_match := Callable(self, "_on_match_started")
	if not _network_client().match_started.is_connected(on_match):
		_network_client().match_started.connect(on_match)

	var on_error := Callable(self, "_on_network_error")
	if not _network_client().error_received.is_connected(on_error):
		_network_client().error_received.connect(on_error)

	var on_ping := Callable(self, "_on_ping_updated")
	if not _network_client().ping_updated.is_connected(on_ping):
		_network_client().ping_updated.connect(on_ping)


func _unbind_network_signals() -> void:
	var on_state := Callable(self, "_on_remote_player_state")
	if _network_client().remote_player_state.is_connected(on_state):
		_network_client().remote_player_state.disconnect(on_state)

	var on_room := Callable(self, "_on_current_room_changed")
	if _network_client().current_room_changed.is_connected(on_room):
		_network_client().current_room_changed.disconnect(on_room)

	var on_match := Callable(self, "_on_match_started")
	if _network_client().match_started.is_connected(on_match):
		_network_client().match_started.disconnect(on_match)

	var on_error := Callable(self, "_on_network_error")
	if _network_client().error_received.is_connected(on_error):
		_network_client().error_received.disconnect(on_error)

	var on_ping := Callable(self, "_on_ping_updated")
	if _network_client().ping_updated.is_connected(on_ping):
		_network_client().ping_updated.disconnect(on_ping)


func _on_current_room_changed(room: Dictionary) -> void:
	if room.is_empty():
		get_tree().paused = false
		_remove_remote_players()
		SceneTransition.change_scene("res://scenes/online_menu.tscn")
		return

	_configure_local_player(room)
	_sync_remote_roster(room)
	_apply_room_state(room)
	_refresh_hud()
	_maybe_enter_match(room)


func _on_match_started(room: Dictionary) -> void:
	_maybe_enter_match(room)


func _on_network_error(_code: String, message: String) -> void:
	host_banner.visible = true
	host_banner.text = message


func _on_ping_updated(_ping_ms: int) -> void:
	_refresh_ping_label()
	if pause_panel != null and pause_panel.visible:
		_refresh_member_list()
	_refresh_member_list()


func _on_remote_player_state(peer_id: int, state: Dictionary) -> void:
	if _entering_match:
		return

	var room: Dictionary = _network_client().get_current_room()
	if room.is_empty() or String(room.get("status", "")) == GameIds.ROOM_STATUS_PLAYING:
		return

	var remote := _ensure_remote_player(peer_id, _player_name_for_peer(peer_id), room)
	if remote.has_method("apply_network_state"):
		remote.apply_network_state(state)


func _maybe_enter_match(room: Dictionary) -> void:
	if _entering_match or room.is_empty():
		return

	if String(room.get("status", "")) != GameIds.ROOM_STATUS_PLAYING:
		return

	_entering_match = true
	get_tree().paused = false
	call_deferred("_change_to_game_scene")


func _change_to_game_scene() -> void:
	# Không dùng hiệu ứng fade của SceneTransition vì trong load_level đã có sẵn hiệu ứng slide :v
	get_tree().change_scene_to_file("res://scenes/online/online_game.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause_panel()


func _toggle_pause_panel() -> void:
	pause_panel.visible = not pause_panel.visible
	if not pause_panel.visible and option_panel != null:
		option_panel.hide()
	get_tree().paused = pause_panel.visible


func _on_pause_butt_pressed() -> void:
	_toggle_pause_panel()


func _on_select_map_pressed() -> void:
	if not is_host:
		return

	SceneTransition.change_scene("res://scenes/world_select.tscn")


func _on_start_game_pressed() -> void:
	if not _network_client().is_room_host():
		host_banner.visible = true
		host_banner.text = "Only the host can start the game."
		return

	if current_players < max_players:
		host_banner.visible = true
		host_banner.text = "Need all players before starting."
		return

	host_banner.visible = true
	host_banner.text = "Starting game..."
	_network_client().start_match()


func _on_exit_butt_pressed() -> void:
	get_tree().paused = false

	var on_room := Callable(self, "_on_current_room_changed")
	if _network_client().current_room_changed.is_connected(on_room):
		_network_client().current_room_changed.disconnect(on_room)

	_network_client().leave_room()
	SceneTransition.change_scene("res://scenes/online_menu.tscn")


func _on_cancel_butt_pressed() -> void:
	if option_panel != null:
		option_panel.hide()
	pause_panel.visible = false
	get_tree().paused = false


func _on_option_butt_pressed() -> void:
	if option_panel == null:
		return
	if option_panel.has_method("reload_settings"):
		option_panel.reload_settings()
	option_panel.show()


func _configure_local_player(room: Dictionary) -> void:
	if player == null:
		return

	var local_peer_id: int = int(_network_client().get_local_peer_id())
	var player_name := _player_name_for_peer(local_peer_id, room)
	if player.has_method("set_network_identity"):
		player.set_network_identity(local_peer_id, player_name)
	if player.has_method("set_network_remote"):
		player.set_network_remote(false)
	player.modulate = RemotePlayerRegistry.player_color_for_peer(room, local_peer_id)
	if player.has_method("set_input_enabled"):
		player.set_input_enabled(true)

	if _lobby_spawn_initialized:
		return

	var spawn_position := _lobby_spawn_position(room, local_peer_id)
	player.global_position = spawn_position
	player.spawn_position = spawn_position
	player.velocity = Vector2.ZERO
	_lobby_spawn_initialized = true


func _sync_remote_roster(room: Dictionary = {}) -> void:
	if _remote_container == null:
		return

	var room_data := room
	if room_data.is_empty():
		room_data = _network_client().get_current_room()

	var local_peer_id: int = int(_network_client().get_local_peer_id())
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
			_ensure_remote_player(peer_id, String(player_data.get("display_name", "Guest%d" % peer_id)), room_data)

	for raw_peer_id in _remote_players.keys().duplicate():
		var peer_id := int(raw_peer_id)
		if seen.has(peer_id):
			continue

		var remote = _remote_players.get(peer_id)
		if is_instance_valid(remote) and remote is Node:
			(remote as Node).queue_free()
		_remote_players.erase(peer_id)


func _ensure_remote_player(peer_id: int, player_name: String, room: Dictionary) -> CharacterBody2D:
	var existing = _remote_players.get(peer_id)
	if is_instance_valid(existing) and existing is CharacterBody2D:
		var existing_player := existing as CharacterBody2D
		existing_player.modulate = RemotePlayerRegistry.player_color_for_peer(room, peer_id)
		return existing_player
	_remote_players.erase(peer_id)

	var remote := PLAYER_SCENE.instantiate() as CharacterBody2D
	remote.name = "RemotePlayer_%d" % peer_id
	_remote_container.add_child(remote)
	if remote.has_method("set_network_identity"):
		remote.set_network_identity(peer_id, player_name)
	if remote.has_method("set_network_remote"):
		remote.set_network_remote(true)
	remote.modulate = RemotePlayerRegistry.player_color_for_peer(room, peer_id)

	var spawn_position := _lobby_spawn_position(room, peer_id)
	remote.global_position = spawn_position
	remote.spawn_position = spawn_position
	remote.velocity = Vector2.ZERO
	_remote_players[peer_id] = remote
	return remote


func _remove_remote_players() -> void:
	for value in _remote_players.values():
		if is_instance_valid(value) and value is Node:
			(value as Node).queue_free()
	_remote_players.clear()


func _player_name_for_peer(peer_id: int, room: Dictionary = {}) -> String:
	var room_data := room
	if room_data.is_empty():
		room_data = _network_client().get_current_room()

	var players = room_data.get("players", [])
	if typeof(players) != TYPE_ARRAY:
		return "Player"

	for raw_player in players:
		if typeof(raw_player) != TYPE_DICTIONARY:
			continue

		var player_data: Dictionary = raw_player
		if int(player_data.get("peer_id", 0)) == peer_id:
			return String(player_data.get("display_name", "Player"))

	return "Player"


func _lobby_spawn_position(room: Dictionary, peer_id: int) -> Vector2:
	var origin := player_spawn.global_position if player_spawn != null else Vector2.ZERO
	var slot_offsets := [
		Vector2(-180.0, 0.0),
		Vector2(180.0, 0.0),
		Vector2(-90.0, 110.0),
		Vector2(90.0, 110.0),
	]

	var players = room.get("players", [])
	if typeof(players) != TYPE_ARRAY:
		return origin

	for index in range(players.size()):
		if typeof(players[index]) != TYPE_DICTIONARY:
			continue
		var player_data: Dictionary = players[index]
		if int(player_data.get("peer_id", 0)) != peer_id:
			continue
		if index >= 0 and index < slot_offsets.size():
			return origin + slot_offsets[index]
		return origin + Vector2((index % 2) * 180.0 - 90.0, (index / 2) * 110.0)

	return origin


func _network_client() -> Node:
	return get_node("/root/NetworkClient")


func _configure_music() -> void:
	if music_player == null:
		return

	OptionsState.assign_music_bus(music_player)
	music_player.stream = CO_OP_MUSIC
	if not music_player.finished.is_connected(_on_music_finished):
		music_player.finished.connect(_on_music_finished)
	music_player.play()


func _on_music_finished() -> void:
	if music_player != null:
		music_player.play()
