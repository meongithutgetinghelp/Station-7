extends Node3D
## Fixed automated kiosk operator; never participates in passenger simulation.

var _head: Node3D
var _status: Label3D
var _indicator: StandardMaterial3D
var _elapsed := 0.0
var powered := false
var _servo: AudioStreamPlayer3D
var _servo_wait := 18.0

func _material(color: Color, metal: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metal
	material.roughness = 0.65
	return material

func _box(parent: Node3D, n: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = n
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node

func _joint(parent: Node3D, n: String, radius: float, height: float, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = n
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	node.material_override = material
	node.position = at
	parent.add_child(node)
	return node

func _ready() -> void:
	add_to_group("kiosk_robot")
	var paint := _material(Color(0.22, 0.29, 0.28), 0.3)
	var ivory := _material(Color(0.64, 0.65, 0.56), 0.15)
	var steel := _material(Color(0.40, 0.46, 0.45), 0.7)
	var rubber := _material(Color(0.045, 0.055, 0.055))
	_indicator = _material(Color(0.65, 0.38, 0.10))
	_indicator.emission = Color(0.65, 0.32, 0.045)
	_indicator.emission_energy_multiplier = 0.65
	_box(self, "BoltedBase", Vector3(0.48, 0.10, 0.40), Vector3(0, 0.05, 0), paint)
	_joint(self, "ServicePedestal", 0.10, 0.67, Vector3(0, 0.41, 0), steel)
	_box(self, "Torso", Vector3(0.44, 0.60, 0.30), Vector3(0, 1.03, 0), paint)
	_box(self, "ServicePanel", Vector3(0.36, 0.40, 0.025), Vector3(0, 1.04, 0.165), ivory)
	for row in range(5):
		_box(self, "CoolingSlot%d" % row, Vector3(0.24, 0.012, 0.008), Vector3(0, 0.91 + row * 0.034, 0.183), rubber)
	_joint(self, "NeckServo", 0.075, 0.12, Vector3(0, 1.39, 0), steel)
	_head = Node3D.new()
	_head.name = "SensorHead"
	_head.position.y = 1.59
	add_child(_head)
	_box(_head, "TerminalHousing", Vector3(0.43, 0.29, 0.30), Vector3.ZERO, ivory)
	_box(_head, "DarkDisplay", Vector3(0.36, 0.20, 0.025), Vector3(0, 0, 0.16), rubber)
	_box(_head, "ScannerBar", Vector3(0.27, 0.012, 0.014), Vector3(0, 0.05, 0.181), _indicator)
	_status = Label3D.new()
	_status.name = "ServiceReadout"
	_status.text = "S7 / AUTO"
	_status.font = preload("res://ui/fonts/SpecialElite.ttf")
	_status.font_size = 28
	_status.pixel_size = 0.0015
	_status.position = Vector3(0, -0.035, 0.182)
	_status.modulate = Color(0.80, 0.62, 0.30)
	_status.outline_size = 0
	_head.add_child(_status)
	for side in [-1.0, 1.0]:
		var shoulder := _joint(self, "ShoulderServo", 0.085, 0.09, Vector3(side * 0.27, 1.21, 0), steel)
		shoulder.rotation.z = PI * 0.5
		_box(self, "UpperArm", Vector3(0.085, 0.16, 0.095), Vector3(side * 0.29, 1.10, 0), paint)
		_joint(self, "ElbowServo", 0.07, 0.10, Vector3(side * 0.29, 1.03, 0.03), steel)
		_box(self, "CounterArm", Vector3(0.10, 0.09, 0.80), Vector3(side * 0.29, 1.08, 0.42), ivory)
		for finger in [-1.0, 1.0]:
			_box(self, "SteelGripper", Vector3(0.025, 0.045, 0.14), Vector3(side * 0.29 + finger * 0.045, 1.08, 0.89), steel)
	for x in [-0.17, 0.17]:
		for y in [0.83, 1.21]:
			_box(self, "PanelBolt", Vector3(0.018, 0.018, 0.013), Vector3(x, y, 0.185), steel)
	_servo = AudioStreamPlayer3D.new()
	_servo.name = "KioskServo"
	_servo.stream = preload("res://audio/ambience/kiosk-servo.wav")
	_servo.bus = "SFX"
	_servo.volume_db = -20
	_servo.max_distance = 7
	_servo.position.y = 1.4
	add_child(_servo)
	GameManager.power_changed.connect(_power_changed)
	_power_changed(GameManager.powered)

func _power_changed(value: bool) -> void:
	powered = value
	if not value and is_instance_valid(_servo): _servo.stop()
	_indicator.emission_enabled = value
	_indicator.albedo_color = Color(0.65, 0.38, 0.10) if value else Color(0.08, 0.07, 0.045)
	_status.visible = value

func _process(delta: float) -> void:
	if not powered: return
	_servo_wait -= delta
	if _servo_wait <= 0:
		_servo.play()
		_servo_wait = 24.0
	_elapsed += delta
	_head.rotation.y = sin(_elapsed * 0.45) * 0.07

func _exit_tree() -> void:
	if is_instance_valid(_servo):
		_servo.stop()
		_servo.stream = null
