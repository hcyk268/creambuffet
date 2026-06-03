extends TileMapLayer
class_name WaterBody

@export var water_area_path: NodePath = ^"WaterArea"
@export var auto_build_collision_from_tiles := true
@export var zone_id := ""
@export var oxygen_drain_rate := 1.0
@export var swim_speed_multiplier := 1.0
@export var current_velocity := Vector2.ZERO


func _ready() -> void:
	_apply_zone_settings()
	if auto_build_collision_from_tiles:
		rebuild_water_area()


func rebuild_water_area() -> void:
	var water_area := get_node_or_null(water_area_path) as Area2D
	if water_area == null:
		return

	_clear_generated_shapes(water_area)

	var tile_size := Vector2(64, 64)
	if tile_set != null:
		tile_size = Vector2(tile_set.tile_size.x, tile_set.tile_size.y)

	for cell in get_used_cells():
		var shape := RectangleShape2D.new()
		shape.size = tile_size

		var collision := CollisionShape2D.new()
		collision.name = "GeneratedWaterCell"
		collision.shape = shape
		collision.position = map_to_local(cell)
		collision.set_meta("generated_by_water_body", true)
		water_area.add_child(collision)


func _apply_zone_settings() -> void:
	var water_area := get_node_or_null(water_area_path) as Area2D
	if water_area == null:
		return

	water_area.set("zone_id", zone_id)
	water_area.set("oxygen_drain_rate", oxygen_drain_rate)
	water_area.set("swim_speed_multiplier", swim_speed_multiplier)
	water_area.set("current_velocity", current_velocity)


func _clear_generated_shapes(water_area: Area2D) -> void:
	for child in water_area.get_children():
		if child is CollisionShape2D and bool(child.get_meta("generated_by_water_body", false)):
			water_area.remove_child(child)
			child.queue_free()
