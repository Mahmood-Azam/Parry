shader_type spatial;
render_mode cull_disabled;
void fragment(){
 vec2 p=UV*vec2(60.0,30.0);
 float a=abs(fract(p.x+p.y)-0.5);
 float b=abs(fract(p.x-p.y)-0.5);
 ALPHA=1.0-smoothstep(0.025,0.065,min(a,b));
 ALPHA_SCISSOR_THRESHOLD=0.35;
 ALBEDO=vec3(0.18,0.125,0.075);
 ROUGHNESS=0.86;
}
