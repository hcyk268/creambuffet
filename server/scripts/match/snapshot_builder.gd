extends RefCounted
class_name SnapshotBuilder

const GameIds = preload("res://scripts/catalog/game_ids.gd")
const ObjectStateQuery = preload("res://scripts/match/object_state_query.gd")


static func build(match_state) -> Dictionary:
	var completion_rules: Array = []
	var raw_completion_rules: Variant = match_state.level_definition.get("completion_rules", [])
	if typeof(raw_completion_rules) == TYPE_ARRAY:
		completion_rules = raw_completion_rules.duplicate(true)

	return {
		"map_id": match_state.map_id,
		"current_level": match_state.current_level,
		"current_level_id": match_state.current_level_id,
		"server_time_ms": Time.get_ticks_msec(),
		"level_definition": match_state.level_definition.duplicate(true),
		"completion_rules": completion_rules,
		"failure_state": match_state.failure_state_snapshot(),
		"objects": match_state.objects.duplicate(true),
		"key_collected": ObjectStateQuery.any_object_state(match_state.objects, GameIds.OBJECT_KIND_KEY, "collected", true),
		"door_opened": (
			ObjectStateQuery.any_object_state(match_state.objects, GameIds.OBJECT_KIND_DOOR, "opened", true)
			or ObjectStateQuery.any_object_state(match_state.objects, GameIds.OBJECT_KIND_EXIT_DOOR, "opened", true)
		),
		"goal_requires_opened_door": _has_door_completion_rule(match_state.level_definition),
		"pushables": match_state.pushable_control_snapshot(),
		"players": match_state.players.duplicate(true),
		"players_at_goal": match_state.players_at_goal.keys(),
		"can_complete_level": match_state.can_complete_level(),
	}


static func _has_door_completion_rule(level_definition: Dictionary) -> bool:
	var raw_rules: Variant = level_definition.get("completion_rules", [])
	if typeof(raw_rules) != TYPE_ARRAY:
		return false

	for raw_rule in raw_rules:
		if typeof(raw_rule) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = raw_rule
		if String(rule.get("type", "")) == "object_state_equals" and String(rule.get("field", "")) == "opened":
			return true
	return false
