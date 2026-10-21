extends RefCounted
## Procedurální animace postavy nad kostrou z Blenderu (character.glb).
##
## Kosti mají v klidové poze identickou rotaci (viz lsx_decoder.gd), takže všechny rotace jsou
## v osách modelu: X = do strany (kladné X je levá strana postavy), Y = nahoru, Z = dopředu.
## Kladná rotace kolem X sklápí „dolů visící“ končetinu DOZADU, záporná DOPŘEDU.
## Každá animace obsahuje stopy pro všechny kosti (a pozici pánve), aby přechody mezi klipy
## nenechávaly „zbytky“ předchozí pózy.
##
## Klipy: idle (dýchání, přešlapování, rozhlížení), walk (cyklus kroku 1 s ≈ 1,3 m/s),
## sit (sed s rukama na stehnech, lehce opřený), lie (vleže na zádech – celé tělo otáčí SimVisual).

const BONES := ["hips", "spine", "chest", "neck", "head",
	"upper_arm_l", "forearm_l", "hand_l", "upper_arm_r", "forearm_r", "hand_r",
	"thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]
const HIPS_REST := Vector3(0, 0.95, 0)
const WALK_SPEED := 1.3          # m/s, při které walk hraje rychlostí 1.0
const SAMPLES := 16              # klíčů na smyčku

static var _lib: AnimationLibrary = null


static func library() -> AnimationLibrary:
	if _lib == null:
		_lib = AnimationLibrary.new()
		_lib.add_animation("idle", _make("idle", 4.0))
		_lib.add_animation("walk", _make("walk", 1.0))
		_lib.add_animation("sit", _make("sit", 4.0))
		_lib.add_animation("lie", _make("lie", 5.0))
	return _lib


## Póza v čase p ∈ <0, 1) → {"pos": Vector3 pánve, "<kost>": Vector3 eulerových úhlů}.
static func pose(clip: String, p: float) -> Dictionary:
	match clip:
		"walk":
			return _pose_walk(p)
		"sit":
			return _pose_sit(p)
		"lie":
			return _pose_lie(p)
	return _pose_idle(p)


static func _make(clip: String, length: float) -> Animation:
	var a := Animation.new()
	a.resource_name = clip
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR
	var pos_track := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(pos_track, NodePath("Skeleton3D:hips"))
	var rot_tracks := {}
	for b in BONES:
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath("Skeleton3D:%s" % b))
		rot_tracks[b] = t
	for i in SAMPLES + 1:
		var p := float(i) / float(SAMPLES)
		var ps: Dictionary = pose(clip, fmod(p, 1.0))
		var time := p * length
		a.position_track_insert_key(pos_track, time, ps.get("pos", HIPS_REST))
		for b in BONES:
			var e: Vector3 = ps.get(b, Vector3.ZERO)
			a.rotation_track_insert_key(rot_tracks[b], time, Quaternion.from_euler(e))
	return a


static func _base() -> Dictionary:
	var d := {"pos": HIPS_REST}
	for b in BONES:
		d[b] = Vector3.ZERO
	# Paže z A-pózy blíž k tělu, lokty lehce pokrčené.
	d["upper_arm_l"] = Vector3(0.0, 0.0, -0.1)
	d["upper_arm_r"] = Vector3(0.0, 0.0, 0.1)
	d["forearm_l"] = Vector3(-0.15, 0.0, 0.0)
	d["forearm_r"] = Vector3(-0.15, 0.0, 0.0)
	return d


static func _pose_idle(p: float) -> Dictionary:
	var d := _base()
	var w := TAU * p
	var breath := sin(w)                     # 1 nádech za 4 s ≈ 15 dechů/min
	var shift := sin(w)                      # přenášení váhy
	d["pos"] = HIPS_REST + Vector3(0.012 * shift, -0.004 * absf(shift), 0.0)
	d["hips"] = Vector3(0.0, 0.0, 0.018 * shift)
	d["spine"] = Vector3(0.015, 0.0, -0.02 * shift)
	d["chest"] = Vector3(-0.015 * breath, 0.0, 0.0)
	d["neck"] = Vector3(0.02, 0.0, 0.0)
	d["head"] = Vector3(0.03 * sin(w * 2.0 + 1.0), 0.14 * sin(w + 0.6), 0.0)
	d["thigh_l"] = Vector3(0.0, 0.0, -0.018 * shift)
	d["thigh_r"] = Vector3(0.0, 0.0, -0.018 * shift)
	d["upper_arm_l"] += Vector3(0.03 * breath, 0.0, 0.0)
	d["upper_arm_r"] += Vector3(0.03 * breath, 0.0, 0.0)
	return d


static func _pose_walk(p: float) -> Dictionary:
	var d := _base()
	for side in [["l", 0.0], ["r", 0.5]]:
		var ph := fposmod(p + float(side[1]), 1.0)
		var c := cos(TAU * ph)
		var swing := maxf(0.0, sin(TAU * (ph - 0.5)))   # švih nohy dopředu (p ∈ 0.5..1)
		var thigh := -0.42 * c
		var shin := 0.08 + 0.75 * swing
		d["thigh_" + side[0]] = Vector3(thigh, 0.0, 0.0)
		d["shin_" + side[0]] = Vector3(shin, 0.0, 0.0)
		d["foot_" + side[0]] = Vector3(-(thigh + shin) * 0.35, 0.0, 0.0)
		# Paže kmitají proti noze na stejné straně.
		var sgn := -1.0 if side[0] == "l" else 1.0
		d["upper_arm_" + side[0]] = Vector3(0.32 * c, 0.0, 0.1 * sgn)
		d["forearm_" + side[0]] = Vector3(-0.25 - 0.15 * maxf(0.0, -c), 0.0, 0.0)
	var cl := cos(TAU * p)
	d["pos"] = HIPS_REST + Vector3(0.0, -0.015 + 0.015 * cos(TAU * 2.0 * p + PI), 0.0)
	d["hips"] = Vector3(0.0, -0.08 * cl, 0.0)
	d["spine"] = Vector3(0.04, 0.05 * cl, 0.0)
	d["chest"] = Vector3(0.0, 0.07 * cl, 0.0)
	d["head"] = Vector3(-0.03, -0.1 * cl, 0.0)
	return d


static func _pose_sit(p: float) -> Dictionary:
	var d := _base()
	var breath := sin(TAU * p)
	var lean := -0.15                          # pánev opřená dozadu
	d["pos"] = Vector3(0.0, 0.5, -0.06)
	d["hips"] = Vector3(lean, 0.0, 0.0)
	d["spine"] = Vector3(0.05, 0.0, 0.0)
	d["chest"] = Vector3(-0.012 * breath, 0.0, 0.0)
	d["head"] = Vector3(0.1, 0.12 * sin(TAU * p), 0.0)
	for s in ["l", "r"]:
		var out := 0.06 if s == "l" else -0.06
		d["thigh_" + s] = Vector3(-PI / 2.0 - lean, 0.0, out)
		d["shin_" + s] = Vector3(1.45, 0.0, 0.0)
		d["foot_" + s] = Vector3(0.12, 0.0, 0.0)
		d["upper_arm_" + s] = Vector3(-0.45, 0.0, -0.05 if s == "l" else 0.05)
		d["forearm_" + s] = Vector3(-0.75, 0.0, 0.0)
	return d


static func _pose_lie(p: float) -> Dictionary:
	var d := _base()
	var breath := sin(TAU * p)
	d["chest"] = Vector3(-0.02 * breath, 0.0, 0.0)
	d["head"] = Vector3(0.05, 0.25, 0.0)
	d["upper_arm_l"] = Vector3(0.0, 0.0, -0.16)
	d["upper_arm_r"] = Vector3(0.0, 0.0, 0.16)
	d["forearm_l"] = Vector3(-0.2, 0.0, 0.0)
	d["forearm_r"] = Vector3(-0.35, 0.0, 0.0)
	d["thigh_l"] = Vector3(0.0, 0.0, 0.05)
	d["thigh_r"] = Vector3(-0.1, 0.0, -0.05)
	d["shin_l"] = Vector3(0.06, 0.0, 0.0)
	d["shin_r"] = Vector3(0.2, 0.0, 0.0)
	d["foot_l"] = Vector3(0.3, 0.0, 0.0)
	d["foot_r"] = Vector3(0.3, 0.0, 0.0)
	return d
