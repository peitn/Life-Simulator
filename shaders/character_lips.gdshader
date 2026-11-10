shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 base_color=vec3(.27,.11,.10);
varying vec3 rest;
void vertex(){rest=CUSTOM0.xyz;}
void fragment(){
	float y=rest.y-1.6035;
	float lines=pow(.5+.5*sin(rest.x*7600.0+sin(rest.x*1700.0)*1.5+y*42.0),5.0);
	float aa=1.0-smoothstep(.00015,.0006,length(fwidth(rest)));
	float edge=smoothstep(.004,.011,abs(y));
	ALBEDO=base_color*(1.0-.07*lines*aa)*(1.0-.10*edge);
	ROUGHNESS=.48+.07*lines*aa;
	SPECULAR=.32;
}
