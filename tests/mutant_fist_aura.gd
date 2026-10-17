extends SceneTree

func _initialize() -> void:
	call_deferred("_check")


func _check() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var boss: Node3D = load("res://assets/enemies/Mutant/mutant_boss.tscn").instantiate()
	stage.add_child(boss)
	var aura := boss.get_node("BossAura")
	assert(aura.fist_only and not aura.final_boss)
	assert(aura.fists.size() == 2)
	assert(aura.get_node_or_null("LivingPlasmaRing") == null)
	assert(aura.get_node_or_null("RisingPlasmaVeil") == null)
	for side in ["Left", "Right"]:
		var fist := aura.get_node("%sFistFlame" % side)
		assert(fist.get_node_or_null("LivingFistFlame") != null)
		assert(fist.get_node_or_null("%sFistFlameTongues" % side) != null)
		assert((fist.get_node("FistFlameLight") as OmniLight3D).light_color.b > 0.9)
	var left: Dictionary = aura.fists[0]
	var anchor := left["anchor"] as Node3D
	var before := anchor.global_position
	var rig := aura.fist_rig as Skeleton3D
	var wrist: int = left["wrist"]
	rig.set_bone_pose_position(wrist, rig.get_bone_pose_position(wrist) + Vector3(0.2, 0.0, 0.0))
	aura._update_fist_positions()
	assert(anchor.global_position.distance_to(before) > 0.1)
	aura.attack_splash()
	aura.power_surge()
	aura.fade_out()
	assert(not (left["cinders"] as GPUParticles3D).emitting)
	print("MUTANT_FIST_AURA_OK")
	quit()
