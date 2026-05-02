extends Control


func _ready() -> void:
	pass


func _on_offline_butt_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/offline/offline_game.tscn")


func _on_start_butt_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/online_menu.tscn")


func _on_quit_butt_pressed() -> void:
	get_tree().quit()
