extends RefCounted
class_name Protocol

const SERVER_PROTOCOL_VERSION := 1

const FIELD_TYPE := "type"
const FIELD_REQUEST_ID := "request_id"
const FIELD_PAYLOAD := "payload"


static func decode_packet(packet: PackedByteArray) -> Dictionary:
	var text := packet.get_string_from_utf8()
	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		return {
			"ok": false,
			"code": "bad_json",
			"message": "Packet is not valid JSON."
		}

	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"code": "bad_packet",
			"message": "Packet root must be a JSON object."
		}

	var packet_dict: Dictionary = data
	var message_type := String(packet_dict.get(FIELD_TYPE, "")).strip_edges()
	if message_type.is_empty():
		return {
			"ok": false,
			"code": "missing_type",
			"message": "Packet is missing a message type."
		}

	var payload = packet_dict.get(FIELD_PAYLOAD, {})
	if typeof(payload) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"code": "bad_payload",
			"message": "Packet payload must be a JSON object."
		}

	return {
		"ok": true,
		"type": message_type,
		"request_id": packet_dict.get(FIELD_REQUEST_ID, null),
		"payload": payload
	}


static func encode_message(message_type: String, payload: Dictionary = {}, request_id = null) -> PackedByteArray:
	var packet := {
		FIELD_TYPE: message_type,
		FIELD_PAYLOAD: payload,
	}

	if request_id != null:
		packet[FIELD_REQUEST_ID] = request_id

	return JSON.stringify(packet).to_utf8_buffer()


static func encode_error(code: String, message: String, request_id = null, details: Dictionary = {}) -> PackedByteArray:
	var payload := {
		"code": code,
		"message": message,
	}

	if not details.is_empty():
		payload["details"] = details

	return encode_message("error", payload, request_id)
