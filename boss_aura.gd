extends Node3D
## Shared, lightweight boss signature: animated shell, motes, floor glyphs and attack flare.

const FX := preload("res://combat_fx.gd")
const SHELL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 aura_color : source_color = vec4(0.6, 0.3, 1.0, 1.0);
uniform float effect_time = 0.0;
uniform float attack_pulse = 0.0;
uniform float fade = 1.0;
varying vec3 shape_pos;
void vertex() { shape_pos = VERTEX; }
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.5);
	float flow = sin(shape_pos.y * 16.0 - effect_time * 5.0 + sin(shape_pos.x * 8.0 + effect_time * 1.7) * 2.0);
	float veins = pow(max(flow, 0.0), 5.0);
	float ends = smoothstep(-1.0, -0.75, shape_pos.y) * (1.0 - smoothstep(0.70, 1.0, shape_pos.y));
	ALBEDO = aura_color.rgb;
	EMISSION = aura_color.rgb * (1.8 + attack_pulse * 2.5);
	ALPHA = (rim * 0.32 + veins * 0.045 + 0.025) * ends * (0.7 + attack_pulse * 0.65) * fade;
}
"""

var owner_body: CharacterBody3D
var aura_color := Color(0.65, 0.30, 1.0)
var body_height := 2.0
var body_radius := 0.85
var shell: MeshInstance3D
var shell_material: ShaderMaterial
var rings: Array[MeshInstance3D] = []
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
	_build_shell()
	_build_rings()
	motes = _make_particles(false)
	splash = _make_particles(true)
	glow = OmniLight3D.new()
	glow.name = "AuraGlow"
	glow.position.y = body_height * 0.48
	glow.light_color = aura_color
	glow.light_energy = 0.55
	glow.omni_range = maxf(3.2, body_height * 0.85)
	glow.shadow_enabled = false
	add_child(glow)


func _build_shell() -> void:
	shell = MeshInstance3D.new()
	shell.name = "FlowingAuraShell"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	shell.mesh = sphere
	shell.position.y = body_height * 0.50
	shell.scale = Vector3(body_radius, body_height * 0.52, body_radius)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = SHELL_SHADER
	shell_material.shader = shader
	shell_material.set_shader_parameter("aura_color", aura_color)
	shell.material_override = shell_material
	add_child(shell)


func _build_rings() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.96
	mesh.outer_radius = 1.0
	mesh.rings = 32
	mesh.ring_segments = 6
	for index in 2:
		var ring := MeshInstance3D.new()
		ring.name = "OrbitingAuraRing%d" % index
		ring.mesh = mesh
		ring.position.y = 0.07 + float(index) * body_height * 0.18
		ring.scale = Vector3.ONE * body_radius * (1.17 if index == 0 else 0.88)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.albedo_color = Color(aura_color.r, aura_color.g, aura_color.b, 0.35 if index == 0 else 0.20)
		material.emission_enabled = true
		material.emission = aura_color
		material.emission_energy_multiplier = 2.0
		ring.material_override = material
		add_child(ring)
		rings.append(ring)


func _make_particles(is_splash: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "AttackAuraSplash" if is_splash else "RisingAuraMotes"
	particles.amount = 54 if is_splash else 44
	particles.lifetime = 0.52 if is_splash else 1.0
	particles.one_shot = is_splash
	particles.explosiveness = 0.94 if is_splash else 0.0
	particles.local_coords = not is_splash
	particles.emitting = not is_splash
	particles.position = Vector3(0.0, body_height * (0.55 if is_splash else 0.45), body_radius * 0.75 if is_splash else 0.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-body_height, -body_height, -body_height), Vector3.ONE * body_height * 2.0)
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.BACK if is_splash else Vector3.UP
	motion.spread = 48.0 if is_splash else 28.0
	motion.initial_velocity_min = (3.0 if is_splash else 0.5) * sqrt(body_height / 2.0)
	motion.initial_velocity_max = (7.0 if is_splash else 1.6) * sqrt(body_height / 2.0)
	motion.gravity = Vector3(0.0, -1.4 if is_splash else 0.2, 0.0)
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(body_radius * 0.55, body_height * (0.13 if is_splash else 0.38), body_radius * 0.55)
	motion.scale_min = 0.6
	motion.scale_max = 1.4
	var gradient := Gradient.new()
	gradient.set_color(0, Color(aura_color.r, aura_color.g, aura_color.b, 0.0))
	gradient.add_point(0.12, Color(aura_color.r, aura_color.g, aura_color.b, 0.85))
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
	quad.size = Vector2(0.055, 0.22) * sqrt(body_height / 2.0) if is_splash else Vector2(0.025, 0.16) * sqrt(body_height / 2.0)
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
	shell_material.set_shader_parameter("effect_time", clock)
	shell_material.set_shader_parameter("attack_pulse", pulse * fade)
	shell_material.set_shader_parameter("fade", fade)
	var breathe := 1.0 + sin(clock * 2.8) * 0.025 + pulse * 0.055
	shell.scale = Vector3(body_radius * breathe, body_height * 0.52, body_radius * breathe)
	for index in rings.size():
		var ring := rings[index]
		ring.rotation.y += delta * (0.8 if index == 0 else -1.2)
		ring.rotation.z = sin(clock * 1.9 + float(index) * 2.0) * 0.10
		var material := ring.material_override as StandardMaterial3D
		var color := material.albedo_color
		color.a = fade * (0.35 if index == 0 else 0.20) * (1.0 + pulse * 0.5)
		material.albedo_color = color
	glow.light_energy = fade * (0.55 + sin(clock * 3.2) * 0.10 + pulse * 1.7)


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
	var origin := splash.global_position
	FX.ring(get_tree().current_scene, origin, Color(aura_color.r, aura_color.g, aura_color.b, 0.65), body_radius * 1.65, owner_body.global_basis.z)


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
