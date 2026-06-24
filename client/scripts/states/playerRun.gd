extends PlayerGroundedState
class_name PlayerRun


func enter() -> void:
	controller.play_animation("run")


func physics_update(delta: float) -> void:
	if transition_to_swim_if_in_water():
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

	if transition_to_fall_if_airborne():
		return

	if is_zero_approx(direction):
		transitioned.emit(self, "idle")
		return

	if controller.dash_just_pressed():
		transitioned.emit(self, "dash")
