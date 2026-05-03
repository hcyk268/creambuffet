class_name LevelCard
extends Button

signal level_chosen(level_id: String)

var level_id: String = ""


func configure(id: String) -> void:
	level_id = id
	text = id


func _ready() -> void:
	pressed.connect(_emit_chosen)


func _emit_chosen() -> void:
	level_chosen.emit(level_id)
