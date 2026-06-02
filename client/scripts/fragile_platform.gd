extends StaticBody2D

@export var sync_id := ""
@export var stand_time := 0.5
@export var disappeared_time := 1.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var stand_detector: Area2D = $StandDetector

var _state := "idle"
var _timer := 0.0
var _tracked_bodies: Dictionary = {}


func _ready() -> void:
	add_to_group("fragile_platform")
	set_physics_process(true)
	stand_detector.body_entered.connect(_on_body_entered)
	stand_detector.body_exited.connect(_on_body_exited)
	call_deferred("_sync_overlaps")


func _physics_process(delta: float) -> void:
	match _state:
		"counting":
			if _tracked_bodies.is_empty():
				_set_state("idle")
				return

			_timer += delta
			if _timer >= maxf(stand_time, 0.0):
				_set_state("hidden")
		"hidden":
			_timer += delta
			if _timer >= maxf(disappeared_time, 0.0):
				_set_state("idle")


func apply_server_state(state: Dictionary) -> void:
	var visible := bool(state.get("visible", true))
	var next_state := "idle" if visible else "hidden"
	_state = next_state
	_timer = float(state.get("timer", 0.0))
	_set_visuals(visible)


func get_state() -> Dictionary:
	return {
		"visible": _state != "hidden",
		"timer": _timer,
	}


func _on_body_entered(body: Node2D) -> void:
	if not _is_valid_body(body):
		return

	_tracked_bodies[body.get_instance_id()] = body
	if _state == "idle":
		_set_state("counting")


func _on_body_exited(body: Node2D) -> void:
	_tracked_bodies.erase(body.get_instance_id())

	if _tracked_bodies.is_empty() and _state == "counting":
		_set_state("idle")


func _sync_overlaps() -> void:
	_tracked_bodies.clear()
	for body in stand_detector.get_overlapping_bodies():
		if _is_valid_body(body):
			_tracked_bodies[body.get_instance_id()] = body

	if not _tracked_bodies.is_empty() and _state == "idle":
		_set_state("counting")


func _is_valid_body(body: Node) -> bool:
	return body.is_in_group("player")


func _set_state(next_state: String) -> void:
	_state = next_state
	match _state:
		"idle":
			_timer = 0.0
			_set_visuals(true)
			call_deferred("_sync_overlaps")
		"counting":
			_timer = 0.0
		"hidden":
			_timer = 0.0
			_set_visuals(false)


func _set_visuals(visible: bool) -> void:
	sprite.visible = visible
	collision_shape.disabled = not visible
	stand_detector.monitoring = visible
	stand_detector.monitorable = visible
