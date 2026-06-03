extends Area2D
class_name WaterZone

signal water_body_entered(body: Node, zone: WaterZone)
signal water_body_exited(body: Node, zone: WaterZone)

@export var zone_id := ""
@export var oxygen_drain_rate := 1.0
@export var swim_speed_multiplier := 1.0
@export var current_velocity := Vector2.ZERO


func _ready() -> void:
	add_to_group("water_zone")

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body.has_method("enter_water_zone"):
		body.enter_water_zone(self)
	elif body.has_method("enter_water"):
		body.enter_water(self)

	water_body_entered.emit(body, self)


func _on_body_exited(body: Node) -> void:
	if body.has_method("exit_water_zone"):
		body.exit_water_zone(self)
	elif body.has_method("exit_water"):
		body.exit_water(self)

	water_body_exited.emit(body, self)
