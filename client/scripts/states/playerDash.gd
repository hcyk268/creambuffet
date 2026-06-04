extends State
class_name PlayerDash

@export var dash_speed: float = 800.0
@export var dash_duration: float = 0.2

var timer: float = 0.0
var dash_direction: float = 1.0


func enter() -> void:
	controller.play_animation("dash")
	timer = dash_duration

	var input_dir := controller.horizontal_input()
	if not is_zero_approx(input_dir):
		dash_direction = input_dir
	else:
		dash_direction = controller.facing_direction()

	controller.set_vertical_velocity(0.0)
	controller.set_horizontal_velocity(dash_direction * dash_speed)


func physics_update(delta: float) -> void:
	if controller.is_in_water():
		transitioned.emit(self, "swim")
		return

	timer -= delta
	controller.move_and_push()

	if timer > 0.0:
		return

	if not controller.is_on_floor():
		transitioned.emit(self, "fall")
		return

	var direction := controller.horizontal_input()
	if not is_zero_approx(direction):
		transitioned.emit(self, "run")
	else:
		transitioned.emit(self, "idle")
