extends Button

const BODY_FONT := preload("res://assets/fonts/EXEPixelPerfect.ttf")
const CARD_BG := preload("res://assets/sprites/Menu1.png")
const PLAYER_ICON := preload("res://assets/sprites/UI-PlayerIcon.png")
const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")

const CARD_SIZE := Vector2(1312, 120)
const TEXT_SIZE := 70
const PING_COLOR := Color(0.42, 0.78, 0.23, 1.0)

var _room_id := ""


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	text = ""
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	_apply_card_style()


func setup(room: Dictionary, ping_ms: int) -> void:
	_room_id = String(room.get("room_id", ""))
	text = ""
	disabled = not bool(room.get("joinable", true))

	for child in get_children():
		remove_child(child)
		child.queue_free()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(row)

	var left_group := HBoxContainer.new()
	left_group.add_theme_constant_override("separation", 32)
	left_group.alignment = BoxContainer.ALIGNMENT_CENTER
	left_group.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var room_label := _make_label("ROOM: %s" % _room_id.to_upper())
	left_group.add_child(room_label)

	var map_id := String(room.get("map_id", GameCatalog.DEFAULT_MAP_ID))
	var map_label := _make_label("MAP: %s" % GameCatalog.get_map_title(map_id).to_upper())
	left_group.add_child(map_label)
	row.add_child(left_group)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var right_group := HBoxContainer.new()
	right_group.add_theme_constant_override("separation", 32)
	right_group.alignment = BoxContainer.ALIGNMENT_CENTER
	right_group.size_flags_horizontal = Control.SIZE_SHRINK_END

	var ping_label := _make_label(_ping_text(ping_ms), PING_COLOR)
	right_group.add_child(ping_label)

	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 8)
	player_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var player_count := int(room.get("player_count", 0))
	var max_players := int(room.get("max_players", 1))
	var count_label := _make_label("%d/%d" % [player_count, max_players])
	player_row.add_child(count_label)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(100, 100)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.texture = PLAYER_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	player_row.add_child(icon)

	right_group.add_child(player_row)
	row.add_child(right_group)


func get_room_id() -> String:
	return _room_id


func _apply_card_style() -> void:
	var normal := StyleBoxTexture.new()
	normal.texture = CARD_BG
	normal.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	normal.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH

	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", normal)
	add_theme_stylebox_override("pressed", normal)
	add_theme_stylebox_override("disabled", normal)
	add_theme_stylebox_override("focus", normal)
	add_theme_font_override("font", BODY_FONT)
	add_theme_font_size_override("font_size", TEXT_SIZE)
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_hover_color", Color.WHITE)
	add_theme_color_override("font_pressed_color", Color.WHITE)
	add_theme_color_override("font_disabled_color", Color(1.0, 1.0, 1.0, 0.45))


func _make_label(text: String, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", TEXT_SIZE)
	label.add_theme_color_override("font_color", color)
	return label


func _ping_text(ping_ms: int) -> String:
	if ping_ms < 0:
		return "PING: --"
	return "PING: %d" % ping_ms
