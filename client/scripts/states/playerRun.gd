extends State
class_name PlayerRun


func enter() -> void:
	controller.play_animation("run")


func physics_update(delta: float) -> void:
	if controller.is_in_water():
		transitioned.emit(self, "swim")
		return

	if not controller.is_on_floor():
		controller.apply_gravity(delta)

	var direction := controller.horizontal_input()
	if not is_zero_approx(direction):
		controller.set_horizontal_velocity(direction * controller.speed())
		controller.face_direction(direction)
	else:
		controller.set_horizontal_velocity(0.0)

	controller.move_and_push()

	if controller.jump_just_pressed():
		transitioned.emit(self, "jump")
		return

	if not controller.is_on_floor():
		transitioned.emit(self, "fall")
		return

	if is_zero_approx(direction):
		transitioned.emit(self, "idle")

	if controller.dash_just_pressed():
		transitioned.emit(self, "dash")
