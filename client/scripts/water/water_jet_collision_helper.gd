extends RefCounted
class_name WaterJetCollisionHelper


static func collision_query_excludes(owner: Area2D) -> Array[RID]:
	var excludes: Array[RID] = [owner.get_rid()]
	var parent_object := owner.get_parent() as CollisionObject2D
	if parent_object != null:
		excludes.append(parent_object.get_rid())
	return excludes


static func collect_affected_bodies(
	owner: Area2D,
	collision_shape: CollisionShape2D,
	affected_collision_mask: int,
	use_overlap_query: bool
) -> Array[Node]:
	var bodies: Array[Node] = []
	var seen: Dictionary = {}
	if owner.monitoring:
		for raw_body in owner.get_overlapping_bodies():
			if raw_body is Node:
				_add_body_once(bodies, seen, raw_body as Node)

	if not use_overlap_query:
		return bodies

	if collision_shape == null or collision_shape.shape == null:
		return bodies

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = collision_shape.shape
	query.transform = collision_shape.global_transform
	query.collision_mask = affected_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = collision_query_excludes(owner)

	var hits: Array[Dictionary] = owner.get_world_2d().direct_space_state.intersect_shape(query, 24)
	for hit in hits:
		var collider = hit.get("collider")
		if collider is Node:
			_add_body_once(bodies, seen, collider as Node)

	return bodies


static func player_impact_length(owner: Area2D, affected_bodies: Array[Node], ray_length: float, stream_half_width: float) -> float:
	var best_length := -1.0
	for body in affected_bodies:
		if not body.is_in_group("player"):
			continue

		var local_position := owner.to_local((body as Node2D).global_position) if body is Node2D else Vector2.ZERO
		var radius := body_impact_radius(body)
		if local_position.y + radius < 0.0 or local_position.y - radius > ray_length:
			continue
		if absf(local_position.x) > stream_half_width + radius:
			continue

		var candidate := clampf(local_position.y - radius, 0.0, ray_length)
		best_length = candidate if best_length < 0.0 else minf(best_length, candidate)

	return best_length


static func ray_impact_length(owner: Area2D, ray_length: float, impact_collision_mask: int, impact_ray_start_offset: float) -> float:
	var start := owner.to_global(Vector2(0.0, maxf(impact_ray_start_offset, 0.0)))
	var end := owner.to_global(Vector2(0.0, ray_length))
	var query := PhysicsRayQueryParameters2D.create(start, end)
	query.collision_mask = impact_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = collision_query_excludes(owner)

	var hit: Dictionary = owner.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1.0

	var hit_position = hit.get("position")
	if typeof(hit_position) != TYPE_VECTOR2:
		return -1.0

	var local_hit := owner.to_local(hit_position)
	return clampf(local_hit.y, 0.0, ray_length)


static func body_impact_radius(body: Node) -> float:
	var collision := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or collision.shape == null:
		return 10.0

	if collision.shape is CircleShape2D:
		return (collision.shape as CircleShape2D).radius * maxf(absf(collision.global_scale.x), absf(collision.global_scale.y))
	if collision.shape is RectangleShape2D:
		var rect := collision.shape as RectangleShape2D
		return rect.size.length() * 0.5 * maxf(absf(collision.global_scale.x), absf(collision.global_scale.y))

	return 10.0


static func _add_body_once(bodies: Array[Node], seen: Dictionary, body: Node) -> void:
	var instance_id := body.get_instance_id()
	if seen.has(instance_id):
		return

	seen[instance_id] = true
	bodies.append(body)
