extends Area2D

signal goal_reached(body: Node)


func _ready() -> void:
	add_to_group("level_goal")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	monitoring = false
	goal_reached.emit(body)
