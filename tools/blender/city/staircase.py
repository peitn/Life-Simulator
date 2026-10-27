# Original Life Simulator staircase prototype. Meters; Blender Z-up -> Godot Y-up.
import bpy, bmesh, json, os, math
from mathutils import Vector
OUT = os.environ.get("LIFESIM_CITY_OUTPUT", "/tmp/city-1793018567-220376-stairs")
os.makedirs(OUT, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'
scene.unit_settings.scale_length=1
# 15 solid risers at .2m, .3m treads; 1m clear width; 4.5m total run.
profile=[(0,0)]
for i in range(15):
    profile.extend([(i*.3,(i+1)*.2),((i+1)*.3,(i+1)*.2)])
profile.append((4.5,0))
n=len(profile)
verts=[(x,y,z) for x in (0,1) for y,z in profile]
faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
mesh=bpy.data.meshes.new('StairSolid')
mesh.from_pydata(verts,[],faces); mesh.update()
bm=bmesh.new(); bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
assert all(e.is_manifold for e in bm.edges)
assert all(f.calc_area()>1e-9 for f in bm.faces)
assert bm.calc_volume(signed=True)>0
bm.to_mesh(mesh); bm.free()
uv=mesh.uv_layers.new(name="MeterUV")
for poly in mesh.polygons:
    axis=max(range(3), key=lambda i:abs(poly.normal[i]))
    axes=[i for i in range(3) if i!=axis]
    for li in poly.loop_indices:
        co=mesh.vertices[mesh.loops[li].vertex_index].co
        uv.data[li].uv=(co[axes[0]],co[axes[1]])
mat=bpy.data.materials.new("Warm stone"); mat.diffuse_color=(.52,.47,.40,1)
mat.use_nodes=True
bs=mat.node_tree.nodes.get("Principled BSDF"); bs.inputs["Base Color"].default_value=mat.diffuse_color
bs.inputs["Roughness"].default_value=.8
obj=bpy.data.objects.new("staircase_straight_3m",mesh); scene.collection.objects.link(obj); mesh.materials.append(mat)
bpy.context.view_layer.objects.active=obj; obj.select_set(True)
mesh.calc_loop_triangles()
bpy.ops.export_scene.gltf(filepath=OUT+"/staircase_straight_3m.glb",export_format="GLB",use_selection=True,export_yup=True)
report={"vertices":len(mesh.vertices),"faces":len(mesh.polygons),"triangles":len(mesh.loop_triangles),"volume_m3":sum(.3*1*(i+1)*.2 for i in range(15)),"bounds_godot":[[0,0,-4.5],[1,3,0]],"pivot":"bottom left at first riser","bottom_socket":[0,0,0],"top_socket":[0,3,-4.5],"riser":.2,"tread":.3,"width":1,"risers":15,"uv":"dominant-axis planar meters, no texture maps","normals":"flat outward; manifold solid","material":"Warm stone linear RGBA .52,.47,.40,1 roughness .8","license":"Original Life Simulator asset; all rights reserved","limitations":["No handrail","No floor opening module","No character traversal or navigation approval"]}
with open(OUT+"/geometry.json","w") as f: json.dump(report,f,indent=2)
scene.render.engine="CYCLES"; scene.cycles.samples=12; scene.cycles.use_denoising=False
scene.render.resolution_x=320;scene.render.resolution_y=320;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='JPEG'
scene.world.color=(.2,.2,.2)
for name,loc,power,size in [('Key',(3,-2,7),1100,5),('Fill',(-3,4,6),800,4)]:
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    light=bpy.data.objects.new(name,data);scene.collection.objects.link(light);light.location=loc
    light.rotation_euler=(Vector((.5,2,1.3))-light.location).to_track_quat('-Z','Y').to_euler()
camdata=bpy.data.cameras.new("Camera");cam=bpy.data.objects.new("Camera",camdata);scene.collection.objects.link(cam);scene.camera=cam
camdata.type='ORTHO';camdata.ortho_scale=6
for name,loc in [('front',(6,-6,5)),('side',(8,2.2,2.5)),('rear',(-5,8,5))]:
    cam.location=loc;cam.rotation_euler=(Vector((.5,2.25,1.5))-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=OUT+"/"+name+".jpg";bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT+"/staircase.blend",compress=True)
print("GEOMETRY="+json.dumps(report))
