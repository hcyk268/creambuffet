extends State
class_name PlayerAirborneState


func transition_to_swim_if_in_water() -> bool:
	if controller.is_in_water():
		transitioned.emit(self, "swim")
		return true
	return false


func apply_airborne_movement(delta: float) -> void:
	controller.apply_gravity(delta)

	var direction := controller.horizontal_input()
	controller.set_horizontal_velocity(direction * controller.speed())
	if not is_zero_approx(direction):
		controller.face_direction(direction)
	controller.move_and_push()


func transition_to_grounded_from_air() -> void:
	var direction := controller.horizontal_input()
	if not is_zero_approx(direction):
		transitioned.emit(self, "run")
	else:
		transitioned.emit(self, "idle")
