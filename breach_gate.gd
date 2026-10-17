extends Node3D
## Project Eclipse survives the meteor and cannot be destroyed by combat.
## The future time-reversal ending removes it explicitly, not through damage.
var is_invulnerable := true
var collision_body: StaticBody3D
var collision_enabled := true
static var fitted_shape: ConcavePolygonShape3D

func setup_collision() -> void:
	if is_instance_valid(collision_body):
		return
	# Bake the normalized model's transforms into one static surface, preserving
	# its stairs, round base and aperture without enclosing empty rooftop space.
	if fitted_shape == null:
		var faces := PackedVector3Array()
		var visual := get_child(0) as Node3D
		for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
			var local_faces := _collision_faces(mesh.mesh)
			var mesh_to_gate := global_transform.affine_inverse() * mesh.global_transform
			for index in local_faces.size():
				local_faces[index] = mesh_to_gate * local_faces[index]
			faces.append_array(local_faces)
		fitted_shape = ConcavePolygonShape3D.new()
		fitted_shape.set_faces(faces)
		# Thin portal surfaces must block approaches from either side.
		fitted_shape.backface_collision = true
	collision_body = StaticBody3D.new()
	collision_body.name = "PortalCollision"
	collision_body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.name = "FittedPortalShape"
	collider.shape = fitted_shape
	collision_body.add_child(collider)
	add_child(collision_body)
	visibility_changed.connect(_sync_collision)
	_sync_collision()

func _collision_faces(mesh: Mesh) -> PackedVector3Array:
	# The render model has ~1.5 million triangles. Reuse its imported LODs for
	# collision instead of putting every tiny cable/detail into the physics BVH.
	var faces := PackedVector3Array()
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if mesh is ArrayMesh:
			var surface_data: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
			var lods: Array = surface_data.get("lods", [])
			var original_data: PackedByteArray = surface_data.get("index_data", PackedByteArray())
			var stride := 2 if original_data.size() == int(surface_data.get("index_count", 0)) * 2 else 4
			var best_count := 0
			var smallest := PackedByteArray()
			var chosen := PackedByteArray()
			for lod: Dictionary in lods:
				var candidate: PackedByteArray = lod.index_data
				if smallest.is_empty() or candidate.size() < smallest.size():
					smallest = candidate
				if candidate.size() <= 3072 * stride and candidate.size() > best_count:
					chosen = candidate
					best_count = candidate.size()
			if best_count == 0 and not lods.is_empty():
				chosen = smallest
			if not chosen.is_empty():
				if stride == 4:
					indices = chosen.to_int32_array()
				else:
					indices.resize(chosen.size() / 2)
					for index in indices.size():
						indices[index] = chosen.decode_u16(index * 2)
		if indices.is_empty():
			faces.append_array(vertices)
		else:
			var start := faces.size()
			faces.resize(start + indices.size())
			for index in indices.size():
				faces[start + index] = vertices[indices[index]]
	return faces

func set_collision_enabled(enabled: bool) -> void:
	collision_enabled = enabled
	_sync_collision()

func _sync_collision() -> void:
	if is_instance_valid(collision_body):
		collision_body.collision_layer = 1 if collision_enabled and is_visible_in_tree() else 0

func take_damage(_amount: float, _attacker: Node = null, _attack_type: String = "environment", _attack_data: Dictionary = {}) -> bool:
	return false
