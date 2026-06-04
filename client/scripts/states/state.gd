extends Node
class_name State

const PlayerStateController = preload("res://scripts/states/player_state_controller.gd")

signal transitioned
var controller: PlayerStateController


func enter() -> void:
	pass


func exit() -> void:
	pass


func update(_delta: float) -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func handle_input(_event: InputEvent) -> void:
	pass
