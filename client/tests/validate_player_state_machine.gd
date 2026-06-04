extends SceneTree

const PlayerScene = preload("res://scenes/player_soda.tscn")
const State = preload("res://scripts/states/state.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var player := PlayerScene.instantiate()
	if player == null:
		failures.append("Could not instantiate player_soda.tscn.")
		_finish(failures)
		return

	root.add_child(player)
	await process_frame

	var state_machine := player.get_node_or_null("StateMachine")
	if state_machine == null:
		failures.append("player_soda.tscn is missing StateMachine.")
	else:
		if state_machine.get("currentState") == null:
			failures.append("StateMachine did not resolve a current state for player_soda.tscn.")
		for child in state_machine.get_children():
			if child is State and child.get("controller") == null:
				failures.append("State %s did not receive a PlayerStateController." % child.name)

	player.queue_free()
	await process_frame
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("Player state machine validation passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)
