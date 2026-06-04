extends State
class_name PlayerIdle


func enter() -> void:
	controller.play_animation("idle")
	controller.set_horizontal_velocity(0.0)


func physics_update(delta: float) -> void:
	if controller.is_in_water():
		transitioned.emit(self, "swim")
		return

	if not controller.is_on_floor():
		controller.apply_gravity(delta)
	else:
		controller.set_vertical_velocity(0.0)

	controller.set_horizontal_velocity(0.0)
	controller.move_and_push()

	if not controller.is_on_floor():
		transitioned.emit(self, "fall")

	if controller.jump_just_pressed():
		transitioned.emit(self, "jump")
		return

	var direction := controller.horizontal_input()
	if not is_zero_approx(direction):
		transitioned.emit(self, "run")

	if controller.dash_just_pressed():
		transitioned.emit(self, "dash")
