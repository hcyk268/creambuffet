extends Node2D

# ============================================================
# Room Scene - khuon vien cho giua nguoi choi (online room view)
# ============================================================
# Day la scene xuat hien sau khi user vao mot phong (qua create/join).
# State duoc lay tu autoload NetworkClient (luon ton tai qua cac scene).
# Neu chay thang scene F6 ma chua connect, NetworkClient tra ve room
# rong -> dung gia tri @export ben duoi lam fallback de test.
# ============================================================
#
# Cau truc scene (xem trong Godot Editor):
#
#   Room (Node2D)                     <- script nay gan o day
#   |- BackgroundLayer  (CanvasLayer) <- nen cho dep, khong anh huong gameplay
#   |- Camera2D                       <- camera nhin vao khuon vien
#   |- Floor (StaticBody2D)           <- san de player dung (WorldBoundary)
#   |- PlayerSpawn (Marker2D)         <- danh dau cho spawn local player
#   |- Player (instance)              <- nhan vat player_soda
#   |- HUD (CanvasLayer)              <- UI overlay: ten phong, so player, banner
#   |- PausePanel (CanvasLayer)       <- cua so ESC: danh sach member + Exit/Cancel
#
# ------------------------------------------------------------
# Quy uoc process_mode (quan trong de pause hoat dong dung):
#   - Room (root):    ALWAYS    -> script van chay khi pause (de bam ESC unpause)
#   - Player:         PAUSABLE  -> dung khi pause
#   - HUD/PausePanel: ALWAYS    -> nut Cancel/Exit van click duoc khi pause
# ============================================================


# ---- Fallback @export (chi dung khi chay scene truc tiep, NetworkClient rong) ----
@export var is_host: bool = true
@export var max_players: int = 4
@export var current_players: int = 1


# ---- Tham chieu node trong scene ----
@onready var host_banner: Label = $HUD/HostBanner
@onready var player_count_label: Label = $HUD/TopBar/PlayerCount
@onready var pause_panel: CanvasLayer = $PausePanel
@onready var member_list: VBoxContainer = $PausePanel/Panel/MarginContainer/VBoxContainer/MemberList


func _ready() -> void:
	var room: Dictionary = _network_client().get_current_room()
	if not room.is_empty():
		_apply_room_state(room)

	var on_room := Callable(self, "_on_current_room_changed")
	if not _network_client().current_room_changed.is_connected(on_room):
		_network_client().current_room_changed.connect(on_room)

	_refresh_hud()
	pause_panel.visible = false
	get_tree().paused = false


func _exit_tree() -> void:
	var on_room := Callable(self, "_on_current_room_changed")
	if _network_client().current_room_changed.is_connected(on_room):
		_network_client().current_room_changed.disconnect(on_room)


func _apply_room_state(room: Dictionary) -> void:
	is_host = _network_client().is_room_host()
	max_players = int(room.get("max_players", max_players))
	var players_arr = room.get("players", [])
	if typeof(players_arr) == TYPE_ARRAY:
		current_players = (players_arr as Array).size()


func _refresh_hud() -> void:
	player_count_label.text = "%d/%d" % [current_players, max_players]
	host_banner.visible = is_host
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
		label.add_theme_font_size_override("font_size", 36)
		var role := "Host" if int(player.get("peer_id", 0)) == host_peer_id else "Ready"
		label.text = "%s     peer %d     %s" % [
			String(player.get("display_name", "Guest")),
			int(player.get("peer_id", 0)),
			role,
		]
		member_list.add_child(label)


func _on_current_room_changed(room: Dictionary) -> void:
	if room.is_empty():
		# Da bi server kick hoac leave -> ve menu online.
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/online_menu.tscn")
		return

	_apply_room_state(room)
	_refresh_hud()


# Bat input ngoai UI (chi trigger khi khong click vao button nao).
#   ESC   -> bat/tat PausePanel
#   ENTER -> chi host moi co quyen (placeholder chon world)
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause_panel()
	elif event.is_action_pressed("ui_accept") and is_host:
		_on_host_enter_pressed()


func _toggle_pause_panel() -> void:
	pause_panel.visible = not pause_panel.visible
	# Pause/unpause toan bo tree theo trang thai panel.
	# Player co process_mode = PAUSABLE nen se tu dung/chay lai.
	get_tree().paused = pause_panel.visible


# ---- Host bam ENTER -> mo World Select scene ----
func _on_host_enter_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/world_select.tscn")


# ---- Nut Exit trong PausePanel: thoat ve menu chinh ----
func _on_exit_butt_pressed() -> void:
	get_tree().paused = false

	# Disconnect listener TRUOC khi goi leave_room().
	# Ly do: neu state = DISCONNECTED, leave_room() se goi _set_current_room({})
	# dong bo va emit `current_room_changed` ngay -> handler _on_current_room_changed
	# se tu navigate -> race voi change_scene_to_file ben duoi (loi "data.tree is null").
	var on_room := Callable(self, "_on_current_room_changed")
	if _network_client().current_room_changed.is_connected(on_room):
		_network_client().current_room_changed.disconnect(on_room)

	_network_client().leave_room()
	get_tree().change_scene_to_file("res://scenes/online_menu.tscn")


# ---- Nut Cancel trong PausePanel: dong panel, tiep tuc choi ----
func _on_cancel_butt_pressed() -> void:
	pause_panel.visible = false
	get_tree().paused = false


func _network_client() -> Node:
	return get_node("/root/NetworkClient")
