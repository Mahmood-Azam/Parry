extends SkeletonModifier3D
## Arms follow a two-handed guard; the sword remains fixed inside the right fist.

var controller: Node
var guard_active := false
var arm_indices: Dictionary = {}
var channel_blend := 0.0
var stance_time := 0.0
var release_remaining := 0.0
var release_blend := 0.0
const PARRY_DURATION := 0.32
var parry_elapsed := PARRY_DURATION
var parry_side := -1.0
var parry_strength := 1.0

func play_parry(perfect: bool = false) -> void:
	# Alternate the actual hand/arm deflection, not the sword's socket transform.
	parry_side = -parry_side
	parry_elapsed = 0.0
	parry_strength = 1.15 if perfect else 1.0
	influence = maxf(influence, 0.75)

func parry_motion() -> float:
	return smoothstep(0.0, 0.055, parry_elapsed) * (1.0 - smoothstep(0.065, PARRY_DURATION, parry_elapsed)) * parry_strength


func play_release() -> void:
	release_remaining = 0.26
	release_blend = 1.0


func _ready() -> void:
	influence = 0.0
	var skeleton := get_skeleton()
	for side in ["Right", "Left"]:
		arm_indices[side] = [
			skeleton.find_bone("mixamorig_" + side + "Arm"),
			skeleton.find_bone("mixamorig_" + side + "ForeArm"),
			skeleton.find_bone("mixamorig_" + side + "Hand"),
		]


func _process(delta: float) -> void:
	parry_elapsed = minf(parry_elapsed + delta, PARRY_DURATION)
	release_remaining = maxf(release_remaining - delta, 0.0)
	if release_remaining <= 0.0:
		release_blend = move_toward(release_blend, 0.0, delta / 0.18)
	var channeling: bool = is_instance_valid(controller) and (controller.is_fire_channeling or controller.ultimate_charging)
	channel_blend = move_toward(channel_blend, 1.0 if channeling else 0.0, delta / 0.20)
	stance_time += delta
	var allowed: bool = (guard_active or channeling or release_remaining > 0.0 or parry_elapsed < PARRY_DURATION) and is_instance_valid(controller)
	if allowed:
		allowed = controller.is_alive and not controller.attacking and not controller.is_dashing and controller.hit_stun_remaining <= 0.0
		if not allowed:
			parry_elapsed = PARRY_DURATION
	influence = move_toward(influence, 1.0 if allowed else 0.0, delta / 0.18)


func _process_modification() -> void:
	if influence <= 0.001:
		return
	var skeleton := get_skeleton()
	var chest_index := skeleton.find_bone("mixamorig_Spine2")
	if chest_index < 0:
		return
	var chest := skeleton.get_bone_global_pose(chest_index).origin
	# This model faces +Z. Raise the hilt below the right shoulder and angle
	# the blade across the torso, with the left palm bracing its upper flat.
	var blade_axis := Vector3(0.84, 0.54, 0.0).normalized()
	var deflection := parry_motion()
	blade_axis = blade_axis.rotated(Vector3.FORWARD, parry_side * deflection * 0.30).rotated(Vector3.RIGHT, -deflection * 0.12)
	var charged_axis := Vector3(-0.16, 0.96, 0.22).normalized()
	var released_axis := Vector3(0.72, -0.25, 0.65).normalized()
	if controller.is_using_ultimate:
		if controller.ultimate_kind == "focused":
			charged_axis = Vector3(-0.08, 0.2, 0.98).normalized()
			released_axis = Vector3(0.02, 0.02, 1.0).normalized()
		else:
			released_axis = Vector3(0.25, -0.88, 0.4).normalized()
	blade_axis = blade_axis.lerp(charged_axis, channel_blend).normalized()
	var release_progress := smoothstep(0.0, 1.0, 1.0 - release_remaining / 0.26)
	if release_blend > 0.0:
		var cast_axis := charged_axis.lerp(released_axis, release_progress).normalized()
		blade_axis = blade_axis.lerp(cast_axis, release_blend).normalized()
	var palm_normal := Vector3.FORWARD
	palm_normal = (palm_normal - blade_axis * palm_normal.dot(blade_axis)).normalized()
	var fingers := palm_normal.cross(blade_axis).normalized()
	var right_basis := Basis(blade_axis, fingers, blade_axis.cross(fingers)).orthonormalized()
	var right_wrist := chest + Vector3(-0.24, -0.22, 0.38)
	right_wrist += Vector3(parry_side * 0.075, 0.025, 0.055) * deflection
	right_wrist = right_wrist.lerp(chest + Vector3(-0.08, -0.08 + sin(stance_time * 3.5) * 0.008, 0.24), channel_blend)
	if release_blend > 0.0:
		right_wrist = right_wrist.lerp(chest + Vector3(-0.08, -0.08, 0.24).lerp(Vector3(-0.04, -0.22, 0.40), release_progress), release_blend)
	_solve_arm(skeleton, "Right", right_wrist, right_basis, chest + Vector3(-0.5, -0.4, 0.1))
	var palm_offset: Vector3 = controller.crystal_sword_palm_position + controller.crystal_sword_grip_offset
	var grip := right_wrist + right_basis * palm_offset
	var left_fingers := -blade_axis
	var left_normal := palm_normal
	var left_basis := Basis(left_fingers.cross(left_normal), left_fingers, left_normal).orthonormalized()
	var support_palm := grip + blade_axis * 0.53 + Vector3(0.0, 0.0, -0.035)
	var channel_left_basis := Basis(-blade_axis, fingers, (-blade_axis).cross(fingers)).orthonormalized()
	left_basis = Basis(left_basis.get_rotation_quaternion().slerp(channel_left_basis.get_rotation_quaternion(), channel_blend))
	support_palm = support_palm.lerp(grip - blade_axis * 0.12, channel_blend)
	var left_wrist := support_palm - left_basis * Vector3(0.0, 0.10, 0.025)
	if release_blend > 0.0:
		left_wrist = left_wrist.lerp(chest + Vector3(0.22, -0.18, 0.18), release_progress * release_blend)
	_solve_arm(skeleton, "Left", left_wrist, left_basis, chest + Vector3(0.48, -0.28, 0.12))


func _solve_arm(skeleton: Skeleton3D, side: String, target: Vector3, hand_basis: Basis, pole: Vector3) -> void:
	var indices: Array = arm_indices.get(side, [])
	if indices.size() != 3 or indices.has(-1):
		return
	var upper: int = indices[0]
	var lower: int = indices[1]
	var hand: int = indices[2]
	var upper_pose := skeleton.get_bone_global_pose(upper)
	var elbow := skeleton.get_bone_global_pose(lower).origin
	var wrist := skeleton.get_bone_global_pose(hand).origin
	var root := upper_pose.origin
	var upper_length := root.distance_to(elbow)
	var lower_length := elbow.distance_to(wrist)
	if minf(upper_length, lower_length) < 0.001:
		return
	var direction := (target - root).normalized()
	var distance := clampf(root.distance_to(target), absf(upper_length - lower_length) + 0.001, upper_length + lower_length - 0.001)
	var along := (upper_length * upper_length - lower_length * lower_length + distance * distance) / (2.0 * distance)
	var bend := pole - root
	bend = (bend - direction * bend.dot(direction)).normalized()
	if bend.length_squared() < 0.001:
		return
	var elbow_target := root + direction * along + bend * sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	upper_pose.basis = Basis(Quaternion((elbow - root).normalized(), (elbow_target - root).normalized())) * upper_pose.basis
	skeleton.set_bone_global_pose(upper, upper_pose)
	var lower_pose := skeleton.get_bone_global_pose(lower)
	var hand_pose := skeleton.get_bone_global_pose(hand)
	var clamped_target := root + direction * distance
	lower_pose.basis = Basis(Quaternion((hand_pose.origin - lower_pose.origin).normalized(), (clamped_target - lower_pose.origin).normalized())) * lower_pose.basis
	skeleton.set_bone_global_pose(lower, lower_pose)
	hand_pose = skeleton.get_bone_global_pose(hand)
	hand_pose.basis = hand_basis
	skeleton.set_bone_global_pose(hand, hand_pose)
