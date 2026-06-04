extends CharacterBody2D

signal died
signal water_state_changed(in_water: bool)
signal oxygen_changed(current: float, maximum: float)
signal oxygen_depleted

const LAND_SPRITE_TEXTURE := preload("res://assets/sprites/Player-Soda.png")
const SWIM_SPRITE_TEXTURE := preload("res://assets/sprites/playerswim.png")
const BUBBLE_EFFECT_SCENE := preload("res://prefabs/bubble_effect.tscn")
const PlayerBubbleEffects = preload("res://scripts/player_bubble_effects.gd")
const PlayerNetworkRuntime = preload("res://scripts/player_network_runtime.gd")
const PlayerWaterRuntime = preload("res://scripts/player_water_runtime.gd")
const LAND_SPRITE_HFRAMES := 5
const LAND_SPRITE_VFRAMES := 6
const SWIM_SPRITE_HFRAMES := 4
const SWIM_SPRITE_VFRAMES := 6
const LAND_SPRITE_POSITION := Vector2(0, -27)
const SWIM_SPRITE_POSITION := Vector2(0, -27)
const LAND_SPRITE_SCALE := Vector2.ONE
const SWIM_SPRITE_SCALE := Vector2(0.1, 0.1)
const WATER_JET_BLOCKED_DOT_EPSILON := 0.01
const NAME_LABEL_OFFSET := Vector2(-120.0, -95.0)

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
@export var water_jet_upward_lift_ratio := 0.16
@export var water_jet_upward_max_lift_speed := 78.0
@export var water_jet_upward_lift_stop_speed := 45.0
@export var water_jet_upward_side_ratio := 0.72
@export var water_jet_upward_side_min_speed := 180.0
@export var water_jet_upward_side_max_speed := 280.0

@onready var carried_key_sprite: Sprite2D = get_node_or_null("CarriedKey") as Sprite2D
@onready var bubble_effect: AnimatedSprite2D = get_node_or_null("BubbleEffect") as AnimatedSprite2D
@onready var name_label: Label = get_node_or_null("NameLabel") as Label
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
@onready var state_machine: Node = get_node_or_null("StateMachine")
@onready var player_collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

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
var _bubble_rng := RandomNumberGenerator.new()
var _is_eliminated := false
var _bubble_effects: PlayerBubbleEffects
var _network_runtime: PlayerNetworkRuntime
var _water_runtime: PlayerWaterRuntime


func _ready() -> void:
	_bubble_rng.randomize()
	_bubble_effects = PlayerBubbleEffects.new()
	_bubble_effects.setup(
		self,
		bubble_effect,
		BUBBLE_EFFECT_SCENE,
		bubble_breath_interval,
		bubble_swim_interval,
		bubble_swim_velocity_threshold,
		bubble_trail_lifetime
	)
	_network_runtime = PlayerNetworkRuntime.new()
	_network_runtime.setup(
		self,
		state_machine,
		player_collision_shape,
		sprite,
		animation_player,
		remote_snap_distance,
		remote_reconciliation_gain
	)
	_water_runtime = PlayerWaterRuntime.new()
	_water_runtime.setup(
		self,
		Callable(self, "_update_bubble_effect"),
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
	_water_runtime.set_water_jet_side_sign(_random_water_jet_side_sign())
	_apply_network_control_mode()
	if name_label != null:
		name_label.top_level = true
	_update_name_label()
	_update_key_indicator()
	_update_bubble_effect()
	spawn_position = global_position
	oxygen = max_oxygen
	oxygen_changed.emit(oxygen, max_oxygen)


func _process(delta: float) -> void:
	_update_oxygen(delta)
	_process_bubble_effects(delta)
	_update_name_label_position()

	if carried_key_sprite == null or not carried_key_sprite.visible:
		return

	_carried_key_bob_time += delta
	carried_key_sprite.position = carried_key_offset + Vector2(
		0,
		sin(_carried_key_bob_time * carried_key_bob_speed) * carried_key_bob_amplitude
	)


func _physics_process(delta: float) -> void:
	if not is_remote_player or _network_runtime == null or not _network_runtime.has_remote_target():
		return

	_network_runtime.follow_remote_target(delta)


func set_network_identity(peer_id: int, player_name: String = "") -> void:
	network_peer_id = peer_id
	display_name = player_name
	_update_name_label()


func set_network_remote(remote: bool) -> void:
	is_remote_player = remote
	_apply_network_control_mode()
	_update_name_label()


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
	if _water_runtime != null:
		_water_runtime.set_water_jet_side_sign(_random_water_jet_side_sign())
	if _bubble_effects != null:
		_bubble_effects.reset()
	var was_in_water := _water_runtime.reset_after_respawn() if _water_runtime != null else false
	if was_in_water:
		water_state_changed.emit(false)
	_update_bubble_effect()
	if _network_runtime != null:
		_network_runtime.sync_remote_target_with_owner(is_remote_player)


func reset_oxygen() -> void:
	if _water_runtime != null:
		_water_runtime.reset_oxygen()


func enter_water_zone(zone: Area2D) -> void:
	if _water_runtime != null:
		_water_runtime.enter_water_zone(zone)


func exit_water_zone(zone: Area2D) -> void:
	if _water_runtime != null:
		_water_runtime.exit_water_zone(zone)


func enter_water(zone: Area2D) -> void:
	enter_water_zone(zone)


func exit_water(zone: Area2D) -> void:
	exit_water_zone(zone)


func is_in_water() -> bool:
	return _water_runtime != null and _water_runtime.is_in_water()


func get_water_current_velocity() -> Vector2:
	return _water_runtime.get_water_current_velocity() if _water_runtime != null else Vector2.ZERO


func get_water_swim_speed_multiplier() -> float:
	return _water_runtime.get_water_swim_speed_multiplier() if _water_runtime != null else 1.0


func get_water_oxygen_drain_rate() -> float:
	return _water_runtime.get_water_oxygen_drain_rate() if _water_runtime != null else 0.0


func add_oxygen(amount: float) -> void:
	if _water_runtime != null:
		_water_runtime.add_oxygen(amount)


func apply_water_jet_velocity(jet_velocity: Vector2, delta: float) -> void:
	if _water_runtime != null:
		_water_runtime.apply_water_jet_velocity(jet_velocity, is_remote_player)


func consume_water_jet_velocity() -> Vector2:
	return _water_runtime.consume_water_jet_velocity() if _water_runtime != null else Vector2.ZERO


func move_and_push() -> void:
	if _water_runtime != null:
		_water_runtime.prepare_move(get_physics_process_delta_time())
	move_and_slide()
	if _uses_network_push_intents():
		_collect_push_intents()
	else:
		apply_push_forces()
	if _water_runtime != null:
		_water_runtime.finish_move()


func set_key_count(value: int) -> void:
	key_count = max(value, 0)
	_update_key_indicator()


func set_max_oxygen(value: float) -> void:
	_apply_oxygen_runtime_state(oxygen, value)


func set_oxygen(value: float) -> void:
	_apply_oxygen_runtime_state(value, max_oxygen)


func apply_runtime_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	if state.has("key_count"):
		set_key_count(int(state.get("key_count", key_count)))

	var next_oxygen := oxygen
	var next_max_oxygen := max_oxygen
	var has_oxygen_state := false
	if state.has("oxygen"):
		next_oxygen = float(state.get("oxygen", oxygen))
		has_oxygen_state = true
	if state.has("max_oxygen"):
		next_max_oxygen = float(state.get("max_oxygen", max_oxygen))
		has_oxygen_state = true
	if has_oxygen_state:
		_apply_oxygen_runtime_state(next_oxygen, next_max_oxygen)


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
	if animation_player == null or not animation_player.has_animation(animation):
		return

	_apply_sprite_sheet_for_animation(animation)
	if animation_player.current_animation != animation or not animation_player.is_playing():
		animation_player.play(animation)


func set_facing_direction(direction: float) -> void:
	if sprite == null or is_zero_approx(direction):
		return
	sprite.flip_h = direction < 0.0


func get_facing_direction() -> float:
	if sprite != null:
		return -1.0 if sprite.flip_h else 1.0
	if not is_zero_approx(velocity.x):
		return signf(velocity.x)
	return 1.0


func set_sprite_vertical_flip(flipped: bool) -> void:
	if sprite != null:
		sprite.flip_v = flipped


func consume_push_intents() -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	for raw_value in _push_intents.values():
		if typeof(raw_value) != TYPE_DICTIONARY:
			continue
		intents.append(Dictionary(raw_value).duplicate(true))

	_push_intents.clear()
	return intents


func get_network_state(level_index: int) -> Dictionary:
	if _network_runtime != null:
		return _network_runtime.get_network_state(level_index, carried_key_color)
	return {}


func apply_network_state(state: Dictionary) -> void:
	if _network_runtime != null:
		_network_runtime.apply_network_state(state, is_remote_player, Callable(self, "_update_key_indicator"))


func _apply_network_control_mode() -> void:
	if _network_runtime != null:
		_network_runtime.apply_control_mode(is_remote_player, input_enabled, Callable(self, "_update_elimination_state"))


func _update_elimination_state() -> void:
	if player_collision_shape != null:
		player_collision_shape.set_deferred("disabled", _is_eliminated)

	visible = not _is_eliminated
	if _is_eliminated:
		velocity = Vector2.ZERO

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


func _update_name_label() -> void:
	if name_label == null:
		return

	var cleaned_name := display_name.strip_edges()
	var should_show := _should_show_online_name() and not cleaned_name.is_empty()
	name_label.visible = should_show
	if not should_show:
		name_label.text = ""
		return

	name_label.text = cleaned_name
	name_label.modulate = Color(0.82, 0.95, 1.0) if is_remote_player else Color.WHITE
	_update_name_label_position()


func _update_name_label_position() -> void:
	if name_label == null or not name_label.visible:
		return

	name_label.global_position = global_position + NAME_LABEL_OFFSET


func _update_oxygen(delta: float) -> void:
	if _water_runtime != null:
		_water_runtime.update_oxygen(delta, is_remote_player, _is_eliminated, _is_online_session())


func _apply_oxygen_runtime_state(current: float, maximum: float) -> void:
	var safe_maximum := maxf(maximum, 0.0)
	var safe_current := clampf(current, 0.0, safe_maximum)
	var changed := not is_equal_approx(max_oxygen, safe_maximum) or not is_equal_approx(oxygen, safe_current)
	if _water_runtime != null:
		_water_runtime.sync_oxygen_state(safe_current, safe_maximum)
	else:
		max_oxygen = safe_maximum
		oxygen = safe_current
	if changed:
		oxygen_changed.emit(oxygen, max_oxygen)


func _update_bubble_effect() -> void:
	if _bubble_effects != null:
		_bubble_effects.update_visibility(is_in_water())


func _process_bubble_effects(delta: float) -> void:
	if _bubble_effects != null:
		_bubble_effects.process(delta, is_in_water(), velocity, get_facing_direction())


func _random_water_jet_side_sign() -> float:
	return -1.0 if _bubble_rng.randi_range(0, 1) == 0 else 1.0


func _prune_water_zones() -> void:
	if _water_runtime != null:
		_water_runtime.prune_water_zones()


func _is_online_session() -> bool:
	var network_client := get_node_or_null("/root/NetworkClient")
	if network_client == null or not network_client.has_method("get_current_room"):
		return false

	var current_room = network_client.get_current_room()
	return typeof(current_room) == TYPE_DICTIONARY and not current_room.is_empty()


func _should_show_online_name() -> bool:
	var network_client := get_node_or_null("/root/NetworkClient")
	if network_client == null or not network_client.has_method("get_current_room"):
		return false

	var current_room = network_client.get_current_room()
	if typeof(current_room) != TYPE_DICTIONARY or current_room.is_empty():
		return false

	return String(current_room.get("status", "")) != "playing"


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
