extends RefCounted
class_name PlayerCollisionHelper


static func global_rect_from_body(body: Node2D) -> Rect2:
	var collision_shape := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	return global_rect(collision_shape)


static func global_rect(collision_shape: CollisionShape2D) -> Rect2:
	if collision_shape == null or collision_shape.shape == null:
		return Rect2()

	if collision_shape.shape is CircleShape2D:
		var circle_shape: CircleShape2D = collision_shape.shape
		var scale := collision_shape.global_scale
		var radius := circle_shape.radius * maxf(absf(scale.x), absf(scale.y))
		var center := collision_shape.global_position
		return Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))

	if collision_shape.shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = collision_shape.shape
		var half_size := rect_shape.size * 0.5
		return Rect2(
			collision_shape.global_position - half_size,
			rect_shape.size
		)

	return Rect2()
