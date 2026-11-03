"""Run with Blender --background --factory-startup --python tools/rig_entity.py.

Build a compact anatomical rig and in-place clips for the project’s cleaned creature.
The cleaned GLB remains unchanged; this writes a separate rigged asset.
"""
from pathlib import Path
import json
import math

import bpy
from mathutils import Vector, Quaternion, Euler

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "assets/entity/the_passenger_cleaned.glb"
OUTPUT = PROJECT / "assets/entity/the_passenger_rigged.glb"
AUTHORING = PROJECT / "builds/model-review/rigged"
AUTHORING.mkdir(parents=True, exist_ok=True)

bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
body = next(obj for obj in meshes if "Body" in obj.name)
for obj in meshes:
    matrix = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = matrix
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for obj in list(bpy.context.scene.objects):
    if obj not in meshes:
        bpy.data.objects.remove(obj, do_unlink=True)

rig_data = bpy.data.armatures.new("PassengerSkeleton")
rig = bpy.data.objects.new("PassengerRig", rig_data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")

# Coordinates are Blender Z-up, facing -Y. The exported GLB is Y-up, facing +Z.
bones = {
    "Root": ((0, 0, 0), (0, 0, 0.2), None),
    "Pelvis": ((0.01, 0.025, 1.08), (0.01, 0.015, 1.30), "Root"),
    "Spine": ((0.01, 0.015, 1.30), (0.025, 0.005, 1.55), "Pelvis"),
    "Chest": ((0.025, 0.005, 1.55), (0.02, -0.01, 1.82), "Spine"),
    "Neck": ((0.02, -0.01, 1.82), (-0.015, -0.025, 2.04), "Chest"),
    "Head": ((-0.015, -0.025, 2.04), (-0.03, -0.04, 2.38), "Neck"),
    "Shoulder.L": ((0.02, -0.01, 1.78), (-0.17, -0.015, 1.75), "Chest"),
    "UpperArm.L": ((-0.17, -0.015, 1.75), (-0.235, -0.045, 1.12), "Shoulder.L"),
    "Forearm.L": ((-0.235, -0.045, 1.12), (-0.235, -0.07, 0.49), "UpperArm.L"),
    "Hand.L": ((-0.235, -0.07, 0.49), (-0.23, -0.085, 0.38), "Forearm.L"),
    "Shoulder.R": ((0.02, -0.01, 1.78), (0.17, -0.015, 1.76), "Chest"),
    "UpperArm.R": ((0.17, -0.015, 1.76), (0.23, -0.045, 1.10), "Shoulder.R"),
    "Forearm.R": ((0.23, -0.045, 1.10), (0.235, -0.08, 0.31), "UpperArm.R"),
    "Hand.R": ((0.235, -0.08, 0.31), (0.245, -0.09, 0.22), "Forearm.R"),
    "Thigh.L": ((-0.065, 0.04, 1.14), (-0.12, 0.03, 0.59), "Pelvis"),
    "Shin.L": ((-0.12, 0.03, 0.59), (-0.20, 0.02, 0.09), "Thigh.L"),
    "Foot.L": ((-0.20, 0.02, 0.09), (-0.265, -0.105, 0.045), "Shin.L"),
    "Thigh.R": ((0.075, 0.04, 1.14), (0.14, 0.03, 0.57), "Pelvis"),
    "Shin.R": ((0.14, 0.03, 0.57), (0.22, 0.015, 0.075), "Thigh.R"),
    "Foot.R": ((0.22, 0.015, 0.075), (0.28, -0.105, 0.02), "Shin.R"),
}
for name, (head, tail, parent) in bones.items():
    bone = rig_data.edit_bones.new(name)
    bone.head, bone.tail = head, tail
    bone.use_deform = name != "Root"
    if parent:
        bone.parent = rig_data.edit_bones[parent]
bpy.ops.object.mode_set(mode="OBJECT")
rig.show_in_front = True


def distance_to_segment(point, head, tail):
    axis = tail - head
    t = max(0.0, min(1.0, (point - head).dot(axis) / axis.length_squared))
    return (point - (head + axis * t)).length


deform = {name: (Vector(head), Vector(tail))
          for name, (head, tail, _) in bones.items() if name != "Root"}
for obj in meshes:
    obj.vertex_groups.clear()
    groups = {name: obj.vertex_groups.new(name=name) for name in deform}
    for vertex in obj.data.vertices:
        if "Eye" in obj.name:
            groups["Head"].add([vertex.index], 1.0, "REPLACE")
            continue
        point = vertex.co
        x, y, z = point
        candidates = []
        for name, (head, tail) in deform.items():
            # Anatomical limits keep a hanging forearm from binding to a thigh.
            arm = any(part in name for part in ("Arm", "Forearm", "Hand", "Shoulder"))
            leg = any(part in name for part in ("Thigh", "Shin", "Foot"))
            if z > 1.97 and name not in ("Head", "Neck"):
                continue
            if name in ("Head", "Neck") and z < 1.76:
                continue
            if leg and (z > 1.38 or (z > 0.36 and abs(x) > 0.205 and y < -0.005)):
                continue
            if arm:
                if z < 0.27 or (name.endswith(".L") and x > -0.09) or (name.endswith(".R") and x < 0.09):
                    continue
                if z < 1.26 and abs(x) < 0.165:
                    continue
            if not arm and not leg and z < 0.94:
                continue
            distance = distance_to_segment(point, head, tail)
            weight = 1.0 / (distance + 0.035) ** 4
            candidates.append((weight, name))
        if not candidates:
            candidates = [(1.0, "Pelvis")]
        candidates.sort(reverse=True)
        selected = candidates[:4]
        total = sum(weight for weight, _ in selected)
        for weight, name in selected:
            groups[name].add([vertex.index], weight / total, "REPLACE")
    modifier = obj.modifiers.new("Passenger skin", "ARMATURE")
    modifier.object = rig
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()

scene = bpy.context.scene
scene.render.fps = 30


def pose(name, x=0.0, y=0.0, z=0.0, lift=0.0):
    bone = rig.pose.bones[name]
    rest = rig_data.bones[name].matrix_local.to_quaternion()
    rotation = Euler((x, y, z), "XYZ").to_quaternion()
    bone.rotation_mode = "QUATERNION"
    bone.rotation_quaternion = rest.inverted() @ rotation @ rest
    bone.location = rest.inverted() @ Vector((0, 0, lift))


clips = {"Idle": 96, "Walk": 42, "Chase": 24, "Attack": 30, "Retreat": 30}
rig.animation_data_create()
for clip, frames in clips.items():
    rig.animation_data.action = None
    action = bpy.data.actions.new(clip)
    action.use_fake_user = True
    rig.animation_data.action = action
    for frame in range(frames + 1):
        scene.frame_set(frame)
        t = frame / frames
        cycle = t * math.tau
        swing = math.sin(cycle)
        for name in bones:
            pose(name)
        if clip == "Idle":
            pose("Pelvis", lift=0.008 * math.sin(cycle))
            pose("Chest", x=0.025 * math.sin(cycle), y=0.014 * math.sin(cycle))
            pose("Neck", z=0.035 * math.sin(cycle))
            pose("Head", x=0.025 * math.sin(cycle * 2), z=-0.055 * math.sin(cycle))
            pose("UpperArm.L", x=0.035 * swing)
            pose("UpperArm.R", x=-0.035 * swing)
        elif clip in ("Walk", "Chase", "Retreat"):
            chase = clip == "Chase"
            retreat = clip == "Retreat"
            amount = 0.43 if chase else 0.25
            direction = -1 if retreat else 1
            pose("Pelvis", x=0.08 if chase else (-0.04 if retreat else 0), lift=0.025 * abs(swing))
            pose("Chest", x=0.15 if chase else (-0.05 if retreat else 0.025), z=0.025 * swing)
            pose("Head", x=-0.13 if chase else 0.02, z=-0.025 * swing)
            for side, sign in [("L", 1), ("R", -1)]:
                step = swing * sign * direction
                pose("Thigh." + side, x=amount * step)
                pose("Shin." + side, x=-max(0, step) * (0.32 if chase else 0.17))
                pose("Foot." + side, x=-0.08 * step)
                pose("UpperArm." + side, x=-step * (0.22 if chase else 0.10))
                pose("Forearm." + side, x=-0.10 if chase else 0.035 * step)
                pose("Hand." + side, z=0.03 * step)
        else:
            # Telegraph, reach, then settle. Host impact occurs near the reach peak.
            reach = math.sin(math.pi * t) ** 1.5
            strike = math.exp(-((t - 0.64) / 0.17) ** 2)
            pose("Pelvis", x=0.08 * strike, lift=-0.035 * reach)
            pose("Chest", x=0.22 * strike - 0.06 * reach)
            pose("Neck", x=0.08 * strike)
            pose("Head", x=-0.05 * strike, z=0.045 * reach)
            pose("UpperArm.L", x=-1.05 * reach, z=-0.10 * reach)
            pose("UpperArm.R", x=-0.91 * reach, z=0.10 * reach)
            pose("Forearm.L", x=-0.28 * reach)
            pose("Forearm.R", x=-0.38 * reach)
            pose("Hand.L", x=-0.08 * strike)
            pose("Hand.R", x=-0.08 * strike)
        for bone in rig.pose.bones:
            bone.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=bone.name)
            bone.keyframe_insert(data_path="location", frame=frame, group=bone.name)
    action["in_place"] = True
    action["loop"] = clip != "Attack"

# Validate skin completeness and the worst pose bounds before writing deliverables.
unweighted = 0
bad_weights = 0
for obj in meshes:
    for vertex in obj.data.vertices:
        weights = [group.weight for group in vertex.groups]
        unweighted += not weights
        bad_weights += abs(sum(weights) - 1) > 0.0001
assert not unweighted and not bad_weights
bounds = {}
for clip in clips:
    rig.animation_data.action = bpy.data.actions[clip]
    scene.frame_set(int(clips[clip] * 0.6))
    bpy.context.view_layer.update()
    points = [Vector(corner) for obj in meshes for corner in obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).bound_box]
    extents = [max(p[k] for p in points) - min(p[k] for p in points) for k in range(3)]
    assert max(extents) < 3.4, (clip, extents)
    bounds[clip] = extents
rig.animation_data.action = bpy.data.actions["Idle"]
scene.frame_set(0)
scene.frame_start = 0
scene.frame_end = clips["Idle"]
bpy.ops.object.select_all(action="SELECT")
bpy.context.view_layer.objects.active = rig
bpy.ops.wm.save_as_mainfile(filepath=str(AUTHORING / "the_passenger_rigged.blend"), compress=True)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", export_yup=True,
                          export_animations=True, export_animation_mode="ACTIONS",
                          export_force_sampling=True, export_frame_range=False,
                          export_skins=True, export_def_bones=True, export_extras=True)
report = {"bones": len(bones), "clips": {name: frames / 30 for name, frames in clips.items()},
          "unweighted_vertices": unweighted, "bad_weight_sums": bad_weights,
          "sampled_pose_bounds": bounds, "root_motion": False, "source": str(SOURCE),
          "output": str(OUTPUT), "skinning": "Anatomically constrained distance weights, four influences maximum; eyes rigidly bound to Head."}
(AUTHORING / "rig-report.json").write_text(json.dumps(report, indent=2))
print("RIG_REPORT", json.dumps(report), flush=True)
