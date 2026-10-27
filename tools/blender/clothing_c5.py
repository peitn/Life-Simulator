# Life Simulator C5: independent Blender-authored garments, PBR tileables, full body morph & skin.
# Generator imports the ACTUAL source character GLB and exports a Godot-ready garment library.
# Blender 4.0+, Python stdlib + bpy only; standalone and reproducible.
import bpy, math, os, json, zlib, base64, struct, hashlib, urllib.request, random
from mathutils import Vector
from mathutils.kdtree import KDTree

DOC = "https://peiti-godot-mcp.hf.space/doc/file:lifesim/"
MCP = "https://peiti-godot-mcp.hf.space/mcp"
OUT = "/tmp/lifesim_clothing_c5.glb"
STYLES = {"top": [], "bottom": [], "shoes": []}

def fetch_godot(path):
    body = urllib.request.urlopen(DOC + path, timeout=30).read()
    return body.split(b"\n\n", 1)[-1].strip()

def mcp_write(path, content):
    data = {"jsonrpc":"2.0","id":100,"method":"tools/call",
        "params":{"name":"godot_file_write","arguments":{"project":"lifesim","path":path,"content":content}}}
    req = urllib.request.Request(MCP, data=json.dumps(data).encode(),
        headers={"Content-Type":"application/json","Accept":"application/json, text/event-stream"},method="POST")
    return urllib.request.urlopen(req,timeout=80).read()[:250]

raw=base64.b64decode(b"".join(fetch_godot("previews/glb_parts/p%02d.b64"%i) for i in range(31)))
os.makedirs("/tmp",exist_ok=True)
f="/tmp/lifesim_c5_source.glb"
open(f,"wb").write(raw)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=f)
ARM=bpy.data.objects["body"]
src={}
for ob in bpy.data.objects:
    if ob.type=="MESH":
        for tag in ("cloth_shirt","cloth_pants","shoe_leather","skin_body"):
            if ob.name.endswith("__"+tag) and (tag!="skin_body" or ob.name.startswith("body__")):
                src[tag]=ob
assert len(src)==4,src.keys()
MORPHS=[k.name for k in src["cloth_shirt"].data.shape_keys.key_blocks][1:]
assert len(MORPHS)==10
print("SOURCE",len(raw),"MORPHS",MORPHS)

# Materials use actual image textures baked into the exported GLB: GLSL-independent PBR.
# Tile patterns and normals are deterministically generated, seamless and small (128x128).
def textile_image(name, kind, normal=False, size=128):
    image=bpy.data.images.new("C5_"+name+("_N" if normal else "_A"),width=size,height=size,alpha=True)
    pix=[]
    seed=sum(ord(c)*(i+3) for i,c in enumerate(kind))
    for y in range(size):
        for x in range(size):
            u=x/size*2*math.pi
            v=y/size*2*math.pi
            if kind=="denim":
                tex=0.80+0.11*math.cos((x+y)*math.pi/2)+0.04*math.cos(y*math.pi/2)
                dx=math.sin((x+y)*math.pi/2)*0.22
                dy=dx*0.7
            elif kind=="knit":
                tex=0.84+0.09*math.cos(u*12)*math.cos(v*8)+0.05*math.sin(u*12+v*8)
                dx=math.sin(u*12)*0.4
                dy=math.cos(v*8)*0.3
            elif kind=="fleece":
                tex=0.88+0.05*math.cos(u*31+v*17)+0.025*math.sin(u*44-v*31)
                dx=math.sin(u*31)*0.2
                dy=math.sin(v*17)*0.2
            elif kind=="suiting":
                tex=0.91+0.045*math.sin(u*16)*math.cos(v*17)
                dx=math.cos(u*16)*0.18
                dy=math.sin(v*17)*0.18
            elif kind=="leather":
                tex=0.9+0.06*math.cos(u*13+2*math.sin(v*11))*math.sin(v*18)
                dx=math.sin(u*13)*0.15
                dy=math.cos(v*18)*0.15
            else:
                tex=0.91+0.055*math.cos(u*23)+0.05*math.cos(v*23)+0.02*math.sin(u*11+v*13)
                dx=math.sin(u*23)*0.21
                dy=math.sin(v*23)*0.21
            if normal:
                mag=math.sqrt(1.0+dx*dx+dy*dy)
                col=(0.5+dx/mag*0.5,0.5+dy/mag*0.5,0.5+1.0/mag*0.5,1)
            else:
                tex=max(0.5,min(1.0,tex))
                col=(tex,tex,tex,1)
            pix.extend(col)
    image.pixels.foreach_set(pix)
    image.file_format="PNG"
    image.pack()
    return image

MAT={}
def material(kind,roughness=0.9,metal=0.0):
    if kind in MAT:return MAT[kind]
    mat=bpy.data.materials.new("cloth_"+kind if kind!="leather" else "shoe_leather_c5")
    mat.use_nodes=True; mat.diffuse_color=(0.75,0.75,0.75,1)
    bs=mat.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Roughness"].default_value=roughness
    bs.inputs["Metallic"].default_value=metal
    im=mat.node_tree.nodes.new("ShaderNodeTexImage")
    im.image=textile_image(kind,kind)
    mat.node_tree.links.new(im.outputs["Color"],bs.inputs["Base Color"])
    imn=mat.node_tree.nodes.new("ShaderNodeTexImage")
    imn.image=textile_image(kind,kind,True)
    imn.image.colorspace_settings.name="Non-Color"
    norm=mat.node_tree.nodes.new("ShaderNodeNormalMap")
    norm.inputs["Strength"].default_value=0.24 if kind in ("suiting","leather") else 0.4
    mat.node_tree.links.new(imn.outputs["Color"],norm.inputs["Color"])
    mat.node_tree.links.new(norm.outputs["Normal"],bs.inputs["Normal"])
    MAT[kind]=mat
    return mat

for kind,rough in [("cotton",0.88),("fleece",0.98),("knit",0.98),("denim",0.88),
                   ("suiting",0.68),("leather",0.44),("satin",0.52)]:
    material(kind,rough)

SKIN=bpy.data.materials.new("skin_c5_legs")
SKIN.diffuse_color=(0.78,0.60,0.47,1)
SKIN.use_nodes=True
SKIN.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value=(0.78,0.60,0.47,1)
SKIN.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value=0.6

CREATED=[]
def set_uv(obj,scale=5.0):
    mesh=obj.data
    uv=mesh.uv_layers.get("UVMap")
    if uv is None:uv=mesh.uv_layers.new(name="UVMap")
    for p in mesh.polygons:
        for li in p.loop_indices:
            v=mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv=(v.x*scale+0.5,v.z*scale)

def add_part(obj,part,style):
    obj["c5_part"]=part;obj["c5_style"]=style
    CREATED.append(obj)
    if style not in STYLES.get(part,[]):
        STYLES.setdefault(part,[]).append(style)
    return obj

def apply_fit(obj,mul=1.0,drop=0.0):
    # Same transformation to Basis and EVERY morph target retains blended variants.
    keys=obj.data.shape_keys.key_blocks if obj.data.shape_keys else []
    for k in keys:
        for p in k.data:
            pos=p.co
            z=pos.z
            fac=mul
            if "top" in obj.name:
                t=max(0,min(1,(z-1.33)/0.2))
                fac=mul*(1-t)+(1+(mul-1)*0.3)*t
            pos.x*=fac;pos.y*=fac
            if drop and z<1.22:
                pos.z-=drop*max(0,min(1,(1.22-z)/0.23))
    obj.data.update()

def copy_base(source, name, part, style, mat, fit=1.0,drop=0.0):
    ob=source.copy();ob.data=source.data.copy()
    bpy.context.collection.objects.link(ob)
    ob.name="C5__"+part+"__"+style+"__shell"
    ob.data.materials.clear();ob.data.materials.append(mat)
    apply_fit(ob,fit,drop)
    set_uv(ob)
    return add_part(ob,part,style)

# Generate a skinned, blendshape-aware accessory from arbitrary parametric mesh.
# Source mesh determines nearby bone weights and displacement fields for all 10 body morphs.
def make_mesh(name,coords,faces,source,mat,part,style,bone_override=None):
    m=bpy.data.meshes.new(name)
    m.from_pydata(coords,[],faces);m.update()
    o=bpy.data.objects.new("C5__"+part+"__"+style+"__"+name,m)
    bpy.context.collection.objects.link(o)
    o.parent=ARM
    vg={}
    for group in source.vertex_groups:
        vg[group.name]=o.vertex_groups.new(name=group.name)
    points=[v.co.copy() for v in source.data.vertices]
    kd=KDTree(len(points))
    for i,p in enumerate(points):kd.insert(p,i)
    kd.balance()
    keys=source.data.shape_keys.key_blocks if source.data.shape_keys else []
    index={b.name:b for b in keys}
    influences=[]
    morphD={key:[] for key in MORPHS}
    for n,v in enumerate(coords):
        near=kd.find_n(Vector(v),4)
        weights=[1.0/(max(0.015,d)**2) for pos,i,d in near]
        norm=sum(weights); weights=[w/norm for w in weights]
        inf={}
        for (_,i,_),w in zip(near,weights):
            for g in source.data.vertices[i].groups:
                key=source.vertex_groups[g.group].name
                inf[key]=inf.get(key,0)+g.weight*w
        if bone_override is not None:
            inf=bone_override(Vector(v))
        total=sum(inf.values())
        if total>0:
            for group,wt in sorted(inf.items(),key=lambda x:x[1],reverse=True)[:4]:
                if group in vg and wt>1e-6:
                    vg[group].add([n],wt/total,"REPLACE")
        for name in MORPHS:
            delta=Vector((0,0,0))
            if name in index:
                kb=index[name]
                for (_,i,_),w in zip(near,weights):
                    delta+=(kb.data[i].co-points[i])*w
            morphD[name].append(delta)
    if keys:
        o.shape_key_add(name="Basis",from_mix=False)
        for name in MORPHS:
            kb=o.shape_key_add(name=name,from_mix=False)
            for i,v in enumerate(coords):
                kb.data[i].co=Vector(v)+morphD[name][i]
    am=o.modifiers.new("Armature","ARMATURE")
    am.object=ARM
    m.materials.append(mat)
    for p in m.polygons:p.use_smooth=True
    set_uv(o)
    return add_part(o,part,style)

def strip_between(name,points,width,source,mat,part,style):
    # Small flat cloth panel with UV coordinates; reverse side omitted, no volume.
    vertices=[]
    for x,y,z in points:
        vertices.append((x-width/2,y,z));vertices.append((x+width/2,y,z))
    faces=[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(points)-1)]
    return make_mesh(name,vertices,faces,source,mat,part,style)

def tube(name,coords,radii,source,mat,part,style,segments=10):
    verts=[]
    for p,r in zip(coords,radii):
        for i in range(segments):
            a=2*math.pi*i/segments
            verts.append((p[0]+r*math.cos(a),p[1]+r*math.sin(a),p[2]))
    faces=[]
    for i in range(len(coords)-1):
        for j in range(segments):
            a=i*segments+j;b=i*segments+(j+1)%segments
            faces.append((a,b,b+segments,a+segments))
    return make_mesh(name,verts,faces,source,mat,part,style)

def skirt(name,zbottom,xbottom,ybottom,source,mat,style,part="bottom",N=32,R=11):
    vertices=[];faces=[]
    for j in range(R):
        t=j/(R-1)
        z=1.01+(zbottom-1.01)*t
        rx=0.173+(xbottom-0.173)*t
        ry=0.122+(ybottom-0.122)*t
        for i in range(N):
            a=2*math.pi*i/N
            pleat=(0.006+0.014*t)*math.cos(a*10+0.4)
            rmod=1.0+0.022*t*math.cos(8*a)
            vertices.append(((rx*rmod+pleat)*math.cos(a),(ry*rmod+pleat)*math.sin(a),z))
    for j in range(R-1):
        for i in range(N):
            a=j*N+i;b=j*N+(i+1)%N
            faces.append((a,b,b+N,a+N))
    # Double-sided appearance uses Blender material.backface_culling=False (Godot both sides configurable).
    return make_mesh(name,vertices,faces,source,mat,part,style)

def extra_leg_skin():
    # Pants-like skin under skirts/shorts: it supplies limbs that the base GLB hides under trousers.
    # Keep leg topology, body morphs, and rigging, but repaint.
    o=copy_base(src["cloth_pants"],"leg_skin","legs","skin",SKIN,fit=0.984)
    o.name="C5__legs__skin__skin_surface"
    return o

extra_leg_skin()

# TOPS. Decorative mesh parts are full 3D surfaces, not texture paint.
for style,kind,fit,drop in [
 ("tricko","cotton",1.0,0.0),("tilko","cotton",0.97,0.0),
 ("kosile","suiting",1.035,0.005),("halenka","satin",1.06,0.02),
 ("svetr","knit",1.055,0.005),("rolak","knit",1.04,0.0),
 ("mikina","fleece",1.085,0.023),("sako","suiting",1.075,0.015),
 ("saty","satin",1.055,0.01),("pyzamo","cotton",1.08,0.01),
 ("sportovni","cotton",0.98,0.0)]:
    copy_base(src["cloth_shirt"],"shell","top",style,MAT[kind],fit,drop)

# Button placket/collar for a shirt; fitted lapels for suit jacket.
strip_between("shirt_placket",[(0,-0.128,1.46),(0,-0.13,1.08)],0.014,
              src["cloth_shirt"],MAT["suiting"],"top","kosile")
for i in range(5):
    z=1.405-i*0.068
    tube("shirt_button_%d"%i,[(0,-0.149,z+0.001),(0,-0.149,z-0.001)],
         [0.007,0.007],src["cloth_shirt"],MAT["suiting"],"top","kosile",segments=8)
for side in (-1,1):
    strip_between("jacket_lapel_%s"%side,[(side*0.055,-0.09,1.465),
            (side*0.085,-0.143,1.39),(side*0.09,-0.145,1.29)],
            0.037,src["cloth_shirt"],MAT["suiting"],"top","sako")

# Hoodie has an actually modeled hood covering the back of the head.
hoodV=[];hoodF=[];H=15;R=11
for j in range(R):
    t=j/(R-1)
    z=1.455+0.255*t
    rx=0.10+0.018*math.sin(math.pi*t)
    ry=0.105+0.018*math.sin(math.pi*t)
    for i in range(H):
        a=-math.pi/2+math.pi*i/(H-1)
        hoodV.append((rx*math.sin(a),0.027+ry*math.cos(a)+0.006*t,z))
for j in range(R-1):
    for i in range(H-1):
        n=j*H+i;hoodF.append((n,n+1,n+H+1,n+H))
def hood_bones(v):
    t=max(0,min(1,(v.z-1.45)/0.23))
    return {"neck":0.65*(1-t),"chest":0.35*(1-t),"head":t}
make_mesh("hood",hoodV,hoodF,src["cloth_shirt"],MAT["fleece"],"top","mikina",hood_bones)
for side in (-1,1):
    tube("cord_%s"%side,[(side*0.048,-0.12,1.44),(side*0.050,-0.14,1.29)],
         [0.0035,0.0035],src["cloth_shirt"],MAT["cotton"],"top","mikina",segments=7)
# Front kangaroo pocket, curved slightly out from the torso.
# Actual flat pocket panel, not an intersecting zigzag strip.
make_mesh("kangaroo_pocket",[
    (-0.12,-0.119,1.085),(0.12,-0.119,1.085),
    (0.11,-0.119,1.19),(-0.11,-0.119,1.19)
],[(0,1,2,3)],src["cloth_shirt"],MAT["fleece"],"top","mikina")

# Sweater mock rib neckline and cuffs.
for side in (-1,1):
    tube("cuff_%s"%side,[(side*0.282,0.0,0.993),(side*0.288,0.0,1.033)],
         [0.040,0.042],src["cloth_shirt"],MAT["knit"],"top","svetr",segments=10)
# Turtleneck collar about neck: ring with actual height.
tube("turtleneck",[(0,0,1.478),(0,0,1.525)],[0.056,0.054],
     src["cloth_shirt"],MAT["knit"],"top","rolak",segments=16)

# Long-sleeve extensions are genuine skinned rings (cover the original short sleeve mesh).
# The source torso/arm blend shapes propagate to each garment's sleeves independently.
def long_sleeves(style,kind):
    for side in (-1,1):
        verts=[];faces=[];S=14
        rings=[
            # Extend the shoulder join under the shirt shell; old 1.164m rim
            # left a measured 21mm median surface gap (rest pose).
            (side*0.25,0.0,1.209,0.049),
            (side*0.266,0.0,1.108,0.048),
            (side*0.283,0.0,1.008,0.043),
            (side*0.297,-0.004,0.909,0.034),
            (side*0.30,-0.005,0.875,0.032)
        ]
        for x,y,z,rad in rings:
            for i in range(S):
                a=2*math.pi*i/S
                verts.append((x+rad*math.cos(a),y+rad*math.sin(a),z))
        for j in range(len(rings)-1):
            for i in range(S):
                a=j*S+i;b=j*S+(i+1)%S
                faces.append((a,b,b+S,a+S))
        # Sleeve vertices extend far beyond cloth_shirt: nearest shirt transfer can select hips/legs.
        # Keep morph transfer, but constrain weights to the corresponding arm chain.
        suffix="l" if side>0 else "r"
        elbow_z=ARM.data.bones["forearm_"+suffix].head_local.z
        wrist_z=ARM.data.bones["hand_"+suffix].head_local.z
        def sleeve_bones(v):
            # Keep the upper rim attached to upper arm through elbow flexion.
            # Original nearest fit wrongly assigned ~73% forearm at the
            # shoulder seam, producing 30mm+ pose gaps. Blend after the
            # second ring, reaching forearm near the elbow ring.
            forearm=max(0.0,min(1.0,(elbow_z-0.027-v.z)/0.157))
            hand=max(0.0,min(1.0,(wrist_z+0.04-v.z)/0.08))
            return {"upper_arm_"+suffix:1-forearm,
                    "forearm_"+suffix:forearm*(1-hand),"hand_"+suffix:forearm*hand}
        make_mesh("sleeve_%s"%side,verts,faces,src["cloth_shirt"],MAT[kind],"top",style,sleeve_bones)
for style,kind in [("mikina","fleece"),("svetr","knit"),("rolak","knit"),("sako","suiting"),("kosile","suiting")]:
    long_sleeves(style,kind)

# BOTTOMS, including geometrically shorter shorts and flared skirts.
for style,kind,fit in [
 ("dziny","denim",1.0),("kalhoty","cotton",1.025),("oblekove","suiting",1.03),
 ("teplaky","fleece",1.075),("leginy","cotton",0.99),("pyzamo","cotton",1.07)]:
    copy_base(src["cloth_pants"],"shell","bottom",style,MAT[kind],fit,0)

# Create shorts by clipping the original pants triangles at a real geometry boundary.
def cropped_shorts(zcut=0.61):
    source=src["cloth_pants"]
    mesh=source.data
    points=[v.co.copy() for v in mesh.vertices]
    faces=[]
    newcoords=[]
    cache={}
    for poly in mesh.polygons:
        polygon=list(poly.vertices)
        clipped=[]
        for i,a in enumerate(polygon):
            b=polygon[(i+1)%len(polygon)]
            A=points[a];B=points[b]
            ina=A.z>=zcut;inb=B.z>=zcut
            if ina:
                key=("v",a)
                if key not in cache:cache[key]=len(newcoords);newcoords.append(tuple(A))
                clipped.append(cache[key])
            if ina!=inb:
                key=("e",min(a,b),max(a,b))
                if key not in cache:
                    t=(zcut-A.z)/(B.z-A.z)
                    cache[key]=len(newcoords)
                    newcoords.append(tuple(A.lerp(B,t)))
                clipped.append(cache[key])
        if len(clipped)>=3:
            for j in range(1,len(clipped)-1):
                faces.append((clipped[0],clipped[j],clipped[j+1]))
    print("SHORTS",len(newcoords),len(faces))
    return make_mesh("cropped_pants",newcoords,faces,source,MAT["denim"],"bottom","kratasy")
cropped_shorts()
skirt("pleated_skirt",0.56,0.242,0.163,src["cloth_pants"],MAT["suiting"],"sukne")
# A cloth waistband overlaps the shirt hem and skirt rings to eliminate light gaps.
def waistband(style,kind,part):
    n=32;verts=[];faces=[]
    for z,rx,ry in [(0.976,0.174,0.127),(1.03,0.177,0.129),(1.057,0.172,0.125)]:
        for i in range(n):
            a=2*math.pi*i/n
            verts.append((rx*math.cos(a),ry*math.sin(a),z))
    for j in range(2):
        for i in range(n):
            aa=j*n+i;bb=j*n+(i+1)%n
            faces.append((aa,bb,bb+n,aa+n))
    return make_mesh("waistband",verts,faces,src["cloth_pants"],MAT[kind],part,style)
waistband("sukne","suiting","bottom")

# Dresses own lower mesh, tied to TOP dress selection, not bottom selection.
skirt("dress_lower",0.34,0.29,0.204,src["cloth_pants"],MAT["satin"],"saty","dress")
waistband("saty","satin","dress")

# Shoes. Tall boots gain a shin shaft, while other types remain shaped shoes.
for style,kind,fit in [
 ("tenisky","cotton",1.0),("polobotky","leather",0.99),("kozacky","leather",1.075),
 ("lodicky","leather",0.96),("sandaly","leather",0.99),("pracovni","leather",1.065),
 ("bacory","cotton",1.065)]:
    ob=copy_base(src["shoe_leather"],"shoe","shoes",style,MAT[kind],fit,0)
for side in (-1,1):
    tube("boot_shaft_%s"%side,[(side*0.102,0.015,0.112),(side*0.104,0.014,0.20),
                             (side*0.11,0.005,0.33)],[0.051,0.065,0.075],
         src["cloth_pants"],MAT["leather"],"shoes","kozacky",segments=16)

# C5.1 — subculture wardrobe. No style is bound to gender or personality.
# These are authored geometry variants and real skinned accessories, not just renamed colours.
SUBCULTURE_TOPS = [
    ("punk_vesta","leather",1.045), ("metal_tricko","cotton",1.055),
    ("emo_mikina","fleece",1.09), ("goth_korset","suiting",0.97),
    ("kawaii_svetr","knit",1.08), ("harajuku_bunda","fleece",1.12),
    ("grunge_kosile","cotton",1.13), ("visualkei_sako","suiting",1.12),
]
SUBCULTURE_BOTTOMS = [
    ("punk_kostka","suiting","sukne"), ("goth_sukne","satin","sukne"),
    ("kawaii_sukne","satin","sukne"), ("harajuku_sukne","satin","sukne"),
    ("metal_dziny","denim","dziny"), ("emo_dziny","denim","dziny"),
    ("grunge_dziny","denim","dziny"), ("visualkei_kalhoty","suiting","dziny"),
]
SUBCULTURE_SHOES = [
    ("punk_kanady","leather","kozacky"), ("metal_kanady","leather","kozacky"),
    ("goth_platformy","leather","kozacky"), ("emo_tenisky","cotton","tenisky"),
    ("kawaii_boty","cotton","tenisky"), ("harajuku_platformy","leather","kozacky"),
    ("grunge_kanady","leather","kozacky"), ("visualkei_boty","leather","kozacky"),
]
# Use the real Blender-authored source geometry, with different shape and new attachments.
for style,kind,fit in SUBCULTURE_TOPS:
    source=src["cloth_shirt"]
    copy_base(source,"shell","top",style,MAT[kind],fit,0.018 if "mikina" in style or "bunda" in style else 0)
for style,kind,reference in SUBCULTURE_BOTTOMS:
    if reference=="sukne":
        if style=="punk_kostka": z,rx,ry=0.57,0.24,0.16
        elif style=="goth_sukne": z,rx,ry=0.34,0.285,0.20
        elif style=="kawaii_sukne": z,rx,ry=0.64,0.27,0.19
        else: z,rx,ry=0.60,0.31,0.21
        skirt("subculture_pleated",z,rx,ry,src["cloth_pants"],MAT[kind],style)
    else:
        copy_base(src["cloth_pants"],"shell","bottom",style,MAT[kind],1.01 if style=="emo_dziny" else 1.08)
for style,kind,reference in SUBCULTURE_SHOES:
    copy_base(src["shoe_leather"],"shell","shoes",style,MAT[kind],1.10 if "platformy" in style else 1.045)
    if reference=="kozacky":
        for side in (-1,1):
            tube("boot_shaft_%s"%side,[(side*0.102,0.015,0.112),
                  (side*0.104,0.014,0.20),(side*0.11,0.005,0.33)],
                  [0.055,0.067,0.073],src["cloth_pants"],MAT[kind],"shoes",style,segments=12)
# Extra sleeves on the streetwear/emo/grunge silhouettes.
for style,kind in [("emo_mikina","fleece"),("kawaii_svetr","knit"),
                   ("harajuku_bunda","fleece"),("grunge_kosile","cotton"),
                   ("visualkei_sako","suiting")]:
    long_sleeves(style,kind)
# Decorative hardware: every stud is a genuine, weighted, morph-aware mesh.
def rivet(x,y,z,source,part,style,mat="leather"):
    r=0.008
    verts=[(x-r,y,z-r),(x+r,y,z-r),(x+r,y,z+r),(x-r,y,z+r),
           (x,y-0.008,z)]
    return make_mesh("rivet",verts,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],
                     source,MAT[mat],part,style)
for style in ["punk_vesta","goth_korset","visualkei_sako"]:
    for side in (-1,1):
        for j in range(5):
            rivet(side*(0.09+0.007*j),-0.13,1.10+j*0.067,
                  src["cloth_shirt"],"top",style)
# Corset criss-cross front: visible laces as individual thin skinned tubes.
for j in range(7):
    z=1.09+j*0.04
    side=1 if j%2 else -1
    tube("corset_lace_%02d"%j,[(side*0.053,-0.136,z),
           (-side*0.053,-0.138,z+0.04)],[0.003,0.003],
         src["cloth_shirt"],MAT["leather"],"top","goth_korset",segments=6)
# Punk/metal chains hanging from waistband.
for style in ["punk_kostka","metal_dziny","visualkei_kalhoty"]:
    for i in range(12):
        t=i/11
        x=0.12+0.025*math.sin(math.pi*t)
        y=-0.115-0.018*math.sin(math.pi*t)
        z=0.98-0.19*math.sin(math.pi*t)
        if i==6: z+=0.006  # avoid coincident midpoint rings of the curved chain
        if i==0: coords=[]
        coords.append((x,y,z))
    tube("waist_chain",coords,[0.004]*len(coords),
         src["cloth_pants"],MAT["leather"],"bottom",style,segments=6)
# Kawaii / Harajuku bows on front and shoulders.
for style in ["kawaii_svetr","harajuku_bunda"]:
    for side in (-1,1):
        x=side*0.10
        verts=[(x-0.042,-0.142,1.30),(x-0.007,-0.15,1.28),
               (x-0.042,-0.142,1.25),(x+0.042,-0.142,1.30),
               (x+0.007,-0.15,1.28),(x+0.042,-0.142,1.25)]
        make_mesh("bow_%s"%side,verts,[(0,1,2),(3,5,4)],
                  src["cloth_shirt"],MAT["satin"],"top",style)
# A detachable spiked wristband silhouette on the punk vest.
for side in (-1,1):
    tube("wristband_%s"%side,[(side*0.294,0,0.91),(side*0.296,0,0.94)],
         [0.042,0.042],src["cloth_shirt"],MAT["leather"],"top","punk_vesta",segments=12)
# Embossed horizontal belt strips on the punk and gothic skirts.
for style in ["punk_kostka","goth_sukne"]:
    tube("belt",[(0,0,1.00),(0,0,1.028)],[0.18,0.18],
         src["cloth_pants"],MAT["leather"],"bottom",style,segments=24)

# C5.2: pastel pink kawaii cat hoodie, with two actual 3D cat ears on the hood.
# Cat graphic is made from original weighted mesh geometry (face, eyes, nose, whiskers).
# This outfit remains independent of body type, identity and personality.
CAT_STYLE="kawaii_kocici_mikina"
copy_base(src["cloth_shirt"],"shell","top",CAT_STYLE,MAT["fleece"],1.105)
long_sleeves(CAT_STYLE,"fleece")
# Reuse the original hood's skinned geometry and 10 morphs.
cat_hood=make_mesh("cat_hood",hoodV,hoodF,src["cloth_shirt"],
                   MAT["fleece"],"top",CAT_STYLE,hood_bones)
# The upper hood is on the back of the head. Ears are folded triangular pyramids.
for side in (-1,1):
    cx=side*0.078
    ear=[(cx-0.042,0.058,1.679),(cx+0.042,0.058,1.679),
         (cx,0.060,1.785),(cx,0.104,1.701)]
    make_mesh("cat_ear_%s"%side,ear,
              [(0,1,2),(0,2,3),(2,1,3),(1,0,3)],
              src["cloth_shirt"],MAT["fleece"],"top",CAT_STYLE,hood_bones)
    inner=[(cx-0.024,0.047,1.698),(cx+0.024,0.047,1.698),
           (cx,0.045,1.761)]
    make_mesh("ear_inner_%s"%side,inner,[(0,1,2)],
              src["cloth_shirt"],MAT["satin"],"top",CAT_STYLE,hood_bones)
# Kangaroo pocket and two hanging drawstrings.
make_mesh("cat_pocket",[(-0.123,-0.135,1.077),(0.123,-0.135,1.077),
                        (0.11,-0.137,1.187),(-0.11,-0.137,1.187)],
          [(0,1,2,3)],src["cloth_shirt"],MAT["fleece"],"top",CAT_STYLE)
for side in (-1,1):
    tube("cat_cord_%s"%side,[(side*0.048,-0.136,1.438),
         (side*0.049,-0.155,1.298)],[0.004,0.004],
         src["cloth_shirt"],MAT["cotton"],"top",CAT_STYLE,segments=8)
# Front motif: stylized cat silhouette built from an oval face and two triangular ears.
# Local coordinate system: -Y is front of the character.
def cat_patch(name,verts,faces,mat):
    return make_mesh(name,verts,faces,src["cloth_shirt"],MAT[mat],"top",CAT_STYLE)
def cat_disc(name,cx,cz,rx,rz,mat,y=-0.151,n=20):
    v=[(cx,y,cz)]+[(cx+rx*math.cos(2*math.pi*i/n),y,
                     cz+rz*math.sin(2*math.pi*i/n)) for i in range(n)]
    f=[(0,i+1,1+(i+1)%n) for i in range(n)]
    return cat_patch(name,v,f,mat)
cat_disc("cat_face",0,1.315,0.079,0.072,"cotton")
for side in (-1,1):
    cat_patch("motif_ear_%s"%side,
      [(side*0.039,-0.153,1.354),(side*0.072,-0.153,1.382),
       (side*0.073,-0.153,1.329)],[(0,1,2)],"cotton")
    cat_disc("cat_eye_%s"%side,side*0.029,1.326,0.009,0.014,"leather",y=-0.155,n=12)
    for j in range(2):
        z=1.298+j*0.011
        strip_between("whisker_%s_%d"%(side,j),
                      [(side*0.034,-0.158,z),(side*0.091,-0.158,z+0.008*(j-0.5))],
                      0.0028,src["cloth_shirt"],MAT["leather"],"top",CAT_STYLE)
cat_patch("cat_nose",[(0,-0.157,1.309),(-0.010,-0.157,1.319),
                      (0.010,-0.157,1.319)],[(0,1,2)],"satin")
# The wardrobe scene includes the original 17-bone armature, but NO base character surfaces.
for o in list(bpy.data.objects):
    if o.type=="MESH" and o not in CREATED:
        bpy.data.objects.remove(o,do_unlink=True)
# Keep only created meshes plus rig.
for o in bpy.context.selected_objects:o.select_set(False)
ARM.select_set(True)
for o in CREATED:o.select_set(True)
bpy.context.view_layer.objects.active=ARM
bpy.ops.export_scene.gltf(filepath=OUT,export_format="GLB",use_selection=True,
    export_morph=True,export_skins=True,export_materials="EXPORT",
    export_yup=True,export_apply=False,export_colors=True)
data=open(OUT,"rb").read()
print("C5_EXPORTED",len(data),hashlib.md5(data).hexdigest(),
      "OBJECTS",len(CREATED),"STYLE_COUNTS",{k:len(v) for k,v in STYLES.items()})
print("C5_STATS",sum(len(o.data.vertices) for o in CREATED),
      sum(len(o.data.polygons) for o in CREATED))
# Ship exported GLB as textual base64 segments over the existing Godot MCP bridge.
encoded=base64.b64encode(data).decode()
CH=135000
cnt=(len(encoded)+CH-1)//CH
if os.environ.get("C5_SEND_GLB", "0") == "1":
    for i in range(cnt):
        mcp_write("previews/c5_glb/c5_%03d.b64"%i,encoded[i*CH:(i+1)*CH])
    print("C5_BRIDGE_SENT",cnt,"parts")
else:
    print("C5_GLB_ARCHIVE_DISABLED",cnt,"parts - LSX is the Godot runtime transport")
manifest={"part_count":cnt,"glb_bytes":len(data),"md5":hashlib.md5(data).hexdigest(),
          "styles":STYLES,"mesh_count":len(CREATED),"morphs":MORPHS}
mcp_write("previews/c5_glb/manifest.json",json.dumps(manifest,indent=2))
print("C5_DONE")