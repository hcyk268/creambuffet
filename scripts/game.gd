extends Node2D

@export var levels: Array[PackedScene] = []
@export var start_level_index := 0

@onready var player: CharacterBody2D = $Player
@onready var level_container: Node2D = $LevelContainer
@onready var level_label: Label = $CanvasLayer/LevelLabel

var _current_level: Node
var _current_level_index := -1


func _ready() -> void:
	if levels.is_empty():
		push_warning("Game has no levels configured.")
		return

	var safe_start_index := clampi(start_level_index, 0, levels.size() - 1)
	load_level(safe_start_index)


func load_level(index: int) -> void:
	if index < 0 or index >= levels.size():
		push_warning("Invalid level index: %d" % index)
		return

	if is_instance_valid(_current_level):
		_current_level.queue_free()

	_current_level = levels[index].instantiate()
	level_container.add_child(_current_level)
	_current_level_index = index

	_setup_player_spawn(_current_level)
	_connect_level_goals(_current_level)
	_update_level_label(false)


func next_level() -> void:
	if _current_level_index + 1 >= levels.size():
		_update_level_label(true)
		return

	load_level(_current_level_index + 1)


func restart_level() -> void:
	if _current_level_index < 0:
		return

	load_level(_current_level_index)


func _setup_player_spawn(level_root: Node) -> void:
	var spawn_point := level_root.get_node_or_null("SpawnPoint")
	if spawn_point is Node2D:
		player.global_position = spawn_point.global_position
	else:
		player.global_position = Vector2.ZERO

	player.velocity = Vector2.ZERO
	player.spawn_position = player.global_position
	player.key_count = 0


func _connect_level_goals(level_root: Node) -> void:
	var callback := Callable(self, "_on_goal_reached")
	for node in _find_nodes_in_group(level_root, "level_goal"):
		if node.has_signal("goal_reached") and not node.is_connected("goal_reached", callback):
			node.connect("goal_reached", callback)


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


func _on_goal_reached(_body: Node) -> void:
	next_level()


func _update_level_label(game_complete: bool) -> void:
	if game_complete:
		level_label.text = "All levels cleared!"
		return

	level_label.text = "Level %d / %d" % [_current_level_index + 1, levels.size()]
