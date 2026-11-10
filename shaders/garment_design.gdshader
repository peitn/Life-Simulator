shader_type spatial;
render_mode cull_disabled;
uniform vec4 main_color:source_color=vec4(.7,.4,.6,1.0);
uniform vec4 accent_color:source_color=vec4(.95,.9,.95,1.0);
uniform sampler2D fabric_albedo:source_color,repeat_enable,filter_linear_mipmap;
uniform sampler2D fabric_normal:hint_normal,repeat_enable,filter_linear_mipmap;
uniform bool has_albedo=false;
uniform bool has_normal=false;
uniform int pattern=0;
uniform float pattern_scale=1.0;
uniform float roughness=.8;
void fragment(){
	vec2 p=UV*pattern_scale;
	float motif=0.0;
	if(pattern==1){
		float phase=fract(p.y*2.0);
		float aa=max(fwidth(phase),.015);
		motif=smoothstep(.47-aa,.47+aa,phase)*(1.0-smoothstep(.94-aa,.94+aa,phase));
	}else if(pattern==2){
		vec2 cell=floor(p*2.0);
		motif=mod(cell.x+cell.y,2.0);
	}else if(pattern==3){
		float radius=length(fract(p*2.0)-vec2(.5));
		float aa=max(fwidth(radius),.01);
		motif=1.0-smoothstep(.19-aa,.19+aa,radius);
	}
	vec3 pigment=mix(main_color.rgb,accent_color.rgb,motif);
	vec3 weave=has_albedo?texture(fabric_albedo,UV).rgb:vec3(1.0);
	ALBEDO=pigment*mix(vec3(1.0),weave,.4);
	ROUGHNESS=roughness;
	SPECULAR=.3;
	if(has_normal){NORMAL_MAP=texture(fabric_normal,UV).rgb;NORMAL_MAP_DEPTH=.25;}
}
