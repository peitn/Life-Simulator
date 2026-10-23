# Life Simulator – materiál kůže s mikrodetailem pro vizuální kontrolu v Blenderu (běh 22, C4c).
# Napodobuje skin.gdshader (C4c): zóny mazu a suchosti podle typu pleti (T-zóna / tváře), póry a kožní linie jako bump,
# šupinky u velmi suché pleti, mazový film jako coat, chloupky (vellus) jako sheen. Parametry = row["micro"]
# z tools/face_render_export.gd (stejné hodnoty jako SkinLayers.resolve ve hře). Je to aproximace: Cycles ≠ Forward+.
# Použití: po exec(face_render.py) zavolej exec(skin_micro.py) – přepíše material_for().
# Souřadnice: glTF import převádí Godot (x, y, z) → Blender (x, −z, y); masky se počítají v Godot ose (gy = výška, gz = dopředu).
import bpy

class _NB:
    def __init__(self, nt):
        self.nt = nt; self.n = nt.nodes; self.l = nt.links
    def _in(self, node, idx, v):
        s = node.inputs[idx]
        if isinstance(v, (int, float)):
            s.default_value = float(v)
        else:
            self.l.new(v, s)
    def math(self, op, a, b=0.0, clamp=False):
        m = self.n.new("ShaderNodeMath"); m.operation = op; m.use_clamp = clamp
        self._in(m, 0, a); self._in(m, 1, b)
        return m.outputs[0]
    def ss(self, x, a, b):
        # smoothstep(a, b, x) včetně a > b (klesající)
        r = self.n.new("ShaderNodeMapRange"); r.interpolation_type = "SMOOTHSTEP"; r.clamp = True
        if a <= b:
            self._in(r, "Value", x); r.inputs["From Min"].default_value = a; r.inputs["From Max"].default_value = b
            return r.outputs["Result"]
        self._in(r, "Value", x); r.inputs["From Min"].default_value = b; r.inputs["From Max"].default_value = a
        return self.math("SUBTRACT", 1.0, r.outputs["Result"])
    def band(self, x, lo, hi, soft):
        return self.math("MULTIPLY", self.ss(x, lo - soft, lo + soft), self.math("SUBTRACT", 1.0, self.ss(x, hi - soft, hi + soft)))
    def mix(self, a, b, t):
        return self.math("ADD", a, self.math("MULTIPLY", self.math("SUBTRACT", b, a), t))

def skin_micro_material(f):
    mc = f.get("micro", {})
    oil_t = mc.get("oil_t", 0.21); oil_c = mc.get("oil_c", 0.12); dry_t = mc.get("dry_t", 0.125); dry_c = mc.get("dry_c", 0.125)
    pore_size = mc.get("pore_size", 1.0); micro = mc.get("micro", 0.3); vellus = mc.get("vellus", 0.5); pores = mc.get("pores", 0.6)
    vc = mc.get("vellus_color", [0.35, 0.28, 0.22])
    m = bpy.data.materials.new("skin_micro"); m.use_nodes = True
    nt = m.node_tree; B = _NB(nt)
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = hexc(f["skin"])
    bsdf.inputs["Subsurface Weight"].default_value = 0.25
    bsdf.inputs["Subsurface Radius"].default_value = (1.0, 0.35, 0.2)
    bsdf.inputs["Subsurface Scale"].default_value = 0.004
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(geo.outputs["Position"], sep.inputs[0])
    gx = sep.outputs["X"]; gy = sep.outputs["Z"]; gz = B.math("MULTIPLY", sep.outputs["Y"], -1.0)
    ax = B.math("ABSOLUTE", gx)
    head = B.ss(gy, 1.51, 1.53)
    front = B.math("MULTIPLY", head, B.ss(gz, 0.03, 0.04))
    fore = B.math("MULTIPLY", B.band(gy, 1.695, 1.775, 0.012), B.ss(ax, 0.05, 0.03))
    nose = B.math("MULTIPLY", B.band(gy, 1.612, 1.700, 0.008), B.ss(ax, 0.018, 0.010))
    chin = B.math("MULTIPLY", B.band(gy, 1.552, 1.588, 0.006), B.ss(ax, 0.026, 0.016))
    tz = B.math("MULTIPLY", B.math("MAXIMUM", fore, B.math("MAXIMUM", nose, chin)), front)
    # tváře: exp(−((ax−0,045)/0,02)² − ((y−1,63)/0,024)²)
    e1 = B.math("POWER", B.math("DIVIDE", B.math("SUBTRACT", ax, 0.045), 0.020), 2.0)
    e2 = B.math("POWER", B.math("DIVIDE", B.math("SUBTRACT", gy, 1.630), 0.024), 2.0)
    cz = B.math("MULTIPLY", B.math("EXPONENT", B.math("MULTIPLY", B.math("ADD", e1, e2), -1.0)), front)
    oil_head = B.mix(oil_c, oil_t, tz)
    oil = B.mix(oil_c * 0.5, oil_head, head)
    dry_head = B.mix(dry_c, dry_t, tz)
    dry = B.mix(dry_c, dry_head, head)
    rough = B.math("ADD", 0.52, B.math("SUBTRACT", B.math("MULTIPLY", B.math("SUBTRACT", dry, 0.125), 0.22), B.math("MULTIPLY", B.math("SUBTRACT", oil, 0.04), 0.38)))
    # póry: Voronoi F1 (vzdálenost v buňkách), buňka 0,75 mm × pore_size × (0,7..1) – zóna pz
    pz = B.mix(0.25, B.mix(0.35, B.math("ADD", 0.55, B.math("MULTIPLY", B.math("MAXIMUM", tz, cz), 0.45)), front), head)
    cell = 0.00075 * pore_size
    vor = nt.nodes.new("ShaderNodeTexVoronoi"); vor.voronoi_dimensions = "3D"; vor.feature = "F1"
    vor.inputs["Scale"].default_value = 1.0 / cell
    nt.links.new(geo.outputs["Position"], vor.inputs["Vector"])
    pit = B.ss(vor.outputs["Distance"], 0.30, 0.14)
    ridge_n = nt.nodes.new("ShaderNodeTexNoise"); ridge_n.inputs["Scale"].default_value = 2300.0; ridge_n.inputs["Detail"].default_value = 0.0
    nt.links.new(geo.outputs["Position"], ridge_n.inputs["Vector"])
    rr = B.math("SUBTRACT", 1.0, B.math("ABSOLUTE", B.math("SUBTRACT", B.math("MULTIPLY", ridge_n.outputs["Fac"], 2.0), 1.0)))
    lines = B.ss(rr, 0.80, 1.0)
    height = B.math("ADD", B.math("MULTIPLY", B.math("MULTIPLY", pit, pz), 0.00006 * pores / 0.00005), B.math("MULTIPLY", lines, 0.000025 * micro / 0.00005))
    bump = nt.nodes.new("ShaderNodeBump"); bump.invert = True
    bump.inputs["Strength"].default_value = 1.0; bump.inputs["Distance"].default_value = 0.00005
    nt.links.new(height, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    # šupinky (velmi suchá pleť) – popelavý nádech, matnost
    flake_amt = B.ss(dry, 0.45, 0.9)
    vf = nt.nodes.new("ShaderNodeTexVoronoi"); vf.voronoi_dimensions = "3D"; vf.inputs["Scale"].default_value = 1.0 / 0.0016
    nt.links.new(geo.outputs["Position"], vf.inputs["Vector"])
    # jako shader: šupinka jen v části buněk (pravděpodobnost 0,25 × síla × skupinka), skupinky z nízkofrekvenčního šumu
    pn = nt.nodes.new("ShaderNodeTexNoise"); pn.inputs["Scale"].default_value = 70.0; pn.inputs["Detail"].default_value = 0.0
    nt.links.new(geo.outputs["Position"], pn.inputs["Vector"])
    patch = B.ss(pn.outputs["Fac"], 0.5, 0.75)
    sepc = nt.nodes.new("ShaderNodeSeparateColor"); nt.links.new(vf.outputs["Color"], sepc.inputs[0])
    has = B.math("LESS_THAN", sepc.outputs[0], B.math("MULTIPLY", B.math("MULTIPLY", flake_amt, patch), 0.25))
    fl = B.math("MULTIPLY", B.ss(vf.outputs["Distance"], 0.32, 0.18), has)
    ash = B.math("MINIMUM", B.math("ADD", B.math("MULTIPLY", flake_amt, 0.04), B.math("MULTIPLY", B.math("MULTIPLY", fl, flake_amt), 0.12)), 0.2)
    mixc = nt.nodes.new("ShaderNodeMix"); mixc.data_type = "RGBA"
    nt.links.new(ash, mixc.inputs[0])
    mixc.inputs[6].default_value = hexc(f["skin"]); mixc.inputs[7].default_value = (0.60, 0.58, 0.56, 1.0)
    nt.links.new(mixc.outputs[2], bsdf.inputs["Base Color"])
    rough = B.math("ADD", rough, B.math("MULTIPLY", fl, 0.12))
    rough = B.math("MINIMUM", B.math("MAXIMUM", rough, 0.22), 0.88)
    nt.links.new(rough, bsdf.inputs["Roughness"])
    nt.links.new(B.math("MULTIPLY", B.math("MULTIPLY", oil, oil), 0.3), bsdf.inputs["Coat Weight"])
    bsdf.inputs["Coat Roughness"].default_value = 0.32
    nt.links.new(B.math("ADD", 0.35, B.math("MULTIPLY", oil, 0.25)), bsdf.inputs["Specular IOR Level"])
    bsdf.inputs["Sheen Weight"].default_value = 0.12 * vellus   # Cycles sheen působí i mimo siluetu – slabší než RIM ve hře
    bsdf.inputs["Sheen Tint"].default_value = (vc[0], vc[1], vc[2], 1.0)
    bsdf.inputs["Sheen Roughness"].default_value = 0.45
    return m

def lash_material(f):
    m = bpy.data.materials.new("lash_vc"); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor"); attr.layer_name = "Color"
    mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"; mul.inputs[0].default_value = 1.0
    mul.inputs[6].default_value = hexc(f["lash"]) if "lash" in f else (0.03, 0.025, 0.02, 1)
    nt.links.new(attr.outputs["Color"], mul.inputs[7])
    nt.links.new(mul.outputs[2], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.55
    return m

_material_for_base = material_for

def material_for(nm, f):
    if "skin_body" in nm and "micro" in f:
        return skin_micro_material(f)
    if "eye_lash" in nm:
        return lash_material(f)
    if "mouth_inner" in nm and "mouth" in f:
        return mat("mouth", hexc(f["mouth"]), 0.55, 0.2)
    return _material_for_base(nm, f)
