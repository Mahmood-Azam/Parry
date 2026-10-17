extends Node3D
## Velocity belongs to this root; only one mesh from the supplied VFX pack is used.
@export var speed: float = 18.0
@export var lifetime: float = 1.2
@export var hit_radius: float = 0.4 ## Contact tolerance around the moving slash plane.
@export var charge_ratio: float = 1.0
var slash_width: float = 0.65
var slash_height: float = 3.8
var slash_depth: float = 1.65

const SLASH_SCENE = preload("res://assets/effects/attack_slashes.glb")
const COMBAT_FX = preload("res://combat_fx.gd")
const FLAME_AURA_SCRIPT = preload("res://flame_aura.gd")
const SLASH_SHADER = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform sampler2D slash_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float heat : hint_range(0.0, 1.0) = 1.0;
uniform float effect_age = 0.0;
void fragment() {
	vec4 sample_color = texture(slash_texture, UV);
	float strength = dot(sample_color.rgb, vec3(0.333333));
	vec3 base = mix(vec3(1.0, 0.055, 0.003), vec3(1.0, 0.79, 0.40), heat);
	vec3 core = mix(vec3(1.0, 0.48, 0.04), vec3(1.0, 0.99, 0.9), heat);
	vec3 flame = mix(base, core, smoothstep(0.6, 0.95, strength));
	float flicker = 0.88 + 0.12 * sin(UV.x * 46.0 - effect_age * 22.0 + UV.y * 9.0);
	ALBEDO = flame;
	EMISSION = flame * (1.1 + heat * 1.3 + strength * 1.2);
	ALPHA = sample_color.a * smoothstep(0.025, 0.30, strength) * opacity * flicker;
}
"""

var direction: Vector3 = Vector3.FORWARD
var velocity: Vector3 = Vector3.FORWARD * 18.0
var damage: float = 0.0
var source_player: Node
var age: float = 0.0
var hit_targets: Array[Node] = []
var visual_root: Node3D
var flame_material: ShaderMaterial
var echo_materials: Array[ShaderMaterial] = []
var embers: GPUParticles3D
var flame_trail: GPUParticles3D
var flame_trail_material: ShaderMaterial
var glow: OmniLight3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	direction = direction.normalized()
	velocity = direction * speed
	charge_ratio = clampf(charge_ratio, 0.0, 1.0)
	slash_width = lerpf(0.28, 0.82, charge_ratio)
	slash_height = lerpf(1.4, 4.6, charge_ratio)
	slash_depth = lerpf(0.65, 2.1, charge_ratio)
	_create_slash_visual()
	_start_effects.call_deferred()


func _physics_process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		_release_trail()
		queue_free()
		return
	var previous_position := global_position
	global_position += velocity * delta
	_animate_visual()
	for candidate in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(candidate) or candidate in hit_targets or not candidate is Node3D:
			continue
		var enemy := candidate as Node3D
		var enemy_center := enemy.global_position + Vector3.UP * 0.85
		if not _intersects_sweep(enemy_center, previous_position, global_position):
			continue
		hit_targets.append(enemy)
		_spawn_impact(enemy_center)
		if enemy.has_method("take_damage"):
			enemy.call("take_damage", damage, source_player)
		if is_instance_valid(enemy) and enemy.has_method("apply_stun"):
			enemy.call("apply_stun", 0.45)
		queue_free()
		return


func _create_slash_visual() -> void:
	visual_root = Node3D.new()
	visual_root.name = "FireSlashVisual"
	# Stand the crescent in the flight/vertical plane, as in the reference:
	# mesh X points up, mesh Y points along travel, mesh Z spans its thickness.
	visual_root.basis = Basis(Vector3.UP, Vector3.BACK, Vector3.RIGHT)
	add_child(visual_root)
	var pack := SLASH_SCENE.instantiate()
	var source_mesh: MeshInstance3D
	for candidate in pack.find_children("*", "MeshInstance3D", true, false):
		if String(candidate.name).contains("_slash_"):
			source_mesh = candidate as MeshInstance3D
			break
	if source_mesh == null:
		pack.free()
		push_error("The supplied attack_slashes.glb has no slash mesh.")
		queue_free()
		return

	# Discard the preview sheet's offsets and rotations. Retain the actual
	# crescent geometry, UVs and transparency mask, then size it in world metres.
	var slash := MeshInstance3D.new()
	slash.name = "ImportedFireSlash"
	slash.mesh = source_mesh.mesh
	slash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = SLASH_SHADER
	flame_material = ShaderMaterial.new()
	flame_material.shader = shader
	var source_material := source_mesh.get_active_material(0) as BaseMaterial3D
	var texture := source_material.albedo_texture if source_material != null else null
	if texture == null:
		texture = load("res://assets/effects/attack_slashes_4.png")
	flame_material.set_shader_parameter("slash_texture", texture)
	flame_material.set_shader_parameter("heat", charge_ratio)
	slash.material_override = flame_material
	var bounds := slash.mesh.get_aabb()
	slash.scale = Vector3(slash_height / maxf(bounds.size.x, 0.001), slash_depth / maxf(bounds.size.y, 0.001), slash_width / maxf(bounds.size.z, 0.001))
	slash.position = -bounds.get_center() * slash.scale
	visual_root.add_child(slash)
	# Offset copies form a short luminous wake without changing the hit volume.
	for index in range(1, 4):
		var echo := MeshInstance3D.new()
		echo.name = "SlashWake%d" % index
		echo.mesh = slash.mesh
		echo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		echo.scale = slash.scale * (1.0 - float(index) * 0.035)
		echo.position = -bounds.get_center() * echo.scale + Vector3(0.0, -float(index) * 0.16, 0.0)
		var echo_material := flame_material.duplicate() as ShaderMaterial
		echo_material.set_shader_parameter("heat", maxf(charge_ratio - float(index) * 0.28, 0.0))
		echo.material_override = echo_material
		echo_materials.append(echo_material)
		visual_root.add_child(echo)
	pack.free()

	glow = OmniLight3D.new()
	glow.name = "FireSlashGlow"
	glow.light_color = Color(1.0, 0.18, 0.015).lerp(Color(1.0, 0.92, 0.75), charge_ratio)
	glow.light_energy = 1.6
	glow.omni_range = 2.5
	visual_root.add_child(glow)
	_create_ember_trail()
	_animate_visual()


func _create_ember_trail() -> void:
	embers = GPUParticles3D.new()
	embers.process_mode = Node.PROCESS_MODE_PAUSABLE
	embers.name = "SlashEmberTrail"
	embers.emitting = false
	embers.amount = roundi(lerpf(24.0, 72.0, charge_ratio))
	embers.lifetime = 0.45
	embers.local_coords = false
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	embers.visibility_aabb = AABB(Vector3(-5.0, -5.0, -30.0), Vector3(10.0, 10.0, 60.0))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.FORWARD
	process.spread = 35.0
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 2.2
	process.gravity = Vector3(0.0, 0.7, 0.0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(slash_width * 0.3, slash_height * 0.42, slash_depth * 0.12)
	process.scale_min = 0.5
	process.scale_max = 1.4
	var ramp := Gradient.new()
	var tint := _heat_color()
	ramp.set_color(0, tint)
	ramp.add_point(0.3, Color(1.0, 0.3, 0.015, 0.8))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.06, 0.005, 0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	embers.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.025, 0.065)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = 2.0
	mesh.material = material
	embers.draw_pass_1 = mesh
	add_child(embers)
	# Soft flame tongues follow the leading crescent rather than filling its
	# empty centre. World-space particles linger briefly behind the moving arc.
	flame_trail = GPUParticles3D.new()
	flame_trail.process_mode = Node.PROCESS_MODE_PAUSABLE
	flame_trail.name = "SlashFlameTrail"
	flame_trail.emitting = false
	flame_trail.amount = roundi(lerpf(36.0, 88.0, charge_ratio))
	flame_trail.lifetime = 0.32
	flame_trail.local_coords = false
	flame_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame_trail.visibility_aabb = embers.visibility_aabb
	var flame_process := process.duplicate() as ParticleProcessMaterial
	flame_process.initial_velocity_min = 0.2
	flame_process.initial_velocity_max = 1.3
	flame_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	var points := Image.create(32, 1, false, Image.FORMAT_RGBF)
	for index in range(32):
		var angle := lerpf(-PI * 0.5, PI * 0.5, float(index) / 31.0)
		points.set_pixel(index, 0, Color(0.0, sin(angle) * slash_height * 0.46, cos(angle) * slash_depth * 0.42))
	flame_process.emission_point_texture = ImageTexture.create_from_image(points)
	flame_process.emission_point_count = 32
	flame_trail.process_material = flame_process
	var flame_mesh := QuadMesh.new()
	flame_mesh.size = Vector2(0.25, 0.5) * lerpf(0.75, 1.4, charge_ratio)
	var flame_shader := Shader.new()
	flame_shader.code = FLAME_AURA_SCRIPT.FLAME_SHADER
	flame_trail_material = ShaderMaterial.new()
	flame_trail_material.shader = flame_shader
	flame_trail_material.set_shader_parameter("particle_sprite", true)
	flame_trail_material.set_shader_parameter("flame_axis_world", Vector3.UP * 0.45 - direction * 0.8)
	flame_trail_material.set_shader_parameter("heat", charge_ratio)
	flame_trail_material.set_shader_parameter("opacity", 0.85)
	flame_mesh.material = flame_trail_material
	flame_trail.draw_pass_1 = flame_mesh
	add_child(flame_trail)


func _heat_color() -> Color:
	return Color(1.0, 0.22, 0.025).lerp(Color(1.0, 0.94, 0.7), charge_ratio)


func _start_effects() -> void:
	if is_queued_for_deletion():
		return
	embers.emitting = true
	flame_trail.emitting = true
	COMBAT_FX.burst(get_tree().current_scene, global_position, _heat_color(), roundi(lerpf(12.0, 28.0, charge_ratio)), 0.6)
	COMBAT_FX.ring(get_tree().current_scene, global_position, _heat_color(), 0.4 + charge_ratio * 0.5, direction)


func _release_trail() -> void:
	for emitter in [embers, flame_trail]:
		if is_instance_valid(emitter):
			emitter.emitting = false
			emitter.reparent(get_tree().current_scene, true)
			get_tree().create_timer(emitter.lifetime + 0.1, false).timeout.connect(emitter.queue_free)
	embers = null
	flame_trail = null


func _spawn_impact(impact_position: Vector3) -> void:
	COMBAT_FX.burst(get_tree().current_scene, impact_position, _heat_color(), roundi(lerpf(28.0, 64.0, charge_ratio)), 0.8 + charge_ratio * 0.5)
	COMBAT_FX.ring(get_tree().current_scene, impact_position, _heat_color(), 0.65 + charge_ratio, direction)
	if is_instance_valid(source_player) and source_player.has_method("_add_camera_trauma"):
		source_player.call("_add_camera_trauma", 0.12 + charge_ratio * 0.12)
		if source_player.has_method("_show_combat_feedback"):
			source_player.call("_show_combat_feedback", "FIRE HIT", _heat_color())
	_release_trail()


func _animate_visual() -> void:
	if visual_root == null or flame_material == null:
		return
	var fade_in := clampf(age / 0.045, 0.0, 1.0)
	var fade_out := clampf((lifetime - age) / 0.18, 0.0, 1.0)
	flame_material.set_shader_parameter("opacity", fade_in * fade_out)
	flame_material.set_shader_parameter("effect_age", age)
	if flame_trail_material != null:
		flame_trail_material.set_shader_parameter("effect_time", age)
	for index in range(echo_materials.size()):
		echo_materials[index].set_shader_parameter("opacity", fade_in * fade_out * 0.22 / float(index + 1))
		echo_materials[index].set_shader_parameter("effect_age", age)
	if is_instance_valid(glow):
		glow.light_energy = (1.4 + charge_ratio * 1.1) * fade_in * fade_out * (0.95 + sin(age * 28.0) * 0.05)


func _intersects_sweep(point: Vector3, segment_start: Vector3, segment_end: Vector3) -> bool:
	# A wide moving plane catches targets beside its centre without damaging
	# targets metres ahead of the visible effect, as a large sphere would.
	var along := (point - segment_start).dot(direction)
	var travel := segment_start.distance_to(segment_end)
	var contact_depth := slash_depth * 0.5 + hit_radius
	if along < -contact_depth or along > travel + contact_depth:
		return false
	var closest := segment_start + direction * clampf(along, 0.0, travel)
	var offset := point - closest
	var sideways := direction.cross(Vector3.UP).normalized()
	return absf(offset.dot(sideways)) <= slash_width * 0.5 + hit_radius and absf(offset.y) <= slash_height * 0.5 + hit_radius
