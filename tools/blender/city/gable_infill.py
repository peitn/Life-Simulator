# Original Life Simulator M1 triangular gable infill. Blender 4.x, meters.
import bpy,bmesh,os,math,json,hashlib,base64
from mathutils import Vector
OUT=os.environ.get("CITY_GABLE_OUT","/tmp/city-fallback-1792946854-181335-gable")
os.makedirs(OUT,exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
s=bpy.context.scene
s.unit_settings.system="METRIC"
s.unit_settings.scale_length=1
mat=bpy.data.materials.new("Warm plaster")
mat.use_nodes=True
p=mat.node_tree.nodes.get("Principled BSDF")
p.inputs["Base Color"].default_value=(.64,.60,.52,1)
p.inputs["Roughness"].default_value=.85
root=bpy.data.objects.new("gable_infill_2m",None)
s.collection.objects.link(root)
mesh=bpy.data.meshes.new("gable_prism")
mesh.from_pydata([(0,0,0),(2,0,0),(1,0,.6),(0,.12,0),(2,.12,0),(1,.12,.6)],[],[(0,1,2),(3,5,4),(0,3,4,1),(0,2,5,3),(2,1,4,5)])
mesh.update()
obj=bpy.data.objects.new("gable_prism",mesh)
s.collection.objects.link(obj)
obj.parent=root
mesh.materials.append(mat)
uv=mesh.uv_layers.new(name="UVMap")
for face in mesh.polygons:
 for li in face.loop_indices:
  v=mesh.vertices[mesh.loops[li].vertex_index].co
  n=face.normal
  uv.data[li].uv=(v.x,v.z) if abs(n.y)>.9 else ((v.x,v.y) if abs(n.z)>.9 else (v.x*math.sqrt(1+.6**2),v.y))
bm=bmesh.new()
bm.from_mesh(mesh)
assert all(e.is_manifold for e in bm.edges)
assert all(f.calc_area()>1e-10 for f in bm.faces)
bm.free()
mesh.calc_loop_triangles()
assert len(mesh.loop_triangles)==8 and len(mesh.vertices)==6
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
obj.select_set(True)
bpy.context.view_layer.objects.active=root
glb=OUT+"/gable_infill_2m.glb"
bpy.ops.export_scene.gltf(filepath=glb,export_format="GLB",use_selection=True,export_yup=True)
# Render-only studio; not part of exported geometry.
bpy.ops.object.camera_add()
cam=bpy.context.object
s.camera=cam
cam.data.type="ORTHO"
cam.data.ortho_scale=3.5
for loc,power in [((0,-3,4),350),((4,2,5),300)]:
 bpy.ops.object.light_add(type="AREA",location=loc)
 lamp=bpy.context.object
 lamp.data.energy=power
 lamp.data.size=4
 lamp.rotation_euler=(Vector((1,.05,.2))-lamp.location).to_track_quat("-Z","Y").to_euler()
s.render.engine="CYCLES"
s.cycles.samples=8
s.cycles.use_denoising=False
s.render.resolution_x=256
s.render.resolution_y=256
s.render.resolution_percentage=100
s.render.image_settings.file_format="JPEG"
for label,loc in [("front",(3,-4,2.4)),("back",(-2,4,2.6)),("top",(3,2,4))]:
 cam.location=loc
 cam.rotation_euler=(Vector((1,.05,.2))-cam.location).to_track_quat("-Z","Y").to_euler()
 s.render.filepath=OUT+"/"+label+".jpg"
 bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT+"/gable_infill.blend",compress=True)
raw=open(glb,"rb").read()
print("GABLE_PROTOTYPE="+json.dumps({"triangles":8,"meshes":1,"glb_bytes":len(raw),"glb_sha256":hashlib.sha256(raw).hexdigest(),"blend_path":OUT+"/gable_infill.blend","render_paths":[OUT+"/"+n+".jpg" for n in ("front","back","top")]}))
print("GABLE_GLBB64="+base64.b64encode(raw).decode("ascii"))
