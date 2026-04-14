extends State
class_name PlayerFall

func enter() -> void:
	var anim = parent.get_node("AnimationPlayer")
	anim.play("fall")

func physics_update(delta: float) -> void:
	parent.velocity += parent.get_gravity() * delta

	var direction = Input.get_axis("left", "right")
	parent.velocity.x = direction * parent.SPEED
	parent.move_and_slide()
	
	if direction != 0:
		var sprite = parent.get_node("Sprite2D")
		if direction > 0:
			sprite.flip_h = false
		elif direction < 0:
			sprite.flip_h = true
			
	if parent.is_on_floor():
		if direction != 0:
			Transitioned.emit(self, "run")
		else:
			Transitioned.emit(self, "idle")
			
	if Input.is_action_just_pressed("dash"):
		Transitioned.emit(self, "dash")
		return
