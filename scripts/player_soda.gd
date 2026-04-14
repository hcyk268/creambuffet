extends CharacterBody2D

@export var SPEED := 150.0
@export var JUMP_VELOCITY := -300.0

# KHÔNG CÒN _physics_process ở đây nữa! 
# Node StateMachine (con của Player) sẽ tự động lấy quyền điều khiển.
#
#func _physics_process(delta: float) -> void:
	#if velocity.length() > 0:
		#sprite.play("run")
	#
	## Add the gravity.
	#if not is_on_floor():
		#velocity += get_gravity() * delta
#
	## Handle jump.
	#if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		#velocity.y = JUMP_VELOCITY
		#sprite.play("idle")
#
	## Get the input direction and handle the movement/deceleration.
	## As good practice, you should replace UI actions with custom gameplay actions.
	#var direction := Input.get_axis("ui_left", "ui_right")
	#if direction:
		#velocity.x = direction * SPEED
	#else:
		#velocity.x = move_toward(velocity.x, 0, SPEED)
#
	#move_and_slide()
##
	
