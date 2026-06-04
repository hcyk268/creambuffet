extends RefCounted

const GameIds = preload("res://scripts/catalog/game_ids.gd")
const LinkApplier = preload("res://scripts/match/link_applier.gd")


func apply_collect(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	var object_state: Dictionary = match_state.require_object(target_id, [GameIds.OBJECT_KIND_KEY], GameIds.ACTION_COLLECT)
	if not bool(object_state.get("ok", false)):
		return object_state
	if not match_state.can_player_interact_with_trigger(peer_id, target_id):
		return match_state.error("interaction_out_of_range", "Player must overlap the key trigger to collect it.")

	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})
	if bool(state.get("collected", false)):
		return match_state.error("world_action_rejected", "Key has already been collected.")

	state["collected"] = true
	state["collector_peer_id"] = peer_id
	object_data["state"] = state
	match_state.set_object_data(target_id, object_data)
	match_state.add_player_keys(peer_id, 1)

	var events: Array[Dictionary] = []
	events.append(match_state.event(GameIds.EVENT_KEY_COLLECTED, GameIds.ACTION_COLLECT, peer_id, target_id, {"state": state.duplicate(true)}))
	events.append_array(LinkApplier.apply_links_for_source(match_state, peer_id, target_id, "collected", true))
	return match_state.ok(events)


func apply_open(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	var object_state: Dictionary = match_state.require_object(target_id, GameIds.DOOR_KINDS, GameIds.ACTION_OPEN)
	if not bool(object_state.get("ok", false)):
		return object_state
	if not match_state.can_player_interact_with_trigger(peer_id, target_id):
		return match_state.error("interaction_out_of_range", "Player must overlap the door trigger to open it.")

	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})
	if bool(state.get("opened", false)):
		return match_state.error("world_action_rejected", "Door is already open.")

	var player_state: Dictionary = match_state.get_player_runtime(peer_id)
	var requires: Dictionary = {}
	var raw_requires: Variant = object_data.get("requires", {})
	if typeof(raw_requires) == TYPE_DICTIONARY:
		requires = raw_requires

	if _uses_team_key_requirement(requires):
		var team_key_counts := _consume_team_keys(match_state, requires, peer_id)
		if team_key_counts.is_empty() and not _team_key_requirement_deposited(match_state, requires):
			return match_state.error("missing_team_key", "Team has no carried key to deposit at this door.")

		state["deposited_key_count"] = _deposited_team_key_count(match_state, requires)
		object_data["state"] = state
		match_state.set_object_data(target_id, object_data)

		if not _team_key_requirement_deposited(match_state, requires):
			var deposit_events: Array[Dictionary] = []
			deposit_events.append(match_state.event(GameIds.EVENT_DOOR_KEY_DEPOSITED, GameIds.ACTION_OPEN, peer_id, target_id, {
				"state": state.duplicate(true),
				"player_key_counts": team_key_counts,
			}))
			return match_state.ok(deposit_events)

		state["opened"] = true
		state["opened_by_peer_id"] = peer_id
		state["deposited_key_count"] = _deposited_team_key_count(match_state, requires)
		object_data["state"] = state
		match_state.set_object_data(target_id, object_data)

		var team_events: Array[Dictionary] = []
		team_events.append(match_state.event(GameIds.EVENT_DOOR_OPENED, GameIds.ACTION_OPEN, peer_id, target_id, {
			"state": state.duplicate(true),
			"player_key_counts": team_key_counts,
		}))
		return match_state.ok(team_events)

	var required_count := int(requires.get("count", 0))
	if required_count > 0 and match_state.player_key_count(peer_id) < required_count:
		return match_state.error("missing_key", "Player does not have the required key.")

	if required_count > 0:
		player_state = match_state.consume_player_keys(peer_id, required_count)

	state["opened"] = true
	state["opened_by_peer_id"] = peer_id
	object_data["state"] = state
	match_state.set_object_data(target_id, object_data)

	var events: Array[Dictionary] = []
	events.append(match_state.event(GameIds.EVENT_DOOR_OPENED, GameIds.ACTION_OPEN, peer_id, target_id, {
		"state": state.duplicate(true),
		"player_key_counts": {
			str(peer_id): int(player_state.get("key_count", 0)),
		},
	}))
	return match_state.ok(events)


func _uses_team_key_requirement(requires: Dictionary) -> bool:
	if requires.has("key_ids"):
		return true
	return String(requires.get("scope", "")).strip_edges().to_lower() == "team"


func _team_key_requirement_met(match_state, requires: Dictionary) -> bool:
	var raw_key_ids: Variant = requires.get("key_ids", [])
	if typeof(raw_key_ids) == TYPE_ARRAY and not raw_key_ids.is_empty():
		for raw_key_id in raw_key_ids:
			var key_id := String(raw_key_id)
			var key_object: Dictionary = match_state.get_object_data(key_id)
			if key_object.is_empty():
				return false
			var key_state: Dictionary = key_object.get("state", {})
			if not bool(key_state.get("collected", false)):
				return false
		return true

	var required_count := int(requires.get("count", 0))
	if required_count <= 0:
		return true

	var collected_count := 0
	for target_id in match_state.object_ids():
		var object_data: Dictionary = match_state.get_object_data(target_id)
		if String(object_data.get("kind", "")) != GameIds.OBJECT_KIND_KEY:
			continue
		var state: Dictionary = object_data.get("state", {})
		if bool(state.get("collected", false)):
			collected_count += 1

	return collected_count >= required_count


func _team_key_requirement_deposited(match_state, requires: Dictionary) -> bool:
	var raw_key_ids: Variant = requires.get("key_ids", [])
	if typeof(raw_key_ids) == TYPE_ARRAY and not raw_key_ids.is_empty():
		for raw_key_id in raw_key_ids:
			var key_object: Dictionary = match_state.get_object_data(String(raw_key_id))
			if key_object.is_empty():
				return false
			var key_state: Dictionary = key_object.get("state", {})
			if not bool(key_state.get("spent", false)):
				return false
		return true

	var required_count := int(requires.get("count", 0))
	if required_count <= 0:
		return true
	return _deposited_team_key_count(match_state, requires) >= required_count


func _deposited_team_key_count(match_state, requires: Dictionary) -> int:
	var raw_key_ids: Variant = requires.get("key_ids", [])
	var deposited_count := 0
	if typeof(raw_key_ids) == TYPE_ARRAY and not raw_key_ids.is_empty():
		for raw_key_id in raw_key_ids:
			var key_object: Dictionary = match_state.get_object_data(String(raw_key_id))
			if key_object.is_empty():
				continue
			var key_state: Dictionary = key_object.get("state", {})
			if bool(key_state.get("spent", false)):
				deposited_count += 1
		return deposited_count

	for target_id in match_state.object_ids():
		var object_data: Dictionary = match_state.get_object_data(target_id)
		if String(object_data.get("kind", "")) != GameIds.OBJECT_KIND_KEY:
			continue
		var state: Dictionary = object_data.get("state", {})
		if bool(state.get("spent", false)):
			deposited_count += 1
	return deposited_count


func _consume_team_keys(match_state, requires: Dictionary, depositing_peer_id: int) -> Dictionary:
	var consumed_by_peer: Dictionary = {}
	var raw_key_ids: Variant = requires.get("key_ids", [])
	if typeof(raw_key_ids) == TYPE_ARRAY and not raw_key_ids.is_empty():
		for raw_key_id in raw_key_ids:
			_consume_key_object(match_state, String(raw_key_id), depositing_peer_id, consumed_by_peer)
	else:
		var remaining := int(requires.get("count", 0))
		for target_id in match_state.object_ids():
			if remaining <= 0:
				break
			var object_data: Dictionary = match_state.get_object_data(target_id)
			if String(object_data.get("kind", "")) != GameIds.OBJECT_KIND_KEY:
				continue
			var state: Dictionary = object_data.get("state", {})
			if not bool(state.get("collected", false)) or bool(state.get("spent", false)):
				continue
			if _consume_key_object(match_state, target_id, depositing_peer_id, consumed_by_peer):
				remaining -= 1

	var key_counts: Dictionary = {}
	for raw_peer_id in consumed_by_peer.keys():
		var collector_peer_id := int(raw_peer_id)
		if not match_state.has_player(collector_peer_id):
			continue
		var player_state: Dictionary = match_state.consume_player_keys(collector_peer_id, int(consumed_by_peer[raw_peer_id]))
		key_counts[str(collector_peer_id)] = int(player_state.get("key_count", 0))
	return key_counts


func _consume_key_object(match_state, key_id: String, depositing_peer_id: int, consumed_by_peer: Dictionary) -> bool:
	var key_object: Dictionary = match_state.get_object_data(key_id)
	if key_object.is_empty():
		return false

	var key_state: Dictionary = key_object.get("state", {})
	if not bool(key_state.get("collected", false)) or bool(key_state.get("spent", false)):
		return false

	var collector_peer_id := int(key_state.get("collector_peer_id", 0))
	if collector_peer_id != depositing_peer_id:
		return false

	if collector_peer_id > 0:
		consumed_by_peer[collector_peer_id] = int(consumed_by_peer.get(collector_peer_id, 0)) + 1

	key_state["spent"] = true
	key_object["state"] = key_state
	match_state.set_object_data(key_id, key_object)
	return true
