extends PlayerAirborneState
class_name PlayerJump


func enter() -> void:
	controller.play_animation("air")
	controller.set_vertical_velocity(controller.jump_velocity())


func physics_update(delta: float) -> void:
	if transition_to_swim_if_in_water():
		return

	apply_airborne_movement(delta)

	if controller.vertical_velocity() > 0.0:
		transitioned.emit(self, "fall")
		return

	if controller.is_on_floor() and controller.vertical_velocity() >= 0.0:
		transition_to_grounded_from_air()
