#!/usr/bin/env python3
"""Rebuild runtime anatomical landmark index for the actual Godot character.

This is NOT an exporter of the full Blender sculpt meshes. The index contains
real reference positions and world-space extents from the editable separate
Anatomy_Rig_V1 scene. Render-only low-poly Godot parts follow their nearest
existing character.glb 17 animation bones via BoneAttachment3D.

Blender 4.0, Z-up metres -> Godot Y-up metres via (x,z,-y).
Output: model library asset anatomy_runtime_proxy_v1.json & .json.gz.
Copy to Godot assets/anatomy/anatomy_runtime_proxy_v1.json after validating
194 bone drivers / 60 muscle bundles / 60 cartilage pieces / 6 fat volumes.
"""
import bpy, json, gzip, hashlib
from pathlib import Path
from mathutils import Vector

ROOT=Path('/app/data/library/model/lifesim-anatomy-skeleton-v1')
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'anatomy_skeleton_v1.blend'))
rig=bpy.data.objects['Anatomy_Rig_V1']
CANONICAL=[
    'hips','spine','chest','neck','head',
    'upper_arm_l','forearm_l','hand_l',
    'upper_arm_r','forearm_r','hand_r',
    'thigh_l','shin_l','foot_l',
    'thigh_r','shin_r','foot_r'
]
assert len(CANONICAL)==17
assert all(x in rig.data.bones for x in CANONICAL)
def roundvec(p:Vector)->list[float]:
    return [round(p.x,6),round(p.z,6),round(-p.y,6)]
def driver(bone)->str:
    while bone is not None:
        if bone.name in CANONICAL:return bone.name
        bone=bone.parent
    return 'hips'
def proxy_radius(name:str)->float:
    if name.startswith('finger_'):return .0038
    if name.startswith('toe_'):return .0033
    if name.startswith('vertebra_'):return .017
    if name.startswith('rib_'):return .0065
    if name.startswith(('carpal_','tarsal_')):return .006
    if name.startswith(('metacarpal_','metatarsal_')):return .007
    if name.startswith(('ilium_','ischium_','sacrum')):return .027
    if name.startswith(('thigh_','shin_','upper_arm_','forearm_')):return .021
    if name=='head':return .075
    return .013
def limb_driver(label,side):
    group=str(label.get('group',''))
    if group in ('arm','shoulder','rotator_cuff'):return 'upper_arm_'+side if side else 'chest'
    if group=='forearm':return 'forearm_'+side if side else 'chest'
    if group in ('hip','thigh'):return 'thigh_'+side if side else 'hips'
    if group=='calf':return 'shin_'+side if side else 'hips'
    if group in ('back','chest','thorax'):return 'chest'
    if group=='neck':return 'neck'
    if group=='abdomen':return 'spine'
    return 'chest'

bone_data=[]
for b in rig.data.bones:
    bone_data.append({'n':b.name,'h':roundvec(b.head_local),
        't':roundvec(b.tail_local),'d':driver(b),'r':proxy_radius(b.name)})
muscle_data=[]
for o in bpy.data.objects:
    if not o.name.startswith('Muscle_') or o.type!='MESH':continue
    pts=[v.co.copy() for v in o.data.vertices]
    if len(pts)<36:continue
    a=sum(pts[:12],Vector())/12
    b=sum(pts[-12:],Vector())/12
    name=o.name.removeprefix('Muscle_')
    side='l' if name.endswith('_l') else ('r' if name.endswith('_r') else '')
    radius=sum((v-a).length for v in pts[:12])/12
    muscle_data.append({'n':name,'h':roundvec(a),'t':roundvec(b),
        'd':limb_driver(o,side),'r':round(radius,5)})
cartilage_data=[]
for o in bpy.data.objects:
    if not o.name.startswith('Cartilage_') or o.type!='MESH':continue
    pts=[o.matrix_world@v.co for v in o.data.vertices]
    if not pts:continue
    center=sum(pts,Vector())/len(pts)
    ext=[max(abs(v[k]-center[k]) for v in pts) for k in range(3)]
    d=min(CANONICAL,key=lambda name:(rig.data.bones[name].head_local-center).length_squared)
    cartilage_data.append({'n':o.name.removeprefix('Cartilage_'),
       'p':roundvec(center),'e':[round(max(.002,x),5) for x in (ext[0],ext[2],ext[1])],'d':d})
fat_data=[]
for o in bpy.data.objects:
    if not o.name.startswith('Adipose_') or o.type!='MESH':continue
    points=[o.matrix_world@v.co for v in o.data.vertices]
    lo=[min(v[k] for v in points) for k in range(3)]
    hi=[max(v[k] for v in points) for k in range(3)]
    center=Vector([(a+b)*.5 for a,b in zip(lo,hi)])
    ext=[max(.005,(hi[k]-lo[k])*.5) for k in (0,2,1)]
    fat_data.append({'n':o.name.removeprefix('Adipose_'),'p':roundvec(center),
                     'e':[round(x,5) for x in ext],
                     'd':o.get('anatomy_bone','hips')})
assert (len(bone_data),len(muscle_data),len(cartilage_data),len(fat_data))==(194,60,60,6)
out={
 'schema':'lifesim.blender.anatomy-proxy.v1',
 'coordinate_system':'Godot Y-up from Blender z-up; x=z unchanged, Blender y -> Godot -z',
 'source':'lifesim-anatomy-skeleton-v1/anatomy_skeleton_v1.blend',
 'production_rig_anchor_count':17,
 'source_bone_count':194,
 'overlay_is_exact_export_of_render_meshes':False,
 'visual_is_only_17_driver_pose_following_proxy':True,
 'physically_simulated':False,
 'personal_data':False,
 'bones':bone_data,'muscles':muscle_data,
 'cartilage':cartilage_data,'fat':fat_data}
raw=(json.dumps(out,ensure_ascii=False,separators=(',',':'))+'\n').encode('utf-8')
(ROOT/'anatomy_runtime_proxy_v1.json').write_bytes(raw)
(ROOT/'anatomy_runtime_proxy_v1.json.gz').write_bytes(gzip.compress(raw,compresslevel=9))
(ROOT/'anatomy_runtime_proxy_v1.sha256.txt').write_text(hashlib.sha256(raw).hexdigest()+'\n')
print('ANATOMY_EXPORT_VALIDATED',json.dumps({'bones':len(bone_data),
 'muscles':len(muscle_data),'cartilage':len(cartilage_data),
 'fat':len(fat_data),'bytes':len(raw),
 'sha256':hashlib.sha256(raw).hexdigest()}))
