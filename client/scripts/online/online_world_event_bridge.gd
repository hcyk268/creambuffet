extends RefCounted
class_name OnlineWorldEventBridge

const GameIds = preload("res://scripts/catalog/game_ids.gd")
const PacketCodec = preload("res://scripts/network/packet_codec.gd")
const SyncedNodeRegistry = preload("res://scripts/online/synced_node_registry.gd")

const LOCAL_HAZARD_RESPAWN_REARM_MS := 300

var _player: CharacterBody2D
var _network_client: Node
var _synced_node_registry
var _world_object_applier
var _decrement_shared_hearts: Callable
var _will_eliminate_on_next_death: Callable
var _update_failure_hud: Callable
var _current_level_id := ""
var _match_complete := false
var _remote_apply_active := false
var _pending_local_death_decrement := false
var _pending_local_elimination := false
var _local_hazard_rearm_until_ms := 0


func setup(
	player: CharacterBody2D,
	network_client: Node,
	synced_node_registry,
	world_object_applier,
	decrement_shared_hearts: Callable,
	will_eliminate_on_next_death: Callable,
	update_failure_hud: Callable
) -> void:
	_player = player
	_network_client = network_client
	_synced_node_registry = synced_node_registry
	_world_object_applier = world_object_applier
	_decrement_shared_hearts = decrement_shared_hearts
	_will_eliminate_on_next_death = will_eliminate_on_next_death
	_update_failure_hud = update_failure_hud


func reset_local_runtime_state(level_id: String) -> void:
	_current_level_id = level_id
	_match_complete = false
	_remote_apply_active = false
	_pending_local_death_decrement = false
	_pending_local_elimination = false
	_local_hazard_rearm_until_ms = 0


func set_match_complete(match_complete: bool) -> void:
	_match_complete = match_complete


func set_remote_apply_active(active: bool) -> void:
	_remote_apply_active = active


func connect_level(level_root: Node) -> void:
	if not is_instance_valid(level_root):
		return
	_connect_level_nodes(level_root)


func on_local_player_oxygen_depleted() -> void:
	if not _can_send_local_world_event() or _current_level_id.is_empty():
		return

	_network_client.send_world_event({
		"action": GameIds.ACTION_OXYGEN_DEPLETED,
		"level_id": _current_level_id,
		"position": _vector_to_packet(_player.global_position),
		"velocity": _vector_to_packet(_player.velocity),
	})


func apply_player_died(event_peer_id: int, eliminated: bool, target_player: CharacterBody2D) -> void:
	if target_player != null and eliminated and target_player.has_method("set_input_enabled"):
		target_player.set_input_enabled(false)
	if target_player != null and eliminated and target_player.has_method("set_eliminated"):
		target_player.set_eliminated(true)
	if target_player != null:
		target_player.velocity = Vector2.ZERO

	if event_peer_id == _local_peer_id() and _pending_local_death_decrement:
		_pending_local_death_decrement = false
	else:
		if _decrement_shared_hearts.is_valid():
			_decrement_shared_hearts.call()
		if _update_failure_hud.is_valid():
			_update_failure_hud.call()

	if event_peer_id == _local_peer_id() and _pending_local_elimination:
		_pending_local_elimination = false
	if event_peer_id == _local_peer_id() and eliminated and _player != null and _player.has_method("set_input_enabled"):
		_player.set_input_enabled(false)
	if event_peer_id == _local_peer_id():
		if eliminated:
			print("Local player eliminated until the level resets.")
		else:
			print("Local player death acknowledged by server.")


func apply_player_respawned(event_peer_id: int, target_player: CharacterBody2D) -> void:
	if target_player == null:
		return

	if target_player.has_method("respawn"):
		target_player.respawn()
	if target_player.has_method("set_input_enabled"):
		target_player.set_input_enabled(true)
	if target_player.has_method("set_eliminated"):
		target_player.set_eliminated(false)
	if event_peer_id == _local_peer_id():
		_pending_local_death_decrement = false
		_pending_local_elimination = false
		_local_hazard_rearm_until_ms = Time.get_ticks_msec() + LOCAL_HAZARD_RESPAWN_REARM_MS


func apply_remote_world_event(
	event: Dictionary,
	current_level_id: String,
	current_level_index: int,
	player_for_peer: Callable,
	update_respawn_budget_hud: Callable
) -> bool:
	if not _event_matches_current_level(event, current_level_id, current_level_index):
		return false

	_remote_apply_active = true
	var target_id := String(event.get("target_id", event.get("sync_id", "")))
	var event_peer_id := int(event.get("peer_id", -1))
	var event_state: Dictionary = {}
	var raw_event_state = event.get("state", {})
	if typeof(raw_event_state) == TYPE_DICTIONARY:
		event_state = raw_event_state

	match String(event.get("kind", "")):
		GameIds.EVENT_KEY_COLLECTED:
			if _world_object_applier != null:
				_world_object_applier.apply_key_collected(target_id, event_peer_id)
		GameIds.EVENT_TORCH_COLLECTED:
			if _world_object_applier != null:
				var colected_player = player_for_peer.call(event_peer_id) if player_for_peer.is_valid() else null
				_world_object_applier.apply_torch_collected(target_id, colected_player)
		GameIds.EVENT_BUFF_COLLECTED:
			if _world_object_applier != null:
				var collected_peer_id = int(event.get("torch_owner_peer_id", -1))
				var colected_player = player_for_peer.call(collected_peer_id) if player_for_peer.is_valid() else null
				_world_object_applier.apply_buff_collected(target_id, colected_player)
		GameIds.EVENT_DOOR_OPENED:
			if _world_object_applier != null:
				_world_object_applier.apply_door_opened(target_id, event_peer_id, event)
		GameIds.EVENT_DOOR_KEY_DEPOSITED:
			if _world_object_applier != null:
				_world_object_applier.apply_player_key_counts(event)
		GameIds.EVENT_PLAYER_DIED:
			var died_player = player_for_peer.call(event_peer_id) if player_for_peer.is_valid() else null
			apply_player_died(event_peer_id, bool(event.get("eliminated", false)), died_player)
		GameIds.EVENT_PLAYER_RESPAWNED:
			var respawned_player = player_for_peer.call(event_peer_id) if player_for_peer.is_valid() else null
			apply_player_respawned(event_peer_id, respawned_player)
		GameIds.EVENT_GOAL_ENTERED:
			if event_peer_id == _local_peer_id():
				print("You reached goal! %s", target_id)
		GameIds.EVENT_GOAL_EXITED:
			if event_peer_id == _local_peer_id():
				print("You left goal %s", target_id)
		GameIds.EVENT_BUTTON_STATE:
			if _world_object_applier != null:
				_world_object_applier.apply_button_state(target_id, bool(event.get("pressed", event_state.get("pressed", false))))
		GameIds.EVENT_PUSH_BOX_STATE:
			if _world_object_applier != null:
				_world_object_applier.apply_push_box_state(target_id, event)
		GameIds.EVENT_OXYGEN_COLLECTED:
			if _world_object_applier != null:
				_world_object_applier.apply_oxygen_collected(target_id, event_peer_id, event, event_state)
		GameIds.EVENT_TEAM_RESPAWN_BUDGET_CHANGED:
			if _world_object_applier != null:
				_world_object_applier.apply_object_state_changed(target_id, event_state)
			if update_respawn_budget_hud.is_valid():
				update_respawn_budget_hud.call(event_state)
		GameIds.EVENT_LEVEL_FAILED:
			print("Level failed: %s" % String(event.get("reason", "")))
		GameIds.EVENT_OBJECT_STATE_CHANGED:
			if _world_object_applier != null:
				_world_object_applier.apply_object_state_changed(target_id, event_state)

	_remote_apply_active = false
	return true


func _connect_level_nodes(node: Node) -> void:
	if node.has_signal("goal_reached"):
		var on_goal_reached := Callable(self, "_on_goal_reached").bind(node)
		if not node.is_connected("goal_reached", on_goal_reached):
			node.connect("goal_reached", on_goal_reached)

	if node.has_signal("goal_left"):
		var on_goal_left := Callable(self, "_on_goal_left").bind(node)
		if not node.is_connected("goal_left", on_goal_left):
			node.connect("goal_left", on_goal_left)

	if node.has_signal("collected"):
		var on_collected := Callable(self, "_on_key_collected").bind(node)
		if not node.is_connected("collected", on_collected):
			node.connect("collected", on_collected)
			
	if node.has_signal("torch_collected"):
		var on_collected := Callable(self, "_on_torch_collected").bind(node)
		if not node.is_connected("torch_collected", on_collected):
			node.connect("torch_collected", on_collected)
			
	if node.has_signal("buff_collected"):
		var on_collected := Callable(self, "_on_buff_collected").bind(node)
		if not node.is_connected("buff_collected", on_collected):
			node.connect("buff_collected", on_collected)

	if node.has_signal("door_opened"):
		var on_door_opened := Callable(self, "_on_door_opened").bind(node)
		if not node.is_connected("door_opened", on_door_opened):
			node.connect("door_opened", on_door_opened)

	if node.has_signal("player_death"):
		var on_player_death := Callable(self, "_on_player_death").bind(node)
		if not node.is_connected("player_death", on_player_death):
			node.connect("player_death", on_player_death)

	if node.has_signal("pressed_state_changed"):
		var on_button_state := Callable(self, "_on_button_state_changed").bind(node)
		if not node.is_connected("pressed_state_changed", on_button_state):
			node.connect("pressed_state_changed", on_button_state)

	for child in node.get_children():
		if child is Node:
			_connect_level_nodes(child)


func _on_goal_reached(body: Node, goal_node: Node) -> void:
	if not _can_send_local_world_event(body):
		return

	var target_id := _node_sync_id(goal_node)
	if target_id.is_empty():
		push_warning("Ignoring goal_enter request because goal sync_id is missing.")
		return

	_network_client.send_world_event({
		"action": GameIds.ACTION_GOAL_ENTER,
		"level_id": _current_level_id,
		"target_id": target_id,
	})


func _on_goal_left(body: Node, goal_node: Node) -> void:
	if not _can_send_local_world_event(body):
		return

	var target_id := _node_sync_id(goal_node)
	if target_id.is_empty():
		push_warning("Ignoring goal_exit request because goal sync_id is missing.")
		return

	_network_client.send_world_event({
		"action": GameIds.ACTION_GOAL_EXIT,
		"level_id": _current_level_id,
		"target_id": target_id,
	})


func _on_key_collected(body: Node, key_node: Node) -> void:
	if not _can_send_local_world_event(body):
		return

	var target_id := _node_sync_id(key_node)
	if target_id.is_empty():
		push_warning("Ignoring key_collect request because key sync_id is missing.")
		return

	_network_client.send_world_event({
		"action": GameIds.ACTION_COLLECT,
		"level_id": _current_level_id,
		"target_id": target_id,
		"position": _vector_to_packet(_player.global_position),
		"velocity": _vector_to_packet(_player.velocity),
	})

func _on_torch_collected(body:Node, key_node:Node) -> void:
	if not _can_send_local_world_event(body):
		return

	var target_id := _node_sync_id(key_node)
	if target_id.is_empty():
		push_warning("Ignoring torch_collect request because torch sync_id is missing.")
		return

	_network_client.send_world_event({
		"action": GameIds.ACTION_COLLECT_TORCH,
		"level_id": _current_level_id,
		"target_id": target_id,
		"position": _vector_to_packet(_player.global_position),
		"velocity": _vector_to_packet(_player.velocity),
	})
	
func _on_buff_collected(body:Node, key_node:Node) -> void:
	if not _can_send_local_world_event(body):
		return

	var target_id := _node_sync_id(key_node)
	if target_id.is_empty():
		push_warning("Ignoring buff_collect request because buff sync_id is missing.")
		return

	_network_client.send_world_event({
		"action": GameIds.ACTION_COLLECT_BUFF,
		"level_id": _current_level_id,
		"target_id": target_id,
		"position": _vector_to_packet(_player.global_position),
		"velocity": _vector_to_packet(_player.velocity),
	})
	
func _on_door_opened(door_node: Node) -> void:
	if not _can_send_local_world_event():
		return

	var target_id := _node_sync_id(door_node)
	if target_id.is_empty():
		push_warning("Ignoring open request because door sync_id is missing.")
		return

	_network_client.send_world_event({
		"action": GameIds.ACTION_OPEN,
		"level_id": _current_level_id,
		"target_id": target_id,
		"position": _vector_to_packet(_player.global_position),
		"velocity": _vector_to_packet(_player.velocity),
	})


func _on_player_death(body: Node, spike_node: Node) -> void:
	if not _can_send_local_world_event(body):
		return

	var now_ms: int = Time.get_ticks_msec()
	if now_ms < _local_hazard_rearm_until_ms:
		return
	if _pending_local_death_decrement or _pending_local_elimination:
		_pending_local_death_decrement = false
		_pending_local_elimination = false
	if _player.has_method("is_eliminated") and bool(_player.call("is_eliminated")):
		return

	var target_id := _node_sync_id(spike_node)
	if target_id.is_empty():
		push_warning("Ignoring player_death request because hazard sync_id is missing.")
		return

	var will_eliminate := _will_eliminate_on_next_death.is_valid() and bool(_will_eliminate_on_next_death.call())
	_pending_local_death_decrement = true
	_pending_local_elimination = will_eliminate
	_local_hazard_rearm_until_ms = now_ms + LOCAL_HAZARD_RESPAWN_REARM_MS
	if _decrement_shared_hearts.is_valid():
		_decrement_shared_hearts.call()
	if will_eliminate:
		if _player.has_method("set_eliminated"):
			_player.set_eliminated(true)
		if _player.has_method("set_input_enabled"):
			_player.set_input_enabled(false)
	elif _player.has_method("respawn"):
		_player.respawn()
	if _update_failure_hud.is_valid():
		_update_failure_hud.call()

	_network_client.send_world_event({
		"action": GameIds.ACTION_PLAYER_DEATH,
		"level_id": _current_level_id,
		"target_id": target_id,
		"position": _vector_to_packet(_player.global_position),
		"velocity": _vector_to_packet(_player.velocity),
		"target_position": _vector_to_packet((spike_node as Node2D).global_position if spike_node is Node2D else Vector2.ZERO),
	})


func _on_button_state_changed(is_pressed: bool, button_node: Node) -> void:
	if not _can_send_local_world_event():
		return

	var target_id := _node_sync_id(button_node)
	if target_id.is_empty():
		push_warning("Ignoring button_state request because button sync_id is missing.")
		return

	_network_client.send_world_action(GameIds.ACTION_BUTTON_STATE, target_id, {
		"level_id": _current_level_id,
		"pressed": is_pressed,
		"position": _vector_to_packet(_player.global_position),
		"velocity": _vector_to_packet(_player.velocity),
	})


func _can_send_local_world_event(body: Node = null) -> bool:
	if _network_client == null or _player == null:
		return false
	if _remote_apply_active or _match_complete or _current_level_id.is_empty():
		return false
	if body != null and body != _player:
		return false
	return true


func _node_sync_id(node: Node) -> String:
	return SyncedNodeRegistry.node_sync_id(node)


func _vector_to_packet(value: Vector2) -> Dictionary:
	return PacketCodec.vector_to_packet(value)


func _local_peer_id() -> int:
	if _network_client == null:
		return 0
	return int(_network_client.get_local_peer_id())


func _event_matches_current_level(event: Dictionary, current_level_id: String, current_level_index: int) -> bool:
	var event_level_id := String(event.get("level_id", ""))
	if not event_level_id.is_empty():
		return event_level_id == current_level_id
	return int(event.get("level_index", current_level_index)) == current_level_index
