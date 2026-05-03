extends Area2D

signal goal_reached(body: Node)
signal goal_left(body: Node)


func _ready() -> void:
	add_to_group("level_goal")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	goal_reached.emit(body)


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	goal_left.emit(body)
