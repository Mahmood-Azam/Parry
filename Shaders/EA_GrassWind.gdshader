// EmacEArt Stylized Grass - a Godot 4 port of the URP shader "EmacEArt/StylizedGrass".
//
// Matches the original one to one: three-layer wind anchored at the root, a two-layer
// procedural tint (blob or stripes mode, each with its own set of parameters), and
// foliage shading (normal biased toward world up + additive ambient lift).
//
// Group names and parameter order follow the [Header(...)] sections from Unity, so the
// Godot inspector panel lines up with the Unity one side by side.
//
// DIFFERENCES FROM UNITY - deliberate, listed here so nobody "fixes" them:
//   * Gust: Unity samples the _GustNoise texture. In the package materials that texture
//     is empty (None), so Unity reads white and the gust ends up CONSTANT. Here the
//     noise is generated procedurally by default (looks better, no texture dependency);
//     plug a texture into gust_noise if you want Unity's exact behaviour.
//   * With cull_disabled Godot already flips the normal on back faces, so there is no
//     equivalent of multiplying by VFACE - adding one would flip it a second time.
//   * Unity's additive ambient lift (color.rgb += albedo * tint * lift) is done through
//     EMISSION: Godot gives no access to the lighting result inside the fragment shader,
//     and EMISSION adds to the final color in exactly the same way.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

group_uniforms Base;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.4;

group_uniforms Normal;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;

group_uniforms PBR;
uniform float smoothness : hint_range(0.0, 1.0) = 0.2;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

group_uniforms Wind;
uniform float wind_strength : hint_range(0.0, 2.0) = 0.15;
uniform float wind_speed : hint_range(0.0, 10.0) = 1.5;
uniform float wind_frequency : hint_range(0.0, 5.0) = 0.5;
uniform float wind_direction_x : hint_range(-1.0, 1.0) = 1.0;
uniform float wind_direction_z : hint_range(-1.0, 1.0) = 0.0;
// Model height in local units. Unity assumes 1.0 (saturate(y)); change this only if the
// clump is noticeably taller and should bend along its whole length.
uniform float anchor_height : hint_range(0.05, 10.0) = 1.0;

group_uniforms Gust;
// Empty = procedural noise. Plug a texture in to get Unity's behaviour.
uniform sampler2D gust_noise : hint_default_white, filter_linear, repeat_enable;
uniform bool gust_use_texture = false;
uniform float gust_strength : hint_range(0.0, 2.0) = 0.5;
uniform float gust_scale : hint_range(0.0, 1.0) = 0.05;
uniform float gust_speed : hint_range(0.0, 5.0) = 0.4;

group_uniforms Tint_Small;
uniform vec4 tint_color_small : source_color = vec4(1.0, 0.62, 0.05, 1.0);
uniform bool stripes_mode_small = false;
group_uniforms Tint_Small.Blob;
uniform float tint_scale_small_blob : hint_range(0.01, 1.0) = 0.814;
uniform float tint_intensity_small_blob : hint_range(0.0, 1.0) = 0.928;
uniform float tint_width_small_blob : hint_range(0.0, 1.0) = 0.867;
uniform float tint_speed_small_blob : hint_range(0.0, 2.0) = 0.806;
group_uniforms Tint_Small.Stripes;
uniform float tint_scale_small_stripes : hint_range(0.01, 1.0) = 0.814;
uniform float tint_intensity_small_stripes : hint_range(0.0, 1.0) = 0.928;
uniform float tint_width_small_stripes : hint_range(0.0, 1.0) = 0.867;
uniform float tint_speed_small_stripes : hint_range(0.0, 2.0) = 0.806;

group_uniforms Tint_Large;
uniform vec4 tint_color_large : source_color = vec4(0.32, 0.62, 0.55, 1.0);
uniform bool stripes_mode_large = true;
group_uniforms Tint_Large.Blob;
uniform float tint_scale_large_blob : hint_range(0.005, 0.3) = 0.265;
uniform float tint_intensity_large_blob : hint_range(0.0, 1.0) = 0.706;
uniform float tint_width_large_blob : hint_range(0.0, 1.0) = 0.846;
uniform float tint_speed_large_blob : hint_range(0.0, 2.0) = 0.534;
group_uniforms Tint_Large.Stripes;
uniform float tint_scale_large_stripes : hint_range(0.005, 0.3) = 0.265;
uniform float tint_intensity_large_stripes : hint_range(0.0, 1.0) = 0.706;
uniform float tint_width_large_stripes : hint_range(0.0, 1.0) = 0.846;
uniform float tint_speed_large_stripes : hint_range(0.0, 2.0) = 0.534;

group_uniforms Foliage_Shading;
uniform float ambient_lift : hint_range(0.0, 1.0) = 0.35;
uniform vec4 ambient_tint : source_color = vec4(0.55, 0.7, 0.55, 1.0);
// Bias of the normal toward world up. Grass cards have sideways normals, so side lighting
// would leave the whole meadow black. Unity hardcodes 0.5 here - exposed in this port, but
// leave it alone without a reason: outside 0.4-0.6 the blades stop looking solid.
uniform float normal_up_bias : hint_range(0.0, 1.0) = 0.5;

varying vec3 v_world;


// --- procedural noise (Inigo Quilez style hash + value noise) ----------------
float ea_hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float ea_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = ea_hash21(i);
	float b = ea_hash21(i + vec2(1.0, 0.0));
	float c = ea_hash21(i + vec2(0.0, 1.0));
	float d = ea_hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}


// --- wind --------------------------------------------------------------------
// Three layers:
//   1) per-blade jitter - phase derived from the VERTEX position in object space, so
//      blades within one clump move independently of each other;
//   2) coherent gust - noise over world XZ scrolled along the wind direction, so
//      neighbouring clumps lean together, like a wave crossing the meadow;
//   3) micro-tremble - fast, small shaking of the leaf.
// Anchoring: y=0 (root) stays put, y=1 (tip) swings the most.
void vertex() {
	vec3 position_os = VERTEX;
	float anchor = clamp(position_os.y / max(anchor_height, 0.001), 0.0, 1.0);
	vec3 world_pos = (MODEL_MATRIX * vec4(position_os, 1.0)).xyz;
	v_world = world_pos;

	vec2 dir = normalize(vec2(wind_direction_x, wind_direction_z) + vec2(1e-4, 0.0));

	// 1) per-blade jitter
	float world_phase = TIME * wind_speed
		+ world_pos.x * wind_frequency
		+ world_pos.z * wind_frequency;
	float blade_phase = position_os.x * 12.7 + position_os.z * 8.3;
	float wave = sin(world_phase + blade_phase);
	float jitter = sin(TIME * wind_speed * 3.1 + blade_phase * 2.1) * 0.35;
	float per_blade = wave + jitter;

	// 2) coherent gust
	vec2 gust_uv = world_pos.xz * gust_scale - dir * TIME * gust_speed;
	float gust_sample = gust_use_texture
		? textureLod(gust_noise, gust_uv, 0.0).r
		: ea_value_noise(gust_uv);
	float gust = (gust_sample - 0.5) * 2.0 * gust_strength;

	float total = per_blade + gust;
	vec3 push_ws = vec3(dir.x, 0.0, dir.y) * total * wind_strength * anchor;

	// The push is computed in world space but applied in object space - otherwise rotated
	// instances (the scatter randomises yaw) would each bend in their own direction.
	// Instead of a costly inverse() we use transpose(M) = s^2 * M^-1 for a rotation with
	// uniform scale, so we just divide by the squared column length.
	mat3 m = mat3(MODEL_MATRIX);
	float s2 = max(dot(m[0], m[0]), 1e-6);
	vec3 push_os = (push_ws * m) / s2;

	VERTEX = position_os + push_os;
}


// --- tint --------------------------------------------------------------------
// Width is a power curve applied to the noise:
//   width=0 -> pow(n, 4)    : a few sharp patches, most of the surface left clean
//   width=1 -> pow(n, 0.25) : noise floor lifted, tint covers almost everything
float ea_tint_noise(vec2 world_xz, vec2 wind_dir, float scale, float scroll_speed,
		float width, float phase_offset, bool stripes) {
	float n_mul;
	if (stripes) {
		// Stripes mode. Noise is sampled along the axis perpendicular to the wind, so
		// values stay constant along the wind direction - the result is parallel bands
		// drifting downwind.
		//
		// To avoid a barcode with even spacing, the band coordinate itself is warped by
		// a slower noise (frequency modulation): some bands come out wide and lazy,
		// others narrow and sharp.
		vec2 perp = vec2(-wind_dir.y, wind_dir.x);
		float perp_coord = dot(world_xz, perp);
		float t = TIME * scroll_speed;

		float warp = ea_value_noise(vec2(perp_coord * scale * 0.18 + t * 0.4,
			3.7 + phase_offset));
		float warped_coord = perp_coord * scale + warp * 4.0 + t;

		float n_main = ea_value_noise(vec2(warped_coord, 1.7 + phase_offset));
		// Width envelope: a slow noise that lifts some bands and damps others, so
		// neighbours end up with different intensity.
		float n_env = ea_value_noise(vec2(perp_coord * scale * 0.32 + t * 0.55,
			9.1 + phase_offset));
		n_mul = clamp(n_main * (0.2 + n_env * 1.6), 0.0, 1.0);
	} else {
		// Blob mode: two crossed layers of 2D noise, multiplied together. A single layer
		// would produce a visible band sweeping across the field; crossing them breaks it
		// into organic, drifting patches.
		vec2 base_uv = world_xz * scale;
		vec2 scroll_a = wind_dir * TIME * scroll_speed;
		vec2 scroll_b = vec2(-wind_dir.y, wind_dir.x) * TIME * scroll_speed * 0.7;
		float n_a = ea_value_noise(base_uv + scroll_a + phase_offset);
		float n_b = ea_value_noise(base_uv * 1.6 + scroll_b + 7.37 + phase_offset);
		n_mul = clamp(n_a * n_b * 2.0, 0.0, 1.0);
	}
	float curve = mix(4.0, 0.25, clamp(width, 0.0, 1.0));
	return pow(n_mul, curve);
}


vec3 ea_dual_noise_tint(vec3 world_pos) {
	vec2 wind_dir = normalize(vec2(wind_direction_x, wind_direction_z) + vec2(1e-4, 0.0));

	// Each layer keeps a separate set of parameters for blob and stripes mode, so
	// switching the mode back and forth never loses the other one's settings.
	float s_scale = stripes_mode_small ? tint_scale_small_stripes : tint_scale_small_blob;
	float s_intensity = stripes_mode_small ? tint_intensity_small_stripes : tint_intensity_small_blob;
	float s_width = stripes_mode_small ? tint_width_small_stripes : tint_width_small_blob;
	float s_speed = stripes_mode_small ? tint_speed_small_stripes : tint_speed_small_blob;

	float l_scale = stripes_mode_large ? tint_scale_large_stripes : tint_scale_large_blob;
	float l_intensity = stripes_mode_large ? tint_intensity_large_stripes : tint_intensity_large_blob;
	float l_width = stripes_mode_large ? tint_width_large_stripes : tint_width_large_blob;
	float l_speed = stripes_mode_large ? tint_speed_large_stripes : tint_speed_large_blob;

	float n_s = ea_tint_noise(world_pos.xz, wind_dir, s_scale, s_speed, s_width,
		0.0, stripes_mode_small);
	float n_l = ea_tint_noise(world_pos.xz, wind_dir, l_scale, l_speed, l_width,
		11.3, stripes_mode_large);

	vec3 tint_s = mix(vec3(1.0), tint_color_small.rgb, n_s * s_intensity);
	vec3 tint_l = mix(vec3(1.0), tint_color_large.rgb, n_l * l_intensity);
	return tint_s * tint_l;
}


void fragment() {
	vec4 albedo_a = texture(albedo_texture, UV);

	// The normal is assembled by hand instead of through NORMAL_MAP, because it still has
	// to be biased toward world up - and Godot applies NORMAL_MAP only AFTER fragment().
	vec3 n_ts = texture(normal_texture, UV).rgb * 2.0 - 1.0;
	n_ts.xy *= normal_strength;
	vec3 n_view = normalize(mat3(TANGENT, BINORMAL, NORMAL) * n_ts);
	// World up in view space - inside Godot's fragment shader normals are view-space.
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(n_view, up_view, normal_up_bias));

	vec3 tint = ea_dual_noise_tint(v_world);

	ALBEDO = albedo_a.rgb * base_color.rgb * tint;
	ALPHA = albedo_a.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;

	ROUGHNESS = 1.0 - smoothness;
	METALLIC = metallic;

	// Ambient lift: keeps shaded sides from dropping to black. Added proportionally to
	// albedo so the color stays grassy instead of turning grey.
	EMISSION = ALBEDO * ambient_tint.rgb * ambient_lift;
}
