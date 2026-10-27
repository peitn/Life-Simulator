extends SceneTree
## Verifies actual ElmerSolver 26.2 run metadata and the bounded offline SI
## response atlas. Does NOT claim to rerun Elmer within Godot's game loop.
const FE := preload("res://scripts/physics/anatomy_fem_atlas.gd")
const PhysicsManifest := "res://docs/anatomy/anatomy-physics-v1.json"

var passed: int = 0
var failed: int = 0
func test(ok: bool, label: String) -> void:
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL "+label)

func close(value: float, expectation: float, tolerance: float) -> bool:
    return is_finite(value) and absf(value-expectation) <= tolerance

func _init() -> void:
    call_deferred("run")

func run() -> void:
    var data: Dictionary = FE.read_atlas()
    test(data.get("schema")=="life-simulator.anatomy.elmer-fem.v1",
        "versioned source is actual Elmer output archive")
    test(data.get("solver")=="ElmerSolver 26.2","solver edition recorded")
    test(data.get("source_model")=="lifesim-anatomy-skeleton-v1",
        "model and FEM solver refer to correct independent Blender asset")
    var units: Dictionary=data.get("si_units",{})
    for unit in ["m","Pa","N","kg"]:
        test(units.values().has(unit),"strict SI units contain "+unit)
    var implementation:Dictionary=data.get("implementation",{})
    test(not bool(implementation.get("live_gameplay_enabled",true))
        and not bool(implementation.get("live_ragdoll_enabled",true))
        and not bool(implementation.get("muscle_activation_implemented",true))
        and not bool(implementation.get("medical_validation",true)),
        "offline, non-medical, unintegrated physics is not misrepresented")
    test(not FE.live_physics_enabled(),"gameplay physics not silently overridden")
    var old_model:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(PhysicsManifest))
    test(not bool(old_model.get("physics_in_live_gameplay",true))
        and int(old_model.get("rig_bones",0))==194,
        "old 194-bone Blender reference remains untouched")

    var beam:Dictionary=data.get("bone_cantilever",{})
    test(close(float(beam.get("length_m",0)),.15,.000001)
        and close(float(beam.get("height_m",0)),.015,.000001),
        "15 cm cortical-like cantilever and 15 mm beam height")
    test(close(float(beam.get("elastic_modulus_pa",0)),15e9,1.0)
        and close(float(beam.get("poisson",0)),.30,.000001),
        "cortical-like isotropic 15 GPa E, nu .30")
    test(close(float(beam.get("density_kg_m3",0)),1900.0,.01),
        "explicit static density not 7800 steel default")
    test(close(float(beam.get("boundary",{}).get("total_force_per_m_extrusion_n",0)),1.5,.00001),
        "100 Pa edge traction is 1.5 N/m extrusion, never 100 N")
    var case_b: Array=beam.get("cases",[])
    test(case_b.size()==3,"coarse/medium/fine Elmer stress and displacement available")
    if case_b.size()==3:
        var analytical:float=float(beam["analytic_euler_bernoulli"]["tip_abs_displacement_m"])
        test(close(analytical,4e-7,1e-11),"independent Euler-Bernoulli sanity")
        var prev_error:=INF
        var prev_points:=0
        var i:=0
        for c in case_b:
            var err:float=absf(float(c["max_displacement_m"])-analytical)/analytical
            test(int(c["points"])>prev_points,"increasing physical mesh dofs "+str(i))
            test(err<prev_error,"fine Elmer beam converges toward analytic "+str(i))
            prev_error=err
            prev_points=int(c["points"])
            i+=1
        test(prev_error<.01,"60x16 Elmer displacement within 1% of analytic beam")
        test(close(float(case_b[2]["max_displacement_m"]),3.98879e-7,1e-12),
            "actual VTU fine max displacement archived, not fabricated")
        var resp:Dictionary=FE.bone_cantilever(100.0)
        test(resp.get("ok",false),"bone lookup accepts reference load")
        test(close(float(resp.get("max_vector_displacement_m",0)),float(case_b[2]["max_displacement_m"]),1e-12),
            "bone atlas returns actual fine-grid Elmer result")
        test(float(resp.get("vertical_displacement_at_vector_max_m",0))<0,
            "downward load produces downward signed y displacement")
        test(close(float(resp.get("analytic_euler_bernoulli_m",0)),analytical,1e-13),
            "analytic reference included in result without mixing units")
    var bone_half:Dictionary=FE.bone_cantilever(50.0)
    test(bone_half.get("ok",false) and close(float(bone_half.get("max_vector_displacement_m",0)),.5*3.98879e-7,1e-12),
        "within validated load range linear beam scaling works")
    test(FE.bone_cantilever(0.0).get("ok",false)
        and is_zero_approx(float(FE.bone_cantilever(0.0).get("max_vector_displacement_m",-1.0))),
        "zero load yields zero modeled displacement")
    for invalid in [-1.0,100.01,INF,NAN]:
        test(not FE.bone_cantilever(invalid).get("ok",false),
            "beam refuses out-of-range and nonfinite loads "+str(invalid))

    var cartilage:Dictionary=data.get("cartilage_compression",{})
    test(close(float(cartilage.get("width_m",0)),.04,.000001)
        and close(float(cartilage.get("depth_m",0)),.003,.000001),
        "cartilage FE geometry is 40 mm by 3 mm rectangular patch")
    test(close(float(cartilage.get("elastic_modulus_pa",0)),5e6,.01)
        and close(float(cartilage.get("poisson",0)),.35,.000001),
        "explicit 5 MPa elastically compressible cartilage simplification")
    var cc:Array=cartilage.get("cases",[])
    test(cc.size()==4,"both load values and two independent mesh refinements")
    if cc.size()==4:
        var u20:float=float(cc[0]["max_displacement_m"])
        var u40:float=float(cc[1]["max_displacement_m"])
        var u20fine:float=float(cc[2]["max_displacement_m"])
        var u20ultra:float=float(cc[3]["max_displacement_m"])
        test(close(u20,1.48176e-5,1e-10),"20 kPa VTU result recorded")
        test(close(u40,2.96352e-5,1e-10),"40 kPa VTU result recorded")
        test(close(u20fine,1.49233e-5,1e-10),"fine VTU response recorded")
        test(close(u20ultra,1.49443e-5,1e-10),"ultrafine real VTU 120x24 response recorded")
        test(absf(u40/u20-2.0)<.00001,"doubling pressure doubles displacement")
        test(absf(u20fine/u20-1.0)<.015,
            "cartilage global compliance converges within 1.5% under refinement")
        test(absf(u20ultra/u20fine-1.0)<.005,
            "ultrafine stress displacement further converges within 0.5%")
        test(float(cc[2]["max_von_mises_pa"])>float(cc[0]["max_von_mises_pa"])*1.19
            and float(cc[3]["max_von_mises_pa"])>float(cc[2]["max_von_mises_pa"])*1.10,
            "peak corner stress grows across three meshes and is NOT a clinical failure criterion")
        var out:Dictionary=FE.cartilage_compression(20000.0)
        test(out.get("ok",false) and close(float(out.get("max_vector_displacement_m",0)),u20ultra,1e-10),
            "lookup anchored to genuine fine-grid result")
        test(float(out.get("vertical_displacement_at_vector_max_m",0))<0
            and absf(float(out.get("vertical_displacement_at_vector_max_m",0)))<
                 float(out.get("max_vector_displacement_m",0)),
            "vertical displacement correctly distinguished from vector norm")
        test(not bool(out.get("peak_stress_usable",true))
            and bool(out.get("offline_lookup_only",false))
            and not bool(out.get("live_ragdoll_physics",true)),
            "unsafe peak stress and realtime physics claims explicitly blocked")
        var at40:Dictionary=FE.cartilage_compression(40000.0)
        test(at40.get("ok",false) and close(float(at40.get("max_vector_displacement_m",0)),u20ultra*2.0,1e-10),
            "fine-grid interpolation follows validated pressure linearity")
        var at10:Dictionary=FE.cartilage_compression(10000.0)
        test(at10.get("ok",false) and close(float(at10.get("max_vector_displacement_m",0)),u20ultra*.5,1e-10),
            "bounded elastic interpolation at 10 kPa")
    var soft:Dictionary=cartilage.get("soft_material_case",{})
    test(soft.get("name")=="lifesim_cartilage_soft_c9",
        "independent 2.5 MPa Elmer stiffness perturbation actually executed")
    test(close(float(soft.get("max_displacement_m",0)),2.96352e-5,1e-10),
        "Elmer E/2 => exact twice reference coarse-grid displacement")
    test(close(float(soft.get("max_von_mises_pa",0)),float(cc[0]["max_von_mises_pa"]),1e-4),
        "for traction BC and linear elastic E change, stress pattern remains the same")
    var soft_response:Dictionary=FE.cartilage_compression(20000.0,2500000.0)
    test(soft_response.get("ok",false),"tested soft E=2.5 MPa admitted")
    test(absf(float(soft_response.get("max_vector_displacement_m",0))/float(soft["max_displacement_m"])-1.0)<.015,
        "ultrafine offline surrogate agrees with independently solved soft-mesh case within 1.5%")
    var halfway:Dictionary=FE.cartilage_compression(20000.0,3750000.0)
    test(halfway.get("ok",false) and float(halfway.get("max_vector_displacement_m",0))<
        float(soft_response.get("max_vector_displacement_m",0)),
        "stiffer cartilage deforms less inside tested linear E interval")
    for invalid_e in [0.0,-1.0,2499999.9,5000000.1,INF,NAN]:
        test(not FE.cartilage_compression(20000.0,invalid_e).get("ok",false),
            "unsafe untested E values and NaN explicitly rejected "+str(invalid_e))
    for invalid in [-.001,40000.001,INF,NAN]:
        test(not FE.cartilage_compression(invalid).get("ok",false),
            "cartilage rejects negative, extrapolation, infinities "+str(invalid))
    test(FE.cartilage_compression(0.0).get("ok",false)
        and is_zero_approx(float(FE.cartilage_compression(0.0).get("max_vector_displacement_m",-1))),
        "zero compression -> zero modeled displacement")

    var bone_sif:String=FileAccess.get_file_as_string("res://tools/elmer/bone_cantilever_v1.sif")
    var cartilage_sif:String=FileAccess.get_file_as_string("res://tools/elmer/cartilage_compression_v1.sif")
    test(bone_sif.contains("Youngs Modulus = 15000000000") and
        bone_sif.contains("Force 2 = -100.0") and bone_sif.contains("Plane Stress = Logical True"),
        "reproducible cortical Elmer SIF uses correct material and traction")
    test(cartilage_sif.contains("Youngs Modulus = 5000000") and
        cartilage_sif.contains("Target Boundaries(1) = 1") and
        cartilage_sif.contains("Target Boundaries(1) = 3") and
        cartilage_sif.contains("Force 2 = -20000.0"),
        "cartilage SIF fixes bottom and compresses top with correct edge groups")
    print("ELMER_ATLAS_VALIDATION checks=",passed+failed,
        " pass=",passed," fail=",failed)
    quit(0 if failed==0 else 1)