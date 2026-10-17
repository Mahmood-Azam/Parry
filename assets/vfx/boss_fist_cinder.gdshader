shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform sampler2D flow_texture : repeat_enable, filter_linear_mipmap;
uniform vec3 dark_color = vec3(0.22, 0.003, 0.022);
uniform vec3 flame_color = vec3(0.96, 0.018, 0.055);

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float height = 1.0 - UV.y;
	float noise = texture(flow_texture, UV * vec2(1.7, 1.3) + vec2(TIME * 0.21, -TIME * 0.39)).r;
	float sway = sin(height * 9.0 + TIME * 5.2) * 0.13 + (noise - 0.5) * 0.24;
	float width = mix(0.46, 0.035, pow(height, 0.75)) * (0.78 + noise * 0.42);
	float shape = 1.0 - smoothstep(width * 0.65, width, abs(centered.x - sway));
	shape *= smoothstep(0.0, 0.16, height) * (1.0 - smoothstep(0.92, 1.0, height));
	float filament = smoothstep(0.34, 0.80, noise);
	vec3 color = mix(dark_color, flame_color, filament * 0.9 + height * 0.20);
	ALBEDO = color;
	EMISSION = color * (2.4 + filament * 2.0);
	ALPHA = shape * (0.20 + filament * 0.52) * COLOR.a;
}
