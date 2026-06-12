# res://scripts/ui/level_transition.gd
extends CanvasLayer

const DURATION_IN  := 0.55
const DURATION_OUT := 0.45

var _cover: ColorRect
var _tween: Tween

signal swept_in   # giữa chừng: lúc màn hình đã bị che → gọi load thật
signal swept_out  # hoàn tất: màn hình đã hiện ra


func _ready() -> void:
	layer = 100
	_cover = ColorRect.new()
	_cover.color = Color(0.08, 0.08, 0.12, 1.0)   # tối hơi xanh cho đẹp
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hide_offscreen()
	add_child(_cover)


# Gọi hàm này thay vì load_level trực tiếp
# callback: Callable sẽ được gọi khi màn hình đã tối (lúc đó mới load level)
func transition(callback: Callable) -> void:
	if _tween and _tween.is_running():
		return
	_sweep_in(callback)


# ── private ──────────────────────────────────────────────────────────────────

func _sweep_in(callback: Callable) -> void:
	var vp  : Vector2 = get_viewport().size
	_cover.anchor_right  = 0.0
	_cover.anchor_bottom = 0.0
	_cover.size          = Vector2(vp.x, vp.y)
	_cover.position      = Vector2(0.0, -vp.y)   # bắt đầu từ trên

	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	# slide xuống che màn hình
	_tween.tween_property(_cover, "position:y", 0.0, DURATION_IN)
	_tween.tween_callback(func():
		swept_in.emit()
		callback.call()          # ← load level xảy ra ở đây
		# chờ 1 frame để level render xong rồi mới sweep out
		await get_tree().process_frame
		await get_tree().process_frame
		_sweep_out()
	)


func _sweep_out() -> void:
	var vp_h : int = get_viewport().size.y
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	# slide tiếp xuống dưới màn hình
	_tween.tween_property(_cover, "position:y", vp_h, DURATION_OUT)
	_tween.tween_callback(func():
		_hide_offscreen()
		swept_out.emit()
	)


func _hide_offscreen() -> void:
	if _cover == null:
		return
	_cover.anchor_right  = 1.0
	_cover.anchor_bottom = 1.0
	_cover.offset_top    = -10000.0
	_cover.offset_bottom = -10000.0 + 2000.0
	_cover.size          = Vector2.ZERO
	_cover.position      = Vector2.ZERO
