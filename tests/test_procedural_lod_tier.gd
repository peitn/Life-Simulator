extends RefCounted
const Lod = preload("res://scripts/assets/character_lod.gd")
static func run() -> Dictionary:
	var cases := [[0.30,0,0],[0.19,0,1],[0.04,1,2],[0.056,2,2],[0.064,2,1],[0.21,1,1],[0.231,1,0],[0.30,2,0],[INF,2,0],[0.04,0,2],[0.056,0,1]]
	var failures: Array[String] = []
	for item in cases:
		var got: int = Lod.tier_for(float(item[0]),int(item[1]))
		if got != int(item[2]):
			failures.append(str(item)+" got "+str(got))
	return {"ok":failures.is_empty(),"checks":cases.size(),"failures":failures}
