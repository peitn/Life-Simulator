
def subd(o, lev=1):
    s = o.modifiers.new('sub', 'SUBSURF'); s.levels = lev
    apply_mods(o); bpy.ops.object.shade_smooth()
    return o

def cushion(name, size, loc, m, rot=(0,0,0), puff=0.012):
    o = rbox(name, size, loc, m, min(size) * 0.3, 2, rot=rot)
    o.data.use_auto_smooth = False
    # lehké „nafouknutí“ středu ploch
    c = Vector(loc)
    for v in o.data.vertices:
        d = v.co - c
        v.co += d.normalized() * puff * 0.5
    return subd(o, 1)

def leg(name, loc, h, m, r0=0.022, r1=0.014):
    bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=r1, radius2=r0, depth=h, location=(loc[0], loc[1], h/2))
    o = bpy.context.active_object; o.name = name; set_mat(o, m)
    bpy.ops.object.shade_smooth(); o.data.use_auto_smooth = True; o.data.auto_smooth_angle = math.radians(40)
    return o

def build_sofa():
    reset()
    F = mat('fabric_sofa', (0.24, 0.30, 0.33), 0.95)
    P = mat('fabric_pillow', (0.62, 0.45, 0.17), 0.92)
    W = mat('wood_dark', (0.17, 0.10, 0.06), 0.55)
    parts = []
    for x in (-1.02, 1.02):
        for y in (-0.36, 0.36):
            parts.append(leg('leg', (x, y), 0.1, W))
    parts.append(rbox('base', (2.2, 0.86, 0.2), (0, 0.02, 0.2), F, 0.03, 2))
    for x in (-0.47, 0.47):
        parts.append(cushion('seat', (0.92, 0.66, 0.14), (x, -0.07, 0.37), F))
        parts.append(cushion('back', (0.92, 0.2, 0.44), (x, 0.27, 0.6), F, rot=(math.radians(-10), 0, 0)))
    parts.append(rbox('backframe', (2.2, 0.14, 0.55), (0, 0.38, 0.55), F, 0.04, 2))
    for x in (-1.0, 1.0):
        parts.append(rbox('arm', (0.2, 0.88, 0.5), (x, 0.0, 0.47), F, 0.07, 3))
    parts.append(cushion('pillow', (0.4, 0.13, 0.36), (-0.68, 0.14, 0.6), P, rot=(math.radians(-18), 0, math.radians(14)), puff=0.03))
    return join(parts, 'sofa')

def build_bed(name, w, single):
    reset()
    W = mat('wood_oak', (0.42, 0.29, 0.18), 0.6)
    L = mat('linen_sheet', (0.9, 0.89, 0.85), 0.95)
    D = mat('fabric_duvet', (0.38, 0.4, 0.46) if not single else (0.33, 0.42, 0.36), 0.95)
    H = mat('fabric_headboard', (0.35, 0.32, 0.3), 0.95)
    L2 = 2.1
    parts = []
    for x in (-w/2 + 0.04, w/2 - 0.04):
        for y in (-L2/2 + 0.04, L2/2 - 0.06):
            parts.append(rbox('leg', (0.06, 0.06, 0.12), (x, y, 0.06), W, 0.008, 1))
    for x in (-w/2 + 0.025, w/2 - 0.025):
        parts.append(rbox('rail', (0.05, L2, 0.2), (x, 0, 0.22), W, 0.01, 2))
    parts.append(rbox('rail_f', (w, 0.05, 0.2), (0, -L2/2 + 0.025, 0.22), W, 0.01, 2))
    parts.append(rbox('slats', (w - 0.1, L2 - 0.1, 0.03), (0, 0, 0.25), W, 0.005, 1))
    parts.append(rbox('mattress', (w - 0.08, L2 - 0.1, 0.22), (0, 0, 0.38), L, 0.05, 3))
    duvet = rbox('duvet', (w - 0.02, 1.35, 0.08), (0, -0.37, 0.52), D, 0.035, 3)
    duvet.data.use_auto_smooth = False
    for v in duvet.data.vertices:   # převis přes boky matrace a zvlnění
        if abs(v.co.x) > (w - 0.02) / 2 - 0.04 and v.co.z < 0.52:
            v.co.z -= 0.12; v.co.x *= 1.02
        v.co.z += 0.008 * math.sin(v.co.y * 9.0) * math.cos(v.co.x * 5.0)
    parts.append(subd(duvet, 1))
    parts.append(cushion('fold', (w - 0.02, 0.18, 0.07), (0, 0.33, 0.535), D, rot=(math.radians(8), 0, 0), puff=0.02))
    pw = 0.62 if not single else 0.6
    xs = (-w/4, w/4) if not single else (0,)
    for x in xs:
        parts.append(cushion('pillow', (pw, 0.38, 0.13), (x, 0.74, 0.57), L, rot=(math.radians(-20), 0, 0), puff=0.035))
    if single:
        parts.append(rbox('head', (w, 0.05, 0.85), (0, L2/2 - 0.025, 0.47), W, 0.012, 2))
    else:
        parts.append(rbox('head_frame', (w + 0.04, 0.08, 1.0), (0, L2/2 - 0.02, 0.5), W, 0.015, 2))
        for i in range(3):
            x = -w/3 + i * w/3
            parts.append(cushion('head_pad', (w/3 - 0.03, 0.06, 0.45), (x, L2/2 - 0.07, 0.78), H, puff=0.015))
    return join(parts, name)

def build_fridge():
    reset()
    E = mat('enamel_fridge', (0.85, 0.85, 0.83), 0.32)
    S = mat('metal_steel', (0.72, 0.73, 0.75), 0.28, 1.0)
    K = mat('plastic_dark', (0.06, 0.06, 0.065), 0.5)
    N = mat('paper_note', (0.93, 0.9, 0.78), 0.9)
    R = mat('plastic_red', (0.7, 0.12, 0.1), 0.4)
    parts = []
    parts.append(rbox('body', (0.68, 0.62, 1.84), (0, 0.04, 0.95), E, 0.02, 2))
    parts.append(rbox('kick', (0.64, 0.58, 0.06), (0, 0.06, 0.03), K, 0.005, 1))
    parts.append(rbox('door_top', (0.68, 0.05, 1.12), (0, -0.295, 1.31), E, 0.018, 3))
    parts.append(rbox('door_bot', (0.68, 0.05, 0.68), (0, -0.295, 0.395), E, 0.018, 3))
    parts.append(rbox('gasket', (0.66, 0.02, 0.012), (0, -0.28, 0.745), K, 0.002, 1))
    for z0, h in ((1.0, 0.5), (0.48, 0.3)):
        parts.append(cyl('handle', 0.011, h, (0.28, -0.345, z0 + h/2), S, 10))
        for dz in (0.02, h - 0.02):
            parts.append(cyl('hpost', 0.008, 0.035, (0.28, -0.33, z0 + dz), S, 8, rot=(math.radians(90), 0, 0)))
    parts.append(rbox('note', (0.15, 0.003, 0.2), (-0.12, -0.322, 1.45), N, 0.0, 1, rot=(0, math.radians(4), 0)))
    parts.append(cyl('magnet', 0.016, 0.01, (-0.12, -0.326, 1.535), R, 12, rot=(math.radians(90), 0, 0)))
    parts.append(rbox('note2', (0.1, 0.003, 0.14), (0.05, -0.322, 1.62), N, 0.0, 1, rot=(0, math.radians(-6), 0)))
    parts.append(cyl('magnet2', 0.012, 0.01, (0.05, -0.326, 1.68), K, 12, rot=(math.radians(90), 0, 0)))
    return join(parts, 'fridge')
