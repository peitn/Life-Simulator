extends SceneTree
## Real Elmer 26.2 VTU evidence, two-body material SI, heat source MASS
## normalization, true heat capacities in transient, biomech stress scope.
const Ref := preload("res://scripts/physics/muscle_fat_thermal_reference.gd")
var passed := 0
var failed := 0

func ok(condition: bool, description: String) -> void:
    if condition:
        passed += 1
    else:
        failed += 1
        print("FAIL "+description)


func near(a: float, b: float, tol: float) -> bool:
    return is_finite(a) and is_finite(b) and absf(a-b) <= tol


func _init() -> void:
    call_deferred("run")


func run() -> void:
    var d: Dictionary = Ref.atlas()
    ok(d.get("schema") == "lifesim.fem.musclefat.v1", "versioned Elmer muscle fat research model")
    ok(d.get("solver") == "ElmerSolver 26.2", "actual Elmer solver metadata")
    ok(d.get("blender_asset") == "lifesim-anatomy-skeleton-v1", "separate Blender asset")
    ok(not Ref.is_production_physics(), "this is not silently production ragdoll simulation")
    var flags: Dictionary = d.get("flags", {})
    for name in ["full_3d_anatomical_mesh_solved","actual_muscle_fiber_contraction",
                "adipose_nonlin_compression","explicit_blood_perfusion",
                "live_gameplay_physics","medical_model"]:
        ok(flags.get(name) == false, "honest unsupported feature "+name)
    for name in ["actual_solver_runs","VTU_emitted","validated_against_analytic",
                "transient_specific_heat_solved"]:
        ok(flags.get(name) == true, "correct recorded successful solver feature "+name)
    var info: Dictionary = d.get("methodology", {})
    var thermal: Dictionary = info.get("thermal", {})
    ok(near(float(thermal.get("k_muscle_W_mK",0)),0.5,1e-10),
        "muscle reference thermal conductivity .5 W/mK")
    ok(near(float(thermal.get("k_adipose_W_mK",0)),0.2,1e-10),
        "fat reference conductivity .2 W/mK")
    ok(near(float(thermal.get("density_muscle_kg_m3",0)),1050,1e-10),
        "muscle density in source normalization")
    ok(near(float(thermal.get("density_fat_kg_m3",0)),900,1e-10),
        "fat density in source normalization")
    ok(near(float(thermal.get("specific_heat_muscle_J_kgK",0)),3750,1e-10),
        "transient muscle Cp is real")
    ok(near(float(thermal.get("specific_heat_fat_J_kgK",0)),2300,1e-10),
        "transient fat Cp is real")
    ok(near(float(thermal.get("core_temp_K",0)),310.15,1e-10),
        "37 C core boundary")
    ok(near(float(thermal.get("ambient_temp_K",0)),293.15,1e-10),
        "20 C ambient boundary")
    var cases: Array=d.get("cases", [])
    ok(cases.size()==6, "3 steady base variants, fine mesh, dynamic and mechanical studies")
    var expected:Dictionary={
        "lifesim_mfat_heat_rest_t10":[301.891,310.15,147],
        "lifesim_mfat_heat_active_t10":[303.235,310.269,147],
        "lifesim_mfat_heat_thickfat_t10":[300.173,310.15,203],
        "lifesim_mfat_heat_fine_t10":[301.891,310.15,369]
    }
    for c in cases:
        ok(bool(c.get("solver_ok",false)) and c.get("output_vtu")=="case_t0001.vtu",
            "real Elmer VTU solver output "+str(c.get("name")))
        var name:String=str(c.get("name"))
        if expected.has(name):
            var row:Array=expected[name]
            ok(near(float(c.get("temperature_min_K",0)),float(row[0]),.002),
                "steady skin temperature matches actual VTU "+name)
            ok(near(float(c.get("temperature_max_K",0)),float(row[1]),.002),
                "real maximum temperature of muscle+fat "+name)
            ok(int(c.get("points",0))==int(row[2]),"actual mesh nodes "+name)
            var theory:Dictionary=c.get("analytic",{})
            ok(near(float(theory.get("surface_K",0)),float(row[0]),.005),
                "Elmer surface BC matches multilayer generated 1D analytic "+name)
            ok(near(float(theory.get("maximum_K",0)),float(row[1]),.006),
                "Elmer peak matches 1D volumetric source analytic "+name)
    var rest:Dictionary=Ref.steady_reference(700.0,.010)
    ok(rest.get("ok",false),"read-only thermodynamics reports rest case")
    ok(near(float(rest.get("skin_temperature_K",0)),301.89125,.001),
        "rest skin 28.74125 C")
    ok(near(float(rest.get("muscle_fat_interface_K",0)),306.246875,.001),
        "muscle-fat junction continuity")
    ok(near(float(rest.get("outward_heat_flux_W_m2",0)),87.4125,.001),
        "conduction and Robin convection heat flux")
    var active:Dictionary=Ref.steady_reference(5000.0,.010)
    ok(active.get("ok",false) and near(float(active.get("skin_temperature_K",0)),303.235,.001),
        "muscle activation causes 30.085 C surface in benchmark")
    ok(float(active["maximum_temperature_K"])>310.15,
        "muscle heat production can create interior peak slightly above fixed core")
    var thick:Dictionary=Ref.steady_reference(700.0,.020)
    ok(thick.get("ok",false) and near(float(thick.get("skin_temperature_K",0)),300.173,.001),
        "doubling fat thickness cools exposed surface to 27.023 C")
    ok(float(thick["skin_temperature_K"])<float(rest["skin_temperature_K"]),
        "greater fat thickness provides more insulation in this fixed-core setup")
    ok(float(active["skin_temperature_K"])>float(rest["skin_temperature_K"]),
        "additional metabolic muscle heat increases skin surface temperature")
    ok(not bool(rest.get("live_physics",true)),
        "analytic-to-Elmer thermal sample is not game character thermoregulation")
    var temp:Dictionary=Ref.transient_twelve_minute_reference()
    ok(temp.get("ok",false) and int(temp.get("elapsed_seconds",0))==720,
        "actual 12x60sec transient BDF simulation available")
    ok(near(float(temp.get("min_temperature_K",0)),304.685,.002),
        "12 minute skin has not reached 301.891 K equilibrium")
    ok(near(float(temp.get("max_temperature_K",0)),310.169,.002),
        "transient internal volume heat storage captured")
    ok(float(temp["min_temperature_K"])>float(rest["skin_temperature_K"]),
        "transient surface remains warmer than steady state")
    var mech:Dictionary=Ref.passive_skin_compression(100.0)
    ok(mech.get("ok",false),"linear elastic passive muscle-fat FE sample")
    ok(near(float(mech.get("max_vector_displacement_m",0)),.000285811,.00000001),
        "real Elmer full displacement norm 0.285811 mm")
    ok(absf(float(mech.get("max_vector_displacement_m",0))/
        float(mech.get("reference_1d_series_displacement_m",1))-1) < .015,
        "FEM vs simple 1D muscle-fat series compression within 1.5%")
    ok(not bool(mech.get("muscle_contraction",true)),
        "passive FEM is not active Hill-type muscle dynamics")
    var half:Dictionary=Ref.passive_skin_compression(50.0)
    ok(half.get("ok",false) and near(float(half.get("max_vector_displacement_m",0)),
        .000285811*.5,1e-9),"bounded linear 50Pa lookup scales correctly")
    for bad in [-1.0,100.001,NAN,INF]:
        ok(not Ref.passive_skin_compression(bad).get("ok",false),
            "reject invalid mechanical pressure "+str(bad))
    for bad in [-1.0,699.99,5000.001,NAN,INF]:
        ok(not Ref.steady_reference(bad,.010).get("ok",false),
            "reject unsupported muscle heat source "+str(bad))
    for bad in [.001,.00999,.020001,NAN,INF]:
        ok(not Ref.steady_reference(700.0,bad).get("ok",false),
            "reject untested adipose thickness "+str(bad))
    for p in ["muscle_fat_thermal_rest_v1.sif","muscle_fat_thermal_active_v1.sif",
        "muscle_fat_thermal_thickfat_v1.sif","muscle_fat_compression_v1.sif"]:
        ok(FileAccess.file_exists("res://tools/elmer/"+p),
            "reproducible source Elmer SIF "+p)
    ok(FileAccess.file_exists("res://tools/elmer/build_muscle_fat_v1.py"),
        "fully reproducible 2D mesh + SIF generator")
    var source_sif:String=FileAccess.get_file_as_string("res://tools/elmer/muscle_fat_thermal_rest_v1.sif")
    ok(source_sif.contains("Heat Source = 0.666666666667")
        and source_sif.contains("Heat Source = 0.066666666667"),
        "volumetric production is normalized by density to W/kg in Elmer SIF")
    ok(source_sif.contains("Heat Transfer Coefficient = 10")
        and source_sif.contains("External Temperature = 293.15"),
        "nontrivial Robin air cooling BC actually specified")
    ok(source_sif.contains("Heat Capacity = 3750")
        and source_sif.contains("Heat Capacity = 2300"),
        "specific heat present for actual 12-step thermal time integration")
    print("MUSCLE_FAT_ELMER_TEST pass=",passed," fail=",failed,
        " assertions=",passed+failed)
    quit(0 if failed==0 else 1)
