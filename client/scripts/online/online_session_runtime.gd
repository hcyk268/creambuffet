extends RefCounted
class_name OnlineSessionRuntime

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const OnlineLevelResolver = preload("res://scripts/online/online_level_resolver.gd")
const OnlinePushableSync = preload("res://scripts/online/online_pushable_sync.gd")
const RemotePlayerRegistry = preload("res://scripts/online/remote_player_registry.gd")

var _owner


func setup(owner) -> void:
	_owner = owner


func on_local_player_oxygen_changed(current: float, maximum: float) -> void:
	if _owner._hud_presenter != null:
		_owner._hud_presenter.update_oxygen(current, maximum)


func refresh_oxygen_hud_from_player() -> void:
	if _owner._hud_presenter != null:
		_owner._hud_presenter.refresh_oxygen_from_player(_owner.player)


func update_respawn_budget_hud(state: Dictionary) -> void:
	if _owner._hud_presenter != null:
		_owner._hud_presenter.update_respawn_budget(state)


func bind_network_signals() -> void:
	var on_state := Callable(self, "on_remote_player_state")
	if not _owner._network_client.remote_player_state.is_connected(on_state):
		_owner._network_client.remote_player_state.connect(on_state)

	var on_room := Callable(self, "on_current_room_changed")
	if not _owner._network_client.current_room_changed.is_connected(on_room):
		_owner._network_client.current_room_changed.connect(on_room)

	var on_transition := Callable(self, "on_level_transition")
	if not _owner._network_client.level_transition.is_connected(on_transition):
		_owner._network_client.level_transition.connect(on_transition)

	var on_pushable_control := Callable(self, "on_pushable_control_received")
	if not _owner._network_client.pushable_control_received.is_connected(on_pushable_control):
		_owner._network_client.pushable_control_received.connect(on_pushable_control)

	var on_world_event := Callable(self, "on_world_event_received")
	if not _owner._network_client.world_event_received.is_connected(on_world_event):
		_owner._network_client.world_event_received.connect(on_world_event)


func unbind_network_signals() -> void:
	if _owner._network_client == null:
		return

	var on_state := Callable(self, "on_remote_player_state")
	if _owner._network_client.remote_player_state.is_connected(on_state):
		_owner._network_client.remote_player_state.disconnect(on_state)

	var on_room := Callable(self, "on_current_room_changed")
	if _owner._network_client.current_room_changed.is_connected(on_room):
		_owner._network_client.current_room_changed.disconnect(on_room)

	var on_transition := Callable(self, "on_level_transition")
	if _owner._network_client.level_transition.is_connected(on_transition):
		_owner._network_client.level_transition.disconnect(on_transition)

	var on_pushable_control := Callable(self, "on_pushable_control_received")
	if _owner._network_client.pushable_control_received.is_connected(on_pushable_control):
		_owner._network_client.pushable_control_received.disconnect(on_pushable_control)

	var on_world_event := Callable(self, "on_world_event_received")
	if _owner._network_client.world_event_received.is_connected(on_world_event):
		_owner._network_client.world_event_received.disconnect(on_world_event)


func setup_local_network_identity() -> void:
	var peer_id: int = _owner._network_client.get_local_peer_id()
	var player_name := player_name_for_peer(peer_id)
	if _owner.player.has_method("set_network_identity"):
		_owner.player.set_network_identity(peer_id, player_name)
	if _owner.player.has_method("set_network_remote"):
		_owner.player.set_network_remote(false)


func connect_player_runtime_events() -> void:
	if _owner.player == null:
		return

	if _owner.player.has_signal("oxygen_depleted") and _owner._world_event_bridge != null:
		var on_oxygen_depleted := Callable(_owner._world_event_bridge, "on_local_player_oxygen_depleted")
		if not _owner.player.is_connected("oxygen_depleted", on_oxygen_depleted):
			_owner.player.connect("oxygen_depleted", on_oxygen_depleted)

	if _owner.player.has_signal("oxygen_changed"):
		var on_oxygen_changed := Callable(self, "on_local_player_oxygen_changed")
		if not _owner.player.is_connected("oxygen_changed", on_oxygen_changed):
			_owner.player.connect("oxygen_changed", on_oxygen_changed)

	refresh_oxygen_hud_from_player()


func sync_remote_roster(room: Dictionary = {}) -> void:
	if not _owner._is_online_session or _owner._remote_registry == null:
		return

	var room_data := room
	if room_data.is_empty():
		room_data = _owner._network_client.get_current_room()

	var local_peer_id: int = _owner._network_client.get_local_peer_id()
	_owner._remote_registry.sync_roster(room_data, local_peer_id)


func ensure_remote_player(peer_id: int, player_name: String = "") -> CharacterBody2D:
	if _owner._remote_registry == null:
		return null
	return _owner._remote_registry.ensure(peer_id, player_name)


func remove_remote_players() -> void:
	if _owner._remote_registry != null:
		_owner._remote_registry.remove_all()


func on_remote_player_state(peer_id: int, state: Dictionary) -> void:
	if not _owner._is_online_session:
		return

	if _owner._remote_registry != null:
		_owner._remote_registry.apply_state(peer_id, state, _owner._current_level_index)


func on_current_room_changed(room: Dictionary) -> void:
	if room.is_empty():
		remove_remote_players()
		cache_failure_state({})
		update_failure_hud()
		return

	sync_remote_roster(room)
	apply_match_state_snapshot(room)
	_owner._update_level_label(_owner._match_complete)
	cache_failure_state(room)
	update_failure_hud()


func on_level_transition(from_level_index: int, to_level_index: int, match_complete: bool, room: Dictionary) -> void:
	if match_complete:
		_owner._match_complete = true
		if _owner._world_event_bridge != null:
			_owner._world_event_bridge.set_match_complete(true)
		sync_remote_roster(room)
		apply_match_state_snapshot(room)
		_owner._update_level_label(true)
		cache_failure_state(room)
		update_failure_hud()
		return

	var target_level_id := String(room.get("current_level_id", ""))
	var target_index := OnlineLevelResolver.index_for_level_id(
		_owner._is_online_session,
		_owner._online_level_ids,
		target_level_id,
		to_level_index,
		_owner._current_room()
	)
	if bool(room.get("_restart_level", false)) or target_index != _owner._current_level_index or from_level_index == to_level_index:
		_owner.load_level(target_index)

	sync_remote_roster(room)
	apply_match_state_snapshot(room)
	cache_failure_state(room)
	update_failure_hud()


func on_pushable_control_received(level_index: int, controls: Array) -> void:
	if level_index != _owner._current_level_index:
		return

	apply_pushable_controls(controls)


func player_name_for_peer(peer_id: int) -> String:
	var room: Dictionary = _owner._network_client.get_current_room()
	return RemotePlayerRegistry.player_name_for_peer(room, peer_id)


func on_world_event_received(event: Dictionary) -> void:
	if _owner._world_event_bridge == null:
		return

	_owner._world_event_bridge.apply_remote_world_event(
		event,
		_owner._current_level_id,
		_owner._current_level_index,
		Callable(self, "player_for_peer"),
		Callable(self, "update_respawn_budget_hud")
	)


func decrement_shared_hud_hearts() -> void:
	if _owner._hud_presenter != null:
		_owner._hud_presenter.decrement_shared_hearts()


func will_eliminate_on_next_death() -> bool:
	return _owner._hud_presenter != null and _owner._hud_presenter.will_eliminate_on_next_death()


func apply_match_state_snapshot(room: Dictionary) -> void:
	if _owner._match_state_applier == null:
		return

	if _owner._world_event_bridge != null:
		_owner._world_event_bridge.set_remote_apply_active(true)
	_owner._match_state_applier.apply(
		room,
		_owner._current_level,
		Callable(self, "apply_pushable_controls"),
		Callable(self, "update_respawn_budget_hud")
	)
	if _owner._world_event_bridge != null:
		_owner._world_event_bridge.set_remote_apply_active(false)
	cache_failure_state(room)


func player_for_peer(peer_id: int) -> CharacterBody2D:
	if _owner._remote_registry == null:
		return _owner.player if peer_id == _owner._network_client.get_local_peer_id() else null
	return _owner._remote_registry.player_for_peer(peer_id, _owner._network_client.get_local_peer_id(), _owner.player)


func apply_pushable_controls(raw_controls) -> void:
	OnlinePushableSync.apply_pushable_controls(_owner._current_level, raw_controls, _owner._synced_node_registry)


func collect_pushable_state_observations() -> Array[Dictionary]:
	return OnlinePushableSync.collect_pushable_state_observations(_owner._current_level)


func cache_failure_state(room: Dictionary) -> void:
	if _owner._hud_presenter == null:
		return
	_owner._hud_presenter.cache_failure_state(room, GameCatalog.get_level(_owner._current_level_id))


func update_failure_hud() -> void:
	if _owner._hud_presenter == null:
		return
	_owner._hud_presenter.update_failure_hud(
		_owner._match_complete,
		_owner._current_level_index,
		_owner._total_level_count(),
		_owner._is_online_session,
		_owner._current_room(),
		_owner._current_level_id
	)


func refresh_hud_failure_fallback_state() -> void:
	if _owner._hud_presenter != null:
		_owner._hud_presenter.refresh_failure_fallback_state(GameCatalog.get_level(_owner._current_level_id))
