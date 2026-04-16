extends Area2D

signal collected(body: Node)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	if body.has_method("collect_key"):
		body.collect_key()
		_unlock_all_doors()

	collected.emit(body)
	queue_free()


func _unlock_all_doors() -> void:
	for node in get_tree().get_nodes_in_group("level_door"):
		if node.has_method("open"):
			node.open()
