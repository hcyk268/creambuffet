extends RefCounted
class_name OnlinePushableSync

const SyncedNodeRegistry = preload("res://scripts/online/synced_node_registry.gd")


static func configure_pushables(level_root: Node) -> void:
	for node in _find_nodes_in_group(level_root, "pushable"):
		if node.has_method("set_online_authoritative"):
			node.set_online_authoritative(true)


static func configure_buttons(level_root: Node) -> void:
	for node in _find_nodes_in_group(level_root, "level_button"):
		if node.has_method("set_online_authoritative"):
			node.set_online_authoritative(true)


static func configure_water_objects(level_root: Node) -> void:
	for node in _find_nodes_in_group(level_root, "oxygen_pickup"):
		if node.has_method("set_online_authoritative"):
			node.set_online_authoritative(true)


static func apply_pushable_controls(level_root: Node, raw_controls, synced_nodes: SyncedNodeRegistry) -> void:
	if typeof(raw_controls) != TYPE_ARRAY or not is_instance_valid(level_root):
		return

	for raw_control in raw_controls:
		if typeof(raw_control) != TYPE_DICTIONARY:
			continue

		var control: Dictionary = raw_control
		var body: Node = null
		if synced_nodes != null:
			body = synced_nodes.find(String(control.get("target_id", "")))
		if body == null:
			body = _find_level_node(level_root, String(control.get("node_name", "")))
		if body == null or not body.has_method("apply_server_push_control"):
			continue

		body.apply_server_push_control(float(control.get("drive_x", 0.0)))


static func collect_pushable_state_observations(level_root: Node) -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	if not is_instance_valid(level_root):
		return states

	for node in _find_nodes_in_group(level_root, "pushable"):
		if not (node is Node2D):
			continue

		var body := node as Node2D
		var target_id := SyncedNodeRegistry.node_sync_id(body)
		if target_id.is_empty():
			target_id = body.name

		states.append({
			"target_id": target_id,
			"node_name": body.name,
			"position": _vector_to_packet(body.global_position),
		})

	return states


static func _find_nodes_in_group(root: Node, group_name: StringName) -> Array[Node]:
	var result: Array[Node] = []
	if is_instance_valid(root):
		_collect_group_nodes(root, group_name, result)
	return result


static func _collect_group_nodes(node: Node, group_name: StringName, out_nodes: Array[Node]) -> void:
	if node.is_in_group(group_name):
		out_nodes.append(node)

	for child in node.get_children():
		if child is Node:
			_collect_group_nodes(child, group_name, out_nodes)


static func _find_level_node(level_root: Node, node_name: String) -> Node:
	if not is_instance_valid(level_root) or node_name.is_empty():
		return null

	var direct := level_root.get_node_or_null(NodePath(node_name))
	if direct != null:
		return direct

	return level_root.find_child(node_name, true, false)


static func _vector_to_packet(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}
