shader_type spatial;
uniform vec3 base_color=vec3(.46,.27,.22);
void fragment(){
	float edge=smoothstep(.86,.98,UV.y);
	float moon=(1.0-smoothstep(.12,.23,length(vec2((UV.x-.5)*.9,UV.y-.14))))*.22;
	float rim=smoothstep(.36,.50,abs(UV.x-.5));
	ALBEDO=mix(base_color,vec3(.70,.65,.55),edge*.65+moon)*(1.0-.08*rim);
	ROUGHNESS=.35;
	SPECULAR=.38;
}
