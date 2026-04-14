extends State
class_name PlayerJump

func enter() -> void:
	var anim = parent.get_node("AnimationPlayer")
	anim.play("air")
	
	parent.velocity.y = parent.JUMP_VELOCITY

func physics_update(delta: float) -> void:
	parent.velocity += parent.get_gravity() * delta

	var direction = Input.get_axis("left", "right")
	parent.velocity.x = direction * parent.SPEED
	
	if direction != 0:
		var sprite = parent.get_node("Sprite2D") 
		if direction > 0:
			sprite.flip_h = false
		elif direction < 0:
			sprite.flip_h = true
	parent.move_and_slide()
	
	if parent.velocity.y > 0:
		Transitioned.emit(self, "fall")
		
	if Input.is_action_just_pressed("dash"):
		Transitioned.emit(self, "dash")
		return
