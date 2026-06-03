extends Area2D
class_name WaterJet

signal active_changed(active: bool)

const WATER_JET_TEXTURE := preload("res://assets/sprites/waterjet.png")
const FRAME_SIZE := Vector2(246, 276)

enum VisualPreset {
	LONG_COLUMN,
	VERTICAL_BURST,
	HORIZONTAL_BURST,
	DIAGONAL_DOWN_BURST,
	DIAGONAL_UP_BURST,
	AUTO_BY_DIRECTION,
	RANDOM_BURST,
}

@export var active := true:
	set(value):
		active = value
		if not animate_length:
			_current_jet_length = _get_target_jet_length()
		if not active:
			_impact_length = -1.0
		_apply_active_state()
		_apply_length()
		active_changed.emit(active)
@export var jet_length := 120.0:
	set(value):
		jet_length = maxf(value, 0.0)
		if not animate_length:
			_current_jet_length = _get_target_jet_length()
		_apply_length()
@export var push_strength := 520.0
@export var animate_length := true:
	set(value):
		animate_length = value
		if not animate_length:
			_current_jet_length = _get_target_jet_length()
		_apply_active_state()
		_apply_length()
@export var animate_on_ready := false
@export var extend_speed := 360.0
@export var retract_speed := 520.0
@export var sprite_base_scale := Vector2(0.12, 0.1)
@export var origin_overlap := 0.0:
	set(value):
		origin_overlap = maxf(value, 0.0)
		_apply_length()
@export var end_frame_overlap := 4.0:
	set(value):
		end_frame_overlap = maxf(value, 0.0)
		_apply_length()
@export var impact_frame_overlap := 2.0:
	set(value):
		impact_frame_overlap = maxf(value, 0.0)
		_apply_length()
@export var collision_width_scale := 0.85
@export var visual_preset: VisualPreset = VisualPreset.LONG_COLUMN:
	set(value):
		visual_preset = value
		_random_visual_preset = _pick_random_visual_preset()
		_apply_frame_textures()
		_apply_length()
@export var use_frame_segments := true
@export_range(0, 3, 1) var frame_row := 0
@export_range(0, 3, 1) var start_frame_column := 0
@export_range(0, 3, 1) var body_frame_column := 1
@export_range(0, 3, 1) var end_frame_column := 2
@export_range(0, 3, 1) var short_end_frame_column := 3
@export_range(0, 3, 1) var impact_frame_column := 0
@export_range(0, 3, 1) var burst_frame_column := 0:
	set(value):
		burst_frame_column = clampi(value, 0, 3)
		_cycle_frame_column = burst_frame_column
		_apply_frame_textures()
		_apply_length()
@export var short_end_length_threshold := 70.0
@export var animate_end_frame := true
@export var cycle_burst_frames := true
@export var frame_animation_fps := 8.0
@export var burst_width_scale := 1.0:
	set(value):
		burst_width_scale = maxf(value, 0.05)
		_apply_length()
@export var start_frame_height := 180.0:
	set(value):
		start_frame_height = clampf(value, 1.0, FRAME_SIZE.y)
		_apply_frame_textures()
		_apply_length()
@export var end_frame_height := 165.0:
	set(value):
		end_frame_height = clampf(value, 1.0, FRAME_SIZE.y)
		_apply_frame_textures()
		_apply_length()
@export var impact_frame_height := 130.0:
	set(value):
		impact_frame_height = clampf(value, 1.0, FRAME_SIZE.y)
		_apply_frame_textures()
		_apply_length()
@export var impact_frame_trim_top := 24.0:
	set(value):
		impact_frame_trim_top = clampf(value, 0.0, FRAME_SIZE.y - 1.0)
		_apply_frame_textures()
		_apply_length()
@export var body_frame_trim_top := 58.0:
	set(value):
		body_frame_trim_top = clampf(value, 0.0, FRAME_SIZE.y - 1.0)
		_apply_frame_textures()
		_apply_length()
@export var body_frame_trim_bottom := 50.0:
	set(value):
		body_frame_trim_bottom = clampf(value, 0.0, FRAME_SIZE.y - 1.0)
		_apply_frame_textures()
		_apply_length()
@export var segment_overlap := 4.0:
	set(value):
		segment_overlap = maxf(value, 0.0)
		_apply_length()
@export var draw_stream_overlay := false
@export var affected_collision_mask := 1
@export var use_overlap_query := true
@export var min_collision_width := 36.0
@export var use_impact_splash := true
@export var impact_collision_mask := 1
@export var impact_ray_start_offset := 4.0
@export var stream_tint := Color(0.2, 0.78, 1.0, 0.38)
@export var stream_highlight := Color(0.82, 0.98, 1.0, 0.55)

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

var _direction_override := Vector2.ZERO
var _start_sprite: Sprite2D
var _end_sprite: Sprite2D
var _frame_time := 0.0
var _use_short_end_frame := false
var _cycle_frame_column := 0
var _random_visual_preset := VisualPreset.VERTICAL_BURST
var _impact_length := -1.0
var _current_jet_length := 0.0
var _has_received_config := false


func _ready() -> void:
	add_to_group("water_jet")
	collision_layer = 0
	collision_mask = affected_collision_mask
	if collision_shape != null and collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()
	_cycle_frame_column = burst_frame_column
	_random_visual_preset = _pick_random_visual_preset()
	_current_jet_length = 0.0 if active and animate_length and animate_on_ready else _get_target_jet_length()
	_ensure_frame_sprites()
	_apply_frame_textures()
	_apply_active_state()
	_apply_length()


func _process(delta: float) -> void:
	var length_changed := _update_length_animation(delta)
	if _current_jet_length > 0.0:
		_update_impact_state()
	if length_changed:
		_apply_active_state()

	if not active or not animate_end_frame or frame_animation_fps <= 0.0:
		return

	_frame_time += delta
	var frame_duration := 1.0 / frame_animation_fps
	if _frame_time < frame_duration:
		return

	_frame_time = fmod(_frame_time, frame_duration)
	if _uses_segmented_visual():
		_use_short_end_frame = not _use_short_end_frame
	elif cycle_burst_frames:
		_cycle_frame_column = (_cycle_frame_column + 1) % 4
		if _cycle_frame_column == 0 and visual_preset == VisualPreset.RANDOM_BURST:
			_random_visual_preset = _pick_random_visual_preset()
	_apply_frame_textures()
	_apply_length()


func _physics_process(delta: float) -> void:
	if not active or _current_jet_length <= 0.0:
		return

	_update_impact_state()
	var jet_velocity: Vector2 = get_jet_velocity()
	for body in _collect_affected_bodies():
		if not body.is_in_group("player") and not body.has_method("apply_water_jet_velocity"):
			continue

		if body.has_method("apply_water_jet_velocity"):
			body.apply_water_jet_velocity(jet_velocity, delta)
		else:
			var raw_velocity = body.get("velocity")
			if typeof(raw_velocity) == TYPE_VECTOR2:
				body.set("velocity", raw_velocity + jet_velocity * delta)


func configure(
	next_active: bool,
	next_length: float,
	next_push_strength: float,
	next_direction: Vector2 = Vector2.ZERO
) -> void:
	var first_config := not _has_received_config
	set_jet_direction(next_direction)
	jet_length = next_length
	push_strength = next_push_strength
	active = next_active
	_has_received_config = true
	if first_config and not animate_on_ready:
		_current_jet_length = _get_target_jet_length()
		_apply_active_state()
		_apply_length()


func set_jet_direction(direction: Vector2) -> void:
	_direction_override = direction.normalized() if not direction.is_zero_approx() else Vector2.ZERO
	_apply_frame_textures()
	_apply_length()


func get_jet_direction() -> Vector2:
	if not _direction_override.is_zero_approx():
		return _direction_override

	return Vector2.DOWN.rotated(global_rotation).normalized()


func get_jet_velocity() -> Vector2:
	return get_jet_direction() * push_strength


func _apply_active_state() -> void:
	var has_visible_length := _current_jet_length > 0.01
	var should_show := active or has_visible_length
	var should_detect := active and has_visible_length
	visible = should_show
	set_deferred(&"monitoring", should_detect)
	set_deferred(&"monitorable", should_detect)
	set_process(active or has_visible_length)
	set_physics_process(should_detect)
	if collision_shape != null:
		collision_shape.set_deferred(&"disabled", not should_detect)
	queue_redraw()


func _apply_length() -> void:
	var display_width: float = FRAME_SIZE.x * sprite_base_scale.x
	var visual_length: float = _get_visual_jet_length()
	var display_height: float = maxf(visual_length + origin_overlap, 0.0)
	var local_start_y: float = -origin_overlap
	var local_center_y: float = local_start_y + display_height * 0.5
	var scaled_height := 0.0
	if FRAME_SIZE.y > 0.0 and sprite_base_scale.y > 0.0:
		scaled_height = display_height / FRAME_SIZE.y

	if sprite != null and _uses_segmented_visual():
		sprite.scale = Vector2(sprite_base_scale.x, scaled_height)
		sprite.position = Vector2(0, local_center_y)
		sprite.rotation = 0.0
		sprite.visible = true

	var cap_scale := Vector2(sprite_base_scale.x, sprite_base_scale.y)
	if _start_sprite != null:
		_start_sprite.visible = false

	if _end_sprite != null and _uses_segmented_visual():
		var end_display_height: float = _get_current_end_frame_height() * sprite_base_scale.y
		_end_sprite.scale = cap_scale
		_end_sprite.position = Vector2(0, visual_length - end_display_height * 0.5 + _get_current_end_overlap())
		_end_sprite.rotation = PI if _has_impact() else 0.0
		_end_sprite.visible = true

	if sprite != null and _uses_segmented_visual():
		var end_display_height: float = _get_current_end_frame_height() * sprite_base_scale.y
		var body_start_y: float = local_start_y
		var body_end_y: float = visual_length - end_display_height + _get_current_end_overlap() + segment_overlap
		var body_height: float = maxf(body_end_y - body_start_y, 1.0)
		var body_texture_height: float = _get_body_frame_height()
		sprite.scale = Vector2(sprite_base_scale.x, body_height / body_texture_height)
		sprite.position = Vector2(0, body_start_y + body_height * 0.5)

	if sprite != null and not _uses_segmented_visual():
		_apply_burst_visual_transform(local_start_y, display_height)
		sprite.visible = true
		if _start_sprite != null:
			_start_sprite.visible = false
		if _end_sprite != null:
			_end_sprite.visible = false

	if collision_shape != null:
		if collision_shape.shape is RectangleShape2D:
			var rect := collision_shape.shape as RectangleShape2D
			rect.size = Vector2(maxf(display_width * collision_width_scale, min_collision_width), display_height)
		collision_shape.position = Vector2(0, local_center_y)

	queue_redraw()


func _draw() -> void:
	if not draw_stream_overlay or not _uses_segmented_visual() or _get_effective_jet_length() <= 0.0:
		return

	var stream_width: float = FRAME_SIZE.x * sprite_base_scale.x
	var start_y: float = -origin_overlap
	var end_y: float = _get_visual_jet_length()
	var tip_y: float = end_y + minf(16.0, maxf(_get_effective_jet_length() * 0.14, 6.0))
	var start_half_width: float = stream_width * 0.18
	var end_half_width: float = stream_width * 0.42

	var stream_shape := PackedVector2Array([
		Vector2(-start_half_width, start_y),
		Vector2(start_half_width, start_y),
		Vector2(end_half_width, end_y),
		Vector2(0.0, tip_y),
		Vector2(-end_half_width, end_y),
	])
	draw_colored_polygon(stream_shape, stream_tint)

	var core_width: float = stream_width * 0.18
	var core_shape := PackedVector2Array([
		Vector2(-core_width, start_y + 2.0),
		Vector2(core_width, start_y + 2.0),
		Vector2(core_width * 1.45, end_y - 8.0),
		Vector2(0.0, tip_y - 4.0),
		Vector2(-core_width * 1.45, end_y - 8.0),
	])
	draw_colored_polygon(core_shape, Color(stream_highlight.r, stream_highlight.g, stream_highlight.b, stream_highlight.a * 0.62))

	var left_ripple := PackedVector2Array([
		Vector2(-stream_width * 0.12, start_y + 4.0),
		Vector2(-stream_width * 0.26, _get_effective_jet_length() * 0.45),
		Vector2(-stream_width * 0.36, end_y - 6.0),
	])
	var right_ripple := PackedVector2Array([
		Vector2(stream_width * 0.12, start_y + 4.0),
		Vector2(stream_width * 0.26, _get_effective_jet_length() * 0.52),
		Vector2(stream_width * 0.36, end_y - 8.0),
	])
	draw_polyline(left_ripple, stream_highlight, 1.5)
	draw_polyline(right_ripple, stream_highlight, 1.5)


func _ensure_frame_sprites() -> void:
	if sprite != null:
		sprite.z_index = 1

	_start_sprite = get_node_or_null("StartSprite") as Sprite2D
	if _start_sprite == null:
		_start_sprite = Sprite2D.new()
		_start_sprite.name = "StartSprite"
		add_child(_start_sprite)
	_start_sprite.z_index = 2

	_end_sprite = get_node_or_null("EndSprite") as Sprite2D
	if _end_sprite == null:
		_end_sprite = Sprite2D.new()
		_end_sprite.name = "EndSprite"
		add_child(_end_sprite)
	_end_sprite.z_index = 3


func _apply_frame_textures() -> void:
	if _uses_segmented_visual():
		if sprite != null:
			var body_region := _get_body_frame_region()
			sprite.texture = _make_frame_texture(
				body_frame_column,
				frame_row,
				body_region.position.y,
				body_region.size.y,
				body_region.position.x,
				body_region.size.x
			)
		if _start_sprite != null:
			_start_sprite.texture = null
		if _end_sprite != null:
			var end_region := _get_current_end_frame_region()
			if _has_impact():
				_end_sprite.texture = _make_frame_texture(
					impact_frame_column,
					frame_row,
					end_region.position.y,
					end_region.size.y,
					end_region.position.x,
					end_region.size.x
				)
			else:
				var column := short_end_frame_column if _should_use_short_end_frame() else end_frame_column
				_end_sprite.texture = _make_frame_texture(
					column,
					frame_row,
					end_region.position.y,
					end_region.size.y,
					end_region.position.x,
					end_region.size.x
				)
		return

	if sprite != null:
		var row := _get_burst_frame_row()
		var column := _get_burst_frame_column()
		var bounds := _get_frame_bounds(row, column)
		sprite.texture = _make_frame_texture(column, row, bounds.position.y, bounds.size.y, bounds.position.x, bounds.size.x)


func _make_frame_texture(
	column: int,
	row: int,
	crop_top: float = 0.0,
	crop_height: float = FRAME_SIZE.y,
	crop_left: float = 0.0,
	crop_width: float = FRAME_SIZE.x
) -> AtlasTexture:
	var safe_column := clampi(column, 0, 3)
	var safe_row := clampi(row, 0, 3)
	var safe_crop_top := clampf(crop_top, 0.0, FRAME_SIZE.y - 1.0)
	var safe_crop_height := clampf(crop_height, 1.0, FRAME_SIZE.y - safe_crop_top)
	var safe_crop_left := clampf(crop_left, 0.0, FRAME_SIZE.x - 1.0)
	var safe_crop_width := clampf(crop_width, 1.0, FRAME_SIZE.x - safe_crop_left)
	var frame_texture := AtlasTexture.new()
	frame_texture.atlas = WATER_JET_TEXTURE
	frame_texture.region = Rect2(
		Vector2(safe_column * FRAME_SIZE.x + safe_crop_left, safe_row * FRAME_SIZE.y + safe_crop_top),
		Vector2(safe_crop_width, safe_crop_height)
	)
	return frame_texture


func _should_use_short_end_frame() -> bool:
	if jet_length <= short_end_length_threshold:
		return true

	return animate_end_frame and _use_short_end_frame


func _get_body_frame_height() -> float:
	return _get_body_frame_region().size.y


func _get_body_frame_region() -> Rect2:
	var bounds := _get_frame_bounds(frame_row, body_frame_column)
	var top := maxf(body_frame_trim_top, bounds.position.y)
	var bottom := minf(FRAME_SIZE.y - body_frame_trim_bottom, bounds.position.y + bounds.size.y)
	var height := maxf(bottom - top, 1.0)
	return Rect2(bounds.position.x, top, bounds.size.x, height)


func _get_current_end_frame_region() -> Rect2:
	if _has_impact():
		return _get_top_frame_region(impact_frame_column, frame_row, impact_frame_height, impact_frame_trim_top)

	var column := short_end_frame_column if _should_use_short_end_frame() else end_frame_column
	return _get_bottom_frame_region(column, frame_row, end_frame_height)


func _get_top_frame_region(column: int, row: int, target_height: float, trim_top: float = 0.0) -> Rect2:
	var bounds := _get_frame_bounds(row, column)
	var top := bounds.position.y + minf(maxf(trim_top, 0.0), bounds.size.y - 1.0)
	var height := minf(maxf(target_height, 1.0), bounds.position.y + bounds.size.y - top)
	return Rect2(bounds.position.x, top, bounds.size.x, height)


func _get_bottom_frame_region(column: int, row: int, target_height: float) -> Rect2:
	var bounds := _get_frame_bounds(row, column)
	var height := minf(maxf(target_height, 1.0), bounds.size.y)
	var top := bounds.position.y + bounds.size.y - height
	return Rect2(bounds.position.x, top, bounds.size.x, height)


func _get_target_jet_length() -> float:
	return jet_length if active else 0.0


func _get_effective_jet_length() -> float:
	if not animate_length:
		return _get_target_jet_length()
	return clampf(_current_jet_length, 0.0, jet_length)


func _update_length_animation(delta: float) -> bool:
	var previous_length := _current_jet_length
	var target_length := _get_target_jet_length()
	if not animate_length:
		_current_jet_length = target_length
	else:
		var speed := extend_speed if target_length > _current_jet_length else retract_speed
		_current_jet_length = move_toward(
			_current_jet_length,
			target_length,
			maxf(speed, 0.0) * delta
		)

	if is_equal_approx(previous_length, _current_jet_length):
		return false

	if _current_jet_length <= 0.01:
		_impact_length = -1.0
	_apply_length()
	return true


func _get_visual_jet_length() -> float:
	var current_length := _get_effective_jet_length()
	if _has_impact():
		return clampf(_impact_length, 0.0, current_length)
	return current_length


func _has_impact() -> bool:
	return use_impact_splash and _impact_length >= 0.0


func _get_current_end_frame_height() -> float:
	return _get_current_end_frame_region().size.y


func _get_current_end_overlap() -> float:
	return impact_frame_overlap if _has_impact() else end_frame_overlap


func _uses_segmented_visual() -> bool:
	return use_frame_segments and _get_effective_visual_preset() == VisualPreset.LONG_COLUMN


func _get_effective_visual_preset() -> int:
	if visual_preset == VisualPreset.AUTO_BY_DIRECTION:
		return _pick_directional_visual_preset()
	if visual_preset == VisualPreset.RANDOM_BURST:
		return _random_visual_preset
	return visual_preset


func _pick_directional_visual_preset() -> int:
	var direction := get_jet_direction()
	if direction.is_zero_approx():
		return VisualPreset.LONG_COLUMN

	var abs_x := absf(direction.x)
	var abs_y := absf(direction.y)
	if _get_effective_jet_length() >= 110.0 and abs_y >= abs_x:
		return VisualPreset.LONG_COLUMN
	if abs_x > abs_y * 1.35:
		return VisualPreset.HORIZONTAL_BURST
	if direction.x * direction.y >= 0.0:
		return VisualPreset.DIAGONAL_DOWN_BURST
	return VisualPreset.DIAGONAL_UP_BURST


func _pick_random_visual_preset() -> int:
	return VisualPreset.VERTICAL_BURST + (randi() % 4)


func _get_burst_frame_row() -> int:
	match _get_effective_visual_preset():
		VisualPreset.HORIZONTAL_BURST:
			return 1
		VisualPreset.DIAGONAL_DOWN_BURST:
			return 2
		VisualPreset.DIAGONAL_UP_BURST:
			return 3
		_:
			return 0


func _get_burst_frame_column() -> int:
	return clampi(_cycle_frame_column if cycle_burst_frames else burst_frame_column, 0, 3)


func _get_frame_bounds(row: int, column: int) -> Rect2:
	var safe_row := clampi(row, 0, 3)
	var safe_column := clampi(column, 0, 3)
	match safe_row:
		0:
			match safe_column:
				0:
					return Rect2(74, 30, 116, 233)
				1:
					return Rect2(88, 42, 76, 210)
				2:
					return Rect2(75, 44, 89, 206)
				_:
					return Rect2(77, 56, 74, 181)
		1:
			match safe_column:
				0:
					return Rect2(53, 82, 157, 117)
				1:
					return Rect2(62, 103, 127, 76)
				2:
					return Rect2(41, 98, 157, 85)
				_:
					return Rect2(37, 102, 153, 77)
		2:
			match safe_column:
				0:
					return Rect2(44, 46, 175, 177)
				1:
					return Rect2(45, 49, 162, 171)
				2:
					return Rect2(43, 57, 154, 156)
				_:
					return Rect2(43, 63, 141, 143)
		_:
			match safe_column:
				0:
					return Rect2(47, 39, 170, 180)
				1:
					return Rect2(51, 45, 149, 168)
				2:
					return Rect2(48, 49, 144, 160)
				_:
					return Rect2(43, 49, 141, 160)


func _apply_burst_visual_transform(local_start_y: float, display_height: float) -> void:
	var row := _get_burst_frame_row()
	var column := _get_burst_frame_column()
	var bounds := _get_frame_bounds(row, column)
	var target_width := maxf(FRAME_SIZE.x * sprite_base_scale.x * burst_width_scale, 1.0)
	var target_length := maxf(display_height, 1.0)

	sprite.position = Vector2(0, local_start_y + display_height * 0.5)
	sprite.rotation = _get_burst_rotation_offset(row, bounds)
	match row:
		0:
			sprite.scale = Vector2(target_width / bounds.size.x, target_length / bounds.size.y)
		1:
			sprite.scale = Vector2(target_length / bounds.size.x, target_width / bounds.size.y)
		_:
			var source_length := maxf(bounds.size.length(), 1.0)
			var uniform_scale := target_length / source_length
			sprite.scale = Vector2.ONE * uniform_scale * burst_width_scale


func _get_burst_rotation_offset(row: int, bounds: Rect2) -> float:
	match row:
		1:
			return PI * 0.5
		2:
			var down_right_angle := atan2(bounds.size.y, bounds.size.x)
			return PI * 0.5 - down_right_angle
		3:
			var up_right_angle := -atan2(bounds.size.y, bounds.size.x)
			return PI * 0.5 - up_right_angle
		_:
			return 0.0


func _update_impact_state() -> void:
	if not use_impact_splash:
		_set_impact_length(-1.0)
		return

	var ray_length := _get_effective_jet_length()
	if ray_length <= 0.0:
		_set_impact_length(-1.0)
		return

	var impact_length := _get_player_impact_length(ray_length)
	var start := to_global(Vector2(0.0, maxf(impact_ray_start_offset, 0.0)))
	var end := to_global(Vector2(0.0, ray_length))
	var query := PhysicsRayQueryParameters2D.create(start, end)
	query.collision_mask = impact_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = _get_collision_query_excludes()

	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var hit_position = hit.get("position")
		if typeof(hit_position) == TYPE_VECTOR2:
			var local_hit := to_local(hit_position)
			var ray_impact := clampf(local_hit.y, 0.0, ray_length)
			impact_length = ray_impact if impact_length < 0.0 else minf(impact_length, ray_impact)

	_set_impact_length(impact_length)


func _get_player_impact_length(ray_length: float) -> float:
	var best_length := -1.0
	var stream_half_width := maxf(FRAME_SIZE.x * sprite_base_scale.x * collision_width_scale, min_collision_width) * 0.5
	for body in _collect_affected_bodies():
		if not body.is_in_group("player"):
			continue

		var local_position := to_local((body as Node2D).global_position) if body is Node2D else Vector2.ZERO
		var radius := _get_body_impact_radius(body)
		if local_position.y + radius < 0.0 or local_position.y - radius > ray_length:
			continue
		if absf(local_position.x) > stream_half_width + radius:
			continue

		var candidate := clampf(local_position.y - radius, 0.0, ray_length)
		best_length = candidate if best_length < 0.0 else minf(best_length, candidate)

	return best_length


func _get_body_impact_radius(body: Node) -> float:
	var collision := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return 10.0

	if collision.shape is CircleShape2D:
		return (collision.shape as CircleShape2D).radius * maxf(absf(collision.global_scale.x), absf(collision.global_scale.y))
	if collision.shape is RectangleShape2D:
		var rect := collision.shape as RectangleShape2D
		return rect.size.length() * 0.5 * maxf(absf(collision.global_scale.x), absf(collision.global_scale.y))

	return 10.0


func _set_impact_length(next_length: float) -> void:
	if is_equal_approx(_impact_length, next_length):
		return

	_impact_length = next_length
	_apply_frame_textures()
	_apply_length()


func _get_collision_query_excludes() -> Array[RID]:
	var excludes: Array[RID] = [get_rid()]
	var parent_object := get_parent() as CollisionObject2D
	if parent_object != null:
		excludes.append(parent_object.get_rid())
	return excludes


func _collect_affected_bodies() -> Array[Node]:
	var bodies: Array[Node] = []
	var seen: Dictionary = {}
	if monitoring:
		for raw_body in get_overlapping_bodies():
			if raw_body is Node:
				_add_body_once(bodies, seen, raw_body as Node)

	if not use_overlap_query:
		return bodies

	if collision_shape == null or collision_shape.shape == null:
		return bodies

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = affected_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = _get_collision_query_excludes()

	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_shape(query, 24)
	for hit in hits:
		var collider = hit.get("collider")
		if collider is Node:
			_add_body_once(bodies, seen, collider as Node)

	return bodies


func _add_body_once(bodies: Array[Node], seen: Dictionary, body: Node) -> void:
	var instance_id := body.get_instance_id()
	if seen.has(instance_id):
		return

	seen[instance_id] = true
	bodies.append(body)
