shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec3 skater_position = vec3(10000.0, 10000.0, 10000.0);
uniform float skater_clear_radius : hint_range(0.4, 1.4) = 0.78;
varying vec3 tint;
varying float height_factor;
void vertex() {
 tint=INSTANCE_CUSTOM.rgb;
 height_factor=clamp(VERTEX.y,0.0,1.0);
 vec3 wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 vec2 from_skater=wp.xz-skater_position.xz;
 float distance_to_skater=length(from_skater);
 float deck_clear=1.0-smoothstep(0.16,skater_clear_radius,distance_to_skater);
 vec2 bend_direction=distance_to_skater>0.001 ? from_skater/distance_to_skater : vec2(1.0,0.0);
 VERTEX.xz+=bend_direction*deck_clear*height_factor*0.34;
 VERTEX.y-=deck_clear*height_factor*0.72;
 float wind=sin(TIME*1.1+wp.x*0.75+wp.z*0.45)+0.35*sin(TIME*2.3+wp.z*1.7);
 VERTEX.x+=wind*height_factor*height_factor*0.055;
}
void fragment() {
 ALBEDO=tint*mix(vec3(0.55,0.64,0.45),vec3(1.16,1.04,0.73),height_factor);
 ROUGHNESS=0.93;
 if(!FRONT_FACING) { NORMAL=-NORMAL; }
 BACKLIGHT=ALBEDO*0.22;
}
