extends Area2D
signal player_death(body: Node)

@export var sync_id := ""

# --- New Rising Properties ---
@export var rising_time: float = 10.0       # How many seconds to wait before rising
@export var magma_speed: float = 20.0      # How fast it stretches upwards (pixels per second)

const MAGMA_SURFACE_KILL_PADDING := 8.0

var _time_elapsed: float = 0.0
var _is_rising: bool = false
var _tracked_bodies: Dictionary = {}

@onready var nine_patch: NinePatchRect = $NinePatchRect
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	add_to_group("level_hazard")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if collision_shape and collision_shape.shape:
		collision_shape.shape = collision_shape.shape.duplicate()
	if animation_player:
		animation_player.play("magma_idle_moving")
	call_deferred("_sync_overlaps")


func _physics_process(delta: float) -> void:
	# 1. Handle the delay timer
	if not _is_rising:
		_time_elapsed += delta
		if _time_elapsed >= rising_time:
			_is_rising = true

	# 2. Handle the stretching/rising movement safely
	if _is_rising:
		var growth := magma_speed * delta

		# Move the entire Area2D position UPWARDS
		position.y -= growth

		# Stretch the visual texture down so it covers the screen
		if nine_patch:
			nine_patch.size.y += growth

		# Grow the collision shape to match the visual so the full
		# rising area is lethal, not just the original thin strip.
		if collision_shape and collision_shape.shape is RectangleShape2D:
			var rect: RectangleShape2D = collision_shape.shape
			rect.size.y += growth
			# Shift the shape down by half the growth so the top edge
			# stays aligned with the Area2D origin while the bottom extends.
			collision_shape.position.y += growth * 0.5

	_sync_overlaps()


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
				# A respawned player can still be inside the magma; allow
				# the overlap to trigger again instead of being permanently
				# suppressed by the previous death.
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
	if nine_patch != null:
		return Rect2(global_position + nine_patch.position, nine_patch.size)

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
