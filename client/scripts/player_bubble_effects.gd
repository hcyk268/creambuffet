extends RefCounted
class_name PlayerBubbleEffects

var _owner: Node
var _bubble_effect: AnimatedSprite2D
var _bubble_scene: PackedScene
var _bubble_breath_interval := 0.7
var _bubble_swim_interval := 0.16
var _bubble_swim_velocity_threshold := 45.0
var _bubble_trail_lifetime := 0.75
var _bubble_emit_timer := 0.0
var _rng := RandomNumberGenerator.new()


func setup(
	owner: Node,
	bubble_effect: AnimatedSprite2D,
	bubble_scene: PackedScene,
	bubble_breath_interval: float,
	bubble_swim_interval: float,
	bubble_swim_velocity_threshold: float,
	bubble_trail_lifetime: float
) -> void:
	_owner = owner
	_bubble_effect = bubble_effect
	_bubble_scene = bubble_scene
	_bubble_breath_interval = bubble_breath_interval
	_bubble_swim_interval = bubble_swim_interval
	_bubble_swim_velocity_threshold = bubble_swim_velocity_threshold
	_bubble_trail_lifetime = bubble_trail_lifetime
	_rng.randomize()


func reset() -> void:
	_bubble_emit_timer = 0.0


func update_visibility(in_water: bool) -> void:
	if _bubble_effect == null:
		return

	_bubble_effect.visible = in_water
	if in_water:
		if not _bubble_effect.is_playing():
			_bubble_effect.play("bubble")
	else:
		_bubble_effect.stop()


func process(delta: float, in_water: bool, velocity: Vector2, facing_direction: float) -> void:
	if _bubble_effect == null:
		return

	if not in_water:
		_bubble_emit_timer = 0.0
		return

	_bubble_emit_timer -= delta
	if _bubble_emit_timer > 0.0:
		return

	var is_swimming := velocity.length() >= _bubble_swim_velocity_threshold
	var interval := _bubble_swim_interval if is_swimming else _bubble_breath_interval
	_bubble_emit_timer = interval * _rng.randf_range(0.75, 1.25)
	_spawn_bubble_burst(is_swimming, velocity, facing_direction)


func _spawn_bubble_burst(is_swimming: bool, velocity: Vector2, facing_direction: float) -> void:
	if _owner == null or _bubble_effect == null:
		return

	var count: int = _rng.randi_range(2, 4) if is_swimming else 1
	for index in range(count):
		var bubble: AnimatedSprite2D = _bubble_effect.duplicate() as AnimatedSprite2D
		if bubble == null:
			bubble = _bubble_scene.instantiate() as AnimatedSprite2D
		if bubble == null:
			continue

		bubble.name = "BubbleTrail"
		_owner.add_child(bubble)
		bubble.visible = true
		bubble.position = _get_bubble_spawn_offset(is_swimming, velocity, facing_direction)
		bubble.scale = _bubble_effect.scale * _rng.randf_range(0.65, 1.25)
		bubble.speed_scale = _rng.randf_range(0.75, 1.35)
		bubble.modulate = Color(1.0, 1.0, 1.0, _rng.randf_range(0.55, 0.9))
		bubble.play("bubble")

		var drift := _get_bubble_drift(is_swimming, velocity)
		var lifetime := _bubble_trail_lifetime * _rng.randf_range(0.75, 1.25)
		var tween: Tween = _owner.create_tween()
		tween.tween_property(bubble, "position", bubble.position + drift, lifetime)
		tween.parallel().tween_property(bubble, "modulate:a", 0.0, lifetime)
		tween.tween_callback(bubble.queue_free)


func _get_bubble_spawn_offset(is_swimming: bool, velocity: Vector2, facing_direction: float) -> Vector2:
	if not is_swimming:
		return Vector2(
			_rng.randf_range(-5.0, 5.0),
			_rng.randf_range(-38.0, -28.0)
		)

	var trail_side: float = -1.0
	if not is_zero_approx(velocity.x):
		trail_side = -signf(velocity.x)
	else:
		trail_side = -facing_direction

	return Vector2(
		trail_side * _rng.randf_range(8.0, 18.0),
		_rng.randf_range(-34.0, -16.0)
	)


func _get_bubble_drift(is_swimming: bool, velocity: Vector2) -> Vector2:
	if not is_swimming:
		return Vector2(
			_rng.randf_range(-12.0, 12.0),
			_rng.randf_range(-42.0, -22.0)
		)

	var horizontal_drift: float = -signf(velocity.x) * _rng.randf_range(10.0, 28.0)
	if is_zero_approx(velocity.x):
		horizontal_drift = _rng.randf_range(-14.0, 14.0)

	return Vector2(
		horizontal_drift,
		_rng.randf_range(-28.0, -10.0)
	)
