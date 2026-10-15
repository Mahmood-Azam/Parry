shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// EmacEArt - EA_Water
// Stylized low-poly water for Godot 4.
// Requires the Forward+ (or Mobile) renderer - the Compatibility renderer
// encodes the depth buffer differently and the depth reconstruction below
// would need a remap.
//
// Low-poly toon water: depth banding, shore glow, toon specular, fresnel,
// screen-space refraction, projected + painted foam, caustics projected on
// the floor beneath the water, and sparkle glints.
//
// Mesh requirements:
//   - a subdivided plane if you want vertex waves (wave_height > 0)
//   - vertex colors are optional control zones, painted per vertex:
//       R = 0 -> painted surface foam island, 1 -> none (default)
//       G < 0.5 -> hidden zone (cave openings etc.), pixels are discarded
//       B = 0 -> animation frozen (under bridges, ice), 1 -> animated (default)
//     An unpainted mesh is white (1,1,1) -> visible, animated, no painted foam.

group_uniforms Colors_and_Depth;
uniform vec4 shallow_color : source_color = vec4(0.485, 0.810, 0.906, 0.65);
uniform vec4 deep_color : source_color = vec4(0.248, 0.507, 0.722, 0.92);
// Vertical distance (metres) at which the water shows the full deep color.
uniform float water_depth : hint_range(0.1, 20.0) = 3.0;
uniform int color_bands : hint_range(1, 8) = 3;
uniform vec4 shore_glow_color : source_color = vec4(0.906, 0.982, 1.0, 1.0);
uniform float shore_glow_width : hint_range(0.0, 0.75) = 0.15;
group_uniforms;

group_uniforms Lighting_and_Toon;
uniform vec4 specular_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float specular_size : hint_range(5.0, 60.0) = 24.0;
uniform float specular_softness : hint_range(0.0, 1.0) = 0.25;
// Cuts the finished highlight a second time, the way a toon shader stencils it:
// 0 keeps the gradient specular_softness produced, 1 flattens every lit pixel to
// the same brightness so the reflection ends up as flat chips, not a glow.
uniform float specular_hardness : hint_range(0.0, 1.0) = 0.85;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float fresnel_power : hint_range(0.0, 3.0) = 1.0;
// Screen-space refraction of everything under the surface.
uniform float refraction_strength : hint_range(0.0, 0.1) = 0.02;
group_uniforms;

group_uniforms Foam_and_Shore;
// Texture uses foam_texture below; the other four styles are procedural.
uniform int foam_style : hint_enum("Texture", "Cloudy", "Blobs", "Scatter", "Cellular") = 4;
uniform vec4 foam_color : source_color = vec4(0.972, 0.985, 1.0, 1.0);
uniform sampler2D foam_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float foam_tiling : hint_range(0.0, 0.1) = 0.02;
// Total reach of the shoreline foam: 0 -> none, 1 -> the full foam depth.
uniform float foam_cutoff : hint_range(0.0, 1.0) = 0.5;
// Vertical metres from the shoreline the foam band can cover.
uniform float foam_depth : hint_range(0.0, 2.0) = 0.5;
uniform float foam_speed : hint_range(0.0, 0.6) = 0.4;
// 0 -> even ribbon of foam along every edge, 1 -> the band is chewed up by the
// foam pattern into irregular patches with gaps.
uniform float foam_edge_break : hint_range(0.0, 1.0) = 0.6;
// Breaks up the waterline itself. The surface is cut where the ground rises
// above it, and that cut is geometrically clean - foam reaching it ends along a
// perfectly smooth arc. This jitters the cut height (metres) with noise, so the
// waterline runs irregular like water soaking into sand.
uniform float shore_edge_break : hint_range(0.0, 0.6) = 0.25;
// How abruptly every foam mask ends. 0 keeps the wide soft falloff the foam had
// before, 1 collapses it to a stencil cut. Even at 1 a pixel-wide blend stays,
// otherwise the cut would staircase along the shoreline.
uniform float foam_hardness : hint_range(0.0, 1.0) = 0.8;
// Mixes foam into the water with an overlay instead of painting it over. Overlay
// keeps the water underneath visible, so foam over the deep end comes out cooler
// than foam over the shallows. 0 = the flat foam_color blend used so far.
uniform float foam_overlay : hint_range(0.0, 1.0) = 0.0;
group_uniforms;

group_uniforms Caustics;
uniform vec4 caustics_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float caustics_strength : hint_range(0.0, 0.5) = 0.25;
uniform float caustics_scale : hint_range(0.0, 0.1) = 0.05;
uniform float caustics_speed : hint_range(0.0, 1.2) = 0.5;
// Three offset caustic samples -> rainbow fringe along the bright veins.
uniform bool chromatic_aberration = true;
group_uniforms;

group_uniforms Sparkle;
// Tiny animated glints scattered over the surface. Brightness.
uniform float sparkle_boost : hint_range(0.0, 1.0) = 0.0;
// How many of them and how far apart.
uniform float sparkle_density : hint_range(0.0, 1.0) = 0.5;
// Size of a single glint.
uniform float sparkle_size : hint_range(0.0, 1.0) = 0.35;
group_uniforms;

group_uniforms Waves_Geometry;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_tiling : hint_range(0.0, 0.15) = 0.08;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.5;
uniform float wave_speed : hint_range(0.0, 0.2) = 0.05;
// Vertex wave amplitude (metres). Needs a subdivided plane.
uniform float wave_height : hint_range(0.0, 0.3) = 0.04;
group_uniforms;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear, repeat_disable;

varying vec3 v_world_pos;
varying vec4 v_color;

// -- Triple-sine UV warp ------------------------------------------------------
vec2 distort_uv(vec2 uv, float amount, float t) {
	float a = amount * 0.01;
	float b = amount * 0.12;
	uv.y += a * (sin(uv.x * 3.5 + t * 0.35) + sin(uv.x * 4.8 + t * 1.05) + sin(uv.x * 7.3 + t * 0.45)) / 3.0;
	uv.x += b * (sin(uv.y * 4.0 + t * 0.50) + sin(uv.y * 6.8 + t * 0.75) + sin(uv.y * 11.3 + t * 0.20)) / 3.0;
	uv.y += b * (sin(uv.x * 4.2 + t * 0.64) + sin(uv.x * 6.3 + t * 1.65) + sin(uv.x * 8.2 + t * 0.45)) / 3.0;
	return uv;
}

// -- Toon threshold -----------------------------------------------------------
// One place where every foam mask decides how wide its edge is. The caller
// passes the soft width it used before and the width of a single pixel measured
// on the same field (fwidth); foam_hardness slides between them. A plain step()
// would staircase on a shoreline that crosses the screen diagonally, so the
// pixel width is the floor, never zero.
float foam_threshold(float v, float center, float soft_width, float px_width) {
	float w = max(mix(soft_width, px_width, foam_hardness), 1e-5);
	return smoothstep(center - w, center + w, v);
}

// -- Overlay blend ------------------------------------------------------------
// Dark water darkens the foam, bright water brightens it - the foam picks up the
// tint underneath instead of stamping one flat white over shallows and deeps
// alike.
vec3 overlay_blend(vec3 base, vec3 top) {
	vec3 lo = 2.0 * base * top;
	vec3 hi = 1.0 - 2.0 * (1.0 - base) * (1.0 - top);
	return mix(lo, hi, step(vec3(0.5), base));
}

// -- Reconstruct world position from screen UV + raw depth --------------------
// Forward+ / Mobile: NDC z is the raw depth value (reversed-z projection
// matrices make this work without any remap on Godot 4.3+).
vec3 reconstruct_world_pos(vec2 suv, float raw_depth, mat4 inv_proj, mat4 inv_view) {
	vec3 ndc = vec3(suv * 2.0 - 1.0, raw_depth);
	vec4 view_pos = inv_proj * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	return (inv_view * vec4(view_pos.xyz, 1.0)).xyz;
}

// -- Procedural noise helpers -------------------------------------------------
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float worley_min_dist(vec2 p) {
	vec2 pi = floor(p);
	vec2 pf = fract(p);
	float min_d = 1.0;
	for (int wx = -1; wx <= 1; wx++) {
		for (int wy = -1; wy <= 1; wy++) {
			vec2 g = vec2(float(wx), float(wy));
			vec2 o = vec2(
				fract(sin(dot(pi + g, vec2(127.1, 311.7))) * 43758.5),
				fract(sin(dot(pi + g, vec2(269.5, 183.3))) * 12345.6));
			min_d = min(min_d, length(g + o - pf));
		}
	}
	return min_d;
}

// Cloudy - soft low-frequency wisps (FBM), animated by t
float foam_cloudy(vec2 p, float t) {
	vec2 da = vec2(t * 0.45, t * 0.30);
	vec2 db = vec2(-t * 0.32, t * 0.50);
	float v = vnoise(p * 0.8 + da) * 0.55
			+ vnoise(p * 1.7 + db + 3.1) * 0.30
			+ vnoise(p * 3.3 + da * 0.6 + 7.4) * 0.15;
	return smoothstep(0.42, 0.50, v); // sharp toon edge
}

// Blobs - large organic shapes, hard binary toon edge
float foam_blobs(vec2 p, float t) {
	vec2 d = vec2(t * 0.18, t * 0.12);
	float v = vnoise(p * 0.45 + d) * 0.60
			+ vnoise(p * 0.95 - d * 0.6 + 2.7) * 0.40;
	return smoothstep(0.47, 0.50, v); // hard edge
}

// Scatter - small high-frequency specks
float foam_scatter(vec2 p, float t) {
	vec2 d = vec2(t * 0.85, t * 0.65);
	float v = vnoise(p * 4.5 + d)
			* (0.6 + 0.4 * vnoise(p * 0.7 - d * 0.4));
	return smoothstep(0.64, 0.67, v); // hard speckles
}

// Cellular - Worley voronoi cells, animated scroll
float foam_cellular(vec2 p, float t) {
	vec2 d = vec2(t * 0.25, t * 0.18);
	float dist = worley_min_dist(p * 1.2 + d);
	// Inverted edge pair: bright inside the cells, dark seams between them.
	return 1.0 - smoothstep(0.36, 0.42, dist);
}

float sample_foam_styled(vec2 uv, float t) {
	if (foam_style == 1) {
		return foam_cloudy(uv, t);
	} else if (foam_style == 2) {
		return foam_blobs(uv, t);
	} else if (foam_style == 3) {
		return foam_scatter(uv, t);
	} else if (foam_style == 4) {
		return foam_cellular(uv, t);
	}
	return texture(foam_texture, uv).r; // Texture style
}

// -- Sparkle glints -----------------------------------------------------------
// One candidate point per cell, but only a fraction of the cells light up and
// each blinks on its own phase - an irregular twinkle rather than a dot grid.
float sparkle_points(vec2 p, float t, float density, float size) {
	vec2 pi = floor(p);
	vec2 pf = fract(p);
	float acc = 0.0;
	for (int sx = -1; sx <= 1; sx++) {
		for (int sy = -1; sy <= 1; sy++) {
			vec2 g = vec2(float(sx), float(sy));
			vec2 cell = pi + g;
			float h1 = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5);
			float h2 = fract(sin(dot(cell, vec2(269.5, 183.3))) * 12345.6);
			float h3 = fract(sin(dot(cell, vec2(419.2, 371.9))) * 65537.1);
			if (h3 > density) {
				continue; // most cells stay dark
			}
			float d = length(g + vec2(h1, h2) - pf);
			float r = mix(0.05, 0.18, size);
			float point_mask = 1.0 - smoothstep(r * 0.35, r, d);
			float blink = sin(t * 2.6 + h1 * 31.4 + h2 * 17.7) * 0.5 + 0.5;
			acc = max(acc, point_mask * smoothstep(0.45, 1.0, blink));
		}
	}
	return acc;
}

// -- Caustics - organic tongue/streak refraction lines ------------------------
// Real pool caustics look like irregular bright tongues, NOT a regular diamond
// grid. The sample position is distorted with low-frequency noise before the
// wavefront interference - straight ridges bend into organic streaks.
// 1 - abs(sum) gives bright RIDGES where the waves cross zero; pow() sharpens
// them into thin tongues with continuous coverage.
float caustic(vec2 p, float t) {
	float ct = t * 0.55;
	// Low-frequency distortion -> bends straight ridges into organic tongues
	vec2 dist = vec2(
		vnoise(p * 0.35 + ct * 0.08),
		vnoise(p * 0.35 + ct * 0.10 + 5.1)) - 0.5;
	vec2 pd = p + dist * 0.7;
	// Four wave fronts at irrational angles -> non-repeating interference
	float w1 = sin(dot(pd, vec2(1.000, 0.000)) * 2.0 + ct * 0.60);
	float w2 = sin(dot(pd, vec2(0.500, 0.866)) * 2.2 + ct * 0.45);
	float w3 = sin(dot(pd, vec2(-0.500, 0.866)) * 1.8 + ct * 0.55);
	float w4 = sin(dot(pd, vec2(0.707, 0.707)) * 2.7 + ct * 0.40);
	float v = (w1 + w2 + w3 + w4) * 0.25;  // -1 ... +1
	float ridge = 1.0 - abs(v);            // 0 (valley) ... 1 (ridge)
	ridge = pow(ridge, 4.0);               // thin tongues
	// Soft flicker for shimmer (not high-frequency speckle)
	float flicker = 0.75 + 0.25 * sin(ct * 3.0 + p.x * 1.3 + p.y * 0.9);
	return clamp(ridge * flicker * 1.4, 0.0, 1.0);
}

// Two-tap union blend - two caustic networks at different scale/phase overlap
// into a richer organic pattern. max() preserves brightness on both networks
// rather than carving (min() would erase most of it).
float caustic_blend(vec2 p, float t) {
	float ca = caustic(p, t);
	float cb = caustic(p * 1.43 + 2.7, t * 0.78);
	return max(ca, cb);
}

// -- Vertex -------------------------------------------------------------------
void vertex() {
	v_color = COLOR;
	// COLOR.b = 1 (default, unpainted) -> animated
	// COLOR.b = 0 (painted black) -> frozen (under bridges, ice, etc.)
	float wave_anim = clamp(COLOR.b, 0.0, 1.0);
	float t = TIME * wave_speed;
	VERTEX.y += (sin(VERTEX.x * 2.0 + t) * 0.5 + sin(VERTEX.z * 1.7 + t * 0.8) * 0.5)
			* wave_height * wave_anim;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// -- Fragment -----------------------------------------------------------------
void fragment() {
	// COLOR.g < 0.5 -> cave / hidden zone -> clip.
	// Default unpainted vertex = white (g = 1) -> always visible.
	if (v_color.g < 0.5) {
		discard;
	}

	vec3 pos_ws = v_world_pos;
	vec2 scr_uv = SCREEN_UV;

	// COLOR.b = 1 (default) animates foam; 0 freezes it.
	float foam_anim = clamp(v_color.b, 0.0, 1.0);

	// -- Depth ----------------------------------------------------------------
	// World-space vertical Y: camera-independent - bands don't dance when you
	// rotate / tilt the camera.
	float raw_depth = texture(depth_texture, scr_uv).r;
	vec3 scene_ws = reconstruct_world_pos(scr_uv, raw_depth, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	// Discard water pixels where the scene is ABOVE the water surface
	// (no cyan halo around protruding objects, no overshoot of the basin).
	// The cut height is jittered with the same scale of noise the foam uses,
	// otherwise the waterline is a mathematically clean curve and every foam
	// band ends along a smooth arc on the land side.
	float shore_jitter = (vnoise(pos_ws.xz * 1.8 + TIME * foam_speed * 0.2) - 0.5)
			* shore_edge_break;
	if (scene_ws.y > pos_ws.y + 0.05 + shore_jitter) {
		discard;
	}
	float depth_diff = max(0.0, pos_ws.y - scene_ws.y); // vertical metres
	float depth_t = clamp(depth_diff / max(0.001, water_depth), 0.0, 1.0);

	// -- Flat face normal (low-poly faceted look) -----------------------------
	vec3 flat_n = normalize(cross(dFdx(pos_ws), dFdy(pos_ws)));
	if (flat_n.y < 0.0) {
		flat_n = -flat_n;
	}

	// -- Wave normals (dual-layer scroll, world XZ projection) ----------------
	float t = TIME * wave_speed;
	vec2 nm_base = pos_ws.xz * normal_tiling;
	vec3 tn_a = texture(normal_map, nm_base + t * vec2(0.07, 0.05)).rgb * 2.0 - 1.0;
	vec3 tn_b = texture(normal_map, nm_base * 0.7 + t * vec2(-0.04, 0.08)).rgb * 2.0 - 1.0;
	vec3 tn = normalize(tn_a + tn_b);
	vec3 wave_n = normalize(vec3(tn.x, tn.z, tn.y));
	vec3 blend_n = normalize(mix(flat_n, wave_n, normal_strength * 0.5));

	// High-frequency normal for tight specular. The tiling is far denser than the
	// lighting normal above on purpose: at the old 2.1 / 1.7 the surface faced
	// nearly the same way over metres of water, so the whole highlight lit up as
	// one spread blob. Dense tiling splits the sun into separate chips the size
	// of a wavelet.
	vec3 st_a = texture(normal_map, nm_base * 9.0 + t * vec2(0.11, 0.07)).rgb * 2.0 - 1.0;
	vec3 st_b = texture(normal_map, nm_base * 6.3 + t * vec2(-0.06, 0.12)).rgb * 2.0 - 1.0;
	vec3 st = normalize(st_a + st_b);
	vec3 spec_n_ws = normalize(vec3(st.x, st.z, st.y));

	// -- Depth banding (toon bands) -------------------------------------------
	float bands = max(1.0, float(color_bands));
	float banded_t = floor(depth_t * bands) / bands;
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, banded_t);

	// -- Shore glow -----------------------------------------------------------
	float shore_t = clamp(depth_diff / max(0.001, shore_glow_width * water_depth), 0.0, 1.0);
	col = mix(shore_glow_color.rgb, col, shore_t);

	// -- Refraction (screen texture) ------------------------------------------
	// Dedicated normal sample with FIXED tiling (0.45), independent of
	// normal_tiling - at low slider values the lighting normal becomes nearly
	// constant across the surface -> no per-pixel variation -> no visible
	// distortion. Hard-coded tiling keeps refraction working regardless of how
	// the user sets the lighting normal.
	vec2 ref_nm_uv = pos_ws.xz * 0.45 + TIME * wave_speed * vec2(0.06, 0.04);
	vec3 ref_tn = texture(normal_map, ref_nm_uv).rgb * 2.0 - 1.0;
	vec2 ref_off = ref_tn.xy * refraction_strength * 4.0 * (1.0 - depth_t * 0.3);
	vec2 ref_uv = clamp(scr_uv + ref_off, vec2(0.001), vec2(0.999));
	vec3 ref_col = texture(screen_texture, ref_uv).rgb;
	col = mix(ref_col, col, clamp(depth_t * 0.9 - 0.1, 0.0, 1.0));

	// -- Caustics - vein refraction network, projected on the floor -----------
	// Sampled in scene_ws.xz (the ground beneath the water), NOT pos_ws.xz
	// (the water surface) -> caustics stick to the terrain like real refracted
	// light. Walk past a rock under the pool and the bright veins crawl over it
	// instead of sliding off the rock edge.
	// Slider caustics_scale remapped to density 0.5..2.5.
	float caustic_zone = clamp(1.0 - smoothstep(0.30, 1.00, depth_t), 0.0, 1.0);
	float c_scale = mix(0.5, 2.5, caustics_scale);
	vec2 c_p = scene_ws.xz * c_scale;
	float c_t = TIME * caustics_speed;
	vec3 caustic_rgb;
	if (chromatic_aberration) {
		// Chromatic aberration: three offset samples -> visible rainbow fringe
		// along caustic edges (like real underwater refraction).
		vec2 c_off = vec2(0.28, 0.0);
		caustic_rgb = vec3(
			caustic_blend(c_p + c_off, c_t),
			caustic_blend(c_p, c_t),
			caustic_blend(c_p - c_off, c_t));
	} else {
		// No CA: one sample, no rainbow fringing, ~3x cheaper.
		float c = caustic_blend(c_p, c_t);
		caustic_rgb = vec3(c);
	}
	// Toon step: hard levels instead of a photoreal soft glow. Uses the same
	// step count as the depth bands so the whole surface stays one style.
	caustic_rgb = floor(caustic_rgb * bands) / bands;
	// Patchy mask: low-frequency vnoise (also in scene_ws), animated slowly ->
	// some regions fully bright (1), others completely cut (0), soft
	// transition. Without it the caustics cover the floor like a uniform film.
	float caust_mask = smoothstep(0.35, 0.65, vnoise(scene_ws.xz * 0.30 + c_t * 0.18));
	// Auto-color: blend Shallow <-> ShoreGlow (70% toward the glow, the
	// brighter end) and boost luminance so the reflex stays clearly brighter
	// than the water tint under it. caustics_tint remains as an optional
	// modulator (default white = pure auto).
	vec3 caust_auto_tint = mix(shallow_color.rgb, shore_glow_color.rgb, 0.7);
	caust_auto_tint = clamp(caust_auto_tint * 1.55, 0.0, 1.0);
	vec3 caust_effect = caust_auto_tint * caustics_tint.rgb * caustic_rgb
			* caustic_zone * caust_mask * caustics_strength;
	// Screen blend: 1 - (1-a)(1-b) - light that PENETRATES the water color
	// instead of being painted on top. No over-saturation, no chalky film.
	// Works on any water tint by construction.
	col = 1.0 - (1.0 - col) * (1.0 - clamp(caust_effect, vec3(0.0), vec3(1.0)));

	// -- Fresnel - brightens the color at grazing angles ----------------------
	vec3 view_dir_ws = normalize(CAMERA_POSITION_WORLD - pos_ws);
	float fresnel = pow(1.0 - clamp(dot(blend_n, view_dir_ws), 0.0, 1.0), max(0.1, fresnel_power));
	col = mix(col, shore_glow_color.rgb, fresnel * 0.55);

	// -- Alpha ----------------------------------------------------------------
	float alpha = mix(shallow_color.a, deep_color.a, depth_t);
	alpha = clamp(alpha + fresnel * 0.3, 0.0, 1.0);

	// -- FOAM -----------------------------------------------------------------
	float foam_t = TIME * foam_speed * foam_anim;

	// Projected foam - vertical world-Y at 4 diagonal taps (8 px).
	// World-space Y is camera-independent -> the foam does NOT dance during
	// camera rotation / tilt (eye-depth based foam did).
	vec2 ts = 8.0 / VIEWPORT_SIZE;
	vec2 fu0 = scr_uv + ts * vec2(1.0, 1.0);
	vec2 fu1 = scr_uv + ts * vec2(-1.0, 1.0);
	vec2 fu2 = scr_uv + ts * vec2(1.0, -1.0);
	vec2 fu3 = scr_uv + ts * vec2(-1.0, -1.0);
	vec3 fw0 = reconstruct_world_pos(fu0, texture(depth_texture, fu0).r, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	vec3 fw1 = reconstruct_world_pos(fu1, texture(depth_texture, fu1).r, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	vec3 fw2 = reconstruct_world_pos(fu2, texture(depth_texture, fu2).r, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	vec3 fw3 = reconstruct_world_pos(fu3, texture(depth_texture, fu3).r, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	// Above-water taps -> absolute huge sentinel (no foam contribution).
	// Must NOT be tied to foam_depth - when foam_depth = 0 a relative sentinel
	// collapsed to 0 and stamped a full foam ring around every protruding
	// object (outline bug).
	const float big_d = 1e6;
	float fd0 = (fw0.y > pos_ws.y) ? big_d : (pos_ws.y - fw0.y);
	float fd1 = (fw1.y > pos_ws.y) ? big_d : (pos_ws.y - fw1.y);
	float fd2 = (fw2.y > pos_ws.y) ? big_d : (pos_ws.y - fw2.y);
	float fd3 = (fw3.y > pos_ws.y) ? big_d : (pos_ws.y - fw3.y);
	// Smallest vertical metres = shallowest tap = shore zone.
	float proj_diff = min(min(fd0, fd1), min(fd2, fd3));
	// proj_dist: 0 = at the object edge, 1 = a full foam_depth away
	float proj_dist = clamp(proj_diff / max(0.001, foam_depth), 0.0, 1.0);

	// Foam pattern with UV distortion - sampled once, used for the tongues.
	// Slider mapped linearly to an internal 0.05..2.0 tiling range: left end ->
	// huge tongues, right end -> fine pattern.
	float foam_tiling_x = mix(0.05, 2.0, foam_tiling);
	vec2 foam_uv = distort_uv(pos_ws.xz * foam_tiling_x, 0.3, foam_t);
	float foam_samp = sample_foam_styled(foam_uv, foam_t);

	// -- Projected foam - solid inner ring + wispy outer tongues --------------
	// Thick GUARANTEED white band along the shoreline (inner_mask, no noise)
	// + irregular outer patches breaking up farther from the edge
	// (outer_mask, noise-modulated). foam_cutoff controls the total reach.
	// Break-up noise at a FIXED high frequency (roughly half a metre per cell),
	// deliberately independent of foam_tiling: the pattern tiling is metres
	// wide, so a rock 1.5 m across would sit inside a single cell and get an
	// even ribbon of foam around it no matter what the slider says.
	// Two continuous octaves, NOT the toon foam pattern - the pattern is
	// thresholded to 0/1, so it can only switch the band between two widths and
	// both edges stay smooth arcs between the switches.
	float bt = foam_t * 0.6;
	float break_n = vnoise(pos_ws.xz * 1.9 + vec2(bt * 0.5, bt * 0.3)) * 0.62
			+ vnoise(pos_ws.xz * 4.6 - vec2(bt * 0.4, bt * 0.6) + 5.3) * 0.38;
	// Push the distance field itself around: every edge derived from it - inner
	// and outer alike - picks up the same irregular wobble.
	float pd = clamp(proj_dist + (break_n - 0.5) * foam_edge_break * 0.95, 0.0, 1.0);
	float foam_break = smoothstep(0.35, 0.65, break_n);
	float fw_aa = fwidth(pd) + 0.01;
	// Half a pixel of blend to each side of the threshold = one pixel in total.
	float pd_px = fwidth(pd) * 0.5;
	float inner_reach = foam_cutoff * 0.30
			* mix(1.0, 0.35 + foam_break * 1.30, foam_edge_break);
	float inner_mask = 1.0 - foam_threshold(pd, inner_reach, fw_aa, pd_px);
	// Outer tongues mix both scales: the wide pattern places the patches, the
	// break-up sample tears their edges.
	float outer_shape = mix(foam_samp, min(foam_samp, foam_break), foam_edge_break);
	float shape_px = fwidth(outer_shape) * 0.5;
	float outer_reach = foam_cutoff * (0.35 + outer_shape * 1.30);
	float outer_mask = (1.0 - foam_threshold(pd, outer_reach, fw_aa, pd_px))
			// gaps between patches
			* foam_threshold(outer_shape, 0.425, 0.125, shape_px);
	float proj_foam = max(inner_mask, outer_mask);

	// Surface foam islands: COLOR.r = 0 -> foam, 1 -> no foam.
	// Modulated by the pattern so painted foam also gets broken edges.
	float surf_weight = 1.0 - v_color.r;
	float samp_px = fwidth(foam_samp) * 0.5;
	float surf_foam = surf_weight * foam_threshold(foam_samp, 0.55, 0.15, samp_px);

	float foam_mask = max(proj_foam, surf_foam);

	// Foam color: flat foam_color as before, or the same color pushed through
	// overlay so the water below shows through it (foam_overlay).
	vec3 foam_rgb = mix(foam_color.rgb, overlay_blend(col, foam_color.rgb), foam_overlay);
	col = mix(col, foam_rgb, foam_mask * foam_color.a);
	alpha = max(alpha, foam_mask * foam_color.a);

	// -- Sparkle glints -------------------------------------------------------
	// Placed here, not in light(), so the glints cover the whole surface
	// instead of living inside the specular highlight.
	if (sparkle_boost > 0.0) {
		float spk_t = TIME * (0.4 + wave_speed * 6.0);
		vec2 spk_p = pos_ws.xz * mix(1.2, 5.5, sparkle_density);
		float glint = sparkle_points(spk_p, spk_t,
				mix(0.04, 0.45, sparkle_density), sparkle_size);
		glint *= 1.0 - foam_mask; // foam is already white
		col = mix(col, specular_color.rgb, glint * sparkle_boost);
		alpha = max(alpha, glint * sparkle_boost * 0.85);
	}

	// The water color is fully authored here - emission carries it, albedo
	// stays black so ambient light does not double-tint the surface.
	// The toon specular is added per light in light().
	ALBEDO = vec3(0.0);
	EMISSION = col;
	ALPHA = alpha;
	// View-space high-frequency normal for the toon specular in light().
	NORMAL = normalize((VIEW_MATRIX * vec4(spec_n_ws, 0.0)).xyz);
}

// -- Light - toon specular + sparkle ------------------------------------------
void light() {
	// Toon specular - four orthogonal controls:
	//   specular_size     -> highlight tightness (pow exponent)
	//   specular_softness -> toon edge AA width (0 hard, 1 soft)
	//   specular_hardness -> flattens what is left of the gradient (0 off, 1 flat)
	//   specular_intensity-> brightness multiplier
	vec3 half_dir = normalize(VIEW + LIGHT);
	float ndoth = max(dot(NORMAL, half_dir), 0.0);
	float spec_raw = pow(ndoth, max(1.0, specular_size));
	float spec_edge = mix(0.004, 0.35, specular_softness);
	float spec_soft = smoothstep(0.5 - spec_edge, 0.5 + spec_edge, spec_raw);
	// Second cut, right above zero: anything the soft pass lit at all goes to
	// full brightness, so the chip has one flat value instead of a falloff.
	float spec_hard = smoothstep(0.005, 0.01, spec_soft);
	float spec_mask = mix(spec_soft, spec_hard, specular_hardness);
	vec3 light_col = LIGHT_COLOR / PI;
	vec3 spec = specular_color.rgb * spec_mask * specular_intensity * light_col;

	SPECULAR_LIGHT += spec * ATTENUATION;
}
