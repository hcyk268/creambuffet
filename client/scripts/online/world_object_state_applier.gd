extends RefCounted
class_name WorldObjectStateApplier

const PacketCodec = preload("res://scripts/network/packet_codec.gd")

var _player: PlayerSoda
var _network_client: Node
var _synced_nodes


func setup(player: CharacterBody2D, network_client: Node, synced_nodes) -> void:
	_player = player as PlayerSoda
	_network_client = network_client
	_synced_nodes = synced_nodes


func apply_key_collected(sync_id: String, peer_id: int) -> void:
	var key_node := _find_node(sync_id)
	var key_color := Color.WHITE
	if is_instance_valid(key_node):
		if key_node is CanvasItem:
			key_color = (key_node as CanvasItem).modulate
		_forget_node(sync_id)
		key_node.queue_free()

	if peer_id == _local_peer_id() and _player != null:
		_player.collect_key(1, key_color)

func apply_torch_collected(sync_id:String,  collected_player: CharacterBody2D) -> void:
	var torch_node := _find_node(sync_id)

	if is_instance_valid(torch_node):
		_forget_node(sync_id)
		torch_node.queue_free()

	if collected_player is PlayerSoda:
		(collected_player as PlayerSoda).collect_torch()
		
func apply_buff_collected(sync_id:String, collected_player: CharacterBody2D) -> void:
	var buff_node := _find_node(sync_id)
	print(collected_player)
	if is_instance_valid(buff_node):
		_forget_node(sync_id)
		buff_node.queue_free()

	if collected_player is PlayerSoda:
		(collected_player as PlayerSoda).add_light_buff()

func apply_door_opened(sync_id: String, event_peer_id: int, event: Dictionary = {}) -> void:
	var door_node := _find_node(sync_id)
	if door_node != null and door_node.has_method("apply_server_open_state"):
		door_node.apply_server_open_state(true)
	elif door_node != null and door_node.has_method("open"):
		door_node.open()

	if apply_player_key_counts(event):
		return

	if event_peer_id == _local_peer_id() and _player != null:
		_player.use_key()


func apply_player_key_counts(event: Dictionary) -> bool:
	if _player == null:
		return false

	var local_peer_id := _local_peer_id()
	var raw_key_counts: Variant = event.get("player_key_counts", {})
	if typeof(raw_key_counts) == TYPE_DICTIONARY and _player != null:
		var key_counts: Dictionary = raw_key_counts
		if key_counts.has(str(local_peer_id)):
			_player.set_key_count(int(key_counts[str(local_peer_id)]))
			return true
		if key_counts.has(local_peer_id):
			_player.set_key_count(int(key_counts[local_peer_id]))
			return true
	return false


func apply_oxygen_collected(sync_id: String, event_peer_id: int, event: Dictionary, state: Dictionary) -> void:
	var oxygen_node := _find_node(sync_id)
	if oxygen_node != null and oxygen_node.has_method("apply_server_state"):
		oxygen_node.apply_server_state(state, _local_peer_id())

	if event_peer_id != _local_peer_id():
		return

	if _player != null:
		_player.add_oxygen(float(event.get("oxygen_amount", event.get("amount", 0.0))))


func apply_button_state(sync_id: String, is_pressed: bool) -> void:
	var button_node := _find_node(sync_id)
	if button_node != null and button_node.has_method("apply_server_pressed"):
		button_node.apply_server_pressed(is_pressed)


func apply_object_state_changed(sync_id: String, state: Dictionary) -> void:
	var node := _find_node(sync_id)
	if node == null:
		return

	if state.has("active"):
		if node.has_method("apply_server_state"):
			node.apply_server_state(state)
		elif node.has_method("set_activation"):
			node.set_activation(bool(state.get("active", false)))
	if state.has("open"):
		if node.has_method("apply_server_open_state"):
			node.apply_server_open_state(bool(state.get("open", false)))
		elif node.has_method("set_open"):
			node.set_open(bool(state.get("open", false)))
	if state.has("opened"):
		if node.has_method("apply_server_open_state"):
			node.apply_server_open_state(bool(state.get("opened", false)))
		elif node.has_method("set_open"):
			node.set_open(bool(state.get("opened", false)))
	if state.has("pressed") and node.has_method("apply_server_pressed"):
		node.apply_server_pressed(bool(state.get("pressed", false)))
	if (state.has("remaining_uses") or state.has("claimed_peer_ids")) and node.has_method("apply_server_state"):
		node.apply_server_state(state, _local_peer_id())


func apply_push_box_state(sync_id: String, event: Dictionary) -> void:
	var node := _find_node(sync_id)
	if node == null:
		return

	var raw_position = event.get("position", {})
	if typeof(raw_position) != TYPE_DICTIONARY:
		var raw_state = event.get("state", {})
		if typeof(raw_state) == TYPE_DICTIONARY:
			raw_position = Dictionary(raw_state).get("position", {})

	if typeof(raw_position) != TYPE_DICTIONARY:
		return

	var fallback := Vector2.ZERO
	if node is Node2D:
		fallback = (node as Node2D).global_position
	var next_position := PacketCodec.packet_to_vector(raw_position, fallback)
	if node.has_method("apply_server_position"):
		node.apply_server_position(next_position)
	elif node is Node2D:
		(node as Node2D).global_position = next_position


func remove_collected_key(sync_id: String) -> void:
	var key_node := _find_node(sync_id)
	if is_instance_valid(key_node):
		_forget_node(sync_id)
		key_node.queue_free()


func _find_node(sync_id: String) -> Node:
	if _synced_nodes == null:
		return null
	return _synced_nodes.find(sync_id)


func _forget_node(sync_id: String) -> void:
	if _synced_nodes != null:
		_synced_nodes.forget(sync_id)


func _local_peer_id() -> int:
	if _network_client == null:
		return 0
	return int(_network_client.get_local_peer_id())
