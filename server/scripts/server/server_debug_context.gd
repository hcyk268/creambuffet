extends RefCounted
class_name ServerDebugContext

const Room = preload("res://scripts/lobby/room.gd")


func info(message: String) -> void:
	print("[server] %s" % message)


func warn(message: String) -> void:
	printerr("[server][warn] %s" % message)


func request_label(request_id) -> String:
	return "-" if request_id == null else str(request_id)


func room_label(room: Room) -> String:
	if room == null:
		return "room=- map=- status=- level=- players=0"

	return "room=%s map=%s status=%s level=%s(%d) players=%d" % [
		room.room_id,
		room.map_id,
		room.status,
		room.current_level_id,
		room.current_level_index,
		room.player_ids().size()
	]


func payload_label(payload: Dictionary) -> String:
	var parts: Array[String] = []
	if payload.has("level_id"):
		parts.append("payload_level=%s" % String(payload.get("level_id", "")))
	elif payload.has("level_index"):
		parts.append("payload_level_index=%d" % int(payload.get("level_index", -1)))

	var sync_id := String(payload.get("sync_id", "")).strip_edges()
	if not sync_id.is_empty():
		parts.append("sync_id=%s" % sync_id)

	var node_name := String(payload.get("node_name", "")).strip_edges()
	if not node_name.is_empty():
		parts.append("node_name=%s" % node_name)

	var position_raw: Variant = payload.get("position", null)
	if typeof(position_raw) == TYPE_DICTIONARY:
		var position: Dictionary = position_raw
		parts.append("pos=(%.1f,%.1f)" % [float(position.get("x", 0.0)), float(position.get("y", 0.0))])

	var velocity_raw: Variant = payload.get("velocity", null)
	if typeof(velocity_raw) == TYPE_DICTIONARY:
		var velocity: Dictionary = velocity_raw
		parts.append("vel=(%.1f,%.1f)" % [float(velocity.get("x", 0.0)), float(velocity.get("y", 0.0))])

	var push_intents_raw: Variant = payload.get("push_intents", null)
	if typeof(push_intents_raw) == TYPE_ARRAY:
		parts.append("push_intents=%d" % Array(push_intents_raw).size())

	var pushable_states_raw: Variant = payload.get("pushable_states", null)
	if typeof(pushable_states_raw) == TYPE_ARRAY:
		parts.append("pushable_states=%d" % Array(pushable_states_raw).size())

	var result := ""
	for part in parts:
		if not result.is_empty():
			result += " "
		result += part
	return result
