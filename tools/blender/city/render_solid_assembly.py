import bpy, os
from mathutils import Vector
OUT="/tmp/city-1792820091-68355"
bpy.ops.wm.open_mainfile(filepath=OUT+"/solid_wall.blend")
scene=bpy.context.scene
solid=bpy.data.objects["wall_solid_2m"]
second=solid.copy();scene.collection.objects.link(second);second.location.x=4
for child in list(solid.children):
 c=child.copy();c.data=child.data;scene.collection.objects.link(c);c.parent=second
plaster=bpy.data.materials["Warm plaster"];wood=bpy.data.materials["Painted door trim"]
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

root.location.x=2
cam=scene.camera;cam.data.ortho_scale=7.5
scene.render.resolution_x=720;scene.render.resolution_y=400
scene.cycles.samples=24
for name,loc in [("assembly_front",(8,-10,5)),("assembly_back",(-2,10,4.5))]:
 cam.location=loc;cam.rotation_euler=(Vector((3,0,1.3))-cam.location).to_track_quat('-Z','Y').to_euler()
 scene.render.filepath=OUT+"/"+name+".jpg";bpy.ops.render.render(write_still=True)
print("ASSEMBLY_RENDER_OK")
