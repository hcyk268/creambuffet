extends Node2D

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const GameIds = preload("res://scripts/catalog/game_ids.gd")
const RemotePlayerRegistry = preload("res://scripts/online/remote_player_registry.gd")
const SyncedNodeRegistry = preload("res://scripts/online/synced_node_registry.gd")
const OnlineHudPresenter = preload("res://scripts/online/online_hud_presenter.gd")
const OnlineLevelLoader = preload("res://scripts/online/online_level_loader.gd")
const OnlineMatchStateApplier = preload("res://scripts/online/online_match_state_applier.gd")
const OnlinePushableSync = preload("res://scripts/online/online_pushable_sync.gd")
const OnlineLevelResolver = preload("res://scripts/online/online_level_resolver.gd")
const OnlineSessionRuntime = preload("res://scripts/online/online_session_runtime.gd")
const OnlineWorldEventBridge = preload("res://scripts/online/online_world_event_bridge.gd")
const WorldObjectStateApplier = preload("res://scripts/online/world_object_state_applier.gd")
const NETWORK_SEND_INTERVAL := 0.05

@export var levels: Array[PackedScene] = []
@export var start_level_index := 0

@onready var player: CharacterBody2D = $Player
@onready var level_container: Node2D = $LevelContainer
@onready var level_label: Label = $CanvasLayer/LevelLabel
@onready var water_hud: Control = $CanvasLayer/WaterHud
@onready var oxygen_bar: ProgressBar = $CanvasLayer/WaterHud/OxygenBar
@onready var oxygen_label: Label = $CanvasLayer/WaterHud/OxygenLabel
@onready var respawn_label: Label = $CanvasLayer/WaterHud/RespawnLabel
@onready var time_label: Label = $CanvasLayer/TimeLabel
@onready var level_transition: LevelTransition = $LevelTransition
@onready var time_out_player: AudioStreamPlayer = get_node_or_null("TimeOutSfx") as AudioStreamPlayer

var _current_level: Node
var _current_level_index := -1
var _current_level_id := ""
var _online_level_ids: Array[String] = []
var _network_client: Node
var _is_online_session := false
var _remote_registry: RemotePlayerRegistry
var _send_timer := 0.0
var _match_complete := false
var _synced_node_registry: SyncedNodeRegistry
var _hud_presenter: OnlineHudPresenter
var _world_object_applier: WorldObjectStateApplier
var _level_loader: OnlineLevelLoader
var _match_state_applier: OnlineMatchStateApplier
var _session_runtime: OnlineSessionRuntime
var _world_event_bridge: OnlineWorldEventBridge


func _ready() -> void:
	_network_client = get_node_or_null("/root/NetworkClient")
	_is_online_session = _network_client != null and not _network_client.get_current_room().is_empty()
	_remote_registry = RemotePlayerRegistry.new()
	_remote_registry.setup(self, player)
	_synced_node_registry = SyncedNodeRegistry.new()
	_level_loader = OnlineLevelLoader.new()
	_hud_presenter = OnlineHudPresenter.new()
	_hud_presenter.setup(
		level_label,
		water_hud,
		oxygen_bar,
		oxygen_label,
		respawn_label,
		time_label,
		Callable(self, "_on_time_limit_expired")
	)
	_world_object_applier = WorldObjectStateApplier.new()
	_world_object_applier.setup(player, _network_client, _synced_node_registry)
	_match_state_applier = OnlineMatchStateApplier.new()
	_match_state_applier.setup(_world_object_applier, _synced_node_registry, _network_client, player)
	_session_runtime = OnlineSessionRuntime.new()
	_session_runtime.setup(self)
	_world_event_bridge = OnlineWorldEventBridge.new()
	_world_event_bridge.setup(
		player,
		_network_client,
		_synced_node_registry,
		_world_object_applier,
		Callable(_session_runtime, "decrement_shared_hud_hearts"),
		Callable(_session_runtime, "will_eliminate_on_next_death"),
		Callable(_session_runtime, "update_failure_hud")
	)

	if levels.is_empty():
		push_warning("Game has no levels configured.")
		return

	if _is_online_session:
		_bind_network_signals()
		_setup_local_network_identity()
		_connect_player_runtime_events()
		_configure_online_levels()

	var safe_start_index := clampi(start_level_index, 0, levels.size() - 1)
	if _is_online_session:
		var room: Dictionary = _network_client.get_current_room()
		safe_start_index = clampi(int(room.get("current_level_index", safe_start_index)), 0, levels.size() - 1)

	load_level(safe_start_index)
	_sync_remote_roster()
	if _is_online_session:
		_cache_failure_state(_network_client.get_current_room())
	else:
		_cache_failure_state({})
	_update_failure_hud()


func _exit_tree() -> void:
	_unbind_network_signals()


func _process(_delta: float) -> void:
	_update_failure_hud()


func _physics_process(delta: float) -> void:
	if not _is_online_session or _match_complete or _current_level_index < 0:
		return

	_send_timer += delta
	if _send_timer < NETWORK_SEND_INTERVAL:
		return

	_send_timer = 0.0
	if player.has_method("get_network_state"):
		var state: Dictionary = player.get_network_state(_current_level_index)
		var pushable_states := _collect_pushable_state_observations()
		if not pushable_states.is_empty():
			state["pushable_states"] = pushable_states
		if player.has_method("consume_push_intents"):
			var push_intents: Array[Dictionary] = player.consume_push_intents()
			if not push_intents.is_empty():
				state["push_intents"] = push_intents
		_network_client.send_player_state(state)


func _on_time_limit_expired() -> void:
	if time_out_player == null or time_out_player.stream == null:
		return
	time_out_player.play()


func load_level(index: int) -> void:
	if level_transition != null:
		level_transition.transition(func(): _do_load_level(index))
	else:
		_do_load_level(index)
	
func _do_load_level(index: int) -> void:	
	var load_result := _level_loader.load_level(
		level_container,
		_current_level,
		player,
		_remote_registry,
		_synced_node_registry,
		_is_online_session,
		levels,
		_online_level_ids,
		index,
		_current_room()
	)
	if not bool(load_result.get("ok", false)):
		push_warning(String(load_result.get("message", "Could not load level.")))
		return

	_current_level = load_result.get("level")
	_current_level_index = int(load_result.get("level_index", index))
	_current_level_id = String(load_result.get("level_id", ""))
	_match_complete = false
	_apply_level_player_defaults()
	if _world_event_bridge != null:
		_world_event_bridge.reset_local_runtime_state(_current_level_id)

	if _world_event_bridge != null:
		_world_event_bridge.connect_level(_current_level)
	_refresh_hud_failure_fallback_state()
	_update_level_label(false)
	_refresh_water_hud_for_level()
	_update_failure_hud()
	call_deferred("_finalize_level_spawn")


func _configure_online_levels() -> void:
	if not _is_online_session:
		return

	var resolved := _level_loader.configure_online_levels(_network_client.get_current_room())
	var runtime_levels: Array[PackedScene] = resolved.get("levels", [])
	_online_level_ids = Array(resolved.get("level_ids", []))

	if runtime_levels.is_empty():
		push_warning("No online levels could be resolved for map %s." % String(resolved.get("map_id", GameCatalog.DEFAULT_MAP_ID)))
		return

	levels = runtime_levels


func restart_level() -> void:
	if _current_level_index < 0:
		return

	load_level(_current_level_index)


func _finalize_level_spawn() -> void:
	_level_loader.finalize_level_spawn(_current_level, player, _remote_registry)


func _update_level_label(game_complete: bool) -> void:
	if _hud_presenter == null:
		return
	_hud_presenter.update_level_label(
		game_complete,
		_current_level_index,
		_total_level_count(),
		_is_online_session,
		_current_room(),
		_current_level_id
	)


func _refresh_water_hud_for_level() -> void:
	if _hud_presenter == null:
		return

	var has_oxygen := _current_level_uses_ruleset(GameIds.RULESET_OXYGEN_V1)
	var respawn_state := _team_respawn_budget_state_for_current_level()
	_hud_presenter.refresh_water_hud(has_oxygen, respawn_state, player)


func _apply_level_player_defaults() -> void:
	if player == null or not player.has_method("apply_runtime_state") or _current_level_id.is_empty():
		return

	var level_def := GameCatalog.get_level(_current_level_id)
	var player_defaults_raw: Variant = level_def.get("player_state_defaults", {})
	if typeof(player_defaults_raw) != TYPE_DICTIONARY:
		return

	player.apply_runtime_state(player_defaults_raw)


func _current_level_uses_ruleset(ruleset_id: String) -> bool:
	if _current_level_id.is_empty():
		return false

	var level_def := GameCatalog.get_level(_current_level_id)
	var raw_rulesets: Variant = level_def.get("rulesets", [])
	if typeof(raw_rulesets) != TYPE_ARRAY:
		return false

	for raw_ruleset in raw_rulesets:
		if String(raw_ruleset) == ruleset_id:
			return true
	return false


func _team_respawn_budget_state_for_current_level() -> Dictionary:
	if _current_level_id.is_empty():
		return {}

	var level_def := GameCatalog.get_level(_current_level_id)
	var objects_raw: Variant = level_def.get("objects", {})
	if typeof(objects_raw) != TYPE_DICTIONARY:
		return {}

	var objects: Dictionary = objects_raw
	for raw_object in objects.values():
		if typeof(raw_object) != TYPE_DICTIONARY:
			continue
		var object_data: Dictionary = raw_object
		if String(object_data.get("kind", "")) != GameIds.OBJECT_KIND_TEAM_RESPAWN_BUDGET:
			continue
		var state_raw: Variant = object_data.get("state", {})
		if typeof(state_raw) == TYPE_DICTIONARY:
			return Dictionary(state_raw).duplicate(true)
		return {
			"used": 0,
			"max": int(object_data.get("max_respawns", 3)),
			"failed": false,
		}

	return {}


func _current_room() -> Dictionary:
	if _is_online_session and _network_client != null:
		return _network_client.get_current_room()
	return {}


func _total_level_count() -> int:
	var total_levels := levels.size()
	if not _is_online_session or _network_client == null:
		return total_levels

	var room: Dictionary = _network_client.get_current_room()
	var room_level_ids = room.get("level_ids", [])
	if typeof(room_level_ids) == TYPE_ARRAY and not room_level_ids.is_empty():
		total_levels = room_level_ids.size()
	return total_levels


func _on_local_player_oxygen_changed(current: float, maximum: float) -> void:
	if _session_runtime != null:
		_session_runtime.on_local_player_oxygen_changed(current, maximum)


func _refresh_oxygen_hud_from_player() -> void:
	if _session_runtime != null:
		_session_runtime.refresh_oxygen_hud_from_player()


func _update_oxygen_hud(current: float, maximum: float) -> void:
	if _session_runtime != null:
		_session_runtime.on_local_player_oxygen_changed(current, maximum)


func _update_respawn_budget_hud(state: Dictionary) -> void:
	if _session_runtime != null:
		_session_runtime.update_respawn_budget_hud(state)


func _bind_network_signals() -> void:
	if _session_runtime != null:
		_session_runtime.bind_network_signals()


func _unbind_network_signals() -> void:
	if _session_runtime != null:
		_session_runtime.unbind_network_signals()


func _setup_local_network_identity() -> void:
	if _session_runtime != null:
		_session_runtime.setup_local_network_identity()


func _connect_player_runtime_events() -> void:
	if _session_runtime != null:
		_session_runtime.connect_player_runtime_events()


func _sync_remote_roster(room: Dictionary = {}) -> void:
	if _session_runtime != null:
		_session_runtime.sync_remote_roster(room)


func _ensure_remote_player(peer_id: int, player_name: String = "") -> CharacterBody2D:
	return _session_runtime.ensure_remote_player(peer_id, player_name) if _session_runtime != null else null


func _remove_remote_players() -> void:
	if _session_runtime != null:
		_session_runtime.remove_remote_players()


func _on_remote_player_state(peer_id: int, state: Dictionary) -> void:
	if _session_runtime != null:
		_session_runtime.on_remote_player_state(peer_id, state)


func _on_current_room_changed(room: Dictionary) -> void:
	if _session_runtime != null:
		_session_runtime.on_current_room_changed(room)


func _on_level_transition(_from_level_index: int, to_level_index: int, match_complete: bool, room: Dictionary) -> void:
	if _session_runtime != null:
		_session_runtime.on_level_transition(_from_level_index, to_level_index, match_complete, room)


func _on_pushable_control_received(level_index: int, controls: Array) -> void:
	if _session_runtime != null:
		_session_runtime.on_pushable_control_received(level_index, controls)


func _player_name_for_peer(peer_id: int) -> String:
	return _session_runtime.player_name_for_peer(peer_id) if _session_runtime != null else ""


func _on_world_event_received(event: Dictionary) -> void:
	if _session_runtime != null:
		_session_runtime.on_world_event_received(event)

func _apply_match_state_snapshot(room: Dictionary) -> void:
	if _session_runtime != null:
		_session_runtime.apply_match_state_snapshot(room)

func _player_for_peer(peer_id: int) -> CharacterBody2D:
	return _session_runtime.player_for_peer(peer_id) if _session_runtime != null else null

func _apply_pushable_controls(raw_controls) -> void:
	if _session_runtime != null:
		_session_runtime.apply_pushable_controls(raw_controls)


func _collect_pushable_state_observations() -> Array[Dictionary]:
	return _session_runtime.collect_pushable_state_observations() if _session_runtime != null else []


func _level_id_for_index(index: int) -> String:
	return OnlineLevelResolver.level_id_for_index(_is_online_session, _online_level_ids, index, _current_room())


func _index_for_level_id(level_id: String, fallback_index: int) -> int:
	return OnlineLevelResolver.index_for_level_id(_is_online_session, _online_level_ids, level_id, fallback_index, _current_room())


func _cache_failure_state(room: Dictionary) -> void:
	if _session_runtime != null:
		_session_runtime.cache_failure_state(room)


func _update_failure_hud() -> void:
	if _session_runtime != null:
		_session_runtime.update_failure_hud()


func _refresh_hud_failure_fallback_state() -> void:
	if _session_runtime != null:
		_session_runtime.refresh_hud_failure_fallback_state()
