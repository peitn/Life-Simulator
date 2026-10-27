#!/usr/bin/env python3
"""Attach verified offline Elmer finite-element reference metadata to the
*separate* anatomical Blender v0.1 asset.

NOT a joint-contact solve on the actual 3D femur/knee geometry.
DOES NOT modify original lifespan character.glb, live game skin, or Bullet
ragdoll constraints. Requires a pre-populated Blender asset-library JSON
'elmer_fem_results_v1.json' (copied from the canonical Godot project).
"""
import bpy
import json
import hashlib
import os
import datetime
from pathlib import Path

ASSET=Path("/app/data/library/model/lifesim-anatomy-skeleton-v1")
ref_file=ASSET/"elmer_fem_results_v1.json"
source=ASSET/"anatomy_skeleton_v1.blend"
assert ref_file.is_file() and source.is_file()
model=json.loads(ref_file.read_text(encoding="utf-8"))
assert model["schema"]=="life-simulator.anatomy.elmer-fem.v1"
assert model["solver"]=="ElmerSolver 26.2"
assert model["implementation"]["live_gameplay_enabled"] is False
assert model["implementation"]["medical_validation"] is False
cart=model["cartilage_compression"]
bone=model["bone_cantilever"]
cases=cart["cases"]
assert len(cases)==4 and cases[-1]["nx"]==120 and cases[-1]["ny"]==24
assert float(cases[-1]["max_displacement_m"])>0
assert cart["soft_material_case"]["elastic_modulus_pa"]==2500000

bpy.ops.wm.open_mainfile(filepath=str(source))
scene=bpy.context.scene
rig=bpy.data.objects.get("Anatomy_Rig_V1")
assert rig and len(rig.data.bones)==194
assert sum(o.rigid_body is not None for o in bpy.data.objects)==17
assert sum(o.rigid_body_constraint is not None for o in bpy.data.objects)==16
scene["elmer_status"]="OFFLINE 2D plane-stress elastostatics only; not game physics"
scene["elmer_solver"]=model["solver"]
scene["elmer_reference_source"]="docs/anatomy/elmer-fem-results-v1.json"
scene["elmer_reference_bone_max_u_m"]=float(bone["cases"][-1]["max_displacement_m"])
scene["elmer_reference_cartilage_pressure_pa"]=20000.0
scene["elmer_reference_cartilage_ultrafine_max_u_m"]=float(cases[-1]["max_displacement_m"])
scene["elmer_reference_cartilage_reference_E_pa"]=float(cart["elastic_modulus_pa"])
scene["elmer_reference_cartilage_soft_E_pa"]=float(cart["soft_material_case"]["elastic_modulus_pa"])
scene["elmer_source_mesh"]="2D 40mm x 3mm plane stress, uniform pressure, flat slab"
scene["elmer_livesim_geometry_solved"]=False
scene["elmer_max_corner_stress_converged"]=False
scene["elmer_realtime_ragdoll_enabled"]=False

for name in ["Cartilage_joint_knee_l","Cartilage_joint_knee_r"]:
    target=bpy.data.objects.get(name)
    assert target is not None,name
    target["elmer_static_reference"]="20kPa top-loaded flat patch; not a solve on this sculpted 3D knee"
    target["elmer_reference_pressure_pa"]=20000.0
    target["elmer_reference_e_pa"]=float(cart["elastic_modulus_pa"])
    target["elmer_reference_soft_e_pa"]=float(cart["soft_material_case"]["elastic_modulus_pa"])
    target["elmer_reference_max_u_m"]=float(cases[-1]["max_displacement_m"])
    target["elmer_reference_max_vm_pa_NOT_USE"]=float(cases[-1]["max_von_mises_pa"])
    target["elmer_corner_stress_unconverged"]=True
    target["elmer_actual_geometry_fem_solver_applied"]=False

blob=bpy.data.texts.get("Elmer_FEM_Reference_v1.json")
if blob is None:
    blob=bpy.data.texts.new("Elmer_FEM_Reference_v1.json")
blob.clear()
blob.write(json.dumps(model,ensure_ascii=False,indent=2))
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(source))

meta_path=ASSET/"meta.json"
meta=json.loads(meta_path.read_text(encoding="utf-8"))
meta["version"]="0.1.2-elmer-material-study"
meta["updated"]=datetime.datetime.now(datetime.timezone.utc).isoformat()
meta["description"]=(
    "Life Simulator 194-bone prototype anatomy, 60 cartilage and muscle proxies, "
    "17 Bullet bodies / 16 constraints, attached reproducible offline Elmer 26.2 "
    "2D stress/compression reference (NOT applied to 3D knee)."
)
meta["files"]=[]
for f in sorted(ASSET.iterdir()):
    if not f.is_file() or f.name=="meta.json":
        continue
    data=f.read_bytes()
    meta["files"].append({
        "path":f.name,
        "bytes":len(data),
        "sha256":hashlib.sha256(data).hexdigest()
    })
meta_path.write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding="utf-8")
print("ELMER_BLENDER_LINK_OK bones=",len(rig.data.bones),
      "cartilage_reference_m=",cases[-1]["max_displacement_m"],
      "soft_reference_m=",cart["soft_material_case"]["max_displacement_m"],
      "json_bytes=",len(blob.as_string()),
      "model_files=",len(meta["files"]))
