extends CharacterBody2D

signal died

@export var SPEED := 150.0
@export var JUMP_VELOCITY := -300.0
@export var carried_key_offset := Vector2(0, -46)
@export var carried_key_bob_amplitude := 2.0
@export var carried_key_bob_speed := 5.0

@onready var carried_key_sprite: Sprite2D = get_node_or_null("CarriedKey") as Sprite2D

var spawn_position: Vector2
var key_count := 0
var network_peer_id := 0
var display_name := ""
var is_remote_player := false
var input_enabled := true
var _carried_key_bob_time := 0.0


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
		"peer_id": network_peer_id,
		"display_name": display_name,
		"level_index": level_index,
		"position": _vector_to_packet(global_position),
		"velocity": _vector_to_packet(velocity),
		"animation": animation,
		"flip_h": flip_h,
		"key_count": key_count,
	}


func apply_network_state(state: Dictionary) -> void:
	global_position = _packet_to_vector(state.get("position", {}), global_position)
	velocity = _packet_to_vector(state.get("velocity", {}), velocity)

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
		collision_shape.set_deferred("disabled", is_remote_player)

	if is_remote_player:
		collision_layer = 0
		collision_mask = 0
		modulate = Color(0.65, 0.9, 1.0, 0.85)
	else:
		collision_layer = 1
		collision_mask = 1
		modulate = Color.WHITE


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
