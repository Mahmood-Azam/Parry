shader_type canvas_item;
render_mode unshaded;
uniform float menu_time = 0.0;
uniform float aspect = 1.77778;
uniform float hover_heat = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float result = 0.0;
	float amplitude = 0.55;
	for (int i = 0; i < 4; i++) {
		result += noise(p) * amplitude;
		p = p * 2.03 + vec2(12.1, 7.7);
		amplitude *= 0.5;
	}
	return result;
}
void fragment() {
	float t = menu_time;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float flame = 0.0;
	float core = 0.0;
	if (p.y < 0.48) {
		float bend = noise(vec2(p.x * 3.0, t * 0.35)) - 0.5;
		vec2 flow = vec2(p.x * 11.0 + bend * p.y * 4.0 + sin(p.y * 16.0 - t * 1.2) * p.y * 1.8, p.y * 4.0 - t * 1.7);
		float fuel = fbm(flow);
		float height = 0.17 + 0.15 * smoothstep(0.25, 0.95, UV.x) + hover_heat * 0.035;
		float density = fuel * 1.65 - p.y / height;
		flame = smoothstep(0.08, 0.58, density) * (1.0 - smoothstep(0.30, 0.47, p.y));
		core = smoothstep(0.49, 1.10, density);
	}
	// A separate sideways flow wraps around the right edge, not a rigid curtain.
	float side = 0.0;
	if (UV.x > 0.88) {
		float edge_flow = fbm(vec2(UV.y * 8.0 - t * 0.4, (1.0 - UV.x) * 22.0 - t));
		side = smoothstep(0.30, 0.82, edge_flow - (1.0 - UV.x) * 5.0) * 0.62;
	}
	flame = max(flame, side);
	vec3 fire = mix(vec3(0.78, 0.065, 0.005), vec3(1.0, 0.40, 0.025), smoothstep(0.1, 0.7, flame));
	fire = mix(fire, vec3(1.0, 0.85, 0.41), core);
	float smoke = noise(vec2(p.x * 3.0 + t * 0.035, p.y * 5.0 - t * 0.10));
	float haze = smoothstep(0.42, 0.85, smoke) * 0.105 * (1.0 - smoothstep(0.3, 0.9, p.y));
	float readable = mix(0.32, 1.0, smoothstep(0.22, 0.53, UV.x));
	float alpha = max(flame * 0.87, haze) * readable;
	COLOR = vec4(mix(vec3(0.22, 0.20, 0.28), fire, smoothstep(0.0, 0.12, flame)), alpha);
}
