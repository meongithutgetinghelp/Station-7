"""Run with Blender --background --python to prepare the project’s supplied subway OBJ.
Preserves its four-car shape/materials; opens the box shells behind functioning doors.
Source OBJ and MTL are retained unchanged alongside the exported GLB.
"""
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/trains/subway"
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
materials = {}
current = None
for line in (OUT / "source/subway_train.mtl").read_text().splitlines():
    fields = line.split()
    if not fields: continue
    if fields[0] == "newmtl":
        current = bpy.data.materials.new(fields[1])
        current.use_nodes = True
        materials[fields[1]] = current
    elif current and fields[0] in {"Kd", "Ke", "Ns", "d"}:
        shader = current.node_tree.nodes.get("Principled BSDF")
        if fields[0] == "Kd":
            color = tuple(map(float, fields[1:4])) + (1,)
            shader.inputs["Base Color"].default_value = color
            current.diffuse_color = color
        elif fields[0] == "Ke":
            shader.inputs["Emission Color"].default_value = tuple(map(float, fields[1:4])) + (1,)
            shader.inputs["Emission Strength"].default_value = 1
        elif fields[0] == "Ns": shader.inputs["Roughness"].default_value = max(.25, (2 / (float(fields[1]) + 2)) ** .5)
        elif fields[0] == "d": shader.inputs["Alpha"].default_value = float(fields[1])

vertices = []
parts = []
part = None
material_name = "steel"
for line in (OUT / "source/subway_train.obj").read_text().splitlines():
    fields = line.split()
    if not fields: continue
    if fields[0] == "o":
        part = {"name": fields[1], "faces": [], "material": material_name}
        parts.append(part)
    elif fields[0] == "usemtl":
        material_name = fields[1]
        if part: part["material"] = material_name
    elif fields[0] == "v": vertices.append(tuple(map(float, fields[1:4])))
    elif fields[0] == "f": part["faces"].append([int(v.split('/')[0]) - 1 for v in fields[1:]])


def mesh_object(name, points, faces, material):
    # OBJ Y-up -> Blender Z-up; glTF export returns the original Godot Y-up axes.
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([(x, -z, .55 + (y-.55)*.43 if y < .55 else y) for x, y, z in points], [], faces)
    mesh.materials.append(materials[material])
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    center = sum((v.co for v in mesh.vertices), Vector()) / len(mesh.vertices)
    for vertex in mesh.vertices: vertex.co -= center
    obj.location = center
    return obj


def cube_geometry(lo, hi, points, faces):
    base = len(points)
    x, y, z = lo
    X, Y, Z = hi
    points.extend([(x,y,z),(X,y,z),(X,Y,z),(x,Y,z),(x,y,Z),(X,y,Z),(X,Y,Z),(x,Y,Z)])
    faces.extend([[base+i for i in face] for face in [(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)]])

objects = {}
bounds = {}
for part in parts:
    ids = sorted({i for face in part["faces"] for i in face})
    remap = {old: new for new, old in enumerate(ids)}
    points = [vertices[i] for i in ids]
    lo = tuple(min(v[i] for v in points) for i in range(3))
    hi = tuple(max(v[i] for v in points) for i in range(3))
    bounds[part["name"]] = (lo, hi)
    faces = [[remap[i] for i in face] for face in part["faces"]]
    if part["name"].startswith("Shell_"):
        points, faces = [], []
        x, y, z = lo
        X, Y, Z = hi
        center = (x+X)/2
        # Hollow floor, roof and car ends, preserving the supplied outside dimensions.
        for a,b in [((x,y,z),(X,y+.08,Z)),((x,Y-.08,z),(X,Y,Z)),((x,y,z),(x+.08,Y,Z)),((X-.08,y,z),(X,Y,Z))]:
            cube_geometry(a,b,points,faces)
        cuts = [x] + [value for c in [center-4,center,center+4] for value in [c-.75,c+.75]] + [X]
        for index in range(len(cuts)-1):
            a,b=cuts[index:index+2]
            for za,zb in [(z,z+.08),(Z-.08,Z)]:
                if index % 2 == 0: cube_geometry((a,y,za),(b,Y,zb),points,faces)
                else:
                    cube_geometry((a,y,za),(b,.65,zb),points,faces)
                    cube_geometry((a,2.65,za),(b,Y,zb),points,faces)
    elif part["name"].startswith(("Stripe_", "Pinstripe_")):
        # Body paint stops at each doorway. Door paint is attached to the moving leaves below.
        points, faces = [], []
        x,y,z = lo; X,Y,Z = hi
        center = (x+X)/2
        cuts = [x] + [value for c in [center-4,center,center+4] for value in [c-.75,c+.75]] + [X]
        for segment in range(0,len(cuts)-1,2):
            cube_geometry((cuts[segment],y,z),(cuts[segment+1],Y,Z),points,faces)
    elif part["name"].startswith("DoorFrame_"):
        points, faces = [], []
        x,y,z=lo; X,Y,Z=hi
        for a,b in [((x,y,z),(x+.06,Y,Z)),((X-.06,y,z),(X,Y,Z)),((x,y,z),(X,y+.06,Z)),((x,Y-.06,z),(X,Y,Z))]:
            cube_geometry(a,b,points,faces)
    objects[part["name"]] = mesh_object(part["name"], points, faces, part["material"])

for index in range(1,25):
    lo,hi = bounds[f"DoorFrame_{index}"]
    cx,cy,cz = [(a+b)/2 for a,b in zip(lo,hi)]
    for side, direction in [("L",-1),("R",1)]:
        center = cx + direction*.36
        points,faces=[],[]
        cube_geometry((center-.345,.71,cz-.025),(center+.345,2.59,cz+.025),points,faces)
        leaf=mesh_object(f"SlidingDoor_{index:02d}_{side}",points,faces,"steel")
        glass_index=(index-1)*2+(1 if side=="L" else 2)
        child=objects[f"DoorGlass_{glass_index}"]
        world=child.matrix_world.copy()
        bpy.context.view_layer.update()
        world=child.matrix_world.copy()
        child.parent=leaf
        child.matrix_world=world
        for name, (stripe_lo, stripe_hi) in bounds.items():
            if not name.startswith(("Stripe_", "Pinstripe_")): continue
            if not stripe_lo[0] <= cx <= stripe_hi[0] or stripe_lo[2]*cz < 0: continue
            points,faces=[],[]
            sign = -1 if cz < 0 else 1
            z1,z2 = sorted((cz + sign*.047, cz + sign*.060))
            cube_geometry((center-.345,stripe_lo[1],z1),(center+.345,stripe_hi[1],z2),points,faces)
            label = "DoorPinstripe" if name.startswith("Pinstripe_") else "DoorStripe"
            paint = mesh_object(f"{label}_{index:02d}_{side}", points, faces, objects[name].data.materials[0].name)
            bpy.context.view_layer.update()
            world = paint.matrix_world.copy()
            paint.parent = leaf
            paint.matrix_world = world
        if side=="L":
            seam=objects[f"DoorSeam_{index}"]
            world=seam.matrix_world.copy()
            seam.parent=leaf
            seam.matrix_world=world

bpy.context.view_layer.update()
bpy.ops.export_scene.gltf(filepath=str(OUT / "subway_train.glb"), export_format="GLB", export_yup=True, export_extras=True)
print("Prepared four-car subway train with 48 sliding leaves:", OUT / "subway_train.glb")
