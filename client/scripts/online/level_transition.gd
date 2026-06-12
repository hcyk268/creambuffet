extends CanvasLayer
class_name LevelTransition

const DURATION_IN := 0.55
const DURATION_OUT := 0.45

var _cover: ColorRect
var _tween: Tween

signal swept_in
signal swept_out


func _ready() -> void:
	layer = 100
	_cover = ColorRect.new()
	_cover.color = Color(0.08, 0.08, 0.12, 1.0)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)
	_configure_cover_layout()
	_hide_offscreen()


func transition(callback: Callable) -> void:
	if _should_skip_animation():
		swept_in.emit()
		callback.call()
		swept_out.emit()
		return
	if _tween and _tween.is_running():
		return
	_sweep_in(callback)


func _sweep_in(callback: Callable) -> void:
	var viewport_size: Vector2 = get_viewport().size
	_configure_cover_layout()
	_cover.visible = true
	_cover.position = Vector2(0.0, -viewport_size.y)

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_cover, "position:y", 0.0, DURATION_IN)
	_tween.tween_callback(func():
		swept_in.emit()
		callback.call()
		await get_tree().process_frame
		await get_tree().process_frame
		_sweep_out()
	)


func _sweep_out() -> void:
	var viewport_height: float = get_viewport().size.y
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_cover, "position:y", viewport_height, DURATION_OUT)
	_tween.tween_callback(func():
		_hide_offscreen()
		swept_out.emit()
	)


func _hide_offscreen() -> void:
	if _cover == null:
		return
	_configure_cover_layout()
	_cover.visible = false
	_cover.position = Vector2(0.0, -get_viewport().size.y)


func _should_skip_animation() -> bool:
	return DisplayServer.get_name() == "headless"


func _configure_cover_layout() -> void:
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.offset_left = 0.0
	_cover.offset_top = 0.0
	_cover.offset_right = 0.0
	_cover.offset_bottom = 0.0
