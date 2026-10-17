extends SkeletonModifier3D
## Two-joint reach with a palm/feather-tip offset; authored flight/idle stays underneath.
var upper := -1
var lower := -1
var hand := -1
var tip_offset := Vector3.ZERO
var target_world := Vector3.ZERO
var pole_world := Vector3.ZERO
var hand_basis_world := Basis.IDENTITY

func _process_modification() -> void:
	if influence <= 0.001 or mini(upper, mini(lower, hand)) < 0:
		return
	var rig := get_skeleton()
	var desired_basis := (rig.global_basis.inverse() * hand_basis_world).orthonormalized()
	var target := rig.to_local(target_world) - desired_basis * tip_offset
	var pole := rig.to_local(pole_world)
	var root_pose := rig.get_bone_global_pose(upper)
	var elbow := rig.get_bone_global_pose(lower).origin
	var wrist := rig.get_bone_global_pose(hand).origin
	var root := root_pose.origin
	var a := root.distance_to(elbow)
	var b := elbow.distance_to(wrist)
	if minf(a, b) < 0.0001:
		return
	var direction := (target - root).normalized()
	var distance := clampf(root.distance_to(target), absf(a - b) + 0.0001, a + b - 0.0001)
	var along := (a * a - b * b + distance * distance) / (2.0 * distance)
	var bend := pole - root
	bend = (bend - direction * bend.dot(direction)).normalized()
	if bend.length_squared() < 0.001:
		return
	var elbow_target := root + direction * along + bend * sqrt(maxf(a * a - along * along, 0.0))
	root_pose.basis = Basis(Quaternion((elbow - root).normalized(), (elbow_target - root).normalized())) * root_pose.basis
	rig.set_bone_global_pose(upper, root_pose)
	var lower_pose := rig.get_bone_global_pose(lower)
	var hand_pose := rig.get_bone_global_pose(hand)
	var clamped_target := root + direction * distance
	lower_pose.basis = Basis(Quaternion((hand_pose.origin - lower_pose.origin).normalized(), (clamped_target - lower_pose.origin).normalized())) * lower_pose.basis
	rig.set_bone_global_pose(lower, lower_pose)
	hand_pose = rig.get_bone_global_pose(hand)
	hand_pose.basis = desired_basis.scaled(hand_pose.basis.get_scale())
	rig.set_bone_global_pose(hand, hand_pose)
