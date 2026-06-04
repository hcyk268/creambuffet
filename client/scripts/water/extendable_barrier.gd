extends StaticBody2D
class_name ExtendableBarrier

@export var sprite_base_scale := Vector2(0.1, 0.1)
@export_range(0.0, 4.0, 0.05) var min_length_ratio := 0.0
@export_range(0.0, 4.0, 0.05) var max_length_ratio := 1.6
@export var cycle_duration := 2.0
@export var manual_extend_speed := 1.4
@export var manual_retract_speed := 1.8
@export var animate_manual_changes := true
@export var auto_cycle := true
@export var start_extended := false
@export var hide_when_retracted := true
@export var open := false:
	set(value):
		open = value
		if is_node_ready():
			_set_open_target(false)
@export var sync_id := ""

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

const ATLAS_SIZE := Vector2(64, 318)

var _time := 0.0
var _manual_ratio := 1.0
var _target_ratio := 1.0


func _ready() -> void:
	add_to_group("extendable_barrier")
	if collision_shape != null and collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()
	_time = cycle_duration * 0.5 if start_extended else 0.0
	if open or not auto_cycle:
		_set_open_target(true)
	else:
		_apply_length(_get_current_ratio())


func _process(delta: float) -> void:
	if not auto_cycle:
		_update_manual_length(delta)
		return

	if cycle_duration <= 0.0:
		_apply_length(max_length_ratio)
		return

	_time = fmod(_time + delta, cycle_duration)
	_apply_length(_get_current_ratio())


func set_length_ratio(ratio: float) -> void:
	auto_cycle = false
	open = false
	_manual_ratio = clampf(ratio, 0.0, max_length_ratio)
	_target_ratio = _manual_ratio
	_apply_length(_manual_ratio)


func set_activation(enabled: bool) -> void:
	auto_cycle = enabled


func set_open(opened: bool) -> void:
	open = opened


func _get_current_ratio() -> float:
	var phase := _time / maxf(cycle_duration, 0.001)
	var wave := 0.5 - cos(phase * TAU) * 0.5
	return lerpf(min_length_ratio, max_length_ratio, wave)


func _apply_length(length_ratio: float) -> void:
	var ratio := clampf(length_ratio, 0.0, max_length_ratio)
	if not open and ratio > 0.0:
		ratio = maxf(ratio, min_length_ratio)
	var is_retracted := ratio <= 0.001
	var displayed_size := Vector2(
		ATLAS_SIZE.x * sprite_base_scale.x,
		ATLAS_SIZE.y * sprite_base_scale.y * ratio
	)

	visible = not (hide_when_retracted and is_retracted)
	if sprite != null:
		sprite.scale = Vector2(sprite_base_scale.x, sprite_base_scale.y * ratio)
		sprite.position = Vector2(0, displayed_size.y * 0.5)
		sprite.visible = not (hide_when_retracted and is_retracted)

	if collision_shape != null:
		if collision_shape.shape is RectangleShape2D:
			var rect := collision_shape.shape as RectangleShape2D
			rect.size = displayed_size
		collision_shape.position = Vector2(0, displayed_size.y * 0.5)
		collision_shape.set_deferred("disabled", is_retracted)


func _set_open_target(instant := false) -> void:
	auto_cycle = false
	_target_ratio = 0.0 if open else max_length_ratio
	if instant or not animate_manual_changes:
		_manual_ratio = _target_ratio
	_apply_length(_manual_ratio)


func _update_manual_length(delta: float) -> void:
	var speed := manual_extend_speed
	if _target_ratio < _manual_ratio:
		speed = manual_retract_speed

	_manual_ratio = move_toward(_manual_ratio, _target_ratio, maxf(speed, 0.0) * delta)
	_apply_length(_manual_ratio)
