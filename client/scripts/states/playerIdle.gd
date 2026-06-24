extends PlayerGroundedState
class_name PlayerIdle


func enter() -> void:
	controller.play_animation("idle")
	controller.set_horizontal_velocity(0.0)


func physics_update(delta: float) -> void:
	if transition_to_swim_if_in_water():
		return

	apply_ground_gravity(delta)
	controller.set_horizontal_velocity(0.0)
	controller.move_and_push()

	if transition_to_fall_if_airborne():
		return

	if controller.jump_just_pressed():
		transitioned.emit(self, "jump")
		return

	var direction := controller.horizontal_input()
	if not is_zero_approx(direction):
		transitioned.emit(self, "run")
		return

	if controller.dash_just_pressed():
		transitioned.emit(self, "dash")
