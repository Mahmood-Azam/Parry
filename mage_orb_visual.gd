extends Node3D
## Shared, bounded projectile/charging effect. No imported preview-sheet offsets.
const FLAME := preload("res://flame_aura.gd")
const ORB_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform bool fiery = false;
uniform float clock = 0.0;
void fragment() {
	float waves = sin(UV.x * 38.0 + clock * 8.0 + sin(UV.y * 23.0 - clock * 5.0) * 2.0);
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	vec3 dark_color = mix(vec3(0.025, 0.008, 0.07), vec3(0.48, 0.06, 0.85), smoothstep(0.5, 1.0, waves) * 0.5 + rim);
	vec3 fire_color = mix(vec3(1.0, 0.08, 0.005), vec3(1.0, 0.87, 0.28), waves * 0.5 + 0.5);
	ALBEDO = fiery ? fire_color : dark_color;
	EMISSION = ALBEDO * (fiery ? 3.5 : 2.8);
}
"""
var fiery := false
var elapsed := 0.0
var orb_material: ShaderMaterial
var bands: Array[MeshInstance3D] = []
var sparks: GPUParticles3D
var flames: GPUParticles3D
var light: OmniLight3D
var flame_material: ShaderMaterial

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var core := MeshInstance3D.new()
	core.name = "VisibleOrb"
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	sphere.radial_segments = 24
	sphere.rings = 12
	core.mesh = sphere
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = ORB_SHADER
	orb_material = ShaderMaterial.new()
	orb_material.shader = shader
	core.material_override = orb_material
	add_child(core)
	for index in 2:
		var band := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.30
		torus.outer_radius = 0.325
		torus.rings = 32
		torus.ring_segments = 6
		band.mesh = torus
		band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		band.material_override = material
		add_child(band)
		bands.append(band)
	sparks = _particles(false)
	flames = _particles(true)
	light = OmniLight3D.new()
	light.shadow_enabled = false
	light.omni_range = 3.0
	add_child(light)
	set_fiery(fiery)

func set_fiery(value: bool) -> void:
	fiery = value
	if orb_material == null:
		return
	orb_material.set_shader_parameter("fiery", fiery)
	var color := Color(1.0, 0.32, 0.025) if fiery else Color(0.65, 0.14, 1.0)
	for band in bands:
		var material := band.material_override as StandardMaterial3D
		material.albedo_color = color
		material.emission = color
		material.emission_energy_multiplier = 3.0
	light.light_color = color
	flames.emitting = fiery
	var process := sparks.process_material as ParticleProcessMaterial
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 0.85, 0.3) if fiery else Color(0.85, 0.35, 1.0))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var texture := GradientTexture1D.new()
	texture.gradient = ramp
	process.color_ramp = texture
	var material := sparks.draw_pass_1.material as StandardMaterial3D
	material.emission = color

func _process(delta: float) -> void:
	elapsed += delta
	orb_material.set_shader_parameter("clock", elapsed)
	flame_material.set_shader_parameter("effect_time", elapsed)
	bands[0].rotation = Vector3(elapsed * 2.2, elapsed * 1.1, 0.5)
	bands[1].rotation = Vector3(1.1, -elapsed * 2.5, elapsed * 1.6)
	light.light_energy = (1.6 if fiery else 1.0) * (0.95 + sin(elapsed * 19.0) * 0.05)

func _particles(is_flame: bool) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "FireWake" if is_flame else "MagicTrail"
	particles.amount = 24 if is_flame else 18
	particles.lifetime = 0.4 if is_flame else 0.5
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.2
	process.direction = Vector3.UP
	process.spread = 140.0
	process.initial_velocity_min = 0.2
	process.initial_velocity_max = 0.8
	process.gravity = Vector3(0, 0.5, 0)
	process.scale_min = 0.5
	process.scale_max = 1.3
	particles.process_material = process
	var quad := QuadMesh.new()
	if is_flame:
		quad.size = Vector2(0.4, 0.7)
		var shader := Shader.new()
		shader.code = FLAME.FLAME_SHADER
		flame_material = ShaderMaterial.new()
		flame_material.shader = shader
		flame_material.set_shader_parameter("particle_sprite", true)
		flame_material.set_shader_parameter("flame_axis_world", Vector3.UP)
		flame_material.set_shader_parameter("heat", 0.8)
		flame_material.set_shader_parameter("opacity", 0.8)
		quad.material = flame_material
	else:
		quad.size = Vector2(0.04, 0.08)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		material.emission_enabled = true
		material.emission_energy_multiplier = 2.5
		quad.material = material
	particles.draw_pass_1 = quad
	add_child(particles)
	return particles
