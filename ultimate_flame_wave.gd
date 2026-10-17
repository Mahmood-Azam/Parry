extends MeshInstance3D
## A soft, noisy expanding ground front rather than a solid opaque disk.
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float age = 0.0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1.0,0.0)),f.x),mix(hash(i+vec2(0.0,1.0)),hash(i+vec2(1.0)),f.x),f.y);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y,p.x);
	float front = clamp(age * 1.45, 0.0, 1.0);
	float flow = sin(angle * 23.0 + age * 14.0) * 0.02 + (noise(p * 9.0 + vec2(age * 1.8,-age * 2.0)) - 0.5) * 0.08;
	float wave = exp(-pow((r - front + flow) * 16.0, 2.0));
	float inner = max(1.0-r/max(front,0.01),0.0) * 0.08;
	float fade = 1.0 - smoothstep(0.5,1.25,age);
	vec3 color = mix(vec3(1.0,0.08,0.002),vec3(1.0,0.85,0.25),wave);
	ALBEDO = color;
	EMISSION = color * 2.7;
	ALPHA = (wave * 0.55 + inner) * fade * (1.0-smoothstep(0.94,1.0,r));
}
"""
var radius := 10.0
var elapsed := 0.0
var effect_material: ShaderMaterial
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	mesh = plane
	var shader := Shader.new()
	shader.code = SHADER
	effect_material = ShaderMaterial.new()
	effect_material.shader = shader
	material_override = effect_material
func _process(delta: float) -> void:
	elapsed += delta
	effect_material.set_shader_parameter("age", elapsed)
	if elapsed >= 1.3:
		queue_free()
