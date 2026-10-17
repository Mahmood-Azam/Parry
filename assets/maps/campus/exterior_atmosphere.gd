extends Node3D
## Small outdoor fog pockets and a few animated fixtures. No collision or shadows.

var fog_layers: Array[Dictionary] = []
var lamps: Array[Dictionary] = []
var cameras: Array[Dictionary] = []
var clock := 0.0
var daylight_progress := 0.0
var metal: StandardMaterial3D
var lamp_glass: StandardMaterial3D
var camera_glass: StandardMaterial3D
var spark_material: StandardMaterial3D
var spark_shape: SphereMesh


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	metal = _surface(Color(0.10, 0.12, 0.16), false)
	lamp_glass = _surface(Color(1.0, 0.74, 0.37), true)
	camera_glass = _surface(Color(0.44, 0.74, 1.0), true)
	spark_material = _surface(Color(1.0, 0.56, 0.16), true)
	spark_shape = SphereMesh.new()
	spark_shape.radius = 0.025
	spark_shape.height = 0.05
	_add_fog("CourtyardMist", Vector3(33.0, 1.8, -74.0), Vector3(24.0, 5.0, 22.0), 0.055)
	_add_fog("RearCourtMist", Vector3(50.0, 2.0, -114.0), Vector3(24.0, 5.5, 24.0), 0.055)
	_add_fog("RoofMist", Vector3(48.0, 8.4, -84.0), Vector3(23.0, 7.0, 32.0), 0.068)
	_add_fog("ABlockMist", Vector3(0.0, 1.6, -7.0), Vector3(20.0, 4.5, 20.0), 0.045)
	_add_streetlight("CourtyardLamp", Vector3(28.0, 0.0, -73.0), false)
	_add_streetlight("FlickeringStreetlight", Vector3(39.0, 0.0, -78.0), true)
	_add_streetlight("RearCourtLamp", Vector3(55.0, 0.0, -111.0), false)
	_add_cctv("WestCCTV", Vector3(41.0, 3.5, -74.0), -PI * 0.5, 0.0)
	_add_cctv("EastCCTV", Vector3(55.0, 3.5, -94.0), PI * 0.5, 2.4)


func _surface(color: Color, glowing: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.35 if not glowing else 0.0
	material.roughness = 0.48
	if glowing:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.5
	return material


func _mesh(parent: Node3D, name: String, shape: Mesh, offset: Vector3, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = name
	visual.mesh = shape
	visual.position = offset
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = 70.0
	parent.add_child(visual)
	return visual


func _box(size: Vector3) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	return box


func _add_fog(name: String, center: Vector3, size: Vector3, density: float) -> void:
	var volume := FogVolume.new()
	volume.name = name
	volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	volume.size = size
	volume.position = center
	var material := FogMaterial.new()
	material.albedo = Color(0.72, 0.79, 0.89)
	material.emission = Color(0.025, 0.035, 0.055)
	material.density = density
	volume.material = material
	add_child(volume)
	fog_layers.append({"material": material, "density": density})


func _add_streetlight(name: String, place: Vector3, faulty: bool) -> void:
	var fixture := Node3D.new()
	fixture.name = name
	fixture.position = place
	add_child(fixture)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.055
	pole.bottom_radius = 0.085
	pole.height = 4.2
	_mesh(fixture, "Pole", pole, Vector3.UP * 2.1, metal)
	_mesh(fixture, "Arm", _box(Vector3(0.94, 0.08, 0.10)), Vector3(0.43, 4.18, 0.0), metal)
	_mesh(fixture, "LampHousing", _box(Vector3(0.48, 0.17, 0.34)), Vector3(0.85, 4.1, 0.0), metal)
	var glow := _mesh(fixture, "LampGlass", _box(Vector3(0.38, 0.035, 0.26)), Vector3(0.85, 4.0, 0.0), lamp_glass)
	var beam := SpotLight3D.new()
	beam.name = "GroundBeam"
	beam.position = Vector3(0.85, 3.99, 0.0)
	beam.rotation.x = -PI * 0.5
	beam.light_color = Color(1.0, 0.68, 0.34)
	beam.light_energy = 2.3
	beam.light_volumetric_fog_energy = 1.2
	beam.spot_range = 12.0
	beam.spot_angle = 53.0
	beam.shadow_enabled = false
	fixture.add_child(beam)
	lamps.append({"fixture": fixture, "beam": beam, "glow": glow, "faulty": faulty, "last_spark_cycle": -1})


func _add_cctv(name: String, place: Vector3, base_yaw: float, phase: float) -> void:
	var mount := Node3D.new()
	mount.name = name
	mount.position = place
	add_child(mount)
	_mesh(mount, "WallBracket", _box(Vector3(0.12, 0.18, 0.72)), Vector3(0.0, 0.0, -0.18), metal)
	var pivot := Node3D.new()
	pivot.name = "ScanningHead"
	pivot.position.z = -0.48
	mount.add_child(pivot)
	_mesh(pivot, "CameraHousing", _box(Vector3(0.43, 0.25, 0.53)), Vector3(0.0, 0.0, -0.20), metal)
	var lens := CylinderMesh.new()
	lens.top_radius = 0.055
	lens.bottom_radius = 0.065
	lens.height = 0.055
	var glass := _mesh(pivot, "CameraLens", lens, Vector3(0.0, 0.0, -0.5), camera_glass)
	glass.rotation.x = PI * 0.5
	var beam := SpotLight3D.new()
	beam.name = "ScanningBeam"
	beam.position.z = -0.52
	beam.light_color = Color(0.47, 0.72, 1.0)
	beam.light_energy = 0.65
	beam.light_volumetric_fog_energy = 0.55
	beam.spot_range = 15.0
	beam.spot_angle = 24.0
	beam.shadow_enabled = false
	pivot.add_child(beam)
	var status := _mesh(pivot, "RecordingLED", _box(Vector3(0.045, 0.045, 0.03)), Vector3(0.13, 0.08, -0.49), _surface(Color(0.95, 0.08, 0.08), true))
	cameras.append({"pivot": pivot, "beam": beam, "status": status, "yaw": base_yaw, "phase": phase})


func set_daylight_progress(value: float) -> void:
	daylight_progress = clampf(value, 0.0, 1.0)
	for layer in fog_layers:
		(layer["material"] as FogMaterial).density = layer["density"] * (1.0 - daylight_progress)


func _process(delta: float) -> void:
	clock += delta
	var night := 1.0 - daylight_progress
	for lamp in lamps:
		var faulty: bool = lamp["faulty"]
		var cycle := floori(clock / 6.4)
		var beat := fmod(clock, 6.4)
		var blink := faulty and (beat < 0.11 or (beat > 0.20 and beat < 0.27))
		var beam: SpotLight3D = lamp["beam"]
		beam.light_energy = 2.3 * night * (0.07 if blink else 0.91 + sin(clock * 3.1) * 0.09)
		(lamp["glow"] as MeshInstance3D).visible = night > 0.05 and not blink
		if faulty and night > 0.1 and beat < 0.11 and cycle != lamp["last_spark_cycle"]:
			lamp["last_spark_cycle"] = cycle
			_spark(lamp["fixture"] as Node3D)
	for camera in cameras:
		var pivot: Node3D = camera["pivot"]
		var phase: float = camera["phase"]
		pivot.rotation.y = camera["yaw"] + sin(clock * 0.65 + phase) * 0.72
		(camera["beam"] as SpotLight3D).light_energy = 0.65 * night
		(camera["status"] as MeshInstance3D).visible = night > 0.1 and fmod(clock + phase, 1.5) < 1.1


func _spark(fixture: Node3D) -> void:
	var origin := to_local(fixture.global_position + Vector3(0.85, 4.0, 0.0))
	for index in 6:
		var mote := _mesh(self, "StreetlightSpark", spark_shape, origin, spark_material)
		var angle := TAU * float(index) / 6.0
		var travel := Vector3(cos(angle) * 0.5, -randf_range(0.25, 0.8), sin(angle) * 0.5)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(mote, "position", origin + travel, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(mote, "transparency", 1.0, 0.32)
		tween.chain().tween_callback(mote.queue_free)
