extends RefCounted
class_name PlayerCapabilities


static func as_player(node: Node) -> PlayerSoda:
	return node as PlayerSoda


static func die(player: Node) -> void:
	var typed := as_player(player)
	if typed != null:
		typed.die()


static func add_oxygen(player: Node, amount: float) -> void:
	var typed := as_player(player)
	if typed != null:
		typed.add_oxygen(amount)


static func enter_water_zone(player: Node, zone: Area2D) -> void:
	var typed := as_player(player)
	if typed != null:
		typed.enter_water_zone(zone)


static func exit_water_zone(player: Node, zone: Area2D) -> void:
	var typed := as_player(player)
	if typed != null:
		typed.exit_water_zone(zone)


static func set_input_enabled(player: Node, enabled: bool) -> void:
	var typed := as_player(player)
	if typed != null:
		typed.set_input_enabled(enabled)


static func set_eliminated(player: Node, eliminated: bool) -> void:
	var typed := as_player(player)
	if typed != null:
		typed.set_eliminated(eliminated)


static func respawn(player: Node) -> void:
	var typed := as_player(player)
	if typed != null:
		typed.respawn()


static func has_key(player: Node) -> bool:
	var typed := as_player(player)
	return typed.has_key() if typed != null else false


static func use_key(player: Node, amount: int = 1) -> bool:
	var typed := as_player(player)
	return typed.use_key(amount) if typed != null else false


static func collect_key(player: PlayerSoda, amount: int = 1, key_color: Color = Color.WHITE) -> void:
	if player != null:
		player.collect_key(amount, key_color)


static func set_key_count(player: PlayerSoda, value: int) -> void:
	if player != null:
		player.set_key_count(value)


static func apply_runtime_state(player: PlayerSoda, state: Dictionary) -> void:
	if player != null:
		player.apply_runtime_state(state)


static func get_network_state(player: PlayerSoda, level_index: int) -> Dictionary:
	return player.get_network_state(level_index) if player != null else {}


static func apply_network_state(player: PlayerSoda, state: Dictionary) -> void:
	if player != null:
		player.apply_network_state(state)


static func configure_network_player(player: PlayerSoda, peer_id: int, player_name: String, remote: bool) -> void:
	if player == null:
		return
	player.set_network_identity(peer_id, player_name)
	player.set_network_remote(remote)
