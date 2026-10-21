
import bpy, bmesh, struct, json, zlib, base64, math, os, binascii
from mathutils import Vector, Matrix
OUT = '/tmp/lifesim_lsx'
os.makedirs(OUT, exist_ok=True)

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()

MATS = {}
def mat(name, color, rough=0.8, metal=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (color[0], color[1], color[2], 1.0)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    MATS[name] = {'name': name, 'color': [round(c, 4) for c in color], 'rough': rough, 'metal': metal}
    return m

def set_mat(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)

def apply_mods(o):
    bpy.context.view_layer.objects.active = o
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    o.select_set(True)
    for md in list(o.modifiers):
        if md.type == 'ARMATURE':
            continue
        bpy.ops.object.modifier_apply(modifier=md.name)

def rbox(name, size, loc, m, bevel=0.02, seg=3, rot=(0, 0, 0)):
    """Kvádr se zaoblenými hranami (bevel) – size = celé rozměry v Blender souřadnicích (x, y, z)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        b = o.modifiers.new('bev', 'BEVEL')
        b.width = min(bevel, min(size) * 0.49)
        b.segments = seg
        b.limit_method = 'NONE'
        b.harden_normals = False
    set_mat(o, m)
    apply_mods(o)
    bpy.ops.object.shade_smooth()
    o.data.use_auto_smooth = True
    o.data.auto_smooth_angle = math.radians(40)
    return o

def cyl(name, r, h, loc, m, verts=16, rot=(0, 0, 0), bevel=0.0):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    if bevel > 0:
        b = o.modifiers.new('bev', 'BEVEL')
        b.width = bevel
        b.segments = 2
    set_mat(o, m)
    apply_mods(o)
    bpy.ops.object.shade_smooth()
    o.data.use_auto_smooth = True
    o.data.auto_smooth_angle = math.radians(40)
    return o

def join(objs, name):
    for ob in bpy.context.selected_objects:
        ob.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o

def g(v):
    """Blender (Z nahoru, předek -Y) -> Godot (Y nahoru, předek +Z)."""
    return (v[0], v[2], -v[1])

def _oct(n):
    l1 = abs(n[0]) + abs(n[1]) + abs(n[2])
    if l1 < 1e-9:
        return (0, 127)
    x, y, z = n[0] / l1, n[1] / l1, n[2] / l1
    if z < 0:
        x, y = (1 - abs(y)) * (1 if x >= 0 else -1), (1 - abs(x)) * (1 if y >= 0 else -1)
    return (max(-127, min(127, round(x * 127))), max(-127, min(127, round(y * 127))))

def _delta16(vals):
    """Rozdíly sousedních hodnot jako uint16 (mod 65536), planárně: nejdřív dolní, pak horní bajty."""
    out = []
    prev = 0
    for v in vals:
        out.append((v - prev) & 0xFFFF)
        prev = v
    return bytes(x & 255 for x in out) + bytes(x >> 8 for x in out)

def _hiwater16(idx):
    """Kódování „vysoké hladiny“: 0 = další nový vrchol, k > 0 = odkaz o k zpět od další nové hodnoty."""
    out = []
    nxt = 0
    for i in idx:
        if i == nxt:
            out.append(0)
            nxt += 1
        else:
            out.append(nxt - i)
    return bytes(x & 255 for x in out) + bytes(x >> 8 for x in out)

QBITS = 12
MORPH_MIN = 1e-5      # morf s menší maximální výchylkou se u části neukládá (= nulový)
MORPH_EPS = 0.0005    # 0,5 mm – menší výchylka vrcholu se uloží jako nula
MAX_MORPHS = 32       # limit formátu (kontroluje i dekodér)
def _quad_part(o, blob, bidx, bone_order, morph_names):
    """Celý objekt jako JEDNA část čtyřúhelníků (řídicí síť pro Catmull-Clark v importu), materiál po plochách.
    Bez normál – dekodér je po dělení dopočítá (pro základ i každý morf)."""
    me = o.data
    M = o.matrix_world
    M3 = M.to_3x3()
    F = [list(p.vertices) for p in me.polygons]
    if any(len(f) != 4 for f in F):
        raise RuntimeError('quad part needs pure quads: %s' % o.name)
    order = {}
    for f in F:
        for v in f:
            if v not in order:
                order[v] = len(order)
    inv = [0] * len(order)
    for v, i in order.items():
        inv[i] = v
    if len(inv) > 65535:
        raise RuntimeError('part too big: %s' % o.name)
    P = [g(M @ me.vertices[v].co) for v in inv]
    IDX = [order[v] for f in F for v in f]          # pořadí Blenderu (CCW); dekodér otočí
    mats = [s.material.name if s.material else '' for s in o.material_slots]
    part = {'qb': QBITS, 'prim': 'quad', 'subdiv': int(o.get('lsx_subdiv', 1)), 'name': o.name,
            'group': o.get('lsx_group', ''), 'mat': mats[0] if mats else '', 'mats': mats,
            'nv': len(P), 'ni': len(IDX)}
    mn = [min(p[i] for p in P) for i in range(3)]
    mx = [max(p[i] for p in P) for i in range(3)]
    part['min'] = [round(x, 5) for x in mn]; part['max'] = [round(x, 5) for x in mx]
    ext = [max(mx[i] - mn[i], 1e-6) for i in range(3)]
    QMAX = (1 << QBITS) - 1
    def put(key, data):
        part[key] = [len(blob), len(data)]
        blob.extend(data)
    Q = [[round((p[i] - mn[i]) / ext[i] * QMAX) for i in range(3)] for p in P]
    put('pos', b''.join(_delta16([q[i] for q in Q]) for i in range(3)))
    put('idx', _hiwater16(IDX))
    put('fmat', bytes(p.material_index for p in me.polygons))
    if bone_order:
        gname = {vg.index: vg.name for vg in o.vertex_groups}
        BI = []; BW = []
        for v in inv:
            ws = []
            for ge in me.vertices[v].groups:
                bn = gname.get(ge.group)
                if bn in bidx and ge.weight > 0.001:
                    ws.append((ge.weight, bidx[bn]))
            ws.sort(reverse=True)
            ws = ws[:2] or [(1.0, 0)]
            if len(ws) == 1:
                ws.append((0.0, ws[0][1]))
            s = ws[0][0] + ws[1][0]
            BI.append((ws[0][1], ws[1][1]))
            BW.append(max(0, min(255, round(ws[0][0] / s * 255))))
        put('bi', bytes(b[0] for b in BI) + bytes(b[1] for b in BI))
        put('bw', bytes(BW))
    if me.shape_keys is not None:
        basis = me.shape_keys.key_blocks[0]
        kbs = {kb.name: kb for kb in me.shape_keys.key_blocks[1:]}
        mlist = []
        for mname in morph_names:
            kb = kbs.get(mname)
            if kb is None:
                continue
            D = [g(M3 @ (kb.data[v].co - basis.data[v].co)) for v in inv]
            sc = max(max(abs(c) for c in d) for d in D)
            if sc < MORPH_MIN:
                continue
            qd = [[0, 0, 0] if (d[0]*d[0]+d[1]*d[1]+d[2]*d[2]) < MORPH_EPS * MORPH_EPS else [max(-127, min(127, round(c / sc * 127))) for c in d] for d in D]
            off = len(blob)
            for c in range(3):
                prev = 0
                for q in qd:
                    blob.append((q[c] - prev) & 255)
                    prev = q[c]
            mlist.append([mname, round(sc, 6), off, len(qd) * 3])
        if mlist:
            part['morphs'] = mlist
    return part

def export_lsx(name, objs, arm=None, bone_order=None, meta=None, morph_bones=None):
    """Kompaktní formát LSX: [u32 délka JSON][JSON][binární bloby], celé zlib + base64.
    Pozice uint16 v AABB části, normály oktaedricky 2×int8, indexy uint16 (pořadí Godot = po směru hodinových ručiček),
    kosti max 2 na vrchol (2×uint8 index + uint8 váha první kosti).
    v4: morph targety ze shape keys (relativní k Basis) – na část [jméno, měřítko, offset, délka], výchylky
    3×int8 planárně (round(d / měřítko * 127)), delta-kódované mezi sousedními vrcholy (mod 256); hlavička 'morphs' = globální pořadí, 'morph_bones' = posuny hlav kostí
    (Godot osy) při plné váze morfu – aby klouby seděly k rozšířenému tělu (ramena, boky)."""
    blob = bytearray()
    parts = []
    bidx = {b: i for i, b in enumerate(bone_order or [])}
    morph_names = []
    for o in objs:
        sk = o.data.shape_keys
        if sk is not None:
            for kb in sk.key_blocks[1:]:
                if kb.name not in morph_names:
                    morph_names.append(kb.name)
    if len(morph_names) > MAX_MORPHS:
        raise RuntimeError('too many morphs: %d' % len(morph_names))
    for o in objs:
        if o.get('lsx_quad'):
            parts.append(_quad_part(o, blob, bidx, bone_order, morph_names))
            continue
        me = o.data
        me.calc_normals_split()
        me.calc_loop_triangles()
        M = o.matrix_world
        N = M.to_3x3().inverted().transposed()
        gname = {vg.index: vg.name for vg in o.vertex_groups}
        kblocks = {}
        if me.shape_keys is not None:
            kblocks = {kb.name: kb for kb in me.shape_keys.key_blocks[1:]}
            basis = me.shape_keys.key_blocks[0]
        bymat = {}
        for t in me.loop_triangles:
            bymat.setdefault(t.material_index, []).append(t)
        for mi, tris in sorted(bymat.items()):
            m = o.material_slots[mi].material if mi < len(o.material_slots) else None
            keys = {}
            P = []; NO = []; BI = []; BW = []; IDX = []; VI = []
            for t in tris:
                tri = []
                for li in t.loops:
                    lp = me.loops[li]
                    vi = lp.vertex_index
                    n = (N @ Vector(lp.normal)).normalized()
                    on = _oct(g(n))
                    k = (vi, on)
                    if k not in keys:
                        keys[k] = len(P)
                        P.append(g(M @ me.vertices[vi].co))
                        NO.append(on)
                        VI.append(vi)
                        if bone_order:
                            ws = []
                            for ge in me.vertices[vi].groups:
                                bn = gname.get(ge.group)
                                if bn in bidx and ge.weight > 0.001:
                                    ws.append((ge.weight, bidx[bn]))
                            ws.sort(reverse=True)
                            ws = ws[:2] or [(1.0, 0)]
                            if len(ws) == 1:
                                ws.append((0.0, ws[0][1]))
                            s = ws[0][0] + ws[1][0]
                            BI.append((ws[0][1], ws[1][1]))
                            BW.append(max(0, min(255, round(ws[0][0] / s * 255))))
                    tri.append(keys[k])
                IDX.extend((tri[0], tri[2], tri[1]))
            # Přečíslování vrcholů v pořadí prvního použití (nutné pro kódování vysoké hladiny).
            remap = {}
            for i in IDX:
                if i not in remap:
                    remap[i] = len(remap)
            inv = [0] * len(remap)
            for a, b in remap.items():
                inv[b] = a
            P = [P[i] for i in inv]; NO = [NO[i] for i in inv]; VI = [VI[i] for i in inv]
            if bone_order:
                BI = [BI[i] for i in inv]; BW = [BW[i] for i in inv]
            IDX = [remap[i] for i in IDX]
            if len(P) > 65535:
                raise RuntimeError('part too big: %s %d' % (o.name, len(P)))
            mn = [min(p[i] for p in P) for i in range(3)]
            mx = [max(p[i] for p in P) for i in range(3)]
            ext = [max(mx[i] - mn[i], 1e-6) for i in range(3)]
            QMAX = (1 << QBITS) - 1
            part = {'qb': QBITS, 'name': o.name, 'group': o.get('lsx_group', ''), 'mat': m.name if m else '', 'nv': len(P), 'ni': len(IDX),
                    'min': [round(x, 5) for x in mn], 'max': [round(x, 5) for x in mx]}
            def put(key, data):
                part[key] = [len(blob), len(data)]
                blob.extend(data)
            Q = [[round((p[i] - mn[i]) / ext[i] * QMAX) for i in range(3)] for p in P]
            # Delta kódování po složkách (planárně) – výrazně lepší komprese zlibem.
            put('pos', b''.join(_delta16([q[i] for q in Q]) for i in range(3)))
            put('nrm', bytes(((n[0] & 255) for n in NO)) + bytes(((n[1] & 255) for n in NO)))
            put('idx', _hiwater16(IDX))
            if bone_order:
                put('bi', bytes(b[0] for b in BI) + bytes(b[1] for b in BI))
                put('bw', bytes(BW))
            if kblocks:
                mlist = []
                for mname in morph_names:
                    kb = kblocks.get(mname)
                    if kb is None:
                        continue
                    D = []
                    for vi in VI:
                        d = M.to_3x3() @ (kb.data[vi].co - basis.data[vi].co)
                        D.append(g(d))
                    sc = max(max(abs(c) for c in d) for d in D)
                    if sc < MORPH_MIN:
                        continue
                    # Výchylky pod MORPH_EPS se nulují (šum pole daleko od oblasti morfu) – lepší komprese.
                    qd = [[0, 0, 0] if (d[0]*d[0]+d[1]*d[1]+d[2]*d[2]) < MORPH_EPS * MORPH_EPS else [max(-127, min(127, round(c / sc * 127))) for c in d] for d in D]
                    off = len(blob)
                    for c in range(3):   # delta mezi sousedními vrcholy (mod 256) → lepší komprese
                        prev = 0
                        for q in qd:
                            blob.append((q[c] - prev) & 255)
                            prev = q[c]
                    mlist.append([mname, round(sc, 6), off, len(qd) * 3])
                if mlist:
                    part['morphs'] = mlist
            parts.append(part)
    head = {'v': 4 if morph_names else 3, 'name': name, 'materials': [MATS[k] for k in sorted(MATS) if any(p['mat'] == k or k in p.get('mats', []) for p in parts)], 'parts': parts, 'meta': meta or {}}
    if morph_names:
        head['morphs'] = morph_names
        head['morph_bones'] = morph_bones or {}
    if arm is not None and bone_order:
        bones = []
        for bn in bone_order:
            b = arm.data.bones[bn]
            hd = g(arm.matrix_world @ b.head_local)
            tl = g(arm.matrix_world @ b.tail_local)
            bones.append({'name': bn, 'parent': bidx[b.parent.name] if b.parent else -1,
                          'head': [round(x, 5) for x in hd], 'tail': [round(x, 5) for x in tl]})
        head['bones'] = bones
    js = json.dumps(head, separators=(',', ':')).encode()
    raw = struct.pack('<I', len(js)) + js + bytes(blob)
    data = base64.b64encode(zlib.compress(raw, 9)).decode()
    open(os.path.join(OUT, name + '.b64'), 'w').write(data)
    CH = 3500
    n = (len(data) + CH - 1) // CH
    tris = sum(p['ni'] for p in parts) // 3
    print('LSX_DONE %s v=%d raw=%d b64=%d chunks=%d tris=%d verts=%d morphs=%d crc=%08x' % (name, head['v'], len(raw), len(data), n, tris, sum(p['nv'] for p in parts), len(morph_names), binascii.crc32(data.encode()) & 0xffffffff))
    return data

def chunk(name, k, CH=3500):
    data = open(os.path.join(OUT, name + '.b64')).read()
    n = (len(data) + CH - 1) // CH
    s = data[k * CH:(k + 1) * CH]
    print('LSXC %s %d/%d %08x' % (name, k, n, binascii.crc32(s.encode()) & 0xffffffff))
    print(s)
    print('LSXEND')

def preview(fname, cam_loc, cam_rot, lens=50, res=(200,170), target=None):
    bpy.ops.object.camera_add(location=cam_loc, rotation=[math.radians(a) for a in cam_rot])
    cam=bpy.context.active_object; cam.data.lens=lens; bpy.context.scene.camera=cam
    bpy.ops.object.light_add(type='SUN', rotation=(math.radians(50),math.radians(10),math.radians(-30))); bpy.context.active_object.data.energy=4
    w=bpy.data.worlds.new('w'); bpy.context.scene.world=w; w.use_nodes=True
    w.node_tree.nodes['Background'].inputs[0].default_value=(0.6,0.65,0.7,1); w.node_tree.nodes['Background'].inputs[1].default_value=0.7
    sc=bpy.context.scene; sc.render.engine='CYCLES'; sc.cycles.samples=16; sc.cycles.use_denoising=False
    sc.render.resolution_x=res[0]; sc.render.resolution_y=res[1]; sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='JPEG'; sc.render.image_settings.quality=60
    sc.render.filepath=os.path.join(OUT, fname + '.jpg')
    bpy.ops.render.render(write_still=True)
    d=base64.b64encode(open(os.path.join(OUT, fname + '.jpg'),'rb').read()).decode()
    open(os.path.join(OUT, fname + '.b64'),'w').write(d)
    print('PREVLEN', fname, len(d), (len(d)+3499)//3500)
