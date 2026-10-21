
# Postava pro Life Simulator – verze C2 (běh 8): JEDNA základní síť těla se shape keys.
# Spuštění v Blenderu: exec(lsx_common.py); exec(char.py); export_body() (viz README.md).
#
# Tělo = ŘÍDICÍ SÍŤ (cage) z čtyřúhelníků: strom uzlů → skin modifier → 1× subdivision (868 vrcholů).
# Do Godotu jde jen cage + shape keys; import ji 1× zjemní Catmull-Clarkem (scripts/assets/subdiv.gd,
# stejný algoritmus jako cc_matrix() níže, bez limitní plochy) → ~6 900 trojúhelníků, normály dopočítané.
# Proč: 4× méně přenášených dat (Blender běží jako vzdálená služba a data jdou textově po částech).
#
# Morfy NEvznikají přestavěním sítě (skin modifier by při jiných poloměrech mohl změnit topologii), ale
# deformačním polem field(): vrchol se promítne na nejbližší segmenty stromu (vážené 1/q^8, q = vzdálenost /
# místní poloměr), radiální složka se škáluje násobiteli poloměrů uzlů a přičte se posun uzlů; k tomu hladké
# „laloky“ (poprsí, břicho, hýždě). Pole se vyhodnotí na JEMNÉ síti (to, co hráč uvidí) a výchylky řídicí
# sítě se najdou metodou nejmenších čtverců: min |S·d − D|² + λ|d|² (S = matice Catmull-Clarka). Bez toho by
# zjemnění lokální tvary (poprsí) zploštilo na polovinu.
#
# Morfy (mapování v scripts/character/body_morphs.gd): lineární klíče frame/shoulders/chest/bust/waist/hips
#   s váhou (v − výchozí) / (1 − výchozí) ∈ ⟨−výchozí/(1−výchozí), 1⟩ a páry muscle_lo/hi, fat_lo/hi:
#   váha_hi = max(0, (v − výchozí) / (1 − výchozí)),  váha_lo = max(0, (výchozí − v) / výchozí).
# Žádný morf není vázaný na pohlaví ani identitu – poprsí, boky, ramena… jsou samostatné osy.
# Hlava, oči a vlasy jsou zatím z verze v3 (assets/src/character_head.lsx), obličejové morfy přijdou v C3.
import numpy as np
reset()
SUBLEV = 1
REG = 1e-3

BONES = [('hips', None, (0,0,0.95), (0,0,1.08)), ('spine','hips',(0,0,1.08),(0,0,1.28)), ('chest','spine',(0,0,1.28),(0,0,1.45)),
 ('neck','chest',(0,0,1.45),(0,0,1.56)), ('head','neck',(0,0,1.56),(0,0,1.78))]
for s, sx in (('l', 1), ('r', -1)):
    BONES += [('upper_arm_'+s,'chest',(0.19*sx,0,1.42),(0.25*sx,0.01,1.16)), ('forearm_'+s,'upper_arm_'+s,(0.25*sx,0.01,1.16),(0.29*sx,0,0.93)),
              ('hand_'+s,'forearm_'+s,(0.29*sx,0,0.93),(0.305*sx,-0.005,0.80)),
              ('thigh_'+s,'hips',(0.09*sx,0,0.93),(0.1*sx,-0.01,0.5)), ('shin_'+s,'thigh_'+s,(0.1*sx,-0.01,0.5),(0.1*sx,0.02,0.09)),
              ('foot_'+s,'shin_'+s,(0.1*sx,0.02,0.09),(0.1*sx,-0.12,0.025))]
ORDER = [b[0] for b in BONES]
bpy.ops.object.armature_add(location=(0,0,0))
arm = bpy.context.active_object; arm.name = 'rig'
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
for b in list(eb): eb.remove(b)
for n, p, h, t in BONES:
    e = eb.new(n); e.head = h; e.tail = t
    if p: e.parent = eb[p]; e.use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')

M_SKIN = mat('skin_body', (0.78, 0.58, 0.47), 0.55)
M_SHIRT = mat('cloth_shirt', (0.35, 0.42, 0.5), 0.92)
M_PANTS = mat('cloth_pants', (0.16, 0.18, 0.22), 0.88)
M_SHOE = mat('shoe_leather', (0.12, 0.1, 0.09), 0.5)

# --- Strom uzlů těla: (jméno, pozice v Blenderu, (poloměr x, poloměr y)) – neutrální výchozí postava ---
NODES = [('p',(0,0,0.95),(0.162,0.105)), ('w',(0,0,1.10),(0.128,0.088)), ('c',(0,0,1.30),(0.159,0.113)),
         ('s',(0,0,1.42),(0.14,0.088)), ('n1',(0,0,1.50),(0.054,0.054)), ('n2',(0,0,1.58),(0.048,0.048))]
EDGES = [('p','w'),('w','c'),('c','s'),('s','n1'),('n1','n2')]
ARM = [((0.18,0,1.42),(0.054,0.054)), ((0.218,0.005,1.29),(0.048,0.048)), ((0.25,0.01,1.16),(0.039,0.039)),
       ((0.27,0.004,1.05),(0.041,0.038)), ((0.29,0,0.93),(0.030,0.027)), ((0.303,-0.004,0.845),(0.029,0.033)),
       ((0.307,-0.006,0.80),(0.021,0.023))]
LEG = [((0.09,0,0.90),(0.095,0.095)), ((0.097,-0.004,0.72),(0.080,0.080)), ((0.1,-0.01,0.5),(0.056,0.056)),
       ((0.1,0.006,0.33),(0.058,0.06)), ((0.1,0.02,0.10),(0.038,0.038)), ((0.1,-0.12,0.035),(0.042,0.029))]
for s, sx in (('L', 1), ('R', -1)):
    prev = 's'
    for i, (p, r) in enumerate(ARM):
        nm = 'a%d%s' % (i, s); NODES.append((nm, (p[0]*sx, p[1], p[2]), r)); EDGES.append((prev, nm)); prev = nm
    prev = 'p'
    for i, (p, r) in enumerate(LEG):
        nm = 'l%d%s' % (i, s); NODES.append((nm, (p[0]*sx, p[1], p[2]), r)); EDGES.append((prev, nm)); prev = nm
NI = {n[0]: i for i, n in enumerate(NODES)}
NP = np.array([n[1] for n in NODES], dtype=float)
NR = np.array([n[2] for n in NODES], dtype=float)
SEG = [(NI[a], NI[b]) for a, b in EDGES]

# Laloky: (střed, sigma, směr výchylky, šířková brána |x| < limit nebo None). Blender: předek = −Y.
LOBES = {
    'bust':  [((0.085, -0.098, 1.275), 0.056, (0.0, -1.0, -0.28), 0.165), ((-0.085, -0.098, 1.275), 0.056, (0.0, -1.0, -0.28), 0.165)],
    'belly': [((0.0, -0.08, 1.06), 0.085, (0.0, -1.0, 0.05), 0.2)],
    'glute': [((0.072, 0.085, 0.86), 0.065, (0.0, 1.0, -0.15), None), ((-0.072, 0.085, 0.86), 0.065, (0.0, 1.0, -0.15), None)],
}
BASIS_LOBES = {'bust': 0.015, 'glute': 0.012}   # výchozí bust 0.2 → 0.2 × 0.075

# Lineární morfy (jeden klíč, váha −1..1 podle vzdálenosti od výchozí hodnoty – deformační pole je lineární
# v násobitelích i posunech, takže záporná váha je přesné „opačné“ těleso) a asymetrické páry pro svaly a tuk
# (úbytek a nárůst vypadají jinak: hubnutí ≠ zrcadlo obezity).
KEYS = {
    'frame':     {'r': {'*': 1.08, 'a2': 1.04, 'a4': 1.04, 'l2': 1.04, 'l4': 1.04, 'n1': 1.04, 'n2': 1.04},
                  'o': {'a*': (0.008, 0, 0), 'l*': (0.006, 0, 0)}},
    'muscle_hi': {'r': {'a0': 1.25, 'a1': 1.4, 'a2': 1.12, 'a3': 1.28, 'a4': 1.05, 'c': (1.1, 1.15), 's': (1.15, 1.2),
                        'n1': 1.22, 'n2': 1.1, 'p': 1.04, 'l0': 1.12, 'l1': 1.25, 'l2': 1.08, 'l3': 1.25, 'l4': 1.03},
                  'o': {'a*': (0.012, 0, 0)}, 'lobes': {'glute': 0.015}},
    'muscle_lo': {'r': {'a0': 0.9, 'a1': 0.82, 'a2': 0.95, 'a3': 0.85, 'c': 0.94, 's': 0.9, 'n1': 0.92, 'l1': 0.86, 'l3': 0.85},
                  'o': {'a*': (-0.005, 0, 0)}, 'lobes': {'glute': -0.008}},
    'fat_hi':    {'r': {'a0': 1.25, 'a1': 1.45, 'a2': 1.3, 'a3': 1.25, 'a4': 1.1, 'a5': 1.05, 'c': (1.18, 1.25), 's': (1.12, 1.15),
                        'n1': 1.35, 'n2': 1.25, 'w': (1.5, 1.6), 'p': (1.3, 1.35), 'l0': 1.35, 'l1': 1.42, 'l2': 1.25,
                        'l3': 1.2, 'l4': 1.08},
                  'o': {'a*': (0.022, 0, 0), 'l*': (0.02, 0, 0), 'w': (0, -0.012, 0)},
                  'lobes': {'belly': 0.06, 'glute': 0.03, 'bust': 0.012}},
    'fat_lo':    {'r': {'a0': 0.9, 'a1': 0.85, 'a3': 0.9, 'c': 0.95, 'w': (0.88, 0.86), 'p': 0.92, 'l0': 0.92, 'l1': 0.88,
                        'l3': 0.92, 'n1': 0.94},
                  'o': {'a*': (-0.006, 0, 0), 'l*': (-0.006, 0, 0)}, 'lobes': {'glute': -0.008}},
    'shoulders': {'r': {'s': (1.18, 1.04), 'c': (1.04, 1.0), 'a0': 1.05}, 'o': {'a*': (0.025, 0, 0)}},
    'chest':     {'r': {'c': (1.12, 1.14), 's': (1.05, 1.08), 'w': 1.03}, 'o': {'a*': (0.006, 0, 0)}},
    'bust':      {'lobes': {'bust': 0.06}},
    'waist':     {'r': {'w': (1.18, 1.15)}},
    'hips':      {'r': {'p': (1.16, 1.08), 'l0': 1.08}, 'o': {'l*': (0.018, 0, 0)}, 'lobes': {'glute': 0.012}},
}
# Výchozí hodnoty schématu, které základní síť představuje (kontroluje tests/test_body_morphs.gd).
BASIS_DEFAULTS = {'frame': 0.5, 'muscle': 0.35, 'body_fat': 0.3, 'shoulders': 0.5, 'chest': 0.5, 'bust': 0.2,
                  'waist': 0.5, 'hips': 0.5, 'leg_length': 0.5}

def _match(pat, nm):
    """'*' = vše, 'a*' = všechny uzly paže (obě strany), 'a1' = uzel a1L i a1R, 'w' = přesně uzel w."""
    base = nm[:-1] if nm[-1] in 'LR' and len(nm) > 1 and nm[0] in 'al' else nm
    if pat == '*':
        return True
    if pat.endswith('*'):
        return base.startswith(pat[:-1]) and nm[0] == pat[0] and nm[0] in 'al'
    return base == pat

def _side(nm):
    return 1.0 if nm.endswith('L') else (-1.0 if nm.endswith('R') else 0.0)

def node_params(spec):
    mul = np.ones((len(NODES), 2)); off = np.zeros((len(NODES), 3))
    for pat, m in spec.get('r', {}).items():
        mm = (m, m) if isinstance(m, (int, float)) else m
        for i, n in enumerate(NODES):
            if _match(pat, n[0]):
                mul[i, 0] *= mm[0]; mul[i, 1] *= mm[1]
    for pat, o in spec.get('o', {}).items():
        for i, n in enumerate(NODES):
            if _match(pat, n[0]):
                sd = _side(n[0])
                off[i] += (o[0] * (sd if sd != 0 else 1.0), o[1], o[2])
    return mul, off

def lobe_disp(V, name, amp):
    D = np.zeros_like(V)
    for c, sig, d, gate in LOBES[name]:
        c = np.array(c); d = np.array(d); d = d / np.linalg.norm(d)
        r2 = ((V - c) ** 2).sum(axis=1)
        w = np.exp(-r2 / (2 * sig * sig))
        if gate is not None:
            w *= np.clip((gate - np.abs(V[:, 0])) / 0.03, 0, 1)
        D += (amp * w)[:, None] * d
    return D

def field(V, spec):
    """Výchylky vrcholů V (n×3) pro jeden morf."""
    mul, off = node_params(spec)
    num = np.zeros_like(V); den = np.zeros(len(V))
    for i, j in SEG:
        A = NP[i]; B = NP[j]; ab = B - A; L2 = float(ab @ ab)
        t = np.clip(((V - A) @ ab) / L2, 0.0, 1.0)
        C = A + t[:, None] * ab
        a = ab / math.sqrt(L2)
        u = np.array([1.0, 0, 0]) - a[0] * a
        if np.linalg.norm(u) < 0.3:
            u = np.array([0, 1.0, 0]) - a[1] * a
        u /= np.linalg.norm(u); v = np.cross(a, u)
        R = V - C
        ax = (R @ a)[:, None] * a
        per = R - ax
        pu = per @ u; pv = per @ v
        tt = t[:, None]
        r_t = (1 - tt) * NR[i] + tt * NR[j]
        m_t = (1 - tt) * mul[i] + tt * mul[j]
        o_t = (1 - tt) * off[i] + tt * off[j]
        newp = C + o_t + ax + (pu * m_t[:, 0])[:, None] * u + (pv * m_t[:, 1])[:, None] * v
        q = np.maximum(np.linalg.norm(R, axis=1) / r_t.mean(axis=1), 0.3)
        w = q ** -8
        num += w[:, None] * (newp - V); den += w
    D = num / den[:, None]
    for ln, amp in spec.get('lobes', {}).items():
        D += lobe_disp(V, ln, amp)
    return D

def morph_bones():
    """Posun hlav kostí (Godot osy) při plné váze morfu – ramena (upper_arm) a kyčle (thigh).
    Godot posouvá klidovou polohu kosti i inverzní bind (SimVisual._apply_joints), takže se paže neposune dvakrát."""
    out = {}
    for k, spec in KEYS.items():
        mul, off = node_params(spec)
        bones = {}
        for bn, nn in (('upper_arm_l', 'a0L'), ('upper_arm_r', 'a0R'), ('thigh_l', 'l0L'), ('thigh_r', 'l0R')):
            o = off[NI[nn]]
            if np.abs(o).max() > 1e-6:
                bones[bn] = [round(float(x), 5) for x in g(o)]
        if bones:
            out[k] = bones
    return out

def cc_matrix(F, nv):
    """Catmull-Clark, 1 úroveň, uzavřená čtyřúhelníková síť, BEZ limitní plochy, jako hustá matice S
    (jemné vrcholy × řídicí vrcholy) + nové plochy. Pořadí jemných vrcholů: [vrcholové body][hranové body
    v pořadí objevení po plochách][body ploch]. Stejný algoritmus: scripts/assets/subdiv.gd.
    Ověřeno proti Blender Subdivision Surface (use_limit_surface=False): max. chyba 3,6e-7 m."""
    edges = {}
    for fi, f in enumerate(F):
        for k in range(4):
            a, b = f[k], f[(k + 1) % 4]
            edges.setdefault((min(a, b), max(a, b)), []).append(fi)
    ek = list(edges.keys()); eid = {k: i for i, k in enumerate(ek)}
    ne = len(ek); nf = len(F)
    S = np.zeros((nv + ne + nf, nv))
    for fi, f in enumerate(F):
        for v in f:
            S[nv + ne + fi, v] += 0.25
    for (a, b), fs in edges.items():
        if len(fs) != 2:
            raise RuntimeError('cage is not closed 2-manifold')
        r = nv + eid[(a, b)]
        S[r, a] += 0.25; S[r, b] += 0.25
        for fi in fs:
            S[r] += 0.25 * S[nv + ne + fi]
    vf = [[] for _ in range(nv)]; ve = [[] for _ in range(nv)]
    for fi, f in enumerate(F):
        for v in f:
            vf[v].append(fi)
    for (a, b) in ek:
        ve[a].append(b); ve[b].append(a)
    for v in range(nv):
        n = len(ve[v])
        Fa = np.zeros(nv)
        for fi in vf[v]:
            Fa += S[nv + ne + fi] / len(vf[v])
        R = np.zeros(nv)
        for u in ve[v]:
            R[v] += 0.5 / n; R[u] += 0.5 / n
        row = (Fa + 2 * R) / n
        row[v] += (n - 3) / n
        S[v] = row
    NF = []
    for fi, f in enumerate(F):
        fp = nv + ne + fi
        for k in range(4):
            e1 = nv + eid[(min(f[k], f[(k + 1) % 4]), max(f[k], f[(k + 1) % 4]))]
            e0 = nv + eid[(min(f[k - 1], f[k]), max(f[k - 1], f[k]))]
            NF.append((f[k], e1, fp, e0))
    return S, NF

def build_cage():
    me = bpy.data.meshes.new('body')
    me.from_pydata([n[1] for n in NODES], [(NI[a], NI[b]) for a, b in EDGES], [])
    o = bpy.data.objects.new('body', me); bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    sk = o.modifiers.new('skin', 'SKIN'); sk.branch_smoothing = 0.6
    for i, n in enumerate(NODES):
        me.skin_vertices[0].data[i].radius = n[2]
    me.skin_vertices[0].data[0].use_root = True
    ss = o.modifiers.new('sub', 'SUBSURF'); ss.levels = SUBLEV
    apply_mods(o)
    bpy.ops.object.shade_smooth()
    o['lsx_group'] = 'body'; o['lsx_quad'] = 1; o['lsx_subdiv'] = 1
    return o

def solve_cage(o):
    """Základní řídicí síť tak, aby její zjemnění neslo výchozí laloky (nejmenší čtverce, regularizace k původní)."""
    F = [list(p.vertices) for p in o.data.polygons]
    C = np.array([v.co[:] for v in o.data.vertices])
    S, NF = cc_matrix(F, len(C))
    Ainv = np.linalg.inv(S.T @ S + REG * np.eye(len(C)))
    fine = S @ C
    T0 = fine.copy()
    for ln, amp in BASIS_LOBES.items():
        T0 += lobe_disp(fine, ln, amp)
    C0 = Ainv @ (S.T @ T0 + REG * C)
    o.data.vertices.foreach_set('co', C0.ravel()); o.data.update()
    return S, Ainv, C0, NF

def add_keys(o, S, Ainv, C0):
    F0 = S @ C0
    o.shape_key_add(name='Basis', from_mix=False)
    stats = {}; resid = {}
    for k, spec in KEYS.items():
        D = field(F0, spec)
        d = Ainv @ (S.T @ D)
        kb = o.shape_key_add(name=k, from_mix=False)
        kb.data.foreach_set('co', (C0 + d).ravel())
        stats[k] = round(float(np.linalg.norm(D, axis=1).max()), 4)
        resid[k] = round(float(np.linalg.norm(S @ d - D, axis=1).max()), 4)
    return stats, resid

def weight_auto(objs):
    for ob in bpy.context.selected_objects: ob.select_set(False)
    for o in objs: o.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')

def paint_body(o):
    o.data.materials.clear()
    for m in (M_SKIN, M_SHIRT, M_PANTS, M_SHOE): o.data.materials.append(m)
    gn = {vg.index: vg.name for vg in o.vertex_groups}
    dom = []
    for v in o.data.vertices:
        best = max(v.groups, key=lambda e: e.weight, default=None)
        dom.append(gn.get(best.group, 'hips') if best else 'hips')
    for p in o.data.polygons:
        names = [dom[i] for i in p.vertices]
        n = max(set(names), key=names.count)
        z = p.center.z
        if n.startswith('foot'): mi = 3
        elif n.startswith('hand') or n.startswith('forearm') or n in ('neck', 'head'): mi = 0
        elif n.startswith('thigh') or n.startswith('shin'): mi = 2
        elif n == 'hips': mi = 2 if z < 1.0 else 1
        elif n == 'chest' and z > 1.465: mi = 0
        else: mi = 1
        p.material_index = mi

body = build_cage()
S_CC, A_INV, C0, NF = solve_cage(body)
weight_auto([body])
paint_body(body)
KEY_STATS, KEY_RESID = add_keys(body, S_CC, A_INV, C0)

def export_body():
    meta = {'height': 1.78, 'leg_length': 0.93, 'key_stats': KEY_STATS, 'key_resid': KEY_RESID,
            'basis_defaults': BASIS_DEFAULTS, 'morph_bones': morph_bones(), 'fine_tris': len(NF) * 2}
    return export_lsx('body', [body], arm, ORDER, meta, morph_bones())
