extends Node
class_name PlayerVisual

const LAND_SPRITE_TEXTURE := preload("res://assets/sprites/Player-sheet.png")
const DASH_SPRITE_TEXTURE := preload("res://assets/sprites/Player-Soda.png")
const LAND_SPRITE_HFRAMES := 5
const LAND_SPRITE_VFRAMES := 8
const DASH_SPRITE_VFRAMES := 6
const LAND_SPRITE_POSITION := Vector2(0, -27)
const LAND_SPRITE_SCALE := Vector2.ONE

var _owner: CharacterBody2D
var _sprite: Sprite2D
var _animation_player: AnimationPlayer
var _facing_direction := 1.0
var _mirror_facing_for_remote := false
var _current_animation := ""


func setup(owner: CharacterBody2D, sprite: Sprite2D, animation_player: AnimationPlayer) -> void:
	_owner = owner
	_sprite = sprite
	_animation_player = animation_player
	if _sprite != null:
		_facing_direction = -1.0 if _sprite.flip_h else 1.0


func set_mirror_facing_for_remote(enabled: bool) -> void:
	_mirror_facing_for_remote = enabled


func play_animation(animation: String) -> void:
	if _animation_player == null or not _animation_player.has_animation(animation):
		return

	_current_animation = animation

	if animation.begins_with("swim"):
		_play_swim_animation()
		return

	_apply_sprite_sheet_for_animation(animation)
	if _animation_player.current_animation != animation or not _animation_player.is_playing():
		_animation_player.play(animation)


func get_animation() -> String:
	if _animation_player == null:
		return ""
	return _animation_player.current_animation


func set_facing_direction(direction: float) -> void:
	if is_zero_approx(direction):
		return

	_facing_direction = signf(direction)
	_apply_visual_facing()


func get_facing_direction() -> float:
	if not is_zero_approx(_facing_direction):
		return _facing_direction
	if _owner != null and not is_zero_approx(_owner.velocity.x):
		return signf(_owner.velocity.x)
	return 1.0


func set_vertical_flip(flipped: bool) -> void:
	if _sprite != null:
		_sprite.flip_v = flipped


func get_flip_h() -> bool:
	return _sprite.flip_h if _sprite != null else false


func set_flip_h(flipped: bool) -> void:
	if _sprite != null:
		_sprite.flip_h = flipped


func apply_sprite_sheet_for_animation(animation: String) -> void:
	if animation.begins_with("swim"):
		_current_animation = animation
		if not _mirror_facing_for_remote:
			_apply_visual_facing()
		return
	_apply_sprite_sheet_for_animation(animation)


func _play_swim_animation() -> void:
	if _animation_player.current_animation != _current_animation or not _animation_player.is_playing():
		_animation_player.play(_current_animation)
	if not _mirror_facing_for_remote:
		_apply_visual_facing()


func _apply_sprite_sheet_for_animation(animation: String) -> void:
	if animation == "dash":
		_apply_sprite_sheet(
			DASH_SPRITE_TEXTURE,
			LAND_SPRITE_HFRAMES,
			DASH_SPRITE_VFRAMES,
			LAND_SPRITE_POSITION,
			LAND_SPRITE_SCALE
		)
	else:
		_apply_sprite_sheet(
			LAND_SPRITE_TEXTURE,
			LAND_SPRITE_HFRAMES,
			LAND_SPRITE_VFRAMES,
			LAND_SPRITE_POSITION,
			LAND_SPRITE_SCALE
		)

	if not _mirror_facing_for_remote:
		_apply_visual_facing()


func _apply_visual_facing() -> void:
	if _sprite == null or _mirror_facing_for_remote:
		return

	_sprite.flip_h = _facing_direction < 0.0


func _apply_sprite_sheet(
	texture: Texture2D,
	hframes: int,
	vframes: int,
	sprite_position: Vector2,
	sprite_scale: Vector2
) -> void:
	if _sprite == null:
		return

	_sprite.texture = texture
	_sprite.hframes = hframes
	_sprite.vframes = vframes
	_sprite.position = sprite_position
	_sprite.scale = sprite_scale

	var max_frame := hframes * vframes
	if max_frame > 0 and _sprite.frame >= max_frame:
		_sprite.frame = 0
