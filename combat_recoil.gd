extends SkeletonModifier3D
## Additive torso recoil: feet, collision and the sword's hand mount stay intact.
var bone := -1
var elapsed := 1.0
var strength := 0.0
var axis := Vector3.RIGHT

func _ready() -> void:
	var rig := get_skeleton()
	for i in rig.get_bone_count():
		var label := rig.get_bone_name(i).to_lower()
		if "spine" in label or "chest" in label:
			bone = i
			if "spine2" in label or "chest" in label:
				break
	# The original low-tier skeleton uses anonymous Blender bone names. This
	# is its chest fork (neck + both arms), verified from the imported hierarchy.
	if bone < 0:
		bone = rig.find_bone("Bone.003_46_51")

func kick(direction: Vector3, power: float) -> void:
	elapsed = 0.0
	strength = power
	var local := get_skeleton().global_basis.inverse() * direction
	axis = Vector3(local.z, 0.0, -local.x).normalized()
	if axis.length_squared() < 0.1:
		axis = Vector3.RIGHT

func _process(delta: float) -> void:
	elapsed += delta

func _process_modification() -> void:
	if bone < 0 or elapsed >= 0.24:
		return
	var envelope := sin(minf(elapsed / 0.035, 1.0) * PI * 0.5) * pow(1.0 - elapsed / 0.24, 2.0)
	var rig := get_skeleton()
	var pose := rig.get_bone_global_pose(bone)
	pose.basis = Basis(Quaternion(axis, strength * envelope)) * pose.basis
	rig.set_bone_global_pose(bone, pose)
