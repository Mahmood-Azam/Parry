extends Node3D
## Reversible damage layer. The source campus scene and all intact nodes survive.
signal restored
var campus: Node3D
var destroyed := false
var mesh_states: Array = []
var collision_states: Array = []
var batch_states: Array = []
var detail_states: Array = []
var rubble: MultiMeshInstance3D
var fragments: Array = []
var collapse_time := 0.0
var progress := 0.0
var reversal: Tween
const SAFE_HEIGHT := 6.35

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_capture_intact()
	_build_rubble()

func _in_damage_zone(bounds: AABB) -> bool:
	var center := bounds.get_center()
	return center.x > 38.5 and center.x < 60.0 and center.z > -105.0 and center.z < -34.0 and bounds.end.y > 7.2

func _capture_intact() -> void:
	# Also capture separately parented graffiti/trim in the same footprint so
	# decorative planes cannot remain suspended above demolished walls.
	for mesh: MeshInstance3D in campus.find_children("*", "MeshInstance3D", true, false):
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		if not _in_damage_zone(bounds):
			continue
		# Preserve the ground floor, first-floor relic room, and their ceilings.
		if bounds.position.y < SAFE_HEIGHT:
			# Long decorative fins/windows get shortened, not left floating.
			if bounds.size.y > 7 and mesh.find_children("*", "CollisionShape3D", true, false).is_empty():
				mesh_states.append([weakref(mesh), mesh.visible, mesh.transform, true])
			continue
		mesh_states.append([weakref(mesh), mesh.visible, mesh.transform, false])
		for shape: CollisionShape3D in mesh.find_children("*", "CollisionShape3D", true, false):
			collision_states.append([weakref(shape), shape.disabled])
	for label: Label3D in campus.find_children("*", "Label3D", true, false):
		var p := label.global_position
		if p.y > SAFE_HEIGHT and _in_damage_zone(AABB(p, Vector3.ONE)):
			detail_states.append([weakref(label), label.visible])
	# The runtime map batches repeated boxes. Snapshot affected instance
	# transforms too, otherwise an optimized copy could survive demolition.
	for batch: MultiMeshInstance3D in campus.find_children("*", "MultiMeshInstance3D", true, false):
		if not batch.name.begins_with("StaticArchitectureBatch"):
			continue
		for i in batch.multimesh.instance_count:
			var local := batch.multimesh.get_instance_transform(i)
			var bounds: AABB = (batch.global_transform * local) * batch.multimesh.mesh.get_aabb()
			if _in_damage_zone(bounds) and bounds.position.y >= SAFE_HEIGHT:
				batch_states.append([weakref(batch), i, local])

func _build_rubble() -> void:
	rubble = MultiMeshInstance3D.new()
	rubble.name = "CollapsedBuildingFragments"
	rubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rubble.visibility_range_end = 100.0
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	mesh.material = material
	multi.mesh = mesh
	multi.instance_count = 48
	rubble.multimesh = multi
	add_child(rubble)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9047
	for i in multi.instance_count:
		var start := Vector3(rng.randf_range(40.0, 51.0), rng.randf_range(8.0, 17.0), rng.randf_range(-96.0, -43.0))
		var end := Vector3(rng.randf_range(36.2, 39.0), 0.2, start.z + rng.randf_range(-2, 2))
		# Keep the entrance and the route toward it clear of visible rubble.
		if absf(end.z + 74.55) < 2.0:
			end.z -= 4.0
		var size := Vector3(rng.randf_range(0.35, 1.2), rng.randf_range(0.15, 0.45), rng.randf_range(0.3, 0.9))
		var spin := Vector3(rng.randf_range(-2, 2), rng.randf_range(-3, 3), rng.randf_range(-2, 2))
		fragments.append([start, end, size, spin])
		multi.set_instance_color(i, Color(0.55, 0.53, 0.48).lerp(Color(0.86, 0.82, 0.72), rng.randf()))
	_set_fragment_progress(0.0)
	rubble.hide()

func destroy(animated: bool = true) -> void:
	if destroyed:
		if not animated:
			collapse_time = 2.4
			_set_fragment_progress(1.0)
		_hide_details()
		return
	if is_instance_valid(reversal):
		reversal.kill()
	destroyed = true
	_hide_details()
	collapse_time = 0.0 if animated else 2.4
	for state in mesh_states:
		var mesh: MeshInstance3D = state[0].get_ref()
		if not is_instance_valid(mesh):
			continue
		if state[3]:
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			var keep := maxf(SAFE_HEIGHT - bounds.position.y, 0.1)
			mesh.scale.y *= keep / maxf(bounds.size.y, 0.1)
			var shortened: AABB = mesh.global_transform * mesh.get_aabb()
			mesh.global_position.y += bounds.position.y - shortened.position.y
		else:
			mesh.hide()
	for state in collision_states:
		var shape: CollisionShape3D = state[0].get_ref()
		if is_instance_valid(shape):
			shape.set_deferred("disabled", true)
	for state in batch_states:
		var batch: MultiMeshInstance3D = state[0].get_ref()
		if is_instance_valid(batch):
			var zero: Transform3D = state[2]
			zero.basis = Basis.IDENTITY.scaled(Vector3.ZERO)
			batch.multimesh.set_instance_transform(state[1], zero)
	rubble.show()
	_set_fragment_progress(0.0 if animated else 1.0)

func _process(delta: float) -> void:
	if destroyed and collapse_time < 2.4 and not is_instance_valid(reversal):
		collapse_time = minf(collapse_time + delta, 2.4)
		_set_fragment_progress(collapse_time / 2.4)

func _set_fragment_progress(value: float) -> void:
	progress = value
	for i in fragments.size():
		var item: Array = fragments[i]
		var position: Vector3 = item[0].lerp(item[1], value) + Vector3.UP * sin(value * PI) * 2.2
		var basis := Basis.from_euler(item[3] * value).scaled(item[2])
		rubble.multimesh.set_instance_transform(i, global_transform.affine_inverse() * Transform3D(basis, position))

func restore_intact() -> void:
	if is_instance_valid(reversal):
		reversal.kill()
	reversal = null
	destroyed = false
	for state in mesh_states:
		var mesh: MeshInstance3D = state[0].get_ref()
		if is_instance_valid(mesh):
			mesh.transform = state[2]
			mesh.visible = state[1]
	for state in collision_states:
		var shape: CollisionShape3D = state[0].get_ref()
		if is_instance_valid(shape):
			shape.set_deferred("disabled", state[1])
	for state in batch_states:
		var batch: MultiMeshInstance3D = state[0].get_ref()
		if is_instance_valid(batch):
			batch.multimesh.set_instance_transform(state[1], state[2])
	for state in detail_states:
		var label: Node3D = state[0].get_ref()
		if is_instance_valid(label):
			label.visible = state[1]
	if is_instance_valid(rubble):
		rubble.hide()
	progress = 0.0

func _hide_details() -> void:
	for state in detail_states:
		var label: Node3D = state[0].get_ref()
		if is_instance_valid(label):
			label.hide()

func reverse_destruction(seconds: float = 2.5) -> void:
	if not destroyed:
		restored.emit()
		return
	if is_instance_valid(reversal):
		reversal.kill()
	reversal = create_tween()
	reversal.tween_method(_set_fragment_progress, progress, 0.0, maxf(seconds, 0.01)).set_trans(Tween.TRANS_SINE)
	reversal.tween_callback(func():
		reversal = null
		restore_intact()
		restored.emit()
	)
