extends Area2D
class_name WaterZone

signal water_body_entered(body: Node, zone: WaterZone)
signal water_body_exited(body: Node, zone: WaterZone)

const PlayerCapabilities = preload("res://scripts/player/player_capabilities.gd")

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
	PlayerCapabilities.enter_water_zone(body, self)
	water_body_entered.emit(body, self)


func _on_body_exited(body: Node) -> void:
	PlayerCapabilities.exit_water_zone(body, self)
	water_body_exited.emit(body, self)
