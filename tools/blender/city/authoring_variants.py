"""Original modular openings and periodic PBR surfaces. Blender 4.0+.
Godot coordinates: X width, Y up, Z depth; convert to Blender (X,-Z,Y).
All original city files remain untouched. Output is under variants/materials_v2.
"""
import bpy, bmesh, math, json, os, hashlib
import numpy as np
from pathlib import Path

SOURCE=Path(os.environ.get('CITY_SOURCE_ROOT') or Path(__file__).resolve().parents[3])
ROOT=Path(os.environ.get('CITY_OUTPUT_ROOT',SOURCE))
MODELS=ROOT/'assets/city/variants'; TEX=ROOT/'assets/city/materials_v2'; DOC=ROOT/'docs/city'
for p in [MODELS,TEX,DOC]:p.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
N=256
u,v=np.meshgrid(np.linspace(0,1,N),np.linspace(0,1,N))
tau=2*math.pi
grain=.55*np.sin(tau*(7*u+3*v))+.28*np.sin(tau*(17*u-11*v))+.17*np.cos(tau*(23*u+19*v))
PRESETS={
 'plaster_white':('Bílá omítka','plaster',(.79,.78,.72)),
 'plaster_sand':('Písková omítka','plaster',(.64,.52,.35)),
 'plaster_sage':('Šalvějová omítka','plaster',(.42,.55,.45)),
 'brick_white':('Bílá cihla','brick',(.72,.74,.70)),
 'wood_oak':('Světlý dub','wood',(.52,.31,.12)),
 'wood_dark':('Tmavé dřevo','wood',(.18,.075,.028)),
 'tile_white':('Bílá dlažba','tile',(.78,.79,.74)),
 'tile_terracotta':('Terakotová dlažba','tile',(.51,.20,.085)),
 'stone_grey':('Šedý kámen','stone',(.37,.40,.42)),
 'concrete_dark':('Tmavý beton','concrete',(.20,.22,.23)),
 'wallpaper_stripe':('Pruhovaná tapeta','stripe',(.67,.63,.49)),
 'parquet_oak':('Dubové parkety','parquet',(.48,.28,.10))
}
materials={};surface_manifest={}

def png(name,rgba,noncolor=False):
    rgba=np.asarray(rgba,dtype=np.float32).copy();rgba[-1,:]=rgba[0,:];rgba[:,-1]=rgba[:,0]
    im=bpy.data.images.new(name,width=N,height=N,alpha=True)
    if noncolor:im.colorspace_settings.name='Non-Color'
    im.pixels.foreach_set(rgba.ravel());im.filepath_raw=str(TEX/(name+'.png'));im.file_format='PNG';im.save();im.pack();im.use_fake_user=True
    return im

def make_material(name,images):
    mat=bpy.data.materials.new(name);mat.use_nodes=True;mat.use_fake_user=True
    bs=mat.node_tree.nodes.get('Principled BSDF')
    for key,socket in [('albedo','Base Color'),('roughness','Roughness')]:
        tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=images[key];tex.extension='REPEAT'
        mat.node_tree.links.new(tex.outputs['Color'],bs.inputs[socket])
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=images['normal'];tex.extension='REPEAT'
    normal=mat.node_tree.nodes.new('ShaderNodeNormalMap');mat.node_tree.links.new(tex.outputs['Color'],normal.inputs['Color']);mat.node_tree.links.new(normal.outputs['Normal'],bs.inputs['Normal'])
    return mat

for key,(label,kind,color) in PRESETS.items():
    h=.5+.015*grain;shade=1+.035*grain;rough=.8+.025*grain
    if kind in ['brick','tile']:
        rows=4; x=(u*4+(np.floor(v*rows)%2)*(.5 if kind=='brick' else 0))%1;y=(v*rows)%1
        joint=(np.minimum(x,1-x)<(.035 if kind=='brick' else .018))|(np.minimum(y,1-y)<(.045 if kind=='brick' else .018))
        h=np.where(joint,.12,.6+.015*grain);shade=np.where(joint,.58,1+.04*grain);rough=(.48 if kind=='tile' else .82)+.02*grain
    elif kind in ['wood','parquet']:
        gu=np.sin(tau*(16*u+.035*np.sin(tau*3*v)))
        if kind=='parquet':
            gv=np.sin(tau*(16*v+.035*np.sin(tau*3*u)));gu=np.where((np.floor(u*4)+np.floor(v*4))%2==0,gu,gv)
            joint=(np.minimum((u*4)%1,1-(u*4)%1)<.015)|(np.minimum((v*4)%1,1-(v*4)%1)<.015)
        else:joint=np.minimum((u*4)%1,1-(u*4)%1)<.015
        h=np.where(joint,.2,.55+.02*gu);shade=np.where(joint,.55,1+.12*gu+.035*grain);rough=.65+.03*grain
    elif kind=='stripe':shade=1+.12*np.sin(tau*4*u)+.01*grain;h=.5+.003*grain;rough=.73+.02*grain
    elif kind=='stone':h=.5+.045*grain;shade=1+.12*grain;rough=.9+.02*grain
    elif kind=='concrete':h=.5+.027*grain;shade=1+.08*grain;rough=.87+.02*grain
    rgba=np.ones((N,N,4));rgba[:,:,:3]=np.clip(np.array(color)*shade[:,:,None],0,1)
    images={'albedo':png(key+'_albedo',rgba)}
    dx=(np.roll(h,-1,axis=1)-np.roll(h,1,axis=1))*.8;dy=(np.roll(h,-1,axis=0)-np.roll(h,1,axis=0))*.8
    normals=np.stack([-dx,-dy,np.ones_like(dx)],axis=-1);normals/=np.linalg.norm(normals,axis=-1,keepdims=True)
    rgba[:,:,:3]=normals*.5+.5;images['normal']=png(key+'_normal',rgba,True)
    rgba[:,:,:3]=np.clip(rough,0,1)[:,:,None];images['roughness']=png(key+'_roughness',rgba,True)
    materials[key]=make_material('City_'+key,images)
    surface_manifest[key]={'label':label,'tile_m':1,'size':[N,N],'maps':{m:'assets/city/materials_v2/'+key+'_'+m+'.png' for m in images},'normal':'OpenGL +Y','original':True}

# Include every older mapped material in the editable native material collection.
for key in ['plaster','brick','concrete','wood','tile','roof']:
    images={}
    for part in ['albedo','normal','roughness']:
        im=bpy.data.images.load(str(SOURCE/('assets/city/materials/'+key+'_'+part+'.png')),check_existing=True)
        if part!='albedo':im.colorspace_settings.name='Non-Color'
        im.pack();im.use_fake_user=True;images[part]=im
    materials[key]=make_material('City_'+key,images)
metal=bpy.data.materials.new('City_metal');metal.use_nodes=True;metal.use_fake_user=True
bs=metal.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.15,.26,.32,1);bs.inputs['Metallic'].default_value=.8;bs.inputs['Roughness'].default_value=.32
materials['metal']=metal
glass=bpy.data.materials.new('City_glass');glass.use_nodes=True;glass.use_fake_user=True;glass.diffuse_color=(.65,.82,.9,.28)
bs=glass.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=glass.diffuse_color;bs.inputs['Alpha'].default_value=.28;bs.inputs['Roughness'].default_value=.1
glass.blend_method='BLEND';materials['glass']=glass

def convert(p):return (p[0],-p[2],p[1])
current=[];colliders=[]
def prism(name,poly,depth,mat,collision=False,glass_=False):
    n=len(poly);points=[(x,y,z) for z in [-depth/2,depth/2] for x,y in poly]
    verts=[convert(p) for p in points]
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    assert all(e.is_manifold for e in bm.edges) and bm.calc_volume(signed=True)>0
    bm.to_mesh(mesh);bm.free()
    uv=mesh.uv_layers.new(name='MeterUV')
    for face in mesh.polygons:
        axis=max(range(3),key=lambda i:abs(face.normal[i]));axes=[i for i in range(3) if i!=axis]
        for li in face.loop_indices:
            co=mesh.vertices[mesh.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]],co[axes[1]])
    obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj);mesh.materials.append(materials[mat]);current.append(obj)
    if collision:colliders.append({'name':name,'points':points,'glass':glass_})
    return obj
def box(name,lo,hi,mat,collision=False):
    ob=prism(name,[(lo[0],lo[1]),(hi[0],lo[1]),(hi[0],hi[1]),(lo[0],hi[1])],hi[2]-lo[2],mat,collision,mat=='glass')
    shift=(lo[2]+hi[2])/2
    if shift:
        for vert in ob.data.vertices:vert.co.y-=shift
        if collision:
            colliders[-1]['points']=[[p[0],p[1],p[2]+shift] for p in colliders[-1]['points']]
    return ob
def line(name,a,b,width,depth,mat):
    dx=b[0]-a[0];dy=b[1]-a[1];length=math.hypot(dx,dy);nx=-dy/length*width/2;ny=dx/length*width/2
    return prism(name,[(a[0]+nx,a[1]+ny),(b[0]+nx,b[1]+ny),(b[0]-nx,b[1]-ny),(a[0]-nx,a[1]-ny)],depth,mat)
report={};collections=[]
def finish(name,category,details):
    bpy.ops.object.select_all(action='DESELECT');triangles=0
    for ob in current:ob.select_set(True);ob.data.calc_loop_triangles();triangles+=len(ob.data.loop_triangles)
    assert triangles<3000
    path=MODELS/(name+'.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_tangents=True,export_draco_mesh_compression_enable=False)
    coll=bpy.data.collections.new(name);scene.collection.children.link(coll)
    for ob in current:
        for old in list(ob.users_collection):old.objects.unlink(ob)
        coll.objects.link(ob)
    collections.append(coll)
    report[name]={'category':category,'triangles':triangles,'glb':'assets/city/variants/'+name+'.glb','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'colliders':colliders.copy(),**details}
    current.clear();colliders.clear()

for name,left,right,sill,top,double in [('window_wide',.2,1.8,1.0,2.1,False),('window_double',.4,1.6,.8,2.1,True)]:
    for part,lo,hi in [('Left',(0,0,-.1),(left,2.8,.1)),('Right',(right,0,-.1),(2,2.8,.1)),('SillWall',(left,0,-.1),(right,sill,.1)),('Header',(left,top,-.1),(right,2.8,.1))]:box(name+'_'+part,lo,hi,'plaster_white',True)
    for part,lo,hi in [('FrameL',(left-.03,sill-.03,-.13),(left+.03,top+.03,.13)),('FrameR',(right-.03,sill-.03,-.13),(right+.03,top+.03,.13)),('FrameB',(left+.03,sill-.03,-.13),(right-.03,sill+.03,.13)),('FrameT',(left+.03,top-.03,-.13),(right-.03,top+.03,.13))]:box(name+'_'+part,lo,hi,'wood_oak')
    if double:
        box(name+'_Mullion',(.97,sill,-.12),(1.03,top,.12),'wood_oak',True)
        for side,x1,x2 in [('L',left,.97),('R',1.03,right)]:box(name+'_Glass'+side,(x1,sill,-.0075),(x2,top,.0075),'glass',True)
    else:box(name+'_Glass',(left,sill,-.0075),(right,top,.0075),'glass',True)
    finish(name,'window',{'wall_size':[2,2.8,.2],'opening':[left,sill,right,top],'closed_glass':True,'pivot':[0,0,0]})

box('ArchLeft',(0,0,-.1),(.5,2.8,.1),'plaster_sand',True);box('ArchRight',(1.5,0,-.1),(2,2.8,.1),'plaster_sand',True)
box('ArchBottom',(.5,0,-.1),(1.5,.8,.1),'plaster_sand',True)
arc=[(.5+i/16,1.8+math.sqrt(max(0,.25-(.5+i/16-1)**2))) for i in range(17)]
for i in range(16):
    a,b=arc[i],arc[i+1]
    prism('ArchTop%02d'%i,[a,b,(b[0],2.8),(a[0],2.8)],.2,'plaster_sand',True)
    line('ArchFrame%02d'%i,a,b,.05,.26,'wood_dark')
line('ArchFrameL',(.5,.8),(.5,1.8),.05,.26,'wood_dark');line('ArchFrameR',(1.5,.8),(1.5,1.8),.05,.26,'wood_dark');line('ArchFrameB',(.5,.8),(1.5,.8),.05,.26,'wood_dark')
prism('ArchGlass',[(.5,.8),(1.5,.8)]+list(reversed(arc)),.015,'glass',True,True)
finish('window_arch','window',{'wall_size':[2,2.8,.2],'opening':[.5,.8,1.5,2.3],'closed_glass':True,'pivot':[0,0,0],'arc_segments':16})

for kind in ['door_panelled','door_glazed','door_metal']:
    material='metal' if kind=='door_metal' else 'wood_dark' if kind=='door_panelled' else 'wood_oak'
    if kind=='door_glazed':
        for part,lo,hi in [('L',(0,0,-.0225),(.12,2.06,.0225)),('R',(.84,0,-.0225),(.96,2.06,.0225)),('B',(.12,0,-.0225),(.84,.78,.0225)),('T',(.12,1.92,-.0225),(.84,2.06,.0225))]:box(kind+part,lo,hi,material)
        box('DoorGlass',(.12,.78,-.0075),(.84,1.92,.0075),'glass')
    else:
        box(kind+'_Leaf',(0,0,-.0225),(.96,2.06,.0225),material)
        if kind=='door_panelled':
            for z1,z2 in [(-.032,-.0225),(.0225,.032)]:
                for y1,y2 in [(.15,.89),(1.14,1.92)]:box('RaisedPanel',(.09,y1,z1),(.87,y2,z2),'wood_oak')
        else:
            for y in [.3,.6,1.5,1.8]:box('MetalRib',(.08,y,-.029),(.88,y+.025,-.0225),'metal')
    for z1,z2 in [(-.075,-.0225),(.0225,.075)]:box('Handle',(.78,.98,z1),(.90,1.02,z2),'metal')
    finish(kind,'door_leaf',{'leaf_size':[.96,2.06,.045],'pivot':'hinge bottom','compatible_scene':'m1_door.gd','closed_collision':'single full leaf box; glass remains solid'})

for i,coll in enumerate(collections):coll.hide_viewport=i>0;coll.hide_render=i>0
bpy.ops.wm.save_as_mainfile(filepath=str(MODELS/'authoring_variants.blend'),compress=True)
(DOC/'variants_manifest.json').write_text(json.dumps({'version':'1.0','license':'Original Life Simulator assets; all rights reserved','units':'meters','models':report,'surfaces':surface_manifest,'mapped_materials_native':18,'total_materials_native':20,'original_files_untouched':True},indent=2))
(ROOT/'assets/city/surfaces_v2.json').write_text(json.dumps(surface_manifest,indent=2))
print('AUTHORING_VARIANTS_READY',json.dumps({k:v['triangles'] for k,v in report.items()}),'new_surfaces',len(surface_manifest))

