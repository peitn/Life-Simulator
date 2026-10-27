#!/usr/bin/env python3
"""C14 Blender true existing-phalange bone articulation demo.

28 real bones (14 each hand) in original 194-bone anatomical Armature; 28
new skinned/articulated low-poly finger bone visual bodies + 10 existing
fingernails, independent proximal/distal keyframed animation showcase.

This Blender rig action is an authoring/demo proof of REAL independent
phalange bones, not an assertion of active Godot joint physics. The Godot
production rig still uses 17 bones and 20 visual joint-region morphs.
"""
import bpy, math, json, hashlib, datetime
from mathutils import Vector, Matrix
from pathlib import Path

ROOT=Path('/app/data/library/model/lifesim-anatomy-skeleton-v1')
MODEL=ROOT/'anatomy_skeleton_v1.blend'
bpy.ops.wm.open_mainfile(filepath=str(MODEL))
rig=bpy.data.objects['Anatomy_Rig_V1']
assert len(rig.data.bones)==194
assert len([b for b in rig.data.bones if b.name.startswith('finger_')])==28
assert 'Anatomy_C14_FingerJoints' not in bpy.data.collections, 'C14 already exists'
assert 'Anatomy_C14_IndependentFingerJoints' not in bpy.data.actions
coll=bpy.data.collections.new('Anatomy_C14_FingerJoints')
bpy.context.scene.collection.children.link(coll)

mat=bpy.data.materials.new('C14_Phalange_BoneIvory')
mat.use_nodes=True
mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.79,.76,.62,1)
mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.67

def segment_obj(bone):
    head=bone.head_local
    tail=bone.tail_local
    vec=(tail-head)
    axis=vec.normalized()
    ref=Vector((0,1,0)) if abs(axis.dot(Vector((0,1,0))))<.95 else Vector((1,0,0))
    tangent=axis.cross(ref).normalized()
    bitangent=axis.cross(tangent).normalized()
    length=vec.length
    radius=.0040 if '_1_' not in bone.name else .0052
    verts=[]
    faces=[]
    rings=5;radial=10
    for r in range(rings):
        t=r/(rings-1)
        center=head+vec*t
        taper=.7+.25*math.sin(math.pi*t)
        for j in range(radial):
            a=math.tau*j/radial
            vert=center+(tangent*math.cos(a)+bitangent*math.sin(a))*radius*taper
            verts.append(tuple(vert))
    for r in range(rings-1):
        for j in range(radial):
            a=r*radial+j;b=r*radial+(j+1)%radial
            c=a+radial;d=b+radial
            faces.extend([(a,b,c),(b,d,c)])
    mesh=bpy.data.meshes.new('C14_'+bone.name+'_Mesh')
    mesh.from_pydata(verts,[],faces);mesh.update()
    obj=bpy.data.objects.new('C14_Phalanx_'+bone.name,mesh)
    coll.objects.link(obj)
    obj.parent=rig
    bone_group=obj.vertex_groups.new(name=bone.name)
    bone_group.add(list(range(len(verts))),1,'REPLACE')
    modifier=obj.modifiers.new('C14_PhalangeArmature','ARMATURE')
    modifier.object=rig
    mesh.materials.append(mat)
    obj['driver']=bone.name
    obj['physical_ragdoll']=False
    return obj

parts=[]
for side in ['l','r']:
    for digit in range(1,6):
        names=sorted(
            [n for n in rig.data.bones.keys() if
             n.startswith('finger_'+str(digit)+'_') and n.endswith('_'+side)],
            key=lambda name:int(name.split('_')[2]))
        assert len(names)==(2 if digit==1 else 3)
        for n in names:
            parts.append(segment_obj(rig.data.bones[n]))
assert len(parts)==28

action=bpy.data.actions.new('Anatomy_C14_IndependentFingerJoints')
action.use_fake_user=True
rig.animation_data_create()
rig.animation_data.action=action
pose_bones={}
for b in rig.pose.bones:
    if b.name.startswith('finger_'):
        b.rotation_mode='XYZ'
        pose_bones[b.name]=b
assert len(pose_bones)==28

# Pose snapshots: rest -> proximal only -> distal only -> opposite thumb ->
# grasp-like all digits -> rest. Demonstrates independent underlying skeletal
# segments rather than morph keys. Peak degrees chosen visual illustrative.
frames=[1,16,32,48,64,80]
def set_angle(bone_name,angle):
    b=pose_bones[bone_name]
    b.rotation_euler=(math.radians(angle),0,0)
    b.keyframe_insert(data_path='rotation_euler',frame=frame,group='C14 joint '+bone_name)
for frame in frames:
    for bone_name in pose_bones:
        digit=int(bone_name.split('_')[1])
        segment=int(bone_name.split('_')[2])
        side=bone_name.split('_')[3]
        angle=0.0
        if frame==16 and side=='l' and digit==2 and segment==1:angle=44
        elif frame==32 and side=='l' and digit==2 and segment>=2:angle=37
        elif frame==48 and side=='r' and digit==1 and segment==2:angle=59
        elif frame==64:
            angle=42 if segment==1 else (39 if segment==2 else 25)
        set_angle(bone_name,angle)

# Numerical objective verification of the ACTUAL rig articulation.
scene=bpy.context.scene
scene.frame_set(1)
left_pip='finger_2_2_l'
left_base='finger_2_1_l'
reference_pip=rig.pose.bones[left_pip].tail.copy()
reference_base=rig.pose.bones[left_base].tail.copy()
scene.frame_set(16)
prox_pip=rig.pose.bones[left_pip].tail.copy()
scene.frame_set(32)
distal_pip=rig.pose.bones[left_pip].tail.copy()
scene.frame_set(1)
assert (prox_pip-reference_pip).length>.0001
assert (distal_pip-reference_pip).length>.0001
assert max(abs(x) for x in rig.pose.bones[left_pip].rotation_euler)<.000001

scene.frame_start=1
scene.frame_end=80
scene.frame_set(1)
coll.hide_render=True
scene['C14_has_actual_individual_blender_bones']=True
scene['C14_playable_character_has_real_finger_bones']=False
scene['C14_finger_rigidbody_solver_live']=False
scene['C14_pose_keyframes']=[1,16,32,48,64,80]
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(MODEL))

# A demonstrator glTF with source rig and 28 skinned finger bone meshes.
bpy.ops.object.select_all(action='DESELECT')
for x in parts:x.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active=rig
export=ROOT/'anatomy_independent_finger_joints_c14.glb'
bpy.ops.export_scene.gltf(filepath=str(export),export_format='GLB',
                          use_selection=True,export_extras=True,
                          export_animations=True)
assert export.stat().st_size>30000
stats=dict(original_armature_bones=194,independent_finger_phalange_bones=28,
           skinned_phalanx_render_meshes=28,frames=frames,
           left_index_proximal_tip_displacement_m=(prox_pip-reference_pip).length,
           left_index_distal_tip_displacement_m=(distal_pip-reference_pip).length,
           exported_glb_bytes=export.stat().st_size,
           in_game_skeletal_retarget=False,physical_joint_solver_active=False)
(ROOT/'anatomy_finger_joints_c14_manifest.json').write_text(json.dumps(stats,indent=2))
metadata_path=ROOT/'meta.json'
metadata=json.loads(metadata_path.read_text())
metadata['version']='0.3.4-C14-articulated-fingers'
metadata['updated']=datetime.datetime.now(datetime.timezone.utc).isoformat()
metadata['files']=[]
for f in sorted(ROOT.iterdir()):
    if f.is_file() and f.name!='meta.json':
        buf=f.read_bytes()
        metadata['files'].append({'path':f.name,'bytes':len(buf),
            'sha256':hashlib.sha256(buf).hexdigest()})
metadata_path.write_text(json.dumps(metadata,indent=2))
print('BLENDER_C14_ACTUAL_PHALANGE_BONE_ANIMATION_OK',json.dumps(stats))
