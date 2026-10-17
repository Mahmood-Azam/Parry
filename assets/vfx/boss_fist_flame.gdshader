shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform sampler2D flow_texture : repeat_enable, filter_linear_mipmap;
uniform float effect_time = 0.0;
uniform float attack_pulse = 0.0;
uniform float opacity = 1.0;
uniform float phase = 0.0;
uniform vec3 dark_color = vec3(0.20, 0.004, 0.018);
uniform vec3 flame_color = vec3(0.82, 0.012, 0.045);
uniform vec3 hot_color = vec3(1.0, 0.075, 0.085);

float flow(vec2 uv) {
	return texture(flow_texture, uv).r;
}

void vertex() {
	float t = effect_time;
	float wave = sin(UV.x * 31.4 + UV.y * 14.0 + t * 5.5 + phase);
	wave += sin(UV.x * 68.0 - UV.y * 29.0 - t * 7.2) * 0.36;
	VERTEX += NORMAL * wave * (0.045 + attack_pulse * 0.035);
	VERTEX.y += max(0.0, UV.y - 0.35) * wave * 0.085;
}

void fragment() {
	float t = effect_time;
	vec2 drift = UV * vec2(2.4, 2.0) + vec2(t * 0.17, -t * 0.41);
	float broad = flow(drift + vec2(phase * 0.11));
	float detail = flow(UV * vec2(5.1, 4.2) + vec2(-t * 0.32, -t * 0.68));
	float tongues = flow(UV * vec2(3.2, 2.6) + vec2(t * 0.24, -t * 0.95));
	float turbulence = broad * 0.43 + detail * 0.30 + tongues * 0.40;
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float flicker = 0.86 + 0.14 * sin(t * 13.0 + phase + UV.x * 18.0);
	float body = smoothstep(0.43, 0.72, turbulence) * (0.28 + rim * 0.72);
	float bright = smoothstep(0.65, 0.91, turbulence) * (0.35 + rim * 0.65);
	vec3 color = mix(dark_color, flame_color, smoothstep(0.35, 0.77, turbulence));
	color = mix(color, hot_color, bright * 0.70);
	ALBEDO = color;
	EMISSION = color * (2.5 + bright * 3.2 + attack_pulse * 1.3);
	ALPHA = clamp((body * 0.68 + bright * 0.24) * flicker * opacity, 0.0, 0.78);
}
