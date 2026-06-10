extends RigidBody2D

const BLOCK_PUSH_SFX := preload("res://assets/sound/block push.wav")

@export var sync_id := ""
@export var online_target_speed := 95.0
@export var online_acceleration := 14.0
@export var online_drag := 18.0

@onready var sfx_player: AudioStreamPlayer = get_node_or_null("SfxPlayer") as AudioStreamPlayer

var _online_authoritative := false
var _server_drive_x := 0.0
var _server_control_updated_at_ms := 0
var _last_push_sfx_ms := 0


func _ready() -> void:
	add_to_group("pushable")
	if sfx_player != null:
		sfx_player.stream = BLOCK_PUSH_SFX


func _physics_process(delta: float) -> void:
	if not _online_authoritative:
		return

	if Time.get_ticks_msec() - _server_control_updated_at_ms > 200:
		_server_drive_x = 0.0

	sleeping = false
	var target_velocity_x := _server_drive_x * online_target_speed
	var response := online_acceleration if absf(_server_drive_x) > 0.01 else online_drag
	var next_velocity := linear_velocity
	next_velocity.x = move_toward(next_velocity.x, target_velocity_x, response * delta * online_target_speed)
	linear_velocity = next_velocity
	_play_push_sfx(next_velocity)


func set_online_authoritative(enabled: bool) -> void:
	_online_authoritative = enabled
	if not enabled:
		_server_drive_x = 0.0
		_server_control_updated_at_ms = 0


func apply_server_push_control(drive_x: float) -> void:
	_online_authoritative = true
	_server_drive_x = clampf(drive_x, -1.0, 1.0)
	_server_control_updated_at_ms = Time.get_ticks_msec()


func apply_server_position(position: Vector2) -> void:
	_online_authoritative = true
	global_position = position
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_server_drive_x = 0.0
	_server_control_updated_at_ms = Time.get_ticks_msec()
	sleeping = false


func _play_push_sfx(next_velocity: Vector2) -> void:
	if sfx_player == null or sfx_player.stream == null:
		return

	if absf(next_velocity.x) < 20.0:
		return

	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_push_sfx_ms < 350:
		return

	if not sfx_player.playing:
		_last_push_sfx_ms = now_ms
		sfx_player.play()
