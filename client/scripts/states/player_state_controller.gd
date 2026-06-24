extends RefCounted
class_name PlayerStateController

var _player: CharacterBody2D
var _visual: PlayerVisual
var _movement: PlayerMovement
var _water: PlayerWaterComponent


func _init(player: CharacterBody2D) -> void:
	_player = player
	if player != null and player.has_node("PlayerSodaHost"):
		var host: Node = player.get_node("PlayerSodaHost")
		_visual = host.get_node_or_null("PlayerVisual") as PlayerVisual
		_movement = host.get_node_or_null("PlayerMovement") as PlayerMovement
		_water = host.get_node_or_null("PlayerWater") as PlayerWaterComponent


func is_ready() -> bool:
	return is_instance_valid(_player)


func is_in_water() -> bool:
	if _water != null:
		return _water.is_in_water()
	return is_ready() and _player.has_method("is_in_water") and bool(_player.is_in_water())


func is_on_floor() -> bool:
	return is_ready() and _player.is_on_floor()


func gravity() -> Vector2:
	return _player.get_gravity() if is_ready() else Vector2.ZERO


func apply_gravity(delta: float) -> void:
	set_velocity(get_velocity() + gravity() * delta)


func move_and_push() -> void:
	if _movement != null:
		_movement.move_and_push()
	elif is_ready() and _player.has_method("move_and_push"):
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
	if _movement != null:
		return _movement.get_speed()
	return float(_player.SPEED) if is_ready() else 0.0


func jump_velocity() -> float:
	if _movement != null:
		return _movement.get_jump_velocity()
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
	if _visual != null:
		_visual.play_animation(animation)
	elif is_ready() and _player.has_method("play_player_animation"):
		_player.play_player_animation(animation)


func face_direction(direction: float) -> void:
	if _visual != null:
		_visual.set_facing_direction(direction)
	elif is_ready() and _player.has_method("set_facing_direction"):
		_player.set_facing_direction(direction)


func facing_direction() -> float:
	if _visual != null:
		return _visual.get_facing_direction()
	if is_ready() and _player.has_method("get_facing_direction"):
		return float(_player.get_facing_direction())
	return 1.0


func set_vertical_flip(flipped: bool) -> void:
	if _visual != null:
		_visual.set_vertical_flip(flipped)
	elif is_ready() and _player.has_method("set_sprite_vertical_flip"):
		_player.set_sprite_vertical_flip(flipped)


func water_swim_speed_multiplier() -> float:
	if _water != null:
		return _water.get_water_swim_speed_multiplier()
	if not is_ready() or not _player.has_method("get_water_swim_speed_multiplier"):
		return 1.0
	return float(_player.get_water_swim_speed_multiplier())


func water_current_velocity() -> Vector2:
	if _water != null:
		return _water.get_water_current_velocity()
	if not is_ready() or not _player.has_method("get_water_current_velocity"):
		return Vector2.ZERO
	return _player.get_water_current_velocity()
