import bpy, os, json, math
from mathutils import Vector
OUT="/tmp/lifesim_city_20261024_0029"
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
root=bpy.data.objects.new("wall_doorway_2m",None)
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
# Pivot at left wall endpoint, floor level; Blender +Z up, glTF/Godot +Y up.
box("left_pier",(.25,0,1.4),(.5,.2,2.8),plaster,.002)
box("right_pier",(1.75,0,1.4),(.5,.2,2.8),plaster,.002)
box("lintel",(1,0,2.45),(1,.2,.7),plaster,.002)
# Casing on both faces, clear opening remains 1.0 x 2.1 m.
for side in [-1,1]:
 y=side*.115
 box("casing_left_"+str(side),(.46,y,1.05),(.08,.03,2.10),wood,.003)
 box("casing_right_"+str(side),(1.54,y,1.05),(.08,.03,2.10),wood,.003)
 box("casing_top_"+str(side),(1,y,2.14),(1.16,.03,.08),wood,.003)
 for x in [.23,1.77]:
  box("skirting_"+str(side)+"_"+str(x),(x,side*.112,.055),(.46,.024,.11),wood,.002)
bpy.ops.object.select_all(action='DESELECT')
root.select_set(True)
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=OUT+"/wall_doorway_2m.glb",export_format='GLB',use_selection=True,export_yup=True)
triangles=sum(len(o.data.polygons)*0 for o in parts)
for o in parts:o.data.calc_loop_triangles()
triangles=sum(len(o.data.loop_triangles) for o in parts)
assert triangles < 3000
for o in parts:
 assert o.data.uv_layers.active is not None
 assert all(p.area>0 for p in o.data.polygons)
manifest={"asset":"wall_doorway_2m","version":"0.1","license":"Original Life Simulator asset; all rights reserved","source":"doorway.py","units":"meters","godot_axes":"Y up; width X; thickness Z","pivot":[0,0,0],"wall_extent":[2,2.8,.2],"visual_depth":.26,"opening":{"x":[.5,1.5],"y":[0,2.1]},"grid_m":.5,"triangles":triangles,"materials":["Warm plaster","Painted door trim"],"uv":"1 UV unit per meter, projected before bevel","textures":[],"interaction_points":[],"collision_boxes":[{"center":[.25,1.4,0],"size":[.5,2.8,.2]},{"center":[1.75,1.4,0],"size":[.5,2.8,.2]},{"center":[1,2.45,0],"size":[1,.7,.2]}],"notes":"Open doorway, no door leaf yet. Casings decorative; simplified collision excludes 3 cm trim. Navmesh and build-mode integration pending."}
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
bpy.ops.wm.save_as_mainfile(filepath=OUT+"/doorway.blend",compress=True)
print("CITY_RESULT="+json.dumps({"manifest":manifest,"files":{f:os.path.getsize(OUT+"/"+f) for f in os.listdir(OUT)}}))
