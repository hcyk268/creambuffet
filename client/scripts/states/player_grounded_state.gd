extends State
class_name PlayerGroundedState


func transition_to_swim_if_in_water() -> bool:
	if controller.is_in_water():
		transitioned.emit(self, "swim")
		return true
	return false


func transition_to_fall_if_airborne() -> bool:
	if not controller.is_on_floor():
		transitioned.emit(self, "fall")
		return true
	return false


func apply_ground_gravity(delta: float) -> void:
	if not controller.is_on_floor():
		controller.apply_gravity(delta)
	else:
		controller.set_vertical_velocity(0.0)
