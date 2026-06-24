extends Area2D

signal player_death(body: Node)

const PlayerCapabilities = preload("res://scripts/player/player_capabilities.gd")

@export var sync_id : String

func _ready() -> void:
	add_to_group("level_hazard")
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_death.emit(body)
	if not _is_online_session():
		PlayerCapabilities.die(body)

func _is_online_session() -> bool:
	var network_client: Node = get_node_or_null("/root/NetworkClient")
	if network_client == null or not network_client.has_method("get_current_room"):
		return false

	var current_room = network_client.get_current_room()
	return typeof(current_room) == TYPE_DICTIONARY and not current_room.is_empty()
