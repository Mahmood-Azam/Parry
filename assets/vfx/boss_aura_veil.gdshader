shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D flow_texture : repeat_enable, filter_linear_mipmap;
uniform float effect_time = 0.0;
uniform float attack_pulse = 0.0;
uniform float opacity = 1.0;

vec2 seamless_uv(vec2 p) {
	return 1.0 - abs(fract(p * 0.5) * 2.0 - 1.0);
}

float flow(vec2 p) {
	return texture(flow_texture, seamless_uv(p)).r;
}

void vertex() {
	float wave = sin(UV.x * 18.849556 + UV.y * 9.0 - effect_time * 2.3);
	wave += sin(UV.x * 43.982296 - UV.y * 13.0 + effect_time * 3.2) * 0.45;
	VERTEX.xz *= 1.0 + wave * (0.026 + UV.y * 0.035);
}

void fragment() {
	float t = effect_time;
	vec2 rising = UV * vec2(2.0, 1.65) + vec2(t * 0.08, -t * 0.20);
	float broad = flow(rising);
	float detail = flow(UV * vec2(4.0, 3.4) + vec2(-t * 0.12, -t * 0.34));
	float filaments = smoothstep(0.31, 0.68, broad * 0.66 + detail * 0.54);
	float broken_edge = smoothstep(0.22, 0.65, detail);
	float flame_height = 0.59 + broad * 0.24 + sin(UV.x * 31.415926 + t * 1.4) * 0.08;
	float height_fade = 1.0 - smoothstep(flame_height - 0.29, flame_height, UV.y);
	float root = 1.0 - smoothstep(0.0, 0.54, UV.y);
	float smoke = smoothstep(0.20, 0.61, broad) * height_fade;
	float hot_core = filaments * broken_edge * root;
	vec3 purple = vec3(0.23, 0.035, 0.28);
	vec3 crimson = vec3(0.48, 0.015, 0.055);
	vec3 orange = vec3(1.0, 0.29, 0.035);
	vec3 color = mix(purple, crimson, filaments);
	color = mix(color, orange, max(hot_core * 0.9, filaments * 0.53));
	float alpha = (filaments * (0.23 + root * 0.30) + smoke * 0.075) * height_fade * opacity;
	ALBEDO = color;
	EMISSION = color * (2.4 + hot_core * 2.2 + attack_pulse * 1.3);
	ALPHA = clamp(alpha, 0.0, 0.64);
}
