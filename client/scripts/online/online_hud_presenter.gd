extends RefCounted
class_name OnlineHudPresenter

var _level_label: RichTextLabel
var _water_hud: Control
var _oxygen_bar: ProgressBar
var _oxygen_label: Label
var _respawn_label: Label
var _time_label: Label
var _time_limit_expired: Callable
var _failure_state: Dictionary = {}
var _failure_fallback_state: Dictionary = {}
var _failure_snapshot_ms := 0
var _time_limit_expired_notified := false


func setup(
	level_label: RichTextLabel,
	water_hud: Control,
	oxygen_bar: ProgressBar,
	oxygen_label: Label,
	respawn_label: Label,
	time_label: Label,
	time_limit_expired: Callable = Callable()
) -> void:
	_level_label = level_label
	_water_hud = water_hud
	_oxygen_bar = oxygen_bar
	_oxygen_label = oxygen_label
	_respawn_label = respawn_label
	_time_label = time_label
	_time_limit_expired = time_limit_expired


func update_level_label(
	game_complete: bool,
	current_level_index: int,
	total_levels: int,
	_is_online_session: bool,
	_room: Dictionary,
	_current_level_id: String
) -> void:
	if _level_label == null:
		return

	if game_complete:
		_level_label.text = "All Cleared!"
		return

	var hearts_text := _failure_hearts_text()
	var hearts_suffix := ""
	if not hearts_text.is_empty():
		hearts_suffix = " %s" % hearts_text

	_level_label.text = "%d / %d%s" % [
		current_level_index + 1,
		total_levels,
		hearts_suffix,
	]


func refresh_water_hud(has_oxygen: bool, respawn_state: Dictionary, player: CharacterBody2D) -> void:
	if _water_hud == null or _oxygen_bar == null or _oxygen_label == null or _respawn_label == null:
		return

	var has_respawn_budget := not respawn_state.is_empty()
	_water_hud.visible = has_oxygen or has_respawn_budget
	_oxygen_bar.visible = has_oxygen
	_oxygen_label.visible = has_oxygen
	_respawn_label.visible = has_respawn_budget

	if has_oxygen:
		refresh_oxygen_from_player(player)
	if has_respawn_budget:
		update_respawn_budget(respawn_state)


func refresh_oxygen_from_player(player: CharacterBody2D) -> void:
	if player == null:
		return

	var maximum := float(player.get("max_oxygen"))
	if maximum <= 0.0:
		maximum = 10.0
	var current := float(player.get("oxygen"))
	update_oxygen(current, maximum)


func update_oxygen(current: float, maximum: float) -> void:
	if _oxygen_bar == null or _oxygen_label == null:
		return

	var safe_maximum := maxf(maximum, 1.0)
	var safe_current := clampf(current, 0.0, safe_maximum)
	_oxygen_bar.max_value = safe_maximum
	_oxygen_bar.value = safe_current
	_oxygen_label.text = "O2: %d/%d" % [ceili(safe_current), ceili(safe_maximum)]


func update_respawn_budget(state: Dictionary) -> void:
	if _respawn_label == null:
		return

	var max_respawns := int(state.get("max", state.get("max_respawns", 3)))
	var used_respawns := int(state.get("used", 0))
	var remaining := maxi(max_respawns - used_respawns, 0)
	_respawn_label.text = "Respawn: %d/%d" % [remaining, max_respawns]


func cache_failure_state(room: Dictionary, fallback_level_definition: Dictionary) -> void:
	if room.is_empty():
		_failure_state = {}
		_failure_snapshot_ms = 0
		_time_limit_expired_notified = false
		refresh_failure_fallback_state(fallback_level_definition)
		return

	var match_state_raw = room.get("match_state", {})
	if typeof(match_state_raw) != TYPE_DICTIONARY:
		_failure_state = {}
		_failure_snapshot_ms = 0
		_time_limit_expired_notified = false
		return

	var match_state: Dictionary = match_state_raw
	var failure_state_raw = match_state.get("failure_state", {})
	if typeof(failure_state_raw) != TYPE_DICTIONARY:
		_failure_state = {}
		_failure_snapshot_ms = 0
		_time_limit_expired_notified = false
		return

	_failure_state = Dictionary(failure_state_raw).duplicate(true)
	_failure_snapshot_ms = Time.get_ticks_msec()
	_time_limit_expired_notified = false


func update_failure_hud(
	match_complete: bool,
	current_level_index: int,
	total_levels: int,
	is_online_session: bool,
	room: Dictionary,
	current_level_id: String
) -> void:
	if _level_label == null:
		return

	if match_complete:
		if _time_label != null:
			_time_label.visible = false
		update_level_label(true, current_level_index, total_levels, is_online_session, room, current_level_id)
		return

	var failure_display_state := display_failure_state()
	var time_limit: Dictionary = failure_display_state.get("time_limit", {})
	if _time_label != null:
		if bool(time_limit.get("enabled", false)):
			_time_label.visible = true
			var remaining_ms := _failure_time_remaining_ms(failure_display_state)
			_time_label.text = "TIME %s" % _format_time_ms(remaining_ms)
			if remaining_ms <= 0:
				_emit_time_limit_expired()
		else:
			_time_label.visible = false

	update_level_label(match_complete, current_level_index, total_levels, is_online_session, room, current_level_id)


func decrement_shared_hearts() -> void:
	var failure_state := _failure_state if not _failure_state.is_empty() else _failure_fallback_state
	var death_limit: Dictionary = failure_state.get("death_limit", {})
	if death_limit.is_empty() or not bool(death_limit.get("enabled", false)):
		return

	var hearts_remaining := maxi(int(death_limit.get("hearts_remaining", 0)) - 1, 0)
	death_limit["hearts_remaining"] = hearts_remaining
	failure_state["death_limit"] = death_limit
	if _failure_state.is_empty():
		_failure_fallback_state = failure_state
	else:
		_failure_state = failure_state


func will_eliminate_on_next_death() -> bool:
	var failure_state := display_failure_state()
	var death_limit: Dictionary = failure_state.get("death_limit", {})
	if death_limit.is_empty() or not bool(death_limit.get("enabled", false)):
		return false

	return int(death_limit.get("hearts_remaining", 0)) <= 1


func display_failure_state() -> Dictionary:
	if not _failure_state.is_empty():
		return Dictionary(_failure_state).duplicate(true)
	return Dictionary(_failure_fallback_state).duplicate(true)


func refresh_failure_fallback_state(level_definition: Dictionary) -> void:
	_failure_fallback_state = {
		"time_limit": {},
		"death_limit": {},
	}
	_time_limit_expired_notified = false

	if level_definition.is_empty():
		return

	var raw_rules: Variant = level_definition.get("failure_rules", [])
	if typeof(raw_rules) != TYPE_ARRAY:
		return

	for raw_rule in raw_rules:
		if typeof(raw_rule) != TYPE_DICTIONARY:
			continue

		var rule: Dictionary = raw_rule
		match String(rule.get("type", "")):
			"time_limit":
				var seconds := maxf(float(rule.get("seconds", 0.0)), 0.0)
				if seconds <= 0.0:
					continue
				var duration_ms := int(round(seconds * 1000.0))
				_failure_fallback_state["time_limit"] = {
					"enabled": true,
					"duration_ms": duration_ms,
					"started_at_ms": Time.get_ticks_msec(),
					"remaining_ms": duration_ms,
				}
			"death_limit":
				var hearts := maxi(int(rule.get("hearts", rule.get("max_deaths", 0))), 0)
				if hearts <= 0:
					continue
				_failure_fallback_state["death_limit"] = {
					"enabled": true,
					"hearts_max": hearts,
					"hearts_remaining": hearts,
					"shared": bool(rule.get("shared", true)),
				}


func _failure_hearts_text() -> String:
	var death_limit: Dictionary = display_failure_state().get("death_limit", {})
	if not bool(death_limit.get("enabled", false)):
		return ""

	var hearts_max := maxi(int(death_limit.get("hearts_max", 0)), 0)
	var hearts_remaining := maxi(int(death_limit.get("hearts_remaining", 0)), 0)
	if hearts_max <= 0:
		return ""

	# 1. Define the paths to your PNGs inside the BBCode tags
	# We use vertical_alignment=center to stop the PNG from looking too big/misaligned
	var full_heart_tag := "[img=16x16 vertical_alignment=center]res://assets/sprites/heart_full.png[/img]"
	var empty_heart_tag := "[img=16x16 vertical_alignment=center]res://assets/sprites/heart_empty.png[/img]"

	var hearts := ""
	for index in range(hearts_max):
		# 2. Append the PNG tags instead of the text unicode symbols
		hearts += full_heart_tag if index < hearts_remaining else empty_heart_tag
	return hearts


func _failure_time_remaining_ms(state: Dictionary) -> int:
	var time_limit: Dictionary = state.get("time_limit", {})
	if time_limit.is_empty():
		return 0

	var duration_ms := int(time_limit.get("duration_ms", 0))
	var started_at_ms := int(time_limit.get("started_at_ms", 0))
	
	# Scenario 1: A network state packet from a server room match
	if _failure_snapshot_ms > 0:
		# Use the remaining time sent by the server, minus how much local 
		# engine time has ticked by since we received that specific snapshot.
		var remaining_at_snapshot := int(time_limit.get("remaining_ms", duration_ms))
		var ms_since_snapshot := Time.get_ticks_msec() - _failure_snapshot_ms
		return maxi(remaining_at_snapshot - ms_since_snapshot, 0)

	# Scenario 2: Local fallback rule tracking (Offline play/Testing)
	if started_at_ms <= 0:
		return maxi(int(time_limit.get("remaining_ms", 0)), 0)

	return maxi(duration_ms - (Time.get_ticks_msec() - started_at_ms), 0)


func _format_time_ms(remaining_ms: int) -> String:
	var total_seconds := maxi(int(remaining_ms / 1000), 0)
	var minutes := int(total_seconds / 60)
	var seconds := int(total_seconds % 60)
	return "%02d:%02d" % [minutes, seconds]


func _emit_time_limit_expired() -> void:
	if _time_limit_expired_notified:
		return

	_time_limit_expired_notified = true
	if _time_limit_expired.is_valid():
		_time_limit_expired.call()
