extends Node
class_name PlayerWaterComponent

const PlayerWaterRuntime = preload("res://scripts/player_water_runtime.gd")

@export var oxygen_recovery_rate := 3.0
@export var default_oxygen_drain_rate := 1.0
@export var water_jet_response := 14.0
@export var water_jet_cross_drag := 2.5
@export var water_jet_max_velocity := 760.0
@export var water_jet_upward_lift_ratio := 0.16
@export var water_jet_upward_max_lift_speed := 78.0
@export var water_jet_upward_lift_stop_speed := 45.0
@export var water_jet_upward_side_ratio := 0.72
@export var water_jet_upward_side_min_speed := 180.0
@export var water_jet_upward_side_max_speed := 280.0

const WATER_JET_BLOCKED_DOT_EPSILON := 0.01

var _owner: CharacterBody2D
var _runtime: PlayerWaterRuntime
var _bubble_rng := RandomNumberGenerator.new()


func setup(owner: CharacterBody2D, bubble_refresh_callback: Callable) -> void:
	_owner = owner
	_bubble_rng.randomize()
	_runtime = PlayerWaterRuntime.new()
	_runtime.setup(
		owner,
		bubble_refresh_callback,
		default_oxygen_drain_rate,
		oxygen_recovery_rate,
		water_jet_response,
		water_jet_cross_drag,
		water_jet_max_velocity,
		water_jet_upward_lift_ratio,
		water_jet_upward_max_lift_speed,
		water_jet_upward_lift_stop_speed,
		water_jet_upward_side_ratio,
		water_jet_upward_side_min_speed,
		water_jet_upward_side_max_speed,
		WATER_JET_BLOCKED_DOT_EPSILON
	)
	_runtime.set_water_jet_side_sign(_random_water_jet_side_sign())


func process(delta: float, is_remote_player: bool, is_eliminated: bool) -> void:
	if _runtime != null:
		_runtime.update_oxygen(delta, is_remote_player, is_eliminated, _is_online_session())


func enter_water_zone(zone: Area2D) -> void:
	if _runtime != null:
		_runtime.enter_water_zone(zone)


func exit_water_zone(zone: Area2D) -> void:
	if _runtime != null:
		_runtime.exit_water_zone(zone)


func is_in_water() -> bool:
	return _runtime != null and _runtime.is_in_water()


func get_water_current_velocity() -> Vector2:
	return _runtime.get_water_current_velocity() if _runtime != null else Vector2.ZERO


func get_water_swim_speed_multiplier() -> float:
	return _runtime.get_water_swim_speed_multiplier() if _runtime != null else 1.0


func get_water_oxygen_drain_rate() -> float:
	return _runtime.get_water_oxygen_drain_rate() if _runtime != null else 0.0


func add_oxygen(amount: float) -> void:
	if _runtime != null:
		_runtime.add_oxygen(amount)


func apply_water_jet_velocity(jet_velocity: Vector2, is_remote_player: bool) -> void:
	if _runtime != null:
		_runtime.apply_water_jet_velocity(jet_velocity, is_remote_player)


func consume_water_jet_velocity() -> Vector2:
	return _runtime.consume_water_jet_velocity() if _runtime != null else Vector2.ZERO


func prepare_move(delta: float) -> void:
	if _runtime != null:
		_runtime.prepare_move(delta)


func finish_move() -> void:
	if _runtime != null:
		_runtime.finish_move()


func reset_oxygen() -> void:
	if _runtime != null:
		_runtime.reset_oxygen()


func reset_after_respawn() -> bool:
	if _runtime == null:
		return false

	_runtime.set_water_jet_side_sign(_random_water_jet_side_sign())
	return _runtime.reset_after_respawn()


func sync_oxygen_state(current: float, maximum: float) -> void:
	if _runtime != null:
		_runtime.sync_oxygen_state(current, maximum)


func prune_water_zones() -> void:
	if _runtime != null:
		_runtime.prune_water_zones()


func _random_water_jet_side_sign() -> float:
	return -1.0 if _bubble_rng.randi_range(0, 1) == 0 else 1.0


func _is_online_session() -> bool:
	var network_client := get_node_or_null("/root/NetworkClient")
	if network_client == null or not network_client.has_method("get_current_room"):
		return false

	var current_room = network_client.get_current_room()
	return typeof(current_room) == TYPE_DICTIONARY and not current_room.is_empty()
