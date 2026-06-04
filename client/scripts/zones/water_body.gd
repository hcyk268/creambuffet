extends TileMapLayer
class_name WaterBody

const WATER_VISUAL_SHADER := preload("res://shaders/water_body.gdshader")
const DEFAULT_FLOW_DIRECTION := Vector2(1.0, 0.18)

@export var water_area_path: NodePath = ^"WaterArea"
@export var auto_build_collision_from_tiles := true
@export var zone_id := ""
@export var oxygen_drain_rate := 1.0
@export var swim_speed_multiplier := 1.0
@export var current_velocity := Vector2.ZERO
@export var use_visual_shader := true
@export_range(0.0, 4.0, 0.05) var shader_scroll_speed := 0.35
@export_range(0.0, 0.02, 0.0005) var shader_current_speed_boost := 0.004
@export_range(0.0, 4.0, 0.05) var shader_distortion_px := 0.75
@export_range(0.0, 1.0, 0.01) var shader_shimmer_strength := 0.14
@export_range(0.0, 1.0, 0.01) var shader_foam_strength := 0.4
@export_range(0.0, 1.0, 0.01) var shader_depth_darkening := 0.18
@export_range(0.0, 32.0, 0.5) var shader_surface_band_px := 18.0
@export_range(0.0, 8.0, 0.1) var shader_wave_height_px := 2.2
@export var animate_tiles := true
@export_range(0.0, 24.0, 0.1) var animation_fps := 4.0
@export var surface_animation_block := Rect2i(0, 0, 8, 2)
@export var middle_animation_block := Rect2i(0, 2, 8, 2)
@export var bottom_animation_block := Rect2i(0, 4, 4, 4)

var _base_tiles: Dictionary = {}
var _animation_time := 0.0


func _ready() -> void:
	_cache_base_tiles()
	_apply_zone_settings()
	_configure_visual_shader()
	if auto_build_collision_from_tiles:
		rebuild_water_area()
	_update_tile_animation(true)
	set_process(animate_tiles and animation_fps > 0.0)


func _process(delta: float) -> void:
	if not animate_tiles or animation_fps <= 0.0:
		return

	_animation_time += delta
	_update_tile_animation()


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

	_update_visual_shader_params()


func _apply_zone_settings() -> void:
	var water_area := get_node_or_null(water_area_path) as Area2D
	if water_area == null:
		return

	water_area.set("zone_id", zone_id)
	water_area.set("oxygen_drain_rate", oxygen_drain_rate)
	water_area.set("swim_speed_multiplier", swim_speed_multiplier)
	water_area.set("current_velocity", current_velocity)
	_update_visual_shader_params()


func _cache_base_tiles() -> void:
	_base_tiles.clear()

	for cell in get_used_cells():
		var source_id := get_cell_source_id(cell)
		var atlas_coords := get_cell_atlas_coords(cell)
		_base_tiles[cell] = {
			"source_id": source_id,
			"atlas_coords": atlas_coords,
			"alternative_tile": get_cell_alternative_tile(cell),
			"animation_tiles": _get_animation_tiles_for(source_id, atlas_coords)
		}

	_update_visual_shader_params()


func _update_tile_animation(force := false) -> void:
	if _base_tiles.is_empty():
		return

	var animation_frame := int(floor(_animation_time * animation_fps))
	for cell in _base_tiles.keys():
		var base_tile: Dictionary = _base_tiles[cell]
		var animation_tiles: Array = base_tile.get("animation_tiles", [])
		if animation_tiles.size() <= 1:
			continue

		var animated_atlas_coords: Vector2i = animation_tiles[_get_animation_tile_index(cell, animation_frame, animation_tiles.size())]
		if not force and get_cell_atlas_coords(cell) == animated_atlas_coords:
			continue

		set_cell(
			cell,
			int(base_tile.get("source_id", -1)),
			animated_atlas_coords,
			int(base_tile.get("alternative_tile", 0))
		)


func _get_animation_tiles_for(source_id: int, atlas_coords: Vector2i) -> Array[Vector2i]:
	var block := _get_animation_block_for(atlas_coords)
	if block.size == Vector2i.ZERO:
		return _single_animation_tile(atlas_coords)

	var source: TileSetAtlasSource = null
	if tile_set != null:
		source = tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null:
		return _single_animation_tile(atlas_coords)

	var animation_tiles: Array[Vector2i] = []
	for tile_index in range(source.get_tiles_count()):
		var tile_coords := source.get_tile_id(tile_index)
		if block.has_point(tile_coords):
			animation_tiles.append(tile_coords)

	if animation_tiles.is_empty():
		animation_tiles.append(atlas_coords)
	return animation_tiles


func _single_animation_tile(atlas_coords: Vector2i) -> Array[Vector2i]:
	var animation_tiles: Array[Vector2i] = []
	animation_tiles.append(atlas_coords)
	return animation_tiles


func _get_animation_block_for(atlas_coords: Vector2i) -> Rect2i:
	for block in [surface_animation_block, middle_animation_block, bottom_animation_block]:
		if block.has_point(atlas_coords):
			return block
	return Rect2i()


func _get_animation_tile_index(cell: Vector2i, animation_frame: int, tile_count: int) -> int:
	var value := cell.x * 73856093
	value = value ^ (cell.y * 19349663)
	value = value ^ (animation_frame * 83492791)
	return posmod(value, tile_count)


func _clear_generated_shapes(water_area: Area2D) -> void:
	for child in water_area.get_children():
		if child is CollisionShape2D and bool(child.get_meta("generated_by_water_body", false)):
			water_area.remove_child(child)
			child.queue_free()


func _configure_visual_shader() -> void:
	if not use_visual_shader:
		return

	var shader_material: ShaderMaterial = null
	if material is ShaderMaterial and (material as ShaderMaterial).shader == WATER_VISUAL_SHADER:
		shader_material = material as ShaderMaterial
	elif material == null:
		shader_material = ShaderMaterial.new()
		shader_material.shader = WATER_VISUAL_SHADER
		material = shader_material
	else:
		return

	_update_visual_shader_params(shader_material)


func _update_visual_shader_params(shader_material: ShaderMaterial = null) -> void:
	if not use_visual_shader:
		return

	if shader_material == null:
		if not (material is ShaderMaterial):
			return
		shader_material = material as ShaderMaterial
		if shader_material.shader != WATER_VISUAL_SHADER:
			return

	var bounds := _get_local_water_bounds()
	var tile_size := _get_tile_size()
	var flow_direction := DEFAULT_FLOW_DIRECTION
	var flow_speed := shader_scroll_speed
	if not current_velocity.is_zero_approx():
		flow_direction = current_velocity.normalized()
		flow_speed += current_velocity.length() * shader_current_speed_boost

	shader_material.set_shader_parameter("bounds_origin", bounds.position)
	shader_material.set_shader_parameter("bounds_size", bounds.size)
	shader_material.set_shader_parameter("tile_pixel_size", tile_size)
	shader_material.set_shader_parameter("flow_direction", flow_direction)
	shader_material.set_shader_parameter("flow_speed", flow_speed)
	shader_material.set_shader_parameter("distortion_px", shader_distortion_px)
	shader_material.set_shader_parameter("shimmer_strength", shader_shimmer_strength)
	shader_material.set_shader_parameter("foam_strength", shader_foam_strength)
	shader_material.set_shader_parameter("depth_darkening", shader_depth_darkening)
	shader_material.set_shader_parameter("surface_band_px", shader_surface_band_px)
	shader_material.set_shader_parameter("wave_height_px", shader_wave_height_px)


func _get_local_water_bounds() -> Rect2:
	var cells := get_used_cells()
	var tile_size := _get_tile_size()
	if cells.is_empty():
		return Rect2(Vector2.ZERO, tile_size)

	var half_tile := tile_size * 0.5
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for cell in cells:
		var cell_center := map_to_local(cell)
		var cell_min := cell_center - half_tile
		var cell_max := cell_center + half_tile
		min_point.x = minf(min_point.x, cell_min.x)
		min_point.y = minf(min_point.y, cell_min.y)
		max_point.x = maxf(max_point.x, cell_max.x)
		max_point.y = maxf(max_point.y, cell_max.y)

	return Rect2(min_point, max_point - min_point)


func _get_tile_size() -> Vector2:
	if tile_set != null:
		return Vector2(tile_set.tile_size)
	return Vector2(64, 64)
