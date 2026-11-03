extends Node3D

const MODEL = preload("res://assets/passengers/passenger_base.glb")
const Appearance = preload("res://passenger_appearance.gd")
static var _materials: Dictionary = {}
var profile: Dictionary = {}
var appearance: Dictionary = {}
var skeleton: Skeleton3D
var seated: bool = false
var _seat_height: float = 0.56
var _indices: Dictionary = {}
var _rest_rotations: Dictionary = {}
var _local_rest: Dictionary = {}
var _gait: float = 0
var _walking: float = 0
var _elapsed: float = 0


func _ready() -> void:
	appearance = Appearance.describe(profile)
	var model := MODEL.instantiate()
	add_child(model)
	for node in model.find_children("*", "Skeleton3D", true, false): skeleton = node
	assert(skeleton != null, "Passenger requires its skeleton")
	for index in range(skeleton.get_bone_count()):
		var name_text := skeleton.get_bone_name(index)
		_indices[name_text] = index
		_local_rest[name_text] = skeleton.get_bone_rest(index)
		_rest_rotations[name_text] = skeleton.get_bone_global_rest(index).basis.get_rotation_quaternion()
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 2 if profile.get("anomaly", false) else 1
		var name_text := str(mesh.name)
		if name_text.begins_with("HairStyle"): mesh.visible = name_text == "HairStyle%d" % int(appearance.hair_style)
		if name_text == "Glasses": mesh.visible = bool(appearance.glasses)
		if name_text == "Bag": mesh.visible = bool(appearance.bag)
		for surface in range(mesh.mesh.get_surface_count()):
			var original: StandardMaterial3D = mesh.get_active_material(surface)
			var role := str(original.resource_name)
			var color: Color = {"Skin": profile.skin, "Hair": profile.hair, "Coat": profile.coat, "Shirt": appearance.shirt, "Trousers": appearance.trousers}.get(role, original.albedo_color)
			var key := role + "/" + color.to_html(true)
			if not _materials.has(key):
				var material: StandardMaterial3D = original.duplicate()
				material.albedo_color = color
				material.vertex_color_use_as_albedo = role == "Detail"
				_materials[key] = material
			mesh.set_surface_override_material(surface, _materials[key])
	scale = Vector3.ONE * float(appearance.height)
	_gait = float(int(appearance.seed) % 100) * 0.1
	_apply_pose(1.0)


func set_seated(value: bool, seat_height: float = 0.56) -> void:
	seated = value
	_seat_height = seat_height
	_walking = 0
	_apply_pose(1.0)
	if skeleton: skeleton.force_update_all_bone_transforms()


func update_motion(delta: float, speed: float) -> void:
	_elapsed += delta
	_walking = move_toward(_walking, 0.0 if seated else clampf(speed / 1.7, 0, 1), delta * 5)
	_gait += delta * minf(12.0, speed * 5.2) if speed > 0.05 and not seated else 0.0
	_apply_pose(minf(1.0, delta * 12))


func _rotation(name_text: String, euler: Vector3, blend: float) -> void:
	if not _indices.has(name_text): return
	var rest: Quaternion = _rest_rotations[name_text]
	var local: Transform3D = _local_rest[name_text]
	var desired := local.basis.get_rotation_quaternion() * rest.inverse() * Quaternion.from_euler(euler) * rest
	var index: int = _indices[name_text]
	skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index).slerp(desired, blend))


func _apply_pose(blend: float) -> void:
	if not skeleton: return
	var breath: float = sin(_elapsed * 1.3 + float(int(appearance.seed) % 13))
	_rotation("Spine", Vector3(0.012 * breath, 0, 0), blend)
	_rotation("Chest", Vector3(0.015 * breath, 0, sin(_gait) * _walking * 0.018), blend)
	_rotation("Head", Vector3(0.008 * breath, 0.018 * sin(_elapsed * 0.7), 0), blend)
	skeleton.set_bone_pose_scale(_indices.Head, Vector3(float(appearance.face_width), 1, 1))
	var pelvis: int = _indices.Pelvis
	var rest: Quaternion = _rest_rotations.Pelvis
	var height: float = (_seat_height / scale.y + 0.06 - 0.91) if seated else absf(sin(_gait)) * _walking * 0.012
	var parent_index := skeleton.get_bone_parent(pelvis)
	var parent_rest := skeleton.get_bone_global_rest(parent_index) if parent_index >= 0 else Transform3D.IDENTITY
	var local: Transform3D = _local_rest.Pelvis
	skeleton.set_bone_pose_position(pelvis, local.origin + parent_rest.basis.inverse() * Vector3(0, height, 0))
	for side in ["L", "R"]:
		var sign_value: float = 1.0 if side == "L" else -1.0
		var step: float = sin(_gait) * sign_value * _walking
		_rotation("Thigh." + side, Vector3(-PI * 0.5 if seated else step * 0.34, 0, 0), blend)
		_rotation("Shin." + side, Vector3(PI * 0.5 if seated else -maxf(0, step) * 0.32, 0, 0), blend)
		_rotation("Foot." + side, Vector3(0 if seated else -0.10 * step, 0, 0), blend)
		_rotation("UpperArm." + side, Vector3(-0.42 if seated else -0.24 * step, 0, 0), blend)
		_rotation("Forearm." + side, Vector3(-1.0 if seated else -0.06, 0, 0), blend)
		_rotation("Hand." + side, Vector3(0, 0, 0), blend)
		var shin_scale: float = clampf((_seat_height / scale.y + 0.06 - 0.085) / 0.405, 0.9, 1.5) if seated else 1.0
		skeleton.set_bone_pose_scale(_indices["Shin." + side], Vector3(1, shin_scale, 1))


func joint_world(name_text: String) -> Vector3:
	if not skeleton or not _indices.has(name_text): return global_position
	skeleton.force_update_all_bone_transforms()
	return (skeleton.global_transform * skeleton.get_bone_global_pose(_indices[name_text])).origin
