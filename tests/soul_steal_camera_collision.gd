extends SceneTree

func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	_add_solid(stage, Vector3(0.0, 2.25, 0.0), Vector3(6.0, 0.2, 7.0))
	_add_solid(stage, Vector3(0.0, 1.5, 1.8), Vector3(6.0, 3.0, 0.2))
	var cinematic := preload("res://soul_steal_cinematic.gd").new()
	stage.add_child(cinematic)
	cinematic.camera_probe.radius = 0.28
	await physics_frame
	var focus := Vector3(0.0, 1.1, 0.0)
	var through_wall: Vector3 = cinematic._resolve_camera_collision(focus, Vector3(0.0, 1.1, 4.0))
	assert(through_wall.z < 1.5)
	var through_ceiling: Vector3 = cinematic._resolve_camera_collision(focus, Vector3(0.0, 4.0, 0.0))
	assert(through_ceiling.y < 2.0)
	var around_corner: Vector3 = cinematic._resolve_camera_collision(focus, Vector3(0.0, 4.0, 4.0))
	assert(around_corner.y < 2.0 and around_corner.z < 1.5)
	print("SOUL_STEAL_CAMERA_COLLISION_OK")
	quit()


func _add_solid(parent: Node3D, position: Vector3, size: Vector3) -> void:
	var solid := StaticBody3D.new()
	parent.add_child(solid)
	solid.position = position
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	solid.add_child(collider)
