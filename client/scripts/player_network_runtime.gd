extends RefCounted
class_name PlayerNetworkRuntime

const PacketCodec = preload("res://scripts/network/packet_codec.gd")
const PlayerSnapshot = preload("res://scripts/player/player_snapshot.gd")

var _owner: CharacterBody2D
var _state_machine: Node
var _player_collision_shape: CollisionShape2D
var _visual: PlayerVisual
var _inventory: PlayerInventory
var _remote_snap_distance := 48.0
var _remote_reconciliation_gain := 14.0
var _remote_target_position := Vector2.ZERO
var _remote_target_velocity := Vector2.ZERO
var _has_remote_target := false


func setup(
	owner: CharacterBody2D,
	state_machine: Node,
	player_collision_shape: CollisionShape2D,
	visual: PlayerVisual,
	inventory: PlayerInventory,
	remote_snap_distance: float,
	remote_reconciliation_gain: float
) -> void:
	_owner = owner
	_state_machine = state_machine
	_player_collision_shape = player_collision_shape
	_visual = visual
	_inventory = inventory
	_remote_snap_distance = remote_snap_distance
	_remote_reconciliation_gain = remote_reconciliation_gain


func apply_control_mode(is_remote_player: bool, input_enabled: bool, update_elimination_state: Callable) -> void:
	if _owner == null:
		return

	if is_remote_player:
		_owner.remove_from_group("player")
		_owner.add_to_group("remote_player")
	else:
		_owner.remove_from_group("remote_player")
		_owner.add_to_group("player")

	var controls_enabled := not is_remote_player and input_enabled
	if _state_machine != null:
		_state_machine.set_process(controls_enabled)
		_state_machine.set_physics_process(controls_enabled)
		_state_machine.set_process_unhandled_input(controls_enabled)

	if _player_collision_shape != null:
		_player_collision_shape.set_deferred("disabled", false)

	if is_remote_player:
		_remote_target_position = _owner.global_position
		_remote_target_velocity = Vector2.ZERO
		_has_remote_target = true
		_owner.collision_layer = 1
		_owner.collision_mask = 1
		_owner.modulate = Color(0.65, 0.9, 1.0, 0.85)
		if _visual != null:
			_visual.set_mirror_facing_for_remote(true)
	else:
		_has_remote_target = false
		_owner.collision_layer = 1
		_owner.collision_mask = 1
		_owner.modulate = Color.WHITE
		if _visual != null:
			_visual.set_mirror_facing_for_remote(false)

	if update_elimination_state.is_valid():
		update_elimination_state.call()


func sync_remote_target_with_owner(is_remote_player: bool) -> void:
	if _owner == null:
		return

	_remote_target_position = _owner.global_position
	_remote_target_velocity = Vector2.ZERO
	_has_remote_target = is_remote_player


func has_remote_target() -> bool:
	return _has_remote_target


func get_network_state(level_index: int) -> Dictionary:
	if _owner == null:
		return {}

	var snapshot := PlayerSnapshot.capture_local(_owner, level_index)
	if _inventory != null:
		snapshot.carried_key_color = _inventory.carried_key_color
	return snapshot.to_network_dict()


func apply_network_state(state: Dictionary, is_remote_player: bool) -> void:
	if _owner == null:
		return

	var next_position := PacketCodec.packet_to_vector(state.get("position", {}), _owner.global_position)
	var next_velocity := PacketCodec.packet_to_vector(state.get("velocity", {}), _owner.velocity)
	if is_remote_player:
		_remote_target_position = next_position
		_remote_target_velocity = next_velocity
		_has_remote_target = true
		if _owner.global_position.distance_to(_remote_target_position) > _remote_snap_distance:
			_owner.global_position = _remote_target_position
			_owner.velocity = _remote_target_velocity
	else:
		_owner.global_position = next_position
		_owner.velocity = next_velocity

	if _visual != null:
		_visual.set_flip_h(bool(state.get("flip_h", _visual.get_flip_h())))

	var animation := String(state.get("animation", ""))
	if not animation.is_empty():
		if _visual != null:
			_visual.play_animation(animation)
		elif _owner.has_method("play_player_animation"):
			_owner.call("play_player_animation", animation)

	if _inventory != null:
		_inventory.key_count = int(state.get("key_count", _inventory.key_count))
		_inventory.carried_key_color = PacketCodec.packet_to_color(
			state.get("carried_key_color", {}),
			_inventory.carried_key_color
		)
		_inventory.update_key_indicator()


func follow_remote_target(delta: float) -> void:
	if _owner == null or not _has_remote_target:
		return

	var offset := _remote_target_position - _owner.global_position
	if offset.length() > _remote_snap_distance:
		_owner.global_position = _remote_target_position
		_owner.velocity = _remote_target_velocity
		return

	var desired_velocity := _remote_target_velocity + (offset / maxf(delta, 0.001)) / _remote_reconciliation_gain
	_owner.velocity = desired_velocity
	_owner.move_and_slide()
