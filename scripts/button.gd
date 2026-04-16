extends Area2D

signal pressed_state_changed(is_pressed: bool)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var is_pressed := false
var _tracked_bodies: Dictionary = {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	call_deferred("_sync_overlaps")


func _on_body_entered(body: Node2D) -> void:
	if not _is_valid_body(body):
		return

	_tracked_bodies[body.get_instance_id()] = body
	_update_pressed_state()


func _on_body_exited(body: Node2D) -> void:
	_tracked_bodies.erase(body.get_instance_id())
	_update_pressed_state()


func _sync_overlaps() -> void:
	_tracked_bodies.clear()
	for body in get_overlapping_bodies():
		if _is_valid_body(body):
			_tracked_bodies[body.get_instance_id()] = body
	_update_pressed_state()


func _is_valid_body(body: Node) -> bool:
	return body.is_in_group("player") or body.is_in_group("pushable")


func _update_pressed_state() -> void:
	var next_pressed := not _tracked_bodies.is_empty()
	if is_pressed == next_pressed:
		return

	is_pressed = next_pressed
	animated_sprite.play("pressed" if is_pressed else "released")
	pressed_state_changed.emit(is_pressed)
