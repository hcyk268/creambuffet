extends Node
class_name PlayerMovement

const PlayerMovementConfig = preload("res://scripts/player/player_movement_config.gd")

var _owner: CharacterBody2D
var _config: PlayerMovementConfig
var _water: Node
var _push_intents: Dictionary = {}
var _is_remote_player := false


func setup(owner: CharacterBody2D, config: PlayerMovementConfig, water_component: Node) -> void:
	_owner = owner
	_config = config
	_water = water_component


func set_remote_player(remote: bool) -> void:
	_is_remote_player = remote


func get_speed() -> float:
	return _config.speed if _config != null else 150.0


func get_jump_velocity() -> float:
	return _config.jump_velocity if _config != null else -300.0


func get_push_force() -> float:
	return _config.push_force if _config != null else 8.0


func move_and_push() -> void:
	if _owner == null:
		return

	if _water != null and _water.has_method("prepare_move"):
		_water.call("prepare_move", _owner.get_physics_process_delta_time())

	_owner.move_and_slide()

	if _uses_network_push_intents():
		_collect_push_intents()
	else:
		apply_push_forces()

	if _water != null and _water.has_method("finish_move"):
		_water.call("finish_move")


func consume_push_intents() -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	for raw_value in _push_intents.values():
		if typeof(raw_value) != TYPE_DICTIONARY:
			continue
		intents.append(Dictionary(raw_value).duplicate(true))

	_push_intents.clear()
	return intents


func apply_push_forces() -> void:
	if _owner == null or _is_remote_player:
		return

	var speed := get_speed()
	var push_force := get_push_force()
	for i in range(_owner.get_slide_collision_count()):
		var collision := _owner.get_slide_collision(i)
		if collision == null:
			continue

		var body := collision.get_collider() as RigidBody2D
		if body == null or not body.is_in_group("pushable"):
			continue

		var normal := collision.get_normal()
		var lateral_push := -normal.x
		if absf(lateral_push) < 0.01:
			continue

		var strength := maxf(absf(_owner.velocity.x), speed * 0.6) * push_force
		body.apply_central_force(Vector2(lateral_push * strength, 0.0))
		body.sleeping = false

		var target_x := lateral_push * maxf(absf(_owner.velocity.x), speed * 0.65)
		var next_velocity := body.linear_velocity
		next_velocity.x = lerpf(next_velocity.x, target_x, 0.35)
		body.linear_velocity = next_velocity


func _uses_network_push_intents() -> bool:
	if _is_remote_player:
		return false

	var network_client := get_node_or_null("/root/NetworkClient")
	return network_client != null and not network_client.get_current_room().is_empty()


func _collect_push_intents() -> void:
	if _owner == null or _is_remote_player:
		return

	_push_intents.clear()
	var speed := get_speed()
	for i in range(_owner.get_slide_collision_count()):
		var collision := _owner.get_slide_collision(i)
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
			"strength": clampf(absf(_owner.velocity.x) / maxf(speed, 0.001), 0.35, 1.0),
		}
