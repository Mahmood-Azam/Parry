extends MeshInstance3D
## A short, fading ribbon follows the actual animated blade during fire attacks.

var controller: Node
var blade: MeshInstance3D
var handle: MeshInstance3D
var samples: Array[Dictionary] = []
var clock := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material_override = material
	var sword: Node3D = controller.character.get_node("Skeleton3D/RightHandSocket/Sword")
	blade = sword.find_child("BladeLP_DefaultMaterial_0", true, false)
	handle = sword.find_child("HandleLP_DefaultMaterial_0", true, false)


func _process(delta: float) -> void:
	clock += delta
	while not samples.is_empty() and clock - float(samples[0].time) > 0.12:
		samples.pop_front()
	if controller.is_alive and controller.attacking and controller.fire_meter > 0.0 and is_instance_valid(blade) and is_instance_valid(handle):
		var grip := handle.global_transform * handle.get_aabb().get_center()
		var tip: Vector3 = controller._get_blade_extreme_point(blade, grip)
		samples.append({"base":grip.lerp(tip, 0.25), "tip":tip, "time":clock})
		if samples.size() > 14:
			samples.pop_front()
	if samples.size() < 2:
		mesh = null
		return
	var ribbon := ImmediateMesh.new()
	if samples.size() >= 2:
		ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in range(samples.size() - 1):
			var a: Dictionary = samples[index]
			var b: Dictionary = samples[index + 1]
			for vertex in [a.base, a.tip, b.tip, a.base, b.tip, b.base]:
				var alpha := clampf(1.0 - (clock - float(a.time)) / 0.12, 0.0, 1.0) * 0.42
				ribbon.surface_set_color(Color(1.0, 0.32, 0.025, alpha))
				ribbon.surface_add_vertex(vertex)
		ribbon.surface_end()
	mesh = ribbon
