extends Area2D

signal collected(body: Node, sync_id: String)
@export var sync_id := ""

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return

	collected.emit(body)
