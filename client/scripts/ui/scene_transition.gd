extends CanvasLayer

const DURATION = 0.5
var cover: ColorRect
var _tween: Tween

signal transition_finished

func _ready() -> void:
	layer = 100
	cover = ColorRect.new()
	cover.color = Color(0.0, 0.0, 0.0, 0.0)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.anchor_right  = 1.0
	cover.anchor_bottom = 1.0
	add_child(cover)

func change_scene(path: String) -> void:
	if _tween and _tween.is_running():
		return
	cover.color.a = 0.0
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(cover, "color:a", 1.0, DURATION)
	_tween.tween_callback(func():
		get_tree().change_scene_to_file(path)
		await get_tree().process_frame
		_sweep_out()
	)
	await transition_finished

func _sweep_out() -> void:
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(cover, "color:a", 0.0, DURATION * 0.8)
	_tween.tween_callback(func():
		cover.color.a = 0.0
		transition_finished.emit()
	)
