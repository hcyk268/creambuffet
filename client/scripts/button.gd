extends Area2D

signal pressed_state_changed(is_pressed: bool)

const BUTTON_PRESS_SFX := preload("res://assets/sound/button press.wav")
const BUTTON_CLICK_SFX := preload("res://assets/sound/button click.wav")
const OptionsState = preload("res://scripts/menu/options_state.gd")

enum ActivationMode {
	PRESS_ONCE,
	WHILE_HELD,
}

@export var activation_mode: ActivationMode = ActivationMode.PRESS_ONCE
@export var sync_id := ""
@export var target_platform: AnimatableBody2D
@export var target_activation_node: Node
@export var target_activation_value := true
@export var target_release_activation_value := false
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var sfx_player: AudioStreamPlayer = get_node_or_null("SfxPlayer") as AudioStreamPlayer

var is_pressed := false
var _tracked_bodies: Dictionary = {}
var _online_authoritative := false
var _applying_server_state := false


func _ready() -> void:
	add_to_group("level_button")
	_configure_audio()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	call_deferred("_sync_overlaps")


func _on_body_entered(body: Node2D) -> void:
	if not _is_valid_body(body):
		return

	_tracked_bodies[body.get_instance_id()] = body
	_update_pressed_state()


func _on_body_exited(body: Node2D) -> void:
	_tracked_bodies.erase(body.get_instance_id())
	_update_pressed_state()


func _sync_overlaps() -> void:
	_tracked_bodies.clear()
	for body in get_overlapping_bodies():
		if _is_valid_body(body):
			_tracked_bodies[body.get_instance_id()] = body
	_update_pressed_state()


func _is_valid_body(body: Node) -> bool:
	return body.is_in_group("player") or body.is_in_group("pushable")


func _update_pressed_state() -> void:
	var next_pressed := not _tracked_bodies.is_empty()
	if is_pressed == next_pressed:
		return

	is_pressed = next_pressed
	_apply_pressed_state()
	pressed_state_changed.emit(is_pressed)


func _update_target_platform_state() -> void:
	if _online_authoritative and not _applying_server_state:
		_apply_activation_target(target_activation_node)
		return

	_apply_activation_target(target_platform)
	_apply_activation_target(target_activation_node)


func _apply_activation_target(target: Node) -> void:
	if target == null or not target.has_method("set_activation"):
		return

	match activation_mode:
		ActivationMode.PRESS_ONCE:
			if is_pressed:
				target.set_activation(target_activation_value)
		ActivationMode.WHILE_HELD:
			target.set_activation(target_activation_value if is_pressed else target_release_activation_value)


func apply_server_pressed(pressed: bool) -> void:
	_applying_server_state = true
	is_pressed = pressed
	_apply_pressed_state()
	_applying_server_state = false


func set_online_authoritative(enabled: bool) -> void:
	_online_authoritative = enabled


func _apply_pressed_state() -> void:
	animated_sprite.play("pressed" if is_pressed else "released")
	if is_pressed:
		_play_sfx(BUTTON_PRESS_SFX)
	else:
		_play_sfx(BUTTON_CLICK_SFX)
	_update_target_platform_state()


func _configure_audio() -> void:
	if sfx_player == null:
		return

	sfx_player.stream = BUTTON_PRESS_SFX
	OptionsState.assign_sfx_bus(sfx_player)


func _play_sfx(stream: AudioStream) -> void:
	if sfx_player == null or stream == null:
		return

	sfx_player.stream = stream
	sfx_player.play()
