shader_type spatial;
render_mode diffuse_burley;
uniform vec4 base_color : source_color = vec4(0.6,0.55,0.46,1.0);
uniform float base_metal = 0.0;
uniform float base_roughness = 0.9;
uniform float damage_amount = 1.0;
uniform float crack_amount = 0.35;
uniform sampler2D plaster_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_plaster_texture = false;
uniform bool lightweight = true;
varying vec3 world_position;
varying vec3 world_normal;
float hash3(vec3 p) { p=fract(p*0.1031); p+=dot(p,p.yzx+33.33); return fract((p.x+p.y)*p.z); }
float noise3(vec3 p) {
 vec3 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash3(i),hash3(i+vec3(1,0,0)),f.x),mix(hash3(i+vec3(0,1,0)),hash3(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash3(i+vec3(0,0,1)),hash3(i+vec3(1,0,1)),f.x),mix(hash3(i+vec3(0,1,1)),hash3(i+vec3(1,1,1)),f.x),f.y),f.z);
}
float fbm(vec3 p) { return noise3(p)*0.55+noise3(p*2.07)*0.27+noise3(p*4.13)*0.12+noise3(p*8.21)*0.06; }
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
void fragment() {
 if (lightweight) {
  vec3 p = world_position;
  float grime = noise3(p * 0.65);
  vec3 color = base_color.rgb * (0.65 + grime * 0.45);
  if (use_plaster_texture) {
   vec2 uv = abs(world_normal.y) > 0.65 ? p.xz : (abs(world_normal.x) > 0.65 ? p.zy : p.xy);
   color *= 0.5 + texture(plaster_texture, uv * 0.5).rgb * 0.8;
  }
  float damp = (1.0 - smoothstep(0.0, 2.5, p.y)) * damage_amount;
  ALBEDO = mix(color, color * vec3(0.48, 0.57, 0.43), damp * 0.45);
  ROUGHNESS = base_roughness;
  METALLIC = base_metal;
 } else {
 vec3 p=world_position;
 float broad=fbm(p*0.65);
 float grain=noise3(p*90.0);
 float chips=smoothstep(0.60,0.76,fbm(p*6.0));
 float runoff=smoothstep(0.48,0.72,fbm(p*vec3(3.6,0.12,3.6)));
 float damp=(1.0-smoothstep(0.0,2.5+noise3(p*0.8)*1.7,p.y))*smoothstep(0.3,0.7,broad);
 float crack_field=fbm(p*1.6+vec3(noise3(p*0.37)*3.0));
 float cracks=(1.0-smoothstep(0.001,0.005,abs(crack_field-0.48)))*smoothstep(0.53,0.78,noise3(p*0.5))*crack_amount;
 vec3 plaster=base_color.rgb*(0.76+broad*0.5+(grain-0.5)*0.11);
 float photographic_detail=0.5;
 if(use_plaster_texture){
  vec3 weights=pow(abs(world_normal),vec3(4.0)); weights/=max(dot(weights,vec3(1.0)),0.001);
  vec3 photo=texture(plaster_texture,p.zy*0.5).rgb*weights.x+texture(plaster_texture,p.xz*0.5).rgb*weights.y+texture(plaster_texture,p.xy*0.5).rgb*weights.z;
  photographic_detail=dot(photo,vec3(0.299,0.587,0.114));
  plaster=base_color.rgb*(0.38+photo*0.95)*(0.90+broad*0.20);
 }
 plaster=mix(plaster,base_color.rgb*0.40,chips*0.62*damage_amount);
 plaster=mix(plaster,vec3(0.115,0.10,0.073),runoff*0.32*damage_amount);
 plaster=mix(plaster,vec3(0.085,0.12,0.052),damp*0.62*damage_amount);
 plaster=mix(plaster,vec3(0.065,0.052,0.038),cracks*0.55);
 ALBEDO=plaster;
 ROUGHNESS=clamp(base_roughness+chips*0.15+grain*0.08,0.45,1.0);
 METALLIC=base_metal*(1.0-chips);
 float relief=grain*0.05+chips*0.20+cracks*0.08+photographic_detail*0.24;
 vec3 dx=normalize(dFdx(VERTEX)); vec3 dy=normalize(dFdy(VERTEX));
 NORMAL=normalize(NORMAL-dx*dFdx(relief)*1.5-dy*dFdy(relief)*1.5);
 }
}
