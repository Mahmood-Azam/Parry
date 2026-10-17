extends Node3D
## A continuous, flowing power-up aura rather than separate rigid flame cards.

const COMBAT_FX = preload("res://combat_fx.gd")
const SHELL_SHADER = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float effect_time = 0.0;
uniform float heat = 0.0;
uniform float opacity = 0.0;
uniform float phase_offset = 0.0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0)),f.x),f.y);
}
void fragment() {
	float t=effect_time+phase_offset;
	float y=1.0-UV.y;
	float x=UV.x*2.0-1.0;
	float n=noise(vec2(x*5.0+phase_offset,y*9.0-t*4.0));
	float fine=noise(vec2(x*15.0,y*22.0-t*9.0));
	float profile=pow(max(sin(y*3.14159),0.0),0.62)*0.72;
	float flow=(n-0.5)*(0.20+heat*0.16)+sin(y*14.0-t*7.0)*0.045;
	float distance=abs(x)-profile-flow;
	float contour=exp(-abs(distance)*17.0);
	float filaments=pow(0.5+0.5*sin(x*43.0+y*18.0-t*11.0+n*5.0),7.0);
	float halo=exp(-abs(distance)*7.0)*0.12;
	float ends=smoothstep(0.0,0.07,y)*(1.0-smoothstep(0.94,1.0,y));
	float stream=contour*(0.20+n*0.55+fine*0.30)+halo+filaments*exp(-abs(distance)*9.0)*0.24;
	vec3 gold=mix(vec3(1.0,0.28,0.012),vec3(1.0,0.75,0.08),heat);
	vec3 color=mix(gold,vec3(1.0,0.97,0.58),contour*fine*(0.35+heat*0.35));
	ALBEDO=color;
	EMISSION=color*(1.4+heat*1.2);
	ALPHA=opacity*stream*ends*(1.0-smoothstep(0.84,1.0,abs(x)));
}
"""
const WISP_SHADER = """
shader_type spatial;
render_mode unshaded,cull_disabled,blend_add,depth_draw_never;
uniform float effect_time=0.0;
uniform float heat=0.0;
uniform float opacity=0.0;
instance uniform float seed=0.0;
instance uniform float life=0.0;
void fragment() {
	float y=1.0-UV.y;
	float x=(UV.x-0.5)*2.0;
	float bend=sin(y*10.0-effect_time*8.0+seed*20.0)*0.42;
	float line=exp(-pow((x-bend)*3.0,2.0));
	float ends=sin(y*3.14159);
	float fade=smoothstep(0.0,0.16,life)*(1.0-smoothstep(0.7,1.0,life));
	vec3 color=mix(vec3(1.0,0.46,0.02),vec3(1.0,0.96,0.48),heat);
	ALBEDO=color;
	EMISSION=color*(1.6+heat);
	ALPHA=line*ends*fade*opacity*(1.0-smoothstep(0.78,1.0,abs(x)));
}
"""

var controller: Node
var power := 0.0
var visibility_blend := 0.0
var requested_active := false
var requested_power := 0.0
var clock := 0.0
var ripple_time := 0.0
var shells: Array[MeshInstance3D] = []
var materials: Array[ShaderMaterial] = []
var wisps: Array[MeshInstance3D] = []
var wisp_material: ShaderMaterial
var streaks: GPUParticles3D
var light: OmniLight3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var shader := Shader.new()
	shader.code = SHELL_SHADER
	var envelope := QuadMesh.new()
	envelope.size = Vector2.ONE
	for index in range(2):
		var shell := MeshInstance3D.new()
		shell.name = "EnergyEnvelope%d" % index
		shell.mesh = envelope
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("phase_offset", float(index) * 2.3)
		shell.material_override = material
		materials.append(material)
		shells.append(shell)
		add_child(shell)
	var ribbon_shader := Shader.new()
	ribbon_shader.code = WISP_SHADER
	wisp_material = ShaderMaterial.new()
	wisp_material.shader = ribbon_shader
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for index in range(14):
		var wisp := MeshInstance3D.new()
		wisp.name = "RisingEnergy%d" % index
		wisp.mesh = quad
		wisp.material_override = wisp_material
		wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wisp.set_instance_shader_parameter("seed", float(index) * 0.731)
		wisps.append(wisp)
		add_child(wisp)
	_create_streaks()
	light = OmniLight3D.new()
	light.light_color = Color(1.0,0.62,0.08)
	light.omni_range = 3.2
	add_child(light)
	visible = false


func refresh() -> void:
	requested_active = is_instance_valid(controller) and controller.is_alive and (controller.is_fire_channeling or controller.is_using_ultimate)
	requested_power = (controller.ultimate_power if controller.is_using_ultimate else clampf(controller.fire_channel_charge / maxf(controller.fire_meter_max,1.0),0.0,1.0)) if requested_active else 0.0


func _process(delta: float) -> void:
	refresh()
	clock += delta
	power = move_toward(power,requested_power,delta*4.0)
	visibility_blend = move_toward(visibility_blend,1.0 if requested_active else 0.0,delta/0.14)
	visible = visibility_blend > 0.001
	streaks.emitting = requested_active
	if not visible:
		return
	var pulse := 1.0 + sin(clock*10.0)*lerpf(0.015,0.045,power)
	var height := lerpf(2.4,3.15,power)
	var radius := lerpf(0.52,0.88,power)*pulse
	var camera := get_viewport().get_camera_3d()
	for index in range(shells.size()):
		var shell := shells[index]
		var layer_scale := 1.0-float(index)*0.15
		shell.global_position = controller.global_position + Vector3.UP*(height*0.5+0.02)
		if camera != null:
			var toward := camera.global_position-shell.global_position
			shell.rotation.y = atan2(toward.x,toward.z)
		shell.scale = Vector3(radius*2.7*layer_scale,height,1.0)
		materials[index].set_shader_parameter("effect_time",clock)
		materials[index].set_shader_parameter("heat",power)
		materials[index].set_shader_parameter("opacity",visibility_blend*(0.4+power*0.20)*(1.0-float(index)*0.25))
	wisp_material.set_shader_parameter("effect_time",clock)
	wisp_material.set_shader_parameter("heat",power)
	wisp_material.set_shader_parameter("opacity",visibility_blend*0.72)
	for index in range(wisps.size()):
		var phase := fposmod(clock*(0.65+power*0.35)+float(index)*0.618034,1.0)
		var angle := float(index)*2.39996 + clock*(0.3+power*0.4)
		var wisp := wisps[index]
		wisp.global_position = controller.global_position + Vector3(cos(angle)*radius*0.78,0.14+phase*(height-0.3),sin(angle)*radius*0.65)
		if camera != null:
			var toward := camera.global_position-wisp.global_position
			wisp.rotation.y = atan2(toward.x,toward.z)
		wisp.scale = Vector3(0.16+power*0.12,0.55+power*0.42,1.0)
		wisp.set_instance_shader_parameter("life",phase)
	streaks.global_position = controller.global_position+Vector3.UP*0.12
	streaks.amount_ratio = lerpf(0.25,1.0,power)*visibility_blend
	light.global_position = controller.global_position+Vector3.UP
	light.light_energy = visibility_blend*(0.35+power*1.5)*pulse
	ripple_time += delta
	if ripple_time > 0.7 and power > 0.25:
		ripple_time = 0.0
		COMBAT_FX.ring(get_tree().current_scene,controller.global_position+Vector3.UP*0.035,Color(1.0,0.65,0.08,0.22),radius*1.3)


func _create_streaks() -> void:
	streaks = GPUParticles3D.new()
	streaks.name = "UpwardEnergyStreaks"
	streaks.emitting = false
	streaks.amount = 72
	streaks.lifetime = 0.55
	streaks.local_coords = false
	streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streaks.visibility_aabb = AABB(Vector3(-2.0,0.0,-2.0),Vector3(4.0,5.0,4.0))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 2.2
	process.initial_velocity_max = 4.0
	process.gravity = Vector3(0.0,1.0,0.0)
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.48,0.04,0.38)
	process.scale_min = 0.5
	process.scale_max = 1.2
	var gradient := Gradient.new()
	gradient.set_color(0,Color(1.0,0.8,0.18,0.0))
	gradient.add_point(0.18,Color(1.0,0.88,0.35,0.8))
	gradient.set_color(gradient.get_point_count()-1,Color(1.0,0.5,0.04,0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	streaks.process_material = process
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.012,0.24)
	mesh.material = material
	streaks.draw_pass_1 = mesh
	add_child(streaks)
