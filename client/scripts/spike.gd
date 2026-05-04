extends Area2D
signal player_death
@export var sync_id := ""

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	player_death.emit()
