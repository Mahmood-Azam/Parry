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

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float t = effect_time;
	float broad = flow(p * 1.35 + vec2(t * 0.09, -t * 0.07));
	float fine = flow(p * 3.2 + vec2(-t * 0.15, t * 0.12));
	float curl = sin(angle * 7.0 - t * 2.2) * 0.044 + sin(angle * 13.0 + t * 1.4) * 0.026;
	float center = 0.64 + (broad - 0.5) * 0.22 + curl;
	float width = 0.11 + fine * 0.085 + attack_pulse * 0.035;
	float distance_to_fire = abs(r - center);
	float body = 1.0 - smoothstep(width * 0.38, width, distance_to_fire);
	float tongues = smoothstep(0.48, 0.79, fine) * (1.0 - smoothstep(width * 0.7, width * 2.3, distance_to_fire));
	float smoke = (1.0 - smoothstep(width * 1.0, width * 2.5, distance_to_fire)) * broad;
	float hole = smoothstep(0.30, 0.48, r);
	float edge = 1.0 - smoothstep(0.87, 0.99, r);
	float core = pow(1.0 - smoothstep(0.0, width * 0.46, distance_to_fire), 2.0);
	vec3 crimson = vec3(0.34, 0.012, 0.055);
	vec3 orange = vec3(1.0, 0.27, 0.035);
	vec3 hot = vec3(1.0, 0.58, 0.10);
	vec3 purple = vec3(0.15, 0.025, 0.24);
	vec3 color = mix(purple, crimson, clamp(body + tongues * 0.3, 0.0, 1.0));
	color = mix(color, orange, clamp(body * 0.75 + tongues * 0.4, 0.0, 1.0));
	color = mix(color, hot, core * 0.82);
	float alpha = (body * 0.76 + tongues * 0.40 + smoke * 0.17) * hole * edge * opacity;
	ALBEDO = color;
	EMISSION = color * (1.9 + core * 2.0 + attack_pulse * 1.4);
	ALPHA = clamp(alpha, 0.0, 0.95);
}
