extends Area2D

signal collected(body: Node)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if body.has_method("collect_key"):
		body.collect_key()

	collected.emit(body)
	queue_free()
