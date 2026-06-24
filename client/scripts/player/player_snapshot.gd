extends RefCounted
class_name PlayerSnapshot

const PacketCodec = preload("res://scripts/network/packet_codec.gd")


var level_index := -1
var position := Vector2.ZERO
var velocity := Vector2.ZERO
var animation := ""
var flip_h := false
var carried_key_color := Color.WHITE
var key_count := 0
var oxygen := 0.0
var max_oxygen := 0.0


static func capture_local(player: CharacterBody2D, level_index: int) -> PlayerSnapshot:
	var snapshot := PlayerSnapshot.new()
	snapshot.level_index = level_index

	var typed := player as PlayerSoda
	if typed != null:
		snapshot.position = typed.global_position
		snapshot.velocity = typed.velocity
		snapshot.animation = typed.get_visual_animation()
		snapshot.flip_h = typed.get_visual_flip_h()
		snapshot.carried_key_color = typed.carried_key_color
		snapshot.key_count = typed.key_count
		snapshot.oxygen = typed.oxygen
		snapshot.max_oxygen = typed.max_oxygen
		return snapshot

	snapshot.position = player.global_position
	snapshot.velocity = player.velocity
	return snapshot


func to_network_dict() -> Dictionary:
	return {
		"level_index": level_index,
		"position": PacketCodec.vector_to_packet(position),
		"velocity": PacketCodec.vector_to_packet(velocity),
		"animation": animation,
		"flip_h": flip_h,
		"carried_key_color": PacketCodec.color_to_packet(carried_key_color),
	}


static func apply_network_dict(player: CharacterBody2D, state: Dictionary, is_remote_player: bool) -> void:
	if player == null:
		return

	var next_position := PacketCodec.packet_to_vector(state.get("position", {}), player.global_position)
	var next_velocity := PacketCodec.packet_to_vector(state.get("velocity", {}), player.velocity)
	var typed := player as PlayerSoda
	if is_remote_player and typed != null:
		typed.apply_remote_kinematics(next_position, next_velocity)
	elif is_remote_player:
		player.global_position = next_position
		player.velocity = next_velocity
	else:
		player.global_position = next_position
		player.velocity = next_velocity

	var animation := String(state.get("animation", ""))
	if typed != null:
		if not animation.is_empty():
			typed.play_player_animation(animation)
		typed.set_visual_flip_h(bool(state.get("flip_h", typed.get_visual_flip_h())))
		if state.has("key_count"):
			typed.set_key_count(int(state.get("key_count", typed.key_count)))
		if state.has("carried_key_color"):
			typed.set_carried_key_color(
				PacketCodec.packet_to_color(state.get("carried_key_color", {}), typed.carried_key_color)
			)
		return

	if not animation.is_empty() and player.has_method("play_player_animation"):
		player.call("play_player_animation", animation)


static func apply_runtime_dict(player: CharacterBody2D, state: Dictionary) -> void:
	var typed := player as PlayerSoda
	if typed == null:
		return

	if state.has("key_count"):
		typed.set_key_count(int(state.get("key_count", typed.key_count)))

	var has_oxygen_state := state.has("oxygen") or state.has("max_oxygen")
	if has_oxygen_state:
		var current := float(state.get("oxygen", typed.oxygen))
		var maximum := float(state.get("max_oxygen", typed.max_oxygen))
		typed.set_oxygen_state(current, maximum)
