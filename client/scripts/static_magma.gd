extends Area2D
signal player_death(body: Node)

@export var sync_id := ""

const MAGMA_SURFACE_KILL_PADDING := 0.0

var _tracked_bodies: Dictionary = {}


func _ready() -> void:
	add_to_group("level_hazard")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	call_deferred("_sync_overlaps")


func _on_body_entered(body: Node) -> void:
	if not _is_valid_body(body):
		return
	if not (body is Node2D):
		return

	var body_node := body as Node2D
	if not _body_hits_magma(body_node):
		return

	var body_id := body.get_instance_id()
	if _tracked_bodies.has(body_id):
		return

	_tracked_bodies[body_id] = body
	_kill_player(body)


func _on_body_exited(body: Node) -> void:
	_tracked_bodies.erase(body.get_instance_id())


func _sync_overlaps() -> void:
	var seen_ids: Dictionary = {}

	for body in get_tree().get_nodes_in_group("player"):
		if not (body is Node2D):
			continue
		if not _is_valid_body(body):
			continue

		var body_node := body as Node2D
		var body_id := body_node.get_instance_id()
		if _body_hits_magma(body_node):
			seen_ids[body_id] = true
			if _tracked_bodies.has(body_id):
				# A respawned player can still be inside the magma; allow the
				# overlap to trigger again instead of being permanently ignored.
				if body.has_method("is_eliminated") and bool(body.call("is_eliminated")):
					continue
				_tracked_bodies.erase(body_id)
			_tracked_bodies[body_id] = body_node
			_kill_player(body_node)

	for raw_body_id in _tracked_bodies.keys().duplicate():
		var body_id := int(raw_body_id)
		if seen_ids.has(body_id):
			continue
		_tracked_bodies.erase(body_id)


func _is_valid_body(body: Node) -> bool:
	if body == null or not body.is_in_group("player"):
		return false
	if body.has_method("is_eliminated") and bool(body.call("is_eliminated")):
		return false
	return true


func _body_hits_magma(body: Node2D) -> bool:
	var player_shape_node := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if player_shape_node == null or player_shape_node.shape == null:
		return false
	if not (player_shape_node.shape is CircleShape2D):
		return false

	var magma_rect := _magma_rectangle()
	if magma_rect.size == Vector2.ZERO:
		return false

	var circle_shape: CircleShape2D = player_shape_node.shape
	var circle_center: Vector2 = player_shape_node.global_position
	var player_bottom := circle_center.y + circle_shape.radius
	var player_left := circle_center.x - circle_shape.radius
	var player_right := circle_center.x + circle_shape.radius
	var magma_left := magma_rect.position.x
	var magma_right := magma_rect.position.x + magma_rect.size.x
	var magma_top := magma_rect.position.y
	var magma_bottom := magma_rect.position.y + magma_rect.size.y

	if player_right < magma_left or player_left > magma_right:
		return false
	if circle_center.y > magma_bottom:
		return false
	return player_bottom >= magma_top + MAGMA_SURFACE_KILL_PADDING


func _magma_rectangle() -> Rect2:
	var collision_shape := $CollisionShape2D as CollisionShape2D
	if collision_shape == null or collision_shape.shape == null:
		return Rect2()
	if not (collision_shape.shape is RectangleShape2D):
		return Rect2()

	var rect_shape: RectangleShape2D = collision_shape.shape
	var half_size := rect_shape.size * 0.5
	return Rect2(
		collision_shape.global_position - half_size,
		rect_shape.size
	)


func _kill_player(body: Node) -> void:
	player_death.emit(body)
	if _is_online_session():
		if body.has_method("set_input_enabled"):
			body.set_input_enabled(false)
		if body is CharacterBody2D:
			(body as CharacterBody2D).velocity = Vector2.ZERO
		return

	if body.has_method("die"):
		body.die()


func _is_online_session() -> bool:
	var network_client: Node = get_node_or_null("/root/NetworkClient")
	if network_client == null or not network_client.has_method("get_current_room"):
		return false

	var current_room = network_client.get_current_room()
	return typeof(current_room) == TYPE_DICTIONARY and not current_room.is_empty()
