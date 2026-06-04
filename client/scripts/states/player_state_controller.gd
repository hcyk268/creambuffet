extends RefCounted
class_name PlayerStateController

var _player: CharacterBody2D


func _init(player: CharacterBody2D) -> void:
	_player = player


func is_ready() -> bool:
	return is_instance_valid(_player)


func is_in_water() -> bool:
	return is_ready() and _player.has_method("is_in_water") and bool(_player.is_in_water())


func is_on_floor() -> bool:
	return is_ready() and _player.is_on_floor()


func gravity() -> Vector2:
	return _player.get_gravity() if is_ready() else Vector2.ZERO


func apply_gravity(delta: float) -> void:
	set_velocity(get_velocity() + gravity() * delta)


func move_and_push() -> void:
	if is_ready() and _player.has_method("move_and_push"):
		_player.move_and_push()


func get_velocity() -> Vector2:
	return _player.velocity if is_ready() else Vector2.ZERO


func set_velocity(next_velocity: Vector2) -> void:
	if is_ready():
		_player.velocity = next_velocity


func set_horizontal_velocity(value: float) -> void:
	var next_velocity := get_velocity()
	next_velocity.x = value
	set_velocity(next_velocity)


func set_vertical_velocity(value: float) -> void:
	var next_velocity := get_velocity()
	next_velocity.y = value
	set_velocity(next_velocity)


func vertical_velocity() -> float:
	return get_velocity().y


func scale_velocity(scale: float) -> void:
	set_velocity(get_velocity() * scale)


func lerp_velocity(target: Vector2, weight: float) -> void:
	set_velocity(get_velocity().lerp(target, weight))


func speed() -> float:
	return float(_player.SPEED) if is_ready() else 0.0


func jump_velocity() -> float:
	return float(_player.JUMP_VELOCITY) if is_ready() else 0.0


func horizontal_input() -> float:
	return Input.get_axis("left", "right")


func jump_pressed() -> bool:
	return Input.is_action_pressed("jump")


func jump_just_pressed() -> bool:
	return Input.is_action_just_pressed("jump")


func dash_just_pressed() -> bool:
	return Input.is_action_just_pressed("dash")


func down_pressed() -> bool:
	return InputMap.has_action("down") and Input.is_action_pressed("down")


func play_animation(animation: String) -> void:
	if is_ready() and _player.has_method("play_player_animation"):
		_player.play_player_animation(animation)


func face_direction(direction: float) -> void:
	if is_ready() and _player.has_method("set_facing_direction"):
		_player.set_facing_direction(direction)


func facing_direction() -> float:
	if is_ready() and _player.has_method("get_facing_direction"):
		return float(_player.get_facing_direction())
	return 1.0


func set_vertical_flip(flipped: bool) -> void:
	if is_ready() and _player.has_method("set_sprite_vertical_flip"):
		_player.set_sprite_vertical_flip(flipped)


func water_swim_speed_multiplier() -> float:
	if not is_ready() or not _player.has_method("get_water_swim_speed_multiplier"):
		return 1.0
	return float(_player.get_water_swim_speed_multiplier())


func water_current_velocity() -> Vector2:
	if not is_ready() or not _player.has_method("get_water_current_velocity"):
		return Vector2.ZERO
	return _player.get_water_current_velocity()
