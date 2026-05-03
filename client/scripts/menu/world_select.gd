extends Control

# ============================================================
# World Select - prefab LevelCard (PackedScene.instantiate)
# ============================================================
# Spawn grid trong _ready() tu mang WORLDS - them world/level chi sua data.
# Signal `level_chosen` tu moi card -> _select_level(level_id).
#
# Ghi chu kien truc:
#   - Server hien tai (server_main.gd) chua nhan thong tin "world chon"
#     tu client; viec chon world chi anh huong client-side cho den khi
#     server ho tro. Vi vay luu lua chon vao class-level static var de
#     code khac (lobby/online_game) co the doc khi can.
# ============================================================

const LEVEL_CARD_SCENE := preload("res://prefabs/ui/level_card.tscn")
const SECTION_FONT := preload("res://assets/fonts/EXEPixelPerfect.ttf")

const WORLDS := [
	{"title": "WORLD 1", "levels": ["1-1", "1-2", "1-3", "1-4"]},
	{"title": "WORLD 2", "levels": ["2-1", "2-2", "2-3", "2-4"]},
	{"title": "WORLD 3", "levels": ["3-1", "3-2", "3-3", "3-4"]},
]

# Luu lua chon level cuoi cung; cac scene khac co the doc qua
# WorldSelect.last_selected_level. Khong dung autoload de tranh state global.
static var last_selected_level: String = ""

@onready var _worlds_container: VBoxContainer = $Margin/Vbox/Scroll/Worlds


func _ready() -> void:
	_build_world_sections()


func _build_world_sections() -> void:
	while _worlds_container.get_child_count() > 0:
		var old: Node = _worlds_container.get_child(0)
		_worlds_container.remove_child(old)
		old.free()

	for world_data in WORLDS:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 16)

		var title := Label.new()
		title.text = world_data["title"]
		title.add_theme_font_override("font", SECTION_FONT)
		title.add_theme_font_size_override("font_size", 60)
		section.add_child(title)

		var center := CenterContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 24)

		for level_id in world_data["levels"]:
			var card: LevelCard = LEVEL_CARD_SCENE.instantiate() as LevelCard
			card.configure(level_id)
			card.level_chosen.connect(_select_level)
			grid.add_child(card)

		center.add_child(grid)
		section.add_child(center)
		_worlds_container.add_child(section)


func _select_level(level_id: String) -> void:
	last_selected_level = level_id
	print("[WorldSelect] Selected: ", level_id)
	# TODO (server): khi server ho tro chon world cu the, gui request o day:
	#   NetworkClient.send_world_event({"type": "select_world", "level": level_id})
	# Hien tai chi quay ve room/lobby.
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_back_butt_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
