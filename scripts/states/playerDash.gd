extends State
class_name PlayerDash

@export var dash_speed: float = 800.0 # Tốc độ lướt (nên nhanh hơn SPEED bình thường)
@export var dash_duration: float = 0.2 # Thời gian lướt tính bằng giây

var timer: float = 0.0
var dash_direction: float = 1.0

func enter() -> void:
	var anim = parent.get_node("AnimationPlayer")
	anim.play("dash")
	timer = dash_duration # Bắt đầu đếm ngược thời gian lướt
	
	# 1. XÁC ĐỊNH HƯỚNG LƯỚT
	var input_dir = Input.get_axis("left", "right")
	if input_dir != 0:
		dash_direction = input_dir
	else:
		# Nếu đứng yên mà bấm lướt, sẽ lướt theo hướng đang quay mặt
		var sprite = parent.get_node("Sprite2D")
		dash_direction = -1.0 if sprite.flip_h else 1.0
		
	# 2. XÓA TRỌNG LỰC VÀ BƠM VẬN TỐC
	parent.velocity.y = 0 
	parent.velocity.x = dash_direction * dash_speed

func physics_update(delta: float) -> void:
	# 1. TRỪ THỜI GIAN
	timer -= delta
	
	# 2. CẬP NHẬT VẬT LÝ
	parent.move_and_slide()
	
	# 3. KẾT THÚC LƯỚT KHI HẾT GIỜ
	if timer <= 0:
		if not parent.is_on_floor():
			Transitioned.emit(self, "fall")
		else:
			# Kiểm tra xem người chơi có đang đè phím chạy không
			var direction = Input.get_axis("left", "right")
			if direction != 0:
				Transitioned.emit(self, "run")
			else:
				Transitioned.emit(self, "idle")
