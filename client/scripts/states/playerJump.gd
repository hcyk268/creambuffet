extends State
class_name PlayerJump


func enter() -> void:
	controller.play_animation("air")
	controller.play_jump_sfx()
	controller.set_vertical_velocity(controller.jump_velocity())


func physics_update(delta: float) -> void:
	if controller.is_in_water():
		transitioned.emit(self, "swim")
		return

	controller.apply_gravity(delta)

	var direction := controller.horizontal_input()
	controller.set_horizontal_velocity(direction * controller.speed())
	if not is_zero_approx(direction):
		controller.face_direction(direction)
	controller.move_and_push()

	if controller.vertical_velocity() > 0.0:
		transitioned.emit(self, "fall")

	if controller.is_on_floor() and controller.vertical_velocity() >= 0.0:
		if not is_zero_approx(direction):
			transitioned.emit(self, "run")
		else:
			transitioned.emit(self, "idle")
		return

	if controller.dash_just_pressed():
		transitioned.emit(self, "dash")
