extends Node2D

@export var base_camera_position := Vector2.ZERO
@export var layers: Array[NodePath] = []
@export var motion_scales: Array[Vector2] = []
@export var drift_speeds: Array[Vector2] = []

var _layer_nodes: Array[Node2D] = []
var _initial_positions: Array[Vector2] = []
var _drift_offsets: Array[Vector2] = []


func _ready() -> void:
	_layer_nodes.clear()
	_initial_positions.clear()
	_drift_offsets.clear()

	for layer_path in layers:
		var layer := get_node_or_null(layer_path) as Node2D
		if layer == null:
			continue

		_layer_nodes.append(layer)
		_initial_positions.append(layer.global_position)
		_drift_offsets.append(Vector2.ZERO)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return

	var camera_delta := camera.global_position - base_camera_position
	for index in range(_layer_nodes.size()):
		var layer := _layer_nodes[index]
		var motion_scale := _get_vector_at(motion_scales, index, Vector2.ZERO)
		var drift_speed := _get_vector_at(drift_speeds, index, Vector2.ZERO)

		_drift_offsets[index] += drift_speed * delta
		layer.global_position = _initial_positions[index] + camera_delta * motion_scale + _drift_offsets[index]


func _get_vector_at(values: Array[Vector2], index: int, fallback: Vector2) -> Vector2:
	if index < 0 or index >= values.size():
		return fallback

	return values[index]
