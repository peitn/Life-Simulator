"""Import the measured Godot M2 GLBs as editable native Blender collections.
Run inside Blender 4+ with CITY_M2_SOURCE pointing to an extracted M2 asset bundle.
The canonical primitive authoring catalogue stays beside its exported GLBs.
"""
import bpy, pathlib, os, json, hashlib
root=pathlib.Path(os.environ.get('CITY_M2_SOURCE','/tmp/lifesim-city-m2-complete'))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
records={}
paths=sorted((root/'assets/city/fixtures').glob('*.glb'))+sorted((root/'assets/models').glob('*.glb'))+[root/'docs/city/furniture_editor_example.glb']
for path in paths:
 before=set(bpy.data.objects);bpy.ops.import_scene.gltf(filepath=str(path));objects=set(bpy.data.objects)-before
 collection=bpy.data.collections.new(path.stem);bpy.context.scene.collection.children.link(collection)
 for obj in objects:
  for old in list(obj.users_collection):old.objects.unlink(obj)
  collection.objects.link(obj)
  if obj.type=='MESH':
   assert len(obj.data.vertices)>0
   assert all(all(__import__('math').isfinite(v) for v in vertex.co) for vertex in obj.data.vertices)
 for obj in objects:obj.select_set(False)
 records[path.stem]={'source':str(path.relative_to(root)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'meshes':sum(o.type=='MESH' for o in objects),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects if o.type=='MESH')}
 collection.hide_render=path.stem!='stove';collection.hide_viewport=path.stem!='stove'
for image in bpy.data.images:
 if image.source=='FILE' and image.has_data:image.pack()
bpy.context.scene.render.engine='CYCLES'
bpy.ops.wm.save_as_mainfile(filepath=str(root/'m2_complete.blend'),compress=True)
(root/'native_manifest.json').write_text(json.dumps({'version':1,'models':records,'packed_images':sum(bool(i.packed_file) for i in bpy.data.images)},indent=2))
print('M2_NATIVE',len(records),'models',sum(r['meshes'] for r in records.values()),'meshes')
