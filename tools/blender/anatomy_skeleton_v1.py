#!/usr/bin/env python3
"""Life Simulator anatomical reference v0.1, generated in real Blender 4.0.
Human-scale (m), Z-up Blender coordinates; GLB converts Z-up to Godot Y-up.
NOT a clinical specimen, anatomically faithful 206-bone scan, or calibrated
musculoskeletal solver. The authored skin/17-bone gameplay rig is UNCHANGED.
Physics proxies and constraints are separate from the render/armature rig.
"""
import bpy, math, json, os, hashlib, datetime
from mathutils import Vector
from math import radians
from collections import Counter

ASSET="/app/data/library/model/lifesim-anatomy-skeleton-v1"
os.makedirs(ASSET,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for c in list(bpy.data.collections):
    if c.name!="Collection" and c.users==0: bpy.data.collections.remove(c)

scene=bpy.context.scene
scene.unit_settings.system='METRIC'
scene.unit_settings.scale_length=1.0
scene.gravity=(0,0,-9.81)
scene.render.engine='CYCLES'
scene.cycles.samples=8
scene.cycles.use_denoising=False
bpy.context.view_layer.cycles.use_denoising=False
scene.render.resolution_x=700
scene.render.resolution_y=820
scene.render.resolution_percentage=75
scene.render.film_transparent=False
scene.world.color=(.065,.075,.085)
scene.frame_start=1; scene.frame_end=32
scene['anatomy_version']='0.1.0'
scene['coordinate_convention']='Blender Z-up meters; GLB Godot Y-up'
scene['caveat']='Procedural teaching/modeling reference; NOT medical/FEA calibrated, Bullet not linked to gameplay'
scene['density_units']='kg/m^3'
scene['force_units']='N'
scene['torque_units']='Nm'

collections={}
for name in ["Rig","Bones","Cartilage","Muscles","Ligaments","Physics","Joints","Presentation"]:
    c=bpy.data.collections.new("Anatomy_"+name)
    scene.collection.children.link(c)
    collections[name]=c
collections["Physics"].hide_render=True
collections["Joints"].hide_render=True

def mat(name,colour,rough=.65,alpha=1.0,metal=0.0):
    m=bpy.data.materials.new("Anatomy_"+name)
    m.diffuse_color=(*colour,alpha)
    m.use_nodes=True
    bs=m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value=(*colour,1)
    bs.inputs["Roughness"].default_value=rough
    bs.inputs["Metallic"].default_value=metal
    bs.inputs["Alpha"].default_value=alpha
    if alpha<1:
        m.blend_method='BLEND'
        m.use_nodes=True
    return m
BONE_M=mat("cortical_bone",(.87,.79,.64),.65)
CART_M=mat("hyaline_cartilage",(.32,.67,.60),.30,.78)
DISC_M=mat("intervertebral_disc",(.45,.56,.72),.45)
MUSCLE_M=mat("skeletal_muscle",(.58,.12,.15),.54,.77)
TENDON_M=mat("tendon_ligament",(.81,.79,.65),.66)
PHYS_M=mat("invisible_collision_proxy",(.2,.2,.8),.95)
VIS_M=mat("preview_floor",(.19,.215,.235),.83)
bpy.context.view_layer.objects.active=None

def place(obj,col):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    collections[col].objects.link(obj)
    return obj

def make_mesh(name,vertices,faces,col,material,meta=None,bone=None):
    mesh=bpy.data.meshes.new(name+"_Mesh")
    mesh.from_pydata([tuple(p) for p in vertices],[],faces)
    mesh.update(calc_edges=True)
    obj=bpy.data.objects.new(name,mesh)
    collections[col].objects.link(obj)
    obj.data.materials.append(material)
    if meta:
        for k,v in meta.items(): obj[k]=v
    if bone and bone in bones:
        vg=obj.vertex_groups.new(name=bone)
        vg.add(list(range(len(vertices))),1.0,'REPLACE')
        mod=obj.modifiers.new("Skinned_to_anatomy_"+bone,'ARMATURE')
        mod.object=arm
        mod.use_deform_preserve_volume=True
        obj.parent=arm
        obj['anatomy_bone']=bone
    for polygon in mesh.polygons:
        polygon.use_smooth=len(polygon.vertices)>3
    return obj

bones={}
def reg(name,head,tail,parent=None,group='skeletal',radius=.012):
    if name in bones: raise RuntimeError("Duplicate anatomy bone "+name)
    a=Vector(head);b=Vector(tail)
    if (b-a).length<.003:raise ValueError("Zero length bone "+name)
    bones[name]=dict(head=tuple(a),tail=tuple(b),parent=parent,group=group,radius=radius)

# Absolute primary 17 old names are intentionally maintained for eventual
# human-readable mapping to existing Life Simulator animation data.
reg('hips',(0,0,.945),(0,0,1.07),None,'pelvis',.072)
reg('spine',(0,0,1.07),(0,0,1.28),'hips','axial',.033)
reg('chest',(0,0,1.28),(0,0,1.45),'spine','axial',.036)
reg('neck',(0,0,1.45),(0,0,1.56),'chest','axial',.021)
reg('head',(0,0,1.56),(0,0,1.78),'neck','skull',.077)
reg('mandible',(0,-.02,1.62),(0,-.048,1.595),'head','skull',.013)

# Anatomical spine: five lumbar, twelve thoracic, seven cervical bodies.
for i in range(5):
    z=1.085+i*.041
    reg('vertebra_lumbar_%02d'%(i+1),(0,0,z),(0,0,z+.032),'spine','vertebra',.026-i*.0009)
for i in range(12):
    z=1.292+i*.0146
    reg('vertebra_thoracic_%02d'%(i+1),(0,0,z),(0,0,z+.011),'chest','vertebra',.024-i*.00035)
for i in range(7):
    z=1.478+i*.0135
    reg('vertebra_cervical_%02d'%(i+1),(0,0,z),(0,0,z+.009),'neck','vertebra',.016)

reg('sacrum',(0,-.003,.94),(0,0,1.045),'hips','pelvis',.035)
reg('coccyx',(0,-.019,.895),(0,-.004,.949),'hips','pelvis',.010)
for side,sign in [('l',1),('r',-1)]:
    reg('ilium_'+side,(sign*.058,0,1.045),(sign*.16,-.014,1.027),'hips','pelvis',.039)
    reg('pubis_'+side,(sign*.035,-.048,.938),(sign*.107,-.041,.988),'hips','pelvis',.018)
    reg('ischium_'+side,(sign*.082,.012,.896),(sign*.13,.016,.966),'hips','pelvis',.027)
    reg('clavicle_'+side,(sign*.075,-.018,1.424),(sign*.199,-.007,1.433),'chest','shoulder_girdle',.013)
    reg('scapula_'+side,(sign*.115,.052,1.425),(sign*.211,.056,1.295),'chest','shoulder_girdle',.026)
    reg('upper_arm_'+side,(sign*.19,0,1.42),(sign*.25,.01,1.16),'chest','long_bone',.026)
    reg('forearm_'+side,(sign*.25,.01,1.16),(sign*.29,0,.93),'upper_arm_'+side,'long_bone',.020)
    reg('radius_'+side,(sign*.258,-.008,1.155),(sign*.291,-.012,.940),'forearm_'+side,'long_bone',.012)
    reg('ulna_'+side,(sign*.248,.015,1.159),(sign*.287,.013,.936),'forearm_'+side,'long_bone',.012)
    reg('hand_'+side,(sign*.29,0,.93),(sign*.305,-.005,.80),'forearm_'+side,'hand',.014)
    for i in range(8):
        x=sign*(.299+(i%4)*.006)
        z=.819+(i//4)*.013
        reg('carpal_%02d_%s'%(i+1,side),(x,0,z),(x+sign*.008,-.002,z-.006),'hand_'+side,'hand',.0065)
    for finger in range(5):
        base_x=sign*(.309+(finger-2)*.012)
        base_z=.812
        if finger==0:
            a=Vector((sign*.321,-.003,.821))
            b=a+Vector((sign*.027,-.014,-.045))
        else:
            a=Vector((base_x,-.005,base_z))
            b=a+Vector((sign*.001,-.002,-(.038+[.0,.017,.013,.008,.006][finger])))
        reg('metacarpal_%d_%s'%(finger+1,side),a,b,'hand_'+side,'hand',.005)
        previous=b
        parent='metacarpal_%d_%s'%(finger+1,side)
        for segment in range(3 if finger>0 else 2):
            length=([.023,.018,.012] if finger>0 else [.026,.016])[segment]
            endpoint=previous+Vector((sign*.001,-.001,-length)) if finger>0 else previous+Vector((sign*.007,-.002,-length))
            name='finger_%d_%d_%s'%(finger+1,segment+1,side)
            reg(name,previous,endpoint,parent,'finger',.0038 if finger>0 else .0053)
            previous=endpoint; parent=name
    reg('thigh_'+side,(sign*.09,0,.93),(sign*.10,-.01,.50),'hips','long_bone',.041)
    reg('patella_'+side,(sign*.10,-.046,.52),(sign*.10,-.055,.48),'thigh_'+side,'long_bone',.021)
    reg('shin_'+side,(sign*.10,-.01,.50),(sign*.10,.02,.09),'thigh_'+side,'long_bone',.027)
    reg('fibula_'+side,(sign*.132,.02,.47),(sign*.124,.02,.115),'shin_'+side,'long_bone',.012)
    reg('foot_'+side,(sign*.10,.02,.09),(sign*.10,-.12,.025),'shin_'+side,'foot',.025)
    for j in range(7):
        x=sign*(.081+(j%3)*.014)
        y=-.015-(j//3)*.026
        reg('tarsal_%d_%s'%(j+1,side),(x,y,.05),(x+sign*.006,y-.009,.038),'foot_'+side,'foot',.010)
    for finger in range(5):
        x=sign*(.075+finger*.012)
        y=-.09
        end=(x,-.152+.007*finger,.032)
        reg('metatarsal_%d_%s'%(finger+1,side),(x,y,.044),end,'foot_'+side,'foot',.007)
        prev=Vector(end); parent='metatarsal_%d_%s'%(finger+1,side)
        for segment in range(2 if finger==0 else 3):
            ln=(.021-.0035*segment)*(1 if finger==0 else .78-.07*finger)
            nxt=prev+Vector((0,-ln,-.0007))
            name='toe_%d_%d_%s'%(finger+1,segment+1,side)
            reg(name,prev,nxt,parent,'toe',.0042 if finger==0 else .0033)
            parent=name;prev=nxt

for i in range(12):
    z=1.425-i*.033
    for side,sign in [('l',1),('r',-1)]:
        reg('rib_%02d_%s'%(i+1,side),(sign*.055,.016,z),(sign*(.138+(.022 if i<6 else -.005)), -.008, z-(.014 if i<7 else .020)), 'chest','ribs',.0063)
reg('sternum',(0,-.105,1.43),(0,-.107,1.22),'chest','sternum',.015)
reg('xiphoid',(0,-.112,1.23),(0,-.101,1.19),'sternum','sternum',.009)

# Check hierarchy before editing: internal secondary bones never hijack the
# existing 17-joint sim armature, which remains unchanged and separate.
for name,meta in bones.items():
    if meta['parent'] is not None and meta['parent'] not in bones:
        raise RuntimeError('Unknown parent '+name+' '+meta['parent'])
bpy.ops.object.armature_add()
arm=bpy.context.object
arm.name='Anatomy_Rig_V1'
arm.data.name='Anatomy_Rig_Data_V1'
place(arm,'Rig')
arm.show_in_front=True
arm.data.display_type='STICK'
arm['rig_role']='high-detail reference; nonreplacement for current 17-bone character'
bpy.ops.object.mode_set(mode='EDIT')
for old in list(arm.data.edit_bones):arm.data.edit_bones.remove(old)
for name,meta in bones.items():
    b=arm.data.edit_bones.new(name)
    b.head=meta['head'];b.tail=meta['tail']
    b.use_deform=meta['group'] not in ('ribs','sternum')
for name,meta in bones.items():
    if meta['parent']:
        arm.data.edit_bones[name].parent=arm.data.edit_bones[meta['parent']]
bpy.ops.object.mode_set(mode='OBJECT')

def oriented_tube(name,a,b,r,category,material,bone=None,metadata=None):
    a=Vector(a);b=Vector(b);direction=b-a
    length=direction.length
    if length<.0002:return None
    axis=direction/length
    ref=Vector((0,1,0)) if abs(axis.dot(Vector((0,1,0))))<.9 else Vector((1,0,0))
    U=axis.cross(ref).normalized();V=axis.cross(U).normalized()
    nside=12; nring=9
    profile=[(0.0,.84),(.025,1.06),(.09,1.20),(.19,.87),(.50,.62),(.81,.88),(.91,1.19),(.975,1.08),(1.,.82)]
    vertices=[];faces=[]
    for j,(t,w) in enumerate(profile):
        # bone bulges at epiphyses, narrow dense cortical shaft
        c=a+direction*t
        for k in range(nside):
            ang=math.tau*k/nside
            vertices.append(tuple(c+(U*math.cos(ang)+V*math.sin(ang))*r*w))
    faces.append(tuple(range(nside-1,-1,-1)))
    for j in range(nring-1):
        for k in range(nside):
            aa=j*nside+k;bb=j*nside+(k+1)%nside
            cc=(j+1)*nside+k;dd=(j+1)*nside+(k+1)%nside
            faces.append((aa,bb,dd,cc))
    faces.append(tuple((nring-1)*nside+k for k in range(nside)))
    obj=make_mesh(name,vertices,faces,category,material,metadata,bone)
    return obj

bone_objects={}
for name,meta in bones.items():
    bone_objects[name]=oriented_tube('Bone_'+name,meta['head'],meta['tail'],
        meta['radius'],'Bones',BONE_M,name,{'tissue':'cortical_spongy_proxy','density_kg_m3':1500.0,
        'youngs_modulus_gpa_reference':15.0,'poisson_reference':.30,'anatomical_role':meta['group']})

def sphere_obj(name,at,scale,col,material,meta=None,sub=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=sub,ring_count=max(6,int(sub*.65)),location=at)
    o=bpy.context.object
    o.name=name
    o.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    place(o,col)
    o.data.materials.append(material)
    if meta:
        for k,v in meta.items():o[k]=v
    for polygon in o.data.polygons: polygon.use_smooth=True
    return o

# Skull is a real cranium volume rather than an enormously thick line segment.
skull=sphere_obj('Bone_cranium',(.0,0,1.678),(.079,.077,.105),'Bones',BONE_M,
    {'tissue':'cortical_spongy_proxy','density_kg_m3':1500.0,'reference':'simplified cranium'},24)
for side,sgn in [('l',1),('r',-1)]:
    sphere_obj('Bone_orbit_%s'%side,(sgn*.038,-.061,1.671),(.030,.017,.030),
               'Bones',BONE_M,{'bone':'frontal_zygomatic_proxy'})
    oriented_tube('Bone_mandible_%s'%side,(sgn*.057,-.017,1.635),(sgn*.034,-.058,1.589),
            .009,'Bones',BONE_M,'mandible')
    oriented_tube('Bone_zygomatic_%s'%side,(sgn*.037,-.050,1.639),(sgn*.071,-.029,1.65),
            .011,'Bones',BONE_M,'head')

# Joint cartilage and intervertebral discs, physically separate and labeled.
joint_at={
 'atlanto_occipital':(0,0,1.565),
 'jaw':(0,-.030,1.612),
 'sternoclavicular_l':(.075,-.018,1.424),
 'sternoclavicular_r':(-.075,-.018,1.424),
}
for side,sgn in [('l',1),('r',-1)]:
    joint_at.update({
        'shoulder_'+side:(sgn*.201,.004,1.40),
        'elbow_'+side:(sgn*.25,.01,1.160),
        'wrist_'+side:(sgn*.29,0,.932),
        'hip_'+side:(sgn*.09,0,.930),
        'knee_'+side:(sgn*.10,-.01,.50),
        'ankle_'+side:(sgn*.10,.02,.09),
    })
    for j in range(1,11):
        z=1.425-(j-1)*.033
        oriented_tube('Cartilage_costal_%02d_%s'%(j,side),
           (sgn*.13,-.033,z-.020),(sgn*.032,-.102,z-.027),
            .005,'Cartilage',CART_M,None,
            {'tissue':'costal_cartilage','youngs_modulus_mpa_reference':8.0,
             'damping_reference':.08})
for i in range(1,5):
    z=1.085+i*.041
    sphere_obj('Cartilage_disc_L%d_L%d'%(i,i+1),(0,0,z+.019),
        (.026,.021,.006),'Cartilage',DISC_M,
        {'tissue':'fibrocartilage_disc','youngs_modulus_mpa_reference':6.0})
for i in range(1,12):
    z=1.292+i*.0146
    sphere_obj('Cartilage_disc_T%d_T%d'%(i,i+1),(0,0,z+.009),
        (.022,.019,.0035),'Cartilage',DISC_M,
        {'tissue':'fibrocartilage_disc','youngs_modulus_mpa_reference':5.0})
for i in range(1,7):
    z=1.478+i*.0135
    sphere_obj('Cartilage_disc_C%d_C%d'%(i,i+1),(0,0,z+.007),
        (.014,.014,.003),'Cartilage',DISC_M,
        {'tissue':'fibrocartilage_disc','youngs_modulus_mpa_reference':5.0})
for name,at in joint_at.items():
    size=.017 if name.startswith(('hip','shoulder')) else (.011 if name.startswith(('elbow','knee')) else .008)
    sphere_obj('Cartilage_joint_'+name,at,(size,size*.86,size*.68),
        'Cartilage',CART_M,{'tissue':'articular_hyaline_proxy',
        'youngs_modulus_mpa_reference':9.0,
        'friction_coefficient_reference':.08})
# Nonosseous cartilaginous structures (shape/reference only)
oriented_tube('Cartilage_nasal_septum',(0,-.076,1.68),(0,-.104,1.631),.007,
 'Cartilage',CART_M,None,{'tissue':'septal_cartilage'})
for side,sign in [('l',1),('r',-1)]:
    sphere_obj('Cartilage_auricle_'+side,(sign*.086,.008,1.664),(.009,.017,.032),
     'Cartilage',CART_M,{'tissue':'elastic_ear_cartilage'})

# Volumetric muscle belly proxies with tendon endpoints and metadata.
muscle_records=[]
def muscle(name,a,b,r,max_force,muscle_group,side='midline',tendon_fraction=.12):
    a,b=Vector(a),Vector(b)
    m=oriented_tube('Muscle_'+name,a,b,r,'Muscles',MUSCLE_M,None,{
        'tissue':'skeletal_muscle', 'muscle_name':name,
        'max_isometric_force_N_reference':float(max_force),
        'rest_length_m':float((b-a).length),
        'activation':0.0, 'optimal_fiber_length_m_reference':float((b-a).length*.72),
        'damping_Ns_m_reference':12.0,
        'group':muscle_group, 'side':side})
    for node,pt in [('origin',a),('insertion',b)]:
        sphere_obj('Tendon_'+name+'_'+node,pt,(r*.52,r*.52,r*.70),'Ligaments',
            TENDON_M,{'tissue':'tendon','muscle':name,'attachment':node})
    muscle_records.append(name)
for side,sgn in [('l',1),('r',-1)]:
    # Stabilizers and movers with rough origin/insertion, not exact anatomy.
    specs=[
       ('deltoid',(sgn*.18,0,1.425),(sgn*.243,0,1.28),.039,680,'shoulder'),
       ('supraspinatus',(sgn*.09,.05,1.415),(sgn*.23,0,1.395),.014,180,'rotator_cuff'),
       ('infraspinatus',(sgn*.105,.063,1.387),(sgn*.235,.022,1.375),.020,280,'rotator_cuff'),
       ('biceps_brachii',(sgn*.19,-.026,1.392),(sgn*.259,-.026,1.125),.022,900,'arm'),
       ('triceps_brachii',(sgn*.213,.026,1.39),(sgn*.255,.019,1.147),.024,850,'arm'),
       ('brachialis',(sgn*.217,-.005,1.28),(sgn*.247,-.01,1.128),.019,660,'arm'),
       ('brachioradialis',(sgn*.256,-.019,1.13),(sgn*.287,-.02,.957),.015,380,'forearm'),
       ('flexor_digitorum',(sgn*.251,.008,1.116),(sgn*.301,-.017,.828),.016,550,'forearm'),
       ('extensor_digitorum',(sgn*.252,.022,1.119),(sgn*.303,.009,.834),.013,430,'forearm'),
       ('pectoralis_major',(sgn*.041,-.101,1.363),(sgn*.234,-.044,1.327),.043,1250,'chest'),
       ('latissimus_dorsi',(sgn*.053,.071,1.195),(sgn*.214,.033,1.33),.032,1500,'back'),
       ('trapezius',(sgn*.023,.047,1.515),(sgn*.208,.034,1.408),.030,850,'back'),
       ('serratus_anterior',(sgn*.112,-.051,1.276),(sgn*.165,.056,1.391),.021,310,'thorax'),
       ('rectus_abdominis',(sgn*.043,-.095,1.295),(sgn*.046,-.098,1.017),.024,460,'abdomen'),
       ('external_oblique',(sgn*.143,-.04,1.26),(sgn*.10,-.04,.990),.027,520,'abdomen'),
       ('gluteus_maximus',(sgn*.103,.063,1.04),(sgn*.136,.031,.81),.055,1650,'hip'),
       ('gluteus_medius',(sgn*.153,.035,1.035),(sgn*.109,.022,.857),.027,910,'hip'),
       ('iliopsoas',(sgn*.059,-.041,1.157),(sgn*.102,-.031,.855),.020,680,'hip'),
       ('rectus_femoris',(sgn*.105,-.046,.906),(sgn*.112,-.047,.518),.043,1550,'thigh'),
       ('vastus_lateralis',(sgn*.144,-.003,.86),(sgn*.132,-.032,.521),.042,1760,'thigh'),
       ('vastus_medialis',(sgn*.062,-.026,.846),(sgn*.087,-.032,.519),.035,1410,'thigh'),
       ('biceps_femoris',(sgn*.126,.043,.913),(sgn*.138,.042,.51),.032,1100,'thigh'),
       ('semitendinosus',(sgn*.079,.045,.917),(sgn*.094,.046,.506),.029,1000,'thigh'),
       ('adductor_magnus',(sgn*.072,-.003,.891),(sgn*.115,-.006,.568),.033,1100,'thigh'),
       ('gastrocnemius',(sgn*.101,.044,.473),(sgn*.104,.047,.151),.037,1200,'calf'),
       ('soleus',(sgn*.103,.031,.369),(sgn*.108,.026,.142),.031,1050,'calf'),
       ('tibialis_anterior',(sgn*.108,-.023,.469),(sgn*.106,-.027,.119),.023,490,'calf'),
       ('fibularis_longus',(sgn*.135,.016,.428),(sgn*.131,-.001,.113),.016,270,'calf'),
    ]
    for n,a,b,r,F,g in specs:muscle(n+'_'+side,a,b,r,F,g,side)
muscle('sternocleidomastoid_l',(.033,-.019,1.565),(.073,-.037,1.425),.016,260,'neck','l')
muscle('sternocleidomastoid_r',(-.033,-.019,1.565),(-.073,-.037,1.425),.016,260,'neck','r')
muscle('erector_spinae_l',(.039,.046,1.05),(.041,.052,1.438),.028,950,'back','l')
muscle('erector_spinae_r',(-.039,.046,1.05),(-.041,.052,1.438),.028,950,'back','r')

# Bona fide Bullet rigid bodies: collision volumes are distinct hidden
# proxies to avoid double deforming the detailed bones. Properties are
# order-of-magnitude gameplay references, NOT measured anatomy.
physics_spec=[
('hips',10.0,.17),('spine',5.0,.13),('chest',12.0,.16),
('neck',1.1,.035),('head',4.5,.099)
]
for side in ['l','r']:
    physics_spec += [
      ('upper_arm_'+side,2.1,.045),('forearm_'+side,1.25,.032),
      ('hand_'+side,.45,.025),('thigh_'+side,7.0,.075),
      ('shin_'+side,3.4,.055),('foot_'+side,1.0,.045)]
physics_objects={}
for name,mass,r in physics_spec:
    info=bones[name]
    a=Vector(info['head']);b=Vector(info['tail'])
    vec=b-a
    midpoint=(a+b)/2
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,location=midpoint)
    o=bpy.context.object
    o.name='Physics_Rigid_'+name
    o.scale=(r,r,max(r,vec.length*.55))
    o.rotation_mode='QUATERNION'
    o.rotation_quaternion=Vector((0,0,1)).rotation_difference(vec.normalized())
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    place(o,'Physics')
    o.data.materials.append(PHYS_M)
    bpy.context.view_layer.objects.active=o
    bpy.ops.rigidbody.object_add()
    rb=o.rigid_body
    rb.type='PASSIVE' if name=='hips' else 'ACTIVE'
    rb.mass=mass
    rb.friction=.75
    rb.restitution=.04
    rb.linear_damping=.31
    rb.angular_damping=.48
    rb.collision_shape='CONVEX_HULL'
    rb.use_margin=True
    rb.collision_margin=.005
    o.hide_render=True
    o['sim_mass_kg']=mass
    o['ref_collision_radius_m']=r
    o['physics_model']='Bullet rigid proxy, detached from bone-skin visual'
    physics_objects[name]=o

joint_definitions={
  'spine':('hips','spine',(-.34,.34),(-.22,.22)),
  'chest':('spine','chest',(-.30,.30),(-.23,.23)),
  'neck':('chest','neck',(-.32,.38),(-.24,.24)),
  'head':('neck','head',(-.45,.45),(-.35,.35)),
}
for side in ['l','r']:
    joint_definitions.update({
      'shoulder_'+side:('chest','upper_arm_'+side,(-1.6,1.6),(-1.6,1.6)),
      'elbow_'+side:('upper_arm_'+side,'forearm_'+side,(0.,2.45),(-.03,.03)),
      'wrist_'+side:('forearm_'+side,'hand_'+side,(-1.05,1.05),(-.50,.50)),
      'hip_'+side:('hips','thigh_'+side,(-1.40,1.55),(-.90,.90)),
      'knee_'+side:('thigh_'+side,'shin_'+side,(0.0,2.20),(-.04,.04)),
      'ankle_'+side:('shin_'+side,'foot_'+side,(-.45,.65),(-.30,.30)),
    })
for joint,(parent,child,limits,side_range) in joint_definitions.items():
    pivot=Vector(bones[child]['head'])
    bpy.ops.object.empty_add(type='SPHERE',location=pivot)
    o=bpy.context.object
    o.name='Physics_Joint_'+joint
    place(o,'Joints')
    o.empty_display_size=.018
    bpy.context.view_layer.objects.active=o
    bpy.ops.rigidbody.constraint_add()
    c=o.rigid_body_constraint
    c.type='GENERIC'
    c.object1=physics_objects[parent]
    c.object2=physics_objects[child]
    for axis in ['x','y','z']:
        setattr(c,'use_limit_lin_'+axis,True)
        setattr(c,'limit_lin_'+axis+'_lower',0.)
        setattr(c,'limit_lin_'+axis+'_upper',0.)
    c.use_limit_ang_x=True
    c.limit_ang_x_lower=float(limits[0])
    c.limit_ang_x_upper=float(limits[1])
    c.use_limit_ang_y=True
    c.limit_ang_y_lower=float(side_range[0])
    c.limit_ang_y_upper=float(side_range[1])
    c.use_limit_ang_z=True
    c.limit_ang_z_lower=-.12
    c.limit_ang_z_upper=.12
    c.disable_collisions=True
    c.use_breaking=False
    o['parent_rigid']=parent
    o['child_rigid']=child
    o['max_bend_degrees_reference']=round(math.degrees(limits[1]),1)
    o['constraint_model']='Generic Euler angular limit; no muscle-actuated solver'
    o.hide_render=True

# Few nonrigid ligament spans, tethered reference tissues.
for joint,(parent,child,limits,side_range) in joint_definitions.items():
    center=Vector(bones[child]['head'])
    axis=Vector(bones[child]['tail'])-center
    if axis.length<.03:continue
    oriented_tube('Ligament_'+joint+'_lateral_a',center+Vector((.011,.009,.01)),
        center+axis.normalized()*.03+Vector((.012,.012,.01)),.0035,
        'Ligaments',TENDON_M,None,{'reference_stiffness_N_m':85000.0,'tissue':'ligament','joint':joint})

# Compatible neutral GLB + editable .blend, not an overwrite of character.blend.
camera_position=Vector((2.9,-5.4,2.1))
bpy.ops.object.camera_add(location=camera_position)
cam=bpy.context.object;cam.name='Anatomy_Camera'
place(cam,'Presentation')
direction=Vector((0,0,1.0))-cam.location
cam.rotation_euler=direction.to_track_quat('-Z','Y').to_euler()
cam.data.type='ORTHO'
cam.data.ortho_scale=2.35
scene.camera=cam
for name,xyz,power,size in [
    ('key',(1.9,-3.0,3.9),930,2.7),('fill',(-2.9,-.7,2.0),750,2.8),
    ('rim',(.6,2.0,3.0),1080,1.6)]:
    bpy.ops.object.light_add(type='AREA',location=xyz)
    o=bpy.context.object;o.name='Anatomy_Light_'+name
    place(o,'Presentation')
    o.data.energy=power;o.data.shape='DISK';o.data.size=size
    o.rotation_euler=(Vector((0,0,1.0))-o.location).to_track_quat('-Z','Y').to_euler()
# Bones and translucent muscle overlap, so render two passes separately.
for name in ['Bones','Cartilage','Ligaments','Muscles']:
    collections[name].hide_render=False
outfile=os.path.join(ASSET,'anatomy_osteology_overview.png')
collections['Muscles'].hide_render=True
scene.render.filepath=outfile
bpy.ops.render.render(write_still=True)
collections['Muscles'].hide_render=False
collections['Bones'].hide_render=True
collections['Cartilage'].hide_render=True
collections['Ligaments'].hide_render=True
scene.render.filepath=os.path.join(ASSET,'anatomy_musculature_overview.png')
bpy.ops.render.render(write_still=True)
for name in ['Bones','Cartilage','Ligaments']:
    collections[name].hide_render=False
collections['Muscles'].hide_render=True

# Make all display meshes skinned to bone rig, but no Bullet objects in GLB.
for group in ['Physics','Joints','Presentation']:
    collections[group].hide_render=True
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ASSET,'anatomy_skeleton_v1.blend'))
bpy.ops.object.select_all(action='DESELECT')
for col in ['Bones','Cartilage','Ligaments']:
    for obj in collections[col].objects:
        if obj.type in ('MESH','ARMATURE'):
            obj.select_set(True)
arm.select_set(True)
bpy.context.view_layer.objects.active=arm
try:
    bpy.ops.export_scene.gltf(filepath=os.path.join(ASSET,'anatomy_skeleton_v1.glb'),
        export_format='GLB',use_selection=True,export_apply=False,
        export_extras=True)
    glb_ok=True
except Exception as error:
    print('GLB_EXPORT_ERROR',repr(error))
    glb_ok=False

def mesh_summary():
    return dict(
        rig_bones=len(bones),
        legacy_bones=sum(name in bones for name in ['hips','spine','chest','neck','head']+
            [n+'_'+s for s in ['l','r'] for n in ['upper_arm','forearm','hand','thigh','shin','foot']]),
        anatomical_bone_meshes=len(collections['Bones'].objects),
        cartilage_meshes=len(collections['Cartilage'].objects),
        muscle_bundle_count=len(muscle_records),
        tendon_and_ligament_objects=len(collections['Ligaments'].objects),
        rigid_body_count=len(physics_objects),
        physics_joint_count=len(joint_definitions),
        total_proxy_mass_kg=round(sum(o.rigid_body.mass for o in physics_objects.values()),2),
        finger_phalanges=sum(n.startswith('finger_') for n in bones),
        toe_phalanges=sum(n.startswith('toe_') for n in bones),
        vertebrae=sum(n.startswith('vertebra_') for n in bones),
        ribs=sum(n.startswith('rib_') for n in bones),
        unit_scale='1 Blender m -> 1 Godot m',
        clinical_validation=False,
        coupled_with_live_gameplay_physics=False,
        model_stage='separate Blender anatomy reference and Bullet proxy scaffold',
        blb_path='anatomy_skeleton_v1.blend',
        glb_available=glb_ok,
    )
summary=mesh_summary()
with open(os.path.join(ASSET,'anatomy_manifest.json'),'w') as f:json.dump(summary,f,ensure_ascii=False,indent=2)

# Update the registered private Blender asset's file index so Library tools
# expose actual binaries and the edit-friendly source, rather than orphan files.
mpath=os.path.join(ASSET,'meta.json')
if os.path.exists(mpath):
    with open(mpath) as f:meta=json.load(f)
    meta['description']='Original modular anatomically inspired full-body skeletal rig, explicit cartilage and muscle belly meshes, Bullet rigid-body physics scaffold; distinct from gameplay 17-bone rig; approximate not clinical.'
    meta['tags']=['lifesim','anatomy','skeleton','joints','cartilage','muscles','physics','prototype']
    meta['version']='0.1.0'
    meta['updated']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    meta['files']=[]
    for fname in sorted(os.listdir(ASSET)):
        if fname=='meta.json' or not os.path.isfile(os.path.join(ASSET,fname)):continue
        with open(os.path.join(ASSET,fname),'rb') as f:b=f.read()
        meta['files'].append({'path':fname,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
    with open(mpath,'w') as f:json.dump(meta,f,ensure_ascii=False,indent=2)

assert summary['legacy_bones']==17
assert summary['rig_bones']>120
assert summary['cartilage_meshes']>30
assert summary['muscle_bundle_count']>=50
assert summary['rigid_body_count']==17
assert summary['physics_joint_count']>=16
assert summary['total_proxy_mass_kg']>50
assert all(name in bpy.data.objects for name in ['Anatomy_Rig_V1','Bone_cranium','Cartilage_joint_hip_l','Muscle_biceps_brachii_l','Physics_Joint_knee_l'])
assert os.path.getsize(os.path.join(ASSET,'anatomy_skeleton_v1.blend'))>100_000
print('ANATOMY_SUMMARY='+json.dumps(summary,ensure_ascii=False))
print('ASSET_DIRECTORY='+ASSET)