extends Node
class_name StateMachine

@export var initialState : State  # This var will appear in the Inspector tab

var currentState : State

# Populate the StateMachine using dictionary
var states : Dictionary = {}
func _ready() -> void:
	
	for child in get_children(): 
		if child is State:
			states[child.name.to_lower()] = child
			child.Transitioned.connect(_state_transition) # Signal link with event
			child.parent = get_parent()
			
	if initialState:
		initialState.enter()
		currentState = initialState

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if currentState:
		currentState.update(delta)
		
func _physics_process(delta: float) -> void:
	if currentState:
		currentState.physics_update(delta)

func _unhandled_input(event: InputEvent) -> void:
	currentState.handle_input(event)
	
func _state_transition(oldState, newStateName):
	if oldState != currentState:
		return
	
	var newState = states.get(newStateName.to_lower())
	if !newState:
		return
	
	# Transition happens here
	if currentState:
		currentState.exit()
		
	newState.enter()
	currentState = newState

	
