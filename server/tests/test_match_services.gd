extends SceneTree

const GameIds = preload("res://scripts/catalog/game_ids.gd")
const FailureRuleService = preload("res://scripts/match/failure_rule_service.gd")
const GeometryService = preload("res://scripts/match/geometry_service.gd")
const KeyDoorMechanic = preload("res://scripts/match/mechanics/key_door_mechanic.gd")
const LinkApplier = preload("res://scripts/match/link_applier.gd")
const MechanicRegistry = preload("res://scripts/match/mechanic_registry.gd")
const MatchState = preload("res://scripts/match/match_state.gd")
const MatchStateContext = preload("res://scripts/match/match_state_context.gd")
const TimedObjectService = preload("res://scripts/match/timed_object_service.gd")


class DummyMatchState:
	extends RefCounted

	var level_definition: Dictionary = {}
	var _objects: Dictionary = {}
	var _players: Dictionary = {}

	func _init(level_definition_in: Dictionary = {}, objects_in: Dictionary = {}, players_in: Dictionary = {}) -> void:
		level_definition = level_definition_in.duplicate(true)
		_objects = objects_in.duplicate(true)
		_players = players_in.duplicate(true)

	func has_player(peer_id: int) -> bool:
		return _players.has(peer_id) or _players.has(str(peer_id))

	func get_player_state(peer_id: int) -> Dictionary:
		if _players.has(peer_id):
			return Dictionary(_players[peer_id]).duplicate(true)
		if _players.has(str(peer_id)):
			return Dictionary(_players[str(peer_id)]).duplicate(true)
		return {}

	func get_object_data(target_id: String) -> Dictionary:
		if not _objects.has(target_id):
			return {}
		return Dictionary(_objects[target_id]).duplicate(true)

	func set_object_data(target_id: String, object_data: Dictionary) -> void:
		_objects[target_id] = object_data.duplicate(true)

	func object_ids() -> Array[String]:
		var ids: Array[String] = []
		for raw_id in _objects.keys():
			ids.append(String(raw_id))
		ids.sort()
		return ids

	func event(kind: String, request_action: String, peer_id: int, target_id: String = "", extra: Dictionary = {}) -> Dictionary:
		var result := {
			"kind": kind,
			"request_action": request_action,
			"peer_id": peer_id,
		}
		if not target_id.is_empty():
			result["target_id"] = target_id
		for raw_key in extra.keys():
			result[String(raw_key)] = extra[raw_key]
		return result


func _init() -> void:
	var failures: Array[String] = []
	_test_link_applier(failures)
	_test_key_door_mechanic(failures)
	_test_mechanic_registry_hooks(failures)
	_test_match_state_contract(failures)
	_test_geometry_service(failures)
	_test_failure_rule_service(failures)
	_test_timed_object_service(failures)

	if failures.is_empty():
		print("Match service tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_link_applier(failures: Array[String]) -> void:
	var match_state: DummyMatchState = DummyMatchState.new(
		{
			"links": [
				{
					"source_target_id": "button_a",
					"source_field": "pressed",
					"source_value": true,
					"target_id": "barrier_a",
					"target_field": "open",
					"target_operation": "set",
					"target_value": true,
				},
				{
					"source_target_id": "button_a",
					"source_field": "pressed",
					"source_value": true,
					"target_id": "lamp_a",
					"target_field": "active",
					"target_operation": "toggle",
				},
				{
					"source_target_id": "button_a",
					"source_field": "pressed",
					"source_value": true,
					"target_id": "counter_up",
					"target_field": "value",
					"target_operation": "increment",
					"target_value": 2,
				},
				{
					"source_target_id": "button_a",
					"source_field": "pressed",
					"source_value": true,
					"target_id": "counter_down",
					"target_field": "value",
					"target_operation": "decrement",
					"target_value": 3,
				},
			],
		},
		{
			"barrier_a": {"state": {"open": false}},
			"lamp_a": {"state": {"active": false}},
			"counter_up": {"state": {"value": 5}},
			"counter_down": {"state": {"value": 8}},
		}
	)

	var events: Array = LinkApplier.apply_links_for_source(match_state, 7, "button_a", "pressed", true)
	if events.size() != 4:
		failures.append("LinkApplier.apply_links_for_source() did not emit one event per matching link.")

	if not bool(match_state.get_object_data("barrier_a").get("state", {}).get("open", false)):
		failures.append("LinkApplier.apply_links_for_source() did not apply the set operation.")
	if not bool(match_state.get_object_data("lamp_a").get("state", {}).get("active", false)):
		failures.append("LinkApplier.apply_links_for_source() did not apply the toggle operation.")
	if int(match_state.get_object_data("counter_up").get("state", {}).get("value", -1)) != 7:
		failures.append("LinkApplier.apply_links_for_source() did not apply the increment operation.")
	if int(match_state.get_object_data("counter_down").get("state", {}).get("value", -1)) != 5:
		failures.append("LinkApplier.apply_links_for_source() did not apply the decrement operation.")

	for event in events:
		if String(event.get("kind", "")) != GameIds.EVENT_OBJECT_STATE_CHANGED:
			failures.append("LinkApplier.apply_links_for_source() emitted an unexpected event kind.")
			break

	var ignored_events: Array = LinkApplier.apply_links_for_source(match_state, 7, "button_a", "pressed", false)
	if not ignored_events.is_empty():
		failures.append("LinkApplier.apply_links_for_source() should ignore links when source_value does not match.")


func _test_key_door_mechanic(failures: Array[String]) -> void:
	var match_state: DummyMatchState = DummyMatchState.new(
		{},
		{
			"key_a": {
				"kind": GameIds.OBJECT_KIND_KEY,
				"state": {
					"collected": true,
					"spent": true,
				},
			},
			"key_b": {
				"kind": GameIds.OBJECT_KIND_KEY,
				"state": {
					"collected": true,
					"spent": false,
				},
			},
			"door_a": {
				"kind": GameIds.OBJECT_KIND_DOOR,
				"state": {
					"opened": false,
				},
			},
		}
	)
	var mechanic: Variant = KeyDoorMechanic.new()

	var deposited_count: int = mechanic._deposited_team_key_count(match_state, {"count": 2})
	if deposited_count != 1:
		failures.append("KeyDoorMechanic._deposited_team_key_count() did not count spent team keys for count-based requirements.")

	var water_match_state: Variant = MatchState.new([3], 0, "water_01", "water")
	var water_context: Variant = MatchStateContext.new(water_match_state)
	water_match_state.update_player_runtime(3, {
		"position": {"x": -128.0, "y": -30.0},
		"velocity": {"x": 0.0, "y": 0.0},
	})

	var first_collect: Dictionary = mechanic.apply_collect(water_context, 3, "water01_key_land")
	if not bool(first_collect.get("ok", false)):
		failures.append("KeyDoorMechanic.apply_collect() should allow the first key pickup in water_01.")

	water_match_state.update_player_runtime(3, {
		"position": {"x": -175.0, "y": 140.0},
		"velocity": {"x": 0.0, "y": 0.0},
	})
	water_context = MatchStateContext.new(water_match_state)

	var second_collect: Dictionary = mechanic.apply_collect(water_context, 3, "water01_key_underwater")
	if bool(second_collect.get("ok", false)):
		failures.append("KeyDoorMechanic.apply_collect() allowed a second carried key in water_01.")
	elif String(second_collect.get("code", "")) != "key_capacity_reached":
		failures.append("KeyDoorMechanic.apply_collect() returned an unexpected error code for the water_01 key limit.")

	if water_match_state.player_key_count(3) != 1:
		failures.append("KeyDoorMechanic.apply_collect() changed the player's key count after rejecting the second water_01 key.")
	var underwater_key_state: Dictionary = water_match_state.get_object_data("water01_key_underwater").get("state", {})
	if bool(underwater_key_state.get("collected", false)):
		failures.append("KeyDoorMechanic.apply_collect() still marked the second water_01 key as collected after rejecting it.")


func _test_geometry_service(failures: Array[String]) -> void:
	if not GeometryService.positions_match({"x": 1.0, "y": 1.0}, {"x": 1.2, "y": 1.2}, 0.3):
		failures.append("GeometryService.positions_match() failed for coordinates inside epsilon.")
	if GeometryService.positions_match({"x": 1.0, "y": 1.0}, {"x": 2.0, "y": 2.0}, 0.3):
		failures.append("GeometryService.positions_match() accepted coordinates outside epsilon.")

	var circle := {
		"type": "circle",
		"center": {"x": 0.0, "y": 0.0},
		"radius": 10.0,
	}
	var overlapping_rect := {
		"type": "rectangle",
		"center": {"x": 8.0, "y": 0.0},
		"size": {"x": 10.0, "y": 10.0},
		"margin": 0.0,
	}
	var distant_rect := {
		"type": "rectangle",
		"center": {"x": 40.0, "y": 0.0},
		"size": {"x": 10.0, "y": 10.0},
		"margin": 0.0,
	}
	if not GeometryService.shape_overlap(circle, overlapping_rect):
		failures.append("GeometryService.shape_overlap() missed a circle/rectangle overlap.")
	if GeometryService.shape_overlap(circle, distant_rect):
		failures.append("GeometryService.shape_overlap() reported a false positive overlap.")

	var match_state: DummyMatchState = DummyMatchState.new(
		{},
		{
			"trigger_a": {
				"trigger": {
					"shape": "rectangle",
					"size": {"x": 20.0, "y": 20.0},
					"offset": {"x": 0.0, "y": 0.0},
					"margin": 0.0,
				},
				"transform": {
					"position": {"x": 0.0, "y": 0.0},
				},
			},
			"push_box_a": {
				"body": {
					"shape": "rectangle",
					"size": {"x": 24.0, "y": 24.0},
					"offset": {"x": 0.0, "y": 0.0},
				},
				"state": {
					"position": {"x": 5.0, "y": 0.0},
				},
				"transform": {
					"position": {"x": 5.0, "y": 0.0},
				},
			},
		},
		{
			1: {
				"position": {"x": 0.0, "y": 19.0},
				"previous_position": {"x": -40.0, "y": 19.0},
			},
		}
	)

	if not GeometryService.player_shape_overlaps_target_shape(match_state, 1, "trigger_a", "trigger"):
		failures.append("GeometryService.player_shape_overlaps_target_shape() did not detect a player overlap.")
	if not GeometryService.object_shape_overlaps_target_shape(match_state, "push_box_a", "body", "trigger_a", "trigger"):
		failures.append("GeometryService.object_shape_overlaps_target_shape() did not detect an object overlap.")
	if not GeometryService.did_player_cross_trigger_since_last_update(match_state, 1, "trigger_a"):
		failures.append("GeometryService.did_player_cross_trigger_since_last_update() did not detect a trigger crossing.")


func _test_match_state_contract(failures: Array[String]) -> void:
	var match_state: Variant = MatchState.new([7], 0, "beginner_01", "beginner")
	var event: Dictionary = match_state.event(GameIds.EVENT_DOOR_OPENED, GameIds.ACTION_OPEN, 7, "level01_door_01", {
		"opened": true,
	})

	if String(event.get("kind", "")) != GameIds.EVENT_DOOR_OPENED:
		failures.append("MatchState.event() did not preserve the event kind.")
	if String(event.get("request_action", "")) != GameIds.ACTION_OPEN:
		failures.append("MatchState.event() did not preserve the originating action.")
	if int(event.get("peer_id", -1)) != 7:
		failures.append("MatchState.event() did not preserve the peer id.")
	if int(event.get("level_index", -1)) != 0:
		failures.append("MatchState.event() did not include the current level index.")
	if String(event.get("level_id", "")) != "beginner_01":
		failures.append("MatchState.event() did not include the current level id.")
	if String(event.get("target_id", "")) != "level01_door_01":
		failures.append("MatchState.event() did not preserve the target id.")
	if String(event.get("sync_id", "")) != "level01_door_01":
		failures.append("MatchState.event() did not mirror target_id into sync_id for compatibility.")
	if not bool(event.get("opened", false)):
		failures.append("MatchState.event() did not preserve extra payload fields.")

	match_state.patch_object_state("level01_key_01", {
		"collected": true,
		"collector_peer_id": 7,
	})
	match_state.patch_object_state("level01_door_01", {
		"opened": true,
	})
	match_state.patch_player_state(7, {
		"position": {"x": 24.0, "y": -8.0},
		"velocity": {"x": 0.0, "y": 0.0},
	})

	var snapshot: Dictionary = match_state.snapshot()
	if String(snapshot.get("current_level_id", "")) != "beginner_01":
		failures.append("MatchState.snapshot() did not preserve the current level id.")
	if not bool(snapshot.get("key_collected", false)):
		failures.append("MatchState.snapshot() did not preserve collected-key summary state.")
	if not bool(snapshot.get("door_opened", false)):
		failures.append("MatchState.snapshot() did not preserve opened-door summary state.")

	var snapshot_objects: Dictionary = snapshot.get("objects", {})
	var door_state: Dictionary = snapshot_objects.get("level01_door_01", {}).get("state", {})
	if not bool(door_state.get("opened", false)):
		failures.append("MatchState.snapshot() did not preserve object runtime state.")

	var snapshot_players: Dictionary = snapshot.get("players", {})
	if not snapshot_players.has(7):
		failures.append("MatchState.snapshot() did not preserve player runtime state entries.")
	else:
		var player_state: Dictionary = snapshot_players.get(7, {})
		var player_position: Dictionary = player_state.get("position", {})
		if float(player_position.get("x", 0.0)) != 24.0 or float(player_position.get("y", 0.0)) != -8.0:
			failures.append("MatchState.snapshot() did not preserve patched player runtime state.")


func _test_mechanic_registry_hooks(failures: Array[String]) -> void:
	var registry: Dictionary = MechanicRegistry.build()
	var hooks: Dictionary = registry.get("hooks", {})
	var automatic_runtime_raw: Variant = hooks.get("automatic_player_runtime", [])
	var push_box_hooks_raw: Variant = hooks.get("post_push_box_observation", [])
	if typeof(automatic_runtime_raw) != TYPE_ARRAY or Array(automatic_runtime_raw).is_empty():
		failures.append("MechanicRegistry.build() did not register automatic player-runtime hooks.")
	else:
		var automatic_hook = Array(automatic_runtime_raw)[0]
		if typeof(automatic_hook) != TYPE_CALLABLE or not automatic_hook.is_valid():
			failures.append("MechanicRegistry.build() registered an invalid automatic player-runtime hook.")
	if typeof(push_box_hooks_raw) != TYPE_ARRAY or Array(push_box_hooks_raw).is_empty():
		failures.append("MechanicRegistry.build() did not register post-push-box observation hooks.")
	else:
		var push_box_hook = Array(push_box_hooks_raw)[0]
		if typeof(push_box_hook) != TYPE_CALLABLE or not push_box_hook.is_valid():
			failures.append("MechanicRegistry.build() registered an invalid post-push-box observation hook.")


func _test_failure_rule_service(failures: Array[String]) -> void:
	var configured: Dictionary = FailureRuleService.configure(
		{
			"failure_rules": [
				{"type": "time_limit", "seconds": 3.0},
				{"type": "death_limit", "hearts": 2, "shared": true},
			],
		},
		1000
	)
	var failure_state: Dictionary = configured.get("failure_state", {})
	var time_limit: Dictionary = failure_state.get("time_limit", {})
	var death_limit: Dictionary = failure_state.get("death_limit", {})
	if int(time_limit.get("duration_ms", 0)) != 3000:
		failures.append("FailureRuleService.configure() did not convert the time limit to milliseconds.")
	if int(death_limit.get("hearts_remaining", -1)) != 2:
		failures.append("FailureRuleService.configure() did not seed the death-limit hearts.")

	var snapshot: Dictionary = FailureRuleService.snapshot(failure_state, 1000, 2000)
	if int(snapshot.get("time_limit", {}).get("remaining_ms", -1)) != 2000:
		failures.append("FailureRuleService.snapshot() reported an unexpected remaining time.")
	if int(snapshot.get("death_limit", {}).get("hearts_remaining", -1)) != 2:
		failures.append("FailureRuleService.snapshot() reported an unexpected remaining heart count.")

	var first_death: Dictionary = FailureRuleService.register_hazard_death(failure_state)
	if int(first_death.get("hearts_remaining", -1)) != 1:
		failures.append("FailureRuleService.register_hazard_death() did not decrement the death limit.")
	var second_death: Dictionary = FailureRuleService.register_hazard_death(first_death.get("failure_state", {}))
	if int(second_death.get("hearts_remaining", -1)) != 0:
		failures.append("FailureRuleService.register_hazard_death() did not reach zero hearts at the expected time.")

	var death_failure: Dictionary = FailureRuleService.consume_level_failure(second_death.get("failure_state", {}), 1000, false, 2000)
	if String(death_failure.get("failure", {}).get("reason", "")) != "death_limit":
		failures.append("FailureRuleService.consume_level_failure() did not trigger the death-limit failure.")
	if not bool(death_failure.get("level_reset_pending", false)):
		failures.append("FailureRuleService.consume_level_failure() did not mark the level reset pending after a death-limit failure.")

	var time_only: Dictionary = FailureRuleService.configure(
		{
			"failure_rules": [
				{"type": "time_limit", "seconds": 1.0},
			],
		},
		5000
	)
	var time_failure: Dictionary = FailureRuleService.consume_level_failure(time_only.get("failure_state", {}), 5000, false, 6500)
	if String(time_failure.get("failure", {}).get("reason", "")) != "time_limit":
		failures.append("FailureRuleService.consume_level_failure() did not trigger the time-limit failure.")

	var already_pending: Dictionary = FailureRuleService.consume_level_failure(time_only.get("failure_state", {}), 5000, true, 6500)
	if not Dictionary(already_pending.get("failure", {})).is_empty():
		failures.append("FailureRuleService.consume_level_failure() should not emit a duplicate failure while reset is already pending.")
	if not bool(already_pending.get("level_reset_pending", false)):
		failures.append("FailureRuleService.consume_level_failure() lost the pending reset flag.")


func _test_timed_object_service(failures: Array[String]) -> void:
	var match_state: DummyMatchState = DummyMatchState.new(
		{},
		{
			"water_jet_a": {
				"kind": GameIds.OBJECT_KIND_WATER_JET,
				"timer": {
					"mode": "toggle",
					"min_interval_ms": 100,
					"max_interval_ms": 100,
				},
				"state": {
					"active": true,
				},
			},
			"static_object": {
				"kind": GameIds.OBJECT_KIND_BARRIER,
				"state": {
					"open": false,
				},
			},
		}
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var initial_events: Array = TimedObjectService.advance(match_state, rng, 1000)
	if not initial_events.is_empty():
		failures.append("TimedObjectService.advance() should schedule the first toggle without emitting an event.")

	var scheduled_state: Dictionary = match_state.get_object_data("water_jet_a").get("state", {})
	if int(scheduled_state.get("next_toggle_at_ms", -1)) != 1100:
		failures.append("TimedObjectService.advance() did not schedule the next toggle at the expected timestamp.")
	if not bool(scheduled_state.get("active", false)):
		failures.append("TimedObjectService.advance() changed the active flag while only scheduling the first toggle.")

	var early_events: Array = TimedObjectService.advance(match_state, rng, 1099)
	if not early_events.is_empty():
		failures.append("TimedObjectService.advance() emitted an event before the scheduled toggle timestamp.")

	var toggle_events: Array = TimedObjectService.advance(match_state, rng, 1100)
	if toggle_events.size() != 1:
		failures.append("TimedObjectService.advance() did not emit exactly one event when toggling a timed object.")

	var toggled_state: Dictionary = match_state.get_object_data("water_jet_a").get("state", {})
	if bool(toggled_state.get("active", true)):
		failures.append("TimedObjectService.advance() did not toggle the active flag off at the scheduled timestamp.")
	if int(toggled_state.get("updated_at_ms", -1)) != 1100:
		failures.append("TimedObjectService.advance() did not record the toggle timestamp in object state.")
	if int(toggled_state.get("next_toggle_at_ms", -1)) != 1200:
		failures.append("TimedObjectService.advance() did not reschedule the next toggle after toggling.")

	if toggle_events.is_empty() or String(toggle_events[0].get("kind", "")) != GameIds.EVENT_OBJECT_STATE_CHANGED:
		failures.append("TimedObjectService.advance() emitted an unexpected event kind for timed state changes.")
