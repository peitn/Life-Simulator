shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Rest-space fibres stay attached to the iris through all face morphs.
uniform vec3 base_color = vec3(.12,.20,.16);
uniform int tissue = 0; // iris, limbus, sclera, pupil
varying vec3 rest;
void vertex(){rest=CUSTOM0.xyz;}
float hash(float x){return fract(sin(x*127.1)*43758.5453);}
void fragment(){
	vec2 p=vec2(abs(rest.x)-.0318,rest.y-1.6685);
	float r=length(p)/.0051;
	float a=atan(p.y,p.x);
	vec3 col=base_color;
	float rough=.24;
	if(tissue==0){
		float fibres=.5+.5*sin(a*92.0+sin(a*31.0)*1.8+r*7.0);
		float fine=.5+.5*sin(a*173.0-r*13.0);
		float crypts=smoothstep(.45,.82,.5+.5*sin(a*37.0+r*19.0));
		col*=.58+.32*fibres+.16*fine;
		col=mix(col,col*vec3(1.30,1.05,.65),.22*(1.0-smoothstep(.4,.7,r)));
		col*=1.0-.18*crypts;
		col*=mix(.52,1.0,(1.0-smoothstep(.72,.93,r)));
		rough=.22;
	}else if(tissue==2){
		// Off-white hydrated sclera, soft lid shadow and sparse peripheral vessels.
		float edge=smoothstep(.007,.012,length(p));
		float veins=pow(max(0.0,sin(a*17.0+sin(length(p)*1800.0)*.55)),22.0)*edge;
		col=vec3(.70,.67,.61)*mix(1.0,.80,edge);
		col=mix(col,vec3(.44,.19,.17),veins*.10);
		rough=.30;
	}else if(tissue==3){col=vec3(.0025,.002,.002);rough=.18;}
	float lid=1.0-.20*smoothstep(.001,.006,p.y);
	ALBEDO=col*lid;
	ROUGHNESS=rough;
	SPECULAR=.48;
	CLEARCOAT=.20;
	CLEARCOAT_ROUGHNESS=.14;
}
