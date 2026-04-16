extends StaticBody2D

signal door_opened
signal door_closed

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var detection_area: Area2D = $DetectionArea

var is_open := false


func _ready() -> void:
	add_to_group("level_door")
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	_apply_state()


func set_open(value: bool) -> void:
	if is_open == value:
		return

	is_open = value
	_apply_state()

	if is_open:
		door_opened.emit()
	else:
		door_closed.emit()


func open() -> void:
	set_open(true)


func close() -> void:
	set_open(false)


func _on_detection_area_body_entered(body: Node) -> void:
	if is_open or not body.is_in_group("player"):
		return

	if body.has_method("has_key") and body.has_key():
		open()


func _apply_state() -> void:
	animated_sprite.play("open" if is_open else "closed")
	# body_entered signals can run during physics query flushing, so defer shape toggles.
	collision_shape.set_deferred("disabled", is_open)
	detection_area.set_deferred("monitoring", not is_open)
