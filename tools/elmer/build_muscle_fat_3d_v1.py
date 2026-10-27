#!/usr/bin/env python3
"""Reproducible **real 3D** two-domain FEM bench for Elmer 26.2.

Produces valid ASCII Gmsh 2.2 Hex8 muscle+fat conforming shared interface,
four-sided insulated boundary shell, core Dirichlet, skin Robin or traction,
with separate 3D static/passive mechanical and transient thermal SIF files.

This 3D numerical test is still a FLAT RECTANGULAR slab, not the actual
Blender anatomy surface or human physiology. No elastomer contact, blood
perfusion, muscle activation, capillary water flow or game runtime enabled.

Run:
  python3 tools/elmer/build_muscle_fat_3d_v1.py --out /tmp/mf-3d-ref --nx-muscle 8 --nx-fat 4 --ny 3 --nz 3
  cd /tmp/mf-3d-ref; ElmerGrid 14 2 mesh.msh && ElmerSolver case.sif
Units: SI m, N, Pa, W, K, s; 'Heat Source' in this Elmer setup is W/kg,
so convert from input volumetric W/m3 by dividing by rho.
"""
import argparse
import json
from pathlib import Path

LM=.025
LF=.010
WIDTH=.012
DEPTH=.010
K_MUSCLE=.5
K_FAT=.2
RHO_M=1050.0
RHO_F=900.0
CP_M=3750.0
CP_F=2300.0

def generate_gmsh_hex8(nm:int=8,nf:int=4,ny:int=3,nz:int=3) -> tuple[str,dict]:
    assert 4<=nm<=96 and 2<=nf<=64 and 2<=ny<=32 and 2<=nz<=32
    nx=nm+nf
    xs=[LM*i/nm for i in range(nm+1)]+[LM+LF*(i+1)/nf for i in range(nf)]
    node=lambda i,j,k:1+i+(nx+1)*(j+(ny+1)*k)
    verts=[]
    for k in range(nz+1):
        for j in range(ny+1):
            for i in range(nx+1):
                verts.append(f"{node(i,j,k)} {xs[i]:.10f} {WIDTH*j/ny:.10f} {DEPTH*k/nz:.10f}")
    elements=[]
    def put(kind:int,physical:int,vertices:list[int]):
        eid=len(elements)+1
        elements.append(f"{eid} {kind} 2 {physical} {physical} "+" ".join(map(str,vertices)))

    # Hex8 local node order: square z-bottom CCW then z-top CCW.
    for k in range(nz):
        for j in range(ny):
            for i in range(nx):
                put(5,1 if i<nm else 2,[
                    node(i,j,k),node(i+1,j,k),node(i+1,j+1,k),node(i,j+1,k),
                    node(i,j,k+1),node(i+1,j,k+1),node(i+1,j+1,k+1),node(i,j+1,k+1)])

    # Boundary Physical 11 core; 12 skin; 13 four other insulated faces.
    for k in range(nz):
        for j in range(ny):
            put(3,11,[node(0,j,k),node(0,j,k+1),node(0,j+1,k+1),node(0,j+1,k)])
            put(3,12,[node(nx,j,k),node(nx,j+1,k),node(nx,j+1,k+1),node(nx,j,k+1)])
    for k in range(nz):
        for i in range(nx):
            put(3,13,[node(i,0,k),node(i+1,0,k),node(i+1,0,k+1),node(i,0,k+1)])
            put(3,13,[node(i,ny,k),node(i,ny,k+1),node(i+1,ny,k+1),node(i+1,ny,k)])
    for j in range(ny):
        for i in range(nx):
            put(3,13,[node(i,j,0),node(i,j+1,0),node(i+1,j+1,0),node(i+1,j,0)])
            put(3,13,[node(i,j,nz),node(i+1,j,nz),node(i+1,j+1,nz),node(i,j+1,nz)])
    data=[
        "$MeshFormat","2.2 0 8","$EndMeshFormat",
        "$PhysicalNames","5",
        '3 1 "muscle"','3 2 "fat"','2 11 "core"','2 12 "skin"','2 13 "insulated"',
        "$EndPhysicalNames","$Nodes",str(len(verts)),*verts,"$EndNodes",
        "$Elements",str(len(elements)),*elements,"$EndElements",""
    ]
    count={"nodes":len(verts),"hexes":nx*ny*nz,"quad_faces":len(elements)-nx*ny*nz,
           "nx":nx,"ny":ny,"nz":nz,"muscle_hexahedra":nm*ny*nz,
           "fat_hexahedra":nf*ny*nz,"conforming_interface":True,
           "core_surface_id":11,"skin_surface_id":12,"insulated_surface_id":13}
    assert len(verts)==(nx+1)*(ny+1)*(nz+1)
    assert len(elements)==count["hexes"]+2*ny*nz+2*nx*nz+2*nx*ny
    return "\n".join(data),count

def head(kind:str,transient:bool):
    mode=("Transient\n Timestepping Method = BDF\n BDF Order = 1\n"
          " Timestep Intervals(1) = 12\n Timestep Sizes(1) = 60.0") if transient else "Steady State"
    if kind=="mechanics":
        equation="Linear elasticity"
        procedure='Procedure = "StressSolve" "StressSolver"\n Variable = -dofs 3 Displacement\n Calculate Stresses = Logical True'
    else:
        equation="Heat Equation"
        procedure='Procedure = "HeatSolve" "HeatSolver"\n Variable = Temperature'
    return f"""Header
 Mesh DB "." "mesh"
End
Simulation
 Max Output Level = 4
 Coordinate System = Cartesian 3D
 Simulation Type = {mode}
 Steady State Max Iterations = 1
 Output Intervals = 1
End
"""

def make_sif(mode:str,activation_w_m3:float):
    assert mode in ("rest","active","transient","mechanics")
    assert 0<=activation_w_m3<=10000
    if mode=="mechanics":
        return """Header
 Mesh DB "." "mesh"
End
Simulation
 Max Output Level = 4
 Coordinate System = Cartesian 3D
 Simulation Type = Steady State
 Steady State Max Iterations = 1
 Output Intervals = 1
End
Body 1
 Target Bodies(1) = 1
 Name = "muscle"
 Equation = 1
 Material = 1
End
Body 2
 Target Bodies(1) = 2
 Name = "fat"
 Equation = 1
 Material = 2
End
Equation 1
 Active Solvers(2) = 1 2
End
Solver 1
 Equation = "Linear elasticity"
 Procedure = "StressSolve" "StressSolver"
 Variable = -dofs 3 Displacement
 Calculate Stresses = Logical True
 Linear System Solver = Direct
 Linear System Direct Method = Banded
End
Solver 2
 Exec Solver = After Simulation
 Equation = "ResultOutput"
 Procedure = "ResultOutputSolve" "ResultOutputSolver"
 Output File Name = ../case
 Vtu Format = Logical True
 Binary Output = Logical False
 Single Precision = Logical False
End
Material 1
 Name = "passive_muscle"
 Youngs Modulus = 30000.0
 Poisson Ratio = 0.35
 Density = 1050
End
Material 2
 Name = "passive_fat"
 Youngs Modulus = 5000.0
 Poisson Ratio = 0.35
 Density = 900
End
Boundary Condition 1
 Target Boundaries(1) = 11
 Displacement 1 = 0
 Displacement 2 = 0
 Displacement 3 = 0
End
Boundary Condition 2
 Target Boundaries(1) = 12
 Force 1 = -100.0
End
"""
    istransient=mode=="transient"
    simtype=("Transient\n Timestepping Method = BDF\n BDF Order = 1\n"
             " Timestep Intervals(1) = 12\n Timestep Sizes(1) = 60.0") if istransient else "Steady State"
    ic=" Initial Condition = 1" if istransient else ""
    init="Initial Condition 1\n Temperature = 310.15\nEnd" if istransient else ""
    return f"""Header
 Mesh DB "." "mesh"
End
Simulation
 Max Output Level = 4
 Coordinate System = Cartesian 3D
 Simulation Type = {simtype}
 Steady State Max Iterations = 1
 Output Intervals = 1
End
Body 1
 Name = "muscle"
 Target Bodies(1) = 1
 Equation = 1
 Material = 1
 Body Force = 1
{ic}
End
Body 2
 Name = "fat"
 Target Bodies(1) = 2
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
 Output File Name = ../case
 Vtu Format = Logical True
 Binary Output = Logical False
 Single Precision = Logical False
End
Material 1
 Name = "muscle"
 Heat Conductivity = {K_MUSCLE}
 Density = {RHO_M}
 Heat Capacity = {CP_M}
End
Material 2
 Name = "fat"
 Heat Conductivity = {K_FAT}
 Density = {RHO_F}
 Heat Capacity = {CP_F}
End
Body Force 1
 Heat Source = {activation_w_m3/RHO_M:.12f}
End
Body Force 2
 Heat Source = {60/RHO_F:.12f}
End
Boundary Condition 1
 Target Boundaries(1) = 11
 Temperature = 310.15
End
Boundary Condition 2
 Target Boundaries(1) = 12
 Heat Transfer Coefficient = 10.0
 External Temperature = 293.15
End
{init}
"""

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--out",type=Path,default=Path("/tmp/lifesim-mf3d"))
    ap.add_argument("--mode",choices=["rest","active","transient","mechanics"],default="rest")
    ap.add_argument("--nx-muscle",type=int,default=8)
    ap.add_argument("--nx-fat",type=int,default=4)
    ap.add_argument("--ny",type=int,default=3)
    ap.add_argument("--nz",type=int,default=3)
    args=ap.parse_args()
    gm,manifest=generate_gmsh_hex8(args.nx_muscle,args.nx_fat,args.ny,args.nz)
    args.out.mkdir(parents=True,exist_ok=True)
    (args.out/"mesh.msh").write_text(gm)
    source=5000.0 if args.mode=="active" else 700.0
    (args.out/"case.sif").write_text(make_sif(args.mode,source))
    manifest.update({"schema":"lifesim.elmer.3d.gmsh.v1",
        "simulation":args.mode,"muscle_layer_m":LM,"fat_layer_m":LF,
        "width_m":WIDTH,"depth_m":DEPTH,"metabolic_muscle_W_m3":source,
        "is_actual_Blendermodel_FEM":False,"medical_validation":False})
    (args.out/"mesh_manifest.json").write_text(json.dumps(manifest,indent=2))
    print("LIFESIM_ELMER_3D_GENERATOR",json.dumps(manifest))

if __name__=="__main__":main()
