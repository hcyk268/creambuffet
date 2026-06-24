extends CharacterBody2D
class_name PlayerSoda

signal died
signal water_state_changed(in_water: bool)
signal oxygen_changed(current: float, maximum: float)
signal oxygen_depleted

const DEFAULT_PROFILE := preload("res://data/player/player_soda_default.tres")

@export var profile: PlayerSodaProfile

@onready var carried_key_sprite: Sprite2D = get_node_or_null("CarriedKey") as Sprite2D
@onready var bubble_effect: AnimatedSprite2D = get_node_or_null("BubbleEffect") as AnimatedSprite2D
@onready var name_label: Label = get_node_or_null("NameLabel") as Label
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var animation_player: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer
@onready var state_machine: Node = get_node_or_null("StateMachine")
@onready var player_collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
@onready var jump_sfx: AudioStreamPlayer = get_node_or_null("JumpSfx") as AudioStreamPlayer
@onready var land_sfx: AudioStreamPlayer = get_node_or_null("LandSfx") as AudioStreamPlayer
@onready var death_sfx: AudioStreamPlayer = get_node_or_null("DeathSfx") as AudioStreamPlayer
@onready var respawn_sfx: AudioStreamPlayer = get_node_or_null("RespawnSfx") as AudioStreamPlayer
@onready var key_pickup_sfx: AudioStreamPlayer = get_node_or_null("KeyPickupSfx") as AudioStreamPlayer
@onready var walk_run_sfx: AudioStreamPlayer = get_node_or_null("WalkRunSfx") as AudioStreamPlayer
@onready var torch_light: PointLight2D = $PointLight2D

var spawn_position: Vector2
var oxygen := 10.0
var max_oxygen := 10.0
var key_count := 0
var has_torch := false
var current_light_scale := 4.0
var carried_key_color := Color.WHITE
var network_peer_id := 0
var display_name := ""
var is_remote_player := false
var input_enabled := true

var _host: PlayerSodaHost
var _is_eliminated := false


func _ready() -> void:
	if profile == null:
		profile = DEFAULT_PROFILE.duplicate(true) as PlayerSodaProfile
	profile.ensure_defaults()

	_host = PlayerSodaHost.new()
	_host.name = "PlayerSodaHost"
	add_child(_host)
	_host.initialize(self, profile, _scene_refs())
	_sync_host_network_state()
	_host.on_ready()


func _exit_tree() -> void:
	if _host != null:
		_host.on_exit_tree()


func _process(delta: float) -> void:
	if _host != null:
		_host.process_frame(delta)


func _physics_process(delta: float) -> void:
	if _host != null:
		_host.physics_tick(delta)


func is_eliminated_flag() -> bool:
	return _is_eliminated


func set_eliminated_flag(value: bool) -> void:
	_is_eliminated = value


var SPEED: float:
	get:
		return profile.ensure_defaults().movement.speed


var JUMP_VELOCITY: float:
	get:
		return profile.ensure_defaults().movement.jump_velocity


var PUSH_FORCE: float:
	get:
		return profile.ensure_defaults().movement.push_force


func set_network_identity(peer_id: int, player_name: String = "") -> void:
	network_peer_id = peer_id
	display_name = player_name
	if _host != null:
		_host.set_network_identity(peer_id, player_name)


func set_network_remote(remote: bool) -> void:
	is_remote_player = remote
	if _host != null:
		_host.set_network_remote(remote)


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if _host != null:
		_host.set_input_enabled(enabled)


func set_eliminated(eliminated: bool) -> void:
	_host.set_eliminated(eliminated)


func is_eliminated() -> bool:
	return _is_eliminated


func die() -> void:
	_host.die()


func respawn() -> void:
	_host.respawn()


func reset_oxygen() -> void:
	_host.reset_oxygen()


func enter_water_zone(zone: Area2D) -> void:
	_host.enter_water_zone(zone)


func exit_water_zone(zone: Area2D) -> void:
	_host.exit_water_zone(zone)


func is_in_water() -> bool:
	return _host.is_in_water()


func get_water_current_velocity() -> Vector2:
	return _host.get_water_current_velocity()


func get_water_swim_speed_multiplier() -> float:
	return _host.get_water_swim_speed_multiplier()


func get_water_oxygen_drain_rate() -> float:
	return _host.get_water_oxygen_drain_rate()


func add_oxygen(amount: float) -> void:
	_host.add_oxygen(amount)


func apply_water_jet_velocity(jet_velocity: Vector2, delta: float) -> void:
	_host.apply_water_jet_velocity(jet_velocity, delta)


func consume_water_jet_velocity() -> Vector2:
	return _host.consume_water_jet_velocity()


func move_and_push() -> void:
	_host.move_and_push()


func set_key_count(value: int) -> void:
	_host.set_key_count(value)


func set_max_oxygen(value: float) -> void:
	set_oxygen_state(oxygen, value)


func set_oxygen(value: float) -> void:
	set_oxygen_state(value, max_oxygen)


func set_oxygen_state(current: float, maximum: float) -> void:
	_host.set_oxygen_state(current, maximum)


func apply_runtime_state(state: Dictionary) -> void:
	_host.apply_runtime_state(state)


func collect_key(amount: int = 1, key_color: Color = Color.WHITE) -> void:
	_host.collect_key(amount, key_color)


func collect_torch() -> void:
	_host.collect_torch()


func add_light_buff() -> void:
	_host.add_light_buff()


func set_carried_key_color(key_color: Color) -> void:
	_host.set_carried_key_color(key_color)


func has_key() -> bool:
	return _host.has_key()


func use_key(amount: int = 1) -> bool:
	return _host.use_key(amount)


func play_player_animation(animation: String) -> void:
	_host.play_player_animation(animation)


func get_visual_animation() -> String:
	return _host.get_visual_animation()


func get_visual_flip_h() -> bool:
	return _host.get_visual_flip_h()


func set_visual_flip_h(flipped: bool) -> void:
	_host.set_visual_flip_h(flipped)


func set_facing_direction(direction: float) -> void:
	_host.set_facing_direction(direction)


func get_facing_direction() -> float:
	return _host.get_facing_direction()


func set_sprite_vertical_flip(flipped: bool) -> void:
	_host.set_sprite_vertical_flip(flipped)


func apply_remote_kinematics(target_position: Vector2, target_velocity: Vector2) -> void:
	_host.apply_remote_kinematics(target_position, target_velocity)


func consume_push_intents() -> Array[Dictionary]:
	return _host.consume_push_intents()


func get_network_state(level_index: int) -> Dictionary:
	return _host.get_network_state(level_index)


func apply_network_state(state: Dictionary) -> void:
	_host.apply_network_state(state)


func turn_off_light() -> void:
	_host.turn_off_light()


func _sync_host_network_state() -> void:
	if _host == null:
		return
	if network_peer_id != 0 or not display_name.is_empty():
		_host.set_network_identity(network_peer_id, display_name)
	_host.set_network_remote(is_remote_player)
	_host.set_input_enabled(input_enabled)


func _scene_refs() -> Dictionary:
	return {
		"sprite": sprite,
		"animation_player": animation_player,
		"carried_key_sprite": carried_key_sprite,
		"torch_light": torch_light,
		"bubble_effect": bubble_effect,
		"name_label": name_label,
		"state_machine": state_machine,
		"player_collision_shape": player_collision_shape,
		"jump_sfx": jump_sfx,
		"land_sfx": land_sfx,
		"death_sfx": death_sfx,
		"respawn_sfx": respawn_sfx,
		"key_pickup_sfx": key_pickup_sfx,
		"walk_run_sfx": walk_run_sfx,
	}
