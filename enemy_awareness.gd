extends RefCounted
## A spawn-anchored territory, with hysteresis so enemies cannot chase forever.
var home := Vector3.ZERO
var returning := false
var engaged := false
var aggro_range := 10.0
var leash_range := 16.0

func can_engage(actor: Node3D, candidate: Node3D) -> bool:
	if returning:
		if actor.global_position.distance_to(home) > 0.8:
			return false
		returning = false
		engaged = false
	if not is_instance_valid(candidate) or candidate.get("is_alive") == false:
		engaged = false
		return false
	if absf(candidate.global_position.y - actor.global_position.y) > 2.5:
		returning = true
		engaged = false
		return false
	if actor.global_position.distance_to(home) > leash_range or candidate.global_position.distance_to(home) > leash_range:
		returning = true
		engaged = false
		return false
	if engaged:
		return true
	if actor.global_position.distance_to(candidate.global_position) > aggro_range:
		return false
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP, candidate.global_position + Vector3.UP, 1)
	if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return false
	engaged = true
	return true

func return_direction(actor: Node3D) -> Vector3:
	var offset := home - actor.global_position
	offset.y = 0.0
	return offset.normalized() if offset.length() > 0.6 else Vector3.ZERO

func pursuit_direction(actor: CharacterBody3D, desired: Vector3) -> Vector3:
	# Soft separation keeps a group from occupying the same melee slot.
	var separation := Vector3.ZERO
	for other in actor.get_tree().get_nodes_in_group("enemy"):
		if other == actor or not is_instance_valid(other):
			continue
		var offset: Vector3 = actor.global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > 0.01 and distance < 1.2:
			separation += offset / distance * (1.0 - distance / 1.2) * 0.65
	var direction := (desired + separation).normalized()
	# Follow a nearby wall rather than pushing straight into it indefinitely.
	if actor.is_on_wall():
		var normal := actor.get_wall_normal()
		if direction.dot(normal) < -0.1:
			var tangent := direction.slide(normal)
			if tangent.length_squared() > 0.01:
				direction = tangent.normalized()
	return direction
