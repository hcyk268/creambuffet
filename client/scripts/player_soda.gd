extends CharacterBody2D

signal died
signal water_state_changed(in_water: bool)
signal oxygen_changed(current: float, maximum: float)
signal oxygen_depleted

const LAND_SPRITE_TEXTURE := preload("res://assets/sprites/Player-Soda.png")
const SWIM_SPRITE_TEXTURE := preload("res://assets/sprites/playerswim.png")
const BUBBLE_EFFECT_SCENE := preload("res://prefabs/bubble_effect.tscn")
const LAND_SPRITE_HFRAMES := 5
const LAND_SPRITE_VFRAMES := 6
const SWIM_SPRITE_HFRAMES := 4
const SWIM_SPRITE_VFRAMES := 6
const LAND_SPRITE_POSITION := Vector2(0, -27)
const SWIM_SPRITE_POSITION := Vector2(0, -27)
const LAND_SPRITE_SCALE := Vector2.ONE
const SWIM_SPRITE_SCALE := Vector2(0.1, 0.1)
const WATER_JET_BLOCKED_DOT_EPSILON := 0.01

@export var SPEED := 150.0
@export var JUMP_VELOCITY := -300.0
@export var PUSH_FORCE := 8.0
@export var carried_key_offset := Vector2(0, -46)
@export var carried_key_bob_amplitude := 2.0
@export var carried_key_bob_speed := 5.0
@export var remote_reconciliation_gain := 14.0
@export var remote_snap_distance := 48.0
@export var max_oxygen := 10.0
@export var oxygen_recovery_rate := 3.0
@export var default_oxygen_drain_rate := 1.0
@export var bubble_breath_interval := 0.7
@export var bubble_swim_interval := 0.16
@export var bubble_swim_velocity_threshold := 45.0
@export var bubble_trail_lifetime := 0.75
@export var water_jet_response := 14.0
@export var water_jet_cross_drag := 2.5
@export var water_jet_max_velocity := 760.0

@onready var carried_key_sprite: Sprite2D = get_node_or_null("CarriedKey") as Sprite2D
@onready var bubble_effect: AnimatedSprite2D = get_node_or_null("BubbleEffect") as AnimatedSprite2D

var spawn_position: Vector2
var oxygen := 10.0
var key_count := 0
var carried_key_color := Color.WHITE
var network_peer_id := 0
var display_name := ""
var is_remote_player := false
var input_enabled := true
var _carried_key_bob_time := 0.0
var _push_intents: Dictionary = {}
var _remote_target_position := Vector2.ZERO
var _remote_target_velocity := Vector2.ZERO
var _has_remote_target := false
var _water_zones: Array[Area2D] = []
var _oxygen_depleted_pending := false
var _water_jet_velocity := Vector2.ZERO
var _applied_water_jet_velocity := Vector2.ZERO
var _bubble_emit_timer := 0.0
var _bubble_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_bubble_rng.randomize()
	_apply_network_control_mode()
	_update_key_indicator()
	_update_bubble_effect()
	spawn_position = global_position
	oxygen = max_oxygen
	oxygen_changed.emit(oxygen, max_oxygen)


func _process(delta: float) -> void:
	_update_oxygen(delta)
	_process_bubble_effects(delta)

	if carried_key_sprite == null or not carried_key_sprite.visible:
		return

	_carried_key_bob_time += delta
	carried_key_sprite.position = carried_key_offset + Vector2(
		0,
		sin(_carried_key_bob_time * carried_key_bob_speed) * carried_key_bob_amplitude
	)


func _physics_process(delta: float) -> void:
	if not is_remote_player or not _has_remote_target:
		return

	_follow_remote_target(delta)


func set_network_identity(peer_id: int, player_name: String = "") -> void:
	network_peer_id = peer_id
	display_name = player_name


func set_network_remote(remote: bool) -> void:
	is_remote_player = remote
	_apply_network_control_mode()


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	_apply_network_control_mode()


func die() -> void:
	died.emit()
	respawn()


func respawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	_water_jet_velocity = Vector2.ZERO
	_applied_water_jet_velocity = Vector2.ZERO
	_bubble_emit_timer = 0.0
	var was_in_water := is_in_water()
	_water_zones.clear()
	if was_in_water:
		water_state_changed.emit(false)
	_update_bubble_effect()
	reset_oxygen()
	_remote_target_position = global_position
	_remote_target_velocity = Vector2.ZERO
	_has_remote_target = is_remote_player


func reset_oxygen() -> void:
	_oxygen_depleted_pending = false
	oxygen = max_oxygen
	oxygen_changed.emit(oxygen, max_oxygen)


func enter_water_zone(zone: Area2D) -> void:
	if zone == null:
		return

	_prune_water_zones()
	var was_in_water := is_in_water()
	if not _water_zones.has(zone):
		_water_zones.append(zone)

	if not was_in_water and is_in_water():
		water_state_changed.emit(true)
		_update_bubble_effect()


func exit_water_zone(zone: Area2D) -> void:
	if zone == null:
		return

	var was_in_water := is_in_water()
	_water_zones.erase(zone)
	_prune_water_zones()

	if was_in_water and not is_in_water():
		water_state_changed.emit(false)
		_update_bubble_effect()


func enter_water(zone: Area2D) -> void:
	enter_water_zone(zone)


func exit_water(zone: Area2D) -> void:
	exit_water_zone(zone)


func is_in_water() -> bool:
	_prune_water_zones()
	return not _water_zones.is_empty()


func get_water_current_velocity() -> Vector2:
	_prune_water_zones()
	var current := Vector2.ZERO
	for zone in _water_zones:
		var raw_current = zone.get("current_velocity")
		if typeof(raw_current) == TYPE_VECTOR2:
			current += raw_current
	return current


func get_water_swim_speed_multiplier() -> float:
	_prune_water_zones()
	var multiplier := 1.0
	for zone in _water_zones:
		var raw_multiplier = zone.get("swim_speed_multiplier")
		if typeof(raw_multiplier) == TYPE_FLOAT or typeof(raw_multiplier) == TYPE_INT:
			multiplier *= float(raw_multiplier)
	return maxf(multiplier, 0.05)


func get_water_oxygen_drain_rate() -> float:
	_prune_water_zones()
	var rate := 0.0
	for zone in _water_zones:
		var raw_rate = zone.get("oxygen_drain_rate")
		if typeof(raw_rate) == TYPE_FLOAT or typeof(raw_rate) == TYPE_INT:
			rate += float(raw_rate)
		else:
			rate += default_oxygen_drain_rate
	return maxf(rate, 0.0)


func add_oxygen(amount: float) -> void:
	if max_oxygen <= 0.0:
		return

	var previous_oxygen := oxygen
	oxygen = clampf(oxygen + amount, 0.0, max_oxygen)
	if oxygen > 0.0:
		_oxygen_depleted_pending = false
	if not is_equal_approx(previous_oxygen, oxygen):
		oxygen_changed.emit(oxygen, max_oxygen)


func apply_water_jet_velocity(jet_velocity: Vector2, delta: float) -> void:
	if is_remote_player:
		return

	_water_jet_velocity += jet_velocity
	_water_jet_velocity = _water_jet_velocity.limit_length(water_jet_max_velocity)


func consume_water_jet_velocity() -> Vector2:
	var result: Vector2 = _water_jet_velocity
	_water_jet_velocity = Vector2.ZERO
	return result


func move_and_push() -> void:
	_applied_water_jet_velocity = Vector2.ZERO
	_apply_pending_water_jet(get_physics_process_delta_time())
	move_and_slide()
	if _uses_network_push_intents():
		_collect_push_intents()
	else:
		apply_push_forces()
	_remove_blocked_water_jet_velocity()


func set_key_count(value: int) -> void:
	key_count = max(value, 0)
	_update_key_indicator()


func collect_key(amount: int = 1, key_color: Color = Color.WHITE) -> void:
	key_count += amount
	carried_key_color = key_color
	_update_key_indicator()


func set_carried_key_color(key_color: Color) -> void:
	carried_key_color = key_color
	_update_key_indicator()


func has_key() -> bool:
	return key_count > 0


func use_key(amount: int = 1) -> bool:
	if key_count < amount:
		return false

	key_count -= amount
	_update_key_indicator()
	return true


func play_player_animation(animation: String) -> void:
	var anim_player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player == null or not anim_player.has_animation(animation):
		return

	_apply_sprite_sheet_for_animation(animation)
	if anim_player.current_animation != animation or not anim_player.is_playing():
		anim_player.play(animation)


func consume_push_intents() -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	for raw_value in _push_intents.values():
		if typeof(raw_value) != TYPE_DICTIONARY:
			continue
		intents.append(Dictionary(raw_value).duplicate(true))

	_push_intents.clear()
	return intents


func get_network_state(level_index: int) -> Dictionary:
	var animation := ""
	var anim_player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player != null:
		animation = anim_player.current_animation

	var flip_h := false
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		flip_h = sprite.flip_h

	return {
		"level_index": level_index,
		"position": _vector_to_packet(global_position),
		"velocity": _vector_to_packet(velocity),
		"animation": animation,
		"flip_h": flip_h,
		"carried_key_color": _color_to_packet(carried_key_color),
	}


func apply_network_state(state: Dictionary) -> void:
	var next_position := _packet_to_vector(state.get("position", {}), global_position)
	var next_velocity := _packet_to_vector(state.get("velocity", {}), velocity)
	if is_remote_player:
		_remote_target_position = next_position
		_remote_target_velocity = next_velocity
		_has_remote_target = true
		if global_position.distance_to(_remote_target_position) > remote_snap_distance:
			global_position = _remote_target_position
			velocity = _remote_target_velocity
	else:
		global_position = next_position
		velocity = next_velocity

	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.flip_h = bool(state.get("flip_h", sprite.flip_h))

	var animation := String(state.get("animation", ""))
	var anim_player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim_player != null and not animation.is_empty() and anim_player.has_animation(animation):
		if anim_player.current_animation != animation:
			play_player_animation(animation)
		else:
			_apply_sprite_sheet_for_animation(animation)

	key_count = int(state.get("key_count", key_count))
	carried_key_color = _packet_to_color(state.get("carried_key_color", {}), carried_key_color)
	_update_key_indicator()


func _apply_network_control_mode() -> void:
	if is_remote_player:
		remove_from_group("player")
		add_to_group("remote_player")
	else:
		remove_from_group("remote_player")
		add_to_group("player")

	var state_machine := get_node_or_null("StateMachine")
	var controls_enabled := not is_remote_player and input_enabled
	if state_machine != null:
		state_machine.set_process(controls_enabled)
		state_machine.set_physics_process(controls_enabled)
		state_machine.set_process_unhandled_input(controls_enabled)

	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null:
		collision_shape.set_deferred("disabled", false)

	if is_remote_player:
		_remote_target_position = global_position
		_remote_target_velocity = Vector2.ZERO
		_has_remote_target = true
		collision_layer = 1
		collision_mask = 1
		modulate = Color(0.65, 0.9, 1.0, 0.85)
	else:
		_has_remote_target = false
		collision_layer = 1
		collision_mask = 1
		modulate = Color.WHITE

	_update_bubble_effect()


func _update_key_indicator() -> void:
	if carried_key_sprite == null:
		return

	var should_show := key_count > 0
	if should_show and not carried_key_sprite.visible:
		_carried_key_bob_time = 0.0
		carried_key_sprite.position = carried_key_offset

	carried_key_sprite.visible = should_show
	if should_show:
		carried_key_sprite.modulate = carried_key_color
	if not should_show:
		carried_key_sprite.position = carried_key_offset
		carried_key_sprite.modulate = Color.WHITE


func _update_oxygen(delta: float) -> void:
	if is_remote_player or max_oxygen <= 0.0:
		return

	var previous_oxygen := oxygen
	if is_in_water():
		oxygen = maxf(oxygen - get_water_oxygen_drain_rate() * delta, 0.0)
		if previous_oxygen > 0.0 and oxygen <= 0.0:
			if _is_online_session():
				if not _oxygen_depleted_pending:
					_oxygen_depleted_pending = true
					oxygen_depleted.emit()
			else:
				die()
	else:
		oxygen = minf(oxygen + oxygen_recovery_rate * delta, max_oxygen)
		if oxygen > 0.0:
			_oxygen_depleted_pending = false

	if not is_equal_approx(previous_oxygen, oxygen):
		oxygen_changed.emit(oxygen, max_oxygen)


func _update_bubble_effect() -> void:
	if bubble_effect == null:
		return

	var should_play := is_in_water()
	bubble_effect.visible = should_play
	if should_play:
		if not bubble_effect.is_playing():
			bubble_effect.play("bubble")
	else:
		bubble_effect.stop()


func _apply_pending_water_jet(delta: float) -> void:
	if _water_jet_velocity.is_zero_approx():
		return

	var jet_velocity: Vector2 = consume_water_jet_velocity()
	jet_velocity = _remove_blocked_components_from_water_jet(jet_velocity)
	if jet_velocity.is_zero_approx():
		return

	_applied_water_jet_velocity = jet_velocity
	var jet_direction: Vector2 = jet_velocity.normalized()
	var target_speed: float = minf(jet_velocity.length(), water_jet_max_velocity)
	var current_along: float = velocity.dot(jet_direction)
	var next_along: float = lerpf(
		current_along,
		maxf(current_along, target_speed),
		clampf(water_jet_response * delta, 0.0, 1.0)
	)
	var lateral_velocity: Vector2 = velocity - jet_direction * current_along
	lateral_velocity = lateral_velocity.lerp(
		Vector2.ZERO,
		clampf(water_jet_cross_drag * delta, 0.0, 1.0)
	)
	velocity = lateral_velocity + jet_direction * next_along


func _remove_blocked_components_from_water_jet(jet_velocity: Vector2) -> Vector2:
	if jet_velocity.is_zero_approx():
		return Vector2.ZERO

	var result := jet_velocity
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if collision == null:
			continue

		var normal := collision.get_normal()
		if normal.is_zero_approx():
			continue

		var blocked_amount := result.dot(normal)
		if blocked_amount < -WATER_JET_BLOCKED_DOT_EPSILON:
			result -= normal * blocked_amount

	return result


func _remove_blocked_water_jet_velocity() -> void:
	if _applied_water_jet_velocity.is_zero_approx():
		return

	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if collision == null:
			continue

		var normal := collision.get_normal()
		if normal.is_zero_approx():
			continue

		if _applied_water_jet_velocity.dot(normal) >= -WATER_JET_BLOCKED_DOT_EPSILON:
			continue

		var velocity_into_surface := velocity.dot(normal)
		if velocity_into_surface < 0.0:
			velocity -= normal * velocity_into_surface


func _process_bubble_effects(delta: float) -> void:
	if bubble_effect == null:
		return

	if not is_in_water():
		_bubble_emit_timer = 0.0
		return

	_bubble_emit_timer -= delta
	if _bubble_emit_timer > 0.0:
		return

	var is_swimming: bool = velocity.length() >= bubble_swim_velocity_threshold
	var interval: float = bubble_swim_interval if is_swimming else bubble_breath_interval
	_bubble_emit_timer = interval * _bubble_rng.randf_range(0.75, 1.25)
	_spawn_bubble_burst(is_swimming)


func _spawn_bubble_burst(is_swimming: bool) -> void:
	var count: int = _bubble_rng.randi_range(2, 4) if is_swimming else 1
	for index in range(count):
		var bubble: AnimatedSprite2D = bubble_effect.duplicate() as AnimatedSprite2D
		if bubble == null:
			bubble = BUBBLE_EFFECT_SCENE.instantiate() as AnimatedSprite2D
		if bubble == null:
			continue

		bubble.name = "BubbleTrail"
		add_child(bubble)
		bubble.visible = true
		bubble.position = _get_bubble_spawn_offset(is_swimming)
		bubble.scale = bubble_effect.scale * _bubble_rng.randf_range(0.65, 1.25)
		bubble.speed_scale = _bubble_rng.randf_range(0.75, 1.35)
		bubble.modulate = Color(1.0, 1.0, 1.0, _bubble_rng.randf_range(0.55, 0.9))
		bubble.play("bubble")

		var drift: Vector2 = _get_bubble_drift(is_swimming)
		var lifetime: float = bubble_trail_lifetime * _bubble_rng.randf_range(0.75, 1.25)
		var tween: Tween = create_tween()
		tween.tween_property(bubble, "position", bubble.position + drift, lifetime)
		tween.parallel().tween_property(bubble, "modulate:a", 0.0, lifetime)
		tween.tween_callback(bubble.queue_free)


func _get_bubble_spawn_offset(is_swimming: bool) -> Vector2:
	if not is_swimming:
		return Vector2(
			_bubble_rng.randf_range(-5.0, 5.0),
			_bubble_rng.randf_range(-38.0, -28.0)
		)

	var trail_side: float = -1.0
	if not is_zero_approx(velocity.x):
		trail_side = -signf(velocity.x)
	else:
		var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
		if sprite != null:
			trail_side = -1.0 if sprite.flip_h else 1.0

	return Vector2(
		trail_side * _bubble_rng.randf_range(8.0, 18.0),
		_bubble_rng.randf_range(-34.0, -16.0)
	)


func _get_bubble_drift(is_swimming: bool) -> Vector2:
	if not is_swimming:
		return Vector2(
			_bubble_rng.randf_range(-12.0, 12.0),
			_bubble_rng.randf_range(-42.0, -22.0)
		)

	var horizontal_drift: float = -signf(velocity.x) * _bubble_rng.randf_range(10.0, 28.0)
	if is_zero_approx(velocity.x):
		horizontal_drift = _bubble_rng.randf_range(-14.0, 14.0)

	return Vector2(
		horizontal_drift,
		_bubble_rng.randf_range(-28.0, -10.0)
	)


func _prune_water_zones() -> void:
	for index in range(_water_zones.size() - 1, -1, -1):
		if not is_instance_valid(_water_zones[index]):
			_water_zones.remove_at(index)


func _is_online_session() -> bool:
	var network_client := get_node_or_null("/root/NetworkClient")
	if network_client == null or not network_client.has_method("get_current_room"):
		return false

	var current_room = network_client.get_current_room()
	return typeof(current_room) == TYPE_DICTIONARY and not current_room.is_empty()


func _apply_sprite_sheet_for_animation(animation: String) -> void:
	if animation.begins_with("swim"):
		_apply_sprite_sheet(
			SWIM_SPRITE_TEXTURE,
			SWIM_SPRITE_HFRAMES,
			SWIM_SPRITE_VFRAMES,
			SWIM_SPRITE_POSITION,
			SWIM_SPRITE_SCALE
		)
	else:
		_apply_sprite_sheet(
			LAND_SPRITE_TEXTURE,
			LAND_SPRITE_HFRAMES,
			LAND_SPRITE_VFRAMES,
			LAND_SPRITE_POSITION,
			LAND_SPRITE_SCALE
		)


func _apply_sprite_sheet(
	texture: Texture2D,
	hframes: int,
	vframes: int,
	sprite_position: Vector2,
	sprite_scale: Vector2
) -> void:
	var sprite := get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null:
		return

	sprite.texture = texture
	sprite.hframes = hframes
	sprite.vframes = vframes
	sprite.position = sprite_position
	sprite.scale = sprite_scale

	var max_frame := hframes * vframes
	if max_frame > 0 and sprite.frame >= max_frame:
		sprite.frame = 0


func apply_push_forces() -> void:
	if is_remote_player:
		return

	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if collision == null:
			continue

		var body := collision.get_collider() as RigidBody2D
		if body == null or not body.is_in_group("pushable"):
			continue

		var normal := collision.get_normal()
		var lateral_push := -normal.x
		if absf(lateral_push) < 0.01:
			continue

		var strength := maxf(absf(velocity.x), SPEED * 0.6) * PUSH_FORCE
		body.apply_central_force(Vector2(lateral_push * strength, 0.0))
		body.sleeping = false

		var target_x := lateral_push * maxf(absf(velocity.x), SPEED * 0.65)
		var next_velocity := body.linear_velocity
		next_velocity.x = lerpf(next_velocity.x, target_x, 0.35)
		body.linear_velocity = next_velocity


func _uses_network_push_intents() -> bool:
	if is_remote_player:
		return false

	var network_client := get_node_or_null("/root/NetworkClient")
	return network_client != null and not network_client.get_current_room().is_empty()


func _collect_push_intents() -> void:
	if is_remote_player:
		return

	_push_intents.clear()
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		if collision == null:
			continue

		var body := collision.get_collider() as Node
		if body == null or not body.is_in_group("pushable"):
			continue

		var normal := collision.get_normal()
		var lateral_push := -normal.x
		if absf(lateral_push) < 0.01:
			continue

		var target_id := body.name
		if "sync_id" in body and not String(body.sync_id).strip_edges().is_empty():
			target_id = String(body.sync_id).strip_edges()

		_push_intents[target_id] = {
			"target_id": target_id,
			"node_name": body.name,
			"direction": signf(lateral_push),
			"strength": clampf(absf(velocity.x) / maxf(SPEED, 0.001), 0.35, 1.0),
		}


func _follow_remote_target(delta: float) -> void:
	var offset := _remote_target_position - global_position
	if offset.length() > remote_snap_distance:
		global_position = _remote_target_position
		velocity = _remote_target_velocity
		return

	var desired_velocity := _remote_target_velocity + (offset / maxf(delta, 0.001)) / remote_reconciliation_gain
	velocity = desired_velocity
	move_and_slide()


func _vector_to_packet(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


func _color_to_packet(value: Color) -> Dictionary:
	return {
		"r": value.r,
		"g": value.g,
		"b": value.b,
		"a": value.a,
	}


func _packet_to_color(raw_value, fallback: Color) -> Color:
	if typeof(raw_value) != TYPE_DICTIONARY:
		return fallback

	var data: Dictionary = raw_value
	return Color(
		float(data.get("r", fallback.r)),
		float(data.get("g", fallback.g)),
		float(data.get("b", fallback.b)),
		float(data.get("a", fallback.a))
	)


func _packet_to_vector(raw_value, fallback: Vector2) -> Vector2:
	if typeof(raw_value) == TYPE_DICTIONARY:
		var data: Dictionary = raw_value
		return Vector2(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)))

	if typeof(raw_value) == TYPE_ARRAY and raw_value.size() >= 2:
		return Vector2(float(raw_value[0]), float(raw_value[1]))

	return fallback
