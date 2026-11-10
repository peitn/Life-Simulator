extends "res://tests/test_base.gd"
## H3 gate (8 Nov 2026): REAL rendered parity between the character-editor preview and a spawned
## character whose authored C5 wardrobe (and hair) is built asynchronously (game path:
## ClothingWardrobe.async_load, HairRig.async_build). Pixels come from the actual GPU framebuffer of
## the CharacterPreview SubViewport (same camera, light, environment, frozen idle pose).
##   REF     = editor preview, synchronous wardrobe + hair (CharacterPreview.show_draft)
##   NOCLOTH = the same reference with every garment hidden. Control only: body parts under clothes
##             are culled, so a character without any placeholder would show missing torso/legs.
##   HOLD    = cold cache: a freshly spawned SimVisual while its wardrobe builds (must show the GLB
##             placeholder clothes over the regions the outfit covers, silhouette ≈ REF)
##   FINAL   = the same spawned SimVisual after the background build (must match REF pixel for
##             pixel within a small tolerance, with exactly the same garment pieces)
## Last phase: HOLD→FINAL with BOTH hair and wardrobe asynchronous; the GLB hair "helmet" shown
## while strand cards build must have the same crown colour as the finished cards (dark and grey).
## The gameplay-only overhead marker and name label are hidden on the spawned character (they are
## not part of the look and the editor preview never draws them).
## Run under Xvfb (never --headless): xvfb-run -a godot --path <project> --rendering-method
## gl_compatibility res://tests/test_h3_async_placeholder_render.tscn -- --lease=<main lease>
## Screenshots are written only while the caller holds the live v3 main lease. Public look only.

const Wardrobe := preload("res://scripts/assets/clothing_wardrobe.gd")
const Visual := preload("res://scripts/sim/sim_visual.gd")
const Library := preload("res://scripts/assets/asset_library.gd")
const Schema := preload("res://scripts/character/character_schema.gd")
const Validator := preload("res://scripts/character/character_validator.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")
const HairRig := preload("res://scripts/assets/hair_rig.gd")
const Preview := preload("res://scripts/ui/character_preview.gd")

## CharacterPreview WorldEnvironment clear colour (foreground = anything clearly different).
const BG := Color(0.075, 0.09, 0.12)
const FG_THRESHOLD := 0.15
## FINAL vs REF: identical meshes, materials, camera and pose → only rasterisation noise allowed.
const FINAL_MAX_MEAN_DELTA := 0.002
const FINAL_MIN_IOU := 0.98
## …and no single pixel channel may differ by more than this (a mean can hide a local error;
## suggested in AI room #414).
const FINAL_MAX_PIXEL_DELTA := 0.05
## HOLD must cover what the outfit covers: coverage ≥ this share of REF's coverage in that region.
## Feet: the GLB placeholder shoe is smaller than the authored C5 trainers/pumps (≈ half the pixels),
## the check there only proves the feet are not missing.
const HOLD_MIN_COVER_RATIO := {"torso": 0.75, "legs": 0.75, "feet": 0.40}
## NOCLOTH control must really lose that region (otherwise the region check proves nothing).
const NOCLOTH_MAX_COVER_RATIO := 0.5
## HOLD silhouette vs REF: GLB placeholder clothes are simpler but the same person and pose.
## KNOWN LIMITATION: the GLB has no skirt, a dress waits as shirt + trousers (lower bound only).
const HOLD_MIN_IOU := 0.80
const HOLD_MIN_IOU_DRESS := 0.65
## Helmet placeholder vs finished strand cards: mean |ΔRGB| of the crown pixels (0..1).
const HAIR_MAX_CROWN_DELTA := 0.08

var lease := ""
var _G: Script
var _saved: Array = []


func _ready() -> void:
	watchdog_seconds = 540.0
	await _run()
	Wardrobe.async_load = false
	HairRig.async_build = false
	Wardrobe.wait_for_builds()
	finish("test_h3_async_placeholder_render")


func _fixture(top: String, bottom: String, shoes: String, first: String, hair := {}) -> Dictionary:
	var d := Schema.defaults()
	d["v"] = Schema.VERSION
	d["uid"] = CharacterData.new_uid()
	d["identity"]["first_name"] = first
	d["identity"]["last_name"] = "Náhled"
	d["personality"]["traits"] = ["hravy"]
	d["body"]["body_fat"] = 0.55
	for k in hair:
		d["hair"][k] = hair[k]
	d["clothing"]["active"] = "bezne"
	d["clothing"]["bezne"]["top"] = top
	d["clothing"]["bezne"]["bottom"] = bottom
	d["clothing"]["bezne"]["shoes"] = shoes
	var r: Dictionary = Validator.validate(d)
	if not r.get("ok", false):
		push_error("fixture invalid: " + str(r.get("errors")))
		return {}
	return r["data"]


func _snapshot(data: Dictionary) -> Dictionary:
	var c := CharacterData.new()
	c.set_from_dict(data)
	return c.public_snapshot()


func _is_fg(c: Color) -> bool:
	return absf(c.r - BG.r) + absf(c.g - BG.g) + absf(c.b - BG.b) > FG_THRESHOLD


## Mean per-channel |a-b| over a rectangle, foreground IoU and coverage of both images.
func _compare(a: Image, b: Image, rect: Rect2i) -> Dictionary:
	if a == null or b == null or a.is_empty() or b.is_empty() or a.get_size() != b.get_size():
		return {"ok": false}
	var r := rect.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return {"ok": false}
	var delta := 0.0
	var max_delta := 0.0
	var na := 0
	var nb := 0
	var both := 0
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			delta += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			max_delta = maxf(max_delta, maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))))
			var fa := _is_fg(ca)
			var fb := _is_fg(cb)
			na += int(fa)
			nb += int(fb)
			both += int(fa and fb)
			n += 1
	return {"ok": true, "mean_delta": delta / maxi(1, n * 3), "max_delta": max_delta,
		"iou": float(both) / maxi(1, na + nb - both),
		"cov_a": float(na) / maxi(1, n), "cov_b": float(nb) / maxi(1, n)}


## Mean colour of the top 5 foreground rows of the head (the hair crown), searched in a narrow
## column around the projected body axis. Empty dictionary if no head is found.
func _crown(img: Image, cam: Camera3D, height: float) -> Dictionary:
	var cx := int(round(cam.unproject_position(Vector3(0.0, height, 0.0)).x))
	var top_y := int(round(cam.unproject_position(Vector3(0.0, height * 1.08, 0.0)).y))
	var mid_y := int(round(cam.unproject_position(Vector3(0.0, height * 0.90, 0.0)).y))
	var first := -1
	for y in range(maxi(0, top_y), mini(img.get_height(), mid_y)):
		for x in range(maxi(0, cx - 4), mini(img.get_width(), cx + 5)):
			if _is_fg(img.get_pixel(x, y)):
				first = y
				break
		if first >= 0:
			break
	if first < 0:
		return {}
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(first, mini(img.get_height(), first + 5)):
		for x in range(maxi(0, cx - 8), mini(img.get_width(), cx + 9)):
			var c := img.get_pixel(x, y)
			if _is_fg(c):
				sum += c
				n += 1
	if n == 0:
		return {}
	return {"y": first, "n": n, "color": Color(sum.r / n, sum.g / n, sum.b / n)}


## Screen rectangle of a world-space box in front of the camera (x ±half_w, y from y0 to y1).
func _rect(cam: Camera3D, half_w: float, y0: float, y1: float) -> Rect2i:
	var p0: Vector2 = cam.unproject_position(Vector3(-half_w, y1, 0.0))
	var p1: Vector2 = cam.unproject_position(Vector3(half_w, y0, 0.0))
	var lo := Vector2i(int(floor(minf(p0.x, p1.x))), int(floor(minf(p0.y, p1.y))))
	var hi := Vector2i(int(ceil(maxf(p0.x, p1.x))), int(ceil(maxf(p0.y, p1.y))))
	return Rect2i(lo, hi - lo)


func _grab(preview) -> Image:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return preview.viewport.get_texture().get_image()


func _save(img: Image, tag: String) -> void:
	var path := "res://previews/h3async-%s-%s.png" % [lease, tag]
	if not _G.owns(lease):
		check(false, "main lease lost before screenshot " + tag)
		return
	if FileAccess.file_exists(path):
		check(false, "refuse to overwrite screenshot " + path)
		return
	if img.save_png(path) == OK:
		_saved.append(path)
	else:
		check(false, "screenshot saved " + path)


func _c5_names(v) -> Array:
	var out: Array = []
	for mi in v._c5_nodes:
		out.append(String(mi.name))
	return out


func _legacy_visible(v) -> Dictionary:
	var out := {}
	for mi in Library.parts_in_group(v._model, "body"):
		var n := Library.part_material_name(mi)
		if n in ["cloth_shirt", "cloth_pants", "shoe_leather"]:
			out[n] = bool(out.get(n, false)) or mi.visible
	return out


## A spawned (gameplay-like) character placed exactly where the preview draws its draft.
func _spawn(preview, snap: Dictionary):
	var v = Node3D.new()
	v.set_script(Visual)
	v.name = "SpawnedVisual"
	v.expressions_enabled = false
	v.apply_look(snap)
	preview.viewport.add_child(v)
	# Same contract as CharacterPreview's draft: frozen at the idle pose it starts with.
	v.process_mode = Node.PROCESS_MODE_DISABLED
	# Gameplay overlays (status marker, name label) are not part of the look.
	for overlay in ["_gem", "_label"]:
		var node = v.get(overlay)
		if node is Node3D:
			(node as Node3D).hide()
	return v


func _regions(preview) -> Dictionary:
	var h: float = preview._height
	return {"torso": _rect(preview.camera, 0.30, h * 0.50, h * 0.80),
		"legs": _rect(preview.camera, 0.25, h * 0.08, h * 0.48),
		"feet": _rect(preview.camera, 0.25, -0.02, h * 0.07),
		"full": Rect2i(Vector2i.ZERO, preview.viewport.size)}


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lease="):
			lease = arg.trim_prefix("--lease=")
	_G = load("res://tools/automation_lock.gd")
	if not check(lease.begins_with("main-") and _G.owns(lease), "valid live main lease required for screenshot writes"):
		return
	if not check(DisplayServer.get_name() != "headless", "real display server (Xvfb), not --headless",
			DisplayServer.get_name()):
		return
	Library.enabled = true
	if not check(Library.has_model("character") and Wardrobe.is_available() and not HairRig.context().is_empty(),
			"authored character model, C5 wardrobe and hair cards available"):
		return
	print("  renderer: ", RenderingServer.get_video_adapter_name(), " / ", RenderingServer.get_video_adapter_vendor(),
		" / ", RenderingServer.get_current_rendering_method())
	var fixtures := [
		{"tag": "hoodie", "data": _fixture("mikina", "dziny", "tenisky", "Dana"), "covers": ["torso", "legs", "feet"]},
		{"tag": "dress", "data": _fixture("saty", "zadne", "lodicky", "Ema"), "covers": ["torso", "feet"]},
		{"tag": "barefoot", "data": _fixture("tricko", "kratasy", "bosy", "Iva"), "covers": ["torso"]},
		{"tag": "greyhair", "data": _fixture("tricko", "dziny", "tenisky", "Olga",
			{"melanin": 0.15, "grey": 0.6}), "covers": ["torso", "legs"]},
	]
	for f in fixtures:
		if not check(not (f["data"] as Dictionary).is_empty(), "fictional fixture validates: " + f["tag"]):
			return

	section("REF: editor preview, synchronous wardrobe and hair + NOCLOTH control")
	Wardrobe.async_load = false
	HairRig.async_build = false
	Wardrobe.reset_cache()
	var refs := {}
	for f in fixtures:
		var preview = Preview.new()
		add_child(preview)
		preview.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		preview.show_draft(f["data"])
		var pv = preview.visual
		check(pv.uses_model() and not pv.wardrobe_waiting() and not pv.hair_waiting() and not pv._c5_nodes.is_empty(),
			"preview builds the authored wardrobe and hair synchronously: " + f["tag"], str(_c5_names(pv)))
		var ref_img: Image = await _grab(preview)
		var names := _c5_names(pv)
		var hidden: Array = []
		for mi in pv._c5_nodes:
			if mi.visible:
				mi.visible = false
				hidden.append(mi)
		for mi in Library.parts_in_group(pv._model, "body"):
			if Library.part_material_name(mi) in ["cloth_shirt", "cloth_pants", "shoe_leather"] and mi.visible:
				mi.visible = false
				hidden.append(mi)
		var bare_img: Image = await _grab(preview)
		for mi in hidden:
			mi.visible = true
		var regions := _regions(preview)
		for region_name in f["covers"]:
			var rb: Dictionary = _compare(ref_img, bare_img, regions[region_name])
			check(rb.get("ok", false) and float(rb["cov_a"]) > 0.0 and
				float(rb["cov_b"]) <= float(rb["cov_a"]) * NOCLOTH_MAX_COVER_RATIO,
				"control: without garments the %s region loses most of its pixels: %s" % [region_name, f["tag"]], str(rb))
		_save(ref_img, f["tag"] + "-ref")
		_save(bare_img, f["tag"] + "-nocloth")
		refs[f["tag"]] = {"img": ref_img, "bare": bare_img, "names": names, "regions": regions,
			"height": preview._height, "crown": _crown(ref_img, preview.camera, preview._height)}
		preview.queue_free()
		await get_tree().process_frame

	section("HOLD → FINAL: spawned character, cold wardrobe cache per outfit, ClothingWardrobe.async_load")
	await _async_phase(fixtures.slice(0, 3), refs, false)

	section("HOLD → FINAL with hair AND wardrobe asynchronous (full game path), dark and grey hair")
	await _async_phase([fixtures[0], fixtures[3]], refs, true)

	check(_saved.size() == 4 * 2 + 3 * 2 + 2 * 2, "all screenshots written (%d)" % _saved.size())
	print("H3ASYNC_SAVED ", JSON.stringify(_saved))


func _async_phase(fixtures: Array, refs: Dictionary, hair_async: bool) -> void:
	var suffix := "-fullasync" if hair_async else ""
	for f in fixtures:
		# Every outfit starts cold: the first character with it in this session.
		Wardrobe.async_load = false
		HairRig.async_build = false
		Wardrobe.wait_for_builds()
		Wardrobe.reset_cache()
		if hair_async:
			HairRig.clear_cache()
		HairRig.async_build = hair_async
		Wardrobe.async_load = true
		var ref: Dictionary = refs[f["tag"]]
		var preview = Preview.new()
		add_child(preview)
		preview.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# The draft is only used to frame the camera exactly like the editor; it stays hidden.
		preview._height = float(ref["height"])
		preview._frame_character()
		preview.visual.hide()
		var t0 := Time.get_ticks_usec()
		var v = _spawn(preview, _snapshot(f["data"]))
		var spawn_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var regions := _regions(preview)
		var tag: String = f["tag"] + suffix
		check(regions["torso"] == ref["regions"]["torso"], "same camera framing as the reference: " + tag)
		var waiting_before: bool = v.wardrobe_waiting() and (v.hair_waiting() or not hair_async)
		var hold_img: Image = await _grab(preview)
		var waiting_after: bool = v.wardrobe_waiting() and (v.hair_waiting() or not hair_async)
		check(waiting_before and waiting_after, "HOLD captured while the background build is running: " + tag,
			"before=%s after=%s" % [waiting_before, waiting_after])
		var legacy := _legacy_visible(v)
		check(legacy.get("cloth_shirt", false), "placeholder GLB top visible: " + tag, str(legacy))
		print("  spawn %s: %.0f ms main thread, legacy=%s" % [tag, spawn_ms, str(legacy)])
		for region_name in f["covers"]:
			var hr_cov: Dictionary = _compare(hold_img, ref["img"], regions[region_name])
			print("H3ASYNC_HOLD_COVER ", tag, " ", region_name, " ", JSON.stringify(hr_cov))
			check(hr_cov.get("ok", false) and float(hr_cov["cov_a"]) >= float(hr_cov["cov_b"]) * float(HOLD_MIN_COVER_RATIO[region_name]),
				"HOLD covers the %s region like the final outfit (no missing body): %s" % [region_name, tag], str(hr_cov))
		var hr: Dictionary = _compare(hold_img, ref["img"], regions["full"])
		print("H3ASYNC_HOLD_VS_REF ", tag, " ", JSON.stringify(hr))
		var min_iou: float = HOLD_MIN_IOU_DRESS if f["tag"] == "dress" else HOLD_MIN_IOU
		check(hr.get("ok", false) and float(hr["iou"]) > min_iou,
			"HOLD silhouette close to the final look (IoU > %.2f): %s" % [min_iou, tag], str(hr))
		if hair_async:
			var ch: Dictionary = _crown(hold_img, preview.camera, float(ref["height"]))
			var cr: Dictionary = ref["crown"]
			var ok_crowns := not ch.is_empty() and not cr.is_empty()
			var hd := 9.9
			if ok_crowns:
				var a: Color = ch["color"]
				var b: Color = cr["color"]
				hd = (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			print("H3ASYNC_HAIR_CROWN ", tag, " hold=", ch, " ref=", cr, " delta=", hd)
			check(ok_crowns and hd < HAIR_MAX_CROWN_DELTA,
				"helmet placeholder crown colour matches the finished hair cards (Δ %.3f < %.2f): %s" %
				[hd, HAIR_MAX_CROWN_DELTA, tag])
		# Wait for the background build + frame-spread realisation (and hair if async).
		var frames := 0
		var max_gap := 0.0
		var last := Time.get_ticks_usec()
		var deadline := Time.get_ticks_usec() + 180 * 1000000
		while (v.wardrobe_waiting() or v.hair_waiting()) and Time.get_ticks_usec() < deadline:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			max_gap = maxf(max_gap, (now - last) / 1000.0)
			last = now
			frames += 1
		check(not v.wardrobe_waiting() and not v.hair_waiting(), "background build finished, placeholder left: " + tag)
		print("  wait %s: %d frames, max frame gap %.1f ms (Xvfb software GL; diagnostic only)" % [tag, frames, max_gap])
		var final_img: Image = await _grab(preview)
		check(_c5_names(v) == ref["names"], "FINAL uses exactly the preview's garment pieces: " + tag,
			"%s vs %s" % [str(_c5_names(v)), str(ref["names"])])
		var after := _legacy_visible(v)
		check(not after.get("cloth_shirt", true) and not after.get("cloth_pants", true) and not after.get("shoe_leather", true),
			"placeholder GLB clothes hidden in FINAL: " + tag, str(after))
		var fr: Dictionary = _compare(final_img, ref["img"], regions["full"])
		print("H3ASYNC_FINAL_VS_REF ", tag, " ", JSON.stringify(fr))
		check(fr.get("ok", false) and float(fr["mean_delta"]) < FINAL_MAX_MEAN_DELTA and float(fr["iou"]) > FINAL_MIN_IOU
			and float(fr["max_delta"]) <= FINAL_MAX_PIXEL_DELTA,
			"FINAL render matches the editor preview (mean Δ < %.3f, max Δ ≤ %.2f, IoU > %.2f): %s" %
			[FINAL_MAX_MEAN_DELTA, FINAL_MAX_PIXEL_DELTA, FINAL_MIN_IOU, tag], str(fr))
		var hf: Dictionary = _compare(hold_img, final_img, regions["full"])
		print("H3ASYNC_HOLD_VS_FINAL ", tag, " ", JSON.stringify(hf))
		check(hf.get("ok", false) and float(hf["mean_delta"]) > 0.0005,
			"the swap placeholder → authored look is visible in pixels: " + tag, str(hf))
		_save(hold_img, tag + "-hold")
		_save(final_img, tag + "-final")
		v.queue_free()
		preview.queue_free()
		await get_tree().process_frame
	Wardrobe.async_load = false
	HairRig.async_build = false
