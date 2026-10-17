extends RefCounted
## Short-lived shared effects. All nodes clean themselves up and pause with gameplay.

static func burst(parent: Node, origin: Vector3, tint: Color, count: int = 24, power: float = 1.0, dust: bool = false) -> void:
	var particles := GPUParticles3D.new()
	particles.process_mode = Node.PROCESS_MODE_PAUSABLE
	particles.name = "FootDust" if dust else "CombatEmbers"
	particles.amount = count
	particles.lifetime = 0.48 if dust else 0.62
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3.ONE * -5.0, Vector3.ONE * 10.0)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 85.0 if dust else 150.0
	process.initial_velocity_min = 0.2 if dust else 1.4 * power
	process.initial_velocity_max = 0.8 * power if dust else 5.0 * power
	process.gravity = Vector3(0.0, 0.2 if dust else -5.0, 0.0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12
	process.scale_min = 0.6
	process.scale_max = 1.6
	var ramp := Gradient.new()
	ramp.set_color(0, tint)
	ramp.set_color(1, Color(tint.r, tint.g, tint.b, 0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	particles.process_material = process
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = not dust
	material.emission = tint
	material.emission_energy_multiplier = 2.0
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.18, 0.18) if dust else Vector2(0.018, 0.085)
	if dust:
		var soft := GradientTexture2D.new()
		soft.fill = GradientTexture2D.FILL_RADIAL
		soft.fill_from = Vector2(0.5, 0.5)
		soft.fill_to = Vector2(1.0, 0.5)
		var falloff := Gradient.new()
		falloff.set_color(0, Color(1.0, 1.0, 1.0, 0.35))
		falloff.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		soft.gradient = falloff
		material.albedo_texture = soft
	mesh.material = material
	particles.draw_pass_1 = mesh
	parent.add_child(particles)
	particles.global_position = origin
	particles.restart()
	parent.get_tree().create_timer(particles.lifetime + 0.15, false).timeout.connect(particles.queue_free)


static func ring(parent: Node, origin: Vector3, tint: Color, radius: float, normal: Vector3 = Vector3.UP) -> void:
	var ring_mesh := MeshInstance3D.new()
	ring_mesh.process_mode = Node.PROCESS_MODE_PAUSABLE
	ring_mesh.name = "CombatShockRing"
	ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 8
	ring_mesh.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = tint
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 1.5
	ring_mesh.material_override = material
	parent.add_child(ring_mesh)
	ring_mesh.global_position = origin
	ring_mesh.quaternion = Quaternion(Vector3.UP, normal.normalized())
	ring_mesh.scale = Vector3.ONE * 0.08
	var tween := ring_mesh.create_tween().set_parallel(true)
	tween.tween_property(ring_mesh, "scale", Vector3.ONE * radius, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, 0.28)
	tween.chain().tween_callback(ring_mesh.queue_free)
