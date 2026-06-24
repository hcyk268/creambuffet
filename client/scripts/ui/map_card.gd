class_name MapCard
extends Button

signal map_chosen(map_id: String)

@onready var _thumbnail: TextureRect = $VBox/Thumbnail
@onready var _title: Label = get_node_or_null("VBox/Title") as Label
@onready var _fallback_title: Label = get_node_or_null("Title") as Label
@onready var _subtitle: Label = get_node_or_null("VBox/Subtitle") as Label
@onready var _wip_badge: Label = get_node_or_null("VBox/WipBadge") as Label

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
	var title := String(entry.get("title", map_id))
	if _title != null:
		_title.text = title
	if _fallback_title != null:
		_fallback_title.text = title
	if _subtitle != null:
		_subtitle.text = String(entry.get("subtitle", ""))

	var thumbnail_texture := entry.get("thumbnail_texture", null) as Texture2D
	var thumb_path := String(entry.get("thumbnail_path", "")).strip_edges()
	if thumbnail_texture != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = thumbnail_texture
		atlas.region = Rect2(0, 0, thumbnail_texture.get_width(), thumbnail_texture.get_height())
		_thumbnail.texture = atlas
		_thumbnail.visible = true
	elif thumb_path.is_empty() or not ResourceLoader.exists(thumb_path):
		_thumbnail.visible = false
		_thumbnail.texture = null
	else:
		_thumbnail.texture = load(thumb_path) as Texture2D
		_thumbnail.visible = _thumbnail.texture != null

	var selectable := bool(entry.get("selectable", true))
	var is_wip := bool(entry.get("wip", false))
	disabled = not selectable
	modulate = Color(1, 1, 1, 1) if selectable else Color(0.55, 0.55, 0.55, 1)
	if _wip_badge != null:
		_wip_badge.visible = is_wip


func _emit_chosen() -> void:
	if disabled:
		return
	map_chosen.emit(map_id)
