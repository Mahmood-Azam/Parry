extends Node3D
## Shared boss plasma; the mutant and Bara Ustaad use bone-tracked fist flames.

const FX := preload("res://combat_fx.gd")
const FLOW := preload("res://assets/vfx/boss_plasma_flow.png")
const RING_SHADER := preload("res://assets/vfx/boss_aura_ring.gdshader")
const VEIL_SHADER := preload("res://assets/vfx/boss_aura_veil.gdshader")
const FIST_SHADER := preload("res://assets/vfx/boss_fist_flame.gdshader")
const FIST_PARTICLE_SHADER := preload("res://assets/vfx/boss_fist_cinder.gdshader")

var owner_body: CharacterBody3D
var aura_color := Color(1.0, 0.32, 0.07)
var body_height := 2.0
var body_radius := 0.85
var final_boss := false
var fist_only := false
var ring_material: ShaderMaterial
var veil_material: ShaderMaterial
var fist_rig: Skeleton3D
var fists: Array[Dictionary] = []
var motes: GPUParticles3D
var splash: GPUParticles3D
var glow: OmniLight3D
var clock := 0.0
var pulse := 0.0
var fade := 1.0
var fading := false


func configure(color: Color, height: float, radius: float, is_final_boss: bool = false, use_fist_flames: bool = false) -> void:
	aura_color = color
	body_height = height
	body_radius = radius
	final_boss = is_final_boss
	fist_only = use_fist_flames


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	owner_body = get_parent() as CharacterBody3D
	if final_boss or fist_only:
		process_priority = 10
		_build_fist_flames()
	else:
		_build_plasma()
		motes = _make_particles(false)
		splash = _make_particles(true)
		glow = OmniLight3D.new()
		glow.name = "PlasmaAuraGlow"
		glow.position.y = body_height * 0.38
		glow.light_color = aura_color
		glow.light_energy = 0.85
		glow.omni_range = maxf(3.0, body_height * 0.86)
		glow.shadow_enabled = false
		add_child(glow)


func _build_plasma() -> void:
	ring_material = ShaderMaterial.new()
	ring_material.shader = RING_SHADER
	ring_material.set_shader_parameter("flow_texture", FLOW)
	var ground := MeshInstance3D.new()
	ground.name = "LivingPlasmaRing"
	var ground_mesh := QuadMesh.new()
	ground_mesh.size = Vector2.ONE * body_radius * 4.4
	ground.mesh = ground_mesh
	ground.material_override = ring_material
	ground.rotation.x = -PI * 0.5
	ground.position.y = 0.045
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	veil_material = ShaderMaterial.new()
	veil_material.shader = VEIL_SHADER
	veil_material.set_shader_parameter("flow_texture", FLOW)
	var veil := MeshInstance3D.new()
	veil.name = "RisingPlasmaVeil"
	veil.mesh = _make_veil_mesh()
	veil.material_override = veil_material
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(veil)


func _build_fist_flames() -> void:
	var rigs := owner_body.find_children("*", "Skeleton3D", true, false)
	if rigs.is_empty():
		push_error("Boss fist aura needs a Skeleton3D")
		return
	fist_rig = rigs[0] as Skeleton3D
	for side in ["Left", "Right"]:
		var wrist := fist_rig.find_bone("mixamorig_%sHand" % side)
		var knuckle := fist_rig.find_bone("mixamorig_%sHandMiddle2" % side) if final_boss else -1
		if wrist < 0:
			push_error("Missing %s fist bones" % side)
			continue
		var anchor := Node3D.new()
		anchor.name = "%sFistFlame" % side
		anchor.scale = Vector3.ONE * (1.0 if final_boss else 0.60)
		add_child(anchor)
		var core := MeshInstance3D.new()
		core.name = "LivingFistFlame"
		var sphere := SphereMesh.new()
		sphere.radius = 0.58
		sphere.height = 1.16
		sphere.radial_segments = 48
		sphere.rings = 24
		core.mesh = sphere
		var core_material := ShaderMaterial.new()
		core_material.shader = FIST_SHADER
		core_material.set_shader_parameter("flow_texture", FLOW)
		core_material.set_shader_parameter("phase", 0.0 if side == "Left" else 3.7)
		if fist_only:
			core_material.set_shader_parameter("dark_color", Color(0.005, 0.012, 0.14))
			core_material.set_shader_parameter("flame_color", Color(0.025, 0.27, 1.0))
			core_material.set_shader_parameter("hot_color", Color(0.12, 0.70, 1.0))
		core.material_override = core_material
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		anchor.add_child(core)
		var cinders := _make_fist_cinders(anchor, side)
		var light := OmniLight3D.new()
		light.name = "FistFlameLight"
		light.light_color = aura_color
		light.light_energy = 1.4
		light.omni_range = 2.1
		light.shadow_enabled = false
		anchor.add_child(light)
		fists.append({"anchor": anchor, "wrist": wrist, "knuckle": knuckle, "material": core_material, "cinders": cinders, "light": light})
	_update_fist_positions()


func _make_fist_cinders(anchor: Node3D, side: String) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "%sFistFlameTongues" % side
	particles.amount = 64
	particles.lifetime = 0.43
	particles.local_coords = false
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	particles.emitting = true
	particles.visibility_aabb = AABB(Vector3(-2.0, -2.0, -2.0), Vector3.ONE * 4.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 52.0
	motion.initial_velocity_min = 0.4
	motion.initial_velocity_max = 1.25
	motion.gravity = Vector3(0.0, 0.5, 0.0)
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.31
	motion.scale_min = 0.7
	motion.scale_max = 1.4
	particles.process_material = motion
	var material := ShaderMaterial.new()
	material.shader = FIST_PARTICLE_SHADER
	material.set_shader_parameter("flow_texture", FLOW)
	if fist_only:
		material.set_shader_parameter("dark_color", Color(0.005, 0.025, 0.18))
		material.set_shader_parameter("flame_color", Color(0.065, 0.48, 1.0))
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.74)
	quad.material = material
	particles.draw_pass_1 = quad
	anchor.add_child(particles)
	return particles


func _update_fist_positions() -> void:
	if not is_instance_valid(fist_rig):
		return
	for fist in fists:
		var wrist: int = fist["wrist"]
		var knuckle: int = fist["knuckle"]
		var wrist_position := fist_rig.to_global(fist_rig.get_bone_global_pose(wrist).origin)
		var anchor := fist["anchor"] as Node3D
		if knuckle >= 0:
			var knuckle_position := fist_rig.to_global(fist_rig.get_bone_global_pose(knuckle).origin)
			anchor.global_position = wrist_position.lerp(knuckle_position, 0.48)
		else:
			var wrist_pose := fist_rig.get_bone_global_pose(wrist)
			anchor.global_position = fist_rig.to_global(wrist_pose.origin + wrist_pose.basis.y * 0.25)


func _make_veil_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var sides := 64
	var levels := 16
	for level in levels + 1:
		var height_fraction := float(level) / float(levels)
		var radius := body_radius * (1.12 + 0.20 * sin(height_fraction * PI) - 0.23 * height_fraction)
		for side in sides + 1:
			var around := float(side) / float(sides)
			var angle := around * TAU
			var contour := 1.0 + 0.07 * sin(angle * 5.0 + height_fraction * 8.0) + 0.035 * sin(angle * 11.0 - height_fraction * 13.0)
			vertices.append(Vector3(cos(angle) * radius * contour, body_height * (0.035 + height_fraction * 1.08), sin(angle) * radius * contour))
			uv.append(Vector2(around, height_fraction))
	for level in levels:
		for side in sides:
			var first := level * (sides + 1) + side
			indices.append_array(PackedInt32Array([first, first + sides + 1, first + 1, first + 1, first + sides + 1, first + sides + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_particles(is_splash: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "AttackFlameSplash" if is_splash else "FloatingFlameCinders"
	particles.amount = 58 if is_splash else 38
	particles.lifetime = 0.50 if is_splash else 0.95
	particles.one_shot = is_splash
	particles.explosiveness = 0.95 if is_splash else 0.0
	particles.local_coords = not is_splash
	particles.emitting = not is_splash
	particles.position = Vector3(0.0, body_height * (0.55 if is_splash else 0.38), body_radius * 0.75 if is_splash else 0.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3.ONE * -body_height, Vector3.ONE * body_height * 2.0)
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.BACK if is_splash else Vector3.UP
	motion.spread = 50.0 if is_splash else 28.0
	motion.initial_velocity_min = (3.0 if is_splash else 0.7) * sqrt(body_height / 2.0)
	motion.initial_velocity_max = (7.0 if is_splash else 2.0) * sqrt(body_height / 2.0)
	motion.gravity = Vector3(0.0, -1.4 if is_splash else 0.2, 0.0)
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(body_radius * 0.52, body_height * (0.13 if is_splash else 0.32), body_radius * 0.52)
	motion.scale_min = 0.6
	motion.scale_max = 1.35
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.3, 0.02, 0.12, 0.0))
	gradient.add_point(0.15, Color(1.0, 0.38, 0.07, 0.85))
	gradient.set_color(gradient.get_point_count() - 1, Color(0.24, 0.02, 0.17, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	particles.process_material = motion
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = aura_color
	material.emission_energy_multiplier = 2.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.22) * sqrt(body_height / 2.0) if is_splash else Vector2(0.025, 0.14) * sqrt(body_height / 2.0)
	quad.material = material
	particles.draw_pass_1 = quad
	add_child(particles)
	return particles


func _process(delta: float) -> void:
	clock += delta
	pulse = move_toward(pulse, 0.0, delta * 2.8)
	if fading:
		fade = move_toward(fade, 0.0, delta * 2.0)
		visible = fade > 0.01
	if final_boss or fist_only:
		_update_fist_positions()
		for fist in fists:
			var material := fist["material"] as ShaderMaterial
			material.set_shader_parameter("effect_time", clock)
			material.set_shader_parameter("attack_pulse", pulse)
			material.set_shader_parameter("opacity", fade)
			var light := fist["light"] as OmniLight3D
			light.light_energy = fade * (1.25 + 0.16 * sin(clock * 9.0 + float(fist["wrist"])) + pulse * 1.2)
		return
	for material in [ring_material, veil_material]:
		material.set_shader_parameter("effect_time", clock)
		material.set_shader_parameter("attack_pulse", pulse)
		material.set_shader_parameter("opacity", fade)
	glow.light_energy = fade * (0.8 + sin(clock * 3.0) * 0.12 + pulse * 1.8)


func charge() -> void:
	if not fading:
		pulse = maxf(pulse, 0.55)


func attack_splash() -> void:
	if fading or not is_instance_valid(owner_body):
		return
	pulse = 1.0
	if final_boss or fist_only:
		_burst_fists(17)
		return
	splash.global_position = owner_body.global_position + Vector3.UP * body_height * 0.55 + owner_body.global_basis.z * body_radius * 0.75
	splash.global_basis = owner_body.global_basis
	splash.restart()
	FX.ring(get_tree().current_scene, splash.global_position, Color(1.0, 0.32, 0.07, 0.65), body_radius * 1.65, owner_body.global_basis.z)


func power_surge() -> void:
	if fading or not is_instance_valid(owner_body):
		return
	pulse = 1.4
	if final_boss or fist_only:
		_burst_fists(32)
		return
	var origin := owner_body.global_position + Vector3.UP * 0.08
	FX.ring(get_tree().current_scene, origin, Color(1.0, 0.32, 0.07, 0.72), body_radius * 2.5)
	FX.burst(get_tree().current_scene, origin + Vector3.UP * body_height * 0.35, aura_color, 48, 1.25)


func fade_out() -> void:
	fading = true
	if final_boss or fist_only:
		for fist in fists:
			(fist["cinders"] as GPUParticles3D).emitting = false
	else:
		motes.emitting = false


func _burst_fists(count: int) -> void:
	_update_fist_positions()
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return
	for fist in fists:
		var anchor := fist["anchor"] as Node3D
		FX.burst(scene, anchor.global_position, aura_color, count, 0.65)
