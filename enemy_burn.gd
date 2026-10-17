extends Node3D
## One refreshable fire status per enemy; repeated slashes never stack emitters
## or multiply damage ticks. Inherits gameplay pause from its owning enemy.
const FLAME := preload("res://flame_aura.gd")
const TICK_INTERVAL := 0.25
var remaining: float = 0.0
var damage_per_second: float = 0.0
var heat: float = 0.0
var attacker: WeakRef
var tick_elapsed: float = 0.0
var elapsed: float = 0.0
var flames: GPUParticles3D
var embers: GPUParticles3D
var material: ShaderMaterial
var glow: OmniLight3D
var extinguished: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	position.y = 0.95
	flames = GPUParticles3D.new()
	flames.name = "BurningFlames"
	flames.amount = 36
	flames.lifetime = 0.6
	flames.preprocess = 0.2
	flames.local_coords = false
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 5, 4))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.35, 0.62, 0.27)
	process.direction = Vector3.UP
	process.spread = 18.0
	process.initial_velocity_min = 0.35
	process.initial_velocity_max = 1.0
	process.gravity = Vector3(0, 0.65, 0)
	process.scale_min = 0.65
	process.scale_max = 1.3
	flames.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.30, 0.65)
	var shader := Shader.new()
	shader.code = FLAME.FLAME_SHADER
	material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("particle_sprite", true)
	material.set_shader_parameter("flame_axis_world", Vector3.UP)
	material.set_shader_parameter("opacity", 0.8)
	mesh.material = material
	flames.draw_pass_1 = mesh
	add_child(flames)
	embers = GPUParticles3D.new()
	embers.name = "BurningEmbers"
	embers.amount = 14
	embers.lifetime = 0.8
	embers.local_coords = false
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	embers.visibility_aabb = flames.visibility_aabb
	var spark_process := process.duplicate() as ParticleProcessMaterial
	spark_process.initial_velocity_min = 0.7
	spark_process.initial_velocity_max = 1.8
	spark_process.scale_min = 0.6
	spark_process.scale_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 0.8, 0.2, 1))
	ramp.set_color(1, Color(1, 0.12, 0.005, 0))
	var texture := GradientTexture1D.new()
	texture.gradient = ramp
	spark_process.color_ramp = texture
	embers.process_material = spark_process
	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.025, 0.045)
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_material.vertex_color_use_as_albedo = true
	spark_material.emission_enabled = true
	spark_material.emission = Color(1, 0.38, 0.025)
	spark_material.emission_energy_multiplier = 2.0
	spark_mesh.material = spark_material
	embers.draw_pass_1 = spark_mesh
	add_child(embers)
	glow = OmniLight3D.new()
	glow.light_color = Color(1.0, 0.28, 0.025)
	glow.omni_range = 2.8
	glow.shadow_enabled = false
	add_child(glow)

func ignite(duration: float, dps: float, power: float, source: Node) -> void:
	remaining = maxf(remaining, duration)
	damage_per_second = maxf(damage_per_second, dps)
	heat = maxf(heat, clampf(power, 0.0, 1.0))
	if is_instance_valid(source):
		attacker = weakref(source)
	extinguished = false
	flames.emitting = true
	embers.emitting = true
	material.set_shader_parameter("heat", heat)
	set_physics_process(true)
	set_process(true)

func _physics_process(delta: float) -> void:
	var enemy := get_parent()
	if enemy.is_dead:
		_extinguish()
		return
	var step := minf(delta, remaining)
	remaining = maxf(remaining - step, 0.0)
	tick_elapsed += step
	if tick_elapsed >= TICK_INTERVAL or remaining <= 0.0:
		var amount := tick_elapsed * damage_per_second
		tick_elapsed = 0.0
		var source: Node = attacker.get_ref() if attacker else null
		enemy.take_damage(amount, source)
	if remaining <= 0.0 or enemy.is_dead:
		_extinguish()

func _process(delta: float) -> void:
	elapsed += delta
	material.set_shader_parameter("effect_time", elapsed)
	var strength := clampf(remaining / 0.6, 0.0, 1.0)
	material.set_shader_parameter("opacity", 0.8 * strength)
	glow.light_energy = (0.75 + heat * 0.65) * strength * (0.94 + sin(elapsed * 17.0) * 0.06)

func _extinguish() -> void:
	if extinguished:
		return
	extinguished = true
	remaining = 0.0
	damage_per_second = 0.0
	heat = 0.0
	tick_elapsed = 0.0
	flames.emitting = false
	embers.emitting = false
	glow.light_energy = 0.0
	set_physics_process(false)
	material.set_shader_parameter("opacity", 0.0)
	set_process(false)
	# Reuse the same effect if ignited again; no lingering timers can delete
	# a freshly reapplied burn, and particle tails expire naturally.
