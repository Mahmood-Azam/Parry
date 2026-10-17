extends RefCounted
## A synchronized, first-line greeting. The owl wing and empty palm share one target.
const REACH := preload("res://assets/npc/owl/greeting_limb_ik.gd")
var owl: Node3D
var player: Node3D
var human: Skeleton3D
var bird: Skeleton3D
var hand_reach: SkeletonModifier3D
var wing_reach: SkeletonModifier3D
var guard: SkeletonModifier3D
var guard_was_active := true
var player_basis := Basis.IDENTITY
var line_duration := 3.0
var blend := 0.0
var contact := Vector3.ZERO
var wing_tip := -1

func begin(companion: Node3D, actor: Node3D, seconds: float) -> bool:
	owl = companion
	player = actor
	var character := player.get_node_or_null("WarriorKnight") as Node3D
	if character == null:
		return false
	human = character.get_node_or_null("Skeleton3D") as Skeleton3D
	bird = owl.model.find_child("Skeleton3D", true, false) as Skeleton3D
	if human == null or bird == null:
		return false
	line_duration = maxf(seconds, 0.5)
	player_basis = character.global_basis.orthonormalized()
	hand_reach = REACH.new()
	hand_reach.name = "OwlHandshakeHand"
	hand_reach.upper = human.find_bone("mixamorig_LeftArm")
	hand_reach.lower = human.find_bone("mixamorig_LeftForeArm")
	hand_reach.hand = human.find_bone("mixamorig_LeftHand")
	hand_reach.tip_offset = Vector3(0, 0.10, 0.025)
	human.add_child(hand_reach)
	# The left wing is on the near side in this greeting composition.
	wing_reach = REACH.new()
	wing_reach.name = "OwlHandshakeWing"
	wing_reach.upper = _bone("Bip001_L_UpperArm")
	wing_reach.lower = _bone("Bip001_L_Forearm")
	wing_reach.hand = _bone("Bip001_L_Hand")
	wing_tip = _bone("Bip001_L_Finger0")
	if mini(hand_reach.upper, mini(hand_reach.lower, hand_reach.hand)) < 0 or mini(wing_reach.upper, mini(wing_reach.lower, wing_reach.hand)) < 0 or wing_tip < 0:
		end()
		return false
	wing_reach.tip_offset = bird.get_bone_global_pose(wing_reach.hand).affine_inverse() * bird.get_bone_global_pose(wing_tip).origin
	bird.add_child(wing_reach)
	guard = human.get_node_or_null("SwordGuardPose") as SkeletonModifier3D
	if guard != null:
		guard_was_active = guard.active
		guard.active = false # Do not let the two-handed block compete with the greeting.
	update(0)
	return true

func _bone(prefix: String) -> int:
	for index in bird.get_bone_count():
		if bird.get_bone_name(index).begins_with(prefix):
			return index
	return -1

func update(seconds: float) -> void:
	if not is_instance_valid(hand_reach) or not is_instance_valid(wing_reach):
		return
	var t := clampf(seconds / line_duration, 0, 1) * 3.0
	blend = smoothstep(0.10, 0.65, t) * (1.0 - smoothstep(2.1, 2.75, t))
	var approach := smoothstep(0, 0.55, t) * (1.0 - smoothstep(2.2, 3.0, t))
	var normal_position: Vector3 = player.global_position + owl.hold_offset + Vector3.UP * (owl.ORBIT_HEIGHT + sin(Time.get_ticks_msec() * 0.003) * 0.08)
	var greeting_position := player.global_position + player_basis * Vector3(0.88, 1.43, 0.64)
	owl.global_position = normal_position.lerp(greeting_position, approach)
	var forward := -Vector3(0.88, 0, 0.64)
	forward = player_basis * forward
	var yaw := atan2(forward.x, forward.z)
	owl.model.rotation.y = lerp_angle(-owl.orbit_start - PI * 0.5, yaw, approach)
	var shake_phase := clampf((t - 0.8) / 1.1, 0, 1)
	var shake := sin(shake_phase * TAU * 2.0) * sin(shake_phase * PI) * 0.025
	contact = player.global_position + player_basis * Vector3(0.50, 1.38 + shake, 0.40)
	var fingers := player_basis.z.normalized()
	var normal := player_basis.x.normalized()
	hand_reach.hand_basis_world = Basis(fingers.cross(normal), fingers, normal).orthonormalized()
	hand_reach.target_world = contact
	hand_reach.pole_world = player.global_position + player_basis * Vector3(0.68, 1.10, 0.10)
	hand_reach.influence = blend
	var wing_root := bird.to_global(bird.get_bone_global_pose(wing_reach.upper).origin)
	var wing_axis := wing_root.direction_to(contact)
	var wing_up := (Vector3.UP - wing_axis * Vector3.UP.dot(wing_axis)).normalized()
	wing_reach.hand_basis_world = Basis(wing_axis, wing_up, wing_axis.cross(wing_up)).orthonormalized()
	wing_reach.target_world = contact
	wing_reach.pole_world = owl.global_position + player_basis * Vector3(-0.20, 0.20, -0.15)
	wing_reach.influence = blend

func end() -> void:
	for modifier in [hand_reach, wing_reach]:
		if is_instance_valid(modifier):
			modifier.influence = 0
			modifier.queue_free()
	if is_instance_valid(guard):
		guard.active = guard_was_active
	hand_reach = null
	wing_reach = null
