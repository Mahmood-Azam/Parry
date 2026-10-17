extends Node3D
## Flame tongues track the animated rig instead of wrapping the boss in a mesh.

const FX := preload("res://combat_fx.gd")
const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform vec4 aura_color : source_color = vec4(0.7, 0.3, 1.0, 1.0);
uniform float effect_time = 0.0;
uniform float opacity = 1.0;
uniform float attack_pulse = 0.0;
instance uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}
void fragment() {
	float y = 1.0 - UV.y;
	float x = UV.x * 2.0 - 1.0;
	float t = effect_time + seed * 11.0;
	float flow = noise(vec2(x * 3.7 + seed * 17.0, y * 5.0 - t * 3.4));
	float detail = noise(vec2(x * 9.0, y * 15.0 - t * 7.0));
	float bend = sin(y * 7.0 - t * 4.5) * y * 0.13 + (flow - 0.5) * y * 0.45;
	float width = mix(0.90, 0.015, pow(y, 0.72)) * (0.60 + flow * 0.52);
	float shape = 1.0 - smoothstep(width * 0.65, width, abs(x + bend));
	float ragged_tip = 1.0 - smoothstep(0.68 + flow * 0.20, 1.0, y);
	float intensity = shape * ragged_tip * smoothstep(0.0, 0.10, y);
	float core = pow(shape, 2.6) * (1.0 - y) * (0.55 + detail * 0.45);
	vec3 edge_color = aura_color.rgb * 0.62;
	vec3 hot_color = mix(aura_color.rgb, vec3(1.0), 0.68);
	vec3 flame = mix(edge_color, hot_color, core);
	ALBEDO = flame;
	EMISSION = flame * (1.8 + attack_pulse * 1.8);
	ALPHA = intensity * opacity * (0.55 + flow * 0.35 + detail * 0.10);
}
"""

var owner_body: CharacterBody3D
var rig: Skeleton3D
var aura_color := Color(0.65, 0.30, 1.0)
var body_height := 2.0
var body_radius := 0.85
var flames: Array[Dictionary] = []
var flame_material: ShaderMaterial
var motes: GPUParticles3D
var splash: GPUParticles3D
var glow: OmniLight3D
var clock := 0.0
var pulse := 0.0
var fade := 1.0
var fading := false


func configure(color: Color, height: float, radius: float) -> void:
	aura_color = color
	body_height = height
	body_radius = radius


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	owner_body = get_parent() as CharacterBody3D
	var rigs := owner_body.find_children("*", "Skeleton3D", true, false)
	rig = rigs[0] as Skeleton3D if not rigs.is_empty() else null
	_build_flames()
	motes = _make_particles(false)
	splash = _make_particles(true)
	glow = OmniLight3D.new()
	glow.name = "FlameAuraGlow"
	glow.position.y = body_height * 0.48
	glow.light_color = aura_color
	glow.light_energy = 0.85
	glow.omni_range = maxf(3.0, body_height * 0.86)
	glow.shadow_enabled = false
	add_child(glow)


func _build_flames() -> void:
	var shader := Shader.new()
	shader.code = FLAME_SHADER
	flame_material = ShaderMaterial.new()
	flame_material.shader = shader
	flame_material.set_shader_parameter("aura_color", aura_color)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var sections := [
		{"bones": ["hips", "pelvis"], "level": 0.22, "reach": 0.65, "length": 0.38, "count": 12},
		{"bones": ["spine", "chest"], "level": 0.52, "reach": 0.60, "length": 0.34, "count": 14},
		{"bones": ["head", "neck"], "level": 0.83, "reach": 0.42, "length": 0.24, "count": 8},
		{"bones": ["leftarm", "upperarml", "arm_l"], "level": 0.63, "reach": 0.29, "length": 0.26, "count": 6},
		{"bones": ["rightarm", "upperarmr", "arm_r"], "level": 0.63, "reach": 0.29, "length": 0.26, "count": 6},
		{"bones": ["leftforearm", "lowerarml", "forearm_l"], "level": 0.50, "reach": 0.19, "length": 0.21, "count": 4},
		{"bones": ["rightforearm", "lowerarmr", "forearm_r"], "level": 0.50, "reach": 0.19, "length": 0.21, "count": 4},
		{"bones": ["leftupleg", "leftleg", "thigh_l"], "level": 0.26, "reach": 0.26, "length": 0.31, "count": 6},
		{"bones": ["rightupleg", "rightleg", "thigh_r"], "level": 0.26, "reach": 0.26, "length": 0.31, "count": 6},
		{"bones": ["leftfoot", "leftcalf", "shin_l"], "level": 0.10, "reach": 0.22, "length": 0.22, "count": 4},
		{"bones": ["rightfoot", "rightcalf", "shin_r"], "level": 0.10, "reach": 0.22, "length": 0.22, "count": 4},
	]
	for section_index in sections.size():
		var section: Dictionary = sections[section_index]
		var bone := _find_bone(section["bones"])
		for index in int(section["count"]):
			var tongue := MeshInstance3D.new()
			tongue.name = "AnimatedFlame_%02d_%02d" % [section_index, index]
			tongue.mesh = quad
			tongue.material_override = flame_material
			tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tongue.set_instance_shader_parameter("seed", float(section_index * 17 + index) * 0.173)
			add_child(tongue)
			var angle := float(index) * 2.399963 + float(section_index) * 0.91
			flames.append({"node": tongue, "bone": bone, "level": section["level"], "reach": section["reach"], "length": section["length"], "angle": angle, "seed": float(index * 7 + section_index * 13)})


func _find_bone(names: Array) -> int:
	if rig == null:
		return -1
	for wanted: String in names:
		for index in rig.get_bone_count():
			var name := String(rig.get_bone_name(index)).to_lower().replace("_", "").replace(" ", "")
			if name.contains(wanted):
				return index
	return -1


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
	gradient.set_color(0, Color(aura_color.r, aura_color.g, aura_color.b, 0.0))
	gradient.add_point(0.15, Color(aura_color.r, aura_color.g, aura_color.b, 0.85))
	gradient.set_color(gradient.get_point_count() - 1, Color(aura_color.r, aura_color.g, aura_color.b, 0.0))
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
	flame_material.set_shader_parameter("effect_time", clock)
	flame_material.set_shader_parameter("attack_pulse", pulse)
	flame_material.set_shader_parameter("opacity", fade * (0.72 + pulse * 0.16))
	glow.light_energy = fade * (0.80 + sin(clock * 3.0) * 0.12 + pulse * 1.8)
	var camera := get_viewport().get_camera_3d()
	var bone_positions := {}
	for flame in flames:
		var tongue := flame["node"] as MeshInstance3D
		var anchor := owner_body.to_global(Vector3.UP * body_height * float(flame["level"]))
		var bone: int = flame["bone"]
		if rig != null and bone >= 0:
			if not bone_positions.has(bone):
				bone_positions[bone] = rig.to_global(rig.get_bone_global_pose(bone).origin)
			anchor = bone_positions[bone]
		var angle: float = flame["angle"] + sin(clock * 1.4 + float(flame["seed"])) * 0.12
		var radial := Vector3(cos(angle), 0.0, sin(angle)) * body_radius * float(flame["reach"])
		tongue.global_position = anchor + owner_body.global_basis * radial + Vector3.UP * body_height * float(flame["length"]) * 0.28
		if camera != null:
			var toward := camera.global_position - tongue.global_position
			tongue.global_rotation = Vector3(0.0, atan2(toward.x, toward.z), 0.0)
		var flicker := 0.84 + sin(clock * 7.0 + float(flame["seed"]) * 2.1) * 0.12 + pulse * 0.12
		tongue.scale = Vector3(body_radius * float(flame["reach"]) * 1.08 * flicker, body_height * float(flame["length"]) * flicker, 1.0)


func charge() -> void:
	if not fading:
		pulse = maxf(pulse, 0.55)


func attack_splash() -> void:
	if fading or not is_instance_valid(owner_body):
		return
	pulse = 1.0
	splash.global_position = owner_body.global_position + Vector3.UP * body_height * 0.55 + owner_body.global_basis.z * body_radius * 0.75
	splash.global_basis = owner_body.global_basis
	splash.restart()
	FX.ring(get_tree().current_scene, splash.global_position, Color(aura_color.r, aura_color.g, aura_color.b, 0.65), body_radius * 1.65, owner_body.global_basis.z)


func power_surge() -> void:
	if fading or not is_instance_valid(owner_body):
		return
	pulse = 1.4
	var origin := owner_body.global_position + Vector3.UP * 0.08
	FX.ring(get_tree().current_scene, origin, Color(aura_color.r, aura_color.g, aura_color.b, 0.72), body_radius * 2.5)
	FX.burst(get_tree().current_scene, origin + Vector3.UP * body_height * 0.35, aura_color, 48, 1.25)


func fade_out() -> void:
	fading = true
	motes.emitting = false
