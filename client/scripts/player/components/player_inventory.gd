extends Node
class_name PlayerInventory

@export var carried_key_offset := Vector2(0, -46)
@export var carried_key_bob_amplitude := 2.0
@export var carried_key_bob_speed := 5.0

var key_count := 0
var carried_key_color := Color.WHITE
var has_torch := false
var current_light_scale := 4.0

var _carried_key_sprite: Sprite2D
var _torch_light: PointLight2D
var _carried_key_bob_time := 0.0


func setup(carried_key_sprite: Sprite2D, torch_light: PointLight2D) -> void:
	_carried_key_sprite = carried_key_sprite
	_torch_light = torch_light
	if _torch_light != null:
		_torch_light.enabled = false


func process(delta: float) -> void:
	if _carried_key_sprite == null or not _carried_key_sprite.visible:
		return

	_carried_key_bob_time += delta
	_carried_key_sprite.position = carried_key_offset + Vector2(
		0,
		sin(_carried_key_bob_time * carried_key_bob_speed) * carried_key_bob_amplitude
	)


func set_key_count(value: int) -> void:
	key_count = max(value, 0)
	_update_key_indicator()


func collect_key(amount: int = 1, key_color: Color = Color.WHITE) -> void:
	key_count += amount
	carried_key_color = key_color
	_update_key_indicator()


func set_carried_key_color(key_color: Color) -> void:
	carried_key_color = key_color
	_update_key_indicator()


func has_key() -> bool:
	return key_count > 0


func use_key(amount: int = 1) -> bool:
	if key_count < amount:
		return false

	key_count -= amount
	_update_key_indicator()
	return true


func collect_torch() -> void:
	has_torch = true
	if _torch_light != null:
		_torch_light.enabled = true


func add_light_buff() -> void:
	if not has_torch:
		if _torch_light != null:
			_torch_light.enabled = false
		return

	if _torch_light != null:
		_torch_light.enabled = true
	current_light_scale += 3.0
	if _torch_light != null:
		_torch_light.texture_scale = current_light_scale


func turn_off_light() -> void:
	has_torch = false
	current_light_scale = 4.0
	if _torch_light != null:
		_torch_light.enabled = false
		_torch_light.texture_scale = current_light_scale


func update_key_indicator() -> void:
	if _carried_key_sprite == null:
		return

	var should_show := key_count > 0
	if should_show and not _carried_key_sprite.visible:
		_carried_key_bob_time = 0.0
		_carried_key_sprite.position = carried_key_offset

	_carried_key_sprite.visible = should_show
	if should_show:
		_carried_key_sprite.modulate = carried_key_color
	if not should_show:
		_carried_key_sprite.position = carried_key_offset
		_carried_key_sprite.modulate = Color.WHITE


func _update_key_indicator() -> void:
	update_key_indicator()
