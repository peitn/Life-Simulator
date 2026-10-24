extends Node3D
## A neutral full-body mosaic occluder for opt-in, implied adult sensitive events.
## Displays no body part, injury, gesture, implement, animation or method. The
## original visual is actually hidden; squares are a solid opaque substitute.
## Local/offline display only. Never serialize or replicate this node.
signal completed

const MASK_SECONDS := 2.4
var _covered: Node3D = null
var _remaining := 0.0
var _active := false
var _mosaic: MeshInstance3D

func begin(visual: Node3D, seconds: float = MASK_SECONDS) -> bool:
	if _active or visual == null or not is_instance_valid(visual):
		return false
	_covered = visual
	_covered.visible = false
	_remaining = clampf(seconds, 0.2, 12.0)
	if _mosaic == null:
		_mosaic = MeshInstance3D.new()
		_mosaic.name = "NeutralMosaic"
		var box := BoxMesh.new()
		box.size = Vector3(1.3, 2.4, 1.2)
		_mosaic.mesh = box
		_mosaic.position = Vector3(0.0, 1.2, 0.0)
		_mosaic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Spatial unshaded opaque grid; deliberately not a shader sampling the
		# (potentially uncensored) frame, so no pixelation bypass can reveal it.
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec2 cell = floor(UV * vec2(11.0, 19.0));
	float salt = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 dark = vec3(0.22, 0.24, 0.29);
	vec3 light = vec3(0.34, 0.35, 0.41);
	ALBEDO = mix(dark, light, step(0.5, salt));
}"""
		var mat := ShaderMaterial.new()
		mat.shader = shader
		_mosaic.material_override = mat
		add_child(_mosaic)
	_mosaic.visible = true
	_active = true
	set_process(true)
	return true

func _process(delta: float) -> void:
	if not _active:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		end()

func end() -> void:
	if not _active:
		return
	_active = false
	_remaining = 0.0
	set_process(false)
	if _mosaic != null:
		_mosaic.visible = false
	if _covered != null and is_instance_valid(_covered):
		_covered.visible = true
	_covered = null
	completed.emit()

func is_covering() -> bool:
	return _active

func _exit_tree() -> void:
	# Never strand an invisible character if scene changes mid-transition.
	if _covered != null and is_instance_valid(_covered):
		_covered.visible = true
	_covered = null
