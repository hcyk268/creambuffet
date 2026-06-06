extends RefCounted
class_name PlayerWaterRuntime

var _owner: CharacterBody2D
var _update_bubble_effect: Callable
var _default_oxygen_drain_rate := 1.0
var _oxygen_recovery_rate := 3.0
var _water_jet_response := 14.0
var _water_jet_cross_drag := 2.5
var _water_jet_max_velocity := 760.0
var _water_jet_upward_lift_ratio := 0.16
var _water_jet_upward_max_lift_speed := 78.0
var _water_jet_upward_lift_stop_speed := 45.0
var _water_jet_upward_side_ratio := 0.72
var _water_jet_upward_side_min_speed := 180.0
var _water_jet_upward_side_max_speed := 280.0
var _water_jet_blocked_dot_epsilon := 0.01
var _water_zones: Array[Area2D] = []
var _oxygen_depleted_pending := false
var _water_jet_velocity := Vector2.ZERO
var _applied_water_jet_velocity := Vector2.ZERO
var _water_jet_side_sign := 1.0
var _water_exit_grace_remaining := 0.0

const WATER_EXIT_GRACE_SECONDS := 0.08


func setup(
	owner: CharacterBody2D,
	update_bubble_effect: Callable,
	default_oxygen_drain_rate: float,
	oxygen_recovery_rate: float,
	water_jet_response: float,
	water_jet_cross_drag: float,
	water_jet_max_velocity: float,
	water_jet_upward_lift_ratio: float,
	water_jet_upward_max_lift_speed: float,
	water_jet_upward_lift_stop_speed: float,
	water_jet_upward_side_ratio: float,
	water_jet_upward_side_min_speed: float,
	water_jet_upward_side_max_speed: float,
	water_jet_blocked_dot_epsilon: float
) -> void:
	_owner = owner
	_update_bubble_effect = update_bubble_effect
	_default_oxygen_drain_rate = default_oxygen_drain_rate
	_oxygen_recovery_rate = oxygen_recovery_rate
	_water_jet_response = water_jet_response
	_water_jet_cross_drag = water_jet_cross_drag
	_water_jet_max_velocity = water_jet_max_velocity
	_water_jet_upward_lift_ratio = water_jet_upward_lift_ratio
	_water_jet_upward_max_lift_speed = water_jet_upward_max_lift_speed
	_water_jet_upward_lift_stop_speed = water_jet_upward_lift_stop_speed
	_water_jet_upward_side_ratio = water_jet_upward_side_ratio
	_water_jet_upward_side_min_speed = water_jet_upward_side_min_speed
	_water_jet_upward_side_max_speed = water_jet_upward_side_max_speed
	_water_jet_blocked_dot_epsilon = water_jet_blocked_dot_epsilon


func set_water_jet_side_sign(side_sign: float) -> void:
	_water_jet_side_sign = -1.0 if side_sign < 0.0 else 1.0


func reset_after_respawn() -> bool:
	_water_jet_velocity = Vector2.ZERO
	_applied_water_jet_velocity = Vector2.ZERO
	_water_exit_grace_remaining = 0.0
	var was_in_water := not _water_zones.is_empty()
	_water_zones.clear()
	reset_oxygen()
	return was_in_water


func reset_oxygen() -> void:
	_oxygen_depleted_pending = false
	_set_owner_oxygen(_owner_max_oxygen())
	_emit_oxygen_changed()


func sync_oxygen_state(current: float, maximum: float) -> void:
	var safe_maximum := maxf(maximum, 0.0)
	var safe_current := clampf(current, 0.0, safe_maximum)
	_set_owner_max_oxygen(safe_maximum)
	_set_owner_oxygen(safe_current)
	_oxygen_depleted_pending = safe_current <= 0.0


func enter_water_zone(zone: Area2D) -> void:
	if zone == null:
		return

	_prune_water_zones()
	var was_in_water := is_in_water()
	if not _water_zones.has(zone):
		_water_zones.append(zone)

	if not was_in_water and is_in_water():
		_emit_water_state_changed(true)
		_refresh_bubble_effect()


func exit_water_zone(zone: Area2D) -> void:
	if zone == null:
		return

	var was_in_water := not _water_zones.is_empty()
	_water_zones.erase(zone)
	_prune_water_zones()

	if was_in_water and _water_zones.is_empty():
		_water_exit_grace_remaining = WATER_EXIT_GRACE_SECONDS


func is_in_water() -> bool:
	_prune_water_zones()
	if not _water_zones.is_empty():
		return true
	return _water_exit_grace_remaining > 0.0


func get_water_current_velocity() -> Vector2:
	_prune_water_zones()
	var current := Vector2.ZERO
	for zone in _water_zones:
		var raw_current = zone.get("current_velocity")
		if typeof(raw_current) == TYPE_VECTOR2:
			current += raw_current
	return current


func get_water_swim_speed_multiplier() -> float:
	_prune_water_zones()
	var multiplier := 1.0
	for zone in _water_zones:
		var raw_multiplier = zone.get("swim_speed_multiplier")
		if typeof(raw_multiplier) == TYPE_FLOAT or typeof(raw_multiplier) == TYPE_INT:
			multiplier *= float(raw_multiplier)
	return maxf(multiplier, 0.05)


func get_water_oxygen_drain_rate() -> float:
	_prune_water_zones()
	var rate := 0.0
	for zone in _water_zones:
		var raw_rate = zone.get("oxygen_drain_rate")
		if typeof(raw_rate) == TYPE_FLOAT or typeof(raw_rate) == TYPE_INT:
			rate += float(raw_rate)
		else:
			rate += _default_oxygen_drain_rate
	return maxf(rate, 0.0)


func add_oxygen(amount: float) -> void:
	if _owner_max_oxygen() <= 0.0:
		return

	var previous_oxygen := _owner_oxygen()
	var next_oxygen := clampf(previous_oxygen + amount, 0.0, _owner_max_oxygen())
	if next_oxygen > 0.0:
		_oxygen_depleted_pending = false
	_set_owner_oxygen(next_oxygen)
	if not is_equal_approx(previous_oxygen, next_oxygen):
		_emit_oxygen_changed()


func apply_water_jet_velocity(jet_velocity: Vector2, is_remote_player: bool) -> void:
	if is_remote_player:
		return

	_water_jet_velocity += jet_velocity
	_water_jet_velocity = _water_jet_velocity.limit_length(_water_jet_max_velocity)


func consume_water_jet_velocity() -> Vector2:
	var result := _water_jet_velocity
	_water_jet_velocity = Vector2.ZERO
	return result


func prepare_move(delta: float) -> void:
	_applied_water_jet_velocity = Vector2.ZERO
	_apply_pending_water_jet(delta)


func finish_move() -> void:
	_remove_blocked_water_jet_velocity()


func update_oxygen(delta: float, is_remote_player: bool, is_eliminated: bool, online_session: bool) -> void:
	_update_water_exit_grace(delta)

	if is_remote_player or is_eliminated or _owner_max_oxygen() <= 0.0:
		return

	var previous_oxygen := _owner_oxygen()
	var next_oxygen := previous_oxygen
	if is_in_water():
		next_oxygen = maxf(previous_oxygen - get_water_oxygen_drain_rate() * delta, 0.0)
		if previous_oxygen > 0.0 and next_oxygen <= 0.0:
			if online_session:
				if not _oxygen_depleted_pending:
					_oxygen_depleted_pending = true
					_emit_oxygen_depleted()
			else:
				_set_owner_oxygen(next_oxygen)
				if not is_equal_approx(previous_oxygen, next_oxygen):
					_emit_oxygen_changed()
				if _owner != null and _owner.has_method("die"):
					_owner.call("die")
				return
	else:
		next_oxygen = minf(previous_oxygen + _oxygen_recovery_rate * delta, _owner_max_oxygen())
		if next_oxygen > 0.0:
			_oxygen_depleted_pending = false

	_set_owner_oxygen(next_oxygen)
	if not is_equal_approx(previous_oxygen, next_oxygen):
		_emit_oxygen_changed()


func prune_water_zones() -> void:
	_prune_water_zones()


func _update_water_exit_grace(delta: float) -> void:
	if _water_exit_grace_remaining <= 0.0:
		return

	if not _water_zones.is_empty():
		# Re-entered water during grace — cancel exit.
		_water_exit_grace_remaining = 0.0
		return

	_water_exit_grace_remaining -= delta
	if _water_exit_grace_remaining <= 0.0:
		_water_exit_grace_remaining = 0.0
		_emit_water_state_changed(false)
		_refresh_bubble_effect()


func _apply_pending_water_jet(delta: float) -> void:
	if _owner == null or _water_jet_velocity.is_zero_approx():
		return

	var jet_velocity: Vector2 = consume_water_jet_velocity()
	jet_velocity = _remove_blocked_components_from_water_jet(jet_velocity)
	jet_velocity = _shape_water_jet_velocity(jet_velocity)
	if jet_velocity.is_zero_approx():
		return

	_applied_water_jet_velocity = jet_velocity
	var jet_direction: Vector2 = jet_velocity.normalized()
	var current_velocity: Vector2 = _owner.velocity
	var target_speed: float = minf(jet_velocity.length(), _water_jet_max_velocity)
	var current_along: float = current_velocity.dot(jet_direction)
	var next_along: float = lerpf(
		current_along,
		maxf(current_along, target_speed),
		clampf(_water_jet_response * delta, 0.0, 1.0)
	)
	var lateral_velocity: Vector2 = current_velocity - jet_direction * current_along
	lateral_velocity = lateral_velocity.lerp(
		Vector2.ZERO,
		clampf(_water_jet_cross_drag * delta, 0.0, 1.0)
	)
	_owner.velocity = lateral_velocity + jet_direction * next_along


func _shape_water_jet_velocity(jet_velocity: Vector2) -> Vector2:
	if _owner == null or jet_velocity.is_zero_approx():
		return Vector2.ZERO

	var upward_amount := maxf(-jet_velocity.y, 0.0)
	var horizontal_amount := absf(jet_velocity.x)
	if upward_amount <= horizontal_amount * 0.55:
		return jet_velocity

	var shaped := jet_velocity
	if _owner.velocity.y < -_water_jet_upward_lift_stop_speed:
		shaped.y = 0.0
	else:
		shaped.y = -minf(upward_amount * _water_jet_upward_lift_ratio, _water_jet_upward_max_lift_speed)

	var side_sign := signf(jet_velocity.x)
	if is_zero_approx(side_sign):
		side_sign = _preferred_water_jet_lateral_sign()

	var side_speed := clampf(
		maxf(maxf(horizontal_amount, upward_amount * _water_jet_upward_side_ratio), _water_jet_upward_side_min_speed),
		0.0,
		_water_jet_upward_side_max_speed
	)
	shaped.x = side_sign * side_speed
	return shaped


func _preferred_water_jet_lateral_sign() -> float:
	if _owner != null and not is_zero_approx(_owner.velocity.x):
		_water_jet_side_sign = signf(_owner.velocity.x)
	return _water_jet_side_sign


func _remove_blocked_components_from_water_jet(jet_velocity: Vector2) -> Vector2:
	if _owner == null or jet_velocity.is_zero_approx():
		return Vector2.ZERO

	var result := jet_velocity
	for index in range(_owner.get_slide_collision_count()):
		var collision: KinematicCollision2D = _owner.get_slide_collision(index)
		if collision == null:
			continue

		var normal := collision.get_normal()
		if normal.is_zero_approx():
			continue

		var blocked_amount := result.dot(normal)
		if blocked_amount < -_water_jet_blocked_dot_epsilon:
			result -= normal * blocked_amount

	return result


func _remove_blocked_water_jet_velocity() -> void:
	if _owner == null or _applied_water_jet_velocity.is_zero_approx():
		return

	for index in range(_owner.get_slide_collision_count()):
		var collision: KinematicCollision2D = _owner.get_slide_collision(index)
		if collision == null:
			continue

		var normal := collision.get_normal()
		if normal.is_zero_approx():
			continue

		if _applied_water_jet_velocity.dot(normal) >= -_water_jet_blocked_dot_epsilon:
			continue

		var velocity_into_surface: float = _owner.velocity.dot(normal)
		if velocity_into_surface < 0.0:
			_owner.velocity -= normal * velocity_into_surface


func _prune_water_zones() -> void:
	for index in range(_water_zones.size() - 1, -1, -1):
		if not is_instance_valid(_water_zones[index]):
			_water_zones.remove_at(index)


func _owner_oxygen() -> float:
	return float(_owner.get("oxygen")) if _owner != null else 0.0


func _owner_max_oxygen() -> float:
	return float(_owner.get("max_oxygen")) if _owner != null else 0.0


func _set_owner_oxygen(value: float) -> void:
	if _owner != null:
		_owner.set("oxygen", value)


func _set_owner_max_oxygen(value: float) -> void:
	if _owner != null:
		_owner.set("max_oxygen", value)


func _emit_water_state_changed(in_water: bool) -> void:
	if _owner != null:
		_owner.emit_signal("water_state_changed", in_water)


func _emit_oxygen_changed() -> void:
	if _owner != null:
		_owner.emit_signal("oxygen_changed", _owner_oxygen(), _owner_max_oxygen())


func _emit_oxygen_depleted() -> void:
	if _owner != null:
		_owner.emit_signal("oxygen_depleted")


func _refresh_bubble_effect() -> void:
	if _update_bubble_effect.is_valid():
		_update_bubble_effect.call()
