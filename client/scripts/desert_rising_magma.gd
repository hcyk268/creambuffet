extends Area2D
signal player_death(body: Node)

@export var sync_id := ""

# --- New Rising Properties ---
@export var rising_time: float = 10.0       # How many seconds to wait before rising
@export var magma_speed: float = 20.0      # How fast it stretches upwards (pixels per second)

var _time_elapsed: float = 0.0
var _is_rising: bool = false

@onready var nine_patch: NinePatchRect = $NinePatchRect
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	add_to_group("level_hazard")
	body_entered.connect(_on_body_entered)
	if animation_player:
		animation_player.play("magma_idle_moving")


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


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	player_death.emit(body)
	if not _is_online_session() and body.has_method("die"):
		body.die()


func _is_online_session() -> bool:
	var network_client: Node = get_node_or_null("/root/NetworkClient")
	if network_client == null or not network_client.has_method("get_current_room"):
		return false

	var current_room = network_client.get_current_room()
	return typeof(current_room) == TYPE_DICTIONARY and not current_room.is_empty()
