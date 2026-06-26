extends SceneTree

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const GameIds = preload("res://scripts/catalog/game_ids.gd")
const CreateRoomPanelScene = preload("res://scenes/create_room_panel.tscn")
const OfflineGameScene = preload("res://scenes/offline/offline_game.tscn")
const OnlineGameScene = preload("res://scenes/online/online_game.tscn")


class StubNetworkClient:
	extends Node

	signal connection_state_changed(state, details)
	signal error_received(code, message)
	signal remote_player_state(peer_id, state)
	signal current_room_changed(room)
	signal level_transition(from_level_index, to_level_index, match_complete, room)
	signal pushable_control_received(level_index, controls)
	signal world_event_received(event)

	var _current_room: Dictionary = {}
	var _local_peer_id := 1
	var sent_world_events: Array[Dictionary] = []
	var create_room_calls: Array[Dictionary] = []

	func get_current_room() -> Dictionary:
		return _current_room.duplicate(true)

	func get_local_peer_id() -> int:
		return _local_peer_id

	func get_server_endpoint() -> String:
		return "127.0.0.1:7000"

	func send_player_state(_state: Dictionary) -> void:
		pass

	func send_world_event(event: Dictionary) -> void:
		sent_world_events.append(event.duplicate(true))

	func send_world_action(_action: String, _target_id: String, _payload: Dictionary) -> void:
		pass

	func create_room(max_players: int, world_count: int, randomized: bool, visibility: String = GameIds.ROOM_VISIBILITY_PUBLIC, map_id: String = "beginner") -> void:
		create_room_calls.append({
			"max_players": max_players,
			"world_count": world_count,
			"randomized": randomized,
			"visibility": visibility,
			"map_id": map_id,
		})


func _init() -> void:
	await _run()


func _run() -> void:
	var failures: Array[String] = []
	await _test_offline_scene_smoke(failures)
	await _test_online_scene_smoke(failures)
	await _test_create_room_panel_private_smoke(failures)
	await _test_online_map_loading_smoke(failures)

	if failures.is_empty():
		print("Game scene smoke tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_offline_scene_smoke(failures: Array[String]) -> void:
	var offline_game := OfflineGameScene.instantiate()
	root.add_child(offline_game)
	await _settle_frames()

	var current_level = offline_game.get("_current_level")
	if not is_instance_valid(current_level):
		failures.append("OfflineGame did not instantiate its starting level.")

	var player := offline_game.get_node_or_null("Player") as CharacterBody2D
	if player == null:
		failures.append("OfflineGame did not keep its local player node.")
	else:
		var spawn_point := current_level.get_node_or_null("SpawnPoint") as Node2D if is_instance_valid(current_level) else null
		if spawn_point == null or not player.spawn_position.is_equal_approx(spawn_point.global_position):
			failures.append("OfflineGame did not align player spawn_position with the loaded spawn point.")

	var key_node := _find_node_by_sync_id(current_level, "level01_key_01")
	if key_node == null:
		failures.append("OfflineGame smoke could not find the expected key node in offline_level_001.")
	elif player != null:
		key_node.emit_signal("collected", player)
		if int(player.get("key_count")) != 1:
			failures.append("OfflineGame did not apply local key collection to the player state.")
		if not key_node.is_queued_for_deletion():
			failures.append("OfflineGame did not remove the collected key node.")

	var goal_node := _find_node_by_sync_id(current_level, "level01_goal_01")
	if goal_node == null:
		failures.append("OfflineGame smoke could not find the expected goal node in offline_level_001.")
	elif player != null:
		goal_node.emit_signal("goal_reached", player)
		await _settle_frames(1)
		var completion_screen := offline_game.get_node_or_null("CompletionScreen")
		if completion_screen == null or not completion_screen.call("is_open"):
			failures.append("OfflineGame did not open the completion screen after reaching the only offline goal.")

	await _dispose_node(offline_game)


func _test_online_scene_smoke(failures: Array[String]) -> void:
	var network_client := await _install_stub_network_client({
		"map_id": "beginner",
		"status": "playing",
		"current_level_index": 0,
		"current_level_id": "beginner_01",
		"level_ids": ["beginner_01", "beginner_02"],
		"players": [
			{"peer_id": 1, "display_name": "Local"},
			{"peer_id": 2, "display_name": "Remote"},
		],
		"match_state": {
			"current_level_id": "beginner_01",
			"objects": {},
			"players": {},
			"pushables": [],
		},
	})

	var online_game := OnlineGameScene.instantiate()
	root.add_child(online_game)
	await _settle_frames()

	if String(online_game.get("_current_level_id")) != "beginner_01":
		failures.append("OnlineGame did not load the room's current_level_id on startup.")
	if int(online_game.get("_current_level_index")) != 0:
		failures.append("OnlineGame did not load the room's current_level_index on startup.")
	var local_player := online_game.get_node_or_null("Player") as CharacterBody2D
	if local_player == null:
		failures.append("OnlineGame did not keep its local player node.")
	elif int(local_player.get("network_peer_id")) != 1:
		failures.append("OnlineGame did not assign the local network identity during startup.")

	var remote_container := online_game.get_node_or_null("RemotePlayers")
	if remote_container == null:
		failures.append("OnlineGame did not create the RemotePlayers container during setup.")
	else:
		var remote_player := remote_container.get_node_or_null("RemotePlayer_2") as CharacterBody2D
		if remote_player == null:
			failures.append("OnlineGame did not sync the initial remote roster from the room snapshot.")
		else:
			network_client.remote_player_state.emit(2, {
				"level_index": 0,
				"position": {"x": 320.0, "y": -12.0},
				"velocity": {"x": 0.0, "y": 0.0},
				"display_name": "Remote",
			})
			await _settle_frames(1)
			if not remote_player.is_remote_player:
				failures.append("RemotePlayerRegistry did not configure synced remote players as remote-controlled.")
			elif not remote_player.global_position.is_equal_approx(Vector2(320.0, -12.0)):
				failures.append("OnlineGame did not apply remote player state snapshots to the remote player node.")

	var current_level: Node = online_game.get("_current_level") as Node
	var goal_node := _find_node_by_sync_id(current_level, "level01_goal_01")
	if goal_node == null:
		failures.append("OnlineGame smoke could not find the expected goal node in level_01.")
	elif local_player != null:
		local_player.global_position = Vector2(168.0, -17.0)
		local_player.velocity = Vector2(9.0, -3.0)
		goal_node.emit_signal("goal_reached", local_player)
		goal_node.emit_signal("goal_left", local_player)
		await _settle_frames(1)
		if network_client.sent_world_events.size() < 2:
			failures.append("OnlineGame did not send both goal_enter and goal_exit world events.")
		else:
			var enter_event: Dictionary = network_client.sent_world_events[network_client.sent_world_events.size() - 2]
			var exit_event: Dictionary = network_client.sent_world_events[network_client.sent_world_events.size() - 1]
			if String(enter_event.get("action", "")) != "goal_enter":
				failures.append("OnlineGame sent the wrong action for goal_enter.")
			if enter_event.get("position", {}) != {"x": 168.0, "y": -17.0}:
				failures.append("OnlineGame did not include the local position in goal_enter world events.")
			if enter_event.get("velocity", {}) != {"x": 9.0, "y": -3.0}:
				failures.append("OnlineGame did not include the local velocity in goal_enter world events.")
			if String(exit_event.get("action", "")) != "goal_exit":
				failures.append("OnlineGame sent the wrong action for goal_exit.")
			if exit_event.get("position", {}) != {"x": 168.0, "y": -17.0}:
				failures.append("OnlineGame did not include the local position in goal_exit world events.")
			if exit_event.get("velocity", {}) != {"x": 9.0, "y": -3.0}:
				failures.append("OnlineGame did not include the local velocity in goal_exit world events.")

	var key_node := _find_node_by_sync_id(current_level, "level01_key_01")
	var door_node := _find_node_by_sync_id(current_level, "level01_door_01")
	if key_node == null or door_node == null:
		failures.append("OnlineGame smoke could not find the expected key/door nodes in level_01.")
	elif local_player != null:
		network_client.world_event_received.emit({
			"kind": "key_collected",
			"request_action": "collect",
			"peer_id": 1,
			"level_index": 0,
			"level_id": "beginner_01",
			"target_id": "level01_key_01",
			"sync_id": "level01_key_01",
			"state": {"collected": true},
		})
		await _settle_frames(1)
		if int(local_player.get("key_count")) != 1:
			failures.append("OnlineGame did not apply key_collected world events to the local player state.")
		if is_instance_valid(key_node):
			failures.append("OnlineGame did not remove the collected key node after a key_collected event.")

		network_client.world_event_received.emit({
			"kind": "door_opened",
			"request_action": "open",
			"peer_id": 1,
			"level_index": 0,
			"level_id": "beginner_01",
			"target_id": "level01_door_01",
			"sync_id": "level01_door_01",
			"state": {"opened": true},
		})
		await _settle_frames(1)
		if not bool(door_node.get("is_open")):
			failures.append("OnlineGame did not apply door_opened world events to the synced door node.")
		if int(local_player.get("key_count")) != 0:
			failures.append("OnlineGame did not consume the local carried key after a door_opened event.")

	var room_snapshot := network_client.get_current_room()
	room_snapshot["match_state"] = {
		"current_level_id": "beginner_01",
		"objects": {
			"level01_door_01": {
				"kind": "door",
				"state": {"opened": false},
			},
		},
		"players": {
			1: {
				"key_count": 2,
				"max_oxygen": 18.0,
				"oxygen": 4.0,
			},
		},
		"pushables": [],
	}
	network_client._current_room = room_snapshot.duplicate(true)
	network_client.current_room_changed.emit(room_snapshot)
	if local_player != null and int(local_player.get("key_count")) != 2:
		failures.append("OnlineGame did not apply local player key_count from a match_state snapshot.")
	if local_player != null and not is_equal_approx(float(local_player.get("max_oxygen")), 18.0):
		failures.append("OnlineGame did not apply local player max_oxygen from a match_state snapshot.")
	if local_player != null and not is_equal_approx(float(local_player.get("oxygen")), 4.0):
		failures.append("OnlineGame did not apply local player oxygen from a match_state snapshot.")
	if door_node != null and bool(door_node.get("is_open")):
		failures.append("OnlineGame did not apply synced object state from a match_state snapshot.")
	if network_client.sent_world_events.size() != 2:
		failures.append("OnlineGame echoed an open request while applying an authoritative closed-door snapshot.")

	var restart_room := network_client.get_current_room()
	restart_room["_restart_level"] = true
	network_client.level_transition.emit(0, 0, false, restart_room)
	await _settle_frames()
	if int(online_game.get("_current_level_index")) != 0:
		failures.append("OnlineGame did not keep a stable level index across a restart transition.")

	var next_room := network_client.get_current_room()
	next_room["current_level_index"] = 1
	next_room["current_level_id"] = "beginner_02"
	next_room.erase("_restart_level")
	network_client._current_room = next_room.duplicate(true)
	network_client.level_transition.emit(0, 1, false, next_room)
	await _settle_frames()
	if int(online_game.get("_current_level_index")) != 1 or String(online_game.get("_current_level_id")) != "beginner_02":
		failures.append("OnlineGame did not transition to the next online level from the room payload.")

	var level_two: Node = online_game.get("_current_level") as Node
	var button_node := _find_node_by_sync_id(level_two, "level02_button_01")
	var push_box_node := _find_node_by_sync_id(level_two, "level02_box_01")
	var platform_node := _find_node_by_sync_id(level_two, "level02_platform_01")
	if button_node == null or push_box_node == null or platform_node == null:
		failures.append("OnlineGame smoke could not find the expected button/push-box/platform nodes in level_02.")
	else:
		network_client.world_event_received.emit({
			"kind": "button_state",
			"request_action": "button_state",
			"peer_id": 1,
			"level_index": 1,
			"level_id": "beginner_02",
			"target_id": "level02_button_01",
			"sync_id": "level02_button_01",
			"pressed": true,
			"state": {"pressed": true},
		})
		await _settle_frames(1)
		if not bool(button_node.get("is_pressed")):
			failures.append("OnlineGame did not apply button_state world events on level_02.")

		network_client.world_event_received.emit({
			"kind": "push_box_state",
			"request_action": "push_box_state",
			"peer_id": 1,
			"level_index": 1,
			"level_id": "beginner_02",
			"target_id": "level02_box_01",
			"sync_id": "level02_box_01",
			"position": {"x": 96.0, "y": 32.0},
		})
		if push_box_node is Node2D and not (push_box_node as Node2D).global_position.is_equal_approx(Vector2(96.0, 32.0)):
			failures.append("OnlineGame did not apply push_box_state world events on level_02.")

		var level_two_snapshot := network_client.get_current_room()
		level_two_snapshot["match_state"] = {
			"current_level_id": "beginner_02",
			"objects": {
				"level02_platform_01": {
					"kind": "moving_platform",
					"state": {"active": true},
				},
			},
			"players": {},
			"pushables": [],
		}
		network_client._current_room = level_two_snapshot.duplicate(true)
		network_client.current_room_changed.emit(level_two_snapshot)
		await _settle_frames(1)
		if not bool(platform_node.get("activation")):
			failures.append("OnlineGame did not apply moving-platform activation from a level_02 snapshot.")

	await _dispose_node(online_game)
	await _dispose_node(network_client)


func _test_create_room_panel_private_smoke(failures: Array[String]) -> void:
	var network_client := await _install_stub_network_client({})
	var create_room_panel := CreateRoomPanelScene.instantiate()
	root.add_child(create_room_panel)
	await _settle_frames()

	if not create_room_panel.has_method("set_room_visibility"):
		failures.append("CreateRoomPanel is missing set_room_visibility() for room visibility selection.")
	else:
		create_room_panel.set_room_visibility(GameIds.ROOM_VISIBILITY_PRIVATE)
		create_room_panel.call("_on_create_butt_pressed")
		if network_client.create_room_calls.size() != 1:
			failures.append("CreateRoomPanel did not forward a create_room request for a private room.")
		else:
			var call: Dictionary = network_client.create_room_calls[0]
			if String(call.get("visibility", "")) != GameIds.ROOM_VISIBILITY_PRIVATE:
				failures.append("CreateRoomPanel did not send private visibility when creating a private room.")
			if int(call.get("max_players", 0)) != 2:
				failures.append("CreateRoomPanel changed the default max_players while creating a private room.")

	await _dispose_node(create_room_panel)
	await _dispose_node(network_client)


func _test_online_map_loading_smoke(failures: Array[String]) -> void:
	for map_id in GameCatalog.get_map_ids():
		var level_ids := GameCatalog.get_level_ids(map_id)
		if level_ids.is_empty():
			failures.append("Catalog map %s has no level ids to smoke-test." % map_id)
			continue

		var room := {
			"map_id": map_id,
			"status": "playing",
			"current_level_index": 0,
			"current_level_id": String(level_ids[0]),
			"level_ids": level_ids,
			"players": [
				{"peer_id": 1, "display_name": "Local"},
			],
			"match_state": {
				"current_level_id": String(level_ids[0]),
				"objects": {},
				"players": {},
				"pushables": [],
			},
		}

		var network_client := await _install_stub_network_client(room)

		var online_game := OnlineGameScene.instantiate()
		root.add_child(online_game)
		await _settle_frames()

		for index in range(level_ids.size()):
			if index > 0:
				online_game.load_level(index)
				await _settle_frames()
			if String(online_game.get("_current_level_id")) != String(level_ids[index]):
				failures.append("OnlineGame did not resolve level %s for map %s through the catalog runtime." % [String(level_ids[index]), map_id])
				break
			if not is_instance_valid(online_game.get("_current_level")):
				failures.append("OnlineGame did not instantiate level %s for map %s." % [String(level_ids[index]), map_id])
				break
			_assert_overlapping_door_draws_above_goal(online_game.get("_current_level"), String(level_ids[index]), failures)

		if map_id == "water":
			var water_hud := online_game.get_node_or_null("CanvasLayer/WaterHud") as Control
			var oxygen_bar := online_game.get_node_or_null("CanvasLayer/WaterHud/OxygenBar") as ProgressBar
			var respawn_label := online_game.get_node_or_null("CanvasLayer/WaterHud/RespawnLabel") as Label
			if water_hud == null or oxygen_bar == null or respawn_label == null:
				failures.append("Water-map smoke could not find the expected HUD nodes.")
			else:
				if not water_hud.visible or not oxygen_bar.visible:
					failures.append("OnlineGame did not enable the oxygen HUD for water maps.")
				if not respawn_label.visible:
					failures.append("OnlineGame did not enable the respawn-budget HUD for water maps.")

		await _dispose_node(online_game)
		await _dispose_node(network_client)


func _find_node_by_sync_id(root_node: Node, sync_id: String) -> Node:
	if not is_instance_valid(root_node):
		return null
	if str(root_node.get("sync_id")) == sync_id:
		return root_node

	for child in root_node.get_children():
		if child is Node:
			var match := _find_node_by_sync_id(child, sync_id)
			if match != null:
				return match

	return null


func _assert_overlapping_door_draws_above_goal(root_node: Node, level_id: String, failures: Array[String]) -> void:
	if not is_instance_valid(root_node):
		return

	var doors := _find_nodes_in_group(root_node, "level_door")
	var goals := _find_nodes_in_group(root_node, "level_goal")
	for door in doors:
		if not (door is Node2D):
			continue
		for goal in goals:
			if not (goal is Node2D):
				continue
			if not (door as Node2D).global_position.is_equal_approx((goal as Node2D).global_position):
				continue
			if int(door.get("z_index")) <= int(goal.get("z_index")):
				failures.append("Level %s draws an overlapping goal above its door, making the closed door look open." % level_id)


func _find_nodes_in_group(root_node: Node, group_name: StringName) -> Array[Node]:
	var result: Array[Node] = []
	_collect_nodes_in_group(root_node, group_name, result)
	return result


func _collect_nodes_in_group(node: Node, group_name: StringName, out_nodes: Array[Node]) -> void:
	if not is_instance_valid(node):
		return
	if node.is_in_group(group_name):
		out_nodes.append(node)
	for child in node.get_children():
		if child is Node:
			_collect_nodes_in_group(child, group_name, out_nodes)


func _settle_frames(count: int = 2) -> void:
	for _index in range(count):
		await process_frame


func _install_stub_network_client(room: Dictionary) -> StubNetworkClient:
	var existing := root.get_node_or_null("NetworkClient")
	if existing != null:
		await _dispose_node(existing)

	var network_client := StubNetworkClient.new()
	network_client.name = "NetworkClient"
	network_client._current_room = room.duplicate(true)
	root.add_child(network_client)
	await _settle_frames(1)
	return network_client


func _dispose_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	node.free()
	await _settle_frames(1)
