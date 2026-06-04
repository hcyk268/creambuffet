extends Area2D
class_name WaterJet

signal active_changed(active: bool)

const WATER_JET_TEXTURE := preload("res://assets/sprites/waterjet.png")
const WaterJetCollisionHelper = preload("res://scripts/water/water_jet_collision_helper.gd")
const WaterJetVisualRuntime = preload("res://scripts/water/water_jet_visual_runtime.gd")
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
var _visual_runtime: WaterJetVisualRuntime


func _ready() -> void:
	add_to_group("water_jet")
	collision_layer = 0
	collision_mask = affected_collision_mask
	if collision_shape != null and collision_shape.shape != null:
		collision_shape.shape = collision_shape.shape.duplicate()
	_visual_runtime = WaterJetVisualRuntime.new()
	_visual_runtime.setup(self)
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

	var affected_bodies := WaterJetCollisionHelper.collect_affected_bodies(
		self,
		collision_shape,
		affected_collision_mask,
		use_overlap_query
	)
	_update_impact_state(affected_bodies)
	var jet_velocity: Vector2 = get_jet_velocity()
	for body in affected_bodies:
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
	if _visual_runtime != null:
		_visual_runtime.apply_active_state()


func _apply_length() -> void:
	if _visual_runtime != null:
		_visual_runtime.apply_length()


func _draw() -> void:
	if _visual_runtime != null:
		_visual_runtime.draw_overlay()


func _ensure_frame_sprites() -> void:
	if _visual_runtime != null:
		_visual_runtime.ensure_frame_sprites()


func _apply_frame_textures() -> void:
	if _visual_runtime != null:
		_visual_runtime.apply_frame_textures()


func _get_target_jet_length() -> float:
	return _visual_runtime.get_target_jet_length() if _visual_runtime != null else jet_length if active else 0.0


func _get_effective_jet_length() -> float:
	return _visual_runtime.get_effective_jet_length() if _visual_runtime != null else clampf(_current_jet_length, 0.0, jet_length)


func _update_length_animation(delta: float) -> bool:
	return _visual_runtime.update_length_animation(delta) if _visual_runtime != null else false


func _get_visual_jet_length() -> float:
	return _visual_runtime.get_visual_jet_length() if _visual_runtime != null else _get_effective_jet_length()


func _has_impact() -> bool:
	return _visual_runtime.has_impact() if _visual_runtime != null else use_impact_splash and _impact_length >= 0.0


func _get_current_end_frame_height() -> float:
	return _visual_runtime.get_current_end_frame_height() if _visual_runtime != null else 0.0


func _get_current_end_overlap() -> float:
	return _visual_runtime.get_current_end_overlap() if _visual_runtime != null else end_frame_overlap


func _uses_segmented_visual() -> bool:
	return _visual_runtime.uses_segmented_visual() if _visual_runtime != null else use_frame_segments


func _pick_random_visual_preset() -> int:
	return _visual_runtime.pick_random_visual_preset() if _visual_runtime != null else VisualPreset.VERTICAL_BURST


func _update_impact_state(affected_bodies: Array[Node] = []) -> void:
	if not use_impact_splash:
		_set_impact_length(-1.0)
		return

	var ray_length := _get_effective_jet_length()
	if ray_length <= 0.0:
		_set_impact_length(-1.0)
		return

	var runtime_bodies := affected_bodies
	if runtime_bodies.is_empty():
		runtime_bodies = WaterJetCollisionHelper.collect_affected_bodies(
			self,
			collision_shape,
			affected_collision_mask,
			use_overlap_query
		)

	var impact_length := _get_player_impact_length(ray_length, runtime_bodies)
	var ray_impact := WaterJetCollisionHelper.ray_impact_length(
		self,
		ray_length,
		impact_collision_mask,
		impact_ray_start_offset
	)
	if ray_impact >= 0.0:
		impact_length = ray_impact if impact_length < 0.0 else minf(impact_length, ray_impact)

	_set_impact_length(impact_length)


func _get_player_impact_length(ray_length: float, affected_bodies: Array[Node]) -> float:
	var stream_half_width := maxf(FRAME_SIZE.x * sprite_base_scale.x * collision_width_scale, min_collision_width) * 0.5
	return WaterJetCollisionHelper.player_impact_length(self, affected_bodies, ray_length, stream_half_width)


func _set_impact_length(next_length: float) -> void:
	if _visual_runtime != null:
		_visual_runtime.set_impact_length(next_length)
