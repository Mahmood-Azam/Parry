shader_type spatial;
uniform vec4 color : source_color = vec4(0.11,0.13,0.13,1);
varying vec3 wp;
float h(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise2(vec2 p) { vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y); }
void vertex(){ wp=(MODEL_MATRIX*vec4(VERTEX,1)).xyz; }
void fragment(){
 vec2 p=wp.xz;
 float grain=h(floor(p*80.0));
 float crack=1.0-smoothstep(0.008,0.045,abs(sin(p.x*0.55+sin(p.y*0.7)*0.9+sin(p.y*2.1)*0.11)));
 float patch=noise2(p*0.19)*0.6+noise2(p*0.63)*0.4;
 ALBEDO=mix(color.rgb*(0.8+grain*0.3),vec3(0.032,0.038,0.023),crack*0.85);
 ALBEDO=mix(ALBEDO,vec3(0.12,0.16,0.067),smoothstep(0.60,0.83,patch)*0.38);
 ROUGHNESS=0.95;
}
