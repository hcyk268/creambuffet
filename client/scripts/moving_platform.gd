@tool
extends AnimatableBody2D

enum MovementMode {
	HORIZONTAL,
	VERTICAL,
}

@export var movement_mode: MovementMode = MovementMode.HORIZONTAL:
	set(value):
		_movement_mode = value
		queue_redraw()
	get:
		return _movement_mode

@export var diameter := 64.0:
	set(value):
		_diameter = maxf(value, 0.0)
		queue_redraw()
	get:
		return _diameter

@export var activation := false:
	set(value):
		_activation = value
		_apply_activation_state()
	get:
		return _activation

@export var sync_id := ""

@onready var platform_state: AnimationPlayer = $PlatformState

const MOVE_SPEED := 45.0
const GUIDE_COLOR := Color(0.2, 0.9, 1.0, 0.85)
const GUIDE_END_CAP := 4.0
const GUIDE_LINE_WIDTH := 1.0
const GUIDE_CENTER_RADIUS := 1.75

var _movement_mode: MovementMode = MovementMode.HORIZONTAL
var _diameter := 64.0
var _activation := false
var _origin := Vector2.ZERO
var _travel_direction := 1.0
var _server_elapsed_at_sync := 0.0
var _local_sync_time_ms := 0
var _has_server_phase := false


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		queue_redraw()


func _ready() -> void:
	add_to_group("moving_platform")
	_origin = global_position
	_apply_activation_state()
	queue_redraw()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()


func _physics_process(delta: float) -> void:
	if not activation:
		_origin = global_position
		_travel_direction = 1.0
		_has_server_phase = false
		return

	if _has_server_phase:
		var elapsed := _server_elapsed_at_sync + maxf(float(Time.get_ticks_msec() - _local_sync_time_ms) / 1000.0, 0.0)
		_seek_to_elapsed(elapsed)
		queue_redraw()
		return

	var axis := _movement_axis()
	var half_range := _scaled_half_range()
	var offset_along_axis := (global_position - _origin).dot(axis)
	var next_offset := offset_along_axis + (_travel_direction * MOVE_SPEED * delta)
	if next_offset > half_range:
		next_offset = half_range
		_travel_direction = -1.0
	elif next_offset < -half_range:
		next_offset = -half_range
		_travel_direction = 1.0

	global_position = _origin + (axis * next_offset)
	queue_redraw()


func set_activation(enabled: bool) -> void:
	activation = enabled


func apply_server_state(state: Dictionary) -> void:
	var next_activation := bool(state.get("active", activation))
	if not next_activation:
		_has_server_phase = false
		set_activation(false)
		return

	set_activation(true)
	var started_at_ms := _numeric_state_value(state, "active_started_at_ms", -1)
	var server_time_ms := _numeric_state_value(state, "server_time_ms", -1)
	if started_at_ms < 0 or server_time_ms < 0:
		return

	_server_elapsed_at_sync = maxf(float(server_time_ms - started_at_ms) / 1000.0, 0.0)
	_local_sync_time_ms = Time.get_ticks_msec()
	_has_server_phase = true
	_seek_to_elapsed(_server_elapsed_at_sync)


func _movement_axis() -> Vector2:
	return Vector2.RIGHT if movement_mode == MovementMode.HORIZONTAL else Vector2.DOWN


func _scaled_half_range() -> float:
	var axis_scale := absf(scale.x) if movement_mode == MovementMode.HORIZONTAL else absf(scale.y)
	return maxf(diameter, 0.0) * 0.5 * axis_scale


func _seek_to_elapsed(elapsed: float) -> void:
	var axis := _movement_axis()
	var half_range := _scaled_half_range()
	if half_range <= 0.0:
		global_position = _origin
		_travel_direction = 1.0
		return

	var distance := maxf(elapsed, 0.0) * MOVE_SPEED
	var offset := 0.0
	if distance <= half_range:
		offset = distance
		_travel_direction = 1.0
	else:
		var cycle_distance := fmod(distance - half_range, half_range * 4.0)
		if cycle_distance <= half_range * 2.0:
			offset = half_range - cycle_distance
			_travel_direction = -1.0
		else:
			offset = -half_range + (cycle_distance - half_range * 2.0)
			_travel_direction = 1.0

	global_position = _origin + (axis * offset)


func _numeric_state_value(state: Dictionary, key: String, fallback: int) -> int:
	var raw_value: Variant = state.get(key, fallback)
	if typeof(raw_value) == TYPE_INT or typeof(raw_value) == TYPE_FLOAT:
		return int(raw_value)
	return fallback


func _apply_activation_state() -> void:
	if not is_node_ready():
		return

	var animation_name := "Activated" if activation else "Inactivated"
	if platform_state.has_animation(animation_name):
		platform_state.play(animation_name)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	var axis := _movement_axis()
	var half_range := diameter * 0.5
	var start := -axis * half_range
	var finish := axis * half_range
	var cross_axis := Vector2(-axis.y, axis.x)

	draw_line(start, finish, GUIDE_COLOR, GUIDE_LINE_WIDTH)
	draw_line(start - cross_axis * GUIDE_END_CAP, start + cross_axis * GUIDE_END_CAP, GUIDE_COLOR, GUIDE_LINE_WIDTH)
	draw_line(finish - cross_axis * GUIDE_END_CAP, finish + cross_axis * GUIDE_END_CAP, GUIDE_COLOR, GUIDE_LINE_WIDTH)
	draw_circle(Vector2.ZERO, GUIDE_CENTER_RADIUS, GUIDE_COLOR)
