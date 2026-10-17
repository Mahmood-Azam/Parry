extends Node3D

## Temporary target created at the beginning of every Shadow dash.
@export var lifetime: float = 2.5

var age: float = 0.0
var source_character: Node3D
var visual: Node3D
var material: StandardMaterial3D
var light: OmniLight3D

func _ready() -> void:
	add_to_group("shadow_decoy")
	_setup_visual()

func _process(delta: float) -> void:
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
			for animation in player_silhouette.find_children("*", "AnimationPlayer", true, false):
				(animation as AnimationPlayer).stop()
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
