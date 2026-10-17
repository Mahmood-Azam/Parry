extends Node3D
## The three supplied assets, plus lightweight lighting/particles. No route-blocking collision.
const METEOR := preload("res://assets/cinematics/breach/meteor.glb")
const EXPLOSION := preload("res://assets/cinematics/breach/meteor_explosion.glb")
const GATE := preload("res://assets/cinematics/breach/star_x_gate-zeta.glb")
const FX := preload("res://combat_fx.gd")
var impact_point := Vector3(44.0, 12.5, -81.0)
## Surviving floor-two slab becomes the exposed roof after the upper floors fall.
var gate_point := Vector3(47.0, 6.56, -81.0)
var rest_point := Vector3(41.5, 7.2, -81.0)
var destruction: Node3D
var meteor: Node3D
var explosion: Node3D
var gate: Node3D
var explosion_player: AnimationPlayer
var meteor_trail: GPUParticles3D
var gate_motes: GPUParticles3D
var portal_light: OmniLight3D
var impact_light: OmniLight3D
var scorch: MeshInstance3D
var clock := 0.0
var relic_charge := 0.0
var cinematic := false
var impact_started := false
var shield: MeshInstance3D
var shield_material: StandardMaterial3D
var shield_tween: Tween

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	destruction = Node3D.new()
	destruction.name = "CampusDestruction"
	destruction.set_script(preload("res://campus_destruction.gd"))
	destruction.campus = get_parent().get_node("CampusMap")
	add_child(destruction)
	meteor = _asset(METEOR, "Meteor", 2.8, false)
	explosion = _asset(EXPLOSION, "MeteorExplosion", 3.6, false)
	gate = _asset(GATE, "EclipseGate", 8.0, true)
	gate.set_script(preload("res://breach_gate.gd"))
	shield = MeshInstance3D.new()
	shield.name = "ImpactProtectionField"
	var shell := SphereMesh.new()
	shell.radius = 4.3
	shell.height = 8.6
	shield.mesh = shell
	shield.position = Vector3(0, 3.1, 0)
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shield_material = StandardMaterial3D.new()
	shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_material.albedo_color = Color(0.45, 0.12, 0.9, 0.0)
	shield_material.emission_enabled = true
	shield_material.emission = Color(0.35, 0.08, 0.7)
	shield_material.emission_energy_multiplier = 1.8
	shield.material_override = shield_material
	gate.add_child(shield)
	explosion_player = explosion.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if explosion_player != null:
		for key in explosion_player.get_animation_list():
			explosion_player.get_animation(key).loop_mode = Animation.LOOP_NONE
	meteor_trail = _particles(meteor, Color(1.0, 0.32, 0.025), 80, 0.7, 1.4)
	meteor_trail.position.y = 0.2
	gate_motes = _particles(gate, Color(0.55, 0.12, 1.0), 42, 1.8, 0.8)
	gate_motes.position = Vector3(0, 3.6, 0)
	var process := gate_motes.process_material as ParticleProcessMaterial
	process.emission_sphere_radius = 1.9
	portal_light = _light(gate, Color(0.55, 0.18, 1.0), 3.5, 12.0)
	portal_light.position = Vector3(0, 3.6, 1.0)
	impact_light = _light(self, Color(1.0, 0.32, 0.04), 0.0, 20.0)
	impact_light.position = impact_point + Vector3.UP * 2.0
	scorch = MeshInstance3D.new()
	scorch.name = "ImpactScorch"
	var disc := CylinderMesh.new()
	disc.top_radius = 3.2
	disc.bottom_radius = 3.2
	disc.height = 0.015
	scorch.mesh = disc
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.024, 0.018, 0.025)
	material.roughness = 1.0
	scorch.material_override = material
	add_child(scorch)
	scorch.position = Vector3(38, 0.05, -81)
	show_aftermath()

func _asset(scene: PackedScene, label: String, span: float, grounded: bool) -> Node3D:
	var mount := Node3D.new()
	mount.name = label
	add_child(mount)
	var visual := scene.instantiate() as Node3D
	mount.add_child(visual)
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		var local_box: AABB = (visual.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = local_box if first else bounds.merge(local_box)
		first = false
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visibility_range_end = 100.0
	var factor := span / maxf(bounds.size[bounds.size.max_axis_index()], 0.001)
	visual.scale = Vector3.ONE * factor
	visual.position = -bounds.get_center() * factor
	if grounded:
		visual.position.y = -bounds.position.y * factor
	return mount

func _light(parent: Node3D, tint: Color, energy: float, distance: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = energy
	light.omni_range = distance
	light.shadow_enabled = false
	parent.add_child(light)
	return light

func _particles(parent: Node3D, tint: Color, count: int, lifetime: float, speed: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = lifetime
	particles.local_coords = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.visibility_aabb = AABB(Vector3.ONE * -12, Vector3.ONE * 24)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 35.0
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.5
	process.initial_velocity_min = speed * 0.5
	process.initial_velocity_max = speed
	process.gravity = Vector3(0, 0.3, 0)
	process.scale_min = 0.3
	process.scale_max = 1.0
	var gradient := Gradient.new()
	gradient.set_color(0, tint)
	gradient.set_color(1, Color(tint.r, tint.g, tint.b, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.30)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 2.5
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var falloff := Gradient.new()
	falloff.set_color(0, Color.WHITE)
	falloff.set_color(1, Color(1, 1, 1, 0))
	falloff.add_point(0.35, Color(1, 1, 1, 0.65))
	soft.gradient = falloff
	material.albedo_texture = soft
	quad.material = material
	particles.draw_pass_1 = quad
	parent.add_child(particles)
	return particles

func prepare_intro() -> void:
	destruction.restore_intact()
	cinematic = true
	impact_started = false
	meteor.show()
	explosion.hide()
	# The machine already exists inside the upper storeys. The meteor exposes
	# it by removing the surrounding building; it never scales into existence.
	gate.position = gate_point
	gate.show()
	scorch.hide()
	meteor_trail.emitting = false
	gate_motes.emitting = false
	impact_light.light_energy = 0.0
	gate.scale = Vector3.ONE
	if is_instance_valid(shield_tween):
		shield_tween.kill()
	shield_material.albedo_color.a = 0.0

func strike() -> void:
	if impact_started:
		return
	impact_started = true
	destruction.destroy(true)
	shield_material.albedo_color.a = 0.22
	shield_tween = create_tween()
	shield_tween.tween_property(shield_material, "albedo_color:a", 0.0, 0.75)
	FX.ring(self, gate_point + Vector3.UP * 3.4, Color(0.65, 0.3, 1.0, 0.8), 4.2, Vector3.BACK)
	meteor.hide()
	meteor_trail.emitting = false
	scorch.show()
	explosion.show()
	explosion.position = impact_point + Vector3.UP * 1.0
	if explosion_player != null:
		explosion_player.play("Take 001")
		explosion_player.speed_scale = 1.4
		explosion_player.advance(0.0)
	FX.burst(self, impact_point + Vector3.UP, Color(1.0, 0.44, 0.07), 100, 2.0)
	FX.burst(self, impact_point, Color(0.36, 0.30, 0.28, 0.7), 65, 6.0, true)
	FX.ring(self, impact_point + Vector3.UP * 0.08, Color(1, 0.4, 0.06, 0.75), 9.0)
	impact_light.light_energy = 14.0
	create_tween().tween_property(impact_light, "light_energy", 0.0, 1.1)

func show_aftermath() -> void:
	destruction.destroy(false)
	cinematic = false
	meteor.show()
	meteor.position = rest_point
	meteor.scale = Vector3.ONE * 0.72
	meteor_trail.emitting = false
	explosion.hide()
	if explosion_player != null:
		explosion_player.stop()
	gate.position = gate_point
	gate.scale = Vector3.ONE
	gate.show()
	gate_motes.emitting = true
	scorch.show()
	impact_light.light_energy = 0.0
	if is_instance_valid(shield_tween):
		shield_tween.kill()
	shield_material.albedo_color.a = 0.0

func _process(delta: float) -> void:
	clock += delta
	relic_charge = move_toward(relic_charge, 0.0, delta * 2.2)
	portal_light.light_energy = 2.7 + sin(clock * 2.2) * 0.45 + relic_charge

func energize_with_relics(from_position: Vector3) -> void:
	relic_charge = 5.0
	shield_material.albedo_color.a = 0.65
	var pulse := create_tween()
	pulse.tween_property(shield_material, "albedo_color:a", 0.0, 1.4)
	FX.ring(get_parent(), gate_point + Vector3.UP * 1.3, Color(0.5, 0.85, 1.0), 2.8)
	var sound := AudioStreamPlayer3D.new()
	sound.name = "RelicPortalSound"
	sound.stream = preload("res://breach_audio.gd").cue("portal")
	sound.volume_db = -5.0
	sound.position = gate_point
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()
	for index in 3:
		var mote := MeshInstance3D.new()
		mote.name = "InsertedRelic%d" % (index + 1)
		var sphere := SphereMesh.new()
		sphere.radius = 0.13
		sphere.height = 0.26
		mote.mesh = sphere
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.34, 0.8, 1.0)
		material.emission_enabled = true
		material.emission = Color(0.4, 0.8, 1.0)
		material.emission_energy_multiplier = 3.0
		mote.material_override = material
		add_child(mote)
		mote.global_position = from_position + Vector3.UP * (1.1 + index * 0.15)
		var destination := gate_point + Vector3.UP * (2.1 + index * 0.65)
		var flight := create_tween()
		flight.tween_interval(index * 0.12)
		flight.tween_property(mote, "global_position", destination, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		flight.tween_property(mote, "scale", Vector3.ZERO, 0.2)
		flight.tween_callback(mote.queue_free)

## Restore the campus after the final defender has fallen.
func restore_campus(seconds: float = 2.5) -> void:
	if destruction.destroyed:
		destruction.reverse_destruction(seconds)
		await destruction.restored
	meteor.hide()
	explosion.hide()
	scorch.hide()
	gate.hide()
	gate_motes.emitting = false
