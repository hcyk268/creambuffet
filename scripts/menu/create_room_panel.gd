extends Control

@onready var player_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox1/PlayerLineEdit
@onready var world_input: LineEdit = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox2/WorldLineEdit
@onready var rand_butt: TextureButton = $TextureRect2/MarginContainer/VBoxContainer/Grid/HBox2/HBoxContainer/RandButt

const MIN_PLAYERS = 1
const MAX_PLAYERS = 4

const MIN_WORLDS = 1
const MAX_WORLDS = 5

var current_players: int = 1
var current_worlds: int = 1

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Cập nhật số lên màn hình ngay khi vừa mở bảng
	update_displays()
	
	# Đảm bảo LineEdit không cho người chơi tự gõ chữ bậy bạ vào (Chỉ đọc)
	player_input.editable = false
	world_input.editable = false
	
func update_displays() -> void:
	player_input.text = str(current_players)
	world_input.text = str(current_worlds)

func _on_player_up_pressed() -> void:
	if current_players < MAX_PLAYERS:
		current_players += 1
		update_displays()

func _on_player_down_pressed() -> void:
	if current_players > MIN_PLAYERS:
		current_players -= 1
		update_displays()
		
func _on_world_up_pressed() -> void:
	if current_worlds < MAX_WORLDS:
		current_worlds += 1
		update_displays()

func _on_world_down_pressed() -> void:
	if current_worlds > MIN_WORLDS:
		current_worlds -= 1
		update_displays()

func _on_back_butt_pressed() -> void:
	self.hide()


func _on_create_butt_pressed() -> void:
	# Lấy trạng thái của nút CheckBox (True nếu có dấu tích, False nếu không)
	var is_randomized: bool = rand_butt.button_pressed
	
	# In ra Output để kiểm tra xem đã lấy đúng dữ liệu chưa
	print("--- TẠO PHÒNG ---")
	print("Số người chơi: ", current_players)
	print("Số thế giới: ", current_worlds)
	print("Có Random không?: ", is_randomized)
