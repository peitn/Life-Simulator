extends SceneTree
const Design=preload("res://scripts/clothing/garment_design.gd")
const Library=preload("res://scripts/clothing/garment_library.gd")
const Builder=preload("res://scripts/clothing/garment_builder.gd")
const Styles=preload("res://scripts/assets/subculture_wardrobe.gd")
const Wardrobe=preload("res://scripts/assets/clothing_wardrobe.gd")
const Studio=preload("res://scripts/ui/clothing_studio.gd")
const CD=preload("res://scripts/character/character_data.gd")
const Schema=preload("res://scripts/character/character_schema.gd")
const Codec=preload("res://scripts/character/character_codec.gd")
const Validator=preload("res://scripts/character/character_validator.gd")
const Resolver=preload("res://scripts/character/appearance_resolver.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;print("FAIL ",label)
func _init()->void:call_deferred("run")
func run()->void:
	var recipe:Dictionary=Design.create()
	check(Design.validate(recipe).ok,"default recipe is valid")
	for pair in [["ease",INF],["ease",-1],["length",0],["sleeve_length",2],["details","yes"],["color","red"],["fabric","res://malicious.gd"],["name","bad\nname"],["format",999]]:
		var bad:Dictionary=recipe.duplicate(true)
		bad[pair[0]]=pair[1]
		check(not Design.validate(bad).ok,"reject invalid recipe parameter "+str(pair[0]))
	var bad:Dictionary=recipe.duplicate(true)
	bad.shader="injected code"
	check(not Design.validate(bad).ok,"unknown shader/code field rejected")
	check(not Design.from_json(" ".repeat(Design.MAX_BYTES+1)).ok,"oversized imported text rejected")
	check(not Design.from_json("{bad").ok,"corrupt JSON rejected")
	var source:Dictionary=CD.create().to_dict()
	source.identity.first_name="Nora"
	source.personality.traits=["aktivni"]
	var original:Dictionary=source.duplicate(true)
	var old:Dictionary=source.duplicate(true)
	old.v=18
	for slot in Schema.OUTFIT_CATEGORIES:old.clothing[slot].erase("designs")
	var old_before:String=JSON.stringify(old)
	var migrated:Dictionary=Codec.from_dict(old)
	check(migrated.ok and migrated.data.v==Schema.VERSION,"v18 migrates to new schema")
	check(old_before==JSON.stringify(old),"migration does not mutate source")
	for slot in Schema.OUTFIT_CATEGORIES:check(migrated.data.clothing[slot].designs=={},"legacy outfit has no custom design")
	recipe.pattern="checks"
	recipe.fabric="cotton"
	recipe.sleeve_length=.6
	recipe.ease=.5
	var dressed:Dictionary=Design.put_on_character(source,recipe)
	check(source==original,"custom garment only changes copied draft")
	check(dressed.identity==source.identity and dressed.mind==source.mind and dressed.body==source.body,"clothing independent of identity, psyche and body")
	var valid:Dictionary=Validator.validate(dressed,{"mode":"strict"})
	check(valid.ok,"custom garment accepted by strict character validator")
	check(Codec.decode_code(Codec.encode_code(valid.data),{"mode":"strict"}).get("data",{}).get("clothing",{}).get("bezne",{}).get("designs",{})==dressed.clothing.bezne.designs,"garment survives compressed sharing roundtrip")
	var cd:=CD.new()
	cd.set_from_dict(dressed)
	var public:Dictionary=cd.public_snapshot()
	check(public.clothing.bezne.designs==dressed.clothing.bezne.designs,"public snapshot carries only bounded garment recipe")
	check(not public.has("mind") and not public.get("personality",{}).has("hexaco") and not public.get("personality",{}).has("trait_levels"),"public garment data does not expose private axes")
	bad=dressed.duplicate(true)
	bad.clothing.bezne.designs.top.base="unknown"
	check(not Validator.validate(bad,{"mode":"strict"}).ok,"server rejects mismatched base")
	bad=dressed.duplicate(true)
	bad.clothing.bezne.designs.top["resource_path"]="/tmp/file"
	check(not Validator.validate(bad,{"mode":"strict"}).ok,"server rejects embedded file path")
	check(Validator.validate(bad,{"mode":"repair"}).data.clothing.bezne.designs.is_empty(),"repair drops corrupt design while keeping base clothes")
	var pants:Dictionary=Design.create("bottom","dziny")
	var pants_on:Dictionary=Design.put_on_character(source,pants)
	var dress_on:Dictionary=Design.put_on_character(pants_on,Design.create("top","saty"))
	check(Validator.validate(dress_on,{"mode":"strict"}).ok and not dress_on.clothing.bezne.designs.has("bottom"),"dress replaces custom bottom without stale metadata")
	var skirt_on:Dictionary=Design.put_on_character(dress_on,Design.create("bottom","kawaii_sukne"))
	check(Validator.validate(skirt_on,{"mode":"strict"}).ok and skirt_on.clothing.bezne.top=="tricko" and not skirt_on.clothing.bezne.designs.has("top"),"switching from dress to skirt produces visible valid outfit")
	var short_pants:Dictionary=Design.create("bottom","dziny")
	short_pants.length=.6
	check(Builder.parts(Resolver.resolve(Design.put_on_character(source,short_pants))).any(func(e):return e.category=="legs"),"shortened trousers reveal actual leg skin")
	var preset_on:Dictionary=Styles.apply_to_character(dressed,"punk")
	check(Validator.validate(preset_on,{"mode":"strict"}).ok and preset_on.clothing.bezne.designs.is_empty(),"ordinary style preset clears customized pieces")
	var folder:String="user://test-clothing-"+str(OS.get_process_id())+"/"
	var saved:Dictionary=Library.save_design(recipe,folder)
	check(saved.ok,"device-local recipe saved")
	check(Library.list_designs(folder).size()==1,"saved design is discoverable")
	check(Library.save_design(recipe,folder).ok and Library.list_designs(folder).size()==1,"identical saves do not duplicate recipe")
	check(Library.list_designs(folder)[0].design==Design.validate(recipe).data,"reloaded recipe equals original canonical values")
	var studio:=Studio.new()
	studio.library_directory=folder
	studio.open_design(source)
	root.add_child(studio)
	await process_frame
	await process_frame
	check(studio._preview.visual.uses_model(),"workshop uses actual rigged character")
	check(studio._base.item_count>=20,"real authored top templates selectable")
	check(studio.change("fabric","denim") and studio.change("pattern","stripes"),"material/pattern edits accepted")
	await process_frame
	var visual:Node3D=studio._preview.visual
	check(visual._c5_nodes.any(func(mi):return mi.material_override is ShaderMaterial),"patterned cloth rendered with actual material")
	var prior:String=studio.recipe().pattern
	studio.undo_design()
	check(studio.recipe().pattern!=prior,"Undo restores prior design")
	studio.redo_design()
	check(studio.recipe().pattern==prior,"Redo restores changed design")
	check(studio.import_json(Design.to_json(recipe)),"portable JSON imports into actual UI")
	await process_frame
	check(studio._preview.public_snapshot().clothing.bezne.designs.top.pattern=="checks","import changes real preview snapshot")
	check(studio.change("length",.6),"cropped hem control changes design")
	await process_frame
	check(visual._garment_midriff!=null and visual._garment_midriff.mesh.get_surface_count()==1 and visual._garment_midriff.visible,"cropped tops reveal real skinned midriff instead of empty background")
	check(visual._torso_detail_nodes.values().all(func(mi):return not mi.visible),"cropped top does not expose full anatomy meshes")
	var unchanged:Dictionary=studio.recipe()
	check(not studio.import_json("{bad") and studio.recipe()==unchanged,"invalid import preserves existing work")
	studio._pose=1
	studio._profile=2
	studio._refresh_preview()
	var forearm_rotation:Quaternion=visual._skeleton().get_bone_pose_rotation(visual._skeleton().find_bone("forearm_l"))
	check(absf(forearm_rotation.get_angle()-PI/2)<.001,"elbow fitting pose changes actual rig")
	check(studio._preview.public_snapshot().body.frame==.9,"alternate fitting body changes preview only")
	check(source==original,"fitting poses and designs do not mutate live character")
	var delivered:Dictionary={}
	studio.design_applied.connect(func(value:Dictionary):delivered.merge(value,true))
	studio._accept()
	check(delivered.get("pattern")=="checks","Apply emits reusable design instead of editing world directly")
	await process_frame
	# Explicit neutral and extreme tailored garments: source immutability, rig and morph integrity.
	var cases:Array=[["top","mikina"],["top","kawaii_kocici_mikina"],["top","kosile"],["top","tricko"],["top","saty"],["bottom","dziny"],["bottom","kawaii_sukne"],["shoes","goth_platformy"]]
	var examined:=0
	for pair in cases:
		for settings in [{"length":1.0,"sleeve_length":1.0,"ease":0.0,"cuff_flare":0.0},{"length":.6,"sleeve_length":.45,"ease":1.0,"cuff_flare":1.0},{"length":1.15,"sleeve_length":.75,"ease":.5,"cuff_flare":.5}]:
			var custom:Dictionary=Design.create(pair[0],pair[1])
			custom.merge(settings,true)
			var lp:Dictionary=Resolver.resolve(Design.put_on_character(source,custom))
			var baseline_parts:Array=Wardrobe.active_parts(lp)
			var before_signatures:Array=[]
			for entry in baseline_parts:before_signatures.append(JSON.stringify(entry.mesh.surface_get_arrays(0)))
			var parts:Array=Builder.parts(lp)
			check(not parts.is_empty(),"tailored outfit produced "+str(pair))
			for entry in parts:
				if not entry.has("design"):continue
				var mesh:Mesh=entry.mesh
				var arrays:Array=mesh.surface_get_arrays(0)
				var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
				var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
				var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
				check(mesh.get_blend_shape_count()==10,"custom piece retains all ten body morphs")
				var valid_mesh:=true
				for i in vertices.size():
					if not vertices[i].is_finite():valid_mesh=false
					var total:=0.0
					for k in 4:
						if bones[i*4+k]<0 or bones[i*4+k]>=17:valid_mesh=false
						total+=weights[i*4+k]
					if absf(total-1.0)>.0001:valid_mesh=false
				for k in range(0,indices.size(),3):
					var a:Vector3=vertices[indices[k]]
					var b:Vector3=vertices[indices[k+1]]
					var c:Vector3=vertices[indices[k+2]]
					if (b-a).cross(c-a).length_squared()<1e-15:valid_mesh=false
				check(valid_mesh,"tailored piece finite, normalized, noncollapsed "+entry.name)
				examined+=1
			for i in baseline_parts.size():check(before_signatures[i]==JSON.stringify(baseline_parts[i].mesh.surface_get_arrays(0)),"template arrays never mutated")
	check(examined>=70,"template/parameter matrix covers real pieces")
	for item in Library.list_designs(folder):DirAccess.remove_absolute(ProjectSettings.globalize_path(item.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	print("CLOTHING_STUDIO_RESULT checks=",checks," failures=",failures," pieces=",examined)
	quit(0 if failures==0 else 1)
