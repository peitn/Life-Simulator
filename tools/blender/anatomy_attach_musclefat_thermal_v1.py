#!/usr/bin/env python3
"""Attach ACTUAL Elmer 26.2 multi-material FEM evidence and render clearly
labeled analytical 1D cross-section profiles VALIDATED by Elmer VTU.
Never misrepresent these as mapped 3D anatomical surface temperatures.
"""
import bpy,json,datetime,hashlib,os,math
from mathutils import Vector
from pathlib import Path

ROOT=Path('/app/data/library/model/lifesim-anatomy-skeleton-v1')
data=json.loads((ROOT/'elmer_muscle_fat_v1.json').read_text(encoding='utf-8'))
assert data['schema']=='lifesim.fem.musclefat.v1'
assert all(c['solver_ok'] for c in data['cases'])
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'anatomy_skeleton_v1.blend'))
scene=bpy.context.scene
rig=bpy.data.objects['Anatomy_Rig_V1']
assert len(rig.data.bones)==194
fat=[o for o in bpy.data.objects if o.name.startswith('Adipose_')]
muscles=[o for o in bpy.data.objects if o.name.startswith('Muscle_')]
assert len(fat)==6 and len(muscles)==60

ref=bpy.data.texts.get('Elmer_MuscleFat_Thermodynamics_v1.json')
if ref is None:ref=bpy.data.texts.new('Elmer_MuscleFat_Thermodynamics_v1.json')
ref.clear();ref.write(json.dumps(data,ensure_ascii=False,indent=2))
scene['elmer_mfat_solver']='ElmerSolver 26.2, 2D separate rectangle, NOT 3D modeled body'
scene['elmer_mfat_rest_skin_surface_K']=301.891
scene['elmer_mfat_active_skin_surface_K']=303.235
scene['elmer_mfat_thickfat_skin_surface_K']=300.173
scene['elmer_mfat_transient_12min_skin_surface_K']=304.685
scene['elmer_mfat_passive_compression_m']=.000285811
scene['elmer_mfat_live_simulation']=False
scene['elmer_mfat_actual_body_geometry_solved']=False

for o in fat:
    o['thermal_k_W_mK']=.2
    o['thermal_density_kg_m3']=900
    o['thermal_specific_heat_J_kgK']=2300
    o['metabolic_q_W_m3_reference']=60
    o['elastic_modulus_pa_linear_reference']=5000
    o['elmer_reference_material_id']=2
    o['numerical_field_mapped_to_this_3D_mesh']=False
for o in muscles:
    o['thermal_k_W_mK']=.5
    o['thermal_density_kg_m3']=1050
    o['thermal_specific_heat_J_kgK']=3750
    o['metabolic_q_W_m3_reference']=700
    o['metabolic_q_W_m3_active_reference']=5000
    o['elastic_modulus_pa_linear_reference']=30000
    o['elmer_reference_material_id']=1
    o['numerical_field_mapped_to_this_3D_mesh']=False

collection=bpy.data.collections.get('Anatomy_ThermalDiagnostic')
if collection is None:
    collection=bpy.data.collections.new('Anatomy_ThermalDiagnostic')
    scene.collection.children.link(collection)
assert len(collection.objects)==0
material=bpy.data.materials.new('Thermal_Reference_Color_300to311K')
material.use_nodes=True
nodes=material.node_tree.nodes
nodes.clear()
out=nodes.new('ShaderNodeOutputMaterial')
emit=nodes.new('ShaderNodeEmission')
attribute=nodes.new('ShaderNodeVertexColor')
attribute.layer_name='heat_color'
material.node_tree.links.new(attribute.outputs['Color'],emit.inputs['Color'])
material.node_tree.links.new(emit.outputs['Emission'],out.inputs['Surface'])
text_material=bpy.data.materials.new('Thermal_Text_White')
text_material.diffuse_color=(.89,.93,.99,1)
text_material.use_nodes=True
nodes=text_material.node_tree.nodes
nodes.clear()
out=nodes.new('ShaderNodeOutputMaterial')
em=nodes.new('ShaderNodeEmission')
em.inputs['Color'].default_value=(.92,.94,1.0,1)
em.inputs['Strength'].default_value=1.0
text_material.node_tree.links.new(em.outputs['Emission'],out.inputs['Surface'])

def colormap(T):
    t=max(0,min(1,(T-296.)/(311.-296.)))
    # Blue at cool skin; orange at muscle core, not a patient measurement.
    if t<.5:
        u=t/.5
        return (.10+.52*u,.25+.30*u,.75-.40*u,1)
    u=(t-.5)/.5
    return (.62+.35*u,.55-.35*u,.35-.25*u,1)

def analytic_T(x,case):
    lm=case['Lm'];lf=case['Lf'];qm=case['qm'];qf=case['qf']
    km=.5;kf=.2;h=10;tc=310.15;ta=293.15
    R=lm/km+lf/kf+1/h
    f0=(tc-ta-.5*qm*lm*lm/km-qm*lm*lf/kf-.5*qf*lf*lf/kf
        -(qm*lm+qf*lf)/h)/R
    if x<=lm:
        return tc-(f0*x+.5*qm*x*x)/km
    interface=tc-(f0*lm+.5*qm*lm*lm)/km
    t=x-lm
    return interface-((f0+qm*lm)*t+.5*qf*t*t)/kf

def label(name,string,xyz,size=.035):
    crv=bpy.data.curves.new(name+'_curve','FONT')
    crv.body=string
    crv.size=size
    ob=bpy.data.objects.new(name,crv)
    collection.objects.link(ob)
    ob.location=xyz
    crv.materials.append(text_material)
    # Text appears in X/Z plane as viewed along negative Y.
    ob.rotation_euler=(math.pi/2,0,0)
    return ob

for index,case in enumerate(data['cases'][:3]):
    lab=['REST 700 W/m3','ACTIVE 5000 W/m3','THICK FAT 20 mm'][index]
    z=.6-index*.52
    nxm=24
    nxf=12 if index!=2 else 24
    lm=case['Lm'];lf=case['Lf'];end=lm+lf
    xs=[lm*j/nxm for j in range(nxm+1)]
    xs.extend(lm+lf*j/nxf for j in range(1,nxf+1))
    xleft=-.58
    scale=25.
    verts=[];faces=[]
    for i,x in enumerate(xs):
        xc=xleft+x*scale
        verts.extend([(xc,0,z-.078),(xc,0,z+.078)])
    for i in range(len(xs)-1):faces.append((i*2,(i+1)*2,(i+1)*2+1,i*2+1))
    mesh=bpy.data.meshes.new('Thermo_ElmerCalibrated_2D_'+str(index))
    mesh.from_pydata(verts,[],faces);mesh.update()
    mesh.materials.append(material)
    colors=mesh.vertex_colors.new(name='heat_color')
    for polygon in mesh.polygons:
        for li in polygon.loop_indices:
            vid=mesh.loops[li].vertex_index
            temp=analytic_T(xs[vid//2],case)
            colors.data[li].color=colormap(temp)
    ob=bpy.data.objects.new('Reference_Cutaway_'+str(index),mesh)
    collection.objects.link(ob)
    ob['rendered_analytical_field_validated_by_Elmer']=True
    ob['actual_3D_anatomical_temperature_mesh']=False
    ob['muscle_fat_interface_x_m']=lm
    ob['skin_temperature_K_elmer']=case['temperature_min_K']
    label('Label_'+str(index),
          lab+' | skin '+format(case['temperature_min_K']-273.15,'.2f')+' C',
          (xleft,z and -.001 or -.001,z+.14),.041)
    boundary_x=xleft+lm*scale
    label('TissueMap_'+str(index),'MUSCLE        |     FAT',
         (xleft,-.001,z-.14),.034)
    border=bpy.data.curves.new('Interface_'+str(index),'CURVE')
    border.dimensions='3D';border.bevel_depth=.002; border.bevel_resolution=2
    spline=border.splines.new('POLY');spline.points.add(1)
    spline.points[0].co=(boundary_x,-.002,z-.078,1)
    spline.points[1].co=(boundary_x,-.002,z+.078,1)
    line=bpy.data.objects.new('Interface_line_'+str(index),border)
    collection.objects.link(line)
label('GlobalTitle','LIFE SIM / Elmer 26.2  |  Thermal material slice',
      (-.67,0,1.0),.059)
label('Disclaimer','2D model only  /  vertex colors are ANALYTIC profiles checked by FEM, not full-body heat',
      (-.67,0,-1.02),.029)
label('Legend','Blue: cooler adipose surface       Orange/red: core-facing warmer muscle',
      (-.67,0,-.91),.033)

# Exclude skeletal actor while rendering the thermal lab diagram.
old_flags={c.name:c.hide_render for c in bpy.data.collections}
for coll in bpy.data.collections:
    coll.hide_render=(coll.name!='Anatomy_ThermalDiagnostic')
collection.hide_render=False
temp_camera=bpy.data.objects.new('Anatomy_Thermo_DiagnosticCamera',bpy.data.cameras.new('ThermalDiagnosticCamera'))
collection.objects.link(temp_camera)
temp_camera.location=(0,-3.2,0)
temp_camera.rotation_euler=(math.pi/2,0,0)
temp_camera.data.type='ORTHO'
temp_camera.data.ortho_scale=2.4
old_cam=scene.camera
scene.camera=temp_camera
world=scene.world
world.use_nodes=True
bg=world.node_tree.nodes.get('Background')
if bg:bg.inputs['Color'].default_value=(.06,.065,.075,1);bg.inputs['Strength'].default_value=.8
scene.render.engine='CYCLES';scene.cycles.samples=16
scene.render.resolution_x=1150;scene.render.resolution_y=760
scene.render.resolution_percentage=85
scene.render.filepath=str(ROOT/'anatomy_elmer_muscle_fat_thermal_diagnostic_v1.png')
bpy.ops.render.render(write_still=True)
assert os.path.getsize(scene.render.filepath)>18000
scene.camera=old_cam
for coll in bpy.data.collections:
    if coll.name in old_flags:coll.hide_render=old_flags[coll.name]
collection.hide_render=True
scene['thermal_visual_diagnostic']='Elmer-checked analytical 1D heat profile, isolated cutaway; NOT 3D heat field'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'anatomy_skeleton_v1.blend'))
meta=json.loads((ROOT/'meta.json').read_text())
meta['version']='0.2.1-visual-thermal-fem'
meta['updated']=datetime.datetime.now(datetime.timezone.utc).isoformat()
meta['files']=[]
for f in sorted(ROOT.iterdir()):
    if not f.is_file() or f.name=='meta.json':continue
    bits=f.read_bytes()
    meta['files'].append({'path':f.name,'bytes':len(bits),'sha256':hashlib.sha256(bits).hexdigest()})
(ROOT/'meta.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2))
print('BLENDER_MUSCLE_FAT_THERMO_ATTACHED bones=',len(rig.data.bones),
      'fat_shells=',len(fat),'muscles=',len(muscles),
      'reference_records=',len(data['cases']),
      'render_bytes=',os.path.getsize(ROOT/'anatomy_elmer_muscle_fat_thermal_diagnostic_v1.png'))