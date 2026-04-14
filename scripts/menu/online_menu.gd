extends Control

@onready var enter_id_panel = $EnterIdPanel
@onready var create_room_panel = $CreateRoomPanel

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_public_butt_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_private_butt_pressed() -> void:
	enter_id_panel.show()


func _on_host_butt_pressed() -> void:
	create_room_panel.show()


func _on_option_butt_pressed() -> void:
	pass # Replace with function body.
