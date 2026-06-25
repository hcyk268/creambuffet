extends RefCounted
class_name GeometryService

const GameCatalog = preload("res://scripts/catalog/game_catalog.gd")
const PacketCodec = preload("res://scripts/network/packet_codec.gd")


static func packet_vector(raw_value) -> Dictionary:
	var value := PacketCodec.packet_to_vector(raw_value, Vector2.ZERO)
	return PacketCodec.vector_to_packet(value)


static func packet_vec(x: float, y: float) -> Dictionary:
	return {
		"x": x,
		"y": y,
	}


static func positions_match(first: Dictionary, second: Dictionary, epsilon: float) -> bool:
	if first.is_empty() or second.is_empty():
		return false

	var dx := float(first.get("x", 0.0)) - float(second.get("x", 0.0))
	var dy := float(first.get("y", 0.0)) - float(second.get("y", 0.0))
	return (dx * dx) + (dy * dy) <= epsilon * epsilon


static func player_shape_overlaps_target_shape(match_state, peer_id: int, target_id: String, target_shape_field: String) -> bool:
	var player_shape := player_shape(match_state, peer_id)
	if player_shape.is_empty():
		return false

	var target_shape := shape_for_object(match_state, target_id, target_shape_field)
	if target_shape.is_empty():
		return false

	return shape_overlap(player_shape, target_shape)


static func object_shape_overlaps_target_shape(match_state, source_id: String, source_shape_field: String, target_id: String, target_shape_field: String) -> bool:
	var source_shape := shape_for_object(match_state, source_id, source_shape_field)
	if source_shape.is_empty():
		return false

	var target_shape := shape_for_object(match_state, target_id, target_shape_field)
	if target_shape.is_empty():
		return false

	return shape_overlap(source_shape, target_shape)


static func player_shape(match_state, peer_id: int) -> Dictionary:
	var player_state: Dictionary = match_state.get_player_state(peer_id)
	if player_state.is_empty():
		return {}

	var raw_position: Variant = player_state.get("position", {})
	if typeof(raw_position) != TYPE_DICTIONARY:
		return {}

	return player_shape_for_position(raw_position)


static func player_bounding_rect(match_state, peer_id: int) -> Rect2:
	var player_state: Dictionary = match_state.get_player_state(peer_id)
	if player_state.is_empty():
		return Rect2()
	return player_bounding_rect_for_position(player_state.get("position", {}))


static func did_player_cross_trigger_since_last_update(match_state, peer_id: int, target_id: String) -> bool:
	if not match_state.has_player(peer_id):
		return false

	var player_state: Dictionary = match_state.get_player_state(peer_id)
	if player_state.is_empty():
		return false

	var current_rect := player_bounding_rect_for_position(player_state.get("position", {}))
	if current_rect.size == Vector2.ZERO:
		return false

	var previous_rect := player_bounding_rect_for_position(player_state.get("previous_position", {}))
	if previous_rect.size == Vector2.ZERO:
		return false

	var trigger_shape := shape_for_object(match_state, target_id, "trigger")
	if trigger_shape.is_empty():
		return false

	var trigger_rect := shape_rect(trigger_shape).grow(float(trigger_shape.get("margin", 0.0)))
	return previous_rect.merge(current_rect).intersects(trigger_rect)


static func player_bounding_rect_for_position(raw_position: Variant) -> Rect2:
	var shape := player_shape_for_position(raw_position)
	if shape.is_empty():
		return Rect2()

	var shape_type := String(shape.get("type", ""))
	if shape_type == "rectangle":
		return shape_rect(shape)
	if shape_type == "circle":
		var center: Dictionary = shape.get("center", {})
		var radius := float(shape.get("radius", 0.0))
		return Rect2(
			Vector2(float(center.get("x", 0.0)) - radius, float(center.get("y", 0.0)) - radius),
			Vector2(radius * 2.0, radius * 2.0)
		)
	return Rect2()


static func player_shape_for_position(raw_position: Variant) -> Dictionary:
	if typeof(raw_position) != TYPE_DICTIONARY:
		return {}

	var template := GameCatalog.get_player_template()
	var shape: Dictionary = template.get("shape", {})
	if shape.is_empty():
		return {}

	var base_position: Dictionary = Dictionary(raw_position).duplicate(true)
	var offset: Dictionary = Dictionary(shape.get("offset", {})).duplicate(true)
	var shape_type := String(shape.get("type", ""))
	var result := {
		"type": shape_type,
		"center": packet_vec(
			float(base_position.get("x", 0.0)) + float(offset.get("x", 0.0)),
			float(base_position.get("y", 0.0)) + float(offset.get("y", 0.0))
		),
	}
	if shape_type == "rectangle":
		result["size"] = Dictionary(shape.get("size", {})).duplicate(true)
	else:
		result["radius"] = float(shape.get("radius", 0.0))
	return result


static func shape_for_object(match_state, target_id: String, shape_field: String) -> Dictionary:
	var object_data: Dictionary = match_state.get_object_data(target_id)
	if object_data.is_empty():
		return {}

	var shape_data: Variant = object_data.get(shape_field, {})
	if typeof(shape_data) != TYPE_DICTIONARY:
		return {}

	var transform: Dictionary = object_data.get("transform", {})
	var base_position: Dictionary = transform.get("position", {})
	if shape_field == "body":
		var state: Dictionary = object_data.get("state", {})
		var state_position: Variant = state.get("position", null)
		if typeof(state_position) == TYPE_DICTIONARY:
			base_position = state_position

	if typeof(base_position) != TYPE_DICTIONARY:
		base_position = {}

	var offset: Dictionary = Dictionary(shape_data.get("offset", {})).duplicate(true)
	return {
		"type": String(shape_data.get("shape", "")),
		"center": packet_vec(
			float(base_position.get("x", 0.0)) + float(offset.get("x", 0.0)),
			float(base_position.get("y", 0.0)) + float(offset.get("y", 0.0))
		),
		"size": Dictionary(shape_data.get("size", {})).duplicate(true),
		"radius": float(shape_data.get("radius", 0.0)),
		"margin": float(shape_data.get("margin", 0.0)),
	}


static func shape_rect_for_object(match_state, target_id: String, shape_field: String, override_position: Dictionary = {}) -> Rect2:
	var shape := shape_for_object(match_state, target_id, shape_field)
	if shape.is_empty():
		return Rect2()
	if typeof(override_position) == TYPE_DICTIONARY and not override_position.is_empty():
		var object_data: Dictionary = match_state.get_object_data(target_id)
		var shape_data: Dictionary = object_data.get(shape_field, {})
		var offset: Dictionary = Dictionary(shape_data.get("offset", {})).duplicate(true)
		shape["center"] = packet_vec(
			float(override_position.get("x", 0.0)) + float(offset.get("x", 0.0)),
			float(override_position.get("y", 0.0)) + float(offset.get("y", 0.0))
		)
	return shape_rect(shape)


static func shape_overlap(first: Dictionary, second: Dictionary) -> bool:
	var first_type := String(first.get("type", ""))
	var second_type := String(second.get("type", ""))
	if first_type == "circle" and second_type == "rectangle":
		return circle_intersects_rect(first, second)
	if first_type == "rectangle" and second_type == "rectangle":
		return rectangle_intersects_rect(first, second)
	if first_type == "rectangle" and second_type == "circle":
		return circle_intersects_rect(second, first)
	if first_type == "circle" and second_type == "circle":
		return circle_intersects_circle(first, second)
	return false


static func circle_intersects_rect(circle_shape: Dictionary, rect_shape: Dictionary) -> bool:
	var center: Dictionary = circle_shape.get("center", {})
	var radius := float(circle_shape.get("radius", 0.0))
	var rect := shape_rect(rect_shape)
	var margin := float(rect_shape.get("margin", 0.0))
	rect = rect.grow(margin)
	var circle_position := Vector2(float(center.get("x", 0.0)), float(center.get("y", 0.0)))
	var closest_x := clampf(circle_position.x, rect.position.x, rect.end.x)
	var closest_y := clampf(circle_position.y, rect.position.y, rect.end.y)
	return circle_position.distance_squared_to(Vector2(closest_x, closest_y)) <= radius * radius


static func rectangle_intersects_rect(first: Dictionary, second: Dictionary) -> bool:
	var first_rect := shape_rect(first).grow(float(first.get("margin", 0.0)))
	var second_rect := shape_rect(second).grow(float(second.get("margin", 0.0)))
	return first_rect.intersects(second_rect)


static func circle_intersects_circle(first: Dictionary, second: Dictionary) -> bool:
	var first_center: Dictionary = first.get("center", {})
	var second_center: Dictionary = second.get("center", {})
	var first_position := Vector2(float(first_center.get("x", 0.0)), float(first_center.get("y", 0.0)))
	var second_position := Vector2(float(second_center.get("x", 0.0)), float(second_center.get("y", 0.0)))
	var max_distance := float(first.get("radius", 0.0)) + float(second.get("radius", 0.0))
	return first_position.distance_squared_to(second_position) <= max_distance * max_distance


static func shape_rect(shape_data: Dictionary) -> Rect2:
	var size: Dictionary = shape_data.get("size", {})
	if typeof(size) != TYPE_DICTIONARY:
		return Rect2()
	var center: Dictionary = shape_data.get("center", {})
	var width := float(size.get("x", 0.0))
	var height := float(size.get("y", 0.0))
	return Rect2(
		Vector2(float(center.get("x", 0.0)) - (width * 0.5), float(center.get("y", 0.0)) - (height * 0.5)),
		Vector2(width, height)
	)
