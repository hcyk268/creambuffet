extends RefCounted
class_name CompletionRuleEvaluator

const GameIds = preload("res://scripts/catalog/game_ids.gd")
const ObjectStateQuery = preload("res://scripts/match/object_state_query.gd")


static func can_complete_level(match_state) -> bool:
	var raw_rules: Variant = match_state.level_definition.get("completion_rules", [])
	if typeof(raw_rules) != TYPE_ARRAY:
		return _all_players_at_goal(match_state)

	var rules: Array = raw_rules
	if rules.is_empty():
		return _all_players_at_goal(match_state)

	for raw_rule in rules:
		if typeof(raw_rule) != TYPE_DICTIONARY:
			return false
		if not _evaluate_completion_rule(match_state, raw_rule):
			return false

	return true


static func _evaluate_completion_rule(match_state, rule: Dictionary) -> bool:
	match String(rule.get("type", "")):
		"all_players_at_goal":
			return _all_players_at_goal(match_state, String(rule.get("target_id", "")))
		"object_state_equals":
			return ObjectStateQuery.object_state_field_equals(
				match_state.objects,
				String(rule.get("target_id", "")),
				String(rule.get("field", "")),
				rule.get("value", null)
			)
		"exit_door_open":
			return (
				ObjectStateQuery.any_object_state(match_state.objects, GameIds.OBJECT_KIND_DOOR, "opened", true)
				or ObjectStateQuery.any_object_state(match_state.objects, GameIds.OBJECT_KIND_EXIT_DOOR, "opened", true)
			)
		_:
			return false


static func _all_players_at_goal(match_state, target_id: String = "") -> bool:
	if match_state.player_ids().is_empty():
		return false

	for peer_id in match_state.player_ids():
		var player_state: Dictionary = match_state.get_player_state(peer_id)
		if not bool(player_state.get("at_goal", false)):
			return false
		if not target_id.is_empty() and String(player_state.get("goal_target_id", "")) != target_id:
			return false

	return true
