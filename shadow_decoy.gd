extends Node3D

## Temporary target created at the beginning of every Shadow dash.
const FX := preload("res://combat_fx.gd")
const CAST_SOUND := preload("res://assets/audio/soul_steal/soul_cast.wav")
const TRAVEL_SOUND := preload("res://assets/audio/soul_steal/soul_travel.wav")
const HIT_SOUND := preload("res://assets/audio/soul_steal/soul_hit.wav")
const SOUL_RIM_SHADER := preload("res://assets/vfx/soul_shadow_rim.gdshader")
signal soul_target_started(target: Node3D)
signal soul_struck(target: Node3D, accepted: bool)
signal soul_finished()
@export var lifetime: float = 2.5

var age: float = 0.0
var source_character: Node3D
var visual: Node3D
var material: StandardMaterial3D
var soul_animation: AnimationPlayer
var silhouette_meshes: Array[MeshInstance3D] = []
var light: OmniLight3D
var soul_active := false
var soul_caster: Node3D
var soul_targets: Array[WeakRef] = []
var soul_target_index := 0
var soul_damage := 22.0
var soul_healing := 10.0
var soul_pause := 0.0
var soul_finish_delay := -1.0
var soul_travel_started := false
var soul_flash := 0.0
var soul_trail: GPUParticles3D
var cast_sound: AudioStreamPlayer3D
var travel_sound: AudioStreamPlayer3D

func _ready() -> void:
	add_to_group("shadow_decoy")
	_setup_visual()
	_setup_soul_trail()
	_setup_soul_audio()

func _process(delta: float) -> void:
	if soul_active:
		_process_soul_steal(delta)
		return
	age += delta
	if age >= lifetime:
		queue_free()
		return
	if visual != null:
		visual.position.y = 0.0
	if material != null:
		var fade := clampf((lifetime - age) / 0.45, 0.0, 1.0)
		material.albedo_color.a = 0.42 * fade
		if light != null:
			light.light_energy = 0.8 * fade

func get_decoy_priority() -> float:
	return age


func begin_soul_steal(caster: Node3D, targets: Array[Node3D], damage: float, healing: float) -> bool:
	if soul_active or targets.is_empty() or not is_instance_valid(caster):
		return false
	soul_active = true
	soul_caster = caster
	soul_damage = damage
	soul_healing = healing
	soul_targets.clear()
	for target in targets:
		soul_targets.append(weakref(target))
	soul_target_index = 0
	soul_pause = 0.0
	soul_finish_delay = -1.0
	soul_travel_started = false
	soul_flash = 0.0
	age = 0.0
	soul_trail.emitting = true
	if material != null:
		material.albedo_color = Color(0.025, 0.006, 0.07, 1.0)
		material.emission = Color(0.18, 0.025, 0.42)
		material.emission_energy_multiplier = 2.6
	var rim_material := ShaderMaterial.new()
	rim_material.shader = SOUL_RIM_SHADER
	for mesh in silhouette_meshes:
		mesh.material_overlay = rim_material
	_play_soul_animation("Run", 2.0)
	if light != null:
		light.light_energy = 2.2
	cast_sound.play()
	FX.burst(get_tree().current_scene, global_position + Vector3.UP, Color(0.45, 0.12, 0.85), 22, 0.65)
	return true


func _process_soul_steal(delta: float) -> void:
	soul_flash = move_toward(soul_flash, 0.0, delta * 5.0)
	if material != null:
		material.emission_energy_multiplier = 2.6 + soul_flash * 2.0
	if not is_instance_valid(soul_caster) or soul_caster.get("is_alive") == false:
		soul_finished.emit()
		queue_free()
		return
	if soul_finish_delay >= 0.0:
		soul_finish_delay -= delta
		if soul_finish_delay <= 0.0:
			queue_free()
		return
	if soul_pause > 0.0:
		soul_pause -= delta
		return
	while soul_target_index < soul_targets.size():
		var candidate := soul_targets[soul_target_index].get_ref() as Node3D
		if is_instance_valid(candidate) and candidate.is_inside_tree() and candidate.is_in_group("enemy"):
			break
		soul_target_index += 1
		soul_travel_started = false
	if soul_target_index >= soul_targets.size():
		soul_trail.emitting = false
		soul_finish_delay = 0.22
		soul_finished.emit()
		return
	var target := soul_targets[soul_target_index].get_ref() as Node3D
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var strike_radius := 0.72
	var collider := target.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider != null and collider.shape is CapsuleShape3D:
		strike_radius = maxf(strike_radius, (collider.shape as CapsuleShape3D).radius * 1.05)
	var goal := target.global_position - to_target.normalized() * strike_radius
	goal.y = target.global_position.y
	if not soul_travel_started:
		_play_soul_animation("Run", 2.0)
		travel_sound.pitch_scale = 0.92 + float(soul_target_index % 3) * 0.09
		travel_sound.play()
		soul_travel_started = true
		soul_target_started.emit(target)
	if to_target.length_squared() > 0.001:
		visual.rotation.y = atan2(to_target.x, to_target.z)
	global_position = global_position.move_toward(goal, 32.0 * delta)
	if global_position.distance_to(goal) <= 0.18:
		_strike_soul_target(target)
		soul_target_index += 1
		soul_travel_started = false
		soul_pause = 0.17


func _strike_soul_target(target: Node3D) -> void:
	var accepted: bool = target.call("take_damage", soul_damage, soul_caster)
	soul_struck.emit(target, accepted)
	if not accepted:
		return
	soul_flash = 1.0
	_play_soul_animation("Attack", 2.4)
	if soul_caster.has_method("heal"):
		soul_caster.call("heal", soul_healing)
	FX.burst(get_tree().current_scene, global_position + Vector3.UP * 1.0, Color(0.65, 0.16, 1.0), 32, 0.72)
	FX.burst(get_tree().current_scene, soul_caster.global_position + Vector3.UP, Color(0.36, 0.92, 0.69), 10, 0.4)
	var hit := AudioStreamPlayer3D.new()
	hit.stream = HIT_SOUND
	hit.volume_db = -0.5
	hit.unit_size = 5.0
	get_tree().current_scene.add_child(hit)
	hit.global_position = global_position + Vector3.UP
	hit.finished.connect(hit.queue_free)
	hit.play()


func _play_soul_animation(clip: String, speed: float) -> void:
	if soul_animation == null or not soul_animation.has_animation(clip):
		return
	if soul_animation.current_animation == clip and soul_animation.is_playing():
		return
	soul_animation.speed_scale = speed
	soul_animation.play(clip, 0.06)
	if clip == "Attack":
		soul_animation.seek(minf(soul_animation.get_animation(clip).length * 0.12, 0.35), true)


func _setup_soul_audio() -> void:
	cast_sound = AudioStreamPlayer3D.new()
	cast_sound.name = "SoulCastSound"
	cast_sound.stream = CAST_SOUND
	cast_sound.unit_size = 5.0
	cast_sound.volume_db = -1.0
	add_child(cast_sound)
	travel_sound = AudioStreamPlayer3D.new()
	travel_sound.name = "SoulTravelSound"
	travel_sound.stream = TRAVEL_SOUND
	travel_sound.unit_size = 5.0
	travel_sound.volume_db = -4.0
	add_child(travel_sound)


func _setup_soul_trail() -> void:
	soul_trail = GPUParticles3D.new()
	soul_trail.name = "SoulStealTrail"
	soul_trail.position.y = 1.0
	soul_trail.amount = 72
	soul_trail.lifetime = 0.42
	soul_trail.local_coords = false
	soul_trail.emitting = false
	soul_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 180.0
	motion.initial_velocity_min = 0.2
	motion.initial_velocity_max = 1.8
	motion.gravity = Vector3(0.0, 0.3, 0.0)
	motion.scale_min = 0.35
	motion.scale_max = 1.0
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.60, 0.17, 1.0, 0.0))
	gradient.add_point(0.17, Color(0.60, 0.17, 1.0, 0.9))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.12, 0.82, 0.72, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	soul_trail.process_material = motion
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = Color(0.55, 0.2, 0.9)
	material.emission_energy_multiplier = 2.5
	var spark := SphereMesh.new()
	spark.radius = 0.034
	spark.height = 0.068
	spark.material = material
	soul_trail.draw_pass_1 = spark
	add_child(soul_trail)

func take_damage(_amount: float, _attacker: Node = null, _attack_type: String = "melee", _attack_data: Dictionary = {}) -> bool:
	# The decoy absorbs enemy attacks without passing damage to the player.
	age = minf(age + 0.08, lifetime)
	return true

func _setup_visual() -> void:
	visual = Node3D.new()
	visual.name = "ShadowVisual"
	add_child(visual)

	if source_character != null:
		# Duplicate the actual player model and freeze it in the pose captured at
		# dash start. This keeps the decoy humanoid instead of spawning the old orb.
		var player_silhouette := source_character.duplicate() as Node3D
		if player_silhouette != null:
			player_silhouette.name = "PlayerSilhouette"
			player_silhouette.position = Vector3.ZERO
			player_silhouette.rotation = Vector3.ZERO
			player_silhouette.scale = source_character.scale
			visual.add_child(player_silhouette)
			material = StandardMaterial3D.new()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color(0.08, 0.02, 0.16, 0.42)
			material.emission_enabled = true
			material.emission = Color(0.16, 0.02, 0.38, 1.0)
			material.emission_energy_multiplier = 1.8
			for mesh in player_silhouette.find_children("*", "MeshInstance3D", true, false):
				(mesh as MeshInstance3D).material_override = material
				silhouette_meshes.append(mesh as MeshInstance3D)
			for animation in player_silhouette.find_children("*", "AnimationPlayer", true, false):
				(animation as AnimationPlayer).stop()
				if soul_animation == null:
					soul_animation = animation as AnimationPlayer
			light = OmniLight3D.new()
			light.light_color = Color(0.25, 0.04, 0.65)
			light.light_energy = 0.8
			light.omni_range = 1.8
			visual.add_child(light)
			return

	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.48
	sphere.height = 1.4
	orb.mesh = sphere
	material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.16, 0.04, 0.28, 0.34)
	material.emission_enabled = true
	material.emission = Color(0.24, 0.03, 0.55, 1.0)
	material.emission_energy_multiplier = 3.5
	orb.material_override = material
	visual.add_child(orb)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.52
	torus.outer_radius = 0.58
	ring.mesh = torus
	ring.position.y = -0.55
	ring.material_override = material
	visual.add_child(ring)

	light = OmniLight3D.new()
	light.light_color = Color(0.35, 0.08, 0.8)
	light.light_energy = 1.4
	light.omni_range = 2.8
	visual.add_child(light)

	var sparks := GPUParticles3D.new()
	sparks.name = "ShadowSparks"
	sparks.amount = 24
	sparks.lifetime = 0.9
	sparks.randomness = 0.7
	var spark_process := ParticleProcessMaterial.new()
	spark_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spark_process.emission_sphere_radius = 0.42
	spark_process.direction = Vector3.UP
	spark_process.spread = 180.0
	spark_process.initial_velocity_min = 0.25
	spark_process.initial_velocity_max = 0.8
	spark_process.gravity = Vector3(0.0, 0.35, 0.0)
	spark_process.scale_min = 0.22
	spark_process.scale_max = 0.48
	sparks.process_material = spark_process
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.025
	spark_mesh.height = 0.05
	spark_mesh.material = material
	sparks.draw_pass_1 = spark_mesh
	visual.add_child(sparks)
