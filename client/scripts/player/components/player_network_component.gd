extends Node
class_name PlayerNetworkComponent

const PlayerNetworkRuntime = preload("res://scripts/player_network_runtime.gd")

@export var remote_reconciliation_gain := 14.0
@export var remote_snap_distance := 48.0

var _owner: CharacterBody2D
var _runtime: PlayerNetworkRuntime


func setup(
	owner: CharacterBody2D,
	state_machine: Node,
	collision_shape: CollisionShape2D,
	visual: PlayerVisual,
	inventory: PlayerInventory
) -> void:
	_owner = owner
	_runtime = PlayerNetworkRuntime.new()
	_runtime.setup(
		owner,
		state_machine,
		collision_shape,
		visual,
		inventory,
		remote_snap_distance,
		remote_reconciliation_gain
	)


func apply_control_mode(is_remote_player: bool, input_enabled: bool, update_elimination_state: Callable) -> void:
	if _runtime != null:
		_runtime.apply_control_mode(is_remote_player, input_enabled, update_elimination_state)


func sync_remote_target_with_owner(is_remote_player: bool) -> void:
	if _runtime != null:
		_runtime.sync_remote_target_with_owner(is_remote_player)


func has_remote_target() -> bool:
	return _runtime != null and _runtime.has_remote_target()


func follow_remote_target(delta: float) -> void:
	if _runtime != null:
		_runtime.follow_remote_target(delta)


func get_network_state(level_index: int) -> Dictionary:
	return _runtime.get_network_state(level_index) if _runtime != null else {}


func apply_network_state(state: Dictionary, is_remote_player: bool) -> void:
	if _runtime != null:
		_runtime.apply_network_state(state, is_remote_player)
