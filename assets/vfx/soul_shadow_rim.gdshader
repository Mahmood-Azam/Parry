shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.8);
	float threads = 0.65 + 0.35 * sin(UV.y * 34.0 - TIME * 8.0 + sin(UV.x * 21.0) * 1.4);
	float pulse = 0.86 + 0.14 * sin(TIME * 11.0);
	vec3 violet = mix(vec3(0.18, 0.025, 0.48), vec3(0.60, 0.14, 1.0), threads);
	ALBEDO = violet;
	EMISSION = violet * (2.5 + threads * 1.5) * pulse;
	ALPHA = clamp(rim * (0.38 + threads * 0.28), 0.0, 0.72);
}
