extends Node2D

@onready var chainsaw : AnimatableBody2D = $Chainsaw

func _ready() -> void:
	chainsaw.position = Vector2(305.473,-56.499)
	chainsaw.activation = true
