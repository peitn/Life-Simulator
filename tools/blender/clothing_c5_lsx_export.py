# Transfer authored C5 wardrobe GLB from Blender into five skinned LSX files.
# Run on the Blender MCP service after clothing_c5.py. Independent from Godot's glTF importer.
import bpy, urllib.request, json, hashlib
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="/tmp/lifesim_clothing_c5.glb")
url="https://peiti-godot-mcp.hf.space/doc/file:lifesim/tools/blender/lsx_common.py"
common=urllib.request.urlopen(url,timeout=25).read().split(b"\n\n",1)[-1].decode("utf-8")
ns={}
exec(compile(common,"lsx_common.py","exec"),ns)
arm=bpy.data.objects["body"]
def order_bones(bones):
    out=[]
    def visit(b):
        if b.parent and b.parent.name not in out: visit(b.parent)
        if b.name not in out: out.append(b.name)
    for b in bones: visit(b)
    return out
order=order_bones(arm.data.bones)
for obj in bpy.data.objects:
    if obj.type=="MESH" and obj.name.startswith("C5__"):
        obj["lsx_group"]=obj.name.split("__")[1]+"_"+obj.name.split("__")[2]
        for mat in obj.data.materials:
            if mat is not None and mat.name not in ns["MATS"]:
                kind=mat.name.split("_")[-1]
                rough=0.55 if kind in ("satin","leather","suiting") else (0.96 if kind in ("knit","fleece") else 0.88)
                ns["MATS"][mat.name]={"name":mat.name,"color":[0.77,0.77,0.77],"rough":rough,"metal":0.0}
MCP="https://peiti-godot-mcp.hf.space/mcp"
def write(path,content):
    data={"jsonrpc":"2.0","id":11,"method":"tools/call",
         "params":{"name":"godot_file_write","arguments":{"project":"lifesim","path":path,"content":content}}}
    req=urllib.request.Request(MCP,data=json.dumps(data).encode(),method="POST",
        headers={"Content-Type":"application/json","Accept":"application/json, text/event-stream"})
    return urllib.request.urlopen(req,timeout=35).read()[:60]
manifest={}
for part in ["top","bottom","shoes","dress","legs"]:
    objects=[o for o in bpy.data.objects if o.type=="MESH" and o.name.startswith("C5__"+part+"__")]
    encoded=ns["export_lsx"]("c5_"+part,objects,arm,order,{"purpose":"clothing_C5","part":part})
    chunk=125000
    count=(len(encoded)+chunk-1)//chunk
    for i in range(count):
        write("previews/c5_lsx/%s_%03d.b64"%(part,i),encoded[i*chunk:(i+1)*chunk])
    manifest[part]={"parts":count,"length":len(encoded),"objects":len(objects),
                    "md5_b64":hashlib.md5(encoded.encode()).hexdigest()}
    print("EXPORTED",part,"objects",len(objects),"chunks",count)
write("previews/c5_lsx/manifest.json",json.dumps(manifest,indent=2))
print("LSX_READY",manifest)

