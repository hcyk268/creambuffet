extends Area2D
class_name OxygenTank

signal collected(body: Node)

@export var oxygen_amount := 5.0
@export var consume_on_collect := true
@export var sync_id := ""

@onready var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var collision_shape: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

var _online_authoritative := false
var _available_for_local := true


func _ready() -> void:
	add_to_group("oxygen_pickup")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if _online_authoritative:
		if _available_for_local:
			collected.emit(body)
		return

	if body.has_method("add_oxygen"):
		body.add_oxygen(oxygen_amount)

	collected.emit(body)
	if consume_on_collect:
		queue_free()


func set_online_authoritative(enabled: bool) -> void:
	_online_authoritative = enabled


func apply_server_state(state: Dictionary, local_peer_id: int = 0) -> void:
	var remaining_uses := int(state.get("remaining_uses", 1))
	var claimed_by_local := false
	var claimed_raw: Variant = state.get("claimed_peer_ids", [])
	if typeof(claimed_raw) == TYPE_ARRAY:
		for raw_peer_id in claimed_raw:
			if int(raw_peer_id) == local_peer_id:
				claimed_by_local = true
				break

	var exhausted := remaining_uses <= 0 or bool(state.get("collected", false))
	_available_for_local = not exhausted and not claimed_by_local
	set_deferred("monitoring", _available_for_local)
	set_deferred("monitorable", not exhausted)
	if collision_shape != null:
		collision_shape.set_deferred("disabled", exhausted)

	visible = not exhausted
	if sprite != null and not exhausted:
		sprite.modulate = Color(1, 1, 1, 0.45) if claimed_by_local else Color.WHITE
