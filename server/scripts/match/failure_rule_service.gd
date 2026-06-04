extends RefCounted
class_name FailureRuleService


static func configure(level_definition: Dictionary, now_ms: int = Time.get_ticks_msec()) -> Dictionary:
	var failure_state := {
		"time_limit": {},
		"death_limit": {},
	}

	var raw_failure_rules: Variant = level_definition.get("failure_rules", [])
	if typeof(raw_failure_rules) == TYPE_ARRAY:
		for raw_rule in raw_failure_rules:
			if typeof(raw_rule) != TYPE_DICTIONARY:
				continue

			var rule: Dictionary = raw_rule
			match String(rule.get("type", "")):
				"time_limit":
					var seconds := maxf(float(rule.get("seconds", 0.0)), 0.0)
					if seconds <= 0.0:
						continue
					failure_state["time_limit"] = {
						"enabled": true,
						"duration_ms": int(round(seconds * 1000.0)),
						"started_at_ms": now_ms,
					}
				"death_limit":
					var hearts := maxi(int(rule.get("hearts", rule.get("max_deaths", 0))), 0)
					if hearts <= 0:
						continue
					failure_state["death_limit"] = {
						"enabled": true,
						"hearts_max": hearts,
						"hearts_remaining": hearts,
						"shared": bool(rule.get("shared", true)),
					}

	return {
		"level_started_at_ms": now_ms,
		"failure_state": failure_state,
		"level_reset_pending": false,
	}


static func register_hazard_death(failure_state: Dictionary) -> Dictionary:
	var next_failure_state: Dictionary = failure_state.duplicate(true)
	var death_limit: Dictionary = next_failure_state.get("death_limit", {})
	if death_limit.is_empty() or not bool(death_limit.get("enabled", false)):
		return {
			"failure_state": next_failure_state,
			"hearts_remaining": -1,
		}

	var hearts_remaining := maxi(int(death_limit.get("hearts_remaining", 0)) - 1, 0)
	death_limit["hearts_remaining"] = hearts_remaining
	next_failure_state["death_limit"] = death_limit
	return {
		"failure_state": next_failure_state,
		"hearts_remaining": hearts_remaining,
	}


static func consume_level_failure(
	failure_state: Dictionary,
	level_started_at_ms: int,
	level_reset_pending: bool,
	now_ms: int = Time.get_ticks_msec()
) -> Dictionary:
	if level_reset_pending:
		return {
			"failure": {},
			"level_reset_pending": true,
		}

	var time_limit: Dictionary = failure_state.get("time_limit", {})
	if not time_limit.is_empty() and time_remaining_ms(failure_state, level_started_at_ms, now_ms) <= 0:
		return {
			"failure": {
				"reason": "time_limit",
			},
			"level_reset_pending": true,
		}

	var death_limit: Dictionary = failure_state.get("death_limit", {})
	if not death_limit.is_empty() and int(death_limit.get("hearts_remaining", 0)) <= 0:
		return {
			"failure": {
				"reason": "death_limit",
			},
			"level_reset_pending": true,
		}

	return {
		"failure": {},
		"level_reset_pending": false,
	}


static func snapshot(failure_state: Dictionary, level_started_at_ms: int, now_ms: int = Time.get_ticks_msec()) -> Dictionary:
	var result := {
		"time_limit": {
			"enabled": false,
			"duration_ms": 0,
			"started_at_ms": level_started_at_ms,
			"remaining_ms": 0,
		},
		"death_limit": {
			"enabled": false,
			"hearts_max": 0,
			"hearts_remaining": 0,
			"shared": true,
		},
	}

	var time_limit: Dictionary = failure_state.get("time_limit", {})
	if not time_limit.is_empty():
		result["time_limit"] = {
			"enabled": true,
			"duration_ms": int(time_limit.get("duration_ms", 0)),
			"started_at_ms": int(time_limit.get("started_at_ms", level_started_at_ms)),
			"remaining_ms": time_remaining_ms(failure_state, level_started_at_ms, now_ms),
		}

	var death_limit: Dictionary = failure_state.get("death_limit", {})
	if not death_limit.is_empty():
		result["death_limit"] = {
			"enabled": true,
			"hearts_max": int(death_limit.get("hearts_max", 0)),
			"hearts_remaining": int(death_limit.get("hearts_remaining", 0)),
			"shared": bool(death_limit.get("shared", true)),
		}

	return result


static func time_remaining_ms(failure_state: Dictionary, level_started_at_ms: int, now_ms: int) -> int:
	var time_limit: Dictionary = failure_state.get("time_limit", {})
	if time_limit.is_empty():
		return 0

	var duration_ms := int(time_limit.get("duration_ms", 0))
	var started_at_ms := int(time_limit.get("started_at_ms", level_started_at_ms))
	return maxi(duration_ms - (now_ms - started_at_ms), 0)
