extends Node3D
## Physical housing shares the live feed's optical center and pan/tilt orientation.

var feed: Camera3D
var feed_index := 0
var mount_offset := Vector3.ZERO
var head: Node3D
var optical_center: Marker3D
var _led: StandardMaterial3D
var hardware_layer: int

static func layer_for(index: int) -> int:
	return 1 << (10 + index)

static func feed_mask(index: int) -> int:
	return 1 | ((63 << 10) & ~layer_for(index)) | ((1 << 17) if index == 2 else 0)

func _material(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = 0.6
	return material

func _mesh(parent: Node3D, n: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = n
	node.mesh = mesh
	node.position = at
	node.layers = hardware_layer
	node.material_override = material
	parent.add_child(node)
	return node

func _box(parent: Node3D, n: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(parent, n, mesh, at, material)

func _ready() -> void:
	add_to_group("station_cameras")
	process_priority = 10
	hardware_layer = layer_for(feed_index)
	var paint := _material(Color(0.54, 0.57, 0.51), 0.25)
	var dark := _material(Color(0.045, 0.06, 0.06), 0.3)
	var metal := _material(Color(0.30, 0.35, 0.34), 0.7)
	var lens := _material(Color(0.035, 0.075, 0.08), 0.5)
	lens.roughness = 0.12
	_box(self, "WallPlate", Vector3(0.045, 0.27, 0.24), mount_offset, metal)
	var arm_start := mount_offset
	var arm_end := Vector3(0, 0.20, 0)
	var arm := CylinderMesh.new()
	arm.top_radius = 0.027
	arm.bottom_radius = 0.027
	arm.height = arm_start.distance_to(arm_end)
	arm.radial_segments = 8
	var bracket := _mesh(self, "MountArm", arm, (arm_start + arm_end) * 0.5, metal)
	bracket.quaternion = Quaternion(Vector3.UP, (arm_end - arm_start).normalized())
	_box(self, "PanTiltMotor", Vector3(0.15, 0.13, 0.15), Vector3(0, 0.17, 0), dark)
	head = Node3D.new()
	head.name = "PanTiltHead"
	add_child(head)
	_box(head, "CameraHousing", Vector3(0.29, 0.21, 0.43), Vector3(0, 0, 0.23), paint)
	_box(head, "SunShield", Vector3(0.34, 0.025, 0.53), Vector3(0, 0.12, 0.20), metal)
	_box(head, "FrontBezel", Vector3(0.27, 0.19, 0.035), Vector3(0, 0, 0.025), dark)
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = 0.068
	lens_mesh.bottom_radius = 0.068
	lens_mesh.height = 0.012
	lens_mesh.radial_segments = 16
	var glass := _mesh(head, "Lens", lens_mesh, Vector3(0, 0, 0.006), lens)
	glass.rotation.x = PI * 0.5
	optical_center = Marker3D.new()
	optical_center.name = "OpticalCenter"
	head.add_child(optical_center)
	_led = _material(Color(0.55, 0.08, 0.035))
	_led.emission = Color(0.65, 0.045, 0.01)
	_led.emission_energy_multiplier = 0.5
	_box(head, "RecordingIndicator", Vector3(0.018, 0.018, 0.009), Vector3(0.105, -0.055, 0.002), _led)
	var label := Label3D.new()
	label.text = "CAM %02d" % (feed_index + 1)
	label.font = preload("res://ui/fonts/SpecialElite.ttf")
	label.font_size = 24
	label.pixel_size = 0.0011
	label.position = Vector3(0.151, 0, 0.25)
	label.rotation.y = PI * 0.5
	label.layers = hardware_layer
	label.shaded = true
	label.outline_size = 0
	head.add_child(label)
	GameManager.power_changed.connect(_power_changed)
	_power_changed(GameManager.powered)
	_process(0)

func _process(_delta: float) -> void:
	if is_instance_valid(feed): head.global_basis = feed.global_basis

func _power_changed(powered: bool) -> void:
	_led.emission_enabled = powered
	_led.albedo_color = Color(0.55, 0.08, 0.035) if powered else Color(0.055, 0.045, 0.04)
