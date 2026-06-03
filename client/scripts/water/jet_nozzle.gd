extends StaticBody2D
class_name WaterJetNozzle

signal jet_state_changed(active: bool)

@export var active := true:
	set(value):
		active = value
		_update_visual_state()
		_configure_water_jet()
		jet_state_changed.emit(active)
@export var sync_id := ""
@export var jet_direction := Vector2.DOWN
@export var jet_strength := 520.0
@export var jet_length := 120.0:
	set(value):
		jet_length = maxf(value, 0.0)
		_configure_water_jet()
@export var use_rotation_for_direction := true
@export var keep_jet_world_size := true
@export var jet_animate_length := true:
	set(value):
		jet_animate_length = value
		_configure_water_jet()
@export var jet_animate_on_ready := false:
	set(value):
		jet_animate_on_ready = value
		_configure_water_jet()
@export var jet_extend_speed := 360.0:
	set(value):
		jet_extend_speed = maxf(value, 0.0)
		_configure_water_jet()
@export var jet_retract_speed := 520.0:
	set(value):
		jet_retract_speed = maxf(value, 0.0)
		_configure_water_jet()
@export_enum(
	"Long Column",
	"Vertical Burst",
	"Horizontal Burst",
	"Diagonal Down Burst",
	"Diagonal Up Burst",
	"Auto By Direction",
	"Random Burst"
) var jet_visual_preset := 0:
	set(value):
		jet_visual_preset = value
		_configure_water_jet()
@export_range(0, 3, 1) var jet_burst_frame_column := 0:
	set(value):
		jet_burst_frame_column = clampi(value, 0, 3)
		_configure_water_jet()
@export var jet_cycle_burst_frames := true:
	set(value):
		jet_cycle_burst_frames = value
		_configure_water_jet()
@export var jet_burst_width_scale := 1.0:
	set(value):
		jet_burst_width_scale = maxf(value, 0.05)
		_configure_water_jet()
@export var jet_min_collision_width := 36.0:
	set(value):
		jet_min_collision_width = maxf(value, 1.0)
		_configure_water_jet()
@export var water_jet_path: NodePath = ^"WaterJet"


func _ready() -> void:
	add_to_group("water_jet_nozzle")
	_update_visual_state()
	_configure_water_jet()


func get_jet_origin() -> Vector2:
	var marker := get_node_or_null("JetOrigin") as Marker2D
	if marker == null:
		return global_position
	return marker.global_position


func get_jet_velocity() -> Vector2:
	var direction := get_jet_direction()
	if direction.is_zero_approx():
		return Vector2.ZERO
	return direction * jet_strength


func get_jet_direction() -> Vector2:
	if use_rotation_for_direction:
		return Vector2.DOWN.rotated(global_rotation).normalized()

	if jet_direction.is_zero_approx():
		return Vector2.ZERO
	return jet_direction.normalized()


func set_activation(enabled: bool) -> void:
	active = enabled


func set_jet_length(length: float) -> void:
	jet_length = length


func _update_visual_state() -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.modulate = Color.WHITE if active else Color(0.55, 0.55, 0.55, 0.8)


func _configure_water_jet() -> void:
	var water_jet: Node = get_node_or_null(water_jet_path)
	if water_jet == null:
		return

	if water_jet is Node2D:
		var jet_node: Node2D = water_jet as Node2D
		var marker: Marker2D = get_node_or_null("JetOrigin") as Marker2D
		if marker != null:
			jet_node.position = marker.position
		jet_node.rotation = 0.0
		jet_node.scale = _get_jet_local_scale()

	_configure_water_jet_visual(water_jet)
	if water_jet.has_method("configure"):
		water_jet.configure(active, jet_length, jet_strength, get_jet_direction())


func _configure_water_jet_visual(water_jet: Node) -> void:
	water_jet.set("animate_length", jet_animate_length)
	water_jet.set("animate_on_ready", jet_animate_on_ready)
	water_jet.set("extend_speed", jet_extend_speed)
	water_jet.set("retract_speed", jet_retract_speed)
	water_jet.set("visual_preset", jet_visual_preset)
	water_jet.set("burst_frame_column", jet_burst_frame_column)
	water_jet.set("cycle_burst_frames", jet_cycle_burst_frames)
	water_jet.set("burst_width_scale", jet_burst_width_scale)
	water_jet.set("min_collision_width", jet_min_collision_width)


func _get_jet_local_scale() -> Vector2:
	if not keep_jet_world_size:
		return Vector2.ONE

	var safe_x: float = maxf(absf(scale.x), 0.001)
	var safe_y: float = maxf(absf(scale.y), 0.001)
	var sign_x := -1.0 if scale.x < 0.0 else 1.0
	var sign_y := -1.0 if scale.y < 0.0 else 1.0
	return Vector2(sign_x / safe_x, sign_y / safe_y)
