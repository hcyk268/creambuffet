extends SceneTree

const Protocol = preload("res://scripts/network/protocol.gd")


func _init() -> void:
	var failures: Array[String] = []

	var encoded: PackedByteArray = Protocol.encode_message("hello", {"player_name": "Codex"}, "req-1")
	var decoded: Dictionary = Protocol.decode_packet(encoded)
	if not bool(decoded.get("ok", false)):
		failures.append("Protocol.decode_packet() rejected a packet produced by Protocol.encode_message().")
	else:
		if int(decoded.get("v", -1)) != Protocol.SERVER_PROTOCOL_VERSION:
			failures.append("Protocol.decode_packet() returned an unexpected protocol version.")
		if String(decoded.get("type", "")) != "hello":
			failures.append("Protocol.decode_packet() returned an unexpected message type.")
		var payload: Dictionary = decoded.get("payload", {})
		if String(payload.get("player_name", "")) != "Codex":
			failures.append("Protocol.decode_packet() returned an unexpected payload.")
		if String(decoded.get("request_id", "")) != "req-1":
			failures.append("Protocol.decode_packet() lost the request id.")

	var error_packet: PackedByteArray = Protocol.encode_error("bad_packet", "Bad packet.", "req-2", {"field": "type"})
	var decoded_error: Dictionary = Protocol.decode_packet(error_packet)
	if not bool(decoded_error.get("ok", false)):
		failures.append("Protocol.decode_packet() rejected a packet produced by Protocol.encode_error().")
	else:
		if String(decoded_error.get("type", "")) != "error":
			failures.append("Protocol.encode_error() did not preserve the error message type.")
		var error_payload: Dictionary = decoded_error.get("payload", {})
		if String(error_payload.get("code", "")) != "bad_packet":
			failures.append("Protocol.encode_error() did not preserve the error code.")
		if typeof(error_payload.get("details", null)) != TYPE_DICTIONARY:
			failures.append("Protocol.encode_error() did not preserve details.")

	var legacy_packet: PackedByteArray = JSON.stringify({
		"type": "world_event_request",
		"payload": {
			"action": "button_state",
		},
	}).to_utf8_buffer()
	var decoded_legacy: Dictionary = Protocol.decode_packet(legacy_packet)
	if not bool(decoded_legacy.get("ok", false)):
		failures.append("Protocol.decode_packet() no longer accepts the legacy world_event_request packet shape.")

	var missing_version_packet: PackedByteArray = JSON.stringify({
		"type": "hello",
		"payload": {},
	}).to_utf8_buffer()
	var missing_version: Dictionary = Protocol.decode_packet(missing_version_packet)
	if bool(missing_version.get("ok", false)) or String(missing_version.get("code", "")) != "missing_protocol_version":
		failures.append("Protocol.decode_packet() did not reject a non-legacy packet without a protocol version.")

	if failures.is_empty():
		print("Protocol tests passed.")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)
