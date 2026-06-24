extends Node
class_name PlayerBubbleComponent

const BUBBLE_EFFECT_SCENE := preload("res://prefabs/bubble_effect.tscn")
const PlayerBubbleEffects = preload("res://scripts/player_bubble_effects.gd")

@export var bubble_breath_interval := 0.7
@export var bubble_swim_interval := 0.16
@export var bubble_swim_velocity_threshold := 45.0
@export var bubble_trail_lifetime := 0.75

var _effects: PlayerBubbleEffects
var _owner: CharacterBody2D
var _visual: PlayerVisual
var _water: PlayerWaterComponent


func setup(
	owner: CharacterBody2D,
	bubble_effect: AnimatedSprite2D,
	visual: PlayerVisual,
	water: PlayerWaterComponent
) -> void:
	_owner = owner
	_visual = visual
	_water = water
	_effects = PlayerBubbleEffects.new()
	_effects.setup(
		owner,
		bubble_effect,
		BUBBLE_EFFECT_SCENE,
		bubble_breath_interval,
		bubble_swim_interval,
		bubble_swim_velocity_threshold,
		bubble_trail_lifetime
	)


func reset() -> void:
	if _effects != null:
		_effects.reset()


func update_visibility() -> void:
	if _effects != null and _water != null:
		_effects.update_visibility(_water.is_in_water())


func process(delta: float) -> void:
	if _effects == null or _water == null or _visual == null:
		return

	_effects.process(
		delta,
		_water.is_in_water(),
		_owner.velocity if _owner != null else Vector2.ZERO,
		_visual.get_facing_direction()
	)
