extends Node3D
## B4 (23. 11. 2026): pant křídla dveří ve stěně parcely. Když je v dosahu postava, křídlo se plynule otevře
## a po jejím odchodu zase zavře. Čistě vizuální – průchodnost řeší LotGrid (hrany v rozsahu dveří jsou volné)
## a dveře nemají kolizi. Běží na serveru i u klientů (u klientů jsou ve world.sims loutky postav).
## B4b (24. 11. 2026): zámek. Zamčené dveře se otevřou jen postavě s klíčem (LotGrid.door_passable – jméno
## uzlu postavy je u serveru i u klientů stejné); kontrolka u kliky ukazuje stav: zelená odemčeno,
## jantarová osobní zámek, červená zamčeno pro všechny. Stav se čte z parcely při každé kontrole okolí,
## takže se po změně zámku nemusí stavět znovu uzel stěny.

const LotGridDoor := preload("res://scripts/world/lot_grid.gd")
const OPEN_DEG := 100.0
## Dosah od středu otvoru (m), kdy se dveře otevírají.
const NEAR := 1.4
## Rychlost otvírání (°/s) a interval kontroly okolí (s).
const SPEED := 260.0
const POLL := 0.12
const LAMP_OPEN := Color(0.3, 0.72, 0.38)
const LAMP_OWN := Color(0.95, 0.66, 0.2)
const LAMP_ALL := Color(0.9, 0.2, 0.18)

## Svět (main.gd) – kvůli seznamu postav a parcele. Slabá vazba: když zmizí, dveře zůstanou zavřené.
var world: Node = null
## oid otvoru v LotGrid (0 = neznámé → bez zámku) a šířka křídla (poloha kontrolky).
var oid := 0
var leaf_w := 0.8
var angle := 0.0
var want_open := false
## "" / "*" / klíč postavy – poslední přečtený zámek.
var lock_state := ""
var _poll := 0.0
var _lamp: MeshInstance3D
var _lamp_mat: StandardMaterial3D


func _ready() -> void:
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.emission_enabled = true
	_lamp_mat.roughness = 0.35
	_lamp = MeshInstance3D.new()
	_lamp.name = "LockLamp"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.022, 0.045, 0.014)
	_lamp.mesh = bm
	_lamp.material_override = _lamp_mat
	_lamp.position = Vector3(maxf(leaf_w - 0.1, 0.05), 1.11, 0.03)
	_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lamp)
	_update_lamp()


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL
		var lk := read_lock()
		if lk != lock_state:
			lock_state = lk
			_update_lamp()
		want_open = someone_near()
	step(delta)


## Posune úhel křídla k cíli (otevřeno/zavřeno). Volají i testy.
func step(delta: float) -> void:
	angle = move_toward(angle, OPEN_DEG if want_open else 0.0, SPEED * maxf(delta, 0.0))
	rotation_degrees.y = angle


## Záznam otvoru z parcely světa ({} = nic).
func _record() -> Dictionary:
	if oid <= 0 or world == null or not is_instance_valid(world):
		return {}
	var lot: Variant = world.get("lot")
	if lot == null or typeof(lot) != TYPE_OBJECT:
		return {}
	var ops: Variant = lot.get("openings")
	if typeof(ops) != TYPE_DICTIONARY or not (ops as Dictionary).has(oid):
		return {}
	return ops[oid]


func read_lock() -> String:
	return String(_record().get("lock", ""))


## Je nějaká postava S PRŮCHODEM blíž než NEAR od středu otvoru (rodič = držák otvoru)?
func someone_near() -> bool:
	if world == null or not is_instance_valid(world) or not is_inside_tree():
		return false
	var sims: Variant = world.get("sims")
	if typeof(sims) != TYPE_ARRAY:
		return false
	var holder := get_parent() as Node3D
	if holder == null:
		return false
	var rec := _record()
	var c := holder.global_position
	for s in sims:
		if is_instance_valid(s) and s is Node3D:
			if not rec.is_empty() and not LotGridDoor.door_passable(rec, String((s as Node3D).name)):
				continue
			var p: Vector3 = (s as Node3D).global_position
			if Vector2(p.x - c.x, p.z - c.z).length() <= NEAR:
				return true
	return false


func lamp_color() -> Color:
	if lock_state == "":
		return LAMP_OPEN
	return LAMP_ALL if lock_state == LotGridDoor.LOCK_ALL else LAMP_OWN


func _update_lamp() -> void:
	if _lamp_mat == null:
		return
	var c := lamp_color()
	_lamp_mat.albedo_color = c
	_lamp_mat.emission = c
	_lamp_mat.emission_energy_multiplier = 0.4 if lock_state == "" else 1.6
