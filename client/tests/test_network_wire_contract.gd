extends SceneTree

const GameIds = preload("res://scripts/catalog/game_ids.gd")
const ProtocolConstants = preload("res://scripts/network/protocol_constants.gd")


class CapturingNetworkClient:
	extends "res://scripts/network/network_client.gd"

	var sent_packets: Array[Dictionary] = []
	var inferred_calls := 0
	var inferred_action := ""
	var inferred_payload: Dictionary = {}

	func _send_packet(
		message_type: String,
		payload: Dictionary = {},
		request_id: String = "",
		transfer_mode: int = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	) -> void:
		sent_packets.append({
			"type": message_type,
			"payload": payload.duplicate(true),
			"request_id": request_id,
			"transfer_mode": transfer_mode,
		})

	func _infer_legacy_target_id(action: String, payload: Dictionary) -> String:
		inferred_calls += 1
		inferred_action = action
		inferred_payload = payload.duplicate(true)
		return "legacy_button_01"


class EventRecorder:
	extends RefCounted

	var events: Array[Dictionary] = []

	func record(event: Dictionary) -> void:
		events.append(event.duplicate(true))


func _init() -> void:
	var failures: Array[String] = []
	_test_send_world_action(failures)
	_test_send_world_event_normalization(failures)
	_test_send_world_event_legacy_target_inference(failures)
	_test_handle_world_event_emits_duplicate(failures)

	if failures.is_empty():
		print("Client network wire-contract tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _new_client() -> CapturingNetworkClient:
	var client := CapturingNetworkClient.new()
	client.connection_state = "connected"
	client._current_room = {
		"map_id": "beginner",
		"current_level_id": "beginner_01",
	}
	return client


func _test_send_world_action(failures: Array[String]) -> void:
	var client := _new_client()
	client.send_world_action(GameIds.ACTION_OPEN, "level01_door_01", {
		"opened": true,
	})

	if client.sent_packets.size() != 1:
		failures.append("NetworkClient.send_world_action() did not send exactly one packet.")
		return

	var packet: Dictionary = client.sent_packets[0]
	if String(packet.get("type", "")) != ProtocolConstants.MESSAGE_WORLD_ACTION_REQUEST:
		failures.append("NetworkClient.send_world_action() used an unexpected message type.")

	var payload: Dictionary = packet.get("payload", {})
	if String(payload.get("action", "")) != GameIds.ACTION_OPEN:
		failures.append("NetworkClient.send_world_action() did not preserve the world action.")
	if String(payload.get("target_id", "")) != "level01_door_01":
		failures.append("NetworkClient.send_world_action() did not preserve the target id.")
	if String(payload.get("level_id", "")) != "beginner_01":
		failures.append("NetworkClient.send_world_action() did not inject the current level id.")
	if not String(packet.get("request_id", "")).begins_with("%s-" % ProtocolConstants.REQUEST_PREFIX_ACTION):
		failures.append("NetworkClient.send_world_action() did not use the action request-id prefix.")


func _test_send_world_event_normalization(failures: Array[String]) -> void:
	var client := _new_client()
	client.send_world_event({
		"kind": GameIds.EVENT_BUTTON_STATE,
		"sync_id": "level01_button_01",
		"pressed": true,
		"node_name": "Button",
		"peer_id": 12,
		"level_has_key": true,
		"level_has_door": false,
		"key_count": 3,
	})

	if client.sent_packets.size() != 1:
		failures.append("NetworkClient.send_world_event() did not send exactly one packet.")
		return

	var packet: Dictionary = client.sent_packets[0]
	var payload: Dictionary = packet.get("payload", {})
	if String(payload.get("action", "")) != GameIds.ACTION_BUTTON_STATE:
		failures.append("NetworkClient.send_world_event() did not normalize event kind into the expected action.")
	if String(payload.get("target_id", "")) != "level01_button_01":
		failures.append("NetworkClient.send_world_event() did not normalize sync_id into target_id.")
	if not bool(payload.get("pressed", false)):
		failures.append("NetworkClient.send_world_event() dropped event payload fields that should remain on the wire.")
	if payload.has("kind") or payload.has("sync_id") or payload.has("node_name") or payload.has("peer_id"):
		failures.append("NetworkClient.send_world_event() left legacy-only metadata in the outgoing action payload.")
	if payload.has("level_has_key") or payload.has("level_has_door") or payload.has("key_count"):
		failures.append("NetworkClient.send_world_event() leaked client-only HUD fields into the outgoing action payload.")


func _test_send_world_event_legacy_target_inference(failures: Array[String]) -> void:
	var client := _new_client()
	client.send_world_event({
		"kind": GameIds.EVENT_BUTTON_STATE,
		"level_index": 0,
		"pressed": true,
	})

	if client.inferred_calls != 1:
		failures.append("NetworkClient.send_world_event() did not attempt legacy target inference when target_id was absent.")
		return

	if String(client.inferred_action) != GameIds.EVENT_BUTTON_STATE:
		failures.append("NetworkClient.send_world_event() passed an unexpected action into legacy target inference.")

	var packet: Dictionary = client.sent_packets[0]
	var payload: Dictionary = packet.get("payload", {})
	if String(payload.get("target_id", "")) != "legacy_button_01":
		failures.append("NetworkClient.send_world_event() did not use the inferred legacy target id.")


func _test_handle_world_event_emits_duplicate(failures: Array[String]) -> void:
	var client := _new_client()
	var recorder := EventRecorder.new()
	client.world_event_received.connect(Callable(recorder, "record"))

	var payload := {
		"event": {
			"kind": GameIds.EVENT_DOOR_OPENED,
			"state": {
				"opened": true,
			},
		},
	}
	client._handle_world_event(payload)

	if recorder.events.size() != 1:
		failures.append("NetworkClient._handle_world_event() did not emit the world event signal.")
		return

	payload["event"]["state"]["opened"] = false
	var recorded_event: Dictionary = recorder.events[0]
	var recorded_state: Dictionary = recorded_event.get("state", {})
	if not bool(recorded_state.get("opened", false)):
		failures.append("NetworkClient._handle_world_event() did not deep-duplicate the emitted event payload.")
