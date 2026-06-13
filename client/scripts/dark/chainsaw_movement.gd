@tool
extends AnimatableBody2D

@export var sync_id := ""

enum MovementMode {
	HORIZONTAL,
	VERTICAL,
	DIAGONAL,
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
		

@onready var chainsaw_state: AnimationPlayer = $ChainsawState
@onready var detect_area : Area2D = $Area2D
@onready var sfx : AudioStreamPlayer2D = $Sfx

const MOVE_SPEED := 60.0
const GUIDE_COLOR := Color(0.2, 0.9, 1.0, 0.85)
const GUIDE_END_CAP := 4.0
const GUIDE_LINE_WIDTH := 1.0
const GUIDE_CENTER_RADIUS := 1.75

var _movement_mode: MovementMode = MovementMode.HORIZONTAL
var _diameter := 64.0
var _activation := false
var _origin := Vector2.ZERO
var _travel_direction := 1.0


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		set_process(true)
		queue_redraw()


func _ready() -> void:
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
		return

	var axis := _movement_axis()
	var half_range := maxf(diameter, 0.0) * 0.5 * scale.x
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


func _movement_axis() -> Vector2:
	match movement_mode:
		MovementMode.HORIZONTAL:
			return Vector2.RIGHT
		MovementMode.VERTICAL:
			return Vector2.DOWN
		MovementMode.DIAGONAL:
			return Vector2.RIGHT.rotated(deg_to_rad(rotation_degrees))
	return Vector2.RIGHT


func _apply_activation_state() -> void:
	if not is_node_ready():
		return

	var animation_name := "Activated" if activation else "Inactivated"
	if chainsaw_state.has_animation(animation_name):
		chainsaw_state.play(animation_name)
	
	if activation:
		sfx.play()
	else:
		sfx.stop()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	var axis := _movement_axis()
	if movement_mode == MovementMode.DIAGONAL:
		axis = axis.rotated(-rotation)
	var half_range := diameter * 0.5
	var start := -axis * half_range
	var finish := axis * half_range
	var cross_axis := Vector2(-axis.y, axis.x)

	draw_line(start, finish, GUIDE_COLOR, GUIDE_LINE_WIDTH)
	draw_line(start - cross_axis * GUIDE_END_CAP, start + cross_axis * GUIDE_END_CAP, GUIDE_COLOR, GUIDE_LINE_WIDTH)
	draw_line(finish - cross_axis * GUIDE_END_CAP, finish + cross_axis * GUIDE_END_CAP, GUIDE_COLOR, GUIDE_LINE_WIDTH)
	draw_circle(Vector2.ZERO, GUIDE_CENTER_RADIUS, GUIDE_COLOR)
