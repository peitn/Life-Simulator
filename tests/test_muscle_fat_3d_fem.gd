extends SceneTree
## Tests real isolated ElmerSolver 26.2 3D Hex8 results and honest boundary
## with existing 2D benchmarks. No step here runs a live avatar solver.
const FEM := preload("res://scripts/physics/muscle_fat_fem_3d_reference.gd")
const TWO_D := "res://docs/anatomy/elmer_muscle_fat_v1.json"

var passed := 0
var failed := 0

func expect(condition: bool, label: String) -> void:
    if condition:
        passed += 1
    else:
        failed += 1
        print("FAIL "+label)


func near(a: float, b: float, epsilon: float) -> bool:
    return is_finite(a) and is_finite(b) and absf(a-b) <= epsilon


func _init() -> void:
    call_deferred("run")


func run() -> void:
    var d: Dictionary = FEM.evidence()
    expect(d.get("schema")=="lifesim.fem.musclefat.3d.v1",
        "versioned 3D material Elmer FEM results source")
    expect(d.get("solver")=="ElmerSolver 26.2",
        "true remote Elmer solver revision")
    expect(d.get("mesher")=="ElmerGrid 14 2 ASCII Gmsh 2.2",
        "real supported Gmsh to ElmerGrid 3D mesh converter")
    expect(not FEM.model_is_live_gameplay(),
        "none of the FEM calculations silently enable production physics")
    var limitations: Dictionary=d.get("limitations",{})
    expect(bool(limitations.get("actual_3D_hex8_FEM_solved",false)),
        "results are actual Elmer 3D hexahedral FEM and not a 2D picture")
    for key in ["actual_anatomy_Blendermodel_geometry_solved","not_clinical",
        "not_pennes_blood_perfusion","not_muscle_activation",
        "not_live_gameplay_physics","not_full_3D_joint_physics",
        "geometry_flat_research_blocks_only"]:
        expect(limitations.get(key)==(key!="actual_anatomy_Blendermodel_geometry_solved"),
            "explicit truthful 3D scope/limitation "+key)
    var mesh: Dictionary=d.get("geometry",{})
    expect(mesh.get("physical_body_ids",{}).get("muscle")==1 and
           mesh.get("physical_body_ids",{}).get("fat")==2,
        "3D conforming bulk domains use two physical material IDs")
    var bc:Dictionary=mesh.get("physical_boundary_ids",{})
    expect(bc.get("core")==11 and bc.get("skin")==12 and bc.get("insulated_sides")==13,
        "3D physical boundary IDs preserve thermal BCs")
    expect(near(float(mesh.get("muscle_thickness_m",0)),.025,1e-10) and
           near(float(mesh.get("fat_thickness_m",0)),.01,1e-10),
        "two volumetric soft tissues occupy correct 25+10 mm depths")
    expect(near(float(mesh.get("width_m",0)),.012,1e-10) and
           near(float(mesh.get("depth_m",0)),.010,1e-10),
        "3D block has two independent transverse space dimensions")
    var thermal: Dictionary=d.get("thermal",{})
    expect(near(float(thermal.get("k_muscle_W_mK",0)),.5,.000001),
        "muscle conductivity same as prior 2D Elmer")
    expect(near(float(thermal.get("k_fat_W_mK",0)),.2,.000001),
        "fat conductivity same as prior 2D Elmer")
    expect(near(float(thermal.get("rho_muscle_kg_m3",0)),1050.0,.00001) and
           near(float(thermal.get("rho_fat_kg_m3",0)),900.0,.00001),
        "density explicitly used to normalize Elmer specific heat source")
    expect(near(float(thermal.get("cp_muscle_J_kgK",0)),3750.0,.00001) and
           near(float(thermal.get("cp_fat_J_kgK",0)),2300.0,.00001),
        "3D BDF transient materials include true specific heat capacities")
    expect(near(float(thermal.get("core_K",0)),310.15,.00001) and
           near(float(thermal.get("air_K",0)),293.15,.00001) and
           near(float(thermal.get("surface_heat_transfer_W_m2K",0)),10.0,.00001),
        "37C core and 20C ambient with Robin h=10 W/m2K")
    expect(not bool(thermal.get("volumetric_source_elmer_conversion","").is_empty()),
        "Elmer W/kg heat source normalization was applied")
    var cases: Array=d.get("cases",[])
    expect(cases.size()==5,"five independent actual 3D solver cases stored")
    for i in cases.size():
        var c:Dictionary=cases[i]
        expect(FEM.APPROVED_CASES.has(String(c.get("name"))),
            "only known solved 3D cases included "+str(i))
        expect(int(c.get("points",0))>0 and int(c.get("bulk_hex8",0))>0,
            "case contains actual 3D volume cells "+str(i))
        expect(c.get("filename","").ends_with(".vtu"),
            "real VTU output file recorded "+str(i))
        expect(int(c.get("nm",0))>=4 and int(c.get("nf",0))>=2,
            "each material has independently meshed thickness "+str(i))
    var rest:Dictionary=FEM.solved_case("lifesim_mfat_3d_heat_coarse_c11")
    var fine:Dictionary=FEM.solved_case("lifesim_mfat_3d_heat_fine_c11")
    var active:Dictionary=FEM.solved_case("lifesim_mfat_3d_active_c11")
    var transient:Dictionary=FEM.solved_case("lifesim_mfat_3d_transient_c11")
    var mech:Dictionary=FEM.solved_case("lifesim_mfat_3d_mech_c11")
    for c in [rest,fine,active,transient,mech]:
        expect(c.get("ok",false),"read-only API exposes genuine one-case evidence")
        expect(not bool(c.get("live_physics",true)),
            "3D FEM reader prevents live game physics claim")
        expect(c.get("scope")=="offline_3D_flat_two_tissue_slab_not_Blendermodel",
            "no misidentification of 3D rectangular FEM with Blender anatomy")
    expect(rest.get("points")==208 and rest.get("bulk_hex8")==108 and
           rest.get("boundary_quad4")==162,
        "Gmsh coarse volume mesh is 208 nodes, 108 Hex8 and 162 boundary Quad4")
    expect(fine.get("points")==900 and fine.get("bulk_hex8")==600 and
           fine.get("boundary_quad4")==530,
        "real mesh refinement uses 900 nodes 600 Hex8 530 external faces")
    expect(int(fine["points"])>int(rest["points"])*4,
        "real 3D finite-element spatial refinement (not same mesh)")
    expect(near(float(rest.get("min_K",0)),301.89125,.00001),
        "208-node Elmer VTU skin temperature matches independent 1D analytic")
    expect(near(float(fine.get("min_K",0)),301.89125,.00001),
        "900-node Elmer VTU preserves true skin temperature under 3D refinement")
    expect(near(float(fine.get("max_K",0)),310.15,.00001),
        "rest case core maximum remains physically bounded")
    var analytic:Dictionary=FEM.comparison_with_1d_rest()
    expect(analytic.get("ok",false) and int(analytic.get("verified_grid_nodes",0))==900,
        "analytic 1D vs actual refined Elmer3D result response")
    expect(near(float(analytic.get("absolute_error_kelvin",NAN)),0,.00001),
        "3D rest Elmer solution satisfies separate 1D heat balance")
    expect(active.get("points")==208 and active.get("source_muscle_W_m3")==5000,
        "active muscle heat source is deliberate 5k W/m3 scenario")
    expect(near(float(active.get("min_K",0)),303.235,.001),
        "3D active Elmer skin temperature 30.085C")
    expect(float(active["min_K"])>float(rest["min_K"]),
        "greater internal muscular heat increases outer tissue surface T")
    expect(near(float(active.get("max_K",0)),310.264,.005),
        "3D active thermal maximum plausible and not runaway >600K")
    expect(transient.get("time_s")==720 and transient.get("step_s")==60 and
           transient.get("bdf_order")==1,
        "12 explicit elapsed minutes solved in 3D transient BDF1")
    expect(near(float(transient.get("min_K",0)),304.684,.001),
        "3D thermal capacitance delays skin cooling at 720 seconds")
    expect(float(transient["min_K"])>float(rest["min_K"]),
        "transient surface has not yet equilibrated to steady 28.74C")
    expect(mech.get("points")==208 and mech.get("traction_pa")==100,
        "3D linear elastic mechanics is actual -100Pa traction, not -100N")
    expect(near(float(mech.get("max_vector_displacement_m",0)),.000282131,1e-9),
        "actual 3D displacement vector max ~0.282131mm")
    expect(near(float(mech.get("max_von_mises_pa",0)),136.307,.005),
        "actual 3D von Mises max for unvalidated elastic block")
    expect(absf(float(mech.get("max_vector_displacement_m",0))/
        float(mech.get("uniaxial_1d_reference_m",0))-1.0)<.02,
        "3D passive FE close to 1D muscle-fat series compression within 2%")
    var vec:Array=mech.get("max_vector_components_m",[])
    expect(vec.size()==3,"actual 3D displacement vector has 3 Cartesian components")
    if vec.size()==3:
        var mag=sqrt(float(vec[0])*float(vec[0])+
            float(vec[1])*float(vec[1])+float(vec[2])*float(vec[2]))
        expect(near(mag,float(mech["max_vector_displacement_m"]),.000003),
            "reported maximum displacement is vector magnitude, not x-only")
        expect(float(vec[0])<0 and float(vec[1])<0 and float(vec[2])<0,
            "signed material strain present on all axes in selected VTU point")
    var twoD: Variant=JSON.parse_string(FileAccess.get_file_as_string(TWO_D))
    expect(typeof(twoD)==TYPE_DICTIONARY,"prior 2D Elmer model available as benchmark")
    if typeof(twoD)==TYPE_DICTIONARY:
        var prev_cases:Array=twoD.get("cases",[])
        var prev_therm:float=NAN
        var prev_mech:float=NAN
        for c in prev_cases:
            if c.get("name")=="lifesim_mfat_heat_rest_t10":
                prev_therm=float(c.get("temperature_min_K",NAN))
            if c.get("name")=="lifesim_mfat_mech_t10":
                prev_mech=float(c.get("measured_max_vector_displacement_m",NAN))
        expect(near(prev_therm,float(rest["min_K"]),.002),
            "new real 3D heat agrees with independently executed 2D baseline")
        expect(is_finite(prev_mech) and
            absf(prev_mech/float(mech["max_vector_displacement_m"])-1)<.035,
            "new real 3D 3-axis compression agrees with 2D baseline within 3.5%")
    expect(not FEM.solved_case("../../etc/passwd").get("ok",false),
        "reader cannot perform arbitrary filename lookup")
    expect(not FEM.solved_case("").get("ok",false),
        "missing/unnamed cases explicitly rejected")
    expect(FileAccess.file_exists("res://tools/elmer/build_muscle_fat_3d_v1.py"),
        "reproducible actual 3D Gmsh hex8 mesher and .sif generator source saved")
    expect(FileAccess.file_exists("res://tools/blender/anatomy_elmer_3d_field_visual_v1.py"),
        "true VTU node data mapped to separate Blender 3D preview source saved")
    expect(not bool(analytic.get("medical_model",true)) and
           bool(analytic.get("model_not_actual_anatomical_geometry",false)),
        "explicitly refuses to call rectangular slab an anatomical human body")
    print("MUSCLE_FAT_ELMER_3D_TEST pass=",passed,
        " fail=",failed," assertions=",passed+failed)
    quit(0 if failed==0 else 1)
