extends Node3D
## Rendering-only changes: all building and terrain collisions stay intact.
var quality: int = 0
var render_distance: int = 1
var vegetation: Array[MultiMeshInstance3D] = []
var original_multimeshes: Array[MultiMesh] = []
var foliage_chunks: Array[MultiMeshInstance3D] = []
var foliage_base_ranges: Array[float] = []
var surface_materials: Array[ShaderMaterial] = []
var environment: Environment
var world_environment: WorldEnvironment
var fog_check_clock := 0.0
var outdoor_fog := true
var source_instances: int = 0
var rendered_instances: int = 0
var batched_mesh_count: int = 0
var batch_count: int = 0
var static_visuals: Array[GeometryInstance3D] = []
var static_extents: Array[float] = []
var static_shadows: Array[int] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var static_bins: Dictionary = {}
	for node in find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry is MultiMeshInstance3D:
			vegetation.append(geometry)
			original_multimeshes.append(geometry.multimesh)
			source_instances += geometry.multimesh.instance_count
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif geometry is MeshInstance3D:
			var mesh_node := geometry as MeshInstance3D
			var extent := mesh_node.get_aabb().size.length()
			static_visuals.append(mesh_node)
			static_extents.append(extent)
			static_shadows.append(mesh_node.cast_shadow)
			# Keep large facades; cull small distant furnishings, rubble and trim.
			geometry.visibility_range_end = 55.0 if extent < 3.0 else 160.0
			geometry.visibility_range_end_margin = 5.0
			if mesh_node.mesh is BoxMesh and extent < 18.0:
				var box := mesh_node.mesh as BoxMesh
				var box_material: Material = mesh_node.material_override if mesh_node.material_override else box.material
				var center := mesh_node.global_position
				var cell := Vector3i(floori(center.x / 20.0), floori(center.y / 8.0), floori(center.z / 20.0))
				var key := "%s/%s/%s/%s/%s/%s/%s" % [box.size, box.subdivide_width, box.subdivide_height, box.subdivide_depth, box_material.get_rid() if box_material else RID(), cell, geometry.visibility_range_end]
				if not static_bins.has(key):
					static_bins[key] = []
				static_bins[key].append(mesh_node)
			var surface_material := mesh_node.material_override as ShaderMaterial
			if surface_material and surface_material.shader and surface_material.shader.resource_path.ends_with("aged_surface.gdshader") and not surface_materials.has(surface_material):
				surface_materials.append(surface_material)
	_batch_static_boxes(static_bins)
	for node in find_children("*", "WorldEnvironment", true, false):
		world_environment = node
		environment = node.environment.duplicate(true)
		node.environment = environment
		_setup_night()
	for node in find_children("*", "Light3D", true, false):
		if node is DirectionalLight3D:
			node.light_color = Color(0.48, 0.62, 0.86)
			node.light_energy = 0.48
			node.directional_shadow_max_distance = 55.0
		elif node is OmniLight3D:
			node.light_color = Color(0.43, 0.53, 0.66)
			node.light_energy = 0.28
			node.shadow_enabled = false
			node.distance_fade_enabled = true
			node.distance_fade_begin = 16.0
			node.distance_fade_length = 5.0
	var config := ConfigFile.new()
	config.load("user://shadowborn_graphics.cfg")
	apply_quality(int(config.get_value("graphics", "quality", 0)), false)
	apply_render_distance(int(config.get_value("graphics", "render_distance", 1)), false)


func _process(delta: float) -> void:
	if not is_instance_valid(world_environment) or world_environment.environment != environment:
		return # The ending swaps to its own daylight environment.
	fog_check_clock -= delta
	if fog_check_clock <= 0.0:
		fog_check_clock = 0.35
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var start := camera.global_position
			var query := PhysicsRayQueryParameters3D.create(start, start + Vector3.UP * 35.0, 1)
			outdoor_fog = get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	var target := 0.009 if outdoor_fog else 0.0015
	environment.fog_density = lerpf(environment.fog_density, target, 1.0 - exp(-1.8 * delta))

func _batch_static_boxes(bins: Dictionary) -> void:
	# Repeated walls, frames, desks and trim become instanced draw calls. Their
	# original physics bodies remain untouched; only original visuals are hidden.
	for group: Array in bins.values():
		if group.size() < 3:
			continue
		var first := group[0] as MeshInstance3D
		var center := Vector3.ZERO
		for original: MeshInstance3D in group:
			center += original.global_position
		center /= group.size()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = first.mesh
		multi.instance_count = group.size()
		var batch := MultiMeshInstance3D.new()
		batch.name = "StaticArchitectureBatch"
		batch.multimesh = multi
		batch.material_override = first.material_override
		batch.cast_shadow = first.cast_shadow
		batch.visibility_range_end = first.visibility_range_end
		batch.visibility_range_end_margin = 5.0
		add_child(batch)
		batch.global_position = center
		static_visuals.append(batch)
		static_extents.append(first.get_aabb().size.length())
		static_shadows.append(first.cast_shadow)
		for index in group.size():
			var original := group[index] as MeshInstance3D
			multi.set_instance_transform(index, batch.global_transform.affine_inverse() * original.global_transform)
			original.hide()
		batched_mesh_count += group.size()
		batch_count += 1

func _setup_night() -> void:
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.30, 0.39, 0.54)
	environment.ambient_light_energy = 0.38
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.035, 0.052, 0.085)
	environment.fog_light_energy = 0.7
	environment.fog_density = 0.009
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.65
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 0.68
	environment.adjustment_contrast = 1.08
	if environment.sky and environment.sky.sky_material is ProceduralSkyMaterial:
		var sky := environment.sky.sky_material as ProceduralSkyMaterial
		sky.sky_top_color = Color(0.004, 0.008, 0.022)
		sky.sky_horizon_color = Color(0.032, 0.045, 0.067)
		sky.ground_bottom_color = Color(0.003, 0.005, 0.009)
		sky.ground_horizon_color = Color(0.025, 0.032, 0.045)

func apply_quality(value: int, save: bool = true) -> void:
	quality = clampi(value, 0, 2)
	# Night-time micro detail accounts for most baked triangles. Culling it
	# sooner and omitting its shadow pass leaves the buildings and collisions.
	for index in static_visuals.size():
		var visual := static_visuals[index]
		var extent := static_extents[index]
		if extent < 1.0:
			visual.visibility_range_end = [35.0, 45.0, 55.0][quality]
		elif extent < 3.0:
			visual.visibility_range_end = [50.0, 55.0, 55.0][quality]
		else:
			visual.visibility_range_end = 160.0
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if quality == 0 and extent < 1.0 else static_shadows[index]
	var fractions := [0.22, 0.40, 0.75]
	var ranges := [22.0, 32.0, 48.0]
	rendered_instances = 0
	for chunk in foliage_chunks:
		chunk.hide()
		chunk.queue_free()
	foliage_chunks.clear()
	foliage_base_ranges.clear()
	for index in vegetation.size():
		var node := vegetation[index]
		var source := original_multimeshes[index]
		var is_grass := "grass" in node.name.to_lower() or "weed" in node.name.to_lower()
		var ratio: float = fractions[quality] if is_grass else [0.40, 0.65, 1.0][quality]
		var bins: Dictionary = {}
		# Source MultiMeshes span the campus and have their origins at (0,0,0).
		# Split them spatially so distance culling actually follows each patch.
		for item in maxi(1, int(source.instance_count * ratio)):
			var original := mini(source.instance_count - 1, int(float(item) / ratio))
			var origin := source.get_instance_transform(original).origin
			var cell := Vector2i(floori(origin.x / 12.0), floori(origin.z / 12.0))
			if not bins.has(cell):
				bins[cell] = []
			bins[cell].append(original)
		for cell: Vector2i in bins:
			var center := Vector3(cell.x * 12.0 + 6.0, 0.0, cell.y * 12.0 + 6.0)
			var reduced := MultiMesh.new()
			reduced.transform_format = source.transform_format
			reduced.use_colors = source.use_colors
			reduced.use_custom_data = source.use_custom_data
			reduced.mesh = source.mesh
			reduced.instance_count = bins[cell].size()
			for item in reduced.instance_count:
				var original: int = bins[cell][item]
				var instance_transform := source.get_instance_transform(original)
				instance_transform.origin -= center
				reduced.set_instance_transform(item, instance_transform)
				if source.use_colors:
					reduced.set_instance_color(item, source.get_instance_color(original))
				if source.use_custom_data:
					reduced.set_instance_custom_data(item, source.get_instance_custom_data(original))
			var chunk := MultiMeshInstance3D.new()
			chunk.name = "FoliageChunk"
			chunk.multimesh = reduced
			chunk.material_override = node.material_override
			chunk.transform = node.transform * Transform3D(Basis.IDENTITY, center)
			chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var base_range: float = ranges[quality] if is_grass else ranges[quality] * 2.0
			chunk.visibility_range_end = base_range
			chunk.visibility_range_end_margin = 4.0
			node.get_parent().add_child(chunk)
			foliage_chunks.append(chunk)
			foliage_base_ranges.append(base_range)
			rendered_instances += reduced.instance_count
		node.hide()
	for material in surface_materials:
		material.set_shader_parameter("lightweight", quality < 2)
	if environment:
		environment.ssil_enabled = false
		environment.ssao_enabled = quality > 0
		environment.ssao_intensity = 1.1
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if quality == 0 else Viewport.MSAA_2X
	apply_render_distance(render_distance, false)
	if save:
		var config := ConfigFile.new()
		config.load("user://shadowborn_graphics.cfg")
		config.set_value("graphics", "quality", quality)
		config.save("user://shadowborn_graphics.cfg")


func apply_render_distance(value: int, save: bool = true) -> void:
	render_distance = clampi(value, 0, 2)
	var multiplier: float = [0.65, 1.0, 1.5][render_distance]
	for index in static_visuals.size():
		var extent := static_extents[index]
		var base_range := 160.0
		if extent < 1.0:
			base_range = [35.0, 45.0, 55.0][quality]
		elif extent < 3.0:
			base_range = [50.0, 55.0, 55.0][quality]
		static_visuals[index].visibility_range_end = base_range * multiplier
	for index in foliage_chunks.size():
		foliage_chunks[index].visibility_range_end = foliage_base_ranges[index] * multiplier
	if save:
		var config := ConfigFile.new()
		config.load("user://shadowborn_graphics.cfg")
		config.set_value("graphics", "render_distance", render_distance)
		config.save("user://shadowborn_graphics.cfg")
