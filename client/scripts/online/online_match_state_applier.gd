extends RefCounted
class_name OnlineMatchStateApplier

const GameIds = preload("res://scripts/catalog/game_ids.gd")

var _world_object_applier
var _synced_node_registry
var _network_client: Node
var _player: CharacterBody2D


func setup(world_object_applier, synced_node_registry, network_client: Node, player: CharacterBody2D) -> void:
	_world_object_applier = world_object_applier
	_synced_node_registry = synced_node_registry
	_network_client = network_client
	_player = player


func apply(room: Dictionary, current_level: Node, apply_pushable_controls: Callable, update_respawn_budget_hud: Callable) -> void:
	if room.is_empty() or not is_instance_valid(current_level):
		return

	var match_state_raw = room.get("match_state", {})
	if typeof(match_state_raw) != TYPE_DICTIONARY:
		return

	var match_state: Dictionary = match_state_raw
	var objects_raw = match_state.get("objects", {})
	if typeof(objects_raw) == TYPE_DICTIONARY:
		var object_states: Dictionary = objects_raw
		for raw_target_id in object_states.keys():
			var target_id := String(raw_target_id)
			var object_raw: Variant = object_states.get(target_id, {})
			if typeof(object_raw) != TYPE_DICTIONARY:
				continue
			var object_data: Dictionary = object_raw
			var state_raw: Variant = object_data.get("state", {})
			var state: Dictionary = {}
			if typeof(state_raw) == TYPE_DICTIONARY:
				state = state_raw
			_apply_object_state(target_id, object_data, state, update_respawn_budget_hud)
	else:
		var is_door_opened := bool(match_state.get("door_opened", false))
		for node in _find_nodes_in_group(current_level, "level_door"):
			if node.has_method("set_open"):
				node.set_open(is_door_opened)

		if bool(match_state.get("key_collected", false)):
			for node in _find_nodes_in_group(current_level, "level_key"):
				if is_instance_valid(node):
					node.queue_free()

	var players_raw = match_state.get("players", {})
	if typeof(players_raw) == TYPE_DICTIONARY:
		var players_state: Dictionary = players_raw
		var local_peer_id := _local_peer_id()
		var local_state: Variant = players_state.get(local_peer_id, players_state.get(str(local_peer_id), {}))
		if typeof(local_state) == TYPE_DICTIONARY and _player != null:
			var local_state_dict: Dictionary = local_state
			if _player.has_method("apply_runtime_state"):
				_player.apply_runtime_state(local_state_dict)
			elif _player.has_method("set_key_count"):
				_player.set_key_count(int(local_state_dict.get("key_count", 0)))

	var pushables_raw = match_state.get("pushables", [])
	if typeof(pushables_raw) == TYPE_ARRAY and apply_pushable_controls.is_valid():
		apply_pushable_controls.call(pushables_raw)


func _apply_object_state(target_id: String, object_data: Dictionary, state: Dictionary, update_respawn_budget_hud: Callable) -> void:
	match String(object_data.get("kind", "")):
		GameIds.OBJECT_KIND_KEY:
			if bool(state.get("collected", false)) and _world_object_applier != null:
				_world_object_applier.remove_collected_key(target_id)
		GameIds.OBJECT_KIND_DOOR, GameIds.OBJECT_KIND_EXIT_DOOR:
			var door_node := _find_node_by_sync_id(target_id)
			if door_node != null and door_node.has_method("set_open"):
				door_node.set_open(bool(state.get("opened", false)))
		GameIds.OBJECT_KIND_BUTTON, GameIds.OBJECT_KIND_PRESSURE_PLATE:
			if _world_object_applier != null:
				_world_object_applier.apply_button_state(target_id, bool(state.get("pressed", false)))
		GameIds.OBJECT_KIND_PUSH_BOX:
			if _world_object_applier != null:
				_world_object_applier.apply_push_box_state(target_id, {"position": state.get("position", {})})
		GameIds.OBJECT_KIND_MOVING_PLATFORM, GameIds.OBJECT_KIND_OXYGEN_TANK, GameIds.OBJECT_KIND_OXYGEN_STATION:
			if _world_object_applier != null:
				_world_object_applier.apply_object_state_changed(target_id, state)
		GameIds.OBJECT_KIND_TEAM_RESPAWN_BUDGET:
			if update_respawn_budget_hud.is_valid():
				update_respawn_budget_hud.call(state)
		GameIds.OBJECT_KIND_WATER_JET_NOZZLE, GameIds.OBJECT_KIND_WATER_JET:
			if _world_object_applier != null:
				_world_object_applier.apply_object_state_changed(target_id, state)
		GameIds.OBJECT_KIND_EXTENDABLE_BARRIER, GameIds.OBJECT_KIND_WATER_BARRIER, GameIds.OBJECT_KIND_BARRIER:
			if _world_object_applier != null:
				_world_object_applier.apply_object_state_changed(target_id, state)


func _find_node_by_sync_id(sync_id: String) -> Node:
	if _synced_node_registry == null:
		return null
	return _synced_node_registry.find(sync_id)


func _find_nodes_in_group(root: Node, group_name: StringName) -> Array[Node]:
	var result: Array[Node] = []
	_collect_group_nodes(root, group_name, result)
	return result


func _collect_group_nodes(node: Node, group_name: StringName, out_nodes: Array[Node]) -> void:
	if node.is_in_group(group_name):
		out_nodes.append(node)

	for child in node.get_children():
		if child is Node:
			_collect_group_nodes(child, group_name, out_nodes)


func _local_peer_id() -> int:
	if _network_client == null:
		return 0
	return int(_network_client.get_local_peer_id())
