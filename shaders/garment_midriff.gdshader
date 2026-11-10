shader_type spatial;
uniform vec4 skin_color:source_color=vec4(.7,.5,.35,1.0);
uniform float hem_height=1.06;
varying float rest_y;
void vertex(){rest_y=CUSTOM0.y;}
void fragment(){
	if(rest_y>hem_height){discard;}
	ALBEDO=skin_color.rgb;
	ROUGHNESS=.65;
	SPECULAR=.35;
}
