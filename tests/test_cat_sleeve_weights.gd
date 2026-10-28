extends SceneTree
## H2b regression: sleeve weights remain on their own arm chain.
## Not a full pose/clipping certification.
const Wardrobe = preload("res://scripts/assets/clothing_wardrobe.gd")
var failed := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failed += 1

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var source := FileAccess.get_file_as_string("res://tools/blender/clothing_c5.py")
	check(source.contains('make_mesh("sleeve_%s"%side,verts,faces,src["cloth_shirt"],MAT[kind],"top",style,sleeve_bones)'), "generator uses authored arm-only sleeve override")
	for style in ["mikina", "kawaii_kocici_mikina", "svetr", "rolak", "sako", "kosile", "emo_mikina", "kawaii_svetr", "harajuku_bunda", "grunge_kosile", "visualkei_sako"]:
		var parts := {}
		for info in Wardrobe.parts("top", style):
			parts[String(info.get("name", ""))] = info["mesh"]
		check(parts.has("shell") and parts.has("sleeve_-1") and parts.has("sleeve_1"), style + " authored shell and sleeves")
		if not parts.has("sleeve_-1") or not parts.has("sleeve_1"):
			continue
		for side in ["sleeve_-1", "sleeve_1"]:
			var arrays: Array = (parts[side] as ArrayMesh).surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := int(bones.size() / verts.size()) if verts.size() > 0 else 0
			check(per == 4 and verts.size() == 70 and weights.size() == bones.size(), style + "/" + side + " skin arrays")
			if per != 4 or verts.size() != 70:
				continue
			var ymin := INF
			var ymax := -INF
			for v in verts:
				ymin = minf(ymin, v.y)
				ymax = maxf(ymax, v.y)
			var lower := 0
			var upper := 0
			var lower_wrong := 0.0
			var upper_wrong := 0.0
			var lower_thigh := 0.0
			var upper_thigh := 0.0
			var max_sum_error := 0.0
			var wrong_arm := 0.0
			var shoulder_arm := 0.0
			var shoulder_forearm := 0.0
			var second_forearm := 0.0
			var second_count := 0
			var shoulder_index := 5 if side == "sleeve_1" else 11
			var forearm_index := shoulder_index + 1
			var allowed = [5,6,7] if side == "sleeve_1" else [11,12,13]
			for i in verts.size():
				var leg_or_hip := 0.0
				var thigh := 0.0
				var total := 0.0
				for k in per:
					var b := bones[i * per + k]
					var w := weights[i * per + k]
					total += w
					if b not in allowed and not (absf(verts[i].y-ymax)<.001 and b in [0,1,2]): wrong_arm += w
					if absf(verts[i].y - ymax) < 0.001:
						if b == shoulder_index: shoulder_arm += w
						if b == forearm_index: shoulder_forearm += w
					if absf(verts[i].y - 1.108) < 0.001 and b == forearm_index:
						second_forearm += w
					if b in [8, 9, 10, 14, 15, 16] or (b==0 and absf(verts[i].y-ymax)>=.001):
						leg_or_hip += w
					if b in [8, 14]:
						thigh += w
				max_sum_error = maxf(max_sum_error, absf(total - 1.0))
				if absf(verts[i].y - 1.108) < 0.001:
					second_count += 1
				if absf(verts[i].y - ymin) < 0.001:
					lower += 1
					lower_wrong += leg_or_hip
					lower_thigh += thigh
				if absf(verts[i].y - ymax) < 0.001:
					upper += 1
					upper_wrong += leg_or_hip
					upper_thigh += thigh
			var bad_lower := lower_wrong / maxf(1.0, float(lower))
			var bad_upper := upper_wrong / maxf(1.0, float(upper))
			var thigh_lower := lower_thigh / maxf(1.0, float(lower))
			var thigh_upper := upper_thigh / maxf(1.0, float(upper))
			print("WEIGHT_BASELINE style=", style, " side=", side, " lower_wrong=", bad_lower, " upper_wrong=", bad_upper, " lower_thigh=", thigh_lower, " upper_thigh=", thigh_upper, " lower_n=", lower, " upper_n=", upper, " max_sum_error=", max_sum_error)
			check(lower == 14 and upper == 14 and max_sum_error < 0.0001, style + "/" + side + " rings normalized")
			check(bad_lower < 0.001 and bad_upper < 0.001 and wrong_arm < 0.001, style + "/" + side + " only seam rim may share matching torso weights; no opposite limb influences")
			check(thigh_lower < 0.001 and thigh_upper < 0.001, style + "/" + side + " no thigh weights at wrist ring")
			check(absf(ymax - 1.209) < 0.001 and second_count == 14, style + "/" + side + " authored shoulder and transition geometry")
			check(shoulder_arm > 1.39 and shoulder_forearm < 12.61, style + "/" + side + " seam retains upper-arm anchor while following shell skin")
			check(second_forearm / maxf(1.0, float(second_count)) > 0.35 and second_forearm / maxf(1.0, float(second_count)) < 0.37,
				style + "/" + side + " smooth forearm transition ring")
	print("SLEEVE_WEIGHT_BASELINE checks=", checks, " failed=", failed)
	quit(0 if failed == 0 else 1)
