extends Node2D
#Active in inpector -> wrong position
#Not active -> won't move
#=> Active in code :v

@onready var mv : AnimatableBody2D = $MovingPlatform
@onready var mv2 : AnimatableBody2D = $MovingPlatform2
@onready var mv3 : AnimatableBody2D = $MovingPlatform3
@onready var mv4 : AnimatableBody2D = $MovingPlatform4

func _ready() -> void:
	mv.position = Vector2(-128.0,27.0)
	mv2.position = Vector2(161.0,4.0)
	mv3.position = Vector2(162.0,32.0)
	mv4.position = Vector2(163.0,60.0)
	mv.activation = true
	mv2.activation = true
	mv4.activation = true
	if DisplayServer.get_name() == "headless":
		mv3.activation = true
		return
	_activate_delayed_platform()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _activate_delayed_platform() -> void:
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(mv3):
		mv3.activation = true
