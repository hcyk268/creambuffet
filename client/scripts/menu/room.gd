extends Node2D

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const BODY_FONT := preload("res://assets/fonts/EXEPixelPerfect.ttf")

@export var is_host: bool = true
@export var max_players: int = 4
@export var current_players: int = 1

@onready var host_banner: Label = $HUD/HostBanner
@onready var player_count_label: Label = $HUD/TopBar/PlayerCount
@onready var room_title_label: Label = $HUD/TopBar/RoomTitle
@onready var map_label: Label = $HUD/BottomBar/MapLabel
@onready var host_controls: HBoxContainer = $HUD/BottomBar/HostControls
@onready var pause_panel: CanvasLayer = $PausePanel
@onready var member_list: VBoxContainer = $PausePanel/Panel/MarginContainer/VBoxContainer/MemberList

var _entering_match := false


func _ready() -> void:
	var room: Dictionary = _network_client().get_current_room()
	if room.is_empty():
		get_tree().change_scene_to_file("res://scenes/online_menu.tscn")
		return

	_apply_room_state(room)
	_bind_network_signals()
	_refresh_hud()
	pause_panel.visible = false
	get_tree().paused = false


func _exit_tree() -> void:
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
	var level_count := int(room.get("world_count", GameCatalog.get_level_ids(map_id).size()))

	room_title_label.text = "ROOM %s" % room_id if not room_id.is_empty() else "ROOM"
	player_count_label.text = "%d/%d" % [current_players, max_players]
	map_label.text = "Map: %s (%d levels)" % [map_title, level_count]

	if is_host:
		host_banner.text = "Choose a map, then start the game."
		host_controls.visible = true
	else:
		host_banner.text = "Waiting for host to choose a map and start..."
		host_controls.visible = false

	_refresh_member_list()


func _refresh_member_list() -> void:
	if member_list == null:
		return

	for child in member_list.get_children():
		member_list.remove_child(child)
		child.queue_free()

	var room: Dictionary = _network_client().get_current_room()
	var players_arr = room.get("players", [])
	if typeof(players_arr) != TYPE_ARRAY:
		return

	var host_peer_id: int = int(room.get("host_peer_id", -1))
	for raw_player in players_arr:
		if typeof(raw_player) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = raw_player
		var label := Label.new()
		label.add_theme_font_override("font", BODY_FONT)
		label.add_theme_font_size_override("font_size", 36)
		var role := "Host" if int(player.get("peer_id", 0)) == host_peer_id else "Ready"
		label.text = "%s     peer %d     %s" % [
			String(player.get("display_name", "Guest")),
			int(player.get("peer_id", 0)),
			role,
		]
		member_list.add_child(label)


func _bind_network_signals() -> void:
	var on_room := Callable(self, "_on_current_room_changed")
	if not _network_client().current_room_changed.is_connected(on_room):
		_network_client().current_room_changed.connect(on_room)

	var on_match := Callable(self, "_on_match_started")
	if not _network_client().match_started.is_connected(on_match):
		_network_client().match_started.connect(on_match)

	var on_error := Callable(self, "_on_network_error")
	if not _network_client().error_received.is_connected(on_error):
		_network_client().error_received.connect(on_error)


func _unbind_network_signals() -> void:
	var on_room := Callable(self, "_on_current_room_changed")
	if _network_client().current_room_changed.is_connected(on_room):
		_network_client().current_room_changed.disconnect(on_room)

	var on_match := Callable(self, "_on_match_started")
	if _network_client().match_started.is_connected(on_match):
		_network_client().match_started.disconnect(on_match)

	var on_error := Callable(self, "_on_network_error")
	if _network_client().error_received.is_connected(on_error):
		_network_client().error_received.disconnect(on_error)


func _on_current_room_changed(room: Dictionary) -> void:
	if room.is_empty():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/online_menu.tscn")
		return

	_apply_room_state(room)
	_refresh_hud()
	_maybe_enter_match(room)


func _on_match_started(room: Dictionary) -> void:
	_maybe_enter_match(room)


func _on_network_error(_code: String, message: String) -> void:
	host_banner.text = message


func _maybe_enter_match(room: Dictionary) -> void:
	if _entering_match or room.is_empty():
		return

	if String(room.get("status", "")) != "playing":
		return

	_entering_match = true
	get_tree().paused = false
	call_deferred("_change_to_game_scene")


func _change_to_game_scene() -> void:
	get_tree().change_scene_to_file("res://scenes/online/online_game.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause_panel()


func _toggle_pause_panel() -> void:
	pause_panel.visible = not pause_panel.visible
	get_tree().paused = pause_panel.visible


func _on_select_map_pressed() -> void:
	if not is_host:
		return

	get_tree().change_scene_to_file("res://scenes/world_select.tscn")


func _on_start_game_pressed() -> void:
	if not _network_client().is_room_host():
		host_banner.text = "Only the host can start the game."
		return

	host_banner.text = "Starting game..."
	_network_client().start_match()


func _on_exit_butt_pressed() -> void:
	get_tree().paused = false

	var on_room := Callable(self, "_on_current_room_changed")
	if _network_client().current_room_changed.is_connected(on_room):
		_network_client().current_room_changed.disconnect(on_room)

	_network_client().leave_room()
	get_tree().change_scene_to_file("res://scenes/online_menu.tscn")


func _on_cancel_butt_pressed() -> void:
	pause_panel.visible = false
	get_tree().paused = false


func _network_client() -> Node:
	return get_node("/root/NetworkClient")
