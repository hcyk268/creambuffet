extends RefCounted
class_name TimedObjectService

const GameIds = preload("res://scripts/catalog/game_ids.gd")

static func advance(match_state, rng: RandomNumberGenerator, now_ms: int = Time.get_ticks_msec()) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	for target_id in match_state.object_ids():
		var object_data: Dictionary = match_state.get_object_data(target_id)
		if object_data.is_empty():
			continue

		var kind := String(object_data.get("kind", ""))
		if not GameIds.is_water_jet_kind(kind):
			continue

		var timer := object_timer_data(object_data)
		if timer.is_empty():
			continue

		var mode := String(timer.get("mode", "random_toggle")).strip_edges().to_lower()
		if mode != "random_toggle" and mode != "toggle":
			continue

		var state: Dictionary = object_data.get("state", {})
		if not state.has("active"):
			state["active"] = true
		if not state.has("next_toggle_at_ms"):
			schedule_water_jet_toggle(state, timer, now_ms, rng)
			object_data["state"] = state
			match_state.set_object_data(target_id, object_data)
			continue

		if now_ms < int(state.get("next_toggle_at_ms", 0)):
			continue

		state["active"] = not bool(state.get("active", true))
		state["updated_at_ms"] = now_ms
		schedule_water_jet_toggle(state, timer, now_ms, rng)
		object_data["state"] = state
		match_state.set_object_data(target_id, object_data)
		events.append(match_state.event(GameIds.EVENT_OBJECT_STATE_CHANGED, "timed_state", 0, target_id, {
			"state": state.duplicate(true),
		}))

	return events


static func object_timer_data(object_data: Dictionary) -> Dictionary:
	var raw_timer: Variant = object_data.get("timer", object_data.get("schedule", {}))
	if typeof(raw_timer) != TYPE_DICTIONARY:
		return {}
	return Dictionary(raw_timer).duplicate(true)


static func schedule_water_jet_toggle(state: Dictionary, timer: Dictionary, now_ms: int, rng: RandomNumberGenerator) -> void:
	var min_interval := maxi(int(timer.get("min_interval_ms", timer.get("interval_min_ms", 900))), 1)
	var max_interval := maxi(int(timer.get("max_interval_ms", timer.get("interval_max_ms", min_interval))), min_interval)
	state["next_toggle_at_ms"] = now_ms + rng.randi_range(min_interval, max_interval)
