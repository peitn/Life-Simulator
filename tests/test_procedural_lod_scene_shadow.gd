extends RefCounted
const Visual = preload("res://scripts/sim/sim_visual.gd")
static func run() -> Dictionary:
	var v = Visual.new()
	var model = Node3D.new()
	var part = MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	part.position = Vector3(0.3, 1.2, -0.2)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	model.add_child(part)
	v.add_child(model)
	v._model = model
	v._lod_shadow_nodes = [part]
	var pose = part.transform
	var mesh = part.mesh
	var fails: Array[String] = []
	var checks = 0
	for t in [1, 0, 1, 0]:
		checks += 1
		if not v.set_lod_tier(t) or v.lod_tier() != t:
			fails.append("tier "+str(t))
		checks += 1
		var expected = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if t == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if part.cast_shadow != expected:
			fails.append("shadow "+str(t))
		checks += 1
		if part.transform != pose or part.mesh != mesh:
			fails.append("pose/mesh "+str(t))
	v.free()
	return {"ok":fails.is_empty(),"checks":checks,"failures":fails}
