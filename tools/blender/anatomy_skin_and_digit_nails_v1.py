#!/usr/bin/env python3
"""Non-destructive Blender anatomy C12: paired chest detail, navel, 20 nails.

Adds real sculptable closed/solid mesh surfaces to *separate* collection of
editable anatomy_skeleton_v1.blend. Existing 194-bone rig, muscles, cartilage,
fat, ligaments, physics and C11 FEM remain unchanged. Anatomy only: no
active Elmer physical solution on these meshes, no gender classification.
Godot runtime uses separately validated 10-body-morph torso GLB-proxy data.
"""
from pathlib import Path
import bpy,math,json,os,hashlib,datetime
from mathutils import Vector

ROOT=Path('/app/data/library/model/lifesim-anatomy-skeleton-v1')
SCENE=ROOT/'anatomy_skeleton_v1.blend'
bpy.ops.wm.open_mainfile(filepath=str(SCENE))
rig=bpy.data.objects['Anatomy_Rig_V1']
assert len(rig.data.bones)==194
assert sum(o.rigid_body is not None for o in bpy.data.objects)==17
assert sum(o.rigid_body_constraint is not None for o in bpy.data.objects)==16
NAME='Anatomy_SkinDetails'
assert NAME not in bpy.data.collections, 'non-destructive source script is single-use'
coll=bpy.data.collections.new(NAME)
bpy.context.scene.collection.children.link(coll)

def mat(name,col,rough):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes=True
    m.diffuse_color=(*col,1)
    bs=m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(*col,1)
    bs.inputs['Roughness'].default_value=rough
    return m

skin=mat('Anatomy_SkinDetail_Base',(.67,.43,.32),.63)
areola=mat('Anatomy_SkinDetail_Areola',(.46,.245,.20),.71)
papilla=mat('Anatomy_SkinDetail_Nipple',(.40,.19,.18),.55)
umb_rim=mat('Anatomy_SkinDetail_UmbilicusRim',(.59,.37,.30),.71)
umb_shadow=mat('Anatomy_SkinDetail_UmbilicusInner',(.23,.105,.09),.84)
nails=mat('Anatomy_SkinDetail_Nail',(.83,.65,.59),.34)

def mesh(name,points,faces,material,bone):
    assert bone in rig.data.bones
    me=bpy.data.meshes.new(name+'_mesh')
    me.from_pydata([tuple(q) for q in points],[],faces)
    me.update()
    ob=bpy.data.objects.new(name,me)
    coll.objects.link(ob)
    me.materials.append(material)
    for p in me.polygons:p.use_smooth=True
    group=ob.vertex_groups.new(name=bone)
    group.add(list(range(len(points))),1.0,'REPLACE')
    ob.parent=rig
    deform=ob.modifiers.new('Live_AnatomyBone','ARMATURE')
    deform.object=rig
    deform.use_deform_preserve_volume=True
    ob['skin_detail_reference_v1']=True
    ob['driver_bone']=bone
    ob['live_gameplay_physics']=False
    ob['medical_anatomy_validated']=False
    return ob

def disc(name,x,z,y,sx,sz,bump,material,bone,rings=3,segs=20):
    # Anatomical frontal surface is the Blender negative-Y plane.
    verts=[(x,y-bump,z)]
    for j in range(1,rings+1):
        t=j/rings
        y_offset=bump*math.exp(-5*t*t)
        for i in range(segs):
            a=math.tau*i/segs
            u=math.cos(a);v=math.sin(a)
            verts.append((x+sx*t*u,y-y_offset,z+sz*t*v))
    faces=[]
    for i in range(segs):
        faces.append((0,1+i,1+(i+1)%segs))
    for k in range(1,rings):
        a=1+(k-1)*segs
        b=1+k*segs
        for i in range(segs):
            q=(i+1)%segs
            faces.append((a+i,b+i,b+q,a+q))
    ob=mesh(name,verts,faces,material,bone)
    ob['front_surface_is_a_procedural_overlay']=True
    ob['original_body_skin_mesh_cut']=False
    return ob

torso=[]
for side,sgn in [('l',1),('r',-1)]:
    torso.append(disc('Areola_'+side,sgn*.103,1.351,-.070,.019,.013,.0014,areola,'chest'))
    torso.append(disc('Nipple_'+side,sgn*.103,1.351,-.074,.0062,.0054,.0055,papilla,'chest'))
torso.append(disc('Umbilicus_Rim',0,1.088,-.071,.0108,.014,.0018,umb_rim,'spine'))
torso.append(disc('Umbilicus_Inner',0,1.088,-.073,.0042,.007,.0013,umb_shadow,'spine'))

# True individually authored nail plates on the distal finger and toe bones,
# not generic cylinders or an unsupported claim of full physiologic nails.
def nailplate(name,center,across,longitudinal,face,half_width,length,material,bone):
    across=across.normalized();longitudinal=longitudinal.normalized()
    face=face.normalized()
    # 3x5 fully two-dimensional polygon grid, slight convexity at center.
    verts=[]
    faces=[]
    rows=5;cols=5
    for j in range(rows):
        v=(j/(rows-1)-.5)*2.
        taper=math.sqrt(max(.2,1-.28*v*v))
        for i in range(cols):
            u=(i/(cols-1)-.5)*2.
            verts.append(center+across*half_width*u*taper+
                longitudinal*length*v*.5+face*(.0008*(1-u*u)*(1-v*v)))
    for j in range(rows-1):
        for i in range(cols-1):
            a=j*cols+i;b=a+cols
            faces.append((a,a+1,b+1,b))
    ob=mesh(name,verts,faces,material,bone)
    ob['nail_anatomy_not_a_collision_mesh']=True
    return ob

digit=[]
for s in ['l','r']:
    for finger in range(1,6):
        base='finger_'+str(finger)+'_'
        b_candidates=[rig.data.bones[name] for name in rig.data.bones.keys()
                      if name.startswith(base) and name.endswith('_'+s)]
        bone=max(b_candidates,key=lambda b:int(b.name.split('_')[2]))
        axis=(bone.tail_local-bone.head_local).normalized()
        center=bone.tail_local-axis*.006
        digit.append(nailplate('Fingernail_%s_%d'%(s,finger),center,
            Vector((1,0,0)),axis,Vector((0,-1,0)),
            .004 if finger>1 else .005,.010 if finger>1 else .011,
            nails,bone.name))
    for toe in range(1,6):
        base='toe_'+str(toe)+'_'
        c=[rig.data.bones[name] for name in rig.data.bones.keys()
            if name.startswith(base) and name.endswith('_'+s)]
        bone=max(c,key=lambda b:int(b.name.split('_')[2]))
        axis=(bone.tail_local-bone.head_local).normalized()
        center=bone.tail_local-axis*.006+Vector((0,0,.004))
        digit.append(nailplate('Toenail_%s_%d'%(s,toe),center,
            Vector((1,0,0)),axis,Vector((0,0,1)),
            .004 if toe>1 else .007,.011 if toe>1 else .013,nails,bone.name))
assert len(torso)==6 and len(digit)==20
assert all(len(o.data.vertices)>=20 and o.get('driver_bone') in rig.data.bones for o in torso+digit)
assert len(coll.objects)==26

bpy.context.scene['torso_detail_revision']='C12 v1 separate 2 areolae+2 papillae+umbilical ring/inner and 20 anatomical nail plates'
bpy.context.scene['torso_umbilicus_cut_into_skin']=False
bpy.context.scene['clinical_accuracy']=False
bpy.context.scene['torso_active_gameplay_fem']=False

# Save original anatomy main file with all references intact.
coll.hide_render=True
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(SCENE))

# Export dedicated extra geometry as a separate GLB, not gameplay's main rig.
coll.hide_render=False
bpy.ops.object.select_all(action='DESELECT')
for item in torso+digit:item.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active=rig
out=ROOT/'anatomy_skin_and_nails_v1.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_extras=True)
assert out.stat().st_size>10000
coll.hide_render=True
bpy.ops.wm.save_as_mainfile(filepath=str(SCENE))
stats=dict(rig_bones=len(rig.data.bones),chest_geometry=len(torso),
    ten_fingernails=len([ob for ob in digit if ob.name.startswith('Fingernail')]),
    ten_toenails=len([ob for ob in digit if ob.name.startswith('Toenail')]),
    armature_mapped_meshes=len(coll.objects),export_glb_bytes=out.stat().st_size,
    full_body_physics_enabled=False)
(ROOT/'anatomy_skin_details_v1.json').write_text(json.dumps(stats,indent=2))
meta_path=ROOT/'meta.json'
meta=json.loads(meta_path.read_text())
meta['version']='0.3.2-body-details'
meta['updated']=datetime.datetime.now(datetime.timezone.utc).isoformat()
meta['files']=[]
for f in sorted(ROOT.iterdir()):
    if f.is_file() and f.name!='meta.json':
        raw=f.read_bytes()
        meta['files'].append({'path':f.name,'bytes':len(raw),
            'sha256':hashlib.sha256(raw).hexdigest()})
meta_path.write_text(json.dumps(meta,ensure_ascii=False,indent=2))
print('BLENDER_BODY_DETAILS_C12_SUCCESS',json.dumps(stats))
