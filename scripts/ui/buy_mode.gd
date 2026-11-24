extends CanvasLayer
## Režim nákupu (B1, 20. 11. 2026). Klávesa B v main.gd.
##
## Levý panel: rozpočet domácnosti, kategorie, položky s cenou a popiskem. Duch položky sleduje myš
## a přichytává se na mřížku parcely (zelený = lze postavit, červený = důvod pod panelem).
## Ovládání: levé tlačítko / Enter = postavit, R / Shift+R = otočit, klik na koupený předmět = vybrat,
## Delete / X = prodat vybraný, M = přesunout vybraný, Esc nebo B = zavřít.
## Nástroj Zeď (B2, 22. 11. 2026): T nebo tlačítko „Stavět zeď“; tažení myší od bodu k bodu mřížky hran
## (osový zámek podle delšího směru), puštění = postavit; klik na stěnu = vybrat, Delete = zbourat.
## Nástroj Dveře/Okno (B4, 23. 11. 2026): V = dveře, O = okno, Shift+O = široké okno; najeď myší na zeď
## (duch otvoru se přichytí na mřížku podél zdi), klik = osadit; klik na otvor = vybrat, Delete = vybourat a zazdít.
## UI NIKDY nemění LotGrid samo: posílá požadavek main.request_lot_action (offline/host hned, klient RPC);
## lokální LotGrid.check slouží jen pro náhled – rozhoduje server.
## Offline se při otevření hra pozastaví (jako při zařizování bytu) a při zavření se vrátí rychlost.

const LotGrid := preload("res://scripts/world/lot_grid.gd")
const Catalog := preload("res://scripts/world/buy_catalog.gd")

const PANEL_W := 340
const C_BG := Color(0.06, 0.065, 0.075, 0.9)
const C_LINE := Color(0.78, 0.66, 0.48, 0.35)
const C_TEXT := Color(0.9, 0.88, 0.84)
const C_DIM := Color(0.62, 0.6, 0.57)
const C_ACCENT := Color(0.86, 0.68, 0.42)
const C_OK := Color(0.35, 0.85, 0.5, 0.42)
const C_BAD := Color(0.95, 0.3, 0.25, 0.42)

var main: Node = null
var category := "sleep"
var selected_id := ""        # položka katalogu k postavení
var selected_uid := 0        # vybraný koupený předmět
var moving_uid := 0          # přesouvaný předmět (duch = jeho položka)
var rot := 0
var anchor := Vector2i.ZERO
var last_reason := ""
var _prev_speed := -1
## Nástroj Zeď.
var wall_tool := false
var wall_dragging := false
var wall_start := Vector2i.ZERO
var wall_end := Vector2i.ZERO
var selected_wid := 0
var _wall_ghost: MeshInstance3D
var _wall_mat: StandardMaterial3D
var _wall_btn: Button
var _wall_box: VBoxContainer
var _wall_label: Label
## Kontrola stěny se v náhledu počítá jen při změně (body, revize parcely, rozpočet).
var _wall_cache_key := ""
var _wall_cache_reason := ""
## Nástroj Dveře/Okno (B4): druh z LotGrid.OPENINGS, "" = vypnuto; cíl {"wid", "at"} pod myší.
var open_kind := ""
var open_target: Dictionary = {}
var selected_oid := 0
var _open_ghost: MeshInstance3D
var _open_mat: StandardMaterial3D
var _open_btns := {}
var _open_box: VBoxContainer
var _open_label: Label
var _lock_box: HBoxContainer

var _root: Control
var _funds: Label
var _cats: HBoxContainer
var _list: VBoxContainer
var _desc: Label
var _status: Label
var _sel_box: VBoxContainer
var _sel_label: Label
var _ghost: Node3D
var _ghost_mesh: MeshInstance3D
var _ghost_front: MeshInstance3D
var _ghost_mat: StandardMaterial3D


func _ready() -> void:
	layer = 20
	_build_ui()
	_build_ghost()
	if main != null:
		if main.has_signal("lot_changed"):
			main.lot_changed.connect(_refresh)
		if main.net != null and main.net.mode == main.net.Mode.OFFLINE and main.clock != null:
			_prev_speed = int(main.clock.speed_index)
			main.net.request_speed(0)
	_select_category(category)
	_refresh()


func close() -> void:
	if main != null and _prev_speed >= 0 and main.net != null and main.net.mode == main.net.Mode.OFFLINE:
		main.net.request_speed(_prev_speed)
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	if _wall_ghost != null and is_instance_valid(_wall_ghost):
		_wall_ghost.queue_free()
	if _open_ghost != null and is_instance_valid(_open_ghost):
		_open_ghost.queue_free()
	if main != null:
		main.buy_mode = null
	queue_free()


# ---------------------------------------------------------------- UI

func _style(bg: Color, border: Color = C_LINE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.name = "BuyPanel"
	_root.add_theme_stylebox_override("panel", _style(C_BG))
	_root.position = Vector2(12, 60)
	_root.custom_minimum_size = Vector2(PANEL_W, 0)
	add_child(_root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_root.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := _label("Zařizování", 22, C_ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_b := Button.new()
	close_b.text = "✕"
	close_b.tooltip_text = "Zavřít (Esc / B)"
	close_b.pressed.connect(close)
	head.add_child(close_b)
	_funds = _label("", 17, C_TEXT)
	_funds.name = "Funds"
	v.add_child(_funds)
	var scroll_c := ScrollContainer.new()
	scroll_c.custom_minimum_size = Vector2(PANEL_W - 20, 38)
	scroll_c.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll_c)
	_cats = HBoxContainer.new()
	scroll_c.add_child(_cats)
	for c in Catalog.CATEGORY_ORDER:
		var b := Button.new()
		b.text = String(Catalog.CATEGORIES[c])
		b.toggle_mode = true
		b.name = "Cat_" + c
		b.pressed.connect(_select_category.bind(c))
		_cats.add_child(b)
	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(PANEL_W - 20, 260)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(list_scroll)
	_list = VBoxContainer.new()
	_list.name = "Items"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_list)
	_wall_btn = Button.new()
	_wall_btn.name = "WallTool"
	_wall_btn.toggle_mode = true
	_wall_btn.text = "Stavět zeď (T) · %s / m" % _price(LotGrid.WALL_PRICE_PER_CELL * 4)
	_wall_btn.tooltip_text = "Táhni myší po mřížce. Zbourání do 24 hodin vrátí celou cenu, potom nic."
	_wall_btn.toggled.connect(set_wall_tool)
	v.add_child(_wall_btn)
	var orow := HBoxContainer.new()
	orow.name = "OpeningTools"
	v.add_child(orow)
	var keys := {"door": "V", "window": "O", "window_wide": "⇧O"}
	for k in LotGrid.OPENING_ORDER:
		var ob := Button.new()
		ob.name = "Open_" + k
		ob.toggle_mode = true
		ob.text = "%s (%s)" % [String(LotGrid.OPENINGS[k]["name"]), String(keys.get(k, ""))]
		ob.tooltip_text = "%s · %s · najeď na zeď a klikni. Vybourání do 24 hodin vrátí celou cenu." % [
			String(LotGrid.OPENINGS[k]["name"]), _price(LotGrid.opening_price(k))]
		ob.toggled.connect(func(on: bool): set_open_tool(k if on else ""))
		orow.add_child(ob)
		_open_btns[k] = ob
	_desc = _label("Vyber věc a postav ji na parcelu.", 15, C_DIM)
	_desc.custom_minimum_size = Vector2(PANEL_W - 20, 0)
	v.add_child(_desc)
	_sel_box = VBoxContainer.new()
	_sel_box.visible = false
	v.add_child(_sel_box)
	_sel_label = _label("", 15, C_TEXT)
	_sel_label.custom_minimum_size = Vector2(PANEL_W - 20, 0)
	_sel_box.add_child(_sel_label)
	var row := HBoxContainer.new()
	_sel_box.add_child(row)
	var sell_b := Button.new()
	sell_b.name = "Sell"
	sell_b.text = "Prodat (Del)"
	sell_b.pressed.connect(sell_selected)
	row.add_child(sell_b)
	var move_b := Button.new()
	move_b.name = "Move"
	move_b.text = "Přesunout (M)"
	move_b.pressed.connect(start_move)
	row.add_child(move_b)
	_wall_box = VBoxContainer.new()
	_wall_box.visible = false
	v.add_child(_wall_box)
	_wall_label = _label("", 15, C_TEXT)
	_wall_label.custom_minimum_size = Vector2(PANEL_W - 20, 0)
	_wall_box.add_child(_wall_label)
	var demo_b := Button.new()
	demo_b.name = "Demolish"
	demo_b.text = "Zbourat (Del)"
	demo_b.pressed.connect(demolish_selected_wall)
	_wall_box.add_child(demo_b)
	_open_box = VBoxContainer.new()
	_open_box.visible = false
	v.add_child(_open_box)
	_open_label = _label("", 15, C_TEXT)
	_open_label.custom_minimum_size = Vector2(PANEL_W - 20, 0)
	_open_box.add_child(_open_label)
	var unopen_b := Button.new()
	unopen_b.name = "Unopen"
	unopen_b.text = "Vybourat a zazdít (Del)"
	unopen_b.pressed.connect(demolish_selected_opening)
	_open_box.add_child(unopen_b)
	# B4b: zámek vybraných dveří (rozhoduje server: za sebe nebo pro všechny; cizí klíč neodemkneš).
	_lock_box = HBoxContainer.new()
	_lock_box.name = "LockBox"
	_open_box.add_child(_lock_box)
	for spec in [["LockMe", "Zamknout pro mě (L)", "me"], ["LockAll", "Pro všechny", "all"], ["Unlock", "Odemknout", "none"]]:
		var lb := Button.new()
		lb.name = String(spec[0])
		lb.text = String(spec[1])
		lb.focus_mode = Control.FOCUS_ALL
		lb.pressed.connect(lock_selected.bind(String(spec[2])))
		_lock_box.add_child(lb)
	_status = _label("", 15, Color(0.95, 0.55, 0.45))
	_status.custom_minimum_size = Vector2(PANEL_W - 20, 0)
	v.add_child(_status)
	v.add_child(_label("Myš/Enter postavit · R otočit · klik na věc vybrat · Del prodat · M přesunout · T zeď · V dveře · O okno · L zámek · Esc zavřít", 13, C_DIM))


func _select_category(c: String) -> void:
	category = c
	for b in _cats.get_children():
		(b as Button).button_pressed = String(b.name) == "Cat_" + c
	for ch in _list.get_children():
		ch.queue_free()
	for id in Catalog.ids_in(c):
		var it := Catalog.get_item(id)
		var b := Button.new()
		b.name = "Item_" + id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   %s" % [String(it["name"]), _price(int(it["price"]))]
		b.tooltip_text = "%s\nKvalita %s · Atmosféra %+d" % [String(it["desc"]), _stars(float(it["quality"])), int(it["appeal"])]
		b.pressed.connect(pick_item.bind(id))
		b.mouse_entered.connect(_show_desc.bind(id))
		b.focus_entered.connect(_show_desc.bind(id))
		_list.add_child(b)


static func _price(p: int) -> String:
	if p == 0:
		return "zdarma"
	var s := str(p)
	var out := ""
	var n := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		n += 1
		if n % 3 == 0 and i > 0:
			out = " " + out
	return out + " kr"


static func _meters(cells: int) -> String:
	return ("%.2f" % (float(cells) * LotGrid.CELL)).replace(".", ",")


static func _stars(q: float) -> String:
	var n := clampi(int(roundf((q - 0.6) / 0.7 * 4.0)) + 1, 1, 5)
	return "★".repeat(n) + "☆".repeat(5 - n)


func _show_desc(id: String) -> void:
	var it := Catalog.get_item(id)
	_desc.text = "%s – %s\nKvalita %s · Atmosféra %+d · %s" % [String(it["name"]), String(it["desc"]),
		_stars(float(it["quality"])), int(it["appeal"]),
		{"indoor": "dovnitř", "outdoor": "ven", "any": "kamkoli"}[String(it["place"])]]


func _refresh() -> void:
	if main == null or main.lot == null:
		return
	_funds.text = "Rozpočet domácnosti: %s" % _price(int(main.lot.funds))
	if selected_uid != 0 and not main.lot.items.has(selected_uid):
		selected_uid = 0
	if moving_uid != 0 and not main.lot.items.has(moving_uid):
		moving_uid = 0
	if selected_uid != 0:
		var rec: Dictionary = main.lot.items[selected_uid]
		var it := Catalog.get_item(String(rec["id"]))
		var now := float(main.clock.total_minutes) if main.clock != null else 0.0
		_sel_label.text = "%s · výkup %s" % [String(it["name"]), _price(main.lot.sell_value(selected_uid, now))]
		_sel_box.visible = true
	else:
		_sel_box.visible = false
	if selected_wid != 0 and not main.lot.walls.has(selected_wid):
		selected_wid = 0
	if selected_wid != 0:
		var w: Dictionary = main.lot.walls[selected_wid]
		var now2 := float(main.clock.total_minutes) if main.clock != null else 0.0
		var cells := absi(int(w["x1"]) - int(w["x0"])) + absi(int(w["z1"]) - int(w["z0"]))
		var back: int = main.lot.wall_refund_value(selected_wid, now2)
		_wall_label.text = "Zeď %s m · %s" % [_meters(cells), ("zbourání vrátí " + _price(back)) if back > 0 else "zbourání nic nevrátí"]
		_wall_box.visible = true
	else:
		_wall_box.visible = false
	if selected_oid != 0 and not main.lot.openings.has(selected_oid):
		selected_oid = 0
	if selected_oid != 0:
		var o: Dictionary = main.lot.openings[selected_oid]
		var now3 := float(main.clock.total_minutes) if main.clock != null else 0.0
		var back3: int = main.lot.opening_refund_value(selected_oid, now3)
		_open_label.text = "%s %s m · %s" % [String(LotGrid.OPENINGS[String(o["kind"])]["name"]),
			_meters(LotGrid.opening_cells(String(o["kind"]))),
			("vybourání vrátí " + _price(back3)) if back3 > 0 else "vybourání nic nevrátí"]
		var is_door := LotGrid.is_door(String(o["kind"]))
		if is_door and main.has_method("lot_lock_text"):
			_open_label.text += " · " + String(main.lot_lock_text(String(o.get("lock", ""))))
		if _lock_box != null:
			_lock_box.visible = is_door
			var lk := String(o.get("lock", ""))
			(_lock_box.get_node("Unlock") as Button).disabled = lk == ""
			(_lock_box.get_node("LockAll") as Button).disabled = lk == LotGrid.LOCK_ALL
			(_lock_box.get_node("LockMe") as Button).disabled = main.lot_my_sim() == "" or lk == main.lot_my_sim()
		_open_box.visible = true
	else:
		_open_box.visible = false


func pick_item(id: String) -> void:
	if wall_tool:
		set_wall_tool(false)
	if open_kind != "":
		set_open_tool("")
	selected_id = id
	moving_uid = 0
	selected_uid = 0
	_status.text = ""
	_show_desc(id)
	_refresh()


# ---------------------------------------------------------------- duch na mřížce

func _build_ghost() -> void:
	_ghost = Node3D.new()
	_ghost.name = "BuyGhost"
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.albedo_color = C_OK
	_ghost_mat.no_depth_test = false
	_ghost_mesh = MeshInstance3D.new()
	_ghost_mesh.mesh = BoxMesh.new()
	_ghost_mesh.material_override = _ghost_mat
	_ghost_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(_ghost_mesh)
	_ghost_front = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.2, 0.03, 0.2)
	_ghost_front.mesh = fm
	_ghost_front.material_override = _ghost_mat
	_ghost.add_child(_ghost_front)
	_ghost.visible = false
	if main != null:
		main.add_child(_ghost)
	_wall_mat = _ghost_mat.duplicate()
	_wall_ghost = MeshInstance3D.new()
	_wall_ghost.name = "WallGhost"
	_wall_ghost.mesh = BoxMesh.new()
	_wall_ghost.material_override = _wall_mat
	_wall_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wall_ghost.visible = false
	if main != null:
		main.add_child(_wall_ghost)
	_open_mat = _ghost_mat.duplicate()
	_open_ghost = MeshInstance3D.new()
	_open_ghost.name = "OpeningGhost"
	_open_ghost.mesh = BoxMesh.new()
	_open_ghost.material_override = _open_mat
	_open_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_open_ghost.visible = false
	if main != null:
		main.add_child(_open_ghost)


func _ghost_item() -> String:
	if moving_uid != 0 and main.lot.items.has(moving_uid):
		return String(main.lot.items[moving_uid]["id"])
	return selected_id


func _mouse_ground() -> Variant:
	if main == null or main.camera_rig == null:
		return null
	var cam: Camera3D = main.camera_rig.get("camera") as Camera3D
	if cam == null:
		return null
	var mp := get_viewport().get_mouse_position()
	var o := cam.project_ray_origin(mp)
	var d := cam.project_ray_normal(mp)
	if absf(d.y) < 1e-4:
		return null
	var t := -o.y / d.y
	if t <= 0.0:
		return null
	var hit := o + d * t
	return Vector2(hit.x, hit.z)


func _process(_delta: float) -> void:
	if main == null or main.lot == null:
		return
	if open_kind != "":
		_ghost.visible = false
		var og: Variant = _mouse_ground()
		if og != null:
			aim_opening(og)
		update_open_ghost()
		return
	if wall_tool:
		_ghost.visible = false
		var gw: Variant = _mouse_ground()
		if gw != null:
			var pt: Vector2i = main.lot.snap_lattice(gw)
			if wall_dragging:
				set_wall_drag(wall_start, pt)
			else:
				wall_start = pt
				wall_end = pt
		update_wall_ghost()
		return
	var id := _ghost_item()
	if id == "":
		_ghost.visible = false
		return
	var g: Variant = _mouse_ground()
	if g != null:
		anchor = main.lot.snap_anchor(id, g, rot)
	update_ghost()


## Náhled: pozice, velikost a barva ducha podle lokální kontroly (rozhoduje server).
func update_ghost() -> void:
	var id := _ghost_item()
	if id == "":
		_ghost.visible = false
		return
	var it := Catalog.get_item(id)
	var c: Vector2 = main.lot.center_of(id, anchor.x, anchor.y, rot)
	_ghost.visible = true
	_ghost.position = Vector3(c.x, 0.0, c.y)
	_ghost.rotation_degrees = Vector3(0, LotGrid.yaw_deg(rot), 0)
	var h := maxf(float(it["h"]), 0.05)
	(_ghost_mesh.mesh as BoxMesh).size = Vector3(float(it["w"]), h, float(it["d"]))
	_ghost_mesh.position = Vector3(0, h * 0.5 + 0.01, 0)
	_ghost_front.position = Vector3(0, 0.02, float(it["d"]) * 0.5 + 0.18)
	last_reason = main.lot.check(id, anchor.x, anchor.y, rot, moving_uid)
	if last_reason == "" and moving_uid == 0 and int(it["price"]) > int(main.lot.funds):
		last_reason = "funds"
	if last_reason == "" and moving_uid == 0 and main.lot.items.size() >= LotGrid.MAX_ITEMS:
		last_reason = "limit"
	_ghost_mat.albedo_color = C_OK if last_reason == "" else C_BAD
	_status.text = "" if last_reason == "" else String(LotGrid.REASON_TEXT.get(last_reason, ""))


# ---------------------------------------------------------------- akce

func place_ghost() -> void:
	var id := _ghost_item()
	if id == "" or main == null:
		return
	update_ghost()
	if last_reason != "":
		if main.hud != null:
			main.hud.show_notice(String(LotGrid.REASON_TEXT.get(last_reason, "Tohle nejde.")))
		return
	if moving_uid != 0:
		main.request_lot_action("move", [moving_uid, anchor.x, anchor.y, rot])
		moving_uid = 0
	else:
		main.request_lot_action("buy", [id, anchor.x, anchor.y, rot])


# ---------------------------------------------------------------- nástroj Zeď (B2)

func set_wall_tool(on: bool) -> void:
	if on and open_kind != "":
		set_open_tool("")
	wall_tool = on
	wall_dragging = false
	if _wall_btn != null and _wall_btn.button_pressed != on:
		_wall_btn.set_pressed_no_signal(on)
	if on:
		selected_id = ""
		moving_uid = 0
		selected_uid = 0
		_desc.text = "Zeď: táhni myší od bodu k bodu. Nesmí jít skrz nábytek, dveře ani zdi domu a nesmí zatarasit přístup k věcem."
	else:
		_status.text = ""
		_status.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))
	update_wall_ghost()
	_refresh()


## Konec tažení s osovým zámkem (delší směr vyhraje); body jsou mřížkové body hran.
func set_wall_drag(start: Vector2i, raw_end: Vector2i) -> void:
	wall_start = start
	if absi(raw_end.x - start.x) >= absi(raw_end.y - start.y):
		wall_end = Vector2i(raw_end.x, start.y)
	else:
		wall_end = Vector2i(start.x, raw_end.y)


func _wall_cells() -> int:
	return absi(wall_end.x - wall_start.x) + absi(wall_end.y - wall_start.y)


## Náhled stěny: poloha, délka, barva a důvod podle lokální kontroly (rozhoduje server).
func update_wall_ghost() -> void:
	if _wall_ghost == null:
		return
	if not wall_tool or main == null or main.lot == null:
		_wall_ghost.visible = false
		return
	var a: Vector2 = main.lot.origin + Vector2(wall_start) * LotGrid.CELL
	var b: Vector2 = main.lot.origin + Vector2(wall_end) * LotGrid.CELL
	var cells := _wall_cells()
	var h := LotGrid.WALL_HEIGHT if wall_dragging else 0.3
	var length := maxf(a.distance_to(b), 0.0) + LotGrid.WALL_THICK
	(_wall_ghost.mesh as BoxMesh).size = Vector3(length, h, LotGrid.WALL_THICK + 0.02)
	var mid := (a + b) * 0.5
	_wall_ghost.position = Vector3(mid.x, h * 0.5 + 0.01, mid.y)
	_wall_ghost.rotation_degrees = Vector3(0, 90.0 if wall_start.x == wall_end.x and wall_start.y != wall_end.y else 0.0, 0)
	_wall_ghost.visible = true
	if cells == 0:
		last_reason = ""
		_wall_mat.albedo_color = C_OK
		_status.text = ""
		return
	var key := "%d,%d,%d,%d|%d|%d" % [wall_start.x, wall_start.y, wall_end.x, wall_end.y, int(main.lot.revision), int(main.lot.funds)]
	if key != _wall_cache_key:
		_wall_cache_key = key
		_wall_cache_reason = main.lot.check_wall(wall_start.x, wall_start.y, wall_end.x, wall_end.y)
	last_reason = _wall_cache_reason
	var price: int = LotGrid.wall_price(wall_start.x, wall_start.y, wall_end.x, wall_end.y)
	if last_reason == "" and price > int(main.lot.funds):
		last_reason = "funds"
	_wall_mat.albedo_color = C_OK if last_reason == "" else C_BAD
	if last_reason == "":
		_status.text = "Zeď %s m · %s" % [_meters(cells), _price(price)]
		_status.add_theme_color_override("font_color", C_TEXT)
	else:
		_status.text = String(LotGrid.REASON_TEXT.get(last_reason, ""))
		_status.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))


func place_wall() -> void:
	wall_dragging = false
	if main == null or not wall_tool or _wall_cells() == 0:
		update_wall_ghost()
		return
	wall_dragging = true
	update_wall_ghost()
	wall_dragging = false
	if last_reason != "":
		if main.hud != null:
			main.hud.show_notice(String(LotGrid.REASON_TEXT.get(last_reason, "Tohle nejde.")))
		update_wall_ghost()
		return
	main.request_lot_action("wall", [wall_start.x, wall_start.y, wall_end.x, wall_end.y])
	wall_start = wall_end
	update_wall_ghost()


# ---------------------------------------------------------------- nástroj Dveře/Okno (B4)

## kind = druh z LotGrid.OPENINGS, "" = vypnout.
func set_open_tool(kind: String) -> void:
	if kind != "" and not LotGrid.OPENINGS.has(kind):
		kind = ""
	if kind != "" and wall_tool:
		set_wall_tool(false)
	open_kind = kind
	open_target = {}
	for k in _open_btns:
		var b: Button = _open_btns[k]
		if b.button_pressed != (k == kind):
			b.set_pressed_no_signal(k == kind)
	if kind != "":
		selected_id = ""
		moving_uid = 0
		selected_uid = 0
		_desc.text = "%s: najeď myší na postavenou zeď a klikni. Potřebuje kus zdi po obou stranách%s." % [
			String(LotGrid.OPENINGS[kind]["name"]),
			" a volný prostor před i za dveřmi" if LotGrid.is_door(kind) else ""]
	else:
		_status.text = ""
		_status.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))
	update_open_ghost()
	_refresh()


## Zaměří otvor na stěnu nejblíž bodu p (x, z): střed otvoru pod myší, přichycený na buňky podél stěny.
func aim_opening(p: Vector2) -> void:
	open_target = {}
	if open_kind == "" or main == null or main.lot == null:
		return
	var wid: int = main.lot.wall_at_world(p, 0.45)
	if wid == 0:
		return
	var w: Dictionary = main.lot.walls[wid]
	var ab: Array = main.lot.wall_world(w)
	var a: Vector2 = ab[0]
	var b: Vector2 = ab[1]
	var wl := absi(int(w["x1"]) - int(w["x0"])) + absi(int(w["z1"]) - int(w["z0"]))
	var cells := LotGrid.opening_cells(open_kind)
	var along := (p - a).dot((b - a).normalized()) / LotGrid.CELL
	var at := int(roundf(along - float(cells) * 0.5))
	at = clampi(at, LotGrid.OPENING_EDGE, maxi(LotGrid.OPENING_EDGE, wl - LotGrid.OPENING_EDGE - cells))
	open_target = {"wid": wid, "at": at}


## Náhled otvoru: poloha a barva podle lokální kontroly (rozhoduje server).
func update_open_ghost() -> void:
	if _open_ghost == null:
		return
	if open_kind == "" or main == null or main.lot == null:
		_open_ghost.visible = false
		return
	if open_target.is_empty() or not main.lot.walls.has(int(open_target["wid"])):
		_open_ghost.visible = false
		last_reason = "opening_bad"
		_status.text = "Najeď myší na postavenou zeď."
		_status.add_theme_color_override("font_color", C_DIM)
		return
	var info: Dictionary = LotGrid.OPENINGS[open_kind]
	var probe := {"oid": 0, "wid": int(open_target["wid"]), "kind": open_kind, "at": int(open_target["at"])}
	var ab: Array = main.lot.opening_world(probe)
	var mid: Vector2 = ((ab[0] as Vector2) + (ab[1] as Vector2)) * 0.5
	var sill := float(info["sill"])
	var head := float(info["head"])
	(_open_ghost.mesh as BoxMesh).size = Vector3(float(LotGrid.opening_cells(open_kind)) * LotGrid.CELL, head - sill, LotGrid.WALL_THICK + 0.06)
	_open_ghost.position = Vector3(mid.x, (sill + head) * 0.5, mid.y)
	var w: Dictionary = main.lot.walls[int(open_target["wid"])]
	_open_ghost.rotation_degrees = Vector3(0, 0.0 if int(w["z0"]) == int(w["z1"]) else 90.0, 0)
	_open_ghost.visible = true
	last_reason = main.lot.check_opening(int(open_target["wid"]), open_kind, int(open_target["at"]))
	var price := LotGrid.opening_price(open_kind)
	if last_reason == "" and price > int(main.lot.funds):
		last_reason = "funds"
	_open_mat.albedo_color = C_OK if last_reason == "" else C_BAD
	if last_reason == "":
		_status.text = "%s · %s" % [String(info["name"]), _price(price)]
		_status.add_theme_color_override("font_color", C_TEXT)
	else:
		_status.text = String(LotGrid.REASON_TEXT.get(last_reason, ""))
		_status.add_theme_color_override("font_color", Color(0.95, 0.55, 0.45))


func place_opening() -> void:
	if main == null or open_kind == "":
		return
	update_open_ghost()
	if last_reason != "":
		if main.hud != null and not open_target.is_empty():
			main.hud.show_notice(String(LotGrid.REASON_TEXT.get(last_reason, "Tohle nejde.")))
		return
	main.request_lot_action("open", [int(open_target["wid"]), open_kind, int(open_target["at"])])
	update_open_ghost()


func demolish_selected_opening() -> void:
	if selected_oid == 0 or main == null:
		return
	main.request_lot_action("unopen", [selected_oid])


## B4b: "me" = zamknout pro mou postavu, "all" = pro všechny, "none" = odemknout, "toggle" = L (moje ↔ odemčeno).
func lock_selected(how: String) -> void:
	if selected_oid == 0 or main == null or main.lot == null or not main.lot.openings.has(selected_oid):
		return
	var cur: String = main.lot.lock_of(selected_oid)
	var mine: String = main.lot_my_sim()
	var want := ""
	match how:
		"me":
			want = mine
		"all":
			want = LotGrid.LOCK_ALL
		"none":
			want = ""
		"toggle":
			want = "" if cur != "" else mine
		_:
			return
	if (how == "me" or (how == "toggle" and cur == "")) and mine == "":
		if main.hud != null:
			main.hud.show_notice("Nemáš postavu, pro kterou zamknout.")
		return
	main.request_lot_action("lock", [selected_oid, want])


func demolish_selected_wall() -> void:
	if selected_wid == 0 or main == null:
		return
	main.request_lot_action("unwall", [selected_wid])


func sell_selected() -> void:
	if selected_uid == 0 or main == null:
		return
	main.request_lot_action("sell", [selected_uid])


func start_move() -> void:
	if selected_uid == 0 or main == null or not main.lot.items.has(selected_uid):
		return
	moving_uid = selected_uid
	selected_id = ""
	rot = int(main.lot.items[selected_uid]["rot"])


func _select_at_mouse() -> bool:
	var g: Variant = _mouse_ground()
	if g == null:
		return false
	var oid: int = main.lot.opening_at_world(g, 0.3)
	if oid != 0:
		selected_oid = oid
		selected_wid = 0
		selected_uid = 0
		selected_id = ""
		moving_uid = 0
		_refresh()
		return true
	selected_oid = 0
	var uid: int = main.lot.uid_at_world(g)
	if uid == 0:
		var wid: int = main.lot.wall_at_world(g)
		if wid == 0:
			_refresh()
			return false
		selected_wid = wid
		selected_uid = 0
		selected_id = ""
		moving_uid = 0
		_refresh()
		return true
	selected_wid = 0
	selected_uid = uid
	selected_id = ""
	moving_uid = 0
	_refresh()
	return true


func _over_panel() -> bool:
	return _root.get_global_rect().has_point(get_viewport().get_mouse_position())


func _unhandled_input(event: InputEvent) -> void:
	if open_kind != "" and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _over_panel():
			return
		if not event.pressed:
			var og: Variant = _mouse_ground()
			if og != null:
				aim_opening(og)
			place_opening()
		get_viewport().set_input_as_handled()
		return
	if wall_tool and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _over_panel():
			return
		var g: Variant = _mouse_ground()
		if g != null:
			var pt: Vector2i = main.lot.snap_lattice(g)
			if event.pressed:
				wall_dragging = true
				wall_start = pt
				wall_end = pt
			elif wall_dragging:
				set_wall_drag(wall_start, pt)
				if wall_end == wall_start:
					wall_dragging = false
					_select_at_mouse()
				else:
					place_wall()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _over_panel():
			return
		if not event.pressed:
			if _ghost_item() != "":
				place_ghost()
			else:
				_select_at_mouse()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				# Q/E otáčí kameru (CameraRig), proto předmět otáčí R / Shift+R.
				rot = (rot + (3 if event.shift_pressed else 1)) % 4
			KEY_ENTER, KEY_KP_ENTER:
				place_ghost()
			KEY_DELETE, KEY_X:
				if selected_oid != 0:
					demolish_selected_opening()
				elif selected_wid != 0:
					demolish_selected_wall()
				else:
					sell_selected()
			KEY_T:
				set_wall_tool(not wall_tool)
			KEY_V:
				set_open_tool("" if open_kind == "door" else "door")
			KEY_L:
				# B4b: L zamkne vybrané dveře pro mou postavu / odemkne; Shift+L pro všechny.
				if selected_oid != 0:
					lock_selected("all" if event.shift_pressed else "toggle")
			KEY_O:
				var ok := "window_wide" if event.shift_pressed else "window"
				set_open_tool("" if open_kind == ok else ok)
			KEY_M:
				start_move()
			KEY_ESCAPE, KEY_B:
				if wall_dragging:
					wall_dragging = false
					update_wall_ghost()
				elif wall_tool:
					set_wall_tool(false)
				elif open_kind != "":
					set_open_tool("")
				elif selected_id != "" or moving_uid != 0:
					selected_id = ""
					moving_uid = 0
					_status.text = ""
				else:
					close()
			_:
				return
		get_viewport().set_input_as_handled()
