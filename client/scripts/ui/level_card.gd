class_name LevelCard
extends Button

signal level_chosen(level_index: int)

const CARD_BG := preload("res://assets/sprites/UI-LevelCard.png")
const REGION_LIGHT := Rect2(16, 16, 32, 32)
const REGION_DARK := Rect2(64, 16, 32, 32)

@onready var _thumbnail: TextureRect = $MarginContainer/Content/Thumbnail
@onready var _level_number: Label = $MarginContainer/Content/LevelNumber

var level_index := -1
var level_id := ""
var _pending_entry: Dictionary = {}
var _style_light: StyleBoxTexture
var _style_dark: StyleBoxTexture
var _highlighted := false


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	text = ""
	mouse_filter = Control.MOUSE_FILTER_STOP
	pressed.connect(_emit_chosen)
	_style_light = _make_stylebox(REGION_LIGHT)
	_style_dark = _make_stylebox(REGION_DARK)
	set_highlighted(false)
	if not _pending_entry.is_empty():
		_apply_entry(_pending_entry)
		_pending_entry.clear()


func configure(entry: Dictionary) -> void:
	if not is_node_ready():
		_pending_entry = entry.duplicate(true)
		return
	_apply_entry(entry)


func set_highlighted(highlighted: bool) -> void:
	_highlighted = highlighted
	_apply_visual_state()


func set_selected(selected: bool) -> void:
	set_highlighted(selected)


func _apply_entry(entry: Dictionary) -> void:
	level_index = int(entry.get("level_index", -1))
	level_id = String(entry.get("level_id", ""))
	visible = bool(entry.get("visible", true))
	disabled = not bool(entry.get("enabled", true))
	set_highlighted(bool(entry.get("selected", false)) or bool(entry.get("highlighted", false)))

	if _level_number != null:
		if level_index >= 0:
			_level_number.text = str(level_index + 1)
		else:
			_level_number.text = ""

	if _thumbnail == null:
		return

	var thumbnail_texture := entry.get("thumbnail_texture", null) as Texture2D
	var thumbnail_path := String(entry.get("thumbnail_path", "")).strip_edges()
	if thumbnail_texture != null:
		_thumbnail.texture = thumbnail_texture
		_thumbnail.visible = true
	elif not thumbnail_path.is_empty() and ResourceLoader.exists(thumbnail_path):
		_thumbnail.texture = load(thumbnail_path) as Texture2D
		_thumbnail.visible = _thumbnail.texture != null
	else:
		_thumbnail.texture = null
		_thumbnail.visible = false


func _apply_visual_state() -> void:
	if _style_light == null or _style_dark == null:
		return

	var active := _style_light if _highlighted else _style_dark
	add_theme_stylebox_override("normal", active)
	add_theme_stylebox_override("hover", active)
	add_theme_stylebox_override("pressed", active)
	add_theme_stylebox_override("focus", active)


func _make_stylebox(region: Rect2) -> StyleBoxTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = CARD_BG
	atlas.region = region
	var style := StyleBoxTexture.new()
	style.texture = atlas
	return style


func _emit_chosen() -> void:
	if level_index < 0 or disabled:
		return
	level_chosen.emit(level_index)
