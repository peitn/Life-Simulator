import bpy, os, json, math
from mathutils import Vector
OUT="/tmp/city-1792820091-68355"
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
plaster=material("Warm plaster",(0.64,0.60,0.52),0.85)
wood=material("Painted door trim",(0.22,0.25,0.24),0.55)
root=bpy.data.objects.new("wall_solid_2m",None)
scene.collection.objects.link(root)
parts=[]
def box(name,loc,size,mat,bevel):
 bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
 o=bpy.context.object;o.name=name;o.dimensions=size
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.data.materials.append(mat)
 # Physical UV scale: one UV unit per meter; project each face on dominant axes.
 uv=o.data.uv_layers.active
 for poly in o.data.polygons:
  n=poly.normal
  axes=(0,2) if abs(n.y)>0.5 else ((1,2) if abs(n.x)>0.5 else (0,1))
  for li in poly.loop_indices:
   co=o.data.vertices[o.data.loops[li].vertex_index].co+o.location
   uv.data[li].uv=(co[axes[0]],co[axes[1]])
 if bevel:
  mod=o.modifiers.new("Edge highlights","BEVEL");mod.width=bevel;mod.segments=2
  bpy.context.view_layer.objects.active=o
  bpy.ops.object.modifier_apply(modifier=mod.name)
 o.parent=root;parts.append(o)
 return o
# Pivot left endpoint at floor, +X width; export converts Z-up to Y-up.
box("solid_core",(1,0,1.4),(2,.2,2.8),plaster,.002)
for side in [-1,1]:
 box("skirting_"+str(side),(1,side*.112,.055),(2,.024,.11),wood,.002)
bpy.ops.object.select_all(action='DESELECT')
root.select_set(True)
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=OUT+"/wall_solid_2m.glb",export_format='GLB',use_selection=True,export_yup=True)
triangles=sum(len(o.data.polygons)*0 for o in parts)
for o in parts:o.data.calc_loop_triangles()
triangles=sum(len(o.data.loop_triangles) for o in parts)
assert triangles < 3000
for o in parts:
 assert o.data.uv_layers.active is not None
 assert all(p.area>0 for p in o.data.polygons)
manifest={"asset":"wall_solid_2m","version":"0.1","license":"Original Life Simulator asset; all rights reserved","source":"tools/blender/city/solid_wall.py","units":"meters","godot_axes":"Y up; width X; thickness Z","pivot":[0,0,0],"wall_extent":[2,2.8,.2],"visual_depth":.248,"grid_m":.5,"triangles":triangles,"mesh_count":len(parts),"materials":["Warm plaster","Painted door trim"],"uv":"1 UV unit per meter; projected before bevel","textures":[],"collision_boxes":[{"center":[1,1.4,0],"size":[2,2.8,.2]}],"interaction_points":[],"notes":"Solid wall with two-sided skirting. Matches doorway core and skirting. End bevel 2mm creates intentional joint line; no texture maps or corner connector yet."}
open(OUT+"/manifest.json","w").write(json.dumps(manifest,indent=2))
# Presentation rig excluded from GLB.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.012))
bpy.context.object.data.materials.append(material("Backdrop",(.19,.21,.23),.9))
scene.world.color=(.3,.3,.3)
for loc,energy,size in [((0,-4,6),700,5),((3,3,4),500,4)]:
 bpy.ops.object.light_add(type='AREA',location=loc)
 o=bpy.context.object;o.data.energy=energy;o.data.shape='DISK';o.data.size=size
 o.rotation_euler=(Vector((1,0,1.3))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add()
cam=bpy.context.object;scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=4.2
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=False
scene.render.resolution_x=480;scene.render.resolution_y=480;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='JPEG';scene.render.image_settings.quality=75

for name,loc in [("front",(4,-6,3.6)),("back",(-2,6,3.3))]:
 cam.location=loc;cam.rotation_euler=(Vector((1,0,1.35))-cam.location).to_track_quat('-Z','Y').to_euler()
 scene.render.filepath=OUT+"/"+name+".jpg";bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT+"/solid_wall.blend",compress=True)
print("CITY_RESULT="+json.dumps({"manifest":manifest,"files":{f:os.path.getsize(OUT+"/"+f) for f in os.listdir(OUT)}}))
