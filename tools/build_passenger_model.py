"""Blender authoring source for Station 7's original low-poly passengers."""
from pathlib import Path
import bpy
import math
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/passengers"
SOURCE = ROOT / "builds/passenger-redesign"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

bones = {
    "Root": ((0, 0, 0), (0, 0, .2), None),
    "Pelvis": ((0, 0, .91), (0, 0, 1.05), "Root"),
    "Spine": ((0, 0, 1.05), (0, 0, 1.26), "Pelvis"),
    "Chest": ((0, 0, 1.26), (0, 0, 1.43), "Spine"),
    "Neck": ((0, 0, 1.43), (0, 0, 1.52), "Chest"),
    "Head": ((0, 0, 1.52), (0, 0, 1.78), "Neck"),
}
for sign, side in [(-1, "L"), (1, "R")]:
    bones.update({
        "Shoulder." + side: ((0, 0, 1.40), (sign*.205, 0, 1.395), "Chest"),
        "UpperArm." + side: ((sign*.205, 0, 1.395), (sign*.255, 0, 1.075), "Shoulder."+side),
        "Forearm." + side: ((sign*.255, 0, 1.075), (sign*.27, -.015, .81), "UpperArm."+side),
        "Hand." + side: ((sign*.27, -.015, .81), (sign*.27, -.02, .70), "Forearm."+side),
        "Thigh." + side: ((sign*.09, 0, .91), (sign*.09, 0, .49), "Pelvis"),
        "Shin." + side: ((sign*.09, 0, .49), (sign*.09, 0, .085), "Thigh."+side),
        "Foot." + side: ((sign*.09, 0, .085), (sign*.09, -.15, .05), "Shin."+side),
    })
data = bpy.data.armatures.new("PassengerSkeleton")
rig = bpy.data.objects.new("PassengerRig", data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
for name, (head, tail, parent) in bones.items():
    bone = data.edit_bones.new(name)
    bone.head, bone.tail = head, tail
    bone.use_deform = name != "Root"
    if parent:
        bone.parent = data.edit_bones[parent]
bpy.ops.object.mode_set(mode="OBJECT")

palette = {"Skin": (.72,.50,.36,1), "Coat": (.30,.44,.38,1),
           "Trousers": (.10,.13,.17,1), "Shoes": (.065,.055,.05,1),
           "Shirt": (.82,.79,.67,1), "Hair": (.12,.08,.055,1), "Detail": (1,1,1,1)}
materials = {}
for name, color in palette.items():
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Roughness"].default_value = .85
    if name == "Detail":
        attribute = material.node_tree.nodes.new("ShaderNodeVertexColor")
        attribute.layer_name = "Tint"
        material.node_tree.links.new(attribute.outputs["Color"], shader.inputs["Base Color"])
    materials[name] = material

batches = {}


def add_geometry(batch, verts, faces, weights, color=(1,1,1,1)):
    entry = batches.setdefault(batch, {"verts": [], "faces": [], "weights": [], "colors": []})
    offset = len(entry["verts"])
    entry["verts"].extend(verts)
    entry["faces"].extend(tuple(index+offset for index in face) for face in faces)
    entry["weights"].extend(weights)
    entry["colors"].extend([color]*len(verts))


def torso_weight(z):
    if z < 1.03: return {"Pelvis": 1}
    if z < 1.22:
        t = (z-1.03)/.19
        return {"Spine": 1-t*.5, "Chest": t*.5}
    return {"Chest": 1}


def rings(batch, rows, weight, segments=16, color=(1,1,1,1)):
    # Each row is (center_x, center_y, height, x_radius, y_radius).
    verts=[]
    for x,y,z,rx,ry in rows:
        for i in range(segments):
            a=math.tau*i/segments
            verts.append((x+rx*math.cos(a),y+ry*math.sin(a),z))
    faces=[]
    for row in range(len(rows)-1):
        for i in range(segments):
            j=(i+1)%segments
            faces.append((row*segments+i,row*segments+j,(row+1)*segments+j,(row+1)*segments+i))
    faces.extend([tuple(reversed(range(segments))),tuple((len(rows)-1)*segments+i for i in range(segments))])
    add_geometry(batch,verts,faces,[weight(Vector(v)) for v in verts],color)


def ellipsoid(batch, center, radii, bone, color=(1,1,1,1), segments=12, latitude=8):
    rows=[]
    for j in range(latitude+1):
        a=-math.pi/2+math.pi*j/latitude
        radial=max(.001,math.cos(a))
        rows.append((center[0],center[1],center[2]+radii[2]*math.sin(a),radii[0]*radial,radii[1]*radial))
    rings(batch,rows,lambda p:{bone:1},segments,color)


def patch(batch, vertices, bone, color=(1,1,1,1)):
    add_geometry(batch,vertices,[tuple(range(len(vertices)))],[{bone:1}]*len(vertices),color)


# Tapered tailoring, round shoulders, an actual neck and a shaped jaw.
rings("Coat",[(0,0,.87,.185,.115),(0,0,.96,.195,.125),(0,0,1.07,.165,.115),
              (0,0,1.22,.19,.13),(0,0,1.36,.225,.115),(0,0,1.415,.18,.09),
              (0,0,1.445,.075,.065)],lambda p:torso_weight(p.z))
rings("Skin",[(0,0,1.405,.052,.052),(0,0,1.51,.052,.052)],lambda p:{"Neck":1})
rings("Skin",[(0,-.01,1.49,.048,.048),(0,-.005,1.525,.075,.068),
              (0,0,1.59,.103,.088),(0,.005,1.665,.107,.093),
              (0,.008,1.73,.09,.081),(0,.008,1.765,.045,.047)],lambda p:{"Head":1},20)
ellipsoid("Skin",(0,-.091,1.626),(.018,.028,.032),"Head",segments=10,latitude=6)
for sign,side in [(-1,"L"),(1,"R")]:
    ellipsoid("Skin",(sign*.108,.002,1.63),(.019,.025,.038),"Head")
    def arm_weight(p, side=side):
        t=max(0,min(1,(1.12-p.z)/.09))
        return {"UpperArm."+side:1-t,"Forearm."+side:t}
    rings("Coat",[(sign*.27,-.014,.80,.044,.046),(sign*.267,-.006,.91,.048,.05),
                  (sign*.255,0,1.07,.052,.054),(sign*.235,0,1.27,.062,.067),
                  (sign*.205,0,1.39,.075,.078)],arm_weight,12)
    ellipsoid("Skin",(sign*.27,-.017,.748),(.043,.028,.066),"Hand."+side)
    ellipsoid("Skin",(sign*.239,-.037,.765),(.017,.018,.034),"Hand."+side,segments=8,latitude=6)
    def leg_weight(p,side=side):
        t=max(0,min(1,(.535-p.z)/.09))
        return {"Thigh."+side:1-t,"Shin."+side:t}
    rings("Trousers",[(sign*.09,0,.105,.057,.058),(sign*.09,0,.23,.059,.061),
                      (sign*.09,0,.49,.067,.069),(sign*.09,0,.68,.073,.077),
                      (sign*.09,0,.90,.089,.094)],leg_weight,12)
    # Rounded leather shoes with a flat sole, rather than rectangular feet.
    rings("Shoes",[(sign*.09,-.045,.018,.067,.132),(sign*.09,-.045,.045,.072,.14),
                   (sign*.09,-.035,.085,.066,.124),(sign*.09,.002,.115,.049,.065)],lambda p,side=side:{"Foot."+side:1},16)
    # Human eyes and brows: small whites and dark pupils, without monster emission.
    ellipsoid("Detail",(sign*.043,-.084,1.651),(.024,.013,.012),"Head",(.89,.88,.82,1))
    ellipsoid("Detail",(sign*.043,-.096,1.651),(.007,.004,.008),"Head",(.06,.07,.06,1),10,6)
    patch("Hair",[(sign*.019,-.094,1.675),(sign*.066,-.083,1.678),(sign*.066,-.084,1.686),(sign*.019,-.095,1.683)],"Head")
    # Lapels, seams and coat buttons.
    patch("Shirt",[(sign*.012,-.145,1.435),(sign*.078,-.145,1.395),(sign*.038,-.145,1.335)],"Chest")
    patch("Detail",[(sign*.045,-.131,1.16),(sign*.12,-.126,1.16),(sign*.12,-.127,1.166),(sign*.045,-.132,1.166)],"Spine",(.12,.14,.13,1))
patch("Shirt",[(-.035,-.146,1.43),(.035,-.146,1.43),(.015,-.146,1.29),(-.015,-.146,1.29)],"Chest")
for z in [1.31,1.19,1.08]:
    ellipsoid("Detail",(.018,-.137,z),(.008,.004,.008),"Chest" if z>1.22 else "Spine",(.52,.51,.43,1),8,4)
patch("Detail",[(-.026,-.083,1.565),(.026,-.083,1.565),(.018,-.089,1.571),(-.018,-.089,1.571)],"Head",(.31,.16,.13,1))

# Four original interchangeable silhouettes, all attached to the head.
for style in range(4):
    name="HairStyle%d"%style
    rings(name,[(0,.016,1.69,.106,.093),(0,.015,1.75,.098,.09),
                (0,.013,1.792,.055,.057),(0,.012,1.80,.008,.01)],lambda p:{"Head":1},20)
    if style == 1:
        ellipsoid(name,(-.04,-.035,1.752),(.074,.07,.04),"Head")
    if style == 2:
        for sign in [-1,1]:
            ellipsoid(name,(sign*.097,.025,1.60),(.029,.073,.125),"Head")
        ellipsoid(name,(0,.075,1.62),(.10,.04,.125),"Head")
    if style == 3:
        ellipsoid(name,(0,.104,1.728),(.055,.05,.055),"Head")
    if style == 0:
        for sign in [-1,1]:
            ellipsoid(name,(sign*.097,.03,1.695),(.014,.057,.055),"Head",segments=10)

# Eyeglass frames are one optional mesh, not multiple independently drawn boxes.
for sign in [-1,1]:
    x=sign*.044
    front=-.104
    for dz in [-.017,.017]:
        patch("Glasses",[(x-.031,front,1.651+dz-.002),(x+.031,front,1.651+dz-.002),
                         (x+.031,front,1.651+dz+.002),(x-.031,front,1.651+dz+.002)],"Head",(.10,.095,.08,1))
    for dx in [-.031,.031]:
        patch("Glasses",[(x+dx-.002,front,1.634),(x+dx+.002,front,1.634),
                         (x+dx+.002,front,1.668),(x+dx-.002,front,1.668)],"Head",(.10,.095,.08,1))
patch("Glasses",[(-.016,-.105,1.653),(.016,-.105,1.653),(.016,-.105,1.658),(-.016,-.105,1.658)],"Head",(.10,.095,.08,1))
# A compact cross-body bag for some late-night commuters.
rings("Bag",[(.15,-.105,.88,.075,.035),(.15,-.105,1.03,.075,.035)],lambda p:{"Pelvis":.5,"Spine":.5},12)
patch("Bag",[(-.13,-.13,1.43),(-.106,-.134,1.44),(.19,-.152,.97),(.165,-.153,.96)],"Chest")

for name, entry in batches.items():
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(entry["verts"],[],entry["faces"])
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(obj)
    role="Hair" if name.startswith("HairStyle") else "Detail" if name=="Glasses" else "Shoes" if name=="Bag" else name
    mesh.materials.append(materials[role])
    attr=mesh.color_attributes.new(name="Tint",type="FLOAT_COLOR",domain="POINT")
    for i,color in enumerate(entry["colors"]):attr.data[i].color=color
    groups={name:obj.vertex_groups.new(name=name) for name in bones if name!="Root"}
    for index,weights in enumerate(entry["weights"]):
        for bone,weight in weights.items():
            if weight>0:groups[bone].add([index],weight,"REPLACE")
    for polygon in mesh.polygons:polygon.use_smooth=True
    modifier=obj.modifiers.new("Passenger skin","ARMATURE")
    modifier.object=rig
    obj.parent=rig
    mesh.validate(clean_customdata=True)

bpy.context.view_layer.objects.active=rig
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/"passenger_base.blend"),compress=True)
bpy.ops.export_scene.gltf(filepath=str(OUT/"passenger_base.glb"),export_format="GLB",export_animations=False,export_skins=True,export_def_bones=True)
count=sum(len(face.vertices)-2 for obj in bpy.context.scene.objects if obj.type=="MESH" for face in obj.data.polygons)
print("PASSENGER_BASE_TRIANGLES",count,flush=True)
