extends RefCounted
class_name MechanicRegistry

const KeyDoorMechanic = preload("res://scripts/match/mechanics/key_door_mechanic.gd")
const GoalMechanic = preload("res://scripts/match/mechanics/goal_mechanic.gd")
const HazardRespawnMechanic = preload("res://scripts/match/mechanics/hazard_respawn_mechanic.gd")
const PushBoxMechanic = preload("res://scripts/match/mechanics/push_box_mechanic.gd")
const ButtonPlatformMechanic = preload("res://scripts/match/mechanics/button_platform_mechanic.gd")
const OxygenMechanic = preload("res://scripts/match/mechanics/oxygen_mechanic.gd")
const TorchBuffMechanic = preload("res://scripts/match/mechanics/torch_buff_mechanic.gd")

static func build() -> Dictionary:
	var key_door := KeyDoorMechanic.new()
	var goal := GoalMechanic.new()
	var hazard_respawn := HazardRespawnMechanic.new()
	var push_box := PushBoxMechanic.new()
	var button_platform := ButtonPlatformMechanic.new()
	var oxygen := OxygenMechanic.new()
	var torch_buff := TorchBuffMechanic.new()

	var mechanics := {
		"key_door": key_door,
		"goal": goal,
		"hazard_respawn": hazard_respawn,
		"push_box": push_box,
		"button_platform": button_platform,
		"oxygen": oxygen,
		"torch_buff": torch_buff,
	}
	var handlers := {
		"key_door.collect": Callable(key_door, "apply_collect"),
		"key_door.open": Callable(key_door, "apply_open"),
		"goal.enter": Callable(goal, "apply_enter"),
		"goal.exit": Callable(goal, "apply_exit"),
		"hazard_respawn.player_death": Callable(hazard_respawn, "apply_player_death"),
		"push_box.state": Callable(push_box, "apply_state"),
		"button_platform.button_state": Callable(button_platform, "apply_button_state"),
		"oxygen.collect": Callable(oxygen, "apply_collect"),
		"oxygen.oxygen_depleted": Callable(oxygen, "apply_oxygen_depleted"),
		"torch_buff.collect_torch":Callable(torch_buff,"apply_collect_torch"),
		"torch_buff.collect_buff":Callable(torch_buff,"apply_collect_buff"),
	}
	var hooks := {
		"automatic_player_runtime": [
			Callable(hazard_respawn, "apply_automatic_fall_reset"),
		],
		"post_push_box_observation": [
			Callable(button_platform, "refresh_button_states"),
		],
	}

	return {
		"mechanics": mechanics,
		"handlers": handlers,
		"hooks": hooks,
	}
