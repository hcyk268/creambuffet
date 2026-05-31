class_name MapCard
extends Button

signal map_chosen(map_id: String)

@onready var _thumbnail: TextureRect = $VBox/Thumbnail
@onready var _title: Label = $VBox/Title
@onready var _subtitle: Label = $VBox/Subtitle
@onready var _wip_badge: Label = $VBox/WipBadge

var map_id: String = ""
var _pending_entry: Dictionary = {}


func _ready() -> void:
	pressed.connect(_emit_chosen)
	if not _pending_entry.is_empty():
		_apply_entry(_pending_entry)
		_pending_entry.clear()


func configure(entry: Dictionary) -> void:
	if not is_node_ready():
		_pending_entry = entry.duplicate(true)
		return

	_apply_entry(entry)


func _apply_entry(entry: Dictionary) -> void:
	map_id = String(entry.get("map_id", ""))
	_title.text = String(entry.get("title", map_id))
	_subtitle.text = String(entry.get("subtitle", ""))

	var thumb_path := String(entry.get("thumbnail_path", "")).strip_edges()
	if thumb_path.is_empty() or not ResourceLoader.exists(thumb_path):
		_thumbnail.visible = false
		_thumbnail.texture = null
	else:
		_thumbnail.texture = load(thumb_path) as Texture2D
		_thumbnail.visible = _thumbnail.texture != null

	var selectable := bool(entry.get("selectable", true))
	var is_wip := bool(entry.get("wip", false))
	disabled = not selectable
	modulate = Color(1, 1, 1, 1) if selectable else Color(0.55, 0.55, 0.55, 1)
	_wip_badge.visible = is_wip


func _emit_chosen() -> void:
	if disabled:
		return
	map_chosen.emit(map_id)
