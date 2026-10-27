#!/usr/bin/env python3
"""Life Simulator anatomy VISUAL PASS v0.2 (Blender 4.0).
Keeps source 194-bone skeleton, 17 Bullet proxies/16 joints and production
17-bone character untouched. Adds stylized adipose VOLUME meshes, vertebral
processes, curved rib render meshes, soft tissue shaders and anatomical views.
These are anatomical research / art prototypes, NOT medical segmentations.
"""
import bpy,math,os,json,hashlib,datetime
from mathutils import Vector
from pathlib import Path
ROOT=Path("/app/data/library/model/lifesim-anatomy-skeleton-v1")
bpy.ops.wm.open_mainfile(filepath=str(ROOT/"anatomy_skeleton_v1.blend"))
scene=bpy.context.scene
arm=bpy.data.objects["Anatomy_Rig_V1"]
assert len(arm.data.bones)==194
assert sum(o.rigid_body is not None for o in bpy.data.objects)==17
assert sum(o.rigid_body_constraint is not None for o in bpy.data.objects)==16

def group(name):
    key="Anatomy_"+name
    result=bpy.data.collections.get(key)
    assert result is not None,key
    return result

fat_collection=group("Adipose") if bpy.data.collections.get("Anatomy_Adipose") else bpy.data.collections.new("Anatomy_Adipose")
if fat_collection.name not in scene.collection.children:
    try:scene.collection.children.link(fat_collection)
    except RuntimeError:pass
fascia_collection=bpy.data.collections.get("Anatomy_Fascia")
if fascia_collection is None:
    fascia_collection=bpy.data.collections.new("Anatomy_Fascia")
    scene.collection.children.link(fascia_collection)

def material(name,col,rough=.55,alpha=1):
    mat=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes=True
    mat.diffuse_color=(*col,alpha)
    p=mat.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value=(*col,1)
    p.inputs["Roughness"].default_value=rough
    p.inputs["Alpha"].default_value=alpha
    if alpha<1:mat.blend_method="BLEND";mat.use_nodes=True
    return mat

# Sculptural material detail based on Noise texture; explicitly illustrative.
def noise_material(name,low,high,scale,rough=.65,alpha=1):
    mat=material(name,low,rough,alpha)
    nodes=mat.node_tree.nodes;links=mat.node_tree.links
    bs=nodes.get("Principled BSDF")
    tex=nodes.new("ShaderNodeTexNoise");tex.inputs["Scale"].default_value=scale
    tex.inputs["Detail"].default_value=3.0
    col=nodes.new("ShaderNodeValToRGB")
    col.color_ramp.elements[0].color=(*low,1)
    col.color_ramp.elements[1].color=(*high,1)
    links.new(tex.outputs["Fac"],col.inputs["Fac"])
    links.new(col.outputs["Color"],bs.inputs["Base Color"])
    bump=nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value=.18
    bump.inputs["Distance"].default_value=.0009
    links.new(tex.outputs["Fac"],bump.inputs["Height"])
    links.new(bump.outputs["Normal"],bs.inputs["Normal"])
    return mat

bone=noise_material("Anatomy_Visual_Cortical",(.78,.70,.54),(.96,.91,.79),80,.62)
muscle=noise_material("Anatomy_Visual_MuscleFiber",(.26,.035,.051),(.69,.13,.12),105,.51)
fat=noise_material("Anatomy_Visual_Adipose",(.82,.62,.29),(.97,.86,.51),47,.42,.55)
fascia=noise_material("Anatomy_Visual_Fascia",(.50,.68,.63),(.80,.87,.78),64,.49,.31)
for o in group("Bones").objects:
    if o.type=="MESH":
        if len(o.data.materials):o.data.materials[0]=bone
for o in group("Muscles").objects:
    if o.type!="MESH":continue
    if len(o.data.materials):o.data.materials[0]=muscle
    if not any(m.type=="SUBSURF" for m in o.modifiers):
        sm=o.modifiers.new("Smooth_fusiform_belly", "SUBSURF")
        sm.subdivision_type="CATMULL_CLARK";sm.levels=1;sm.render_levels=1
    for face in o.data.polygons:face.use_smooth=True
    o["render_style"]="stylized fusiform skeletal muscle with procedural fiber shading"
    o["medical_surface_accuracy"]=False

def add_mesh(name,verts,faces,coll,mat,bone_name=None):
    mesh=bpy.data.meshes.new(name+"_mesh")
    mesh.from_pydata([tuple(v) for v in verts],[],faces)
    mesh.update(calc_edges=True)
    ob=bpy.data.objects.new(name,mesh)
    coll.objects.link(ob)
    ob.data.materials.append(mat)
    for f in ob.data.polygons:f.use_smooth=True
    if bone_name:
        assert bone_name in arm.data.bones
        vg=ob.vertex_groups.new(name=bone_name)
        vg.add(list(range(len(verts))),1.0,"REPLACE")
        ob.parent=arm
        rig_mod=ob.modifiers.new("Attached_to_"+bone_name,"ARMATURE")
        rig_mod.object=arm
        rig_mod.use_deform_preserve_volume=True
        ob["anatomy_bone"]=bone_name
    return ob

def tube(name,control,radius,coll,mat,bone_name=None,ns=12):
    control=[Vector(x) for x in control]
    verts=[];faces=[]
    for index,p in enumerate(control):
        direction=(control[min(len(control)-1,index+1)]-control[max(0,index-1)]).normalized()
        if direction.length<.001:direction=Vector((0,1,0))
        ref=Vector((0,0,1)) if abs(direction.z)<.85 else Vector((0,1,0))
        a=direction.cross(ref).normalized();b=direction.cross(a).normalized()
        for j in range(ns):
            t=math.tau*j/ns
            rad=radius*(.9+.10*math.sin(math.pi*index/max(1,len(control)-1)))
            verts.append(p+rad*(a*math.cos(t)+b*math.sin(t)))
    faces.append(tuple(range(ns-1,-1,-1)))
    for i in range(len(control)-1):
        for j in range(ns):
            a=i*ns+j;bb=i*ns+(j+1)%ns
            faces.append((a,bb,bb+ns,a+ns))
    faces.append(tuple((len(control)-1)*ns+j for j in range(ns)))
    return add_mesh(name,verts,faces,coll,mat,bone_name)

# Instead of 24 straight noodle ribs, replace the SAME bone meshes with
# 3D swept, curved arc geometry; their original armature weights remain valid.
rib_count=0
for side,sgn in [("l",1),("r",-1)]:
    for k in range(1,13):
        name="Bone_rib_%02d_%s"%(k,side)
        old=bpy.data.objects[name]
        rigbone="rib_%02d_%s"%(k,side)
        src=arm.data.bones[rigbone]
        a=src.head_local.copy();b=src.tail_local.copy()
        mid=(a+b)/2
        # Natural thoracic curvature: posterior toward lateral, anterior to sternum.
        ctrl=[a,
              Vector((sgn*(abs(a.x)+.055),a.y+.040,a.z-.006)),
              Vector((sgn*(abs(b.x)+.035),b.y+.045,b.z-.018)),
              b]
        path=[]
        for t in range(15):
            u=t/14.0
            p=(1-u)**3*ctrl[0]+3*(1-u)**2*u*ctrl[1]+3*(1-u)*u*u*ctrl[2]+u*u*u*ctrl[3]
            path.append(p)
        obj=tube("Anatomy_VisualRib_tmp_"+str(rib_count),path,.0068,group("Bones"),bone,rigbone,10)
        # Preserve canonical mesh Object naming and old metadata but replace geometry.
        new_mesh=obj.data
        for mat in list(new_mesh.materials):
            pass
        old.data=new_mesh.copy()
        vg=old.vertex_groups.get(rigbone)
        if vg:old.vertex_groups.remove(vg)
        vg=old.vertex_groups.new(name=rigbone)
        vg.add(list(range(len(old.data.vertices))),1.0,"REPLACE")
        old["curved_reconstruction"]=True
        bpy.data.objects.remove(obj,do_unlink=True)
        rib_count+=1

# Posterior transverse & spinous processes for 24 vertebral bodies.
process_count=0
for typ,ids in [("lumbar",5),("thoracic",12),("cervical",7)]:
    for k in range(1,ids+1):
        ref="vertebra_%s_%02d"%(typ,k)
        b=arm.data.bones[ref]
        mid=(b.head_local+b.tail_local)*.5
        width={"lumbar":.036,"thoracic":.029,"cervical":.023}[typ]
        for sgn,side in [(1,"l"),(-1,"r")]:
            tube("Process_%s_%02d_%s"%(typ,k,side),
                 [mid,mid+Vector((sgn*width*.6,.005,.001)),
                  mid+Vector((sgn*width,.017,-.003))],
                 .005 if typ!="cervical" else .0035,group("Bones"),bone,ref,8)
            process_count+=1
        tube("Spinous_process_%s_%02d"%(typ,k),
             [mid,mid+Vector((0,.014,-.004)),
              mid+Vector((0,.037,-.013))],
             .0048 if typ=="lumbar" else .0034,group("Bones"),bone,ref,8)
        process_count+=1

# Fat is an actual hollow 3D VOLUME with inner/outer surfaces and ring walls.
# Its outer shell is intentionally translucent for separate atlas inspection.
# These are approximate parametric subcutaneous envelopes, NOT actual patient
# segmented adipose or mechanical/thermal Elmer meshes.
def adipose_shell(name,x,zmin,zmax,rx,ry,thickness,bone_name,style="region"):
    nv=18;nx=32
    verts=[];faces=[]
    def ring(j,interior):
        t=j/(nv-1);zz=zmin+(zmax-zmin)*t
        taper=0.92+0.11*math.sin(math.pi*t)
        for i in range(nx):
            a=math.tau*i/nx
            dax=rx*taper-(thickness if interior else 0.0)
            day=ry*taper-(thickness if interior else 0.0)
            verts.append((x+dax*math.cos(a),day*math.sin(a),zz))
    for inner in [False,True]:
        for j in range(nv):ring(j,inner)
    for l in range(2):
        ofs=l*nv*nx
        for j in range(nv-1):
            for i in range(nx):
                a=ofs+j*nx+i
                b=ofs+j*nx+(i+1)%nx
                c=a+nx;d=b+nx
                faces.append((a,b,d,c) if l==0 else (a,c,d,b))
    # Annulus cap: stops the shape from being only coincident flat skins.
    for top in [0,nv-1]:
        for i in range(nx):
            a=top*nx+i;b=top*nx+(i+1)%nx
            c=a+nv*nx;d=b+nv*nx
            faces.append((a,c,d,b) if top==0 else (a,b,d,c))
    obj=add_mesh("Adipose_"+name,verts,faces,fat_collection,fat,bone_name)
    obj["tissue"]="subcutaneous_adipose_reference"
    obj["thickness_m"]=thickness
    obj["density_kg_m3_reference"]=900.0
    obj["thermal_conductivity_w_mk_reference"]=.20
    obj["specific_heat_j_kgk_reference"]=2300.0
    obj["elmer_2d_thermal_model_coupled"]=False
    obj["modeling_lod"]="separate volumetric stylized transparent envelope"
    obj["region"]=style
    return obj

fat_objects=[
    adipose_shell("abdominal_waist",0,1.09,1.35,.152,.112,.009,"spine","torso"),
    adipose_shell("pelvis_hips",0,.94,1.10,.178,.13,.012,"hips","pelvis")]
for s,sgn in [("l",1),("r",-1)]:
    fat_objects.append(adipose_shell("thigh_"+s,sgn*.10,.58,.91,.069,.068,.008,"thigh_"+s,"thigh"))
    fat_objects.append(adipose_shell("upper_arm_"+s,sgn*.23,1.17,1.36,.043,.045,.005,"upper_arm_"+s,"upper_arm"))
assert len(fat_objects)==6
assert len(fat_collection.objects)==6
assert all(ob.data.vertices and ob.get("thickness_m")>0 for ob in fat_objects)

# Soft fascia is a separate translucent reference around broad muscle groups.
fascia_objs=[]
for x,s in [(-.23,"r"),(.23,"l")]:
    ob=tube("Fascia_upper_arm_"+s,
            [(x,0,1.38),(x*1.09,0,1.30),(x*1.10,.004,1.19)],
            .035,fascia_collection,fascia,"upper_arm_"+s,14)
    ob["fem_physics_not_solved"]=True;fascia_objs.append(ob)

# Deliberate per-render collection matrix, no global app setting modification.
group("Presentation").hide_render=False  # Critical: area lights reside in this collection.
scene.world.color=(.13,.14,.15)
scene.render.engine="CYCLES"
scene.cycles.samples=24
scene.render.resolution_x=900
scene.render.resolution_y=1030
scene.render.resolution_percentage=78
scene.view_settings.view_transform="Standard"
cam=scene.camera
cam.location=(2.4,-4.5,1.95)
aim=Vector((0,0,1.03))
cam.rotation_euler=(aim-cam.location).to_track_quat("-Z","Y").to_euler()
cam.data.type="ORTHO"
cam.data.ortho_scale=2.05

# Render three genuinely different anatomical views; do not pretend they
# depict precise body composition or that thermal FEM was solved on them.
display=["Bones","Cartilage","Muscles","Ligaments","Adipose","Fascia"]
views=[
 ("skeletal_curved_ribs",{"Bones","Cartilage","Ligaments"}),
 ("muscular_fibers",{"Muscles","Ligaments"}),
 ("muscle_with_adipose",{"Muscles","Adipose","Fascia"}),
 ("full_anatomy_exploded",{"Bones","Cartilage","Muscles","Adipose"})
]
pictures=[]
for label,enabled in views:
    for group_name in display:
        group(group_name).hide_render=(group_name not in enabled)
    scene.render.filepath=str(ROOT/("anatomy_"+label+"_v2.png"))
    bpy.ops.render.render(write_still=True)
    assert os.path.getsize(scene.render.filepath)>15000
    pictures.append(os.path.basename(scene.render.filepath))
for g in display:
    group(g).hide_render=(g in {"Muscles","Adipose","Fascia"})
group("Rig").hide_render=True

scene["visual_revision"]="v0.2 curved rib arcs + 72 vertebral process meshes + 6 adipose hollow volumes + shaded 60 muscles"
scene["visual_model_medically_accurate"]=False
scene["soft_tissue_fem_solved_on_actual_3d_geometry"]=False
scene["muscle_actuator_implemented"]=False
scene["adipose_shell_count"]=6
scene["vertebral_process_meshes"]=process_count
scene["curved_rib_count"]=rib_count
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"anatomy_skeleton_v1.blend"))
# Export an optional dedicated adipose layer for later low-LOD visual debug,
# separately from the original bone and muscle meshes.
bpy.ops.object.select_all(action="DESELECT")
for ob in fat_objects:ob.select_set(True)
arm.select_set(True)
bpy.context.view_layer.objects.active=arm
bpy.ops.export_scene.gltf(filepath=str(ROOT/"anatomy_adipose_v2.glb"),export_format="GLB",use_selection=True,export_extras=True)
assert os.path.getsize(ROOT/"anatomy_adipose_v2.glb")>10000
meta=json.loads((ROOT/"meta.json").read_text())
meta["version"]="0.2.0-visual-tissue"
meta["updated"]=datetime.datetime.now(datetime.timezone.utc).isoformat()
meta["description"]="Prototype 194-bone anatomy with curved ribs, spine processes, fibrous muscle shaders, 6 volumetric fat shells, reference Bullet and Elmer FEM; not a clinically validated body."
meta["files"]=[]
for file in sorted(ROOT.iterdir()):
    if not file.is_file() or file.name=="meta.json":continue
    data=file.read_bytes()
    meta["files"].append({"path":file.name,"bytes":len(data),"sha256":hashlib.sha256(data).hexdigest()})
(ROOT/"meta.json").write_text(json.dumps(meta,ensure_ascii=False,indent=2))
summary=dict(rig_bones=len(arm.data.bones),rigid_bodies=sum(o.rigid_body is not None for o in bpy.data.objects),
    joints=sum(o.rigid_body_constraint is not None for o in bpy.data.objects),
    original_muscle_bundles=len(group("Muscles").objects),
    curved_ribs=rib_count,spinal_process_meshes=process_count,
    adipose_hollow_volumes=len(fat_objects),fascia_objects=len(fascia_objs),
    render_images=pictures,adipose_glb_bytes=os.path.getsize(ROOT/"anatomy_adipose_v2.glb"),
    actual_3d_soft_tissue_fem=False,medical_accuracy=False)
(ROOT/"visual_soft_tissue_manifest_v2.json").write_text(json.dumps(summary,indent=2))
print("ANATOMY_VISUAL_V2="+json.dumps(summary))