extends CharacterBody3D

signal stepped(point: Vector3, radius: float)
## A teammate has no input, UI, or active camera. Host uses its eye for threat checks.
var peer_id: int = 0
var camera: Node3D
var is_crouching: bool = false
var is_sprinting: bool = false
var is_flashlight_on: bool = false
var has_employee_id: bool = true
var employee_id: String = "STAFF-COOP"
var target_position := Vector3.ZERO
var target_yaw: float = 0
var _light: SpotLight3D
var _steps: AudioStreamPlayer3D
var _step_distance: float = 0


func _ready() -> void:
	add_to_group("crew")
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.72
	shape.shape = capsule
	shape.position.y = 0.86
	add_child(shape)
	for part in [[Vector3(0.48, 0.72, 0.28), Vector3(0, 1.02, 0), Color(0.24, 0.38, 0.32)], [Vector3(0.3, 0.35, 0.28), Vector3(0, 1.55, 0), Color(0.66, 0.5, 0.36)], [Vector3(0.35, 0.72, 0.22), Vector3(0, 0.36, 0), Color(0.13, 0.16, 0.17)]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		mesh.mesh = box
		mesh.position = part[1]
		var material := StandardMaterial3D.new()
		material.albedo_color = part[2]
		mesh.material_override = material
		add_child(mesh)
	camera = Node3D.new()
	camera.name = "Eye"
	camera.position.y = 1.6
	add_child(camera)
	_light = SpotLight3D.new()
	_light.spot_range = 20
	_light.spot_angle = 38
	_light.light_energy = 2.0
	camera.add_child(_light)
	var label := Label3D.new()
	label.name = "CrewName"
	label.text = "Staff %d" % peer_id
	label.position.y = 2.05
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.pixel_size = 0.004
	add_child(label)
	_steps = AudioStreamPlayer3D.new()
	_steps.stream = preload("res://mechanical_audio.gd").footstep()
	_steps.bus = "SFX"
	_steps.max_distance = 18
	add_child(_steps)


func apply_pose(pose: Dictionary, immediate: bool = false) -> void:
	var previous := target_position
	target_position = pose.get("p", position)
	target_yaw = float(pose.get("y", rotation.y))
	is_crouching = bool(pose.get("c", false))
	is_sprinting = bool(pose.get("s", false))
	is_flashlight_on = bool(pose.get("f", false))
	camera.position.y = 1.05 if is_crouching else 1.6
	camera.rotation.x = float(pose.get("pitch", 0))
	_light.visible = is_flashlight_on
	var moved := Vector2(target_position.x - previous.x, target_position.z - previous.z).length()
	if moved < 2: _step_distance += moved
	if _step_distance > (0.7 if is_crouching else 1.3):
		_step_distance = 0
		_steps.volume_db = -24 if is_crouching else (-13 if is_sprinting else -18)
		_steps.play()
		stepped.emit(target_position, 13.0 if is_sprinting else (2.0 if is_crouching else 6.0))
	if immediate:
		position = target_position
		rotation.y = target_yaw


func _process(delta: float) -> void:
	position = position.lerp(target_position, minf(1, delta * 15))
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1, delta * 15))
