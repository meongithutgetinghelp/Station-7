extends Node3D
## Port of the user's Platform 7 Hands.html: centimetre geometry, ZXY joints,
## mirrored left hand, and the supplied finger/thumb angles. Props live elsewhere.
const F := {
	"relaxed": [[12,18,8,4],[16,22,10,0],[20,25,12,3],[26,28,12,6]],
	"flashlight": [[68,88,48,0],[74,92,50,0],[78,94,50,0],[82,96,46,0]],
	"flat": [[2,4,2,6],[0,3,2,0],[1,4,2,4],[2,4,2,9]],
	"keyboard": [[24,42,16,3],[28,46,16,0],[26,44,15,3],[24,40,12,5]],
	"reach": [[44,40,22,4],[20,24,10,3],[22,28,12,4],[26,30,12,8]],
	"stamp": [[56,78,28,2],[60,82,30,0],[62,84,30,2],[64,84,26,4]],
	"cleaning": [[78,92,52,0],[82,96,54,0],[84,98,52,0],[86,98,48,0]],
	"document": [[34,52,24,2],[40,58,26,0],[44,60,26,2],[48,62,24,4]],
	"phone": [[34,66,34,2],[40,70,36,0],[44,72,36,2],[48,72,32,4]]
}
const T := {
	"relaxed": [10,0,6,8,10], "flashlight": [36,30,8,22,18],
	"flat": [4,0,14,4,4], "keyboard": [8,0,10,10,8],
	"reach": [24,28,14,26,14], "stamp": [30,24,8,26,16],
	"cleaning": [34,30,6,24,16], "document": [30,36,10,24,16],
	"phone": [18,20,20,8,6]
}
const DEFS := [[2.55,8.0,[4.1,2.4,1.9],0.80],[0.85,9.0,[4.5,2.8,2.0],0.82],[-0.85,8.6,[4.1,2.6,1.9],0.78],[-2.45,7.5,[3.3,2.0,1.8],0.68]]
const SPREAD := [-1,0,1,1]
const POSES := ["relaxed","flashlight","document","reach","stamp","keyboard","cleaning","phone"]
static var _meshes: Dictionary = {}
var _left_build := false
var active_pose := "flashlight"
var document_context := false
var right_anchor: Node3D
var left_anchor: Node3D
var rigs: Array[Dictionary] = []
var _surfaces: Array[SurfaceTool] = []
var _building := false
var _snap := true
var _clock := 0.0

func _init(document: bool = false) -> void:
	document_context = document
	if document: active_pose = "document"

func _ready() -> void:
	_build_hand(false)
	_build_hand(true)
	_update(0)

func set_pose(pose: String, immediate: bool = false) -> void:
	if pose not in POSES: return
	active_pose = pose
	_snap = immediate
	if immediate and not rigs.is_empty(): _update(0)

func set_action(pose: String, right: Node3D = null, left: Node3D = null) -> void:
	right_anchor = right
	left_anchor = left
	set_pose(pose)

func _process(delta: float) -> void:
	_update(delta)

func _update(delta: float) -> void:
	_clock += delta
	var blend := 1.0 if _snap else 1.0 - exp(-delta * 12)
	for rig in rigs:
		var left: bool = rig.left
		var target: Transform3D = _wrist_target(left)
		var anchor: Node3D = null
		if active_pose in ["stamp","keyboard","reach"] and not document_context:
			anchor = left_anchor if left and active_pose == "stamp" else right_anchor
			if left and active_pose == "reach": anchor = null
		var parent: Node3D = anchor if is_instance_valid(anchor) else self
		if rig.wrist.get_parent() != parent: rig.wrist.reparent(parent,true)
		if parent != self: target = parent.global_transform.affine_inverse()*global_transform*target
		rig.wrist.transform = rig.wrist.transform.interpolate_with(target,blend)

		# Two fixed-length uniform segments connect the wrist to the off-screen shoulder.
		# Joint rotations bend the arm; no mesh or bone is stretched.
		var camera := get_viewport().get_camera_3d()
		if camera:
			var cuff: Vector3 = rig.model.to_global(Vector3(0,-6,0))
			var shoulder: Vector3 = camera.to_global(Vector3(-0.24 if left else 0.24,-0.24,0.08))
			var delta_to_shoulder := shoulder-cuff
			var distance := clampf(delta_to_shoulder.length(),0.13,0.55)
			var axis := delta_to_shoulder.normalized()
			shoulder = cuff+axis*distance
			var pole: Vector3 = camera.to_global(Vector3(-0.50 if left else 0.50,-0.65,-0.10))-cuff
			pole = (pole-axis*pole.dot(axis)).normalized()
			var along := (0.22*0.22-0.34*0.34+distance*distance)/(2*distance)
			var elbow := cuff+axis*along+pole*sqrt(maxf(0,0.22*0.22-along*along))
			var local_forearm: Vector3 = (rig.model.global_basis.inverse()*(elbow-cuff)).normalized()
			var local_upper: Vector3 = (rig.model.global_basis.inverse()*(shoulder-elbow)).normalized()
			rig.skeleton.set_bone_pose_rotation(rig.sleeve,Quaternion(Vector3.DOWN,local_forearm))
			rig.skeleton.set_bone_pose_rotation(rig.upper,Quaternion(Vector3.DOWN,local_upper))
			rig.skeleton.set_bone_pose_position(rig.upper,rig.model.to_local(elbow))

		var pose := active_pose
		if left and pose in ["flashlight", "phone"]: pose = "relaxed"
		if left and pose in ["reach", "stamp"]: pose = "flat"
		for finger in range(4):
			var angles: Array = F[pose][finger]
			for joint in range(3):
				var euler := Vector3(deg_to_rad(angles[joint]), 0, deg_to_rad(SPREAD[finger] * angles[3]) if joint == 0 else 0.0)
				if pose == "keyboard": euler.x += sin(_clock * 14 + finger * 1.7 + (2 if left else 0)) * 0.045
				if left:
					euler.y = -euler.y
					euler.z = -euler.z
				var bone: int = rig.fingers[finger][joint]
				var q := Basis.from_euler(euler, EULER_ORDER_ZXY).get_rotation_quaternion()
				rig.skeleton.set_bone_pose_rotation(bone, rig.skeleton.get_bone_pose_rotation(bone).slerp(q, blend))
		var thumb: Array = T[pose]
		for joint in range(3):
			var euler := Vector3(deg_to_rad(thumb[3 + joint - 1]), 0, 0) if joint > 0 else Vector3(deg_to_rad(thumb[0] + 14), deg_to_rad(thumb[1]), -deg_to_rad(52 + thumb[2]))
			if left:
				euler.y = -euler.y
				euler.z = -euler.z
			var bone: int = rig.thumb[joint]
			var q := Basis.from_euler(euler, EULER_ORDER_ZXY if joint == 0 else EULER_ORDER_XYZ).get_rotation_quaternion()
			rig.skeleton.set_bone_pose_rotation(bone, rig.skeleton.get_bone_pose_rotation(bone).slerp(q, blend))
	_snap = false

func _basis(fd: Vector3, pd: Vector3, xd: Vector3 = Vector3.ZERO) -> Basis:
	var y := fd.normalized()
	var x: Vector3
	var z: Vector3
	if xd != Vector3.ZERO:
		x = (xd - y * xd.dot(y)).normalized()
		z = x.cross(y)
	else:
		z = (pd - y * pd.dot(y)).normalized()
		x = y.cross(z)
	return Basis(x, y, z).orthonormalized()

func _pin(at: Vector3, basis: Basis, pin: Vector3, left: bool) -> Transform3D:
	if left: pin.x = -pin.x
	return Transform3D(basis, at - basis * (pin * 0.01))

func _world_pin(at: Vector3, basis: Basis, pin: Vector3, left: bool) -> Transform3D:
	return global_transform.affine_inverse() * _pin(at, basis, pin, left)

func _wrist_target(left: bool) -> Transform3D:
	var side := -1.0 if left else 1.0
	if document_context:
		return _pin(Vector3(side * 0.26, -0.155, 0.025), _basis(Vector3(-side * 0.55,-0.1,-0.83), Vector3(-side * 0.55,0.3,0.78)), Vector3(2.4,8.6,1.5), left)
	if active_pose == "stamp" and is_instance_valid(right_anchor):
		if not left: return _world_pin(right_anchor.to_global(Vector3(0,0.12,0)), _basis(Vector3.FORWARD, Vector3.DOWN), Vector3(0,6,0), false)
		if is_instance_valid(left_anchor): return _world_pin(left_anchor.to_global(Vector3(0,0.035,-0.07)), _basis(Vector3.RIGHT, Vector3.DOWN), Vector3(0,9,0), true)
	if active_pose == "keyboard" and is_instance_valid(right_anchor):
		var fd := right_anchor.global_basis.x.normalized()
		var at := right_anchor.global_position + right_anchor.global_basis.z * side * 0.1 + Vector3.UP * 0.06
		return _world_pin(at, _basis(fd, Vector3.DOWN), Vector3(0,12,0), left)
	if active_pose == "reach" and is_instance_valid(right_anchor) and not left:
		return _world_pin(right_anchor.global_position + Vector3.UP * 0.035, _basis(Vector3.RIGHT, Vector3.DOWN), Vector3(1.7,12.6,1.2), false)
	if active_pose == "flashlight" and not left:
		return _pin(Vector3(0.23,-0.23,-0.47), _basis(Vector3(0.85,0.48,-0.20), Vector3.ZERO, Vector3(0,-0.12,1)), Vector3(0,6.2,3.1), false)
	if active_pose == "phone" and not left:
		return _pin(Vector3(0.23,-0.20,-0.48), _basis(Vector3(-1,0.15,0),Vector3(0,0.25,1)), Vector3(0.5,5.3,2), false)
	if active_pose == "cleaning":
		var start := Vector3(0.11,-0.20,-0.01)
		var end := Vector3(0.40,-0.34,-1.1)
		var axis := (end - start).normalized()
		return _pin(start.lerp(end, 0.72 if left else 0.40), _basis(Vector3(-side * 0.8,-0.1,-0.5), Vector3.ZERO, axis * side), Vector3(0,6.2,2.3), left)
	if active_pose == "reach" and not left:
		return _pin(Vector3(0.23,-0.22,-0.47), _basis(Vector3(-0.2,-0.45,-0.87),Vector3(-0.25,-0.85,0.45)), Vector3(1.7,12.6,1.2), false)
	if active_pose in ["keyboard", "stamp"]:
		return Transform3D(_basis(Vector3(-side * 0.1,-0.12,-1), Vector3.DOWN), Vector3(side * 0.12,-0.23,-0.42))
	return Transform3D(_basis(Vector3(side * 0.12,-0.45,-0.88), Vector3(-side * 0.9,-0.4,0.1)), Vector3(side * 0.20,-0.31,-0.24))

func _bone(skeleton: Skeleton3D, label: String, parent: int, point: Vector3) -> int:
	var index := skeleton.get_bone_count()
	skeleton.add_bone(label)
	if parent >= 0: skeleton.set_bone_parent(index, parent)
	if _left_build: point.x = -point.x
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, point))
	skeleton.set_bone_pose_position(index,point)
	return index

func _build_hand(left: bool) -> void:
	_left_build = left
	var wrist := Node3D.new()
	wrist.name = "LeftWrist" if left else "RightWrist"
	add_child(wrist)
	var model := Node3D.new()
	model.scale = Vector3.ONE * 0.01
	wrist.add_child(model)
	var skeleton := Skeleton3D.new()
	model.add_child(skeleton)
	_bone(skeleton, "Wrist", -1, Vector3.ZERO)
	var sleeve_bone := _bone(skeleton, "Sleeve", 0, Vector3(0,-6,0))
	var upper_bone := _bone(skeleton,"UpperArm",0,Vector3(0,-28,0))
	_building = not _meshes.has(left)
	if _building:
		_surfaces.clear()
		for color in [Color("cf9f7c"), Color("e6c0ae"), Color("1f2d3a")]:
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.roughness = 0.62 if _surfaces.is_empty() else (0.25 if _surfaces.size() == 1 else 0.92)
			material.cull_mode = BaseMaterial3D.CULL_BACK
			surface.set_material(material)
			_surfaces.append(surface)
	_ell(Vector3(0,4.8,0),Vector3(3.9,4.7,1.35),0,0)
	_ell(Vector3(2.3,2.7,0.8),Vector3(1.7,2.3,0.9),0,0)
	_ell(Vector3(-2.3,3.3,0.5),Vector3(1.4,3.1,0.75),0,0)
	_ell(Vector3(0,0.2,0),Vector3(2.7,1.9,1.5),0,0)
	_cylinder(Vector3(0,-3,0),6,3.3,2.8,Vector3(1,1,0.95),0,0)
	_cylinder(Vector3(0,-17,0),22,5.5,3.9,Vector3(1,1,0.95),sleeve_bone,2,false)
	if _building:
		var cuff := TorusMesh.new()
		cuff.inner_radius = 3.3
		cuff.outer_radius = 3.9
		cuff.rings = 20
		cuff.ring_segments = 6
		_append(cuff, Transform3D(Basis.IDENTITY,Vector3(0,-6,0)),sleeve_bone,2)
	_cylinder(Vector3(0,-45,0),34,6.7,5.5,Vector3(1,1,0.95),upper_bone,2)
	_ell(Vector3(0,-28,0),Vector3.ONE*5.5,upper_bone,2)
	var fingers: Array = []
	for i in range(4):
		var d: Array = DEFS[i]
		fingers.append(_chain(skeleton,"Finger%d" % i,Vector3(d[0],d[1],0),d[2],d[3]))
	var thumb := _chain(skeleton,"Thumb",Vector3(2.9,1.3,0.5),[3.7,3.1,2.5],0.98)
	if _building:
		var mesh := ArrayMesh.new()
		for surface in _surfaces:
			surface.index()
			surface.commit(mesh)
		_surfaces.clear()
		_meshes[left] = mesh
	var instance := MeshInstance3D.new()
	instance.name = "ReferenceHand"
	instance.mesh = _meshes[left]
	instance.layers = 4
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skeleton.add_child(instance)
	instance.skeleton = NodePath("..")
	instance.skin = skeleton.create_skin_from_rest_transforms()
	rigs.append({"left":left,"wrist":wrist,"skeleton":skeleton,"model":model,"sleeve":sleeve_bone,"upper":upper_bone,"fingers":fingers,"thumb":thumb})

func _chain(skeleton: Skeleton3D, label: String, origin: Vector3, lengths: Array, radius: float) -> Array:
	var bones: Array = []
	var point := origin
	for i in range(lengths.size()):
		var bone := _bone(skeleton,label + str(i),0 if i == 0 else int(bones[-1]),origin if i == 0 else Vector3(0,lengths[i-1],0))
		bones.append(bone)
		_ell(point,Vector3.ONE * radius,bone,0)
		_cylinder(point + Vector3(0,lengths[i]*0.5,0),lengths[i],radius,radius*0.85,Vector3.ONE,bone,0)
		point.y += lengths[i]
		radius *= 0.85
	_ell(point,Vector3.ONE*radius,int(bones[-1]),0)
	_ell(point + Vector3(0,-0.95,-radius*0.72),Vector3(radius*0.78,0.95,radius*0.3),int(bones[-1]),1)
	return bones

func _ell(point: Vector3, size: Vector3, bone: int, surface: int) -> void:
	if not _building: return
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 20
	mesh.rings = 14
	_append(mesh,Transform3D(Basis.IDENTITY.scaled(size),point),bone,surface)

func _cylinder(point: Vector3, height: float, bottom: float, top: float, size: Vector3, bone: int, surface: int, caps: bool = true) -> void:
	if not _building: return
	var mesh := CylinderMesh.new()
	mesh.height = height
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.radial_segments = 16
	mesh.cap_top = caps
	mesh.cap_bottom = caps
	_append(mesh,Transform3D(Basis.IDENTITY.scaled(size),point),bone,surface)

func _append(mesh: PrimitiveMesh, transform: Transform3D, bone: int, surface: int) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var normal_basis := transform.basis.inverse().transposed()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for triangle in range(0, indices.size(), 3):
		for corner in ([0,2,1] if _left_build else [0,1,2]):
			var index: int = indices[triangle + corner]
			var vertex: Vector3 = transform * arrays[Mesh.ARRAY_VERTEX][index]
			var normal: Vector3 = (normal_basis * arrays[Mesh.ARRAY_NORMAL][index]).normalized()
			if _left_build:
				vertex.x = -vertex.x
				normal.x = -normal.x
			_surfaces[surface].set_bones(PackedInt32Array([bone,0,0,0]))
			_surfaces[surface].set_weights(PackedFloat32Array([1,0,0,0]))
			_surfaces[surface].set_normal(normal)
			_surfaces[surface].add_vertex(vertex)


func release_anchors() -> void:
	right_anchor = null
	left_anchor = null
	for rig in rigs:
		if is_instance_valid(rig.wrist) and rig.wrist.get_parent() != self: rig.wrist.reparent(self,true)

func _exit_tree() -> void:
	for rig in rigs:
		if is_instance_valid(rig.wrist) and rig.wrist.get_parent() != self: rig.wrist.queue_free()
