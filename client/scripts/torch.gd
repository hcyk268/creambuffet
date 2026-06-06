extends Area2D
@export var sync_id := ""

signal torch_collected(body: Node)

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if not body.is_in_group("player"):
		return

	torch_collected.emit(body)
