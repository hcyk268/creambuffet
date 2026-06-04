extends RefCounted
class_name MatchState

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const GameIds = preload("res://scripts/catalog/game_ids.gd")
const MechanicRegistry = preload("res://scripts/match/mechanic_registry.gd")
const LevelStateFactory = preload("res://scripts/match/level_state_factory.gd")
const CompletionRuleEvaluator = preload("res://scripts/match/completion_rule_evaluator.gd")
const GeometryService = preload("res://scripts/match/geometry_service.gd")
const FailureRuleService = preload("res://scripts/match/failure_rule_service.gd")
const TimedObjectService = preload("res://scripts/match/timed_object_service.gd")
const SnapshotBuilder = preload("res://scripts/match/snapshot_builder.gd")
const PushIntentService = preload("res://scripts/match/push_intent_service.gd")
const WorldActionDispatcher = preload("res://scripts/match/world_action_dispatcher.gd")
const MatchStateContext = preload("res://scripts/match/match_state_context.gd")
const ObjectStateStore = preload("res://scripts/match/object_state_store.gd")
const PlayerStateStore = preload("res://scripts/match/player_state_store.gd")

const PUSH_BOX_OBSERVE_PADDING := 24.0
const PUSH_BOX_SYNC_EPSILON := 0.5
const HAZARD_RESPAWN_REARM_MS := 250
const OXYGEN_RESPAWN_REARM_MS := 1000

var map_id := GameCatalog.DEFAULT_MAP_ID
var current_level := 0
var current_level_id := ""
var level_definition: Dictionary = {}
var objects: Dictionary = {}
var players: Dictionary = {}
var players_at_goal: Dictionary = {}
var push_intents: Dictionary = {}
var _mechanics: Dictionary = {}
var _mechanic_handlers: Dictionary = {}
var _mechanic_hooks: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var level_started_at_ms := 0
var failure_state: Dictionary = {}
var _level_reset_pending := false
var _object_store: ObjectStateStore
var _player_store: PlayerStateStore


func _init(peer_ids: Array[int] = [], start_level: int = 0, start_level_id: String = "", initial_map_id: String = GameCatalog.DEFAULT_MAP_ID) -> void:
	map_id = GameCatalog.normalize_map_id(initial_map_id)
	current_level = maxi(start_level, 0)
	current_level_id = start_level_id if not start_level_id.is_empty() else GameCatalog.get_level_id_by_index(map_id, current_level)
	_rng.randomize()
	_object_store = ObjectStateStore.new(objects)
	_player_store = PlayerStateStore.new(players)
	_register_mechanic_handlers()
	_register_players(peer_ids)
	_reset_level_state()


func has_player(peer_id: int) -> bool:
	return _player_store.has(peer_id)


func is_player_alive(peer_id: int) -> bool:
	if not has_player(peer_id):
		return false

	var player_state: Dictionary = _player_store.get_state(peer_id)
	return bool(player_state.get("alive", true))


func add_player(peer_id: int) -> void:
	if has_player(peer_id):
		return

	_player_store.set_state(peer_id, _new_player_state())


func remove_player(peer_id: int) -> void:
	if not has_player(peer_id):
		return

	players.erase(peer_id)
	players_at_goal.erase(peer_id)
	push_intents.erase(peer_id)
	_sync_goal_object_states()


func get_player_state(peer_id: int) -> Dictionary:
	if not has_player(peer_id):
		return {}

	return _player_store.get_state(peer_id)


func get_player_runtime(peer_id: int) -> Dictionary:
	return get_player_state(peer_id)


func set_player_state(peer_id: int, player_state: Dictionary) -> void:
	_player_store.set_state(peer_id, player_state)


func patch_player_state(peer_id: int, updates: Dictionary) -> Dictionary:
	return _player_store.patch_state(peer_id, updates)


func player_ids() -> Array[int]:
	return _player_store.ids()


func set_player_alive(peer_id: int, alive: bool) -> Dictionary:
	return _player_store.set_alive(peer_id, alive)


func set_player_goal(peer_id: int, target_id: String) -> Dictionary:
	players_at_goal[peer_id] = true
	return _player_store.set_goal(peer_id, target_id)


func clear_player_goal(peer_id: int) -> Dictionary:
	players_at_goal.erase(peer_id)
	return _player_store.clear_goal(peer_id)


func player_key_count(peer_id: int) -> int:
	return _player_store.key_count(peer_id)


func add_player_keys(peer_id: int, amount: int) -> Dictionary:
	return _player_store.add_key_count(peer_id, amount)


func consume_player_keys(peer_id: int, amount: int) -> Dictionary:
	return _player_store.consume_key_count(peer_id, amount)


func set_player_oxygen(peer_id: int, oxygen: float) -> Dictionary:
	return _player_store.set_oxygen(peer_id, oxygen)


func set_player_max_oxygen(peer_id: int, max_oxygen: float) -> Dictionary:
	return _player_store.set_max_oxygen(peer_id, max_oxygen)


func set_level(level_index: int, level_id: String = "") -> void:
	current_level = maxi(level_index, 0)
	current_level_id = level_id if not level_id.is_empty() else GameCatalog.get_level_id_by_index(map_id, current_level)
	_reset_level_state()
	for peer_id in player_ids():
		_player_store.set_state(peer_id, _new_player_state())


func update_player_runtime(peer_id: int, payload: Dictionary) -> void:
	if not has_player(peer_id):
		return

	var player_state: Dictionary = _player_store.get_state(peer_id)
	var previous_position: Dictionary = {}
	var previous_position_raw = player_state.get("position", {})
	if typeof(previous_position_raw) == TYPE_DICTIONARY:
		previous_position = Dictionary(previous_position_raw).duplicate(true)
	player_state["previous_position"] = previous_position
	player_state["position"] = GeometryService.packet_vector(payload.get("position", player_state.get("position", {})))
	player_state["velocity"] = GeometryService.packet_vector(payload.get("velocity", player_state.get("velocity", {})))
	player_state["updated_at_ms"] = Time.get_ticks_msec()
	_player_store.set_state(peer_id, player_state)


func apply_automatic_fall_reset(peer_id: int) -> Array[Dictionary]:
	return _run_mechanic_event_hooks("automatic_player_runtime", [MatchStateContext.new(self), peer_id])


func advance_timed_mechanics() -> Array[Dictionary]:
	return TimedObjectService.advance(self, _rng)


func apply_push_box_observations(peer_id: int, raw_states) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not has_player(peer_id) or typeof(raw_states) != TYPE_ARRAY:
		return events
	var context := MatchStateContext.new(self)

	for raw_state in raw_states:
		if typeof(raw_state) != TYPE_DICTIONARY:
			continue

		var state: Dictionary = Dictionary(raw_state).duplicate(true)
		var target_id := String(state.get("target_id", state.get("node_name", ""))).strip_edges()
		if target_id.is_empty():
			continue

		var object_state := get_object_data(target_id)
		if object_state.is_empty() or String(object_state.get("kind", "")) != GameIds.OBJECT_KIND_PUSH_BOX:
			continue

		var raw_position = state.get("position", {})
		if typeof(raw_position) != TYPE_DICTIONARY:
			continue

		var observed_position := GeometryService.packet_vector(raw_position)
		var object_data: Dictionary = object_state
		var object_runtime_state: Dictionary = object_data.get("state", {})
		var previous_position: Dictionary = {}
		var raw_previous_position: Variant = object_runtime_state.get("position", {})
		if typeof(raw_previous_position) == TYPE_DICTIONARY:
			previous_position = Dictionary(raw_previous_position).duplicate(true)
		if not GeometryService.positions_match(previous_position, observed_position, PUSH_BOX_SYNC_EPSILON):
			object_runtime_state["position"] = observed_position
			object_runtime_state["updated_by_peer_id"] = peer_id
			object_data["state"] = object_runtime_state
			set_object_data(target_id, object_data)

			events.append(_event(GameIds.EVENT_PUSH_BOX_STATE, GameIds.ACTION_PUSH_BOX_STATE, peer_id, target_id, {
				"position": observed_position.duplicate(true),
			}))
		events.append_array(_run_mechanic_event_hooks("post_push_box_observation", [context, peer_id]))

	return events


func apply_world_action(peer_id: int, action: String, target_id: String, payload: Dictionary) -> Dictionary:
	return WorldActionDispatcher.dispatch(self, peer_id, action, target_id, payload)


func get_mechanic_handler(handler_id: String) -> Callable:
	return _mechanic_handlers.get(handler_id, Callable())


func can_complete_level() -> bool:
	return CompletionRuleEvaluator.can_complete_level(self)


func snapshot() -> Dictionary:
	return SnapshotBuilder.build(self)


func apply_push_intents(peer_id: int, raw_intents) -> Array[Dictionary]:
	return PushIntentService.apply(self, peer_id, raw_intents)


func pushable_control_snapshot() -> Array[Dictionary]:
	return PushIntentService.snapshot(self)


func can_player_interact_with_trigger(peer_id: int, target_id: String) -> bool:
	return GeometryService.player_shape_overlaps_target_shape(self, peer_id, target_id, "trigger")


func can_player_exit_trigger(peer_id: int, target_id: String) -> bool:
	return not can_player_interact_with_trigger(peer_id, target_id)


func can_player_observe_push_box(peer_id: int, target_id: String, observed_position: Dictionary = {}) -> bool:
	if not has_player(peer_id):
		return false
	if not is_player_alive(peer_id):
		return false

	var object_data := get_object_data(target_id)
	if object_data.is_empty() or String(object_data.get("kind", "")) != GameIds.OBJECT_KIND_PUSH_BOX:
		return false

	var body_rect := _shape_rect_for_object(target_id, "body", observed_position)
	if body_rect.size == Vector2.ZERO:
		return false

	var player_rect := GeometryService.player_bounding_rect(self, peer_id)
	if player_rect.size == Vector2.ZERO:
		return false

	return player_rect.grow(PUSH_BOX_OBSERVE_PADDING).intersects(body_rect)


func compute_button_pressed(target_id: String) -> bool:
	var object_data := _get_object(target_id)
	if object_data.is_empty():
		return false

	for peer_id in player_ids():
		if not is_player_alive(peer_id):
			continue
		if can_player_interact_with_trigger(peer_id, target_id):
			return true

	for candidate_id in object_ids():
		var candidate := get_object_data(candidate_id)
		if candidate.is_empty() or String(candidate.get("kind", "")) != GameIds.OBJECT_KIND_PUSH_BOX:
			continue
		if GeometryService.object_shape_overlaps_target_shape(self, candidate_id, "body", target_id, "trigger"):
			return true

	return false


func _players_inside_goal(target_id: String) -> Array:
	var result := []
	for peer_id in player_ids():
		var player_state: Dictionary = _player_store.get_state(peer_id)
		if bool(player_state.get("at_goal", false)) and String(player_state.get("goal_target_id", "")) == target_id:
			result.append(peer_id)
	return result


func players_inside_goal(target_id: String) -> Array:
	return _players_inside_goal(target_id)


func _register_mechanic_handlers() -> void:
	var registry := MechanicRegistry.build()
	_mechanics = registry.get("mechanics", {})
	_mechanic_handlers = registry.get("handlers", {})
	_mechanic_hooks = registry.get("hooks", {})


func _run_mechanic_event_hooks(hook_id: String, args: Array = []) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var raw_hooks: Variant = _mechanic_hooks.get(hook_id, [])
	if typeof(raw_hooks) != TYPE_ARRAY:
		return events

	for raw_hook in raw_hooks:
		if typeof(raw_hook) != TYPE_CALLABLE:
			continue
		var hook: Callable = raw_hook
		if not hook.is_valid():
			continue

		var result = hook.callv(args)
		if typeof(result) != TYPE_ARRAY:
			continue
		events.append_array(Array(result))
	return events


func _sync_goal_object_states() -> void:
	for target_id in object_ids():
		var object_data: Dictionary = get_object_data(target_id)
		if String(object_data.get("kind", "")) != GameIds.OBJECT_KIND_GOAL:
			continue

		var state: Dictionary = object_data.get("state", {})
		state["players_inside"] = _players_inside_goal(target_id)
		object_data["state"] = state
		set_object_data(target_id, object_data)


func sync_goal_object_states() -> void:
	_sync_goal_object_states()


func _register_players(peer_ids: Array[int]) -> void:
	players.clear()
	players_at_goal.clear()
	for peer_id in peer_ids:
		_player_store.set_state(int(peer_id), _new_player_state())


func _reset_level_state() -> void:
	level_definition = GameCatalog.get_level(current_level_id)
	_object_store.clear()
	players_at_goal.clear()
	push_intents.clear()
	_configure_failure_state()
	var built_objects := LevelStateFactory.build_objects(level_definition)
	for raw_target_id in built_objects.keys():
		var target_id := String(raw_target_id)
		_object_store.set_object(target_id, Dictionary(built_objects[raw_target_id]))


func _new_player_state() -> Dictionary:
	return LevelStateFactory.new_player_state(level_definition)


func require_object(target_id: String, allowed_kinds: Array, action: String) -> Dictionary:
	if target_id.strip_edges().is_empty():
		return _error("missing_target_id", "%s requires a target_id." % action)

	var object_data := get_object_data(target_id)
	if object_data.is_empty():
		return _error("unknown_target", "Target does not exist in the current level: %s" % target_id)

	var kind := String(object_data.get("kind", ""))
	if not allowed_kinds.has(kind):
		return _error("wrong_target_kind", "Action %s cannot target object kind %s." % [action, kind])

	return {
		"ok": true,
		"object": object_data,
	}


func register_hazard_death() -> int:
	var result := FailureRuleService.register_hazard_death(failure_state)
	var next_failure_state: Variant = result.get("failure_state", failure_state)
	if typeof(next_failure_state) == TYPE_DICTIONARY:
		failure_state = next_failure_state
	return int(result.get("hearts_remaining", -1))


func consume_level_failure(now_ms: int = Time.get_ticks_msec()) -> Dictionary:
	var result := FailureRuleService.consume_level_failure(
		failure_state,
		level_started_at_ms,
		_level_reset_pending,
		now_ms
	)
	_level_reset_pending = bool(result.get("level_reset_pending", _level_reset_pending))
	var failure: Variant = result.get("failure", {})
	if typeof(failure) != TYPE_DICTIONARY:
		return {}
	return failure


func failure_state_snapshot(now_ms: int = Time.get_ticks_msec()) -> Dictionary:
	return FailureRuleService.snapshot(failure_state, level_started_at_ms, now_ms)


func _get_required_object(target_id: String, allowed_kinds: Array, action: String) -> Dictionary:
	return require_object(target_id, allowed_kinds, action)


func has_object(target_id: String) -> bool:
	return _object_store.has(target_id)


func object_ids() -> Array[String]:
	return _object_store.ids()


func get_object_data(target_id: String) -> Dictionary:
	return _object_store.get_object(target_id)


func set_object_data(target_id: String, object_data: Dictionary) -> void:
	_object_store.set_object(target_id, object_data)


func get_object_state(target_id: String) -> Dictionary:
	return _object_store.get_state(target_id)


func set_object_state(target_id: String, state: Dictionary) -> Dictionary:
	return _object_store.set_state(target_id, state)


func patch_object_state(target_id: String, updates: Dictionary) -> Dictionary:
	return _object_store.patch_state(target_id, updates)


func _get_object(target_id: String) -> Dictionary:
	return get_object_data(target_id)


func _configure_failure_state() -> void:
	var config := FailureRuleService.configure(level_definition)
	level_started_at_ms = int(config.get("level_started_at_ms", 0))
	_level_reset_pending = bool(config.get("level_reset_pending", false))
	var next_failure_state: Variant = config.get("failure_state", {})
	if typeof(next_failure_state) == TYPE_DICTIONARY:
		failure_state = next_failure_state
	else:
		failure_state = {}


func _all_players_dead() -> bool:
	if player_ids().is_empty():
		return false

	for peer_id in player_ids():
		if is_player_alive(peer_id):
			return false

	return true


func did_player_cross_trigger_since_last_update(peer_id: int, target_id: String) -> bool:
	return GeometryService.did_player_cross_trigger_since_last_update(self, peer_id, target_id)


func _shape_rect_for_object(target_id: String, shape_field: String, override_position: Dictionary = {}) -> Rect2:
	return GeometryService.shape_rect_for_object(self, target_id, shape_field, override_position)


func _event(kind: String, request_action: String, peer_id: int, target_id: String = "", extra: Dictionary = {}) -> Dictionary:
	var event := {
		"kind": kind,
		"request_action": request_action,
		"peer_id": peer_id,
		"level_index": current_level,
		"level_id": current_level_id,
	}
	if not target_id.is_empty():
		event["target_id"] = target_id
		event["sync_id"] = target_id

	for key in extra.keys():
		event[key] = extra[key]

	return event


func _ok(events: Array[Dictionary]) -> Dictionary:
	return {
		"ok": true,
		"events": events,
	}


func _error(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
	}


func event(kind: String, request_action: String, peer_id: int, target_id: String = "", extra: Dictionary = {}) -> Dictionary:
	return _event(kind, request_action, peer_id, target_id, extra)


func ok(events: Array[Dictionary]) -> Dictionary:
	return _ok(events)


func error(code: String, message: String) -> Dictionary:
	return _error(code, message)
