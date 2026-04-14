extends State
class_name PlayerIdle

func enter() -> void:
	var anim_sprite = parent.get_node("AnimationPlayer")
	anim_sprite.play("idle")
	parent.velocity.x = 0

func physics_update(_delta: float) -> void:
	if not parent.is_on_floor():
		Transitioned.emit(self, "fall")
		
	if Input.is_action_just_pressed("jump"):
		Transitioned.emit(self, "jump")
		return
	
	var direction = Input.get_axis("left", "right")
	if direction != 0:
		Transitioned.emit(self, "run")
		
	if Input.is_action_just_pressed("dash"):
		Transitioned.emit(self, "dash")
		return
