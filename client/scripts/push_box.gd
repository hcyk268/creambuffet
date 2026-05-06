extends RigidBody2D

@export var online_target_speed := 95.0
@export var online_acceleration := 14.0
@export var online_drag := 18.0

var _online_authoritative := false
var _server_drive_x := 0.0
var _server_control_updated_at_ms := 0


func _ready() -> void:
	add_to_group("pushable")


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


func set_online_authoritative(enabled: bool) -> void:
	_online_authoritative = enabled
	if not enabled:
		_server_drive_x = 0.0
		_server_control_updated_at_ms = 0


func apply_server_push_control(drive_x: float) -> void:
	_online_authoritative = true
	_server_drive_x = clampf(drive_x, -1.0, 1.0)
	_server_control_updated_at_ms = Time.get_ticks_msec()
