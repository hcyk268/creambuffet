extends CharacterBody2D

signal died

@export var SPEED := 150.0
@export var JUMP_VELOCITY := -300.0
@export var PUSH_FORCE := 8.0
@export var carried_key_offset := Vector2(0, -46)
@export var carried_key_bob_amplitude := 2.0
@export var carried_key_bob_speed := 5.0
@export var remote_reconciliation_gain := 14.0
@export var remote_snap_distance := 48.0

@onready var carried_key_sprite: Sprite2D = get_node_or_null("CarriedKey") as Sprite2D

var spawn_position: Vector2
var key_count := 0
var network_peer_id := 0
var display_name := ""
var is_remote_player := false
var input_enabled := true
var _carried_key_bob_time := 0.0
var _push_intents: Dictionary = {}
var _remote_target_position := Vector2.ZERO
var _remote_target_velocity := Vector2.ZERO
var _has_remote_target := false
var _is_eliminated := false


func _ready() -> void:
	_apply_network_control_mode()
	_update_key_indicator()
	spawn_position = global_position


func _process(delta: float) -> void:
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


func set_eliminated(eliminated: bool) -> void:
	_is_eliminated = eliminated
	_update_elimination_state()


func is_eliminated() -> bool:
	return _is_eliminated


func die() -> void:
	died.emit()
	respawn()


func respawn() -> void:
	_is_eliminated = false
	_update_elimination_state()
	global_position = spawn_position
	velocity = Vector2.ZERO
	_remote_target_position = global_position
	_remote_target_velocity = Vector2.ZERO
	_has_remote_target = is_remote_player


func move_and_push() -> void:
	move_and_slide()
	if _uses_network_push_intents():
		_collect_push_intents()
	else:
		apply_push_forces()


func set_key_count(value: int) -> void:
	key_count = max(value, 0)
	_update_key_indicator()


func collect_key(amount: int = 1) -> void:
	key_count += amount
	_update_key_indicator()


func has_key() -> bool:
	return key_count > 0


func use_key(amount: int = 1) -> bool:
	if key_count < amount:
		return false

	key_count -= amount
	_update_key_indicator()
	return true


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
			anim_player.play(animation)

	key_count = int(state.get("key_count", key_count))
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
	_update_elimination_state()


func _update_elimination_state() -> void:
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null:
		collision_shape.set_deferred("disabled", _is_eliminated)

	visible = not _is_eliminated
	if _is_eliminated:
		velocity = Vector2.ZERO
		_remote_target_velocity = Vector2.ZERO


func _update_key_indicator() -> void:
	if carried_key_sprite == null:
		return

	var should_show := key_count > 0
	if should_show and not carried_key_sprite.visible:
		_carried_key_bob_time = 0.0
		carried_key_sprite.position = carried_key_offset

	carried_key_sprite.visible = should_show
	if not should_show:
		carried_key_sprite.position = carried_key_offset


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


func _packet_to_vector(raw_value, fallback: Vector2) -> Vector2:
	if typeof(raw_value) == TYPE_DICTIONARY:
		var data: Dictionary = raw_value
		return Vector2(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)))

	if typeof(raw_value) == TYPE_ARRAY and raw_value.size() >= 2:
		return Vector2(float(raw_value[0]), float(raw_value[1]))

	return fallback
