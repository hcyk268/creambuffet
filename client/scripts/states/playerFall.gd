extends PlayerAirborneState
class_name PlayerFall


func enter() -> void:
	controller.play_animation("fall")


func physics_update(delta: float) -> void:
	if transition_to_swim_if_in_water():
		return

	apply_airborne_movement(delta)

	if controller.is_on_floor():
		transition_to_grounded_from_air()
		return

	if controller.dash_just_pressed():
		transitioned.emit(self, "dash")
