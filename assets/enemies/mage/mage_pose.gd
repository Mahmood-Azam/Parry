extends SkeletonModifier3D
## The supplied asset contains static ActionPose/TPose clips only. Animate its
## own rig in place, keeping the feet and model root grounded during casting.
var controller: Node3D
var rest_poses: Array[Transform3D] = []
var arms: Dictionary = {}
var chest := -1
var elapsed := 0.0
var cast_blend := 0.0
var recoil := 0.0

func _ready() -> void:
	var rig := get_skeleton()
	for index in rig.get_bone_count():
		rest_poses.append(rig.get_bone_pose(index))
		var bone := rig.get_bone_name(index)
		if "Spine02" in bone:
			chest = index
	for side in ["L", "R"]:
		var indices: Array[int] = [-1, -1, -1]
		for index in rig.get_bone_count():
			var bone := rig.get_bone_name(index)
			if ("CC_Base_" + side + "_Upperarm_") in bone:
				indices[0] = index
			elif ("CC_Base_" + side + "_Forearm_") in bone:
				indices[1] = index
			elif ("CC_Base_" + side + "_Hand_") in bone:
				indices[2] = index
		arms[side] = indices

func _process(delta: float) -> void:
	elapsed += delta
	if not is_instance_valid(controller):
		return
	cast_blend = move_toward(cast_blend, 1.0 if controller.is_attacking else 0.0, delta * 5.0)
	recoil = move_toward(recoil, 1.0 if controller.stun_remaining > 0.0 else 0.0, delta * 8.0)

func _process_modification() -> void:
	var rig := get_skeleton()
	if rest_poses.size() != rig.get_bone_count() or not is_instance_valid(controller):
		return
	# Restore the source pose before each procedural pass; never compound IK.
	for index in rest_poses.size():
		rig.set_bone_pose(index, rest_poses[index])
	if chest >= 0:
		var pose := rest_poses[chest]
		pose.basis = pose.basis * Basis(Vector3.RIGHT, sin(elapsed * 2.6) * 0.014 + recoil * 0.1)
		rig.set_bone_pose(chest, pose)
	for side in ["L", "R"]:
		var sign_x := 1.0 if side == "L" else -1.0
		var idle := Vector3(sign_x * 0.31, 1.22, 0.18)
		var cast := Vector3(sign_x * 0.23, 1.35, 0.52)
		var wrist := idle.lerp(cast, cast_blend)
		wrist.y += sin(elapsed * 3.0 + sign_x) * 0.014
		wrist = wrist.lerp(Vector3(sign_x * 0.39, 1.65, 0.08), recoil)
		var point := rig.to_local(controller.to_global(wrist))
		var pole := rig.to_local(controller.to_global(Vector3(sign_x * 0.62, 1.24, 0.08)))
		_solve_arm(rig, arms[side], point, pole)

func _solve_arm(rig: Skeleton3D, indices: Array, target: Vector3, pole: Vector3) -> void:
	if indices.has(-1):
		return
	var upper: int = indices[0]
	var lower: int = indices[1]
	var hand: int = indices[2]
	var upper_pose := rig.get_bone_global_pose(upper)
	var elbow := rig.get_bone_global_pose(lower).origin
	var wrist := rig.get_bone_global_pose(hand).origin
	var origin := upper_pose.origin
	var length_a := origin.distance_to(elbow)
	var length_b := elbow.distance_to(wrist)
	if minf(length_a, length_b) < 0.001:
		return
	var direction := (target - origin).normalized()
	var distance := clampf(origin.distance_to(target), absf(length_a - length_b) + 0.01, length_a + length_b - 0.01)
	var along := (length_a * length_a - length_b * length_b + distance * distance) / (2.0 * distance)
	var bend := pole - origin
	bend = (bend - direction * bend.dot(direction)).normalized()
	if bend.length_squared() < 0.001:
		return
	var elbow_target := origin + direction * along + bend * sqrt(maxf(length_a * length_a - along * along, 0.0))
	upper_pose.basis = Basis(Quaternion((elbow - origin).normalized(), (elbow_target - origin).normalized())) * upper_pose.basis
	rig.set_bone_global_pose(upper, upper_pose)
	var lower_pose := rig.get_bone_global_pose(lower)
	wrist = rig.get_bone_global_pose(hand).origin
	var clamped := origin + direction * distance
	lower_pose.basis = Basis(Quaternion((wrist - lower_pose.origin).normalized(), (clamped - lower_pose.origin).normalized())) * lower_pose.basis
	rig.set_bone_global_pose(lower, lower_pose)
