extends Node
class_name PlayerSodaHost

const PlayerSnapshot = preload("res://scripts/player/player_snapshot.gd")

var _soda: PlayerSoda
var profile: PlayerSodaProfile

var _audio: PlayerAudio
var _visual: PlayerVisual
var _inventory: PlayerInventory
var _movement: PlayerMovement
var _nameplate: PlayerNameplate
var _water: PlayerWaterComponent
var _bubble: PlayerBubbleComponent
var _network: PlayerNetworkComponent
var _movement_config: PlayerMovementConfig


func initialize(player: PlayerSoda, soda_profile: PlayerSodaProfile, scene_refs: Dictionary) -> void:
	_soda = player
	profile = soda_profile.ensure_defaults()
	_movement_config = profile.movement

	_visual = PlayerVisual.new()
	_visual.name = "PlayerVisual"
	add_child(_visual)
	_visual.setup(player, scene_refs.get("sprite"), scene_refs.get("animation_player"))

	_inventory = PlayerInventory.new()
	_inventory.name = "PlayerInventory"
	add_child(_inventory)
	_inventory.setup(scene_refs.get("carried_key_sprite"), scene_refs.get("torch_light"))

	_audio = PlayerAudio.new()
	_audio.name = "PlayerAudio"
	add_child(_audio)
	_audio.setup(
		scene_refs.get("jump_sfx"),
		scene_refs.get("land_sfx"),
		scene_refs.get("death_sfx"),
		scene_refs.get("respawn_sfx"),
		scene_refs.get("key_pickup_sfx"),
		scene_refs.get("walk_run_sfx")
	)

	_nameplate = PlayerNameplate.new()
	_nameplate.name = "PlayerNameplate"
	add_child(_nameplate)
	_nameplate.setup(player, scene_refs.get("name_label"))

	_water = PlayerWaterComponent.new()
	_water.name = "PlayerWater"
	add_child(_water)

	_bubble = PlayerBubbleComponent.new()
	_bubble.name = "PlayerBubble"
	add_child(_bubble)

	_movement = PlayerMovement.new()
	_movement.name = "PlayerMovement"
	add_child(_movement)

	_apply_profile_tuning()
	_water.setup(player, Callable(_bubble, "update_visibility"))
	_bubble.setup(player, scene_refs.get("bubble_effect"), _visual, _water)
	_movement.setup(player, _movement_config, _water)

	_network = PlayerNetworkComponent.new()
	_network.name = "PlayerNetwork"
	add_child(_network)
	_network.remote_reconciliation_gain = profile.remote_reconciliation_gain
	_network.remote_snap_distance = profile.remote_snap_distance
	_network.setup(
		player,
		scene_refs.get("state_machine"),
		scene_refs.get("player_collision_shape"),
		_visual,
		_inventory
	)


func on_ready() -> void:
	_soda.spawn_position = _soda.global_position
	_soda.max_oxygen = profile.max_oxygen
	_soda.oxygen = profile.max_oxygen
	_soda.oxygen_changed.emit(_soda.oxygen, _soda.max_oxygen)
	apply_network_control_mode()
	connect_state_machine_audio()
	sync_legacy_inventory_vars()
	sync_torch_vars()


func on_exit_tree() -> void:
	if _audio != null:
		_audio.stop_all()


func process_frame(delta: float) -> void:
	if _water != null:
		_water.process(delta, _soda.is_remote_player, _soda.is_eliminated_flag())
		sync_oxygen_from_owner()

	if _bubble != null:
		_bubble.process(delta)

	if _nameplate != null:
		_nameplate.process_frame()

	if _inventory != null:
		_inventory.process(delta)


func physics_tick(delta: float) -> void:
	if not _soda.is_remote_player or _network == null or not _network.has_remote_target():
		return
	_network.follow_remote_target(delta)


func set_network_identity(peer_id: int, player_name: String = "") -> void:
	_soda.network_peer_id = peer_id
	_soda.display_name = player_name
	if _nameplate != null:
		_nameplate.set_display_name(player_name)


func set_network_remote(remote: bool) -> void:
	_soda.is_remote_player = remote
	if _audio != null:
		_audio.set_remote_player(remote)
	if _nameplate != null:
		_nameplate.set_remote_player(remote)
	if _movement != null:
		_movement.set_remote_player(remote)
	apply_network_control_mode()


func set_input_enabled(enabled: bool) -> void:
	_soda.input_enabled = enabled
	apply_network_control_mode()


func set_eliminated(eliminated: bool) -> void:
	_soda.set_eliminated_flag(eliminated)
	if eliminated and _audio != null:
		_audio.stop_walk_run_sfx()
	update_elimination_state()


func die() -> void:
	if _audio != null:
		_audio.stop_walk_run_sfx()
		_audio.play_death_sfx()
	_soda.died.emit()
	respawn()


func respawn() -> void:
	if _audio != null:
		_audio.stop_walk_run_sfx()
		_audio.play_respawn_sfx()
	_soda.set_eliminated_flag(false)
	update_elimination_state()
	_soda.global_position = _soda.spawn_position
	_soda.velocity = Vector2.ZERO
	if _bubble != null:
		_bubble.reset()
	var was_in_water := _water.reset_after_respawn() if _water != null else false
	if was_in_water:
		_soda.water_state_changed.emit(false)
	if _bubble != null:
		_bubble.update_visibility()
	if _network != null:
		_network.sync_remote_target_with_owner(_soda.is_remote_player)


func reset_oxygen() -> void:
	if _water != null:
		_water.reset_oxygen()
	sync_oxygen_from_owner()


func enter_water_zone(zone: Area2D) -> void:
	if _water != null:
		_water.enter_water_zone(zone)


func exit_water_zone(zone: Area2D) -> void:
	if _water != null:
		_water.exit_water_zone(zone)


func is_in_water() -> bool:
	return _water != null and _water.is_in_water()


func get_water_current_velocity() -> Vector2:
	return _water.get_water_current_velocity() if _water != null else Vector2.ZERO


func get_water_swim_speed_multiplier() -> float:
	return _water.get_water_swim_speed_multiplier() if _water != null else 1.0


func get_water_oxygen_drain_rate() -> float:
	return _water.get_water_oxygen_drain_rate() if _water != null else 0.0


func add_oxygen(amount: float) -> void:
	if _water != null:
		_water.add_oxygen(amount)
	sync_oxygen_from_owner()


func apply_water_jet_velocity(jet_velocity: Vector2, _delta: float) -> void:
	if _water != null:
		_water.apply_water_jet_velocity(jet_velocity, _soda.is_remote_player)


func consume_water_jet_velocity() -> Vector2:
	return _water.consume_water_jet_velocity() if _water != null else Vector2.ZERO


func move_and_push() -> void:
	if _movement != null:
		_movement.move_and_push()


func set_key_count(value: int) -> void:
	if _inventory != null:
		_inventory.set_key_count(value)
	sync_legacy_inventory_vars()


func set_oxygen_state(current: float, maximum: float) -> void:
	var safe_maximum := maxf(maximum, 0.0)
	var safe_current := clampf(current, 0.0, safe_maximum)
	var changed := not is_equal_approx(_soda.max_oxygen, safe_maximum) or not is_equal_approx(_soda.oxygen, safe_current)
	_soda.max_oxygen = safe_maximum
	_soda.oxygen = safe_current
	if _water != null:
		_water.sync_oxygen_state(safe_current, safe_maximum)
	if changed:
		_soda.oxygen_changed.emit(_soda.oxygen, _soda.max_oxygen)


func apply_runtime_state(state: Dictionary) -> void:
	PlayerSnapshot.apply_runtime_dict(_soda, state)
	sync_legacy_inventory_vars()


func collect_key(amount: int = 1, key_color: Color = Color.WHITE) -> void:
	if _inventory != null:
		_inventory.collect_key(amount, key_color)
	sync_legacy_inventory_vars()
	if _audio != null:
		_audio.play_key_pickup_sfx()


func collect_torch() -> void:
	if _inventory != null:
		_inventory.collect_torch()
	sync_torch_vars()


func add_light_buff() -> void:
	if _inventory != null:
		_inventory.add_light_buff()
	sync_torch_vars()


func set_carried_key_color(key_color: Color) -> void:
	if _inventory != null:
		_inventory.set_carried_key_color(key_color)
	sync_legacy_inventory_vars()


func has_key() -> bool:
	return _inventory.has_key() if _inventory != null else false


func use_key(amount: int = 1) -> bool:
	if _inventory == null:
		return false
	var used := _inventory.use_key(amount)
	sync_legacy_inventory_vars()
	return used


func play_player_animation(animation: String) -> void:
	if _visual != null:
		_visual.play_animation(animation)


func get_visual_animation() -> String:
	return _visual.get_animation() if _visual != null else ""


func get_visual_flip_h() -> bool:
	return _visual.get_flip_h() if _visual != null else false


func set_visual_flip_h(flipped: bool) -> void:
	if _visual != null:
		_visual.set_flip_h(flipped)


func set_facing_direction(direction: float) -> void:
	if _visual != null:
		_visual.set_facing_direction(direction)


func get_facing_direction() -> float:
	return _visual.get_facing_direction() if _visual != null else 1.0


func set_sprite_vertical_flip(flipped: bool) -> void:
	if _visual != null:
		_visual.set_vertical_flip(flipped)


func apply_remote_kinematics(target_position: Vector2, target_velocity: Vector2) -> void:
	_soda.global_position = target_position
	_soda.velocity = target_velocity


func consume_push_intents() -> Array[Dictionary]:
	return _movement.consume_push_intents() if _movement != null else []


func get_network_state(level_index: int) -> Dictionary:
	return _network.get_network_state(level_index) if _network != null else {}


func apply_network_state(state: Dictionary) -> void:
	if _network != null:
		_network.apply_network_state(state, _soda.is_remote_player)
	sync_legacy_inventory_vars()


func turn_off_light() -> void:
	if _inventory != null:
		_inventory.turn_off_light()
	sync_torch_vars()


func sync_legacy_inventory_vars() -> void:
	if _inventory == null:
		return
	_soda.key_count = _inventory.key_count
	_soda.carried_key_color = _inventory.carried_key_color


func sync_torch_vars() -> void:
	if _inventory == null:
		return
	_soda.has_torch = _inventory.has_torch
	_soda.current_light_scale = _inventory.current_light_scale


func connect_state_machine_audio() -> void:
	var state_machine: Node = _soda.state_machine
	if state_machine == null or _audio == null:
		return
	if not state_machine.has_signal("state_transitioned"):
		return
	var transition_callback := Callable(_audio, "on_state_transitioned")
	if not state_machine.is_connected("state_transitioned", transition_callback):
		state_machine.connect("state_transitioned", transition_callback)


func apply_network_control_mode() -> void:
	if _network != null:
		_network.apply_control_mode(_soda.is_remote_player, _soda.input_enabled, Callable(self, "update_elimination_state"))
	if _audio != null:
		_audio.set_remote_player(_soda.is_remote_player)


func update_elimination_state() -> void:
	if _soda.player_collision_shape != null:
		_soda.player_collision_shape.set_deferred("disabled", _soda.is_eliminated_flag())

	_soda.visible = not _soda.is_eliminated_flag()
	if _soda.is_eliminated_flag():
		_soda.velocity = Vector2.ZERO

	if _bubble != null:
		_bubble.update_visibility()


func sync_oxygen_from_owner() -> void:
	var next_oxygen := float(_soda.get("oxygen"))
	var next_max := float(_soda.get("max_oxygen"))
	if not is_equal_approx(_soda.oxygen, next_oxygen):
		_soda.oxygen = next_oxygen
	if not is_equal_approx(_soda.max_oxygen, next_max):
		_soda.max_oxygen = next_max


func _apply_profile_tuning() -> void:
	if _water != null:
		_water.oxygen_recovery_rate = profile.oxygen_recovery_rate
		_water.default_oxygen_drain_rate = profile.default_oxygen_drain_rate
		_water.water_jet_response = profile.water_jet_response
		_water.water_jet_cross_drag = profile.water_jet_cross_drag
		_water.water_jet_max_velocity = profile.water_jet_max_velocity
		_water.water_jet_upward_lift_ratio = profile.water_jet_upward_lift_ratio
		_water.water_jet_upward_max_lift_speed = profile.water_jet_upward_max_lift_speed
		_water.water_jet_upward_lift_stop_speed = profile.water_jet_upward_lift_stop_speed
		_water.water_jet_upward_side_ratio = profile.water_jet_upward_side_ratio
		_water.water_jet_upward_side_min_speed = profile.water_jet_upward_side_min_speed
		_water.water_jet_upward_side_max_speed = profile.water_jet_upward_side_max_speed

	if _bubble != null:
		_bubble.bubble_breath_interval = profile.bubble_breath_interval
		_bubble.bubble_swim_interval = profile.bubble_swim_interval
		_bubble.bubble_swim_velocity_threshold = profile.bubble_swim_velocity_threshold
		_bubble.bubble_trail_lifetime = profile.bubble_trail_lifetime
