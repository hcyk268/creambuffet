extends AnimatableBody2D

@export var online_target_speed := 125.0
@export var online_acceleration := 22.0
@export var online_drag := 12.0
@export var gravity_scale := 1.0
@export var max_fall_speed := 900.0
@export var stacked_contact_tolerance := 2.0
@export var stacked_overlap_margin := 2.0

var _drive_x := 0.0
var _velocity := Vector2.ZERO
var _control_updated_at_ms := 0


func _ready() -> void:
	add_to_group("pushable")


func _physics_process(delta: float) -> void:
	if Time.get_ticks_msec() - _control_updated_at_ms > 200:
		_drive_x = 0.0

	var target_velocity_x := _drive_x * online_target_speed
	var response := online_acceleration if absf(_drive_x) > 0.01 else online_drag
	_velocity.x = move_toward(_velocity.x, target_velocity_x, response * delta * online_target_speed)
	_velocity.y = minf(_velocity.y + ProjectSettings.get_setting("physics/2d/default_gravity") * gravity_scale * delta, max_fall_speed)

	var motion := _velocity * delta
	if motion.is_zero_approx():
		return

	if absf(motion.x) > 0.001:
		_carry_stacked_pushables(motion.x, {})

	var collision := move_and_collide(motion)
	if collision == null:
		return

	var normal := collision.get_normal()
	if absf(normal.x) > 0.01:
		_velocity.x = 0.0
	if normal.y < -0.01 or normal.y > 0.01:
		_velocity.y = 0.0


func set_online_authoritative(_enabled: bool) -> void:
	pass


func apply_server_push_control(drive_x: float) -> void:
	_drive_x = clampf(drive_x, -1.0, 1.0)
	_control_updated_at_ms = Time.get_ticks_msec()


func _carry_stacked_pushables(delta_x: float, moved_ids: Dictionary) -> void:
	moved_ids[get_instance_id()] = true
	for body in get_tree().get_nodes_in_group("pushable"):
		var other := body as Node2D
		if other == null or other == self:
			continue
		if moved_ids.has(other.get_instance_id()):
			continue
		if not _is_stacked_on_top(other):
			continue
		if other.has_method("_carry_with_support"):
			other._carry_with_support(delta_x, moved_ids)


func _carry_with_support(delta_x: float, moved_ids: Dictionary) -> void:
	if moved_ids.has(get_instance_id()):
		return

	_carry_stacked_pushables(delta_x, moved_ids)
	moved_ids[get_instance_id()] = true
	global_position.x += delta_x


func _is_stacked_on_top(other: Node2D) -> bool:
	var own_bounds := _get_world_rect()
	var other_bounds := _get_world_rect(other)
	if own_bounds.size == Vector2.ZERO or other_bounds.size == Vector2.ZERO:
		return false

	var vertical_gap := absf(other_bounds.end.y - own_bounds.position.y)
	if vertical_gap > stacked_contact_tolerance:
		return false

	var horizontal_overlap := minf(own_bounds.end.x, other_bounds.end.x) - maxf(own_bounds.position.x, other_bounds.position.x)
	return horizontal_overlap >= minf(own_bounds.size.x, other_bounds.size.x) - stacked_overlap_margin


func _get_world_rect(target: Node2D = self) -> Rect2:
	var collision_shape := target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape == null:
		return Rect2()

	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle == null:
		return Rect2()

	var size := rectangle.size
	var top_left := target.global_position + collision_shape.position - (size * 0.5)
	return Rect2(top_left, size)
