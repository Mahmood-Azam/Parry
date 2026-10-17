extends "res://assets/enemies/skeleton/skeleton_enemy.gd"
## The supplied Dokkeabi has a rig and one general motion clip, but no separate
## locomotion or strike clips. These clips animate its body and club arm.

const BODY_TEXTURE := preload("res://assets/enemies/gremlin/textures/Dokkeabi_V2_low_M_Dokkeaibi_BaseColor.1001.png")
const BODY_NORMAL := preload("res://assets/enemies/gremlin/textures/T_Dokkeaibi_Normal.png")
const EYES_TEXTURE := preload("res://assets/enemies/gremlin/textures/T_Yeux_BaseColor.png")

func _ready() -> void:
	add_to_group("gremlin")
	_install_animations()
	super._ready()
	_apply_textures()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_dead and not is_attacking and stun_remaining <= 0.0:
		animation_player.speed_scale = 1.5 if current_animation == &"Lesha_walk" else 1.0

func _install_animations() -> void:
	var library := AnimationLibrary.new()
	var idle := Animation.new()
	idle.length = 1.6
	idle.loop_mode = Animation.LOOP_LINEAR
	_add_position(idle, "GremlinModel", [0.0, 0.8, 1.6], [Vector3(0, 0.04, 0), Vector3(0, 0.055, 0), Vector3(0, 0.04, 0)])
	_add_rotation(idle, "GremlinModel", [0.0, 0.8, 1.6], [Vector3.ZERO, Vector3(0, 0, 0.025), Vector3.ZERO])
	library.add_animation("Lesha_idle", idle)

	var walk := Animation.new()
	walk.length = 0.8
	walk.loop_mode = Animation.LOOP_LINEAR
	_add_position(walk, "GremlinModel", [0.0, 0.2, 0.4, 0.6, 0.8], [Vector3(0, 0.04, 0), Vector3(0, 0.085, 0), Vector3(0, 0.04, 0), Vector3(0, 0.085, 0), Vector3(0, 0.04, 0)])
	_add_rotation(walk, "GremlinModel", [0.0, 0.2, 0.4, 0.6, 0.8], [Vector3(0, 0, -0.06), Vector3(0, 0, 0), Vector3(0, 0, 0.06), Vector3(0, 0, 0), Vector3(0, 0, -0.06)])
	_add_rotation(walk, "GremlinModel/Dokkeabi/Skeleton3D:GB_Bras.L", [0.0, 0.4, 0.8], [Vector3(-0.27, 0, 0), Vector3(0.27, 0, 0), Vector3(-0.27, 0, 0)])
	_add_rotation(walk, "GremlinModel/Dokkeabi/Skeleton3D:GB_Bras.R", [0.0, 0.4, 0.8], [Vector3(0.27, 0, 0), Vector3(-0.27, 0, 0), Vector3(0.27, 0, 0)])
	library.add_animation("Lesha_walk", walk)

	var attack := Animation.new()
	attack.length = 0.9
	attack.loop_mode = Animation.LOOP_NONE
	_add_position(attack, "GremlinModel", [0.0, 0.3, 0.51, 0.9], [Vector3(0, 0.04, 0), Vector3(0, 0.03, -0.045), Vector3(0, 0.025, 0.075), Vector3(0, 0.04, 0)])
	_add_rotation(attack, "GremlinModel", [0.0, 0.3, 0.51, 0.9], [Vector3.ZERO, Vector3(-0.13, 0, -0.08), Vector3(0.19, 0, 0.11), Vector3.ZERO])
	_add_rotation(attack, "GremlinModel/Dokkeabi/Skeleton3D:GB_Bras.L", [0.0, 0.3, 0.51, 0.9], [Vector3.ZERO, Vector3(-0.95, 0.1, -0.28), Vector3(0.85, 0, 0.18), Vector3.ZERO])
	_add_rotation(attack, "GremlinModel/Dokkeabi/Skeleton3D:pB_Bras.L", [0.0, 0.3, 0.51, 0.9], [Vector3.ZERO, Vector3(-0.75, 0, 0), Vector3(0.65, 0, 0), Vector3.ZERO])
	library.add_animation("Lesha_attack_1", attack)
	animation_player.add_animation_library("", library)

func _add_position(animation: Animation, path: String, times: Array[float], positions: Array[Vector3]) -> void:
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath(path))
	for index in times.size():
		animation.track_insert_key(track, times[index], positions[index])

func _add_rotation(animation: Animation, path: String, times: Array[float], angles: Array[Vector3]) -> void:
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track, NodePath(path))
	for index in times.size():
		animation.track_insert_key(track, times[index], Quaternion.from_euler(angles[index]))

func _apply_textures() -> void:
	var body := get_node("SkeletonModel/GremlinModel/Dokkeabi/Skeleton3D/SM_Dokkeabi") as MeshInstance3D
	var body_material := (body.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	body_material.albedo_texture = BODY_TEXTURE
	body_material.normal_enabled = true
	body_material.normal_texture = BODY_NORMAL
	body.set_surface_override_material(0, body_material)
	var eyes_material := (body.mesh.surface_get_material(1) as StandardMaterial3D).duplicate() as StandardMaterial3D
	eyes_material.albedo_texture = EYES_TEXTURE
	body.set_surface_override_material(1, eyes_material)
