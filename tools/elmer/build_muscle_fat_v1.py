#!/usr/bin/env python3
"""Reproducible isolated two-domain ElmerFEM muscle/fat research benchmark.

Usage: python3 tools/elmer/build_muscle_fat_v1.py --out /tmp/ls-muscle-fat-v1
Emits Elmer legacy mesh + case.sif for independent 2D plane-stress elasticity,
steady thermal conduction and transient thermal diffusion. Units SI.

This is NOT segmentation of the 3D Blender character, not a Pennes model
(no blood perfusion), not active muscle contraction, and not a 60Hz engine.
"""
from pathlib import Path
import argparse
import json
import math

L_MUSCLE=.025
L_FAT=.010
HEIGHT=.012
CORE_T_K=310.15
AIR_T_K=293.15
H_CONVECTION=10.0
K_MUSCLE=.50
K_FAT=.20
RHO_MUSCLE=1050.0
RHO_FAT=900.0
CP_MUSCLE=3750.0
CP_FAT=2300.0

def emit_mesh(folder:Path,fat_thickness=.01,nm=12,nf=8,ny=6):
    assert nm>=4 and nf>=4 and ny>=2
    assert 0.003 <= fat_thickness <= .025
    xs=[i*L_MUSCLE/nm for i in range(nm+1)]
    xs += [L_MUSCLE+(i+1)*fat_thickness/nf for i in range(nf)]
    nx=nm+nf
    node=lambda i,j:1+j*(nx+1)+i
    cell=lambda i,j:1+j*nx+i
    nodes=[]
    for j in range(ny+1):
        for i in range(nx+1):
            nodes.append(f"{node(i,j)} -1 {xs[i]:.12f} {j*HEIGHT/ny:.12f} 0")
    elems=[]
    for j in range(ny):
        for i in range(nx):
            elems.append(f"{cell(i,j)} {1 if i<nm else 2} 404 "
                         f"{node(i,j)} {node(i+1,j)} {node(i+1,j+1)} {node(i,j+1)}")
    edges=[]
    def append(bid,parent,a,b):
        edges.append(f"{len(edges)+1} {bid} {parent} 0 202 {a} {b}")
    for i in range(nx):append(1,cell(i,0),node(i,0),node(i+1,0))
    for j in range(ny):append(2,cell(nx-1,j),node(nx,j),node(nx,j+1))
    for i in range(nx):append(3,cell(i,ny-1),node(i+1,ny),node(i,ny))
    for j in range(ny):append(4,cell(0,j),node(0,j+1),node(0,j))
    folder.mkdir(parents=True,exist_ok=True)
    header=f"{len(nodes)} {len(elems)} {len(edges)}\n2\n404 {len(elems)}\n202 {len(edges)}\n"
    for name,content in [("mesh.header",header),("mesh.nodes","\n".join(nodes)+"\n"),
                         ("mesh.elements","\n".join(elems)+"\n"),
                         ("mesh.boundary","\n".join(edges)+"\n")]:
        (folder/name).write_text(content)
    assert len(nodes)==(nx+1)*(ny+1)
    assert len(elems)==nx*ny
    assert len(edges)==2*nx+2*ny
    return {"nx":nx,"ny":ny,"nodes":len(nodes),"elements":len(elems),
            "muscle_thickness_m":L_MUSCLE,"fat_thickness_m":fat_thickness,
            "interface_x_m":L_MUSCLE}

def sif_heat(qmuscle_w_m3=700.0,qfat_w_m3=60.0,transient=False):
    # Elmer Heat Source is MASS-specific (W/kg), not volumetric W/m3.
    # First uncorrected trial omitted /density and produced >600 Kelvin.
    # Retain this in source and test against closed-form 1D profile.
    assert 0<=qmuscle_w_m3<=10000 and 0<=qfat_w_m3<=1000
    simtype=("Transient\n Timestepping Method = BDF\n BDF Order = 1\n"
             " Timestep Intervals(1) = 12\n Timestep Sizes(1) = 60.0") if transient else "Steady State"
    ic=" Initial Condition = 1" if transient else ""
    initial="Initial Condition 1\n Temperature = 310.15\nEnd" if transient else ""
    return f"""Header
 Mesh DB "." "."
End
Simulation
 Max Output Level = 4
 Coordinate System = Cartesian 2D
 Simulation Type = {simtype}
 Steady State Max Iterations = 1
 Output Intervals = 1
End
Body 1
 Name = "skeletal_muscle"
 Equation = 1
 Material = 1
 Body Force = 1
{ic}
End
Body 2
 Name = "subcutaneous_adipose"
 Equation = 1
 Material = 2
 Body Force = 2
{ic}
End
Equation 1
 Active Solvers(2) = 1 2
End
Solver 1
 Equation = "Heat Equation"
 Procedure = "HeatSolve" "HeatSolver"
 Variable = Temperature
 Linear System Solver = Direct
 Linear System Direct Method = Banded
 Steady State Convergence Tolerance = 1.0e-10
End
Solver 2
 Exec Solver = After Simulation
 Equation = "ResultOutput"
 Procedure = "ResultOutputSolve" "ResultOutputSolver"
 Output File Name = case
 Vtu Format = Logical True
 Binary Output = Logical False
 Single Precision = Logical False
End
Material 1
 Name = "muscle"
 Heat Conductivity = {K_MUSCLE}
 Density = {RHO_MUSCLE}
 Heat Capacity = {CP_MUSCLE}
End
Material 2
 Name = "fat"
 Heat Conductivity = {K_FAT}
 Density = {RHO_FAT}
 Heat Capacity = {CP_FAT}
End
Body Force 1
 Heat Source = {qmuscle_w_m3/RHO_MUSCLE:.12f}
End
Body Force 2
 Heat Source = {qfat_w_m3/RHO_FAT:.12f}
End
Boundary Condition 1
 Name = "core_310K"
 Target Boundaries(1) = 4
 Temperature = {CORE_T_K}
End
Boundary Condition 2
 Name = "skin_Robin"
 Target Boundaries(1) = 2
 Heat Transfer Coefficient = {H_CONVECTION}
 External Temperature = {AIR_T_K}
End
Boundary Condition 3
 Name = "bottom_adiabatic"
 Target Boundaries(1) = 1
End
Boundary Condition 4
 Name = "top_adiabatic"
 Target Boundaries(1) = 3
End
{initial}
"""

def sif_mechanical():
    return """Header
 Mesh DB "." "."
End
Simulation
 Coordinate System = Cartesian 2D
 Simulation Type = Steady State
 Steady State Max Iterations = 1
 Output Intervals = 1
End
Body 1
 Name = "passive_muscle"
 Equation = 1
 Material = 1
End
Body 2
 Name = "passive_fat"
 Equation = 1
 Material = 2
End
Equation 1
 Active Solvers(2) = 1 2
 Plane Stress = Logical True
End
Solver 1
 Equation = "Linear elasticity"
 Procedure = "StressSolve" "StressSolver"
 Variable = -dofs 2 Displacement
 Calculate Stresses = Logical True
 Linear System Solver = Direct
 Linear System Direct Method = Banded
End
Solver 2
 Exec Solver = After Simulation
 Equation = "ResultOutput"
 Procedure = "ResultOutputSolve" "ResultOutputSolver"
 Output File Name = case
 Vtu Format = Logical True
 Binary Output = Logical False
 Single Precision = Logical False
End
Material 1
 Name = "passive_muscle_isotropic_surrogate"
 Youngs Modulus = 30000.0
 Poisson Ratio = 0.35
 Density = 1050
End
Material 2
 Name = "passive_fat_isotropic_surrogate"
 Youngs Modulus = 5000.0
 Poisson Ratio = 0.35
 Density = 900
End
Boundary Condition 1
 Name = "fixed_core"
 Target Boundaries(1) = 4
 Displacement 1 = 0
 Displacement 2 = 0
End
Boundary Condition 2
 Name = "100Pa_pressure_on_skin"
 Target Boundaries(1) = 2
 Force 1 = -100.0
End
"""

def analytic_thermal(qm,qf,Lf):
    lm=L_MUSCLE;km=K_MUSCLE;kf=K_FAT;h=H_CONVECTION
    R=lm/km+Lf/kf+1/h
    f0=(CORE_T_K-AIR_T_K - qm*lm*lm/(2*km)
        -qm*lm*Lf/kf-qf*Lf*Lf/(2*kf)
        -(qm*lm+qf*Lf)/h)/R
    surface_flux=f0+qm*lm+qf*Lf
    skin_T=AIR_T_K+surface_flux/h
    interface_T=CORE_T_K-(f0*lm+.5*qm*lm*lm)/km
    return {"skin_temperature_K":skin_T,"interface_temperature_K":interface_T,
            "heat_flux_W_m2":surface_flux}

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--out",type=Path,default=Path("/tmp/lifesim-muscle-fat-elmer-v1"))
    args=parser.parse_args()
    cases=[
        ("lifesim_mfat_heat_rest_t10",700,60,.010,12,8,6,False,False),
        ("lifesim_mfat_heat_active_t10",5000,60,.010,12,8,6,False,False),
        ("lifesim_mfat_heat_thickfat_t10",700,60,.020,12,16,6,False,False),
        ("lifesim_mfat_heat_fine_t10",700,60,.010,24,16,8,False,False),
        ("lifesim_mfat_thermal_transient_t10",700,60,.010,12,8,6,True,False),
        ("lifesim_mfat_mech_t10",0,0,.010,12,8,6,False,True)]
    results=[]
    for name,qm,qf,lf,nm,nf,ny,trans,mechanical in cases:
        folder=args.out/name
        geom=emit_mesh(folder,lf,nm,nf,ny)
        (folder/"case.sif").write_text(sif_mechanical() if mechanical else sif_heat(qm,qf,trans))
        results.append({"name":name,**geom,"mode":"elasticity" if mechanical else "bioheat",
                        "analytic":None if mechanical else analytic_thermal(qm,qf,lf)})
    (args.out/"generated_cases.json").write_text(json.dumps(results,indent=2))
    print("MUSCLEFAT_CASE_GENERATION_OK",json.dumps([{"name":x["name"],"nodes":x["nodes"]} for x in results]))

if __name__=="__main__":
    main()
