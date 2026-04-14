extends Control
@onready var id_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/LineEdit

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	id_input.clear()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_back_butt_pressed() -> void:
	self.hide()
	id_input.clear()


func _on_join_butt_pressed() -> void:
	# Lấy chữ trong ô nhập, đồng thời cắt bỏ khoảng trắng thừa ở 2 đầu (nếu có)
	var room_id: String = id_input.text.strip_edges()

	if room_id.is_empty():
		print("Lỗi: Vui lòng nhập mã ID phòng!")
		# Sau này bạn có thể cho rung cái ô nhập hoặc hiện chữ đỏ báo lỗi ở đây
		return

	print("Đã lấy được ID phòng: ", room_id)
	print(">>> Chuẩn bị kích hoạt hệ thống mạng để tham gia... <<<")

	self.hide()
	id_input.clear()
