import bpy, os, json, math, bmesh, hashlib
from mathutils import Vector
OUT="/tmp/city-1792873902-112872"
os.makedirs(OUT,exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'
scene.unit_settings.scale_length=1.0
def material(name,color,rough):
 m=bpy.data.materials.new(name);m.use_nodes=True
 p=m.node_tree.nodes.get("Principled BSDF")
 p.inputs["Base Color"].default_value=(*color,1)
 p.inputs["Roughness"].default_value=rough
 return m
plaster=material("Warm plaster",(.64,.60,.52),.85)
trim=material("Painted door trim",(.22,.25,.24),.55)
root=bpy.data.objects.new("wall_corner_2m",None)
scene.collection.objects.link(root)
parts=[]
def prism(name,outline,height,mat):
 n=len(outline)
 verts=[(x,y,z) for z in [0,height] for x,y in outline]
 faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
 faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
 bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(mesh);bm.free()
 o=bpy.data.objects.new(name,mesh);scene.collection.objects.link(o)
 o.data.materials.append(mat)
 uv=mesh.uv_layers.new(name="UVMap")
 for poly in mesh.polygons:
  normal=poly.normal
  axes=(0,2) if abs(normal.y)>.5 else ((1,2) if abs(normal.x)>.5 else (0,1))
  for li in poly.loop_indices:
   co=mesh.vertices[mesh.loops[li].vertex_index].co
   uv.data[li].uv=(co[axes[0]],co[axes[1]])
 bpy.context.view_layer.objects.active=o;o.select_set(True)
 mod=o.modifiers.new("2mm edge highlights","BEVEL");mod.width=.002;mod.segments=2
 bpy.ops.object.modifier_apply(modifier=mod.name)
 o.select_set(False);o.parent=root;parts.append(o)
 return o
# One manifold L-shaped core; no overlapping boxes at the corner.
prism("corner_core",[(-.1,-.1),(2,-.1),(2,.1),(.1,.1),(.1,2),(-.1,2)],2.8,plaster)
# Continuous L-shaped outer and inner skirting, butt at existing wall sockets.
prism("skirting_outer",[(-.124,-.124),(2,-.124),(2,-.1),(-.1,-.1),(-.1,2),(-.124,2)],.11,trim)
prism("skirting_inner",[(.1,.1),(2,.1),(2,.124),(.124,.124),(.124,2),(.1,2)],.11,trim)
checks=[]
for o in parts:
 o.data.calc_loop_triangles()
 bm=bmesh.new();bm.from_mesh(o.data)
 assert all(e.is_manifold for e in bm.edges),o.name
 assert all(p.area>1e-10 for p in o.data.polygons),o.name
 assert all(abs(v.normal.length-1)<1e-4 for v in bm.verts),o.name
 bm.free()
 assert o.data.uv_layers.active
 for p in o.data.polygons:
  if p.area>.03 and len(p.loop_indices)==4:
   a=[o.data.uv_layers.active.data[i].uv for i in p.loop_indices]
   area=abs(sum(a[i].x*a[(i+1)%4].y-a[(i+1)%4].x*a[i].y for i in range(4)))/2
   assert abs(area/p.area-1)<.02,(o.name,area,p.area)
 checks.append(o.name)
triangles=sum(len(o.data.loop_triangles) for o in parts)
assert triangles<3000
bpy.ops.object.select_all(action='DESELECT');root.select_set(True)
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=OUT+"/wall_corner_2m.glb",export_format='GLB',use_selection=True,export_yup=True)
manifest={"asset":"wall_corner_2m","version":"0.1","source":"tools/blender/city/corner_wall.py","license":"Original Life Simulator asset; all rights reserved","units":"meters","axes":"Blender Z-up to Godot Y-up; legs +X and -Z","pivot":[0,0,0],"height_m":2.8,"leg_length_m":2,"core_depth_m":.2,"grid_m":.5,"sockets":[[2,0,0],[0,0,-2]],"triangles":triangles,"mesh_count":len(parts),"materials":["Warm plaster","Painted door trim"],"uv":"1UV unit/m; dominant-plane projection before 2mm bevel","textures":[],"collision_boxes":[{"center":[.95,1.4,0],"size":[2.1,2.8,.2]},{"center":[0,1.4,-1.05],"size":[.2,2.8,1.9]}],"interaction_points":[],"blender_checks":{"manifold":checks,"nondegenerate":True,"unit_normals":True,"large_quad_uv_density":True},"notes":"Three continuous manifold L-prisms. 2mm end bevel intentional joint. Solid-color PBR only; no texture maps, navmesh or gameplay FPS claim."}
open(OUT+"/manifest.json","w").write(json.dumps(manifest,indent=2))
# Presentation rig excluded from game export.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.012))
bpy.context.object.data.materials.append(material("Backdrop",(.19,.21,.23),.9))
scene.world.color=(.3,.3,.3)
for loc,energy,size in [((1,-4,6),850,5),((3,4,5),700,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc)
 o=bpy.context.object;o.data.energy=energy;o.data.shape='DISK';o.data.size=size
 o.rotation_euler=(Vector((.7,.7,1.2))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add()
cam=bpy.context.object;scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=4.8
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=False
scene.render.resolution_x=480;scene.render.resolution_y=480;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='JPEG';scene.render.image_settings.quality=80
for name,loc in [("outer",(-5,-6,4)),("inner",(6,7,4)),("top",(4,5,8))]:
 cam.location=loc;cam.rotation_euler=(Vector((.7,.7,1.3))-cam.location).to_track_quat('-Z','Y').to_euler()
 scene.render.filepath=OUT+"/"+name+".jpg";bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT+"/corner_wall.blend",compress=True)
print("CITY_RESULT="+json.dumps({"manifest":manifest,"files":{f:{"bytes":os.path.getsize(OUT+"/"+f),"sha256":hashlib.sha256(open(OUT+"/"+f,"rb").read()).hexdigest()} for f in os.listdir(OUT)}}))
