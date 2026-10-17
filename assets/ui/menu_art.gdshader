shader_type canvas_item;
render_mode unshaded;
uniform float menu_time = 0.0;
uniform vec2 parallax = vec2(0.0);

void fragment() {
	vec2 uv = (UV - 0.5) * 0.965 + 0.5 + parallax * 0.009;
	uv += vec2(sin(menu_time * 0.12), cos(menu_time * 0.09)) * 0.0015;
	vec3 art = texture(TEXTURE, uv).rgb;
	float flicker = 0.75 + 0.16 * sin(menu_time * 3.1) + 0.09 * sin(menu_time * 7.3);
	float warmth = exp(-length((UV - vec2(0.68, 0.88)) * vec2(1.6, 2.0)) * 3.5);
	art += vec3(0.19, 0.053, 0.008) * warmth * flicker;
	float shadow_glow = exp(-length((UV - vec2(0.81, 0.40)) * vec2(2.0, 1.0)) * 5.0);
	art += vec3(0.025, 0.008, 0.065) * shadow_glow * (0.6 + 0.4 * sin(menu_time * 0.65));
	float vignette = smoothstep(0.28, 0.88, length((UV - 0.5) * vec2(1.05, 0.85)));
	art *= 1.0 - vignette * 0.4;
	COLOR = vec4(art, 1.0);
}
