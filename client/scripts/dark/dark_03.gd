extends Node2D

@onready var chainsaw : AnimatableBody2D = $Chainsaw

func _ready() -> void:
	chainsaw.position = Vector2(320.0,44.0)
	chainsaw.activation = true
