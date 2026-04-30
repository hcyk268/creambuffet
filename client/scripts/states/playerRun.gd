extends State
class_name PlayerRun

func enter() -> void:
	var anim = parent.get_node("AnimationPlayer")
	anim.play("run")

func physics_update(delta: float) -> void:
	if not parent.is_on_floor():
		parent.velocity += parent.get_gravity() * delta

	var direction = Input.get_axis("left", "right")
	
	if direction != 0:
		parent.velocity.x = direction * parent.SPEED

		var sprite = parent.get_node("Sprite2D") 
		if direction > 0:
			sprite.flip_h = false 
		elif direction < 0:
			sprite.flip_h = true  
			
	else:
		parent.velocity.x = 0

	parent.move_and_slide()

	# Transition between states
	if Input.is_action_just_pressed("jump"):
		Transitioned.emit(self, "jump")
		return

	if not parent.is_on_floor():
		Transitioned.emit(self, "fall")
		return

	if direction == 0:
		Transitioned.emit(self, "idle")
		
	if Input.is_action_just_pressed("dash"):
		Transitioned.emit(self, "dash")
		return
