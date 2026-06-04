extends RefCounted
class_name SyncedNodeRegistry

const NETWORK_GROUPS := [
	"level_key",
	"level_door",
	"level_goal",
	"level_hazard",
	"pushable",
	"level_button",
	"oxygen_pickup",
	"water_jet_nozzle",
	"extendable_barrier",
]

var _synced_nodes: Dictionary = {}
var _level_root: Node
var _level_id := ""


func register_level(level_root: Node, level_id: String, level_definition: Dictionary) -> void:
	_synced_nodes.clear()
	_level_root = level_root
	_level_id = level_id
	if not is_instance_valid(_level_root):
		return

	_collect_synced_nodes(_level_root)
	_warn_missing_catalog_nodes(level_definition)


func find(sync_id: String) -> Node:
	if not is_instance_valid(_level_root) or sync_id.is_empty():
		return null

	if _synced_nodes.has(sync_id):
		var registered = _synced_nodes[sync_id]
		if is_instance_valid(registered) and registered is Node:
			return registered as Node
		_synced_nodes.erase(sync_id)

	var found := _find_node_recursive(_level_root, sync_id)
	if found != null:
		_synced_nodes[sync_id] = found
	return found


func forget(sync_id: String) -> void:
	if not sync_id.is_empty():
		_synced_nodes.erase(sync_id)


static func node_sync_id(node: Node) -> String:
	if node != null and "sync_id" in node:
		return String(node.sync_id).strip_edges()
	return ""


func _collect_synced_nodes(node: Node) -> void:
	var sync_id := node_sync_id(node)
	if not sync_id.is_empty():
		if _synced_nodes.has(sync_id):
			push_warning("Duplicate sync_id in level %s: %s" % [_level_id, sync_id])
		_synced_nodes[sync_id] = node

	for child in node.get_children():
		if child is Node:
			_collect_synced_nodes(child)


func _find_node_recursive(node: Node, sync_id: String) -> Node:
	if node_sync_id(node) == sync_id:
		return node

	for child in node.get_children():
		var result := _find_node_recursive(child, sync_id)
		if result != null:
			return result

	return null


func _warn_missing_catalog_nodes(level_definition: Dictionary) -> void:
	if _level_id.is_empty() or not is_instance_valid(_level_root):
		return

	var objects_raw = level_definition.get("objects", {})
	if typeof(objects_raw) != TYPE_DICTIONARY:
		return

	var objects: Dictionary = objects_raw
	for raw_target_id in objects.keys():
		var target_id := String(raw_target_id)
		var object_data: Dictionary = objects.get(raw_target_id, {})
		var kind := String(object_data.get("kind", ""))
		if kind == "team_respawn_budget":
			continue
		if not _synced_nodes.has(target_id):
			push_warning("Catalog target_id %s is not present as sync_id in %s." % [target_id, _level_id])

	var checked_nodes: Dictionary = {}
	for group_name in NETWORK_GROUPS:
		for node in _find_nodes_in_group(_level_root, StringName(group_name)):
			var instance_id := node.get_instance_id()
			if checked_nodes.has(instance_id):
				continue
			checked_nodes[instance_id] = true
			if node_sync_id(node).is_empty():
				push_warning("Network-relevant node %s is missing sync_id in %s." % [str(node.get_path()), _level_id])


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
