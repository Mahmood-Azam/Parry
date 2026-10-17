extends SkeletonModifier3D
## Seat imported locomotion poses on the body collider's floor plane.
## Only the skeleton's vertical pose changes; movement and jumps stay physical.

var controller: Node
var vertical_offset := 0.0
var hips := -1
var toes: Array[int] = []


func _ready() -> void:
	var skeleton := get_skeleton()
	hips = skeleton.find_bone("mixamorig_Hips")
	for side in ["Left", "Right"]:
		var index := skeleton.find_bone("mixamorig_" + side + "ToeBase")
		if index >= 0:
			toes.append(index)


func _process_modification() -> void:
	if hips < 0 or toes.is_empty() or not is_instance_valid(controller) or not controller.is_alive:
		return
	if not controller.is_on_floor():
		vertical_offset = 0.0
		return
	var skeleton := get_skeleton()
	var target := 0.0
	if not controller.attacking and not controller.is_dashing and controller.hit_stun_remaining <= 0.0:
		var lowest := INF
		for index in toes:
			lowest = minf(lowest, skeleton.to_global(skeleton.get_bone_global_pose(index).origin).y)
		target = clampf(controller.global_position.y + 0.055 - lowest, -0.32, 0.18)
	vertical_offset = move_toward(vertical_offset, target, get_process_delta_time() * 2.5)
	var pose := skeleton.get_bone_global_pose(hips)
	pose.origin += skeleton.global_basis.inverse() * (Vector3.UP * vertical_offset)
	skeleton.set_bone_global_pose(hips, pose)
