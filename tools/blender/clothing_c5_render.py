# Life Simulator C5 - Blender Cycles 4-panel visual QA contact sheet.
# Uses authored GLB and original character GLB, shows hoodie/front+back, jacket skirt, dress.
import bpy, urllib.request, base64, json, math
import numpy as np
from mathutils import Vector

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="/tmp/lifesim_c5_source.glb")
avatar=[o for o in bpy.data.objects if o.type=="MESH"]
for o in avatar:
    if o.name.endswith("__cloth_shirt") or o.name.endswith("__cloth_pants") or o.name.endswith("__shoe_leather"):
        o.hide_render=True
    if o.name.startswith("hair_long") or o.name=="Icosphere":
        o.hide_render=True
bpy.ops.import_scene.gltf(filepath="/tmp/lifesim_clothing_c5.glb")
clothes=[o for o in bpy.data.objects if o.type=="MESH" and o.name.startswith("C5__")]
palette={"cloth_fleece":(0.30,0.16,0.23,1),
 "cloth_knit":(0.28,0.35,0.37,1),"cloth_denim":(0.17,0.25,0.38,1),
 "cloth_suiting":(0.22,0.29,0.34,1),"cloth_satin":(0.38,0.19,0.28,1),
 "cloth_cotton":(0.39,0.42,0.46,1),"shoe_leather_c5":(0.17,0.13,0.12,1)}
for ob in clothes:
    for mat in ob.data.materials:
        if mat is not None and mat.name in palette and mat.use_nodes:
            bs=mat.node_tree.nodes.get("Principled BSDF")
            if bs:
                sockets=[link.from_socket for link in list(bs.inputs["Base Color"].links)]
                for link in list(bs.inputs["Base Color"].links):
                    mat.node_tree.links.remove(link)
                if sockets:
                    mix=mat.node_tree.nodes.new("ShaderNodeMixRGB")
                    mix.blend_type="MULTIPLY";mix.inputs[0].default_value=1.0
                    mat.node_tree.links.new(sockets[0],mix.inputs[1])
                    mix.inputs[2].default_value=palette[mat.name]
                    mat.node_tree.links.new(mix.outputs["Color"],bs.inputs["Base Color"])
                else:
                    bs.inputs["Base Color"].default_value=palette[mat.name]
world=bpy.data.worlds.new("Studio")
bpy.context.scene.world=world;world.use_nodes=True
world.node_tree.nodes["Background"].inputs["Color"].default_value=(0.22,0.24,0.27,1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value=0.75
def area(name,loc,power,size):
    ld=bpy.data.lights.new(name,"AREA")
    ld.energy=power;ld.shape="DISK";ld.size=size
    o=bpy.data.objects.new(name,ld);bpy.context.collection.objects.link(o)
    o.location=loc
    o.rotation_euler=(Vector((0,0,1.0))-o.location).to_track_quat("-Z","Y").to_euler()
area("Key",(-1.4,-2.8,3.1),300,2.3)
area("Fill",(1.7,-1.1,2.2),175,2.0)
area("Rim",(0.0,1.6,2.4),210,1.4)
cd=bpy.data.cameras.new("Camera");cd.type="ORTHO";cd.ortho_scale=2.2
cam=bpy.data.objects.new("Camera",cd);bpy.context.collection.objects.link(cam)
sc=bpy.context.scene;sc.camera=cam;sc.render.engine="CYCLES"
sc.cycles.samples=11;sc.cycles.use_denoising=False
sc.render.resolution_x=290;sc.render.resolution_y=480
sc.render.resolution_percentage=100;sc.render.film_transparent=False
sc.render.image_settings.file_format="PNG";sc.view_settings.view_transform="AgX"
cases=[
 ("hoodie_front",["top__mikina","bottom__dziny","shoes__kozacky"],0.7,-3.7),
 ("hoodie_back",["top__mikina","bottom__dziny","shoes__kozacky"],0.0,3.7),
 ("jacket_skirt",["top__sako","bottom__sukne","shoes__lodicky","legs__skin"],0.7,-3.7),
 ("dress",["top__saty","dress__saty","shoes__polobotky","legs__skin"],0.7,-3.7),
]
rows=[]
for title,tags,cx,cy in cases:
    for ob in clothes:
        ob.hide_render=not any(ob.name.startswith("C5__"+t+"__") for t in tags)
    cam.location=(cx,cy,1.74)
    cam.rotation_euler=(Vector((0,0,0.94))-cam.location).to_track_quat("-Z","Y").to_euler()
    sc.render.filepath="/tmp/"+title+".png"
    bpy.ops.render.render(write_still=True)
    im=bpy.data.images.load(sc.render.filepath)
    rows.append(np.array(im.pixels[:],dtype=np.float32).reshape(480,290,4).copy())
    bpy.data.images.remove(im)
    print("C5_QA_RENDERED",title,"mesh_count",sum(not o.hide_render for o in clothes))
sheet=np.concatenate(rows,axis=1)
preview=bpy.data.images.new("C5_sheet",1160,480,alpha=False)
preview.pixels.foreach_set(sheet.ravel().tolist())
preview.filepath_raw="/tmp/lifesim_c5_sheet.jpg"
preview.file_format="JPEG";preview.save()
b64=base64.b64encode(open(preview.filepath_raw,"rb").read()).decode()
MCP="https://peiti-godot-mcp.hf.space/mcp"
def put(path,content):
    d={"jsonrpc":"2.0","id":31,"method":"tools/call",
       "params":{"name":"godot_file_write","arguments":{"project":"lifesim","path":path,"content":content}}}
    req=urllib.request.Request(MCP,data=json.dumps(d).encode(),method="POST",
         headers={"Content-Type":"application/json","Accept":"application/json, text/event-stream"})
    return urllib.request.urlopen(req,timeout=40).read()[:60]
for i in range(0,len(b64),125000):
    put("previews/c5_qa_%02d.b64"%(i//125000),b64[i:i+125000])
put("previews/c5_qa_manifest.json",json.dumps({"parts":(len(b64)+124999)//125000,
   "bytes":len(b64)*3//4,"cases":[x[0] for x in cases]}))
print("C5_QA_SHEET_SENT",len(b64))

