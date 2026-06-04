extends RefCounted
class_name WaterJetVisualRuntime

const WaterJetFrameAtlas = preload("res://scripts/water/water_jet_frame_atlas.gd")

enum VisualPreset {
	LONG_COLUMN,
	VERTICAL_BURST,
	HORIZONTAL_BURST,
	DIAGONAL_DOWN_BURST,
	DIAGONAL_UP_BURST,
	AUTO_BY_DIRECTION,
	RANDOM_BURST,
}

var _owner


func setup(owner) -> void:
	_owner = owner


func apply_active_state() -> void:
	var has_visible_length: bool = _owner._current_jet_length > 0.01
	var should_show: bool = _owner.active or has_visible_length
	var should_detect: bool = _owner.active and has_visible_length
	_owner.visible = should_show
	_owner.set_deferred(&"monitoring", should_detect)
	_owner.set_deferred(&"monitorable", should_detect)
	_owner.set_process(_owner.active or has_visible_length)
	_owner.set_physics_process(should_detect)
	if _owner.collision_shape != null:
		_owner.collision_shape.set_deferred(&"disabled", not should_detect)
	_owner.queue_redraw()


func apply_length() -> void:
	var display_width: float = _owner.FRAME_SIZE.x * _owner.sprite_base_scale.x
	var visual_length: float = get_visual_jet_length()
	var display_height: float = maxf(visual_length + _owner.origin_overlap, 0.0)
	var local_start_y: float = -_owner.origin_overlap
	var local_center_y: float = local_start_y + display_height * 0.5
	var scaled_height := 0.0
	if _owner.FRAME_SIZE.y > 0.0 and _owner.sprite_base_scale.y > 0.0:
		scaled_height = display_height / _owner.FRAME_SIZE.y

	if _owner.sprite != null and uses_segmented_visual():
		_owner.sprite.scale = Vector2(_owner.sprite_base_scale.x, scaled_height)
		_owner.sprite.position = Vector2(0, local_center_y)
		_owner.sprite.rotation = 0.0
		_owner.sprite.visible = true

	var cap_scale := Vector2(_owner.sprite_base_scale.x, _owner.sprite_base_scale.y)
	if _owner._start_sprite != null:
		_owner._start_sprite.visible = false

	if _owner._end_sprite != null and uses_segmented_visual():
		var end_display_height: float = get_current_end_frame_height() * _owner.sprite_base_scale.y
		_owner._end_sprite.scale = cap_scale
		_owner._end_sprite.position = Vector2(0, visual_length - end_display_height * 0.5 + get_current_end_overlap())
		_owner._end_sprite.rotation = PI if has_impact() else 0.0
		_owner._end_sprite.visible = true

	if _owner.sprite != null and uses_segmented_visual():
		var end_display_height: float = get_current_end_frame_height() * _owner.sprite_base_scale.y
		var body_start_y: float = local_start_y
		var body_end_y: float = visual_length - end_display_height + get_current_end_overlap() + _owner.segment_overlap
		var body_height: float = maxf(body_end_y - body_start_y, 1.0)
		var body_texture_height: float = get_body_frame_height()
		_owner.sprite.scale = Vector2(_owner.sprite_base_scale.x, body_height / body_texture_height)
		_owner.sprite.position = Vector2(0, body_start_y + body_height * 0.5)

	if _owner.sprite != null and not uses_segmented_visual():
		apply_burst_visual_transform(local_start_y, display_height)
		_owner.sprite.visible = true
		if _owner._start_sprite != null:
			_owner._start_sprite.visible = false
		if _owner._end_sprite != null:
			_owner._end_sprite.visible = false

	if _owner.collision_shape != null:
		if _owner.collision_shape.shape is RectangleShape2D:
			var rect: RectangleShape2D = _owner.collision_shape.shape as RectangleShape2D
			rect.size = Vector2(maxf(display_width * _owner.collision_width_scale, _owner.min_collision_width), display_height)
		_owner.collision_shape.position = Vector2(0, local_center_y)

	_owner.queue_redraw()


func draw_overlay() -> void:
	if not _owner.draw_stream_overlay or not uses_segmented_visual() or get_effective_jet_length() <= 0.0:
		return

	var stream_width: float = _owner.FRAME_SIZE.x * _owner.sprite_base_scale.x
	var start_y: float = -_owner.origin_overlap
	var end_y: float = get_visual_jet_length()
	var tip_y: float = end_y + minf(16.0, maxf(get_effective_jet_length() * 0.14, 6.0))
	var start_half_width: float = stream_width * 0.18
	var end_half_width: float = stream_width * 0.42

	var stream_shape := PackedVector2Array([
		Vector2(-start_half_width, start_y),
		Vector2(start_half_width, start_y),
		Vector2(end_half_width, end_y),
		Vector2(0.0, tip_y),
		Vector2(-end_half_width, end_y),
	])
	_owner.draw_colored_polygon(stream_shape, _owner.stream_tint)

	var core_width: float = stream_width * 0.18
	var core_shape := PackedVector2Array([
		Vector2(-core_width, start_y + 2.0),
		Vector2(core_width, start_y + 2.0),
		Vector2(core_width * 1.45, end_y - 8.0),
		Vector2(0.0, tip_y - 4.0),
		Vector2(-core_width * 1.45, end_y - 8.0),
	])
	_owner.draw_colored_polygon(core_shape, Color(
		_owner.stream_highlight.r,
		_owner.stream_highlight.g,
		_owner.stream_highlight.b,
		_owner.stream_highlight.a * 0.62
	))

	var left_ripple := PackedVector2Array([
		Vector2(-stream_width * 0.12, start_y + 4.0),
		Vector2(-stream_width * 0.26, get_effective_jet_length() * 0.45),
		Vector2(-stream_width * 0.36, end_y - 6.0),
	])
	var right_ripple := PackedVector2Array([
		Vector2(stream_width * 0.12, start_y + 4.0),
		Vector2(stream_width * 0.26, get_effective_jet_length() * 0.52),
		Vector2(stream_width * 0.36, end_y - 8.0),
	])
	_owner.draw_polyline(left_ripple, _owner.stream_highlight, 1.5)
	_owner.draw_polyline(right_ripple, _owner.stream_highlight, 1.5)


func ensure_frame_sprites() -> void:
	if _owner.sprite != null:
		_owner.sprite.z_index = 1

	_owner._start_sprite = _owner.get_node_or_null("StartSprite") as Sprite2D
	if _owner._start_sprite == null:
		_owner._start_sprite = Sprite2D.new()
		_owner._start_sprite.name = "StartSprite"
		_owner.add_child(_owner._start_sprite)
	_owner._start_sprite.z_index = 2

	_owner._end_sprite = _owner.get_node_or_null("EndSprite") as Sprite2D
	if _owner._end_sprite == null:
		_owner._end_sprite = Sprite2D.new()
		_owner._end_sprite.name = "EndSprite"
		_owner.add_child(_owner._end_sprite)
	_owner._end_sprite.z_index = 3


func apply_frame_textures() -> void:
	if uses_segmented_visual():
		if _owner.sprite != null:
			var body_region := get_body_frame_region()
			_owner.sprite.texture = make_frame_texture(
				_owner.body_frame_column,
				_owner.frame_row,
				body_region.position.y,
				body_region.size.y,
				body_region.position.x,
				body_region.size.x
			)
		if _owner._start_sprite != null:
			_owner._start_sprite.texture = null
		if _owner._end_sprite != null:
			var end_region := get_current_end_frame_region()
			if has_impact():
				_owner._end_sprite.texture = make_frame_texture(
					_owner.impact_frame_column,
					_owner.frame_row,
					end_region.position.y,
					end_region.size.y,
					end_region.position.x,
					end_region.size.x
				)
			else:
				var column: int = _owner.short_end_frame_column if should_use_short_end_frame() else _owner.end_frame_column
				_owner._end_sprite.texture = make_frame_texture(
					column,
					_owner.frame_row,
					end_region.position.y,
					end_region.size.y,
					end_region.position.x,
					end_region.size.x
				)
		return

	if _owner.sprite != null:
		var row := get_burst_frame_row()
		var column := get_burst_frame_column()
		var bounds := get_frame_bounds(row, column)
		_owner.sprite.texture = make_frame_texture(column, row, bounds.position.y, bounds.size.y, bounds.position.x, bounds.size.x)


func make_frame_texture(
	column: int,
	row: int,
	crop_top: float = 0.0,
	crop_height: float = 0.0,
	crop_left: float = 0.0,
	crop_width: float = 0.0
) -> AtlasTexture:
	var resolved_height: float = crop_height if crop_height > 0.0 else _owner.FRAME_SIZE.y
	var resolved_width: float = crop_width if crop_width > 0.0 else _owner.FRAME_SIZE.x
	return WaterJetFrameAtlas.make_frame_texture(
		_owner.WATER_JET_TEXTURE,
		_owner.FRAME_SIZE,
		column,
		row,
		crop_top,
		resolved_height,
		crop_left,
		resolved_width
	)


func should_use_short_end_frame() -> bool:
	if _owner.jet_length <= _owner.short_end_length_threshold:
		return true

	return _owner.animate_end_frame and _owner._use_short_end_frame


func get_body_frame_height() -> float:
	return get_body_frame_region().size.y


func get_body_frame_region() -> Rect2:
	var bounds := get_frame_bounds(_owner.frame_row, _owner.body_frame_column)
	var top := maxf(_owner.body_frame_trim_top, bounds.position.y)
	var bottom := minf(_owner.FRAME_SIZE.y - _owner.body_frame_trim_bottom, bounds.position.y + bounds.size.y)
	var height := maxf(bottom - top, 1.0)
	return Rect2(bounds.position.x, top, bounds.size.x, height)


func get_current_end_frame_region() -> Rect2:
	if has_impact():
		return get_top_frame_region(_owner.impact_frame_column, _owner.frame_row, _owner.impact_frame_height, _owner.impact_frame_trim_top)

	var column: int = _owner.short_end_frame_column if should_use_short_end_frame() else _owner.end_frame_column
	return get_bottom_frame_region(column, _owner.frame_row, _owner.end_frame_height)


func get_top_frame_region(column: int, row: int, target_height: float, trim_top: float = 0.0) -> Rect2:
	var bounds := get_frame_bounds(row, column)
	var top := bounds.position.y + minf(maxf(trim_top, 0.0), bounds.size.y - 1.0)
	var height := minf(maxf(target_height, 1.0), bounds.position.y + bounds.size.y - top)
	return Rect2(bounds.position.x, top, bounds.size.x, height)


func get_bottom_frame_region(column: int, row: int, target_height: float) -> Rect2:
	var bounds := get_frame_bounds(row, column)
	var height := minf(maxf(target_height, 1.0), bounds.size.y)
	var top := bounds.position.y + bounds.size.y - height
	return Rect2(bounds.position.x, top, bounds.size.x, height)


func get_target_jet_length() -> float:
	return _owner.jet_length if _owner.active else 0.0


func get_effective_jet_length() -> float:
	if not _owner.animate_length:
		return get_target_jet_length()
	return clampf(_owner._current_jet_length, 0.0, _owner.jet_length)


func update_length_animation(delta: float) -> bool:
	var previous_length: float = _owner._current_jet_length
	var target_length := get_target_jet_length()
	if not _owner.animate_length:
		_owner._current_jet_length = target_length
	else:
		var speed: float = _owner.extend_speed if target_length > _owner._current_jet_length else _owner.retract_speed
		_owner._current_jet_length = move_toward(
			_owner._current_jet_length,
			target_length,
			maxf(speed, 0.0) * delta
		)

	if is_equal_approx(previous_length, _owner._current_jet_length):
		return false

	if _owner._current_jet_length <= 0.01:
		_owner._impact_length = -1.0
	apply_length()
	return true


func get_visual_jet_length() -> float:
	var current_length := get_effective_jet_length()
	if has_impact():
		return clampf(_owner._impact_length, 0.0, current_length)
	return current_length


func has_impact() -> bool:
	return _owner.use_impact_splash and _owner._impact_length >= 0.0


func get_current_end_frame_height() -> float:
	return get_current_end_frame_region().size.y


func get_current_end_overlap() -> float:
	return _owner.impact_frame_overlap if has_impact() else _owner.end_frame_overlap


func uses_segmented_visual() -> bool:
	return _owner.use_frame_segments and get_effective_visual_preset() == VisualPreset.LONG_COLUMN


func get_effective_visual_preset() -> int:
	if _owner.visual_preset == _owner.VisualPreset.AUTO_BY_DIRECTION:
		return pick_directional_visual_preset()
	if _owner.visual_preset == _owner.VisualPreset.RANDOM_BURST:
		return _owner._random_visual_preset
	return _owner.visual_preset


func pick_directional_visual_preset() -> int:
	var direction: Vector2 = _owner.get_jet_direction()
	if direction.is_zero_approx():
		return VisualPreset.LONG_COLUMN

	var abs_x := absf(direction.x)
	var abs_y := absf(direction.y)
	if get_effective_jet_length() >= 110.0 and abs_y >= abs_x:
		return VisualPreset.LONG_COLUMN
	if abs_x > abs_y * 1.35:
		return VisualPreset.HORIZONTAL_BURST
	if direction.x * direction.y >= 0.0:
		return VisualPreset.DIAGONAL_DOWN_BURST
	return VisualPreset.DIAGONAL_UP_BURST


func pick_random_visual_preset() -> int:
	return VisualPreset.VERTICAL_BURST + (randi() % 4)


func get_burst_frame_row() -> int:
	match get_effective_visual_preset():
		VisualPreset.HORIZONTAL_BURST:
			return 1
		VisualPreset.DIAGONAL_DOWN_BURST:
			return 2
		VisualPreset.DIAGONAL_UP_BURST:
			return 3
		_:
			return 0


func get_burst_frame_column() -> int:
	return clampi(_owner._cycle_frame_column if _owner.cycle_burst_frames else _owner.burst_frame_column, 0, 3)


func get_frame_bounds(row: int, column: int) -> Rect2:
	return WaterJetFrameAtlas.frame_bounds(row, column)


func apply_burst_visual_transform(local_start_y: float, display_height: float) -> void:
	var row := get_burst_frame_row()
	var column := get_burst_frame_column()
	var bounds := get_frame_bounds(row, column)
	var target_width := maxf(_owner.FRAME_SIZE.x * _owner.sprite_base_scale.x * _owner.burst_width_scale, 1.0)
	var target_length := maxf(display_height, 1.0)

	_owner.sprite.position = Vector2(0, local_start_y + display_height * 0.5)
	_owner.sprite.rotation = get_burst_rotation_offset(row, bounds)
	match row:
		0:
			_owner.sprite.scale = Vector2(target_width / bounds.size.x, target_length / bounds.size.y)
		1:
			_owner.sprite.scale = Vector2(target_length / bounds.size.x, target_width / bounds.size.y)
		_:
			var source_length := maxf(bounds.size.length(), 1.0)
			var uniform_scale := target_length / source_length
			_owner.sprite.scale = Vector2.ONE * uniform_scale * _owner.burst_width_scale


func get_burst_rotation_offset(row: int, bounds: Rect2) -> float:
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


func set_impact_length(next_length: float) -> void:
	if is_equal_approx(_owner._impact_length, next_length):
		return

	_owner._impact_length = next_length
	apply_frame_textures()
	apply_length()
