extends CanvasLayer

const PlayerCapabilities = preload("res://scripts/player/player_capabilities.gd")
const BODY_FONT := preload("res://assets/fonts/EXEPixelPerfect.ttf")

@export var main_menu_scene := "res://scenes/start_menu.tscn"
@export var online_menu_scene := "res://scenes/online_menu.tscn"
@export var level_select_scene := "res://scenes/level_select.tscn"
@export var pause_tree_on_open := true
@export var block_player_input_on_open := true
@export var leave_room_on_exit := true

@onready var _dim: ColorRect = $Dim
@onready var _panel: PanelContainer = $Panel
@onready var _member_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/MemberList
@onready var _level_butt: Button = $Panel/MarginContainer/VBoxContainer/Buttons/LevelButt
@onready var _option_butt: Button = $OptionButt
@onready var _option_panel: Control = $OptionPanel
@onready var _level_select_overlay: Control = $LevelSelectOverlay

var _is_open := false
var _previous_pause_state := false
var _ping_connected := false
var _remote_state_connected := false
var _level_select_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_panel_visible(false)
	_option_panel.visibility_changed.connect(_on_option_panel_visibility_changed)
	if _level_select_overlay.has_signal("overlay_closed"):
		_level_select_overlay.overlay_closed.connect(_on_level_select_overlay_closed)
	if _level_select_overlay.has_signal("level_change_confirmed"):
		_level_select_overlay.level_change_confirmed.connect(_on_level_change_confirmed)


func _exit_tree() -> void:
	_unbind_ping_signal()
	if _is_open:
		_set_game_input_enabled(true)
		if pause_tree_on_open:
			get_tree().paused = _previous_pause_state


func _unhandled_input(event: InputEvent) -> void:
	var completion_screen := get_parent().get_node_or_null("CompletionScreen") if get_parent() != null else null
	if completion_screen != null and completion_screen.has_method("is_open") and completion_screen.is_open():
		return

	if event.is_action_pressed("ui_cancel"):
		if _level_select_open:
			return
		if _option_panel.visible:
			_option_panel.hide()
			get_viewport().set_input_as_handled()
			return
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	if _is_open:
		return

	_is_open = true
	_previous_pause_state = get_tree().paused
	_refresh_member_list()
	_bind_ping_signal()
	_set_panel_visible(true)
	_set_game_input_enabled(false)

	if pause_tree_on_open:
		get_tree().paused = true


func close() -> void:
	if not _is_open:
		return

	if _option_panel != null:
		_option_panel.hide()
	_unbind_ping_signal()
	_set_panel_visible(false)
	_is_open = false
	_set_game_input_enabled(true)

	if pause_tree_on_open:
		get_tree().paused = _previous_pause_state


func _set_panel_visible(visible_state: bool) -> void:
	_dim.visible = visible_state
	_panel.visible = visible_state
	_option_butt.visible = visible_state
	_level_butt.visible = visible_state and _can_open_level_select()


func _on_exit_butt_pressed() -> void:
	_prepare_to_leave_game()
	var exit_scene := _exit_scene_path()
	_change_scene(exit_scene)


func _on_cancel_butt_pressed() -> void:
	close()


func _on_level_butt_pressed() -> void:
	if not _can_open_level_select():
		return

	_open_level_select_overlay()


func _on_option_butt_pressed() -> void:
	if _option_panel == null:
		return
	if _option_panel.has_method("reload_settings"):
		_option_panel.reload_settings()
	_option_panel.show()


func _on_option_panel_visibility_changed() -> void:
	if _dim == null:
		return
	if _is_open:
		_dim.visible = not _option_panel.visible


func _on_ping_updated(_ping_ms: int) -> void:
	if _is_open:
		_refresh_member_list()


func _on_remote_player_state(_peer_id: int, _state: Dictionary) -> void:
	if _is_open:
		_refresh_member_list()


func _bind_ping_signal() -> void:
	var network_client := _network_client()
	if network_client == null or _ping_connected:
		_bind_remote_state_signal()
		return
	if network_client.has_signal("ping_updated"):
		var on_ping := Callable(self, "_on_ping_updated")
		if not network_client.ping_updated.is_connected(on_ping):
			network_client.ping_updated.connect(on_ping)
			_ping_connected = true
	_bind_remote_state_signal()


func _bind_remote_state_signal() -> void:
	var network_client := _network_client()
	if network_client == null or _remote_state_connected:
		return
	if network_client.has_signal("remote_player_state"):
		var on_remote_state := Callable(self, "_on_remote_player_state")
		if not network_client.remote_player_state.is_connected(on_remote_state):
			network_client.remote_player_state.connect(on_remote_state)
			_remote_state_connected = true


func _unbind_ping_signal() -> void:
	var network_client := _network_client()
	if network_client == null:
		return
	var on_ping := Callable(self, "_on_ping_updated")
	if _ping_connected and network_client.ping_updated.is_connected(on_ping):
		network_client.ping_updated.disconnect(on_ping)
	_ping_connected = false
	var on_remote_state := Callable(self, "_on_remote_player_state")
	if _remote_state_connected and network_client.remote_player_state.is_connected(on_remote_state):
		network_client.remote_player_state.disconnect(on_remote_state)
	_remote_state_connected = false


func _refresh_member_list() -> void:
	if _member_list == null:
		return

	for child in _member_list.get_children():
		_member_list.remove_child(child)
		child.queue_free()

	var network_client := _network_client()
	if network_client == null or not network_client.has_method("get_current_room"):
		_add_plain_member_line("Offline")
		return

	var room: Dictionary = network_client.get_current_room()
	if room.is_empty():
		_add_plain_member_line("Offline")
		return

	var players_arr = room.get("players", [])
	if typeof(players_arr) != TYPE_ARRAY:
		return

	var host_peer_id := int(room.get("host_peer_id", -1))
	var local_peer_id := int(network_client.get_local_peer_id()) if network_client.has_method("get_local_peer_id") else -1
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
		_add_member_line(
			String(player.get("display_name", "Guest")),
			suffix,
			role,
			_format_ping(ping_ms),
			_ping_color(ping_ms)
		)


func _add_plain_member_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", 100)
	_member_list.add_child(label)


func _add_member_line(
	player_name: String,
	suffix: String,
	role: String,
	ping_text: String,
	ping_color: Color
) -> void:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.bbcode_enabled = false
	label.add_theme_font_override("normal_font", BODY_FONT)
	label.add_theme_font_size_override("normal_font_size", 100)
	label.append_text("%s%s  |  %s  |  " % [player_name, suffix, role])
	label.push_color(ping_color)
	label.append_text(ping_text)
	label.pop()
	_member_list.add_child(label)


func _ping_text() -> String:
	var network_client := _network_client()
	if network_client == null or not network_client.has_method("get_ping_ms"):
		return "-- ms"
	var ping_ms := int(network_client.get_ping_ms())
	return "%s ms" % ping_ms if ping_ms >= 0 else "-- ms"


func _player_ping_ms(peer_id: int) -> int:
	var network_client := _network_client()
	if network_client == null:
		return -1
	if network_client.has_method("get_player_ping_ms"):
		return int(network_client.get_player_ping_ms(peer_id))
	if network_client.has_method("get_local_peer_id") and peer_id == int(network_client.get_local_peer_id()):
		return int(network_client.get_ping_ms()) if network_client.has_method("get_ping_ms") else -1
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


func _exit_scene_path() -> String:
	var network_client := _network_client()
	if network_client != null and network_client.has_method("get_current_room"):
		var room: Dictionary = network_client.get_current_room()
		if not room.is_empty():
			return online_menu_scene
	return main_menu_scene


func _prepare_to_leave_game() -> void:
	_set_panel_visible(false)
	_is_open = false
	_set_game_input_enabled(true)
	get_tree().paused = false

	if not leave_room_on_exit:
		return

	var network_client := _network_client()
	if network_client != null and network_client.has_method("get_current_room") and network_client.has_method("leave_room"):
		var room: Dictionary = network_client.get_current_room()
		if not room.is_empty():
			network_client.leave_room()


func _prepare_to_open_level_select() -> void:
	if _option_panel != null:
		_option_panel.hide()
	_set_panel_visible(false)
	_is_open = false
	_unbind_ping_signal()
	_set_game_input_enabled(true)
	get_tree().paused = false


func _open_level_select_overlay() -> void:
	if _level_select_overlay == null or not _level_select_overlay.has_method("open_overlay"):
		_prepare_to_open_level_select()
		_change_scene(level_select_scene)
		return

	if _option_panel != null:
		_option_panel.hide()
	_set_panel_visible(false)
	_is_open = false
	_unbind_ping_signal()
	_level_select_open = true
	get_tree().paused = false
	_set_game_input_enabled(false)
	_level_select_overlay.open_overlay()
	if not _level_select_overlay.visible:
		_on_level_select_overlay_closed()


func _on_level_select_overlay_closed() -> void:
	_level_select_open = false
	_set_game_input_enabled(true)


func _on_level_change_confirmed(level_index: int) -> void:
	var game_root := get_parent()
	if game_root == null or not game_root.has_method("load_level"):
		return

	var current_level_index := int(game_root.get("_current_level_index"))
	if current_level_index == level_index:
		return

	game_root.load_level(level_index)


func _can_open_level_select() -> bool:
	var network_client := _network_client()
	if network_client == null or not network_client.has_method("get_current_room"):
		return false
	var room: Dictionary = network_client.get_current_room()
	if room.is_empty():
		return false
	if network_client.has_method("is_room_host") and not bool(network_client.is_room_host()):
		return false
	if network_client.has_method("is_match_active"):
		return bool(network_client.is_match_active())
	return String(room.get("status", "")) == "playing"


func _set_game_input_enabled(enabled: bool) -> void:
	if not block_player_input_on_open:
		return

	var game_root := get_parent()
	if game_root == null:
		return

	var player := game_root.get_node_or_null("Player")
	PlayerCapabilities.set_input_enabled(player, enabled)


func _network_client() -> Node:
	return get_node_or_null("/root/NetworkClient")


func _change_scene(path: String) -> void:
	var scene_transition := get_node_or_null("/root/SceneTransition")
	if scene_transition != null and scene_transition.has_method("change_scene"):
		scene_transition.change_scene(path)
		return
	get_tree().change_scene_to_file(path)
