extends RefCounted
class_name PacketCodec


static func vector_to_packet(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}


static func packet_to_vector(raw_value, fallback: Vector2) -> Vector2:
	if typeof(raw_value) == TYPE_DICTIONARY:
		var data: Dictionary = raw_value
		return Vector2(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)))

	if typeof(raw_value) == TYPE_ARRAY and raw_value.size() >= 2:
		return Vector2(float(raw_value[0]), float(raw_value[1]))

	return fallback


static func color_to_packet(value: Color) -> Dictionary:
	return {
		"r": value.r,
		"g": value.g,
		"b": value.b,
		"a": value.a,
	}


static func packet_to_color(raw_value, fallback: Color) -> Color:
	if typeof(raw_value) != TYPE_DICTIONARY:
		return fallback

	var data: Dictionary = raw_value
	return Color(
		float(data.get("r", fallback.r)),
		float(data.get("g", fallback.g)),
		float(data.get("b", fallback.b)),
		float(data.get("a", fallback.a))
	)
