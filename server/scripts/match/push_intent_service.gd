extends RefCounted
class_name PushIntentService

const INTENT_TTL_MS := 300


static func apply(match_state, peer_id: int, raw_intents) -> Array[Dictionary]:
	if not match_state.has_player(peer_id):
		return snapshot(match_state)

	var next_peer_intents: Dictionary = {}
	if typeof(raw_intents) == TYPE_ARRAY:
		for raw_intent in raw_intents:
			if typeof(raw_intent) != TYPE_DICTIONARY:
				continue

			var intent: Dictionary = Dictionary(raw_intent).duplicate(true)
			var target_id := String(intent.get("target_id", intent.get("node_name", ""))).strip_edges()
			if target_id.is_empty():
				continue

			var object_state: Dictionary = match_state.get_object_data(target_id)
			if object_state.is_empty():
				continue
			if String(object_state.get("kind", "")) != "push_box":
				continue
			if not match_state.can_player_observe_push_box(peer_id, target_id):
				continue

			next_peer_intents[target_id] = {
				"target_id": target_id,
				"node_name": String(intent.get("node_name", target_id)),
				"direction": clampf(float(intent.get("direction", 0.0)), -1.0, 1.0),
				"strength": clampf(float(intent.get("strength", 1.0)), 0.0, 1.0),
				"updated_at_ms": Time.get_ticks_msec(),
			}

	match_state.push_intents[peer_id] = next_peer_intents
	return snapshot(match_state)


static func snapshot(match_state) -> Array[Dictionary]:
	var controls_by_target: Dictionary = {}
	var now_ms := Time.get_ticks_msec()

	for raw_peer_id in match_state.push_intents.keys():
		var peer_id := int(raw_peer_id)
		if not match_state.has_player(peer_id):
			continue

		var peer_intents_raw: Variant = match_state.push_intents.get(peer_id, {})
		if typeof(peer_intents_raw) != TYPE_DICTIONARY:
			continue

		var peer_intents: Dictionary = peer_intents_raw
		for raw_target in peer_intents.keys():
			var target_id := String(raw_target)
			var intent_raw: Variant = peer_intents.get(target_id, {})
			if typeof(intent_raw) != TYPE_DICTIONARY:
				continue

			var intent: Dictionary = intent_raw
			if now_ms - int(intent.get("updated_at_ms", 0)) > INTENT_TTL_MS:
				continue

			var drive_x := float(controls_by_target.get(target_id, 0.0))
			drive_x += float(intent.get("direction", 0.0)) * float(intent.get("strength", 1.0))
			controls_by_target[target_id] = clampf(drive_x, -1.0, 1.0)

	var states: Array[Dictionary] = []
	var targets := controls_by_target.keys()
	targets.sort()

	for raw_target in targets:
		var target_id := String(raw_target)
		states.append({
			"target_id": target_id,
			"node_name": target_id,
			"drive_x": float(controls_by_target.get(target_id, 0.0)),
		})

	return states
