extends Area2D
signal player_death
@export var sync_id := ""

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	player_death.emit()
