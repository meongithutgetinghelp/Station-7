extends Node3D

var equipped: String = "flashlight"
var _items: Dictionary = {}
var _time: float = 0
var _switch_tween: Tween
var _using: bool = false
var _selection_serial: int = 0
var hands: Node3D
var _action_left := 0.0

func _ready() -> void:
	hands = preload("res://scripts/first_person_hands.gd").new()
	hands.name = "HandRig"
	add_child(hands)
	for item in ["flashlight", "mop", "broom", "battery", "phone"]:
		var model := Node3D.new()
		model.name = item.capitalize()
		_items[item] = model
		add_child(model)
	_piece(_items.flashlight, "Barrel", Vector3(0.075, 0.075, 0.27), Vector3(0.23, -0.23, -0.5), Color(0.12, 0.16, 0.15))
	_piece(_items.flashlight, "Lens", Vector3(0.07, 0.07, 0.015), Vector3(0.23, -0.23, -0.64), Color(0.88, 0.91, 0.78))
	_piece(_items.battery, "Cell", Vector3(0.05, 0.11, 0.05), Vector3(0.23, -0.22, -0.47), Color(0.85, 0.67, 0.19))
	_piece(_items.battery, "Terminal", Vector3(0.025, 0.01, 0.025), Vector3(0.23, -0.16, -0.47), Color(0.65, 0.7, 0.68))
	_piece(_items.phone, "PhoneBody", Vector3(0.09, 0.17, 0.016), Vector3(0.23, -0.20, -0.48), Color(0.06, 0.09, 0.08))
	_piece(_items.phone, "PhoneScreen", Vector3(0.076, 0.14, 0.005), Vector3(0.23, -0.196, -0.468), Color(0.35, 0.56, 0.51))
	var jobs := get_tree().get_first_node_in_group("station_jobs")
	var head := Node3D.new()
	_items.mop.add_child(head)
	jobs._build_string_mop(head)
	head.position = Vector3(0.40, 0.17, -1.1)
	var shaft_material := StandardMaterial3D.new()
	shaft_material.albedo_color = Color(0.62, 0.76, 0.65)
	jobs._mop_piece(_items.mop, "MopShaft", Vector3(0.11, -0.20, -0.01), Vector3(0.40, -0.34, -1.1), 0.016, shaft_material)
	var broom_head := Node3D.new()
	_items.broom.add_child(broom_head)
	jobs._build_broom(broom_head)
	broom_head.position = Vector3(0.40, 0.17, -1.1)
	var broom_material := StandardMaterial3D.new()
	broom_material.albedo_color = Color(0.53, 0.37, 0.2)
	jobs._mop_piece(_items.broom, "BroomShaft", Vector3(0.11, -0.20, -0.01), Vector3(0.4, -0.43, -1.1), 0.016, broom_material)
	for model in [_items.mop, _items.broom]:
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			mesh.layers = 4
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	equip("flashlight", false)

func _piece(parent: Node3D, n: String, size: Vector3, point: Vector3, color: Color) -> void:
	var piece := MeshInstance3D.new()
	piece.name = n
	var mesh := BoxMesh.new()
	mesh.size = size
	if n in ["Barrel", "Lens"]:
		var round_mesh := CylinderMesh.new()
		round_mesh.top_radius = size.x * 0.5
		round_mesh.bottom_radius = size.x * 0.5
		round_mesh.height = size.z
		round_mesh.radial_segments = 12
		piece.mesh = round_mesh
		piece.rotation.x = PI * 0.5
	else:
		piece.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	piece.material_override = material
	piece.position = point
	piece.layers = 4 # Viewmodel is omitted from layer-one CCTV.
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(piece)

func equip(item: String, animate: bool = true) -> bool:
	if not _items.has(item) or not GameManager.has_item(item): return false
	cancel_hand_action()
	equipped = item
	_selection_serial += 1
	if item != "flashlight": get_tree().get_first_node_in_group("player").set_flashlight(false, false)
	for key in _items: _items[key].visible = key == item
	if _switch_tween and _switch_tween.is_running(): _switch_tween.kill()
	if animate:
		position.y = -0.22
		_switch_tween = create_tween()
		_switch_tween.tween_property(self, "position:y", 0.0, 0.22).set_trans(Tween.TRANS_SINE)
	return true

func use_item(item: String) -> void:
	if _using: return
	var previous := equipped
	var player := get_tree().get_first_node_in_group("player")
	var was_lit: bool = player.is_flashlight_on
	if not equip(item): return
	var serial := _selection_serial
	_using = true
	if _switch_tween and _switch_tween.is_running(): _switch_tween.kill()
	_switch_tween = create_tween()
	_switch_tween.tween_property(self, "position:z", -0.08, 0.2)
	_switch_tween.tween_property(self, "position:z", 0.0, 0.25)
	await get_tree().create_timer(0.45, false).timeout
	_using = false
	if serial == _selection_serial:
		equip(previous)
		if previous == "flashlight": player.set_flashlight(was_lit, false)

func _unhandled_input(event: InputEvent) -> void:
	if get_tree().get_first_node_in_group("player").in_booth_inspection: return
	if event is InputEventKey and event.pressed and not event.echo:
		var keys := {KEY_1: "flashlight", KEY_2: "mop", KEY_3: "battery", KEY_4: "phone", KEY_5: "broom"}
		if keys.has(event.keycode):
			equip(keys[event.keycode])
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var seated: bool = player.get_meta("seated_workstation", false)
	var desk := get_tree().get_first_node_in_group("booth_desk")
	visible = (not player.in_booth_inspection or seated) and not (desk and desk.held != null)
	if not _using and not GameManager.has_item(equipped): equip("flashlight")
	_action_left = maxf(0, _action_left - delta)
	if _action_left <= 0:
		hands.right_anchor = null
		hands.left_anchor = null
		hands.set_pose({"flashlight":"flashlight","phone":"phone","battery":"reach","mop":"cleaning","broom":"cleaning"}.get(equipped,"relaxed"))
		if equipped == "flashlight" and not player.is_flashlight_on: hands.set_pose("relaxed")
	for key in _items: _items[key].visible = key == equipped and _action_left <= 0 and (key != "flashlight" or player.is_flashlight_on)
	hands.set_process(visible)
	if player.get_meta("computer_focus",false):
		player.flashlight.visible = false
		if player.flashlight_fill: player.flashlight_fill.visible = false
	if not visible: return
	# Tuck long tools aside near solid surfaces instead of cutting through walls.
	var camera := get_parent() as Camera3D
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 1.3)
	query.collision_mask = preload("res://scripts/collision_layers.gd").SOLID
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var tuck: float = 0.0 if seated else clampf(1.3 - camera.global_position.distance_to(hit.position), 0, 1) if not hit.is_empty() else 0.0
	rotation.y = lerp_angle(rotation.y, tuck * 1.3, 1 - exp(-delta * 12))
	_time += delta
	rotation.z = 0.0 if seated else sin(_time * 2) * 0.008
	position.x = 0.0 if seated else sin(_time * 1.4) * 0.004


func play_hand_action(pose: String, right: Node3D = null, left: Node3D = null, duration: float = 0.6) -> void:
	_action_left = duration
	hands.set_action(pose, right, left)

func cancel_hand_action() -> void:
	_action_left = 0
	if not is_instance_valid(hands): return
	hands.release_anchors()
