#!/usr/bin/env python3
"""Render true Elmer 26.2 3D Hex8 muscle+fat thermal VTU field in Blender.

Inputs: persisted 'lifesim-anatomy-skeleton-v1/elmer_mfat_3d_field_v1.json'
contains exact Elmer mesh node coordinates, hexahedron connectivity and
the 208 ACTUAL ElmerSolver VTU temperature values from a 3D static solve.

Shows REAL solved 3D slab values, but NEVER 3D anatomical skin temperature:
the underlying FE geometry is only a 35x12x10 mm two-layer cuboid.
The viewer geometry is deliberately enlarged for inspection. This does not
change the production 17-bone live character, Blender rig, Bullet physics
or multiplayer authority.
"""
import bpy
import math
import json
import os
import hashlib
import datetime
from collections import defaultdict
from pathlib import Path
from mathutils import Vector

ROOT=Path('/app/data/library/model/lifesim-anatomy-skeleton-v1')
file=ROOT/'elmer_mfat_3d_field_v1.json'
blob=json.loads(file.read_text(encoding='utf-8'))
assert blob['schema']=='lifesim.fem.musclefat.3d.field.v1'
assert blob['case_id']=='lifesim_mfat_3d_heat_coarse_c11'
nodes=blob['nodes']  # [Elmer node ID, x_m, y_m, z_m]
elements=blob['hexes'] # [physical body 1 or 2, n1..n8]
temps=blob['temperature_K']
assert len(nodes)==len(temps)==208
assert len(elements)==108
assert abs(min(temps)-301.89125)<.001 and abs(max(temps)-310.15)<.001
node_map={int(n[0]):tuple(map(float,n[1:4])) for n in nodes}
thermal={int(n[0]):float(t) for n,t in zip(nodes,temps)}
assert len(node_map)==208

bpy.ops.wm.open_mainfile(filepath=str(ROOT/'anatomy_skeleton_v1.blend'))
scene=bpy.context.scene
rig=bpy.data.objects['Anatomy_Rig_V1']
assert len(rig.data.bones)==194
assert sum(o.rigid_body is not None for o in bpy.data.objects)==17
assert sum(o.rigid_body_constraint is not None for o in bpy.data.objects)==16
assert len([o for o in bpy.data.objects if o.name.startswith('Muscle_')])==60
assert len([o for o in bpy.data.objects if o.name.startswith('Adipose_')])==6
collection=bpy.data.collections.get('Anatomy_Elmer3D_Diagnostic')
if collection is None:
    collection=bpy.data.collections.new('Anatomy_Elmer3D_Diagnostic')
    scene.collection.children.link(collection)
assert len(collection.objects)==0, 'DO NOT overwrite existing diagnostics'

# Each hex shares faces with neighbor cells; retain only the boundary
# faces of its OWN volume body, including the material interface.
# Hex order: 4 bottom + 4 top corners around z.
hex_faces=[
    (0,3,7,4),  # x- face
    (1,5,6,2),  # x+ face
    (0,4,5,1),  # y- face
    (3,2,6,7),  # y+ face
    (0,1,2,3),  # z- face
    (4,7,6,5),  # z+ face
]
group_faces={1:defaultdict(list),2:defaultdict(list)}
for entry in elements:
    body=int(entry[0])
    assert body in group_faces
    hexa=[int(i) for i in entry[1:]]
    assert len(hexa)==8 and all(x in node_map for x in hexa)
    for face in hex_faces:
        ids=tuple(hexa[i] for i in face)
        group_faces[body][tuple(sorted(ids))].append(ids)

def colormap(t):
    """Color of computed kelvin value, not biomechanical damage/comfort."""
    u=max(0.,min(1.,(t-300.0)/(310.5-300.0)))
    if u<=.52:
        p=u/.52
        return (.08+.41*p,.24+.34*p,.73-.25*p,1.)
    p=(u-.52)/.48
    return (.49+.49*p,.58-.32*p,.48-.37*p,1.)

mat=bpy.data.materials.new('Anatomy_Elmer3D_ActualVTU_VertexKelvin')
mat.use_nodes=True
mat.node_tree.nodes.clear()
node_color=mat.node_tree.nodes.new('ShaderNodeVertexColor')
node_color.layer_name='heat_color'
em=mat.node_tree.nodes.new('ShaderNodeEmission')
em.inputs['Strength'].default_value=1.0
final=mat.node_tree.nodes.new('ShaderNodeOutputMaterial')
mat.node_tree.links.new(node_color.outputs['Color'],em.inputs['Color'])
mat.node_tree.links.new(em.outputs['Emission'],final.inputs['Surface'])

# Geometry scaled 38x for visibility; origin centered.
# Physical-space coordinates always remain in the JSON and metadata.
scale=38.0
center=Vector((.0175,.006,.005))
surfaces=[]
for body,name in [(1,'Muscle'),(2,'Fat')]:
    exterior=[v[0] for v in group_faces[body].values() if len(v)==1]
    used=sorted({n for face in exterior for n in face})
    local={nid:i for i,nid in enumerate(used)}
    verts=[(Vector(node_map[n])-center)*scale for n in used]
    faces=[tuple(local[n] for n in face) for face in exterior]
    mesh=bpy.data.meshes.new('Elmer3D_'+name+'_actualVTU_3DHexSurface')
    mesh.from_pydata(verts,[],faces)
    mesh.update()
    mesh.materials.append(mat)
    numeric=mesh.attributes.new('actual_elmer_kelvin',type='FLOAT',domain='POINT')
    for i,nid in enumerate(used):
        numeric.data[i].value=thermal[nid]
    painted=mesh.vertex_colors.new(name='heat_color')
    for polygon in mesh.polygons:
        for loop in polygon.loop_indices:
            local_index=mesh.loops[loop].vertex_index
            painted.data[loop].color=colormap(thermal[used[local_index]])
        polygon.use_smooth=True
    obj=bpy.data.objects.new('Elmer3D_'+name+'_Surface',mesh)
    collection.objects.link(obj)
    obj['source']='ACTUAL 3D ElmerSolver 26.2 VTU coarse mesh'
    obj['case']='lifesim_mfat_3d_heat_coarse_c11'
    obj['body_physical_id']=body
    obj['solved_3d_flat_slab_not_human_body']=True
    obj['anatomical_3d_mesh_fem']=False
    obj['display_scale_to_meters']=scale
    obj['source_temp_min_K']=min(thermal[n] for n in used)
    obj['source_temp_max_K']=max(thermal[n] for n in used)
    surfaces.append(obj)

# Annotation in camera-facing plane: label boxes named for clarity.
txt=bpy.data.materials.new('Anatomy_Elmer3D_Labels')
txt.use_nodes=True
txt.node_tree.nodes.clear()
out=txt.node_tree.nodes.new('ShaderNodeOutputMaterial')
em=txt.node_tree.nodes.new('ShaderNodeEmission')
em.inputs['Color'].default_value=(.95,.96,1,1)
txt.node_tree.links.new(em.outputs['Emission'],out.inputs['Surface'])

def label(name,body,position,size=.064):
    curve=bpy.data.curves.new(name+'_Curve','FONT')
    curve.body=body
    curve.size=size
    curve.materials.append(txt)
    ob=bpy.data.objects.new(name,curve)
    collection.objects.link(ob)
    ob.location=position
    ob.rotation_euler=(math.pi/2,0,0)
    return ob

# Camera at diagonal to expose thickness, y and z of the actual 3D mesh.
bpy.ops.object.camera_add(location=(2.7,-3.6,2.1))
cam=bpy.context.object
cam.name='Anatomy_Elmer3D_Camera'
for c in list(cam.users_collection):c.objects.unlink(cam)
collection.objects.link(cam)
cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.type='ORTHO'
cam.data.ortho_scale=2.55
label('Elmer3D_Title','3D Elmer field  |  muscle  +  fat',(-1.04,-.7,1.0),.085)
label('Elmer3D_Low','Skin: 28.74 C  /  301.891 K',(-1.04,-.7,-.98),.061)
label('Elmer3D_Scope','Flat reference slab only - NOT anatomically shaped human tissue',(-1.04,-.7,-1.12),.043)

old_flags={col.name:col.hide_render for col in bpy.data.collections}
old_cam=scene.camera
for col in bpy.data.collections:
    col.hide_render=col!=collection
collection.hide_render=False
scene.camera=cam
scene.render.engine='CYCLES'
scene.cycles.samples=18
scene.render.resolution_x=1140
scene.render.resolution_y=760
scene.render.resolution_percentage=84
image_name='anatomy_elmer_actual_3d_temperature_v1.png'
scene.render.filepath=str(ROOT/image_name)
bpy.ops.render.render(write_still=True)
assert (ROOT/image_name).stat().st_size>15000
scene.camera=old_cam
for col in bpy.data.collections:
    col.hide_render=old_flags.get(col.name,True)
collection.hide_render=True
scene['elmer_real_3d_heat_solved']=True
scene['elmer_real_3d_body_anatomy_solved']=False
scene['elmer_real_3d_physics_realtime']=False
scene['elmer3d_field_source']='lifesim_mfat_3d_heat_coarse_c11, true VTU, 208 points, 108 Hex8'
scene['elmer3d_field_display_size_scale']=scale
embedded=bpy.data.texts.get('Elmer3D_ActualVTU_Field_20261027.json')
if embedded is None:embedded=bpy.data.texts.new('Elmer3D_ActualVTU_Field_20261027.json')
embedded.clear()
embedded.write(json.dumps(blob,ensure_ascii=False))
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'anatomy_skeleton_v1.blend'))

# Optional portable, separate diagnostic-only GLB with actual solved vertex colors.
bpy.ops.object.select_all(action='DESELECT')
for o in surfaces:o.select_set(True)
bpy.context.view_layer.objects.active=surfaces[0]
bpy.ops.export_scene.gltf(filepath=str(ROOT/'anatomy_elmer_actual_3d_temperature_v1.glb'),
                           export_format='GLB',use_selection=True,export_extras=True)
assert (ROOT/'anatomy_elmer_actual_3d_temperature_v1.glb').stat().st_size>10000

meta=json.loads((ROOT/'meta.json').read_text())
meta['version']='0.3.0-real-3d-reference-FEM'
meta['description']='Life Simulator 194-bone Blender anatomy with stylized muscles/fat, true 3D ElmerSolver muscle+fat flat-block temperature VTU visualized on original 3D FE mesh (not an anatomical knee or realtime physiology).'
meta['updated']=datetime.datetime.now(datetime.timezone.utc).isoformat()
meta['files']=[]
for f in sorted(ROOT.iterdir()):
    if not f.is_file() or f.name=='meta.json':continue
    content=f.read_bytes()
    meta['files'].append({'path':f.name,'bytes':len(content),
                          'sha256':hashlib.sha256(content).hexdigest()})
(ROOT/'meta.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2))
stats={name:{"vertices":len(o.data.vertices),"surface_faces":len(o.data.polygons)}
       for name,o in zip(['muscle','fat'],surfaces)}
print("BLENDER_ELMER3D_VTU_REAL_SURFACE_OK",json.dumps({
  "original_rig_bones":len(rig.data.bones),"volume_cells":len(elements),
  "source_temperature_points":len(temps),"original_Bullet_bodies":17,
  "original_rigid_constraints":16,"min_K":min(temps),"max_K":max(temps),
  "render_bytes":(ROOT/image_name).stat().st_size,
  "separate_glb_bytes":(ROOT/'anatomy_elmer_actual_3d_temperature_v1.glb').stat().st_size,
  "surface_stats":stats}))
