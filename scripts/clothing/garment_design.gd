extends RefCounted
## Portable, bounded data only. No paths, shader source, scripts or external assets.
const FORMAT := 1
const MAX_BYTES := 4096
const KINDS := {"top":"Vrchní díl / šaty", "bottom":"Spodní díl", "shoes":"Obuv"}
const FABRICS := {"original":"Původní látka", "cotton":"Bavlna", "denim":"Denim", "fleece":"Fleece", "knit":"Úplet", "leather":"Kůže", "satin":"Satén", "suiting":"Obleková látka"}
const PATTERNS := {"solid":"Jednobarevné", "stripes":"Pruhy", "checks":"Kostka", "dots":"Puntíky"}
const NUMBERS := {"ease":[0.0,1.0,0.0], "length":[0.6,1.15,1.0], "sleeve_length":[0.45,1.0,1.0], "cuff_flare":[0.0,1.0,0.0], "pattern_scale":[0.5,4.0,1.0], "roughness":[0.25,1.0,0.8]}
const FIELDS := ["format","name","kind","base","fabric","pattern","color","accent","ease","length","sleeve_length","cuff_flare","pattern_scale","roughness","details"]

static func create(kind:String="top", base:String="mikina") -> Dictionary:
	var d:Dictionary={"format":FORMAT,"name":"Můj návrh","kind":kind,"base":base,"fabric":"original","pattern":"solid","color":"#b26d9b","accent":"#f0e8ed","details":true}
	for key in NUMBERS: d[key]=NUMBERS[key][2]
	return d

static func validate(raw:Variant) -> Dictionary:
	var errors:PackedStringArray=[]
	if not raw is Dictionary or raw.size()>FIELDS.size():
		return {"ok":false,"data":{},"errors":PackedStringArray(["Návrh musí být malý slovník parametrů."])}
	for key in raw:
		if not key is String or key not in FIELDS: errors.append("Neznámé pole návrhu: "+str(key).left(40))
	var d:Dictionary=create()
	if typeof(raw.get("format")) not in [TYPE_INT,TYPE_FLOAT] or float(raw.get("format",0))!=FORMAT:
		errors.append("Nepodporovaná verze návrhu.")
	for key in ["name","base"]:
		var value:Variant=raw.get(key,"")
		if not value is String or value.strip_edges().is_empty() or value.length()>48:
			errors.append("Neplatný název nebo základ návrhu.")
			continue
		var valid:=true
		for i in value.length():
			var ch:int=value.unicode_at(i)
			if ch<32 or ch==127 or (ch>=0x80 and ch<0xa0) or (ch>=0x202a and ch<=0x202e) or (ch>=0x2066 and ch<=0x2069): valid=false
		if not valid: errors.append("Název obsahuje řídicí znaky.")
		d[key]=value.strip_edges()
	for pair in [["kind",KINDS],["fabric",FABRICS],["pattern",PATTERNS]]:
		var value:Variant=raw.get(pair[0],d[pair[0]])
		if value is String and pair[1].has(value): d[pair[0]]=value
		else: errors.append("Neplatná volba: "+str(pair[0]))
	for key in ["color","accent"]:
		var value:Variant=raw.get(key,d[key])
		if value is String and value.length()==7 and value.begins_with("#") and value.substr(1).is_valid_hex_number(false): d[key]=value.to_lower()
		else: errors.append("Barva musí být #rrggbb.")
	for key in NUMBERS:
		var value:Variant=raw.get(key,d[key])
		var spec:Array=NUMBERS[key]
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)<spec[0] or float(value)>spec[1]:
			errors.append("Parametr mimo rozsah: "+str(key))
		else: d[key]=snappedf(float(value),.001)
	if raw.has("details") and not raw.details is bool: errors.append("Detaily musí být ano/ne.")
	else: d.details=raw.get("details",true)
	return {"ok":errors.is_empty(),"data":d if errors.is_empty() else {},"errors":errors}

static func from_json(text:String) -> Dictionary:
	if text.to_utf8_buffer().size()>MAX_BYTES:
		return {"ok":false,"data":{},"errors":PackedStringArray(["Návrh je příliš velký."])}
	var parser:=JSON.new()
	if parser.parse(text)!=OK:
		return {"ok":false,"data":{},"errors":PackedStringArray(["JSON návrhu je poškozený."])}
	return validate(parser.data)

static func to_json(d:Dictionary) -> String:
	return JSON.stringify(d,"\t",true)

static func signature(d:Dictionary) -> String:
	return JSON.stringify(d,"",true).sha256_text()

static func put_on_character(source:Dictionary, recipe:Dictionary, slot:String="bezne") -> Dictionary:
	var checked:Dictionary=validate(recipe)
	if not checked.ok or slot not in ["bezne","pracovni","spolecenske","spani","sport"]: return {}
	var d:Dictionary=source.duplicate(true)
	if not d.get("clothing",{}) is Dictionary or not d.clothing.get(slot,{}) is Dictionary: return {}
	var outfit:Dictionary=d.clothing.get(slot,{})
	var kind:String=checked.data.kind
	outfit[kind]=checked.data.base
	var raw_designs:Variant=outfit.get("designs",{})
	var designs:Dictionary=raw_designs.duplicate(true) if raw_designs is Dictionary else {}
	designs[kind]=checked.data.duplicate(true)
	outfit["designs"]=designs
	if kind=="top" and recipe.base=="saty":
		outfit.bottom="zadne"
		designs.erase("bottom")
	elif kind=="top" and outfit.get("bottom")=="zadne": outfit.bottom="kalhoty"
	if kind=="bottom" and outfit.get("top")=="saty":
		outfit.top="tricko"
		designs.erase("top")
	if kind=="top":outfit.top_color=recipe.color
	elif kind=="bottom":outfit.bottom_color=recipe.color
	d.clothing[slot]=outfit
	d["clothing"]["active"]=slot
	return d
