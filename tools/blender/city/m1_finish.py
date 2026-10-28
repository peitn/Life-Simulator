"""Original M1 finishing kit. Run with Blender --background --python this.py.
Meters, Blender Z-up; glTF converts to Godot Y-up. Deterministic tile maps.
"""
import bpy, bmesh, math, json, os, hashlib
import numpy as np
from mathutils import Vector
from pathlib import Path

ROOT = Path(os.environ.get('LIFESIM_M1_ROOT', Path(__file__).resolve().parents[3]))
ASSETS = ROOT / 'assets/city'
TEX = ASSETS / 'materials'
DOC = ROOT / 'docs/city'
for p in [ASSETS, TEX, DOC]: p.mkdir(parents=True, exist_ok=True)
N = 128
u, v = np.meshgrid(np.linspace(0, 1, N), np.linspace(0, 1, N))
twopi = 2*math.pi
wave = .5*np.sin(twopi*(7*u+3*v)) + .3*np.sin(twopi*(13*u-9*v)) + .2*np.cos(twopi*(19*u+17*v))
PALETTES = {'plaster':(.70,.66,.57), 'brick':(.48,.22,.13), 'concrete':(.43,.45,.44),
            'wood':(.34,.17,.065), 'tile':(.50,.59,.56), 'roof':(.28,.12,.09)}

def image(name, rgba, noncolor=False):
    rgba=np.array(rgba,dtype=np.float32)
    rgba[-1,:]=rgba[0,:]; rgba[:,-1]=rgba[:,0]
    im=bpy.data.images.new(name,width=N,height=N,alpha=True)
    if noncolor: im.colorspace_settings.name='Non-Color'
    im.pixels.foreach_set(rgba.ravel())
    im.filepath_raw=str(TEX/(name+'.png')); im.file_format='PNG'; im.save(); im.pack()
    return im

materials={}
texture_report={}
for name, color in PALETTES.items():
    if name in ['brick','roof']:
        rows=4 if name=='brick' else 6
        row=np.floor(v*rows)
        stagger=(row%2)*.5
        x=(u*4+stagger)%1; y=(v*rows)%1
        mortar=(np.minimum(x,1-x)<.035)|(np.minimum(y,1-y)<.055)
        height=np.where(mortar,.15,.65+.035*wave)
        shade=np.where(mortar,.65,1+.12*wave)
    elif name=='tile':
        x=(u*4)%1; y=(v*4)%1
        mortar=(np.minimum(x,1-x)<.025)|(np.minimum(y,1-y)<.025)
        height=np.where(mortar,.1,.6+.01*wave)
        shade=np.where(mortar,.50,1+.025*wave)
    elif name=='wood':
        grain=np.sin(twopi*(12*u+.04*np.sin(twopi*3*v)))
        joins=np.minimum((u*4)%1,1-(u*4)%1)<.025
        height=np.where(joins,.15,.6+.025*grain+.015*wave)
        shade=np.where(joins,.55,1+.15*grain+.06*wave)
    else:
        height=.5+(.018 if name=='plaster' else .035)*wave
        shade=1+(.04 if name=='plaster' else .09)*wave
    rgba=np.ones((N,N,4)); rgba[:,:,:3]=np.clip(shade[:,:,None]*np.array(color),0,1)
    albedo=image(name+'_albedo',rgba)
    dx=(np.roll(height,-1,axis=1)-np.roll(height,1,axis=1))*.8
    dy=(np.roll(height,-1,axis=0)-np.roll(height,1,axis=0))*.8
    normals=np.stack([-dx,-dy,np.ones_like(dx)],axis=-1)
    normals/=np.linalg.norm(normals,axis=-1,keepdims=True)
    rgba[:,:,:3]=normals*.5+.5
    normal=image(name+'_normal',rgba,True)
    rough=np.clip((.45 if name=='tile' else .72)+.035*wave,0,1)
    rgba[:,:,:3]=rough[:,:,None]
    roughness=image(name+'_roughness',rgba,True)
    mat=bpy.data.materials.new('M1_'+name); mat.use_nodes=True
    bs=mat.node_tree.nodes.get('Principled BSDF')
    for im,socket in [(albedo,'Base Color'),(roughness,'Roughness')]:
        node=mat.node_tree.nodes.new('ShaderNodeTexImage'); node.image=im; node.extension='REPEAT'
        mat.node_tree.links.new(node.outputs['Color'],bs.inputs[socket])
    node=mat.node_tree.nodes.new('ShaderNodeTexImage'); node.image=normal; node.extension='REPEAT'
    nm=mat.node_tree.nodes.new('ShaderNodeNormalMap')
    mat.node_tree.links.new(node.outputs['Color'],nm.inputs['Color']); mat.node_tree.links.new(nm.outputs['Normal'],bs.inputs['Normal'])
    materials[name]=mat
    texture_report[name]={'maps':[f'{name}_{m}.png' for m in ['albedo','normal','roughness']], 'size':[N,N], 'tile_m':1, 'normal':'OpenGL +Y', 'original':True}

bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene; scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
def box(name,lo,hi,material):
    bpy.ops.mesh.primitive_cube_add(size=1,location=tuple((lo[i]+hi[i])/2 for i in range(3)))
    ob=bpy.context.object; ob.name=name; ob.dimensions=tuple(hi[i]-lo[i] for i in range(3))
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    # Flat outward normals and projected meter UV; no generated cube atlas.
    mesh=ob.data; uv=mesh.uv_layers.active or mesh.uv_layers.new(name='MeterUV')
    for face in mesh.polygons:
        axis=max(range(3),key=lambda i:abs(face.normal[i])); axes=[i for i in range(3) if i!=axis]
        for li in face.loop_indices:
            co=mesh.vertices[mesh.loops[li].vertex_index].co+ob.location
            uv.data[li].uv=(co[axes[0]],co[axes[1]])
    ob.data.materials.append(materials[material]); return ob

modules={
 'foundation_2m':[('Foundation',(0,0,-.5),(2,2,0),'concrete')],
 'roof_flat_2m':[('FlatRoof',(0,0,0),(2,2,.15),'roof')],
 'door_leaf_1m':[('Leaf',(0,-.0225,0),(.96,.0225,2.06),'wood'),
  ('PanelFront',(.08,-.029,.16),(.88,-.0225,1.88),'wood'),
  ('PanelBack',(.08,.0225,.16),(.88,.029,1.88),'wood'),
  ('HandleFront',(.78,-.075,.98),(.90,-.029,1.02),'concrete'),
  ('HandleBack',(.78,.029,.98),(.90,.075,1.02),'concrete')]
}
report={}
for name,parts in modules.items():
    obs=[box(*p) for p in parts]
    bpy.ops.object.select_all(action='DESELECT')
    for ob in obs: ob.select_set(True)
    triangles=0
    for ob in obs:
        ob.data.calc_loop_triangles(); triangles+=len(ob.data.loop_triangles)
        bm=bmesh.new(); bm.from_mesh(ob.data)
        assert all(e.is_manifold for e in bm.edges)
        assert bm.calc_volume(signed=True)>0
        bm.free()
    assert triangles<3000
    bpy.ops.export_scene.gltf(filepath=str(ASSETS/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_tangents=True)
    report[name]={'triangles':triangles,'parts':len(obs),'pivot':'hinge bottom' if name.startswith('door') else 'front left top' if name.startswith('foundation') else 'front left base','glb_sha256':hashlib.sha256((ASSETS/(name+'.glb')).read_bytes()).hexdigest()}
    for ob in obs: ob.hide_render=True; ob.hide_set(True)

# Editable source retains all modules at their local origin in named collections.
for name in modules:
    coll=bpy.data.collections.new(name); scene.collection.children.link(coll)
    for ob in list(scene.objects):
        if ob.name in [p[0] for p in modules[name]]:
            for old in list(ob.users_collection): old.objects.unlink(ob)
            coll.objects.link(ob); ob.hide_set(False); ob.hide_render=False
bpy.ops.wm.save_as_mainfile(filepath=str(ASSETS/'m1_finishing_kit.blend'),compress=True)
(DOC/'m1_finishing_manifest.json').write_text(json.dumps({'version':'1.0','license':'Original Life Simulator assets; all rights reserved','units':'meters','modules':report,'materials':texture_report},indent=2))
print('M1_GENERATED',json.dumps(report))
