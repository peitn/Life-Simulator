extends RefCounted
## Shared shader programs, isolated per-character parameters. Colors enter in
## sRGB exactly like the former StandardMaterial3D and are converted once.
const EYE=preload("res://shaders/character_eye.gdshader")
const LIPS=preload("res://shaders/character_lips.gdshader")
const NAILS=preload("res://shaders/character_nails.gdshader")
const EYE_KINDS={"eye_iris":0,"eye_limbus":1,"eye_sclera":2,"eye_pupil":3}
static func supports(name:String)->bool:
	return EYE_KINDS.has(name) or name=="skin_lips"
static func make(name:String)->ShaderMaterial:
	var m:=ShaderMaterial.new()
	m.resource_name="detail_"+name
	m.shader=LIPS if name=="skin_lips" else EYE
	if EYE_KINDS.has(name):m.set_shader_parameter("tissue",EYE_KINDS[name])
	return m
static func nails()->ShaderMaterial:
	var m:=ShaderMaterial.new()
	m.shader=NAILS
	return m
static func color(material:Material,c:Color)->void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("base_color",c.srgb_to_linear())
	elif material is StandardMaterial3D:
		(material as StandardMaterial3D).albedo_color=c
