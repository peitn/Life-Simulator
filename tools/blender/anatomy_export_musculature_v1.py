"""Export the distinct Blender muscle layer as its own optional GLB.
This DOES NOT replace character.glb or attach physics to live characters.
"""
import bpy, os, hashlib, json, datetime
base='/app/data/library/model/lifesim-anatomy-skeleton-v1'
blend=os.path.join(base,'anatomy_skeleton_v1.blend')
bpy.ops.wm.open_mainfile(filepath=blend)
rig=bpy.data.objects.get('Anatomy_Rig_V1')
assert rig and len(rig.data.bones)>=190
bpy.ops.object.select_all(action='DESELECT')
muscles=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('Muscle_')]
assert len(muscles)==60, len(muscles)
for o in muscles:o.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active=rig
path=os.path.join(base,'anatomy_musculature_v1.glb')
bpy.ops.export_scene.gltf(filepath=path,export_format='GLB',
    use_selection=True,export_extras=True)
assert os.path.getsize(path)>10000
info={'file':'anatomy_musculature_v1.glb','bundle_count':len(muscles),
      'contains_rig':True,'contains_physics':False,
      'activation_solver':'not_implemented',
      'max_force_units':'newtons, order-of-magnitude starting values only'}
with open(os.path.join(base,'muscle_manifest.json'),'w') as f:json.dump(info,f,indent=2)
meta_path=os.path.join(base,'meta.json')
with open(meta_path) as f:meta=json.load(f)
meta['updated']=datetime.datetime.now(datetime.timezone.utc).isoformat()
meta['files']=[]
for filename in sorted(os.listdir(base)):
    file=os.path.join(base,filename)
    if filename=='meta.json' or not os.path.isfile(file):continue
    with open(file,'rb') as f:content=f.read()
    meta['files'].append({'path':filename,'bytes':len(content),
                        'sha256':hashlib.sha256(content).hexdigest()})
with open(meta_path,'w') as f:json.dump(meta,f,ensure_ascii=False,indent=2)
print('MUSCLE_EXPORT_OK count=',len(muscles),'bytes=',os.path.getsize(path),
      'rig_bones=',len(rig.data.bones))