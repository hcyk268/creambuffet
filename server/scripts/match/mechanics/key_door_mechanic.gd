extends RefCounted


func apply_collect(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	var object_state: Dictionary = match_state._get_required_object(target_id, ["key"], "collect")
	if not bool(object_state.get("ok", false)):
		return object_state
	if not match_state.can_player_interact_with_trigger(peer_id, target_id):
		return match_state._error("interaction_out_of_range", "Player must overlap the key trigger to collect it.")

	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})
	if bool(state.get("collected", false)):
		return match_state._error("world_action_rejected", "Key has already been collected.")

	state["collected"] = true
	state["collector_peer_id"] = peer_id
	object_data["state"] = state
	match_state.objects[target_id] = object_data

	var player_state: Dictionary = match_state.players[peer_id]
	player_state["key_count"] = int(player_state.get("key_count", 0)) + 1
	match_state.players[peer_id] = player_state

	var events: Array[Dictionary] = []
	events.append(match_state._event("key_collected", "collect", peer_id, target_id, {"state": state.duplicate(true)}))
	events.append_array(_apply_links_for_source(match_state, peer_id, target_id, "collected", true))
	return match_state._ok(events)


func apply_open(match_state, peer_id: int, target_id: String, _payload: Dictionary = {}) -> Dictionary:
	var object_state: Dictionary = match_state._get_required_object(target_id, ["door", "exit_door"], "open")
	if not bool(object_state.get("ok", false)):
		return object_state
	if not match_state.can_player_interact_with_trigger(peer_id, target_id):
		return match_state._error("interaction_out_of_range", "Player must overlap the door trigger to open it.")

	var object_data: Dictionary = object_state["object"]
	var state: Dictionary = object_data.get("state", {})
	if bool(state.get("opened", false)):
		return match_state._error("world_action_rejected", "Door is already open.")

	var player_state: Dictionary = match_state.players[peer_id]
	var requires: Dictionary = {}
	var raw_requires: Variant = object_data.get("requires", {})
	if typeof(raw_requires) == TYPE_DICTIONARY:
		requires = raw_requires

	if _uses_team_key_requirement(requires):
		var team_key_counts := _consume_team_keys(match_state, requires, peer_id)
		if team_key_counts.is_empty() and not _team_key_requirement_deposited(match_state, requires):
			return match_state._error("missing_team_key", "Team has no carried key to deposit at this door.")

		state["deposited_key_count"] = _deposited_team_key_count(match_state, requires)
		object_data["state"] = state
		match_state.objects[target_id] = object_data

		if not _team_key_requirement_deposited(match_state, requires):
			var deposit_events: Array[Dictionary] = []
			deposit_events.append(match_state._event("door_key_deposited", "open", peer_id, target_id, {
				"state": state.duplicate(true),
				"player_key_counts": team_key_counts,
			}))
			return match_state._ok(deposit_events)

		state["opened"] = true
		state["opened_by_peer_id"] = peer_id
		state["deposited_key_count"] = _deposited_team_key_count(match_state, requires)
		object_data["state"] = state
		match_state.objects[target_id] = object_data

		var team_events: Array[Dictionary] = []
		team_events.append(match_state._event("door_opened", "open", peer_id, target_id, {
			"state": state.duplicate(true),
			"player_key_counts": team_key_counts,
		}))
		return match_state._ok(team_events)

	var required_count := int(requires.get("count", 0))
	if required_count > 0 and int(player_state.get("key_count", 0)) < required_count:
		return match_state._error("missing_key", "Player does not have the required key.")

	if required_count > 0:
		player_state["key_count"] = int(player_state.get("key_count", 0)) - required_count
		match_state.players[peer_id] = player_state

	state["opened"] = true
	state["opened_by_peer_id"] = peer_id
	object_data["state"] = state
	match_state.objects[target_id] = object_data

	var events: Array[Dictionary] = []
	events.append(match_state._event("door_opened", "open", peer_id, target_id, {
		"state": state.duplicate(true),
		"player_key_counts": {
			str(peer_id): int(player_state.get("key_count", 0)),
		},
	}))
	return match_state._ok(events)


func _uses_team_key_requirement(requires: Dictionary) -> bool:
	if requires.has("key_ids"):
		return true
	return String(requires.get("scope", "")).strip_edges().to_lower() == "team"


func _team_key_requirement_met(match_state, requires: Dictionary) -> bool:
	var raw_key_ids: Variant = requires.get("key_ids", [])
	if typeof(raw_key_ids) == TYPE_ARRAY and not raw_key_ids.is_empty():
		for raw_key_id in raw_key_ids:
			var key_id := String(raw_key_id)
			var key_object: Dictionary = match_state._get_object(key_id)
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
	for raw_object in match_state.objects.values():
		if typeof(raw_object) != TYPE_DICTIONARY:
			continue
		var object_data: Dictionary = raw_object
		if String(object_data.get("kind", "")) != "key":
			continue
		var state: Dictionary = object_data.get("state", {})
		if bool(state.get("collected", false)):
			collected_count += 1

	return collected_count >= required_count


func _team_key_requirement_deposited(match_state, requires: Dictionary) -> bool:
	var raw_key_ids: Variant = requires.get("key_ids", [])
	if typeof(raw_key_ids) == TYPE_ARRAY and not raw_key_ids.is_empty():
		for raw_key_id in raw_key_ids:
			var key_object: Dictionary = match_state._get_object(String(raw_key_id))
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
			var key_object: Dictionary = match_state._get_object(String(raw_key_id))
			if key_object.is_empty():
				continue
			var key_state: Dictionary = key_object.get("state", {})
			if bool(key_state.get("spent", false)):
				deposited_count += 1
		return deposited_count

	for raw_object in match_state.objects.values():
		if typeof(raw_object) != TYPE_DICTIONARY:
			continue
		var object_data: Dictionary = raw_object
		if String(object_data.get("kind", "")) != "key":
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
		for raw_target_id in match_state.objects.keys():
			if remaining <= 0:
				break
			var target_id := String(raw_target_id)
			var object_data: Dictionary = match_state._get_object(target_id)
			if String(object_data.get("kind", "")) != "key":
				continue
			var state: Dictionary = object_data.get("state", {})
			if not bool(state.get("collected", false)) or bool(state.get("spent", false)):
				continue
			if _consume_key_object(match_state, target_id, depositing_peer_id, consumed_by_peer):
				remaining -= 1

	var key_counts: Dictionary = {}
	for raw_peer_id in consumed_by_peer.keys():
		var collector_peer_id := int(raw_peer_id)
		if not match_state.players.has(collector_peer_id):
			continue
		var player_state: Dictionary = match_state.players[collector_peer_id]
		player_state["key_count"] = maxi(
			int(player_state.get("key_count", 0)) - int(consumed_by_peer[raw_peer_id]),
			0
		)
		match_state.players[collector_peer_id] = player_state
		key_counts[str(collector_peer_id)] = int(player_state.get("key_count", 0))
	return key_counts


func _consume_key_object(match_state, key_id: String, depositing_peer_id: int, consumed_by_peer: Dictionary) -> bool:
	var key_object: Dictionary = match_state._get_object(key_id)
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
	match_state.objects[key_id] = key_object
	return true


func _apply_links_for_source(match_state, peer_id: int, source_target_id: String, source_field: String, source_value) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var raw_links: Variant = match_state.level_definition.get("links", [])
	if typeof(raw_links) != TYPE_ARRAY:
		return events

	for raw_link in raw_links:
		if typeof(raw_link) != TYPE_DICTIONARY:
			continue

		var link: Dictionary = raw_link
		if String(link.get("source_target_id", "")) != source_target_id:
			continue
		if String(link.get("source_field", "")) != source_field:
			continue
		if link.get("source_value", null) != source_value:
			continue

		var target_id := String(link.get("target_id", ""))
		var target: Dictionary = match_state._get_object(target_id)
		if target.is_empty():
			continue

		var target_state: Dictionary = target.get("state", {})
		var target_field := String(link.get("target_field", ""))
		if target_field.is_empty():
			continue

		var operation := String(link.get("target_operation", link.get("operation", "set"))).strip_edges().to_lower()
		match operation:
			"toggle":
				target_state[target_field] = not bool(target_state.get(target_field, false))
			"increment":
				target_state[target_field] = int(target_state.get(target_field, 0)) + int(link.get("target_value", 1))
			"decrement":
				target_state[target_field] = int(target_state.get(target_field, 0)) - int(link.get("target_value", 1))
			_:
				target_state[target_field] = link.get("target_value", true)

		target["state"] = target_state
		match_state.objects[target_id] = target
		events.append(match_state._event("object_state_changed", "linked_state", peer_id, target_id, {
			"state": target_state.duplicate(true),
			"operation": operation,
			"source_target_id": source_target_id,
		}))

	return events
