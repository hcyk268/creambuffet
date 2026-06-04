extends State
class_name PlayerFall


func enter() -> void:
	controller.play_animation("fall")


func physics_update(delta: float) -> void:
	if controller.is_in_water():
		transitioned.emit(self, "swim")
		return

	controller.apply_gravity(delta)

	var direction := controller.horizontal_input()
	controller.set_horizontal_velocity(direction * controller.speed())
	controller.move_and_push()

	if not is_zero_approx(direction):
		controller.face_direction(direction)

	if controller.is_on_floor():
		if not is_zero_approx(direction):
			transitioned.emit(self, "run")
		else:
			transitioned.emit(self, "idle")

	if controller.dash_just_pressed():
		transitioned.emit(self, "dash")
