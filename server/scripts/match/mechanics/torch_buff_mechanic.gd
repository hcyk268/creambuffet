extends RefCounted

const GameIds = preload("res://scripts/catalog/game_ids.gd")

func apply_collect_torch(
	match_state,
	peer_id: int,
	target_id: String,
	_payload: Dictionary = {}
) -> Dictionary:

	var object_state: Dictionary = match_state.require_object(
		target_id,
		[GameIds.OBJECT_KIND_TORCH],
		GameIds.ACTION_COLLECT_TORCH
	)

	if not bool(object_state.get("ok", false)):
		return object_state

	if not match_state.can_player_interact_with_trigger(peer_id, target_id):
		return match_state.error(
			"interaction_out_of_range",
			"Player must overlap the torch trigger."
		)

	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})

	if bool(state.get("collected", false)):
		return match_state.error(
			"world_action_rejected",
			"Torch has already been collected."
		)

	state["collected"] = true
	state["collector_peer_id"] = peer_id

	object_data["state"] = state
	match_state.set_object_data(target_id, object_data)

	var events: Array[Dictionary] = []

	events.append(
		match_state.event(
			GameIds.EVENT_TORCH_COLLECTED,
			GameIds.ACTION_COLLECT_TORCH,
			peer_id,
			target_id,
			{
				"state": state.duplicate(true)
			}
		)
	)

	return match_state.ok(events)


func apply_collect_buff(
	match_state,
	peer_id: int,
	target_id: String,
	_payload: Dictionary = {}
) -> Dictionary:

	var object_state: Dictionary = match_state.require_object(
		target_id,
		[GameIds.OBJECT_KIND_BUFF],
		GameIds.ACTION_COLLECT_BUFF
	)

	if not bool(object_state.get("ok", false)):
		return object_state

	if not match_state.can_player_interact_with_trigger(peer_id, target_id):
		return match_state.error(
			"interaction_out_of_range",
			"Player must overlap the buff trigger."
		)

	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})

	if bool(state.get("collected", false)):
		return match_state.error(
			"world_action_rejected",
			"Buff has already been collected."
		)

	state["collected"] = true
	state["collector_peer_id"] = peer_id

	var current_level := int(state.get("buff_level", 0))
	state["buff_level"] = current_level + 1

	object_data["state"] = state
	match_state.set_object_data(target_id, object_data)

	var torch_owner_peer_id := find_torch_owner(match_state)

	var events: Array[Dictionary] = []

	events.append(
		match_state.event(
			GameIds.EVENT_BUFF_COLLECTED,
			GameIds.ACTION_COLLECT_BUFF,
			peer_id,
			target_id,
			{
				"state": state.duplicate(true),
				"buff_level": state["buff_level"],
				"torch_owner_peer_id": torch_owner_peer_id
			}
		)
	)

	return match_state.ok(events)
	
	
func find_torch_owner(match_state) -> int:
	for object_id in match_state.object_ids():
		var object_data: Dictionary = match_state.get_object_data(object_id)

		if String(object_data.get("kind", "")) != GameIds.OBJECT_KIND_TORCH:
			continue

		var state: Dictionary = object_data.get("state", {})

		if bool(state.get("collected", false)):
			return int(state.get("collector_peer_id", 0))

	return 0
