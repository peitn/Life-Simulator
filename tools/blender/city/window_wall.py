# M1 window-wall Blender source; prototype pending Godot import/QA.
import bpy,os,json,hashlib,bmesh
from mathutils import Vector
OUT="/tmp/city-fallback-1792885508-136007-window"
os.makedirs(OUT,exist_ok=True)
bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.unit_settings.system="METRIC";scene.unit_settings.scale_length=1
def material(name,rgb,rough):
 m=bpy.data.materials.new(name);m.use_nodes=True
 p=m.node_tree.nodes.get("Principled BSDF")
 p.inputs["Base Color"].default_value=(*rgb,1)
 p.inputs["Roughness"].default_value=rough
 return m
plaster=material("Warm plaster",(.64,.60,.52),.85)
trim=material("Painted door trim",(.22,.25,.24),.55)
root=bpy.data.objects.new("wall_window_2m",None);scene.collection.objects.link(root)
parts=[]
def box(name,center,size,mat):
 bpy.ops.mesh.primitive_cube_add(size=1,location=center)
 o=bpy.context.object;o.name=name;o.dimensions=size
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.data.materials.append(mat);uv=o.data.uv_layers.active
 for poly in o.data.polygons:
  n=poly.normal;axes=(0,2) if abs(n.y)>.5 else ((1,2) if abs(n.x)>.5 else (0,1))
  for li in poly.loop_indices:
   v=o.data.vertices[o.data.loops[li].vertex_index].co+o.location
   uv.data[li].uv=(v[axes[0]],v[axes[1]])
 bevel=o.modifiers.new("2mm highlights","BEVEL");bevel.width=.002;bevel.segments=2
 bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=bevel.name)
 o.parent=root;parts.append(o)
box("window_left",(.2,0,1.4),(.4,.2,2.8),plaster)
box("window_right",(1.8,0,1.4),(.4,.2,2.8),plaster)
box("window_sill_core",(1,0,.45),(1.2,.2,.9),plaster)
box("window_header_core",(1,0,2.45),(1.2,.2,.7),plaster)
for side in (-1,1):
 box("skirting_"+str(side),(1,side*.112,.055),(2,.024,.11),trim)
 box("frame_left_"+str(side),(.365,side*.116,1.5),(.07,.032,1.2),trim)
 box("frame_right_"+str(side),(1.635,side*.116,1.5),(.07,.032,1.2),trim)
 box("frame_bottom_"+str(side),(1,side*.116,.865),(1.2,.032,.07),trim)
 box("frame_top_"+str(side),(1,side*.116,2.135),(1.2,.032,.07),trim)
for o in parts:
 o.data.calc_loop_triangles()
 bm=bmesh.new();bm.from_mesh(o.data)
 assert all(e.is_manifold for e in bm.edges),o.name
 assert all(f.calc_area()>1e-10 for f in bm.faces),o.name
 assert all(abs(v.normal.length-1)<1e-4 for v in bm.verts),o.name
 bm.free();assert o.data.uv_layers.active is not None
triangles=sum(len(o.data.loop_triangles) for o in parts)
assert len(parts)==14 and triangles<3000,(len(parts),triangles)
manifest={"asset":"wall_window_2m","version":"0.1-prototype","source":"tools/blender/city/window_wall.py","license":"Original Life Simulator asset; all rights reserved","units":"meters","axes":"Blender Z-up to Godot Y-up","pivot":[0,0,0],"width_m":2,"height_m":2.8,"core_depth_m":.2,"grid_m":.5,"window_opening":{"x_min":.4,"x_max":1.6,"y_min":.9,"y_max":2.1},"sockets":[[0,0,0],[2,0,0]],"triangles":triangles,"mesh_count":14,"materials":["Warm plaster","Painted door trim"],"textures":[],"uv":"Planar projection 1UV/m before bevel","collision_boxes":[{"center":[.2,1.4,0],"size":[.4,2.8,.2]},{"center":[1.8,1.4,0],"size":[.4,2.8,.2]},{"center":[1,.45,0],"size":[1.2,.9,.2]},{"center":[1,2.45,0],"size":[1.2,.7,.2]}],"notes":"Blender source prototype. Godot scene, import, physics and visual QA pending; no glass/navmesh/textures."}
bpy.ops.object.select_all(action="DESELECT");root.select_set(True)
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=OUT+"/wall_window_2m.glb",export_format="GLB",use_selection=True,export_yup=True)
with open(OUT+"/manifest.json","w") as f:json.dump(manifest,f,indent=2)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.012))
bpy.context.object.data.materials.append(material("Backdrop",(.19,.21,.23),.9))
scene.world.color=(.3,.3,.3)
for loc,power,size in [((0,-4,6),750,5),((3,4,5),600,4)]:
 bpy.ops.object.light_add(type="AREA",location=loc)
 lamp=bpy.context.object;lamp.data.energy=power;lamp.data.shape="DISK";lamp.data.size=size
 lamp.rotation_euler=(Vector((1,0,1.3))-lamp.location).to_track_quat("-Z","Y").to_euler()
bpy.ops.object.camera_add()
cam=bpy.context.object;scene.camera=cam;cam.data.type="ORTHO";cam.data.ortho_scale=4.5
scene.render.engine="CYCLES";scene.cycles.samples=16;scene.cycles.use_denoising=False
scene.render.resolution_x=320;scene.render.resolution_y=320;scene.render.resolution_percentage=100
scene.render.image_settings.file_format="JPEG";scene.render.image_settings.quality=78
for name,loc in [("front",(4,-6,3.7)),("back",(-2,6,3.5)),("top",(4,-4,7))]:
 cam.location=loc;cam.rotation_euler=(Vector((1,0,1.35))-cam.location).to_track_quat("-Z","Y").to_euler()
 scene.render.filepath=OUT+"/"+name+".jpg";bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT+"/window_wall.blend",compress=True)
print("CITY_WINDOW_RESULT="+json.dumps({"manifest":manifest,"files":{f:{"bytes":os.path.getsize(OUT+"/"+f),"sha256":hashlib.sha256(open(OUT+"/"+f,"rb").read()).hexdigest()} for f in os.listdir(OUT)}}))
