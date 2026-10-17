extends Node3D
## A brief flash, billowing fire, ballistic embers, smoke and a pressure ring.
const FX := preload("res://combat_fx.gd")
const FLAME := preload("res://flame_aura.gd")
var radius := 3.6
var elapsed := 0.0
var flame_material: ShaderMaterial

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	name = "FireballExplosion"
	FX.burst(self, global_position, Color(1.0, 0.58, 0.08), 90, 1.6)
	FX.ring(self, global_position, Color(1.0, 0.4, 0.035, 0.9), radius)
	_make_cloud(false)
	_make_cloud(true)
	_play_blast()
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	flash.mesh = sphere
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.85, 0.4, 0.85)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.55, 0.1)
	material.emission_energy_multiplier = 6.0
	flash.material_override = material
	add_child(flash)
	var light := OmniLight3D.new()
	light.shadow_enabled = false
	light.light_color = Color(1, 0.46, 0.08)
	light.light_energy = 7.0
	light.omni_range = radius * 2.2
	add_child(light)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 2.5, 0.065).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.075)
	tween.tween_property(light, "light_energy", 0.0, 0.65)
	get_tree().create_timer(2.0, false).timeout.connect(queue_free)
	for player in get_tree().get_nodes_in_group("player"):
		var distance: float = player.global_position.distance_to(global_position)
		if distance < 14.0 and player.has_method("_add_camera_trauma"):
			player.call("_add_camera_trauma", 0.55 * (1.0 - distance / 14.0))

func _process(delta: float) -> void:
	elapsed += delta
	flame_material.set_shader_parameter("effect_time", elapsed)

func _make_cloud(smoke: bool) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "BlastSmoke" if smoke else "BlastFlames"
	particles.amount = 18 if smoke else 44
	particles.lifetime = 1.5 if smoke else 0.65
	particles.one_shot = true
	particles.explosiveness = 0.93
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3.ONE * -7.0, Vector3.ONE * 14.0)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 100.0
	process.initial_velocity_min = 0.5 if smoke else 1.5
	process.initial_velocity_max = 2.0 if smoke else radius * 2.0
	process.damping_min = 1.0
	process.damping_max = 2.5
	process.gravity = Vector3(0, 0.4 if smoke else -1.0, 0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.2
	process.scale_min = 0.75
	process.scale_max = 1.6
	var size_curve := Curve.new()
	size_curve.add_point(Vector2(0, 0.3))
	size_curve.add_point(Vector2(0.25, 1.0))
	size_curve.add_point(Vector2(1.0, 0.8 if smoke else 0.1))
	var size_texture := CurveTexture.new()
	size_texture.curve = size_curve
	process.scale_curve = size_texture
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2) if smoke else Vector2(1.1, 1.6)
	if smoke:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.vertex_color_use_as_albedo = true
		var texture := GradientTexture2D.new()
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1, 0.5)
		var soft := Gradient.new()
		soft.set_color(0, Color.WHITE)
		soft.set_color(1, Color(1, 1, 1, 0))
		texture.gradient = soft
		material.albedo_texture = texture
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.22, 0.13, 0.09, 0.38))
		gradient.set_color(1, Color(0.08, 0.08, 0.1, 0))
		var ramp := GradientTexture1D.new()
		ramp.gradient = gradient
		process.color_ramp = ramp
		quad.material = material
	else:
		var shader := Shader.new()
		shader.code = FLAME.FLAME_SHADER
		flame_material = ShaderMaterial.new()
		flame_material.shader = shader
		flame_material.set_shader_parameter("particle_sprite", true)
		flame_material.set_shader_parameter("flame_axis_world", Vector3.UP)
		flame_material.set_shader_parameter("heat", 1.0)
		flame_material.set_shader_parameter("opacity", 0.9)
		quad.material = flame_material
	particles.draw_pass_1 = quad
	add_child(particles)
	particles.restart()

func _play_blast() -> void:
	# A short synthesized grenade crack and low boom; no external sound asset.
	var rate := 22050
	var samples := PackedByteArray()
	samples.resize(int(rate * 0.75) * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 17931
	var low_noise := 0.0
	for index in samples.size() / 2:
		var t := float(index) / float(rate)
		var noise := rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.16)
		var crack := noise * exp(-t * 55.0) * 0.5
		var boom := sin(TAU * (52.0 * t - 11.0 * t * t)) * exp(-t * 9.0) * 0.42
		var rumble := low_noise * exp(-t * 5.0) * 0.55
		var value := clampf((crack + boom + rumble) * minf(t / 0.002, 1.0), -0.95, 0.95)
		samples.encode_s16(index * 2, roundi(value * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = samples
	var audio := AudioStreamPlayer3D.new()
	audio.stream = stream
	audio.volume_db = -4.0
	audio.unit_size = 5.0
	audio.max_distance = 32.0
	add_child(audio)
	audio.play()
