extends State
class_name PlayerSwim

@export var swim_speed := 110.0
@export var vertical_swim_speed := 95.0
@export var water_drag := 8.0
@export var passive_sink_speed := 18.0
@export var exit_water_grace_time := 0.08

var _exit_grace_timer := 0.0


func enter() -> void:
	_exit_grace_timer = 0.0
	controller.set_vertical_flip(false)
	controller.play_animation("swim_idle")
	controller.scale_velocity(0.45)


func exit() -> void:
	_exit_grace_timer = 0.0
	controller.set_vertical_flip(false)


func physics_update(delta: float) -> void:
	if not controller.is_in_water():
		_exit_grace_timer += delta
		if _exit_grace_timer < exit_water_grace_time:
			# Still within grace period — keep swimming, don't transition yet.
			controller.apply_gravity(delta)
			controller.move_and_push()
			return

		if controller.is_on_floor():
			var ground_direction: float = controller.horizontal_input()
			transitioned.emit(self, "run" if not is_zero_approx(ground_direction) else "idle")
		else:
			transitioned.emit(self, "fall")
		return
	else:
		_exit_grace_timer = 0.0

	var direction: float = controller.horizontal_input()
	var vertical_direction: float = 0.0
	if controller.jump_pressed():
		vertical_direction -= 1.0
	if controller.down_pressed():
		vertical_direction += 1.0

	var swim_input := Vector2(direction, vertical_direction)
	if swim_input.length() > 1.0:
		swim_input = swim_input.normalized()

	var speed_multiplier: float = controller.water_swim_speed_multiplier()
	var desired_velocity := Vector2(
		swim_input.x * swim_speed * speed_multiplier,
		swim_input.y * vertical_swim_speed * speed_multiplier
	)
	if is_zero_approx(swim_input.y):
		desired_velocity.y = passive_sink_speed

	desired_velocity += controller.water_current_velocity()
	controller.lerp_velocity(desired_velocity, clampf(water_drag * delta, 0.0, 1.0))

	_update_facing(direction)
	_update_animation(swim_input)
	controller.move_and_push()


func _update_facing(direction: float) -> void:
	controller.face_direction(direction)


func _update_animation(swim_input: Vector2) -> void:
	if swim_input.length() < 0.1:
		controller.set_vertical_flip(false)
		controller.play_animation("swim_idle")
	elif absf(swim_input.x) > 0.1 and absf(swim_input.y) > 0.1:
		controller.set_vertical_flip(false)
		controller.play_animation("swim_diagonal")
	elif swim_input.y < -0.1:
		controller.set_vertical_flip(false)
		controller.play_animation("swim_up")
	elif swim_input.y > 0.1:
		controller.set_vertical_flip(true)
		controller.play_animation("swim_down")
	else:
		controller.set_vertical_flip(false)
		controller.play_animation("swim")
