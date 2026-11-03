extends Node3D

const Interaction = preload("res://scripts/interactable.gd")
const FieldPanel = preload("res://scripts/field_panel.gd")
const MIN_MESS_DELAY := 150.0
const MAX_MESS_DELAY := 270.0
const MAX_ACTIVE_MESSES := 3

var wire_panel: CanvasLayer
var journal: CanvasLayer
var entity_letter: CanvasLayer
var scattered_notes: Node3D
var cleanliness: float = 100
var cleared: Array[String] = []
var collected: Array[String] = []
var clues: Array[String] = []
var _messes: Dictionary = {}
var _mess_pool: Dictionary = {}
var _pickups: Dictionary = {}
var _station: Node3D
var _spawn_timer: float = 0
var _next_mess_delay: float = MIN_MESS_DELAY
var _mess_generation: Dictionary = {}
var _camera_screens: Array[Dictionary] = []
var _cctv_console: Node
const WALL_CCTV_INTERVAL := 1.0 / 6.0
const MONITOR_CCTV_INTERVAL := 1.0 / 24.0
var _hiding_areas: Array[Area3D] = []
var _spots := [Vector3(2, 0.35, -8), Vector3(13.6, 0.35, 5.5), Vector3(9, 0.35, 16.4), Vector3(20.5, 0.35, -3.5), Vector3(-3, 0.35, -2), Vector3(11, 0.35, -15), Vector3(-10, 0.35, 16.5), Vector3(20, 0.35, 3.4)]


func _ready() -> void:
	add_to_group("station_jobs")
	add_to_group("save_participant")
	_station = get_parent()
	wire_panel = preload("res://scripts/wire_puzzle.gd").new()
	wire_panel.name = "WirePuzzle"
	add_child(wire_panel)
	journal = FieldPanel.new()
	journal.name = "Journal"
	add_child(journal)
	_build_entity_letter()
	# Allocate infrequent dirt props during scene loading, never on the first
	# late-shift spawn. Hidden pooled props have no collision or cleanliness cost.
	for index in range(_spots.size()):
		_create_mess(index)
	_build_pickup("mop", Vector3(-14.65, 0.35, 2.3))
	_box("ElectricalWorkbench", Vector3(0.8, 0.8, 1.0), Vector3(24.1, 0.75, 9.3), Color(0.42, 0.54, 0.48))
	_build_pickup("battery", Vector3(24.0, 1.22, 9.3))
	_build_pickup("maintenance_key", Vector3(24.0, 1.22, 1.6))
	_build_trash_cans()
	_build_restroom()
	_build_security()
	_build_clue("camera", Vector3(24.0, 1.175, 3.3), "CAMERA LOG: The Passenger can imitate a person, but their image vanishes from the booth camera. Compare what you see with the camera feed.")
	_build_clue("power", Vector3(24.749, 1.8, 8.5), "MAINTENANCE NOTE: Damage to a light, gate or door can be repaired locally. A full outage needs all three wires reconnected before the main switch.")
	_build_clue("light", Vector3(-13.1, 1.285, 6.4), "NIGHT REPORT: Break line of sight when it hunts. A direct flashlight beam drives it back briefly. Crouch inside a closed stall to hide. Identify it at Security, then confront it with the light.")
	GameManager.night_started.connect(_new_night)
	GameManager.objectives_changed.connect(_sync_objectives)
	GameManager.power_changed.connect(_power_changed)
	GameManager.shift_finished.connect(func() -> void: get_tree().call_group("world_modal", "close_panel"))
	_new_night(GameManager.night)


func _box(n: String, size: Vector3, pos: Vector3, color: Color, collision: bool = true) -> Node3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	var node: Node3D
	if collision:
		node = _station.box(n, size, pos, material)
	else:
		node = _station._booth_prop(n, size, pos, material)
	var room_name: String = ""
	if n.begins_with("Stall") or n.begins_with("Toilet") or n.begins_with("Sink") or n == "Mirror": room_name = "Restroom"
	elif n.begins_with("Security") or n.begins_with("CCTV"): room_name = "Security"
	elif n == "ElectricalWorkbench": room_name = "Electrical"
	if not room_name.is_empty(): node.reparent(_station.get_node("Rooms/" + room_name), true)
	return node


func _build_pickup(item: String, pos: Vector3) -> void:
	var size := Vector3(0.28, 0.12, 0.18)
	if item in ["mop", "broom"]:
		size = Vector3(0.032, 1.25, 0.032)
		pos.y += 0.85
	var node := _box("Pickup_" + item, size, pos, Color(0.62, 0.76, 0.65) if item == "mop" else Color(0.92, 0.73, 0.25))
	if item == "broom": node.get_child(0).material_override.albedo_color = Color(0.53, 0.37, 0.2)
	if item in ["mop", "broom"]:
		var handle := node.get_child(0) as MeshInstance3D
		var shaft := CylinderMesh.new()
		shaft.top_radius = 0.016
		shaft.bottom_radius = 0.016
		shaft.height = 1.25
		shaft.radial_segments = 12
		handle.mesh = shaft
		if item == "mop": _build_string_mop(node)
		else: _build_broom(node)
		# The visible shaft is slender; an invisible pickup target stays easy to aim at.
		(node.get_child(1) as CollisionShape3D).shape.size = Vector3(0.16, 1.25, 0.16)
	_pickups[item] = node
	node.collision_layer = 8
	Interaction.attach(node, _take.bind(item), func() -> String: return "[E] Take " + item.replace("_", " "))


func _mop_piece(parent: Node3D, n: String, from: Vector3, to: Vector3, radius: float, material: Material) -> void:
	var piece := MeshInstance3D.new()
	piece.name = n
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 6
	piece.mesh = mesh
	piece.material_override = material
	piece.position = (from + to) * 0.5
	piece.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	parent.add_child(piece)


func _build_string_mop(parent: Node3D) -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.38, 0.45, 0.43)
	metal.metallic = 0.65
	metal.roughness = 0.4
	_mop_piece(parent, "MopSocket", Vector3(0, -0.48, 0), Vector3(0, -0.59, 0), 0.035, metal)
	var cotton := StandardMaterial3D.new()
	cotton.albedo_color = Color(0.84, 0.83, 0.71)
	cotton.roughness = 1
	var shade := StandardMaterial3D.new()
	shade.albedo_color = Color(0.70, 0.73, 0.65)
	shade.roughness = 1
	# Three concentric bundles: separate bent strands flare out and settle on the floor.
	for i in range(48):
		var angle := TAU * float(i) / 16.0 + floorf(float(i) / 16.0) * 0.23
		var ring := float(i / 16)
		var outward := Vector3(cos(angle), 0, sin(angle))
		var start := Vector3(0, -0.575, 0) + outward * (0.014 + ring * 0.009)
		var bend := Vector3(0, -0.72, 0) + outward * (0.035 + ring * 0.031)
		var tip := Vector3(0, -0.833 + 0.004 * sin(i * 1.7), 0) + outward * (0.055 + ring * 0.044)
		var material: Material = shade if i % 4 == 0 else cotton
		_mop_piece(parent, "Cotton_%02d_Upper" % i, start, bend, 0.007, material)
		_mop_piece(parent, "Cotton_%02d_Tip" % i, bend, tip, 0.007, material)


func _build_broom(parent: Node3D) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.53, 0.37, 0.20)
	var bristle := StandardMaterial3D.new()
	bristle.albedo_color = Color(0.70, 0.62, 0.39)
	bristle.roughness = 1
	var head := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.34, 0.05, 0.08)
	head.mesh = bar
	head.material_override = wood
	head.position.y = -0.62
	parent.add_child(head)
	for i in range(32):
		var x: float = -0.155 + float(i % 16) * 0.0206
		var z: float = -0.022 if i < 16 else 0.022
		_mop_piece(parent, "Bristle_%d" % i, Vector3(x, -0.64, z), Vector3(x * 1.18, -0.83, z * 1.25), 0.007, bristle)


func _build_trash_cans() -> void:
	var steel := Color(0.33, 0.43, 0.40)
	var points := [Vector3(-15.55, 0.35, -12), Vector3(-15.55, 0.35, -7), Vector3(15.55, 0.35, -14), Vector3(15.55, 0.35, 0.65), Vector3(-25.55, 0.35, 12), Vector3(-25.55, 0.35, 16.5), Vector3(25.55, 0.35, 12), Vector3(25.55, 0.35, 16.5)]
	for i in range(points.size()):
		var bin := _box("TrashCan_%d" % i, Vector3(0.62, 0.94, 0.40), points[i] + Vector3(0, 0.47, 0), steel)
		bin.rotation.y = PI * 0.5 if points[i].x < 0 else -PI * 0.5
		bin.add_to_group("trash_cans")
		var face := _box("BinOpening_%d" % i, Vector3(0.45, 0.18, 0.012), Vector3.ZERO, Color(0.025, 0.035, 0.03), false)
		face.reparent(bin, false)
		face.position = Vector3(0, 0.23, 0.206)
		var hood := _box("BinHood_%d" % i, Vector3(0.53, 0.06, 0.10), Vector3.ZERO, steel.lightened(0.15), false)
		hood.reparent(bin, false)
		hood.position = Vector3(0, 0.35, 0.23)
		var label := Label3D.new()
		label.text = "LITTER\nKEEP STATION 7 CLEAN"
		label.font_size = 32
		label.pixel_size = 0.0018
		label.outline_size = 0
		label.position = Vector3(0, -0.1, 0.209)
		bin.add_child(label)


func _take(item: String) -> void:
	if collected.has(item): return
	collected.append(item)
	GameManager.give_item(item)
	_pickups[item].visible = false
	_pickups[item].collision_layer = 0


func _new_night(_night: int) -> void:
	scattered_notes.set_night(_night)
	cleared.clear()
	collected.clear()
	_spawn_timer = 0
	_next_mess_delay = randf_range(MIN_MESS_DELAY, MAX_MESS_DELAY)
	if not GameManager.loading:
		_station.get_node("ElecDoor_InteractiveDoor").set_jammed(false)
		_station.get_node("ElecDoor_InteractiveDoor").locked = GameManager.night >= 4
	for light in get_tree().get_nodes_in_group("station_lights"): light.set_meta("faulted", false)
	if not GameManager.loading:
		for child in _station.get_children():
			if child is Gate: child.jammed = false
	for node in _messes.values():
		node.visible = false
		node.collision_layer = 0
	_messes.clear()
	_mess_generation.clear()
	for node in _pickups.values():
		node.visible = true
		node.collision_layer = 8
	_update_cleanliness()
	_station._apply_station_power()


func _spawn_mess(index: int) -> void:
	var id := str(index)
	if _messes.has(id):
		if cleared.has(id):
			_mess_generation[id] = int(_mess_generation.get(id, 0)) + 1
			cleared.erase(id)
			_messes[id].visible = true
			_messes[id].collision_layer = 8
		return
	var node: StaticBody3D = _mess_pool[id]
	node.visible = true
	node.collision_layer = 8
	_messes[id] = node
	_mess_generation[id] = 1


func _create_mess(index: int) -> void:
	var id := str(index)
	var node := StaticBody3D.new()
	node.name = "Mess_" + id
	node.position = _spots[index]
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 0.08, 1.3)
	collision.shape = shape
	collision.position.y = 0.025
	node.add_child(collision)
	var surface := MeshInstance3D.new()
	surface.name = "TexturedMess"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.8, 1.5)
	surface.mesh = mesh
	surface.position.y = 0.024
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/materials/floor_mess.gdshader")
	material.set_shader_parameter("stain_seed", float(index * 19 + 7))
	material.set_shader_parameter("dirt_color", Color(0.22, 0.16, 0.09) if index % 2 else Color(0.35, 0.28, 0.16))
	surface.material_override = material
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(surface)
	_station.add_child(node)
	_mess_pool[id] = node
	node.visible = false
	node.collision_layer = 0
	Interaction.attach(node, _clean.bind(id), func() -> String: return "[Hold E] Clean mess" if GameManager.has_item("mop") or GameManager.has_item("broom") else "Cleaning tool required — visit the janitor room", 1.2)


func _clean(id: String) -> void:
	if not (GameManager.has_item("mop") or GameManager.has_item("broom")) or not _messes.has(id) or cleared.has(id): return
	cleared.append(id)
	var player := get_tree().get_first_node_in_group("player")
	if player and player.camera.has_node("Equipment"):
		player.camera.get_node("Equipment").use_item("mop" if GameManager.has_item("mop") else "broom")
	GameManager.reward_once("clean/%s/%d" % [id, _mess_generation.get(id, 1)], 2)
	_messes[id].visible = false
	_messes[id].collision_layer = 0
	_spawn_timer = 0
	_next_mess_delay = randf_range(MIN_MESS_DELAY, MAX_MESS_DELAY)
	_update_cleanliness()
	GameManager.notice_posted.emit("Mess cleaned. Station cleanliness: %d%%" % int(cleanliness))


func _update_cleanliness() -> void:
	cleanliness = maxf(0, 100 - (_messes.size() - cleared.size()) * 10)
	_sync_objectives()


func _sync_objectives() -> void:
	if GameManager.loading or not GameManager.signed_in: return
	var task := {"text": "Keep station clean (%d%%). Tools are in the janitor room." % int(cleanliness), "done": cleanliness >= 100}
	if GameManager.objectives.get("clean_station") != task:
		GameManager.objectives["clean_station"] = task
		GameManager.objectives_changed.emit()


func _process(delta: float) -> void:
	_update_camera_feeds(delta)
	if not Coop.simulation_blocked() and GameManager.state in [GameManager.NightState.WORKING, GameManager.NightState.BLACKOUT] and _has_passengers():
		_spawn_timer += delta
		if _spawn_timer >= _next_mess_delay:
			_spawn_timer = 0
			_next_mess_delay = randf_range(MIN_MESS_DELAY, MAX_MESS_DELAY)
			_spawn_random_mess()
			_update_cleanliness()
	else:
		_spawn_timer = 0
	var members: Array = Coop.crew() if Coop.active else [get_tree().get_first_node_in_group("player")]
	for player in members:
		if not player: continue
		var hidden: bool = false
		for area in _hiding_areas:
			var door: Node = area.get_meta("door", null)
			if area.overlaps_body(player) and player.is_crouching and door and not door.is_open: hidden = true
		player.set_meta("hiding", hidden)


func _has_passengers() -> bool:
	for actor in get_tree().get_nodes_in_group("passenger_actor"):
		if actor.visible and not actor.is_queued_for_deletion(): return true
	return false


func _spawn_random_mess() -> void:
	if _messes.size() - cleared.size() >= MAX_ACTIVE_MESSES: return
	var candidates: Array[int] = []
	for i in range(_spots.size()):
		if _messes.has(str(i)) and not cleared.has(str(i)): continue
		var crowded := false
		for id in _messes:
			if not cleared.has(id) and _messes[id].position.distance_to(_spots[i]) < 8.0:
				crowded = true
				break
		if crowded: continue
		for actor in get_tree().get_nodes_in_group("passenger_actor"):
			if actor.visible and not actor.is_queued_for_deletion() and actor.global_position.distance_to(_spots[i]) < 6:
				candidates.append(i)
				break
	if not candidates.is_empty(): _spawn_mess(candidates.pick_random())


func _input(event: InputEvent) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_J:
			if journal.is_open: journal.close_panel()
			else: open_journal()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_I:
			GameManager.notice_posted.emit("Inventory: " + str(GameManager.inventory))
			get_viewport().set_input_as_handled()


func open_journal() -> void:
	journal.clear_body()
	journal.heading.text = "NIGHT LOG / EVIDENCE"
	journal.paragraph(preload("res://scripts/shift_guidance.gd").briefing(GameManager.night))
	var player := get_tree().get_first_node_in_group("player")
	journal.paragraph("Station condition: battery %d%% · cleanliness %d%% · passengers lost %d / %d" % [int(player.flashlight_charge) if player else 0, int(cleanliness), GameManager.lost_passengers, 1 if GameManager.night <= 4 else 0])
	for objective: Dictionary in GameManager.objectives.values():
		journal.paragraph(("[x] " if objective.done else "[ ] ") + str(objective.text))
	journal.paragraph("Collected clues: %d / 3. Inspect the notes in the booth, Security and Electrical rooms." % clues.size())
	for clue in clues: journal.paragraph(clue)
	var pacing := get_tree().get_first_node_in_group("horror_pacing")
	if pacing:
		for entry in pacing.journal_entries(): journal.paragraph("OBSERVATION: " + entry)
	var remaining := GameManager.shift_blockers()
	journal.paragraph("STILL TO DO BEFORE THE SHIFT CAN FINISH\n• " + "\n• ".join(remaining) if not remaining.is_empty() else "Station secured. The shift will finish shortly.")
	journal.paragraph("Controls: J journal · I inventory · R replace flashlight battery · Tab return · Esc pause")
	journal.open_panel()


func _build_entity_letter() -> void:
	entity_letter = preload("res://scripts/entity_letter.gd").new()
	entity_letter.name = "EntityLetterReader"
	add_child(entity_letter)
	scattered_notes = preload("res://scripts/scattered_notes.gd").new()
	scattered_notes.name = "ScatteredNotes"
	scattered_notes.reader = entity_letter
	add_child(scattered_notes)


func _build_clue(id: String, pos: Vector3, text: String) -> void:
	var node := _box("Clue_" + id, Vector3(0.008, 0.35, 0.24) if id == "power" else Vector3(0.35, 0.04, 0.24), pos, Color(0.94, 0.86, 0.63))
	node.collision_layer = 8
	Interaction.attach(node, func() -> void:
		if not clues.has(text): clues.append(text)
		if not Coop.active or Coop.interaction_peer == multiplayer.get_unique_id(): open_journal(), func() -> String: return "[E] Read night report")


func _build_restroom() -> void:
	# Each 15 x 10 m washroom opens off its original 10 x 5 m foyer.
	# Toilets face a matching sink row across a broad, unobstructed aisle.
	for section in [0, 1]:
		var direction: float = 1.0 if section == 0 else -1.0
		var back: float = -14.8 if section == 0 else 4.8
		var front: float = back + direction * 3.2
		var center: float = (back + front) * 0.5
		for index in range(4):
			var x: float = 29.8 + index * 2.2
			var id := "Stall_%d_%d" % [section, index]
			_station._add_interactive_door(id, Vector3(x, 0.35, front), 1.2, 2.35, false, false, false, false)
			_build_toilet(Vector3(x, 0.35, back + direction * 0.65), section == 1)
			var area := Area3D.new()
			area.collision_layer = 0
			area.collision_mask = 2
			area.position = Vector3(x, 1.5, center)
			var collision := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(2.05, 2.3, 3.0)
			collision.shape = shape
			area.add_child(collision)
			add_child(area)
			area.set_meta("door", _station.get_node(id + "_InteractiveDoor"))
			_hiding_areas.append(area)
		var sink_z: float = -5.72 if section == 0 else -4.28
		_box("SinkCounter_%d" % section, Vector3(8.8, 0.9, 0.95), Vector3(33.1, 0.8, sink_z), Color(0.84, 0.87, 0.81))
		for index in range(4):
			var x: float = 29.8 + index * 2.2
			var basin := MeshInstance3D.new()
			var ring := TorusMesh.new()
			ring.inner_radius = 0.19
			ring.outer_radius = 0.29
			basin.mesh = ring
			basin.material_override = _station.mat_wall
			basin.scale = Vector3(1, 0.28, 0.9)
			basin.position = Vector3(x, 1.27, sink_z)
			add_child(basin)
			_box("SinkRecess", Vector3(0.38, 0.012, 0.34), Vector3(x, 1.257, sink_z), Color(0.3, 0.43, 0.41), false)
			_box("SinkTap", Vector3(0.04, 0.22, 0.04), Vector3(x, 1.36, sink_z + direction * 0.32), Color(0.52, 0.6, 0.58), false)
			_box("SinkSpout", Vector3(0.04, 0.04, 0.23), Vector3(x, 1.45, sink_z + direction * 0.21), Color(0.52, 0.6, 0.58), false)
			_box("Mirror", Vector3(1.5, 0.95, 0.035), Vector3(x, 2.05, -5 + direction * -0.145), Color(0.47, 0.63, 0.65), false)


func _build_toilet(point: Vector3, reversed: bool) -> void:
	var toilet := Node3D.new()
	toilet.name = "Toilet_%d_%d" % [roundi(point.x * 100), roundi(point.z * 100)]
	toilet.position = point
	toilet.rotation.y = PI if reversed else 0
	_station.get_node("Rooms/Restroom").add_child(toilet)
	toilet.global_position = point
	var ceramic := StandardMaterial3D.new()
	ceramic.albedo_color = Color(0.92, 0.93, 0.88)
	ceramic.roughness = 0.25
	ceramic.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Revolved outer bowl, rolled lip and inner cavity: an open shaped bowl.
	var profile := [Vector2(0.10, 0.12), Vector2(0.13, 0.28), Vector2(0.25, 0.36), Vector2(0.28, 0.46), Vector2(0.26, 0.5), Vector2(0.20, 0.5), Vector2(0.19, 0.45), Vector2(0.16, 0.33), Vector2(0.08, 0.30)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(profile.size() - 1):
		for segment in range(24):
			var vertices: Array[Vector3] = []
			for corner in [[row, segment], [row + 1, segment], [row + 1, segment + 1], [row, segment + 1]]:
				var angle := TAU * float(corner[1]) / 24
				var radius: float = profile[corner[0]].x
				vertices.append(Vector3(cos(angle) * radius, profile[corner[0]].y, sin(angle) * radius * 1.3))
			for index in [0, 1, 2, 0, 2, 3]: surface.add_vertex(vertices[index])
	surface.generate_normals()
	var bowl := MeshInstance3D.new()
	bowl.name = "CeramicBowl"
	bowl.mesh = surface.commit()
	bowl.material_override = ceramic
	toilet.add_child(bowl)
	var solid := StaticBody3D.new()
	toilet.add_child(solid)
	var collider := CollisionShape3D.new()
	var volume := BoxShape3D.new()
	volume.size = Vector3(0.44, 0.50, 0.70)
	collider.shape = volume
	collider.position.y = 0.25
	solid.add_child(collider)
	var water := MeshInstance3D.new()
	var water_surface := CylinderMesh.new()
	water_surface.top_radius = 0.13
	water_surface.bottom_radius = 0.13
	water_surface.height = 0.006
	water.mesh = water_surface
	water.position.y = 0.315
	water.scale.z = 1.3
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.41, 0.60, 0.60)
	water_material.roughness = 0.15
	water.material_override = water_material
	toilet.add_child(water)
	bowl.scale.x = 0.8
	water.scale.x = 0.8
	for entry in [["Cistern", Vector3(0.44, 0.43, 0.18), Vector3(0, 0.68, -0.35)], ["FlushButton", Vector3(0.06, 0.02, 0.03), Vector3(0.1, 0.905, -0.35)]]:
		var part := _box(entry[0], entry[1], Vector3.ZERO, ceramic.albedo_color)
		part.reparent(toilet, false)
		part.position = entry[2]
	var base := MeshInstance3D.new()
	var pedestal := CylinderMesh.new()
	pedestal.top_radius = 0.12
	pedestal.bottom_radius = 0.16
	pedestal.height = 0.28
	base.mesh = pedestal
	base.material_override = ceramic
	base.position.y = 0.14
	base.scale.z = 1.3
	toilet.add_child(base)
	var seat := MeshInstance3D.new()
	var rim := TorusMesh.new()
	rim.inner_radius = 0.19
	rim.outer_radius = 0.28
	seat.mesh = rim
	seat.material_override = ceramic
	seat.scale = Vector3(0.8, 0.3, 1.3)
	seat.position.y = 0.51
	toilet.add_child(seat)


func _build_security() -> void:
	_box("SecurityDesk", Vector3(0.8, 0.8, 4), Vector3(24.1, 0.75, 2.5), Color(0.42, 0.54, 0.48))
	var views := [
		[Vector3(14.9, 3.15, -14.8), Vector3(-4, 1, -4), Vector3(15.82, 3.15, -14.8)],
		[Vector3(14.9, 3.15, 8.8), Vector3(-5, 1, 4), Vector3(15.82, 3.15, 8.8)],
		[Vector3(24.8, 3.4, 16.1), Vector3(0, 1, 14), Vector3(25.78, 3.4, 16.1)],
		[Vector3(1.3, 6.5, -30), Vector3(0, 2.5, -24), Vector3(1.58, 6.5, -30)],
		[Vector3(-15.5, 3.0, -12), Vector3(-13.8, 1.25, -14), Vector3(-15.82, 3.0, -12)],
		[Vector3(-15.5, 3.15, -0.3), Vector3(-13, 1, -8), Vector3(-15.82, 3.15, -0.3)],
	]
	for i in range(views.size()):
		var viewport := SubViewport.new()
		viewport.size = Vector2i(256, 144)
		viewport.world_3d = get_world_3d()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		viewport.positional_shadow_atlas_size = 512
		add_child(viewport)
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.position = views[i][0]
		camera.look_at(views[i][1])
		camera.current = true
		camera.cull_mask = preload("res://scripts/security_camera.gd").feed_mask(i)
		camera.set_meta("home_rotation", camera.rotation)
		var hardware := preload("res://scripts/security_camera.gd").new()
		hardware.name = "CCTVPhysical_%02d" % (i + 1)
		hardware.feed = camera
		hardware.feed_index = i
		hardware.position = views[i][0]
		hardware.mount_offset = views[i][2] - views[i][0]
		_station.add_child(hardware)
		var material: StandardMaterial3D = null
		if i < 3:
			var z: float = 0.9 + i * 1.6
			var frame := _box("CCTVFrame_%d" % i, Vector3(0.1, 0.65, 1.0), Vector3(24.78, 1.85, z), Color(0.08, 0.13, 0.13))
			frame.set_meta("camera_index", i)
			frame.add_to_group("cctv_console_targets")
			var screen := MeshInstance3D.new()
			var mesh := QuadMesh.new()
			mesh.size = Vector2(0.85, 0.5)
			screen.mesh = mesh
			# Main view only: feeds must never render other monitor textures.
			screen.layers = 1 << 16
			material = StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_texture = viewport.get_texture()
			screen.material_override = material
			screen.position = Vector3(24.72, 1.85, z)
			screen.rotation_degrees.y = -90
			add_child(screen)
		_camera_screens.append({"material": material, "viewport": viewport, "camera": camera, "hardware": hardware, "refresh_in": float(i) * 0.025})

	var terminal := _box("SecurityTerminal", Vector3(0.3, 0.12, 0.5), Vector3(23.9, 1.22, 2.5), Color(0.18, 0.26, 0.25))
	Interaction.attach(terminal, _identify, func() -> String: return "[E] Review evidence / identify intruder")


func _identify() -> void:
	if clues.size() < 3:
		GameManager.notice_posted.emit("Collect all three night reports before identifying the intruder.")
		if not Coop.active or Coop.interaction_peer == multiplayer.get_unique_id(): open_journal()
	else:
		GameManager.entity_identified = true
		GameManager.complete_objective("identify_entity")
		GameManager.notice_posted.emit("Identified: The Passenger. Confront it with a direct flashlight beam.")


func trigger_fault(kind: String) -> void:
	if kind == "flicker":
		_flicker_lights()
	elif kind == "power": GameManager.cause_power_failure()
	elif kind == "door":
		_station.get_node("ElecDoor_InteractiveDoor").set_jammed(true)
		GameManager.objectives["fix_door"] = {"text": "Unjam the Electrical Room door (hold E).", "done": false}
	elif kind == "gate":
		_station.get_node("GateLane_1").jammed = true
		GameManager.objectives["fix_gate"] = {"text": "Repair the jammed gate reader (hold E).", "done": false}
	elif kind == "light":
		for light in get_tree().get_nodes_in_group("station_lights"):
			if str(light.name).begins_with("HallLight"):
				light.set_meta("faulted", true)
				light.light_energy = 0
				break
		GameManager.objectives["fix_light"] = {"text": "Repair the hall light at Electrical panel 2 (hold E).", "done": false}
	GameManager.objectives_changed.emit()


func _flicker_lights() -> void:
	var settings := get_tree().get_first_node_in_group("pause_menu")
	if settings and settings.reduced_flashes(): return
	for step in range(8):
		if not is_inside_tree() or not GameManager.powered: return
		if settings and settings.reduced_flashes():
			_station._apply_station_power()
			return
		for light in get_tree().get_nodes_in_group("station_lights"):
			if str(light.name).begins_with("HallLight"):
				light.light_energy = 0 if step % 2 == 0 else float(light.get_meta("nominal_energy", 2.8))
		await get_tree().create_timer(0.12 + randf() * 0.12, false).timeout
	_station._apply_station_power()


func repair_light() -> void:
	for light in get_tree().get_nodes_in_group("station_lights"): light.set_meta("faulted", false)
	_station._apply_station_power()
	GameManager.complete_objective("fix_light")


func _power_changed(powered: bool) -> void:
	for entry in _camera_screens:
		if entry.material: entry.material.albedo_color = Color.WHITE if powered else Color.BLACK
		entry.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		entry.refresh_in = 0.0


func save_state() -> Dictionary:
	var lights: Array = []
	for light in get_tree().get_nodes_in_group("station_lights"):
		if light.get_meta("faulted", false): lights.append(str(light.name))
	return {"cleared": cleared, "collected": collected, "clues": clues, "spawned": _messes.size(), "mess_ids": _messes.keys(), "mess_generation": _mess_generation, "timer": _spawn_timer, "next_mess_delay": _next_mess_delay, "lights": lights}


func load_state(data: Dictionary) -> void:
	_new_night(GameManager.night)
	if data.has("mess_ids"):
		for id in data.mess_ids: _spawn_mess(clampi(int(id), 0, _spots.size() - 1))
	else:
		for i in range(clampi(int(data.get("spawned", 0)), 0, _spots.size())): _spawn_mess(i)
	cleared.assign(data.get("cleared", []))
	_mess_generation = data.get("mess_generation", _mess_generation)
	collected.assign(data.get("collected", []))
	clues.assign(data.get("clues", []))
	_spawn_timer = float(data.get("timer", 0))
	_next_mess_delay = clampf(float(data.get("next_mess_delay", MIN_MESS_DELAY)), MIN_MESS_DELAY, MAX_MESS_DELAY)
	_spawn_timer = clampf(_spawn_timer, 0, _next_mess_delay)
	for name in data.get("lights", []):
		var light := _station.get_node_or_null(name)
		if light: light.set_meta("faulted", true)
	for id in cleared:
		if _messes.has(id):
			_messes[id].visible = false
			_messes[id].collision_layer = 0
	for item in collected:
		if _pickups.has(item):
			_pickups[item].visible = false
			_pickups[item].collision_layer = 0
	_update_cleanliness()


func _wall_feed_visible(index: int, viewer: Camera3D) -> bool:
	if index >= 3 or not viewer: return false
	var screen := Vector3(24.72, 1.85, 0.9 + index * 1.6)
	# Screen faces west; skip feeds behind the player or outside the room.
	return viewer.global_position.x < screen.x and viewer.global_position.distance_squared_to(screen) < 144.0 and viewer.is_position_in_frustum(screen)

func _update_camera_feeds(delta: float) -> void:
	if not is_instance_valid(_cctv_console):
		_cctv_console = get_tree().get_first_node_in_group("cctv_monitor")
	var monitor_open: bool = is_instance_valid(_cctv_console) and _cctv_console.is_open
	var viewer := get_viewport().get_camera_3d()
	var wall_budget := 1
	for index in range(_camera_screens.size()):
		var entry: Dictionary = _camera_screens[index]
		var viewport: SubViewport = entry.viewport
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		entry.refresh_in = maxf(0.0, entry.refresh_in - delta)
		if not GameManager.powered or entry.get("signal_lost", false): continue
		var selected: bool = monitor_open and index == _cctv_console.selected
		if not selected and (monitor_open or not _wall_feed_visible(index, viewer)): continue
		if entry.refresh_in > 0.0: continue
		if not selected:
			if wall_budget == 0: continue
			wall_budget -= 1
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		entry.refresh_in = MONITOR_CCTV_INTERVAL if selected else WALL_CCTV_INTERVAL
