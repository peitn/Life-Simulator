#!/usr/bin/env python3
"""C13 genuine closed anatomical torso sculpt in persistent Blender scene.

Separate new surface (45x48 longitudinal/circumferential rings + two caps),
continuous flanks/back, independently real depressed navel geometry and a
paired smooth sculptural pectoral contour. Smooth spine/chest rig weights.
Based on actual Godot production body's measured front silhouette samples,
but source is a separate mesh, NOT the 830-vertex shirt. Do not conflate
this render mesh with a human medical model or a living FEM simulator.

Script is non-destructive, single-shot; 194-bone rig/physics remain unchanged.
"""
from pathlib import Path
import bpy, math, json, hashlib, datetime
from mathutils import Vector

ROOT=Path('/app/data/library/model/lifesim-anatomy-skeleton-v1')
MODEL=ROOT/'anatomy_skeleton_v1.blend'
bpy.ops.wm.open_mainfile(filepath=str(MODEL))
arm=bpy.data.objects['Anatomy_Rig_V1']
assert len(arm.data.bones)==194
assert sum(o.rigid_body is not None for o in bpy.data.objects)==17
assert sum(o.rigid_body_constraint is not None for o in bpy.data.objects)==16
assert 'spine' in arm.data.bones and 'chest' in arm.data.bones
assert 'Anatomy_TorsoC13' not in bpy.data.collections, 'already implemented'
collection=bpy.data.collections.new('Anatomy_TorsoC13')
bpy.context.scene.collection.children.link(collection)

# Measured from the true 830-vertex Blender-authored GLB used by Godot to
# initialize the old bare-shirt proxy. The editable .blend supports further
# independent sculpting while original low-poly GLB keeps its 10 morphs.
samples=[
 (.995,.06962),(1.05,.06965),(1.087,.06893),(1.15,.07383),
 (1.22,.08465),(1.30,.08787),(1.35,.08778),(1.39,.08521),
 (1.45,.07425),(1.50,.07362)]
def lerp(a,b,t):return a*(1-t)+b*t
def front(y):
    if y<=samples[0][0]:return samples[0][1]
    if y>=samples[-1][0]:return samples[-1][1]
    for i in range(len(samples)-1):
        a,b=samples[i],samples[i+1]
        if a[0]<=y<=b[0]:
            return lerp(a[1],b[1],(y-a[0])/(b[0]-a[0]))
    raise ValueError('invalid y')
def smooth(lo,hi,x):
    v=min(1,max(0,(x-lo)/(hi-lo)))
    return v*v*(3-2*v)
def halfwidth(y):
    return .146+.022*smooth(1.08,1.39,y)-.010*smooth(1.42,1.52,y)
def shapez(x,y,z):
    bulge=.009*math.exp(-((abs(x)-.105)/.052)**2 - ((y-1.350)/.065)**2)
    pit=.0085*math.exp(-(x/.018)**2 - ((y-1.088)/.019)**2)
    f=smooth(-.001,.045,z)
    return z+f*(bulge-pit)
def blended_spine(y):return smooth(1.175,1.355,y)
levels=45;sides=48
points=[]
uvs=[]
w_chest=[]
def vec(godot):return (godot[0],-godot[2],godot[1])
for i in range(levels):
    t=i/(levels-1)
    y=lerp(.990,1.520,t)
    rx=halfwidth(y); rz=front(y)
    for j in range(sides):
        a=math.tau*j/sides
        x=rx*math.sin(a);z=shapez(x,y,rz*math.cos(a))
        points.append(vec((x,y,z)))
        uvs.append((j/sides,t))
        w_chest.append(blended_spine(y))
points.append(vec((0,1.52,0)));uvs.append((.5,1.0));w_chest.append(1.0)
points.append(vec((0,.99,0)));uvs.append((.5,0));w_chest.append(0.0)
tris=[]
for i in range(levels-1):
    for j in range(sides):
        nxt=(j+1)%sides
        a=i*sides+j;b=i*sides+nxt;c=(i+1)*sides+j;d=(i+1)*sides+nxt
        tris.append((a,b,c))
        tris.append((b,d,c))
top=levels*sides;bottom=top+1
for j in range(sides):
    nxt=(j+1)%sides
    tris.append((bottom,j,nxt))
    last=(levels-1)*sides
    tris.append((top,last+nxt,last+j))
assert len(points)==2162 and len(tris)==4320
mesh=bpy.data.meshes.new('Skin_Torso_C13_2162')
mesh.from_pydata(points,[],tris);mesh.update(calc_edges=True)
assert len(mesh.vertices)==2162 and len(mesh.polygons)==4320
uv_layer=mesh.uv_layers.new(name='AnatomicalSkinUV')
for p in mesh.polygons:
    for li in p.loop_indices:
        uv_layer.data[li].uv=uvs[mesh.loops[li].vertex_index]
for face in mesh.polygons:face.use_smooth=True
obj=bpy.data.objects.new('Torso_Skin_C13',mesh)
collection.objects.link(obj)
group1=obj.vertex_groups.new(name='spine')
group2=obj.vertex_groups.new(name='chest')
for i,w in enumerate(w_chest):
    if w<1:group1.add([i],max(0,1-w),'REPLACE')
    if w>0:group2.add([i],min(1,w),'REPLACE')
obj.parent=arm
mod=obj.modifiers.new('Skinned_SpineChest','ARMATURE')
mod.object=arm
mod.use_deform_preserve_volume=True
obj['real_topology']="watertight, 3D sculpted 2162-vertex torso, actual inward umbilical skin depression"
obj['original_shirt_mesh_used']=False
obj['tissue_physics_active']=False
obj['medical_anatomy_verified']=False
obj['separate_from_gameplay_body_mesh']=True

material=bpy.data.materials.new('Skin_Torso_C13_SubtleDermis')
material.use_nodes=True
bs=material.node_tree.nodes.get('Principled BSDF')
bs.inputs['Base Color'].default_value=(.62,.39,.30,1.0)
bs.inputs['Roughness'].default_value=.72
nodes=material.node_tree.nodes; links=material.node_tree.links
noise=nodes.new('ShaderNodeTexNoise')
noise.inputs['Scale'].default_value=110
noise.inputs['Detail'].default_value=2
bump=nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value=.13
bump.inputs['Distance'].default_value=.00008
links.new(noise.outputs['Fac'],bump.inputs['Height'])
links.new(bump.outputs['Normal'],bs.inputs['Normal'])
mesh.materials.append(material)

# Require closed topology before saving; every edge must meet two faces.
import bmesh
bm=bmesh.new();bm.from_mesh(mesh)
bad=[e.index for e in bm.edges if not e.is_manifold]
bm.free()
assert not bad,('open/nonmanifold edges',len(bad))

# Save Blender source before export (and again afterward).
scene=bpy.context.scene
scene['C13_torso_skin_vertices']=len(mesh.vertices)
scene['C13_torso_navel_is_recessed_geometry']=True
scene['C13_torso_independent_medical_skin']=False
scene['C13_torso_live_Elmer_FEM']=False
collection.hide_render=True
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(MODEL))

# Independent export with original anatomy armature, not destructive replace.
bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True);arm.select_set(True);bpy.context.view_layer.objects.active=arm
glb=ROOT/'anatomy_torso_skin_c13.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',
                         use_selection=True,export_extras=True)
assert glb.stat().st_size>30000

# Render the true sculpt with a DEDICATED moderated two-area-light setup.
# The prior shared Presentation rig overexposed the torso to solid white.
# Lighting, camera and collection states are restored after Cycles review.
oldflags={c.name:c.hide_render for c in bpy.data.collections}
renderlights=bpy.data.collections.new('C13_Temporary_RenderLights')
scene.collection.children.link(renderlights)
for c in bpy.data.collections:
    c.hide_render=c.name not in ('Anatomy_TorsoC13','Anatomy_SkinDetails',
                                 'C13_Temporary_RenderLights')
collection.hide_render=False
for o in bpy.data.collections['Anatomy_SkinDetails'].objects:
    o.hide_render=o.name.startswith(('Fingernail_','Toenail_'))
oldcam=scene.camera
camera=scene.camera
old_location=camera.location.copy()
old_rotation=camera.rotation_euler.copy()
old_ortho_scale=camera.data.ortho_scale
camera.location=(.33,-2.6,1.24)
camera.rotation_euler=(Vector((0,-.02,1.26))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO'
camera.data.ortho_scale=.85
for name,position,power in [
    ('C13_ReviewKey',(1.2,-1.8,2.4),90),
    ('C13_ReviewFill',(-1.3,-1.8,1.4),40)]:
    light=bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA'))
    renderlights.objects.link(light)
    light.location=position
    light.rotation_euler=(Vector((0,0,1.27))-light.location).to_track_quat('-Z','Y').to_euler()
    light.data.energy=power
    light.data.shape='DISK'
    light.data.size=3.0
scene.render.engine='CYCLES'
scene.cycles.samples=24
scene.render.resolution_x=840
scene.render.resolution_y=1040
scene.render.resolution_percentage=85
scene.render.filepath=str(ROOT/'anatomy_torso_skin_c13_review.png')
bpy.ops.render.render(write_still=True)
assert (ROOT/'anatomy_torso_skin_c13_review.png').stat().st_size>18000

# Restore scene state and remove temporary lights after rendering.
scene.camera=oldcam
camera.location=old_location
camera.rotation_euler=old_rotation
camera.data.ortho_scale=old_ortho_scale
for o in bpy.data.collections['Anatomy_SkinDetails'].objects:
    if o.name.startswith(('Fingernail_','Toenail_')):o.hide_render=False
for c in bpy.data.collections:c.hide_render=oldflags.get(c.name,c.hide_render)
bpy.data.collections.remove(renderlights)
collection.hide_render=True
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(MODEL))
stats=dict(vertices=2162,triangles=4320,
   non_manifold_edges=0,rig_bones=194,
   absolute_source_vertex_count=830,
   bare_shirt_triangles_reused=0,
   skin_blendshapes_on_Blendermodel=0,
   original_character_Godot_skin_morphs=10,
   genuine_navel_cavity=True,
   physical_FEM_coupled=False,
   glb_bytes=glb.stat().st_size)
(ROOT/'anatomy_torso_skin_c13_manifest.json').write_text(json.dumps(stats,indent=2))
meta_path=ROOT/'meta.json'
meta=json.loads(meta_path.read_text(encoding='utf-8'))
meta['version']='0.3.3-C13-sculpted-closed-torso'
meta['updated']=datetime.datetime.now(datetime.timezone.utc).isoformat()
meta['files']=[]
for f in sorted(ROOT.iterdir()):
    if f.is_file() and f.name!='meta.json':
        content=f.read_bytes()
        meta['files'].append({'path':f.name,
                             'bytes':len(content),
                             'sha256':hashlib.sha256(content).hexdigest()})
meta_path.write_text(json.dumps(meta,indent=2),encoding='utf-8')
print('BLENDER_C13_TRUE_CLOSED_TORSO_PASS',json.dumps(stats))