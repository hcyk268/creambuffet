extends State
class_name PlayerSwim

@export var swim_speed := 110.0
@export var vertical_swim_speed := 95.0
@export var water_drag := 8.0
@export var passive_sink_speed := 18.0


func enter() -> void:
	_set_vertical_flip(false)
	parent.play_player_animation("swim_idle")
	parent.velocity *= 0.45


func exit() -> void:
	_set_vertical_flip(false)


func physics_update(delta: float) -> void:
	if not parent.is_in_water():
		if parent.is_on_floor():
			var ground_direction: float = Input.get_axis("left", "right")
			Transitioned.emit(self, "run" if ground_direction != 0 else "idle")
		else:
			Transitioned.emit(self, "fall")
		return

	var direction: float = Input.get_axis("left", "right")
	var vertical_direction: float = 0.0
	if Input.is_action_pressed("jump"):
		vertical_direction -= 1.0
	if InputMap.has_action("down") and Input.is_action_pressed("down"):
		vertical_direction += 1.0

	var swim_input: Vector2 = Vector2(direction, vertical_direction)
	if swim_input.length() > 1.0:
		swim_input = swim_input.normalized()

	var speed_multiplier: float = float(parent.get_water_swim_speed_multiplier())
	var desired_velocity: Vector2 = Vector2(
		swim_input.x * swim_speed * speed_multiplier,
		swim_input.y * vertical_swim_speed * speed_multiplier
	)
	if is_zero_approx(swim_input.y):
		desired_velocity.y = passive_sink_speed

	var water_current: Vector2 = parent.get_water_current_velocity()
	desired_velocity += water_current
	parent.velocity = parent.velocity.lerp(desired_velocity, clampf(water_drag * delta, 0.0, 1.0))

	_update_facing(direction)
	_update_animation(swim_input)
	parent.move_and_push()


func _update_facing(direction: float) -> void:
	if is_zero_approx(direction):
		return

	var sprite: Sprite2D = parent.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.flip_h = direction > 0.0


func _update_animation(swim_input: Vector2) -> void:
	if swim_input.length() < 0.1:
		_set_vertical_flip(false)
		parent.play_player_animation("swim_idle")
	elif absf(swim_input.x) > 0.1 and absf(swim_input.y) > 0.1:
		_set_vertical_flip(false)
		parent.play_player_animation("swim_diagonal")
	elif swim_input.y < -0.1:
		_set_vertical_flip(false)
		parent.play_player_animation("swim_up")
	elif swim_input.y > 0.1:
		_set_vertical_flip(true)
		parent.play_player_animation("swim_down")
	else:
		_set_vertical_flip(false)
		parent.play_player_animation("swim")


func _set_vertical_flip(flipped: bool) -> void:
	var sprite: Sprite2D = parent.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.flip_v = flipped
