shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform vec2 cell = vec2(0.0);
uniform vec2 grid = vec2(4.0,2.0);
uniform vec4 region = vec4(0.0,0.0,1.0,1.0);
uniform bool remove_pale_background = false;
uniform bool monochrome = false;
uniform vec4 ink_color : source_color = vec4(0.025,0.025,0.022,1.0);
void fragment(){
 vec2 uv=(clamp(UV,vec2(0.015),vec2(0.985))+cell)/grid;
 uv=region.xy+uv*region.zw;
 vec4 ink=texture(atlas,uv);
 if(remove_pale_background){
  float low=min(ink.r,min(ink.g,ink.b));
  float high=max(ink.r,max(ink.g,ink.b));
  ink.a*=1.0-smoothstep(0.69,0.82,low)*(1.0-smoothstep(0.025,0.10,high-low));
 }
 ALBEDO=monochrome ? ink_color.rgb : ink.rgb*0.85;
 ALPHA=ink.a;
 ALPHA_SCISSOR_THRESHOLD=0.25;
 ROUGHNESS=0.97;
}
