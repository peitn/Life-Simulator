# Life Simulator – vizuální kontrola obličeje v Blenderu (běh 18, C3+ B).
# Použití v Blenderu (headless): nastav globály a exec(open('/tmp/face_render.py').read()).
#   FACES_URL  – cesta v projektu k JSON z tools/face_render_export.gd (např. "previews/c3b_before.json")
#   GLB        – lokální cesta k character.glb (stažený přes fetch_glb())
#   SEL, TAG, VIEWS, TW, TH, ORTHO, CAM_C, SAMPLES – výběr řádků a kamera
# Výstup: řádky jako .npy v /tmp/rt/<TAG>_<i>.npy; sheet() je složí a send() pošle zpět do Godotu jako base64.
import bpy, json, math, os, base64, urllib.request, hashlib
import numpy as np
from mathutils import Vector

BASE = "https://peiti-godot-mcp.hf.space/doc/file:lifesim/"
MCP = "https://peiti-godot-mcp.hf.space/mcp"

def fetch_text(path):
    d = urllib.request.urlopen(BASE + path, timeout=120).read().decode()
    hdr = "# lifesim/" + path + "\n\n"
    return d[len(hdr):] if d.startswith(hdr) else d

def fetch_glb(parts_dir, n, out="/tmp/character.glb"):
    b64 = "".join(fetch_text("%s/p%02d.b64" % (parts_dir, i)).strip() for i in range(n))
    data = base64.b64decode(b64)
    open(out, "wb").write(data)
    return hashlib.md5(data).hexdigest()

def hexc(h, a=1.0):
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (c[0], c[1], c[2], a)

def mat(name, col, rough=0.5, sss=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = col
    b.inputs["Roughness"].default_value = rough
    if sss > 0:
        b.inputs["Subsurface Weight"].default_value = sss
        b.inputs["Subsurface Radius"].default_value = (1.0, 0.35, 0.2)
        b.inputs["Subsurface Scale"].default_value = 0.004
    return m

def setup(glb):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"; sc.cycles.samples = SAMPLES; sc.cycles.use_denoising = False; sc.cycles.device = "CPU"
    sc.render.resolution_x = TW; sc.render.resolution_y = TH; sc.render.use_compositing = False
    sc.view_settings.view_transform = "AgX"
    w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.16, 0.16, 0.17, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    def light(name, loc, energy, size):
        ld = bpy.data.lights.new(name, "AREA"); ld.energy = energy; ld.size = size
        o = bpy.data.objects.new(name, ld); sc.collection.objects.link(o); o.location = loc
        o.rotation_euler = (Vector((0, 0, 1.6)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    light("key", (-0.9, -1.4, 2.1), 120, 0.8)
    light("fill", (1.2, -1.0, 1.6), 45, 1.0)
    light("rim", (0.3, 1.4, 2.0), 70, 0.6)
    cd = bpy.data.cameras.new("cam"); cd.type = "ORTHO"; cd.ortho_scale = ORTHO
    cam = bpy.data.objects.new("cam", cd); sc.collection.objects.link(cam); sc.camera = cam
    return sc, cam

def render_rows(faces, sel, tag):
    sc, cam = setup(GLB)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    os.makedirs("/tmp/rt", exist_ok=True)
    for fi in sel:
        f = faces[fi]
        keys = dict(f["body"]); keys.update(f["face"])
        for o in meshes:
            sk = o.data.shape_keys
            if sk:
                for kb in sk.key_blocks[1:]:
                    kb.slider_min = -1.0
                    kb.value = float(keys.get(kb.name, 0.0))
            nm = o.name
            o.hide_render = nm.startswith("hair_short") or nm.startswith("hair_long")
            if "skin_lips" in nm: m = mat("lips", hexc(f["lips"]), 0.35, 0.3)
            elif "skin" in nm: m = mat("skin", hexc(f["skin"]), 0.48, 0.25)
            elif "eye_socket" in nm or "mouth_inner" in nm: m = mat("dark", (0.05, 0.02, 0.02, 1), 0.6)
            elif "pupil" in nm: m = mat("pupil", (0.01, 0.01, 0.01, 1), 0.1)
            elif "iris" in nm: m = mat("iris", hexc(f["iris"]), 0.2)
            elif "sclera" in nm: m = mat("sclera", (0.78, 0.76, 0.72, 1), 0.15)
            elif "shirt" in nm: m = mat("top", hexc(f["top"]), 0.8)
            elif "pants" in nm: m = mat("bottom", hexc(f["bottom"]), 0.8)
            else: m = mat("other", (0.08, 0.07, 0.06, 1), 0.6)
            o.data.materials.clear(); o.data.materials.append(m)
        tiles = []
        for vn, az, el in VIEWS:
            a = math.radians(az); e = math.radians(el); dist = 3.0
            C = CAM_C
            cam.location = (C[0] + dist * math.sin(a) * math.cos(e), C[1] - dist * math.cos(a) * math.cos(e), C[2] + dist * math.sin(e))
            cam.rotation_euler = (Vector(C) - cam.location).to_track_quat("-Z", "Y").to_euler()
            p = "/tmp/rt/%s_%d_%s.png" % (tag, fi, vn)
            sc.render.filepath = p
            bpy.ops.render.render(write_still=True)
            im = bpy.data.images.load(p)
            tiles.append(np.array(im.pixels[:], dtype=np.float32).reshape(TH, TW, 4)); bpy.data.images.remove(im)
        np.save("/tmp/rt/%s_%d.npy" % (tag, fi), np.concatenate(tiles, axis=1))
    print("rows", tag, sel)

def sheet(tag, sel, out_tag):
    rows = [np.load("/tmp/rt/%s_%d.npy" % (tag, fi)) for fi in sel]
    s = np.concatenate(rows[::-1], axis=0)
    H, W = s.shape[:2]
    img = bpy.data.images.new("sheet", W, H, alpha=False)
    img.pixels = s.ravel()
    p = "/tmp/rt/sheet_%s.jpg" % out_tag
    img.filepath_raw = p; img.file_format = "JPEG"
    bpy.context.scene.render.image_settings.quality = 85
    img.save()
    return open(p, "rb").read()

def send(tag, data, part=140000):
    b64 = base64.b64encode(data).decode()
    k = max(1, math.ceil(len(b64) / part)); ps = math.ceil(len(b64) / k)
    n = 0
    for i in range(0, len(b64), ps):
        body = {"jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": {"name": "godot_file_write", "arguments": {"project": "lifesim", "path": "previews/blender_%s_%d.b64" % (tag, i // ps), "content": b64[i:i + ps]}}}
        req = urllib.request.Request(MCP, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}, method="POST")
        urllib.request.urlopen(req, timeout=120).read(); n += 1
    print("SENT", tag, len(data), hashlib.md5(data).hexdigest(), "parts", n)
