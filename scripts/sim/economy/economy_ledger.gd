extends RefCounted
## Hlavní kniha (ledger) fiktivní ekonomiky: účty s CELOČÍSELNÝM zůstatkem (krejcary), dvojitý zápis,
## řetězec SHA-256 (každý záznam obsahuje hash předchozího). Žádná náhoda, žádný čas, žádné float.
##
## Pravidla:
##  - Každý záznam = převod `amount` (> 0) z účtu `from` na účet `to` (dvojitý zápis: součet všech zůstatků je vždy 0).
##  - Účty začínající "world:" (world:mint, world:burn) jsou jediné, které smějí jít do mínusu; slouží k vytvoření
##    a zničení peněz (mint/burn). Peníze v oběhu = součet zůstatků všech účtů mimo "world:".
##  - Ostatní účty nikdy nejdou do záporu (převod s nedostatkem prostředků se odmítne). Dluh je evidovaný
##    jinde (půjčky, nedoplatky), ne jako záporný zůstatek.
##  - verify() přepočítá celý řetězec a zůstatky z historie; odhalí změnu libovolného záznamu, vložení, smazání,
##    přeházení i ruční úpravu zůstatku. Nechrání proti útočníkovi, který přepočítá CELÝ řetězec – k tomu
##    slouží `head` jako externí kotva (verify_report(expected_head)).

const GENESIS := "0000000000000000000000000000000000000000000000000000000000000000"
const WORLD_PREFIX := "world:"

var accounts: Dictionary = {}   # String -> int
var entries: Array = []         # Array[Dictionary]: id, day, kind, from, to, amount, memo, prev, hash
var head: String = GENESIS


static func is_world(acc: String) -> bool:
	return acc.begins_with(WORLD_PREFIX)


static func sha256_hex(s: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(s.to_utf8_buffer())
	return ctx.finish().hex_encode()


## Kanonický text záznamu (JSON pole => jednoznačné, odolné vůči oddělovačům v memo).
static func hash_entry(e: Dictionary) -> String:
	var canon := JSON.stringify([int(e["id"]), int(e["day"]), str(e["kind"]), str(e["from"]), str(e["to"]), int(e["amount"]), str(e["memo"]), str(e["prev"])])
	return sha256_hex(canon)


func balance(acc: String) -> int:
	return int(accounts.get(acc, 0))


func size() -> int:
	return entries.size()


## Zapíše převod. Vrací {"ok": bool, "reason": String, "id": int}.
func post(day: int, kind: String, from_acc: String, to_acc: String, amount: int, memo: String = "") -> Dictionary:
	if amount <= 0:
		return {"ok": false, "reason": "amount_not_positive", "id": 0}
	if from_acc == to_acc:
		return {"ok": false, "reason": "same_account", "id": 0}
	if from_acc == "" or to_acc == "":
		return {"ok": false, "reason": "empty_account", "id": 0}
	if is_world(to_acc) and to_acc != "world:burn":
		return {"ok": false, "reason": "bad_world_target", "id": 0}
	if is_world(from_acc) and from_acc != "world:mint":
		return {"ok": false, "reason": "bad_world_source", "id": 0}
	if not is_world(from_acc) and balance(from_acc) < amount:
		return {"ok": false, "reason": "insufficient_funds", "id": 0}
	var e := {"id": entries.size() + 1, "day": day, "kind": kind, "from": from_acc, "to": to_acc,
		"amount": amount, "memo": memo, "prev": head}
	e["hash"] = hash_entry(e)
	entries.append(e)
	head = String(e["hash"])
	accounts[from_acc] = balance(from_acc) - amount
	accounts[to_acc] = balance(to_acc) + amount
	return {"ok": true, "reason": "", "id": int(e["id"])}


## Peníze v oběhu (mimo world:*).
func circulating() -> int:
	var s := 0
	for k in accounts:
		if not is_world(String(k)):
			s += int(accounts[k])
	return s


## Nezávislý součet z historie: vytvořeno − zničeno.
func minted_burned_from_entries() -> Dictionary:
	var minted := 0
	var burned := 0
	for e in entries:
		if String(e["from"]) == "world:mint":
			minted += int(e["amount"])
		if String(e["to"]) == "world:burn":
			burned += int(e["amount"])
	return {"minted": minted, "burned": burned, "net": minted - burned}


## Úplná kontrola řetězce a zůstatků. Vrací {"ok", "error", "index"} (index = 0-based pozice prvního problému).
func verify_report(expected_head: String = "") -> Dictionary:
	var prev := GENESIS
	var bal: Dictionary = {}
	for i in entries.size():
		var e: Dictionary = entries[i]
		for key in ["id", "day", "kind", "from", "to", "amount", "memo", "prev", "hash"]:
			if not e.has(key):
				return {"ok": false, "error": "missing_field_" + key, "index": i}
		if int(e["id"]) != i + 1:
			return {"ok": false, "error": "bad_id", "index": i}
		if String(e["prev"]) != prev:
			return {"ok": false, "error": "broken_link", "index": i}
		var amount := int(e["amount"])
		if amount <= 0:
			return {"ok": false, "error": "bad_amount", "index": i}
		if String(e["hash"]) != hash_entry(e):
			return {"ok": false, "error": "bad_hash", "index": i}
		var f := String(e["from"])
		var t := String(e["to"])
		if f == t:
			return {"ok": false, "error": "same_account", "index": i}
		if not is_world(f) and int(bal.get(f, 0)) < amount:
			return {"ok": false, "error": "overdraft_in_history", "index": i}
		bal[f] = int(bal.get(f, 0)) - amount
		bal[t] = int(bal.get(t, 0)) + amount
		prev = String(e["hash"])
	if prev != head:
		return {"ok": false, "error": "head_mismatch", "index": entries.size()}
	if expected_head != "" and expected_head != head:
		return {"ok": false, "error": "expected_head_mismatch", "index": entries.size()}
	var keys: Dictionary = {}
	for k in bal:
		keys[k] = true
	for k in accounts:
		keys[k] = true
	var total := 0
	for k in keys:
		var b := int(bal.get(k, 0))
		total += b
		if b != int(accounts.get(k, 0)):
			return {"ok": false, "error": "balance_mismatch_" + String(k), "index": -1}
	if total != 0:
		return {"ok": false, "error": "double_entry_sum_nonzero", "index": -1}
	return {"ok": true, "error": "", "index": -1}


func verify(expected_head: String = "") -> bool:
	return bool(verify_report(expected_head)["ok"])


func to_dict() -> Dictionary:
	var ents: Array = []
	for e in entries:
		ents.append((e as Dictionary).duplicate())
	return {"accounts": accounts.duplicate(), "entries": ents, "head": head}


static func from_dict(d: Dictionary) -> RefCounted:
	var l: RefCounted = (load("res://scripts/sim/economy/economy_ledger.gd") as GDScript).new()
	var acc: Dictionary = d.get("accounts", {})
	for k in acc:
		l.accounts[String(k)] = int(acc[k])
	var ents: Array = d.get("entries", [])
	for e in ents:
		var ed: Dictionary = e
		l.entries.append({"id": int(ed["id"]), "day": int(ed["day"]), "kind": String(ed["kind"]), "from": String(ed["from"]),
			"to": String(ed["to"]), "amount": int(ed["amount"]), "memo": String(ed["memo"]), "prev": String(ed["prev"]), "hash": String(ed["hash"])})
	l.head = String(d.get("head", GENESIS))
	return l
