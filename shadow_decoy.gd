extends Node3D

## Temporary target created at the end of every Shadow dash.
@export var lifetime: float = 2.5

var age: float = 0.0
var visual: Node3D
var material: StandardMaterial3D

func _ready() -> void:
	add_to_group("shadow_decoy")
	_setup_visual()

func _process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
		return
	if visual != null:
		visual.position.y = 0.05 + sin(age * 7.0) * 0.04
		visual.rotation.y += delta * 2.5
	if material != null:
		var fade := clampf((lifetime - age) / 0.45, 0.0, 1.0)
		material.albedo_color.a = 0.34 * fade

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

	var light := OmniLight3D.new()
	light.light_color = Color(0.35, 0.08, 0.8)
	light.light_energy = 1.4
	light.omni_range = 2.8
	visual.add_child(light)
