extends Node
class_name PlayerAudio

const JUMP_SFX := preload("res://assets/sound/jump.wav")
const LAND_SFX := preload("res://assets/sound/land.wav")
const DEATH_SFX := preload("res://assets/sound/death-fall.wav")
const RESPAWN_SFX := preload("res://assets/sound/respawn.wav")
const KEY_PICKUP_SFX := preload("res://assets/sound/key pickup.wav")
const WALK_RUN_SFX := preload("res://assets/sound/walk-run.wav")
const OptionsState = preload("res://scripts/menu/options_state.gd")

var _jump_sfx: AudioStreamPlayer
var _land_sfx: AudioStreamPlayer
var _death_sfx: AudioStreamPlayer
var _respawn_sfx: AudioStreamPlayer
var _key_pickup_sfx: AudioStreamPlayer
var _walk_run_sfx: AudioStreamPlayer
var _is_remote_player := false
var _current_state_name := ""


func setup(
	jump_sfx: AudioStreamPlayer,
	land_sfx: AudioStreamPlayer,
	death_sfx: AudioStreamPlayer,
	respawn_sfx: AudioStreamPlayer,
	key_pickup_sfx: AudioStreamPlayer,
	walk_run_sfx: AudioStreamPlayer
) -> void:
	_jump_sfx = jump_sfx
	_land_sfx = land_sfx
	_death_sfx = death_sfx
	_respawn_sfx = respawn_sfx
	_key_pickup_sfx = key_pickup_sfx
	_walk_run_sfx = walk_run_sfx
	_configure_audio_players()


func set_remote_player(remote: bool) -> void:
	_is_remote_player = remote


func on_state_transitioned(previous_state_name: StringName, new_state_name: StringName) -> void:
	_current_state_name = String(new_state_name)
	var next_state := String(new_state_name)
	var previous_state := String(previous_state_name)

	if next_state == "run":
		start_walk_run_sfx()
	else:
		stop_walk_run_sfx()

	if next_state == "jump":
		play_jump_sfx()
	elif _is_landing_transition(previous_state, next_state):
		play_land_sfx()


func play_jump_sfx() -> void:
	_play_one_shot(_jump_sfx)


func play_land_sfx() -> void:
	_play_one_shot(_land_sfx)


func play_death_sfx() -> void:
	_play_one_shot(_death_sfx)


func play_respawn_sfx() -> void:
	_play_one_shot(_respawn_sfx)


func play_key_pickup_sfx() -> void:
	_play_one_shot(_key_pickup_sfx)


func start_walk_run_sfx() -> void:
	if not _should_play():
		return
	_play_looping(_walk_run_sfx)


func stop_walk_run_sfx() -> void:
	if not _should_play():
		return
	if _walk_run_sfx != null and _walk_run_sfx.playing:
		_walk_run_sfx.stop()


func stop_all() -> void:
	for audio_player in [_jump_sfx, _land_sfx, _death_sfx, _respawn_sfx, _key_pickup_sfx, _walk_run_sfx]:
		if audio_player != null:
			audio_player.stop()


func _configure_audio_players() -> void:
	if _jump_sfx != null:
		_jump_sfx.stream = JUMP_SFX
	if _land_sfx != null:
		_land_sfx.stream = LAND_SFX
	if _death_sfx != null:
		_death_sfx.stream = DEATH_SFX
	if _respawn_sfx != null:
		_respawn_sfx.stream = RESPAWN_SFX
	if _key_pickup_sfx != null:
		_key_pickup_sfx.stream = KEY_PICKUP_SFX
	if _walk_run_sfx != null:
		_walk_run_sfx.stream = WALK_RUN_SFX
		if not _walk_run_sfx.finished.is_connected(_on_walk_run_finished):
			_walk_run_sfx.finished.connect(_on_walk_run_finished)

	for player in [_jump_sfx, _land_sfx, _death_sfx, _respawn_sfx, _key_pickup_sfx, _walk_run_sfx]:
		OptionsState.assign_sfx_bus(player)


func _on_walk_run_finished() -> void:
	if _current_state_name == "run" and _walk_run_sfx != null:
		_walk_run_sfx.play()


func _is_landing_transition(previous_state_name: String, new_state_name: String) -> bool:
	if new_state_name != "run" and new_state_name != "idle":
		return false
	return previous_state_name == "jump" or previous_state_name == "fall" or previous_state_name == "dash"


func _play_one_shot(player: AudioStreamPlayer) -> void:
	if not _should_play() or player == null or player.stream == null:
		return
	player.play()


func _play_looping(player: AudioStreamPlayer) -> void:
	if not _should_play() or player == null or player.stream == null:
		return
	if not player.playing:
		player.play()


func _should_play() -> bool:
	return not _is_remote_player and DisplayServer.get_name() != "headless"
