extends Node
class_name StateMachine

const PlayerStateController = preload("res://scripts/states/player_state_controller.gd")

signal state_transitioned(previous_state_name: StringName, new_state_name: StringName)

@export var initialState : State

var currentState : State
var states : Dictionary = {}
var _controller: PlayerStateController


func _ready() -> void:
	_controller = PlayerStateController.new(get_parent() as CharacterBody2D)

	for child in get_children():
		if child is State:
			states[child.name.to_lower()] = child
			child.transitioned.connect(_state_transition)
			child.controller = _controller

	var starting_state: State = _resolve_initial_state()
	if starting_state == null:
		push_warning("StateMachine could not resolve an initial state.")
		return

	starting_state.enter()
	currentState = starting_state


func _process(delta: float) -> void:
	if currentState:
		currentState.update(delta)


func _physics_process(delta: float) -> void:
	if currentState:
		currentState.physics_update(delta)


func _unhandled_input(event: InputEvent) -> void:
	if currentState:
		currentState.handle_input(event)


func _state_transition(oldState: State, newStateName: String) -> void:
	if oldState != currentState:
		return

	var newState: State = states.get(newStateName.to_lower(), null)
	if newState == null:
		return

	if currentState:
		currentState.exit()

	newState.enter()
	currentState = newState
	state_transitioned.emit(StringName(oldState.name.to_lower()), StringName(newState.name.to_lower()))


func _resolve_initial_state() -> State:
	if initialState == null:
		push_warning("StateMachine has no initialState; falling back to Idle if available.")
		return states.get("idle", null)
	if initialState.get_parent() != self:
		push_warning("StateMachine initialState is not a child of this StateMachine; falling back to Idle if available.")
		return states.get("idle", null)
	return initialState
