extends Node3D
## World-sized flame sheets follow the fitted blade or surround the charging body.
## Nothing here changes the sword mount, character rig or combat hitboxes.

const FLAME_SHADER = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float effect_time = 0.0;
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform bool particle_sprite = false;
uniform vec3 flame_axis_world = vec3(0.0, 1.0, 0.0);
instance uniform float seed = 0.0;
varying float particle_phase;
void vertex() {
	particle_phase = 0.0;
	if (particle_sprite) {
		particle_phase = INSTANCE_CUSTOM.y;
		vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
		vec2 up = normalize((VIEW_MATRIX * vec4(flame_axis_world, 0.0)).xy + vec2(0.0, 0.0001));
		MODELVIEW_MATRIX[0] = vec4(up.y * scale.x, -up.x * scale.x, 0.0, 0.0);
		MODELVIEW_MATRIX[1] = vec4(up * scale.y, 0.0, 0.0);
	}
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0,0.0)), f.x),
		mix(hash(i + vec2(0.0,1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void fragment() {
	float y = 1.0 - UV.y;
	float x = UV.x * 2.0 - 1.0;
	float t = effect_time + seed * 13.0 + particle_phase * 2.0;
	float flow = noise(vec2(x * 3.5 + seed * 19.0, y * 5.0 - t * 3.8));
	float fine = noise(vec2(x * 8.0, y * 12.0 - t * 7.0));
	float bend = sin(y * 7.0 - t * 5.0) * 0.16 * y + (flow - 0.5) * 0.48 * y;
	float width = mix(0.92, 0.015, pow(y, 0.75)) * (0.65 + flow * 0.55);
	float shape = smoothstep(0.0, 1.0, clamp(1.0 - abs(x + bend) / max(width, 0.01), 0.0, 1.0));
	float tip = 1.0 - smoothstep(0.65 + flow * 0.12, 1.0, y);
	float intensity = shape * tip * (0.58 + flow * 0.30 + fine * 0.12);
	float core = pow(shape, 3.0) * (1.0 - y) * 0.9;
	vec3 outer = vec3(1.0, 0.07 + heat * 0.10, 0.003);
	vec3 inner = mix(vec3(1.0,0.48,0.035), vec3(1.0,0.96,0.68), heat);
	vec3 flame = mix(outer, inner, core);
	ALBEDO = flame;
	EMISSION = flame * (1.2 + heat * 1.4);
	float fade = particle_sprite ? (1.0 - smoothstep(0.35, 1.0, particle_phase)) : 1.0;
	ALPHA = intensity * opacity * smoothstep(0.0, 0.18, y) * fade;
}
"""
const SHELL_SHADER = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float heat = 0.0;
uniform float opacity = 0.0;
uniform float effect_time = 0.0;
void vertex() { VERTEX += NORMAL * 0.035; }
void fragment() {
	float edge = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	vec3 tint = mix(vec3(1.0,0.16,0.008), vec3(1.0,0.73,0.24), heat);
	ALBEDO = tint;
	EMISSION = tint * (1.2 + heat * 2.0);
	ALPHA = opacity * (0.06 + edge * 0.25) * (0.92 + sin(UV.y * 35.0 - effect_time * 7.0) * 0.08);
}
"""

var controller: Node
var kind := "sword"
var power := 0.0
var visibility_blend := 0.0
var requested_power := 0.0
var requested_active := false
var clock := 0.0
var tongues: Array[MeshInstance3D] = []
var flame_material: ShaderMaterial
var heat_shell: MeshInstance3D
var shell_material: ShaderMaterial
var blade: MeshInstance3D
var handle: MeshInstance3D
var light: OmniLight3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var shader := Shader.new()
	shader.code = FLAME_SHADER
	flame_material = ShaderMaterial.new()
	flame_material.shader = shader
	var count := 18 if kind == "sword" else 40
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for index in range(count):
		var tongue := MeshInstance3D.new()
		tongue.name = "Flame_%02d" % index
		tongue.mesh = quad
		tongue.material_override = flame_material
		tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tongue.set_instance_shader_parameter("seed", float(index) * 0.173)
		add_child(tongue)
		tongues.append(tongue)
	light = OmniLight3D.new()
	light.shadow_enabled = false
	add_child(light)
	if kind == "sword":
		var sword: Node3D = controller.character.get_node("Skeleton3D/RightHandSocket/Sword")
		blade = sword.find_child("BladeLP_DefaultMaterial_0", true, false)
		handle = sword.find_child("HandleLP_DefaultMaterial_0", true, false)
		if blade != null:
			heat_shell = MeshInstance3D.new()
			heat_shell.name = "BladeHeatShell"
			heat_shell.mesh = blade.mesh
			heat_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var shell_shader := Shader.new()
			shell_shader.code = SHELL_SHADER
			shell_material = ShaderMaterial.new()
			shell_material.shader = shell_shader
			heat_shell.material_override = shell_material
			add_child(heat_shell)
	visible = false
	refresh()


func refresh() -> void:
	if not is_instance_valid(controller):
		requested_active = false
		return
	var amount: float = controller.fire_channel_charge if kind == "body" else maxf(controller.fire_meter, controller.fire_channel_charge if controller.is_fire_channeling else 0.0)
	requested_active = controller.is_alive and (controller.is_fire_channeling if kind == "body" else amount > 0.0)
	requested_power = clampf(amount / maxf(controller.fire_meter_max, 1.0), 0.0, 1.0)


func _process(delta: float) -> void:
	refresh()
	clock += delta
	power = move_toward(power, requested_power, delta * 4.0)
	visibility_blend = move_toward(visibility_blend, 1.0 if requested_active else 0.0, delta / 0.12)
	visible = visibility_blend > 0.001
	if not visible:
		return
	flame_material.set_shader_parameter("effect_time", clock)
	flame_material.set_shader_parameter("heat", power)
	flame_material.set_shader_parameter("opacity", visibility_blend * (0.68 if kind == "sword" else 0.46))
	var camera := get_viewport().get_camera_3d()
	if kind == "sword":
		_place_blade_flames(camera)
	else:
		_place_body_flames(camera)
	light.light_color = Color(1.0, 0.25, 0.025).lerp(Color(1.0, 0.78, 0.38), power)
	light.light_energy = visibility_blend * lerpf(0.25, 1.7 if kind == "sword" else 2.5, power)
	light.omni_range = 1.4 if kind == "sword" else 3.0


func _face_camera(tongue: MeshInstance3D, camera: Camera3D) -> void:
	if camera != null:
		var to_camera := camera.global_position - tongue.global_position
		tongue.rotation.y = atan2(to_camera.x, to_camera.z)


func _place_blade_flames(camera: Camera3D) -> void:
	if not is_instance_valid(blade) or not is_instance_valid(handle):
		return
	var grip := handle.global_transform * handle.get_aabb().get_center()
	var axis := -(handle.global_basis * Vector3.BACK).normalized()
	var bounds := blade.get_aabb()
	var near := INF
	var far := -INF
	for corner in range(8):
		var point := blade.global_transform * bounds.get_endpoint(corner)
		var distance := (point - grip).dot(axis)
		near = minf(near, distance)
		far = maxf(far, distance)
	near = maxf(near, 0.065)
	for index in range(tongues.size()):
		var amount := float(index) / float(tongues.size() - 1)
		var tongue := tongues[index]
		var height := lerpf(0.18, 0.64, power) * (0.75 + sin(float(index) * 2.4 + clock * 8.0) * 0.12)
		tongue.global_position = grip + axis * lerpf(near, far, amount) + Vector3.UP * height * 0.42
		_face_camera(tongue, camera)
		tongue.scale = Vector3(lerpf(0.055, 0.19, power), height, 1.0)
	light.global_position = grip + axis * (near + far) * 0.5
	if heat_shell != null:
		heat_shell.global_transform = blade.global_transform
		shell_material.set_shader_parameter("heat", power)
		shell_material.set_shader_parameter("opacity", visibility_blend)
		shell_material.set_shader_parameter("effect_time", clock)


func _place_body_flames(camera: Camera3D) -> void:
	for index in range(tongues.size()):
		var angle := float(index) * 2.399963
		var height := lerpf(0.26, 0.92, power) * (0.75 + sin(clock * 5.0 + float(index)) * 0.12)
		var radius := lerpf(0.21, 0.39, power)
		var base := Vector3(cos(angle) * radius, fposmod(float(index) * 0.618034, 1.0) * 1.58 + 0.03, sin(angle) * radius * 0.7)
		var tongue := tongues[index]
		tongue.global_position = controller.global_position + base + Vector3.UP * height * 0.42
		_face_camera(tongue, camera)
		tongue.scale = Vector3(lerpf(0.11, 0.42, power), height, 1.0)
	light.global_position = controller.global_position + Vector3.UP
