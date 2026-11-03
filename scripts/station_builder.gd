@tool
extends Node3D

const InteractionComponent = preload("res://scripts/interactable.gd")
const NoticeNote = preload("res://scripts/noticeboard_note.gd")

# ─────────────────────────────────────────────────────────────────────────────
#  NIGHT SHIFT AT PLATFORM 7 — Station Builder
#  Shared station geometry and runtime systems. Room shells are PackedScenes.
# ─────────────────────────────────────────────────────────────────────────────

## When enabled, floods the entire scene with bright inspection daylight so
## you can clearly inspect every room, wall, track, and prop.
## Turn off when ready for moody horror atmosphere.
@export var debug_bright_mode: bool = false:
	set(val):
		debug_bright_mode = val
		if is_inside_tree():
			if Engine.is_editor_hint():
				_rebuild()
			else:
				_apply_station_power()

## Invisible wall along the platform edge so the player cannot drop onto the
## tracks. Turn off when the train / track gameplay needs it open.
@export var block_track_access: bool = true

## Spawn two placeholder passengers (one valid ticket, one invalid) that walk to
## the gates and scan, to test the fare gates before real passengers exist.
@export var spawn_test_passengers: bool = false


@export_group("Ticket Booth Noticeboard")
## Expand a note resource to edit its multiline Text and Paper Color, then save.
@export var noticeboard_notes: Array[NoticeNote] = [
	preload("res://notes/night_shift.tres"),
	preload("res://notes/staff_rota.tres"),
	preload("res://notes/power.tres"),
	preload("res://notes/security.tres"),
	preload("res://notes/lost_property.tres"),
	preload("res://notes/reminder.tres"),
	preload("res://notes/custom_1.tres"),
	preload("res://notes/custom_2.tres"),
]:
	set(value):
		noticeboard_notes = value
		if is_inside_tree() and has_node("TB_NoticeFrame"):
			_refresh_noticeboard_notes()

var _observed_notes: Array[Resource] = []

const WALL_H   : float = 7.35   # Seven metres clear in the public hall
const CEIL_H   : float = 7.35
const FLOOR_Y  : float = 0.35   # The one walking-surface height for the whole station
const FLOOR_T  : float = 0.85   # Floor slab thickness (solid from FLOOR_Y down to -0.50)
const WALL_T   : float = 0.25   # Standard wall thickness
const FRAME_DEPTH: float = 0.14 # Glazing channels sit inside the wall reveal.

var _wall_bodies: Array[StaticBody3D] = []

# Material definitions
var mat_floor_main   : Material
var mat_floor_plat   : Material
var mat_wall         : StandardMaterial3D
var mat_wall_trim    : StandardMaterial3D
var mat_ceiling      : StandardMaterial3D
var mat_track        : StandardMaterial3D
var mat_track_bed    : StandardMaterial3D
var mat_sleeper      : StandardMaterial3D
var mat_tunnel       : StandardMaterial3D
var mat_glass        : StandardMaterial3D
var mat_gate         : StandardMaterial3D
var mat_yellow_strip : StandardMaterial3D
var mat_tactile      : StandardMaterial3D
var mat_wood         : StandardMaterial3D
var mat_metal_dark   : StandardMaterial3D
var mat_status_light : StandardMaterial3D
var mat_vending_blue : StandardMaterial3D
var mat_vending_red  : StandardMaterial3D
var mat_vending_glow : StandardMaterial3D
var mat_exit_sign    : StandardMaterial3D
var mat_light_fixture : StandardMaterial3D
var mat_panel_a      : StandardMaterial3D
var mat_sign_amber   : StandardMaterial3D
var mat_panel_b      : StandardMaterial3D
var _preview_return: Transform3D
var _visiting_entity_preview: bool = false


func _ready() -> void:
	_build_materials()
	_build_station()
	if not Engine.is_editor_hint():
		var navigation := preload("res://scripts/station_navigation.gd").new()
		navigation.name = "StationNavigation"
		add_child(navigation)
		var train := preload("res://scripts/train_service.gd").new()
		train.name = "TrainService"
		add_child(train)
		var ambience := preload("res://scripts/station_audio.gd").new()
		ambience.name = "StationAmbience"
		add_child(ambience)
		var pa := preload("res://scripts/station_pa.gd").new()
		pa.name = "StationPA"
		add_child(pa)
		var jobs := preload("res://scripts/station_jobs.gd").new()
		jobs.name = "StationJobs"
		add_child(jobs)
		var entity := preload("res://scripts/passenger_entity.gd").new()
		entity.name = "PassengerEntity"
		add_child(entity)
		var manager := get_node("/root/GameManager")
		var retro := preload("res://scripts/retro_effect.gd").new()
		retro.name = "RetroEffect"
		add_child(retro)
		manager.power_changed.connect(_apply_station_power)
		manager.clock_changed.connect(_update_booth_clock)
		var hud := CanvasLayer.new()
		hud.set_script(preload("res://scripts/night_hud.gd"))
		hud.name = "NightHUD"
		add_child(hud)
		var pause_menu := CanvasLayer.new()
		pause_menu.set_script(preload("res://scripts/pause_menu.gd"))
		pause_menu.name = "PauseMenu"
		add_child(pause_menu)
		var arrival := preload("res://scripts/spawn_fade.gd").new()
		arrival.name = "SpawnFade"
		add_child(arrival)
		var passengers := Node.new()
		passengers.set_script(preload("res://scripts/passenger_director.gd"))
		passengers.name = "PassengerService"
		add_child(passengers)
		var report := preload("res://scripts/shift_report.gd").new()
		report.name = "ShiftReport"
		add_child(report)
		var services := preload("res://scripts/station_services.gd").new()
		services.name = "StationServices"
		add_child(services)
		var events := preload("res://scripts/night_events.gd").new()
		events.name = "NightEvents"
		add_child(events)
		var conversations := preload("res://scripts/passenger_dialogue_events.gd").new()
		conversations.name = "PassengerDialogueEvents"
		add_child(conversations)
		var pacing := preload("res://scripts/horror_pacing.gd").new()
		pacing.name = "HorrorPacing"
		add_child(pacing)
		var desk := preload("res://scripts/booth_desk.gd").new()
		desk.name = "BoothDesk"
		add_child(desk)
		_apply_station_power()
		_update_booth_clock()
		if manager.pending_load:
			manager.pending_load = false
			manager.call_deferred("load_game")
		Coop.call_deferred("attach_world", self)


func _unhandled_input(event: InputEvent) -> void:
	# F1 toggles the bright inspection lighting at runtime.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		debug_bright_mode = not debug_bright_mode

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		_visit_entity_preview()


func _visit_entity_preview() -> void:
	if Coop.active:
		GameManager.notice_posted.emit("Entity preview: use solo play or select EntityModelPreview in the editor.")
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var preview := get_node_or_null("EntityModelPreview") as Node3D
	if not player or not preview: return
	if _visiting_entity_preview:
		player.global_transform = _preview_return
	else:
		_preview_return = player.global_transform
		player.global_position = preview.global_position + Vector3(0, 0.05, 3.6)
		player.rotation.y = 0
		if player.get("head"): player.head.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	_visiting_entity_preview = not _visiting_entity_preview
	GameManager.notice_posted.emit("Entity model display — F2 returns to the station." if _visiting_entity_preview else "Returned to station.")


func _rebuild() -> void:
	for child in get_children():
		# Preserve player if present
		if child.name in ["Player", "EntityModelPreview", "Rooms"] or child is CharacterBody3D:
			continue
		remove_child(child)   # detach now so rebuilt nodes keep their names
		child.queue_free()
	_build_materials()
	_build_station()


# ─── MATERIALS ───────────────────────────────────────────────────────────────
func _build_materials() -> void:
	if debug_bright_mode:
		# Bright, clear architectural inspection palette
		mat_floor_main   = _mat(Color(0.66, 0.65, 0.60), 0.35, 0.0)
		mat_floor_plat   = _mat(Color(0.54, 0.55, 0.52), 0.70, 0.0)
		mat_wall         = _mat(Color(0.92, 0.91, 0.86), 0.45, 0.0)
		mat_wall_trim    = _mat(Color(0.68, 0.73, 0.71), 0.40, 0.0)
		mat_ceiling      = _mat(Color(0.95, 0.94, 0.90), 0.80, 0.0)
		mat_track        = _mat(Color(0.70, 0.72, 0.75), 0.25, 0.85) # Shiny steel
		mat_track_bed    = _mat(Color(0.38, 0.35, 0.32), 0.90, 0.0)
		mat_sleeper      = _mat(Color(0.30, 0.23, 0.18), 0.80, 0.0)
		mat_tunnel       = _mat(Color(0.28, 0.28, 0.30), 0.75, 0.0)
		mat_gate         = _mat(Color(0.92, 0.80, 0.15), 0.30, 0.5)
		mat_yellow_strip = _mat(Color(0.96, 0.85, 0.05), 0.40, 0.0)
		mat_wood         = _mat(Color(0.50, 0.33, 0.20), 0.50, 0.0)
		mat_metal_dark   = _mat(Color(0.22, 0.22, 0.25), 0.35, 0.6)
	else:
		# Warm white station finishes; darkness comes from lighting and power.
		mat_floor_main   = _mat(Color(0.60, 0.59, 0.54), 0.4, 0.0)
		mat_floor_plat   = _mat(Color(0.48, 0.50, 0.47), 0.7, 0.0)
		mat_wall         = _mat(Color(0.89, 0.88, 0.82), 0.45, 0.0)
		mat_wall_trim    = _mat(Color(0.60, 0.67, 0.64), 0.4, 0.0)
		mat_ceiling      = _mat(Color(0.92, 0.91, 0.86), 0.8, 0.0)
		mat_track        = _mat(Color(0.55, 0.55, 0.58), 0.3, 0.8)
		mat_track_bed    = _mat(Color(0.22, 0.20, 0.18), 0.9, 0.0)
		mat_sleeper      = _mat(Color(0.18, 0.14, 0.11), 0.8, 0.0)
		mat_tunnel       = _mat(Color(0.10, 0.10, 0.12), 0.8, 0.0)
		mat_gate         = _mat(Color(0.70, 0.62, 0.12), 0.4, 0.3)
		mat_yellow_strip = _mat(Color(0.90, 0.80, 0.02), 0.4, 0.0)
		mat_wood         = _mat(Color(0.35, 0.24, 0.15), 0.5, 0.0)
		mat_metal_dark   = _mat(Color(0.15, 0.15, 0.17), 0.4, 0.5)

	mat_tactile = _mat(Color(0.62, 0.50, 0.16), 0.92)
	mat_floor_main = _floor_material(Color(0.54, 0.53, 0.47), 0.6)
	mat_floor_plat = _floor_material(Color(0.38, 0.41, 0.39), 0.8)

	# Exit sign + backlit gallery panels
	mat_exit_sign = _mat(Color(0.1, 0.55, 0.2), 0.4, 0.0)
	mat_exit_sign.emission_enabled = true
	mat_exit_sign.emission = Color(0.15, 0.9, 0.3)
	mat_exit_sign.emission_energy_multiplier = 1.2
	mat_sign_amber = _mat(Color(0.9, 0.45, 0.1), 0.4, 0.0)
	mat_sign_amber.emission_enabled = true
	mat_sign_amber.emission = Color(1.0, 0.5, 0.12)
	mat_sign_amber.emission_energy_multiplier = 1.3
	mat_panel_a = _mat(Color(0.55, 0.85, 1.0), 0.3, 0.0)
	mat_panel_a.emission_enabled = true
	mat_panel_a.emission = Color(0.5, 0.8, 1.0)
	mat_panel_a.emission_energy_multiplier = 0.9
	mat_panel_b = _mat(Color(1.0, 0.8, 0.5), 0.3, 0.0)
	mat_panel_b.emission_enabled = true
	mat_panel_b.emission = Color(1.0, 0.75, 0.4)
	mat_panel_b.emission_energy_multiplier = 0.8

	# Vending machines
	mat_vending_blue = _mat(Color(0.12, 0.25, 0.55), 0.35, 0.3)
	mat_vending_red  = _mat(Color(0.65, 0.12, 0.12), 0.35, 0.3)
	mat_vending_glow = _mat(Color(0.95, 0.97, 1.0), 0.2, 0.0)
	mat_vending_glow.emission_enabled = true
	mat_vending_glow.emission = Color(0.85, 0.95, 1.0)
	mat_vending_glow.emission_energy_multiplier = 1.3

	# Shared fluorescent diffuser material follows the station power state.
	mat_light_fixture = _mat(Color(0.8, 0.85, 0.9), 0.4)
	mat_light_fixture.emission_enabled = true
	mat_light_fixture.emission = Color(1.0, 0.97, 0.91)
	mat_light_fixture.emission_energy_multiplier = 1.8

	# Gate status light (green = open)
	mat_status_light = _mat(Color(0.2, 0.9, 0.45), 0.3, 0.0)
	mat_status_light.emission_enabled = true
	mat_status_light.emission = Color(0.2, 0.9, 0.45)
	mat_status_light.emission_energy_multiplier = 1.5

	# Glass
	mat_glass = StandardMaterial3D.new()
	mat_glass.albedo_color = Color(0.6, 0.85, 1.0, 0.3)
	mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass.roughness = 0.05
	mat_glass.metallic = 0.2


func _mat(c: Color, rough: float = 0.5, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


# ─── MAIN BUILD ───────────────────────────────────────────────────────────────
func _build_station() -> void:
	_wall_bodies.clear()
	# ── COORDINATE SYSTEM ──
	# X: -26 … +26 (East (+) / West (-))
	# Z: -16 … +24 (North (+platform/tracks) / South (-entrance))
	# Y: FLOOR_Y (0.35) is the single floor surface for the whole station.
	#    The track trench (Z = 18 … 24) is untouched: ballast, sleepers, rails
	#    and the platform edge keep exactly the levels they always had.

	# 1. Station floor — one continuous, level slab set at FLOOR_Y
	_build_floors()

	# 2. Zones
	_build_entrance_hallway()
	_build_central_concourse()
	_build_side_rooms()
	_build_platform_and_tracks()
	_build_corner_returns()
	for room in $Rooms.get_children():
		for body in room.get_children():
			if body is StaticBody3D and body.is_in_group("authored_room_wall"):
				_wall_bodies.append(body)
	_build_ceiling_and_roof()
	_build_lighting()
	_build_tactile_routes()
	var detail := preload("res://scripts/station_detail.gd").new()
	add_child(detail)
	# Cache nominal energies once; runtime F1 changes lighting without rebuilding.
	for child in get_children():
		if child is Light3D and child.name != "DebugSunlight":
			child.add_to_group("station_lights")
			child.set_meta("nominal_energy", child.light_energy / (2.0 if debug_bright_mode else 1.0))
	if spawn_test_passengers and not Engine.is_editor_hint():
		_spawn_test_passengers()


func _floor_material(color: Color, tile_size: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/materials/station_floor.gdshader")
	material.set_shader_parameter("stone_color", color)
	material.set_shader_parameter("tile_size", tile_size)
	return material


func _detail_box(n: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = n
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func _detail_instances(n: String, mesh: Mesh, material: Material, transforms: Array[Transform3D]) -> void:
	var node := MultiMeshInstance3D.new()
	node.name = n
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.mesh = mesh
	node.multimesh.instance_count = transforms.size()
	for index in range(transforms.size()): node.multimesh.set_instance_transform(index, transforms[index])
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _tactile_strip(n: String, start: Vector3, end: Vector3) -> void:
	var direction := (end - start).normalized()
	var length := start.distance_to(end)
	var yaw := atan2(direction.x, direction.z)
	var rotation := Basis(Vector3.UP, yaw)
	var across := rotation.x
	var bed := _detail_box(n + "_Bed", Vector3(0.6, 0.01, length), (start + end) * 0.5 + Vector3.UP * 0.005, mat_tactile)
	bed.rotation.y = yaw
	var rib := BoxMesh.new()
	rib.size = Vector3(0.028, 0.008, 0.51)
	var transforms: Array[Transform3D] = []
	var count := maxi(1, floori(length / 0.6))
	for tile in range(count):
		var center := start + direction * ((tile + 0.5) * length / count)
		for line in range(6):
			transforms.append(Transform3D(rotation, center + across * ((line - 2.5) * 0.085) + Vector3.UP * 0.014))
	_detail_instances(n + "_RaisedRibs", rib, mat_tactile, transforms)


func _tactile_warning(n: String, at: Vector3, size: Vector2) -> void:
	_detail_box(n + "_Bed", Vector3(size.x, 0.01, size.y), at + Vector3.UP * 0.005, mat_tactile)
	var stud := CylinderMesh.new()
	stud.top_radius = 0.017
	stud.bottom_radius = 0.023
	stud.height = 0.008
	stud.radial_segments = 8
	stud.rings = 1
	var transforms: Array[Transform3D] = []
	var columns := maxi(1, floori(size.x / 0.12))
	var rows := maxi(1, floori(size.y / 0.12))
	for x in range(columns):
		for z in range(rows):
			transforms.append(Transform3D(Basis.IDENTITY, at + Vector3((x + 0.5) * size.x / columns - size.x * 0.5, 0.014, (z + 0.5) * size.y / rows - size.y * 0.5)))
	_detail_instances(n + "_RaisedStuds", stud, mat_tactile, transforms)


func _build_tactile_routes() -> void:
	# Follow a clear gate lane, avoiding pillars, bench islands and the track edge.
	_tactile_strip("TactileEntrance", Vector3(-0.65, FLOOR_Y, -20.7), Vector3(-0.65, FLOOR_Y, 1.7))
	_tactile_strip("TactileGateRoute", Vector3(-0.65, FLOOR_Y, 2.3), Vector3(-0.65, FLOOR_Y, 16.2))
	_tactile_strip("TactileTicketRoute", Vector3(-0.95, FLOOR_Y, 2), Vector3(-6.05, FLOOR_Y, 2))
	_tactile_strip("TactileTicketApproach", Vector3(-6.35, FLOOR_Y, 2.3), Vector3(-6.35, FLOOR_Y, 3.8))
	_tactile_strip("TactilePlatformRoute", Vector3(-25, FLOOR_Y, 16.5), Vector3(25, FLOOR_Y, 16.5))
	_tactile_warning("TactileMainJunction", Vector3(-0.65, FLOOR_Y, 2), Vector2(0.6, 0.6))
	_tactile_warning("TactileTicketJunction", Vector3(-6.35, FLOOR_Y, 2), Vector2(0.6, 0.6))
	_tactile_warning("PlatformTactileWarning", Vector3(0, FLOOR_Y, 18.65), Vector2(50, 0.6))


func _rail_segment(n: String, start: Vector3, end: Vector3, radius: float, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = n
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = start.distance_to(end)
	mesh.radial_segments = 10
	node.mesh = mesh
	node.material_override = material
	node.position = (start + end) * 0.5
	node.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	add_child(node)


# ─── 0. FLOORS (one level surface across the entire station) ─────────────────
func _build_floors() -> void:
	# Every floor piece shares the same top surface (FLOOR_Y) and the same
	# thickness, so they butt together flush — no lips, no height changes and
	# no gaps under walls. Pieces tile the footprint without overlapping, which
	# keeps the top faces from z-fighting.
	var cy: float = FLOOR_Y - FLOOR_T * 0.5

	box("Floor_Hall", Vector3(32.0, FLOOR_T, 16.0), Vector3(0.0, cy, -8.0), mat_floor_main)
	box("Floor_Concourse", Vector3(32.0, FLOOR_T, 10.0), Vector3(0.0, cy, 5.0), mat_floor_main)
	box("Floor_Platform", Vector3(52.0, FLOOR_T, 9.4), Vector3(0.0, cy, 14.7), mat_floor_plat)

	# Only the accessible smoking room needs a floor west of the main hall.
	# No filler room remains behind the concourse / ticket booth.
	box("Floor_SmokingRoom", Vector3(4.0, FLOOR_T, 16.0), Vector3(-18.0, cy, -8.0), mat_floor_main)
	box("Floor_EastFill", Vector3(1.0, FLOOR_T, 26.0), Vector3(25.5, cy, -3.0), mat_floor_main)

	# Level threshold/apron outside the entrance doors
	box("Floor_Apron", Vector3(32.0, FLOOR_T, 4.0), Vector3(0.0, cy, -18.0), mat_floor_main)


# ─── 1. ENTRANCE HALLWAY (Z: -16 to 0, X: -16 to +16) ────────────────────────
func _build_entrance_hallway() -> void:
	# South Wall (Entrance) with centered double door opening
	# Door opening: X: -1.6 to +1.6 (width 3.2m, height 2.6m above FLOOR_Y)
	glass_wall("Hall_South_L", 14.4, Vector3(-8.8, 0.0, -16.0), true)
	# Lounge door (east gallery room) at X = 9.0, width 1.2 (X: 8.4 … 9.6)
	glass_wall("Hall_South_R1", 6.8, Vector3(5.0, 0.0, -16.0), true)
	glass_wall("Hall_South_R2", 6.4, Vector3(12.8, 0.0, -16.0), true)
	var room_top: float = FLOOR_Y + 2.4
	wall("LoungeDoor_Header", Vector3(1.2, WALL_H - room_top, WALL_T), Vector3(9.0, room_top + (WALL_H - room_top) * 0.5, -16.0))
	door_frame("LoungeDoor", Vector3(9.0, FLOOR_Y, -16.0), 1.2, 2.4, false, true)
	_door_sign("LoungeSign", "LOUNGE", Vector3(9.0, FLOOR_Y + 2.95, -15.82), 0.0, 1.1)
	# Header above entrance doors
	var ent_top: float = FLOOR_Y + 2.6
	wall("Hall_South_Header", Vector3(3.2, WALL_H - ent_top, WALL_T), Vector3(0.0, ent_top + (WALL_H - ent_top) * 0.5, -16.0))
	door_frame("EntranceDoors", Vector3(0.0, FLOOR_Y, -16.0), 3.2, 2.6)

	# Green EXIT sign over the tunnel mouth
	box("ExitSign", Vector3(1.0, 0.26, 0.05), Vector3(0.0, FLOOR_Y + 2.9, -15.8), mat_exit_sign)
	var exit_lbl := Label3D.new()
	exit_lbl.name = "ExitSignLabel"
	exit_lbl.text = "EXIT"
	exit_lbl.font_size = 56
	exit_lbl.pixel_size = 0.004
	exit_lbl.modulate = Color(0.9, 1.0, 0.9)
	exit_lbl.outline_size = 0
	exit_lbl.position = Vector3(0.0, FLOOR_Y + 2.9, -15.77)
	add_child(exit_lbl)

	# The station is underground: the entrance is a tunnel that climbs to a
	# (closed) street exit, and the glass walls look into a lit service gallery.
	_build_entrance_tunnel()

	# West Wall of Hallway
	# Smoking-room glass door at Z = -3.0, 1.8 m wide x 2.6 m tall (Z: -3.9 … -2.1)
	glass_wall("Hall_West_A", 12.1, Vector3(-16.0, 0.0, -9.95), false)
	glass_wall("Hall_West_B", 2.1, Vector3(-16.0, 0.0, -1.05), false)
	var smoke_top: float = FLOOR_Y + 2.6
	wall("SmokingDoor_Header", Vector3(WALL_T, WALL_H - smoke_top, 1.8), Vector3(-16.0, smoke_top + (WALL_H - smoke_top) * 0.5, -3.0))
	door_frame("SmokingDoor", Vector3(-16.0, FLOOR_Y, -3.0), 1.8, 2.6, true, true, true)
	_door_sign("SmokingSign", "SMOKING ROOM", Vector3(-15.82, FLOOR_Y + 2.92, -3.0), 90.0, 1.5)
	_build_smoking_room()

	# Architectural columns down hallway
	for px in [-4.0, 4.0]:
		for pz in [-12.0, -4.0]:
			pillar("HallPillar_%s_%s" % [px, pz], Vector3(px, FLOOR_Y, pz), CEIL_H - FLOOR_Y)
	# Use the original wood-and-metal benches throughout passenger areas.
	# Matched back-to-back islands outside the structural columns, with broad
	# cross aisles between islands and an uninterrupted central promenade.
	for x in [-11.0, -7.0, 7.0, 11.0]:
		for z in [-11.0, -4.8]:
			_bench_pair("HallBench_%s_%s" % [x, z], Vector3(x, FLOOR_Y, z))
	for x in [4.5, 8.0, 11.5]:
		bench("LoungeBench_" + str(x), Vector3(x, FLOOR_Y, -18.9))


# ─── 2. CENTRAL CONCOURSE & GATES (Z: 0 to 10) ───────────────────────────────
func _build_central_concourse() -> void:
	# West wall — closes the concourse the same way the east side is closed
	# (the floor used to drop away into an open, unfloored strip here).
	wall("Conc_West", Vector3(WALL_T, WALL_H, 10.0), Vector3(-16.0, WALL_H * 0.5, 5.0))

	# ── A. TICKET BOOTH (West side: X: -16.0 to -7.0, Z: 1.0 to 7.0) ──
	# The booth shares Conc_West as its back wall, with no gap or duplicate wall.
	var tb_w := 9.0
	var tb_d := 6.0
	var tb_cx := -11.5
	var tb_cz := 4.0

	# North wall
	wall("TB_North", Vector3(tb_w, WALL_H, WALL_T), Vector3(tb_cx, WALL_H * 0.5, 7.0))
	# South wall with staff entry door (width 1.2m at X = -10.0)
	var tb_top: float = FLOOR_Y + 2.4
	wall("TB_South_L", Vector3(5.4, WALL_H, WALL_T), Vector3(-13.3, WALL_H * 0.5, 1.0))
	wall("TB_South_Header", Vector3(1.2, WALL_H - tb_top, WALL_T), Vector3(-10.0, tb_top + (WALL_H - tb_top) * 0.5, 1.0))
	wall("TB_South_R", Vector3(2.4, WALL_H, WALL_T), Vector3(-8.2, WALL_H * 0.5, 1.0))
	door_frame("TB_StaffDoor", Vector3(-10.0, FLOOR_Y, 1.0), 1.2, 2.4, false, true)

	# Front service window wall facing Concourse (at X = -7.0)
	# Lower solid counter wall (height 1.0m above the floor)
	wall("TB_Front_Low", Vector3(WALL_T, 1.0, tb_d), Vector3(-7.0, FLOOR_Y + 0.5, tb_cz))
	# Counter shelf
	box("TB_Counter", Vector3(0.36, 0.06, tb_d - WALL_T), Vector3(-7.0, FLOOR_Y + 1.03, tb_cz), mat_metal_dark)
	# One clear visual surface, with separate collision around the document slot.
	_build_ticket_window()
	_build_document_tray("TB_DocTray", Vector3(-7.0, FLOOR_Y + 1.06, tb_cz))
	# Upper header wall (closes the gap up to the ceiling)
	var tb_high_bottom: float = FLOOR_Y + 2.55
	wall("TB_Front_High", Vector3(WALL_T, WALL_H - tb_high_bottom, tb_d), Vector3(-7.0, tb_high_bottom + (WALL_H - tb_high_bottom) * 0.5, tb_cz))

	# Furniture inside booth
	# Desk runs along the service window (long axis = Z); the clerk sits on its
	# west side facing east through the window.
	box("TB_Desk", Vector3(0.8, 0.85, 5.0), Vector3(-7.6, FLOOR_Y + 0.425, tb_cz), mat_wall_trim)
	_build_chair_east("TB_Chair", Vector3(-8.9, FLOOR_Y, tb_cz))
	# Computer monitor & keyboard (off to the side so the slot stays clear)
	box("TB_Monitor_Stand", Vector3(0.12, 0.2, 0.12), Vector3(-7.75, FLOOR_Y + 0.95, 5.3), mat_metal_dark)
	box("TB_Monitor", Vector3(0.05, 0.45, 0.6), Vector3(-7.75, FLOOR_Y + 1.25, 5.3), mat_metal_dark)
	box("TB_Keyboard", Vector3(0.16, 0.02, 0.45), Vector3(-7.9, FLOOR_Y + 0.86, 5.3), mat_metal_dark)
	_booth_prop("TB_InspectionMat", Vector3(0.55, 0.015, 0.8), Vector3(-7.63, FLOOR_Y + 0.8625, 4.0), mat_metal_dark)
	if not Engine.is_editor_hint():
		invisible_wall("TB_InspectionConsole", Vector3(0.5, 0.18, 0.66), Vector3(-7.63, FLOOR_Y + 0.965, 4.0))
	_build_booth_interior()

	# ── B. PASSENGER TURNSTILE GATES — built into the fare barrier (see D) ──

	# ── C. WAITING AREA (East side: X: +2.0 to +16.0, Z: 1.0 to 9.0) ──
	for x in [7.0, 11.0]:
		for z in [2.0, 6.0]:
			_bench_pair("WaitingBench_%s_%s" % [x, z], Vector3(x, FLOOR_Y, z))

	# Continue the hall's column lines; no isolated column inside the seating.
	for px in [-4.0, 4.0]:
		pillar("ConcoursePillar_" + str(px), Vector3(px, FLOOR_Y, 4.0), CEIL_H - FLOOR_Y)

	# ── D. FARE BARRIER (Z = 10.0) ──
	# Glass-band wall separating the paid platform from the concourse. The 5
	# turnstiles sit IN the wall line (centred on X = 0), so the 4 lanes between
	# them are the only way through. The wider platform has a solid return at
	# its west end, so the barrier cannot expose empty space behind the concourse.
	var gate_pitch: float = 1.3
	var gate_half: float = gate_pitch * 2.0 + 0.15   # outer face of the end housings = 2.75
	for i in range(5):
		# The last pedestal has no lane east of it, so it keeps a decorative scanner;
		# the other four get a working scanner from their Gate lane.
		turnstile("Gate_" + str(i), Vector3((float(i) - 2.0) * gate_pitch, FLOOR_Y, 10.0), i == 4)
	for i in range(4):
		var lane := Gate.new()
		lane.name = "GateLane_" + str(i)
		lane.lane_width = gate_pitch - 0.3
		lane.position = Vector3((float(i) - 1.5) * gate_pitch, FLOOR_Y, 10.0)
		add_child(lane)
	var west_len: float = (-gate_half) - (-16.0)
	var east_len: float = 16.0 - gate_half
	wall("Platform_WestReturn", Vector3(10.0, WALL_H, WALL_T), Vector3(-21.0, WALL_H * 0.5, 10.0))
	glass_wall("FareBarrier_W", west_len, Vector3(-16.0 + west_len * 0.5, 0.0, 10.0), true)
	glass_wall("FareBarrier_E", east_len, Vector3(gate_half + east_len * 0.5, 0.0, 10.0), true)
	wall("FareBarrier_Corner", Vector3(1.0, WALL_H, WALL_T), Vector3(25.5, WALL_H * 0.5, 10.0))

	# Vending machines on BOTH faces of the barrier (concourse side faces south,
	# platform side faces north), either side of the gates.
	var vm_i: int = 0
	for vx in [-10.0, -8.7, 6.0, 7.3]:
		vending_machine("VM_Concourse_" + str(vm_i), Vector3(vx, FLOOR_Y, 10.0 - WALL_T * 0.5 - 0.4), -1.0, vm_i % 2 == 0)
		vending_machine("VM_Platform_" + str(vm_i), Vector3(vx, FLOOR_Y, 10.0 + WALL_T * 0.5 + 0.4), 1.0, vm_i % 2 == 1)
		vm_i += 1


# ─── 3. SIDE ROOMS (East Wing: X: 16 to 25, Z: -6 to 10) ────────────────────
func _build_side_rooms() -> void:
	# The frames and surrounding walls are authored in the room scenes.
	_add_interactive_door("StorageDoor", to_local($Rooms/Storage/Doorway.global_position), 1.2, 2.4, true, false, false, false)
	_add_interactive_door("SecurityDoor", to_local($Rooms/Security/Doorway.global_position), 1.2, 2.4, true, false, false, true)
	_add_interactive_door("ElecDoor", to_local($Rooms/Electrical/Doorway.global_position), 1.2, 2.4, true, false, true, false)

	# Electrical Breaker Panels on East wall
	var panel := box("ElecPanel_1", Vector3(0.18, 1.6, 1.0), Vector3(24.85, FLOOR_Y + 1.5, 6.5), mat_metal_dark)
	if not Engine.is_editor_hint():
		InteractionComponent.attach(panel, _use_breaker, _breaker_prompt, 1.5)
	var light_panel := box("ElecPanel_2", Vector3(0.18, 1.6, 1.0), Vector3(24.85, FLOOR_Y + 1.5, 8.5), mat_metal_dark)
	if not Engine.is_editor_hint():
		InteractionComponent.attach(light_panel, func() -> void: get_node("StationJobs").repair_light(), func() -> String: return "[Hold E] Service hall lighting", 1.5)


# ─── 4. PLATFORM & TRACKS (Z: 10 to 24, X: -26 to +26) ───────────────────────
func _build_platform_and_tracks() -> void:
	# ── PLATFORM (Z: 10.0 to 19.4) ──
	# The platform is part of the one level floor surface (see _build_floors).

	# Platform Yellow Safety Warning Line along track edge (Z = 19.15)
	box("PlatformYellowEdge", Vector3(52.0, 0.02, 0.30), Vector3(0.0, FLOOR_Y + 0.01, 19.15), mat_yellow_strip)
	if not Engine.is_editor_hint():
		var inspection := Area3D.new()
		inspection.name = "PlatformInspection"
		inspection.collision_layer = 0
		inspection.collision_mask = 2
		var shape := BoxShape3D.new()
		shape.size = Vector3(50, 2, 5.5)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		inspection.position = Vector3(0, FLOOR_Y + 1.0, 14)
		inspection.add_child(collision)
		inspection.body_entered.connect(_on_platform_entered)
		add_child(inspection)

	# Aligned paired islands, rather than staggered rows threaded around pillars.
	for bx in [-23.0, -14.0, -5.0, 5.0, 14.0, 23.0]:
		_bench_pair("PlatformBench_" + str(bx), Vector3(bx, FLOOR_Y, 13.5))

	# Platform Support Pillars
	for px in [-18.0, -9.0, 0.0, 9.0, 18.0]:
		pillar("PlatPillar_" + str(px), Vector3(px, FLOOR_Y, 15.0), WALL_H - FLOOR_Y)

	# West and East Platform End Walls — platform only (Z:10-19.4), NOT trench zone
	# The tunnel portals sit at X=±26 in the trench zone, so no wall there
	wall("Plat_West", Vector3(WALL_T, WALL_H, 9.4), Vector3(-26.0, WALL_H * 0.5, 14.7))
	wall("Plat_East", Vector3(WALL_T, WALL_H, 9.4), Vector3(26.0, WALL_H * 0.5, 14.7))

	# ── TRACK TRENCH (Z: 19.4 to 24.0, X: -40.0 to +40.0) ──
	# The platform surface is at Y = 0.35.
	# The trench floor sits at Y = -0.55 (about 0.9 m below platform surface).
	# Geometry builds bottom-up: floor → ballast → sleepers → rails.

	const TRENCH_Y    : float = -0.55   # trench floor
	const BALLAST_Y   : float = -0.30   # top of ballast bed
	const SLEEPER_Y   : float = -0.22   # top of sleepers
	const RAIL_TOP_Y  : float = -0.10   # top of rails
	const TRACK_Z     : float = 21.0    # centre of track run
	const TRENCH_Z1   : float = 19.4    # south edge (platform drop)
	const TRENCH_Z2   : float = 24.0    # north wall
	const TRENCH_LEN  : float = 4.6     # TRENCH_Z2 - TRENCH_Z1
	const TRENCH_CZ   : float = 21.7    # (TRENCH_Z1 + TRENCH_Z2) * 0.5

	# 1. Trench floor slab (sits below the ballast)
	box("TrenchFloor", Vector3(80.0, 0.10, TRENCH_LEN),
		Vector3(0.0, TRENCH_Y - 0.05, TRENCH_CZ), mat_track_bed)

	# 2. South trench face — the vertical drop from the platform edge (Y = FLOOR_Y) to trench floor
	#    This is the wall the player sees when standing on the platform looking at the tracks.
	var face_h : float = FLOOR_Y - TRENCH_Y  # = 0.90 m
	box("TrenchFace_South", Vector3(80.0, face_h, WALL_T),
		Vector3(0.0, TRENCH_Y + face_h * 0.5, TRENCH_Z1), mat_floor_plat)

	# 3. North Wall behind the tracks (full-height station wall)
	wall("Outer_North", Vector3(56.0, WALL_H + 0.5, WALL_T),
		Vector3(0.0, (WALL_H + 0.5) * 0.5, TRENCH_Z2))

	# 4. Ballast bed (the gravel mound the sleepers sit on)
	var ballast_h : float = BALLAST_Y - TRENCH_Y  # = 0.25 m
	box("TrackBallast", Vector3(80.0, ballast_h, TRENCH_LEN),
		Vector3(0.0, TRENCH_Y + ballast_h * 0.5, TRENCH_CZ), mat_track_bed)

	# 5. Sleepers (railroad ties) — every 0.8 m along X axis
	var sleeper_h : float = SLEEPER_Y - BALLAST_Y   # = 0.08 m
	var sleepers := StaticBody3D.new()
	sleepers.name = "TrackSleepers"
	add_child(sleepers)
	var instance := MultiMeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.24, sleeper_h, 2.6)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = 99
	instance.multimesh = multi
	instance.material_override = mat_sleeper
	sleepers.add_child(instance)
	var shared_shape := BoxShape3D.new()
	shared_shape.size = mesh.size
	for i in range(-49, 50):
		var point := Vector3(float(i) * 0.8, BALLAST_Y + sleeper_h * 0.5, TRACK_Z)
		multi.set_instance_transform(i + 49, Transform3D(Basis.IDENTITY, point))
		var collision := CollisionShape3D.new()
		collision.shape = shared_shape
		collision.position = point
		sleepers.add_child(collision)

	# 6. Rails — two continuous steel rails, 1.5 m gauge (±0.75 m from track centre)
	var rail_h : float = RAIL_TOP_Y - SLEEPER_Y   # = 0.12 m
	box("Rail_South", Vector3(80.0, rail_h, 0.10),
		Vector3(0.0, SLEEPER_Y + rail_h * 0.5, TRACK_Z - 0.75), mat_track)
	box("Rail_North", Vector3(80.0, rail_h, 0.10),
		Vector3(0.0, SLEEPER_Y + rail_h * 0.5, TRACK_Z + 0.75), mat_track)

	# ── TUNNEL PORTALS & TUBES ───────────────────────────────────────────────────
	# The station outer walls end at X = ±26. Beyond that are the tunnels.
	# Portal = a solid wall face at X=±26 with a rectangular cutout for the train.
	# Cutout: Z = TRACK_Z ± 1.6 (3.2 m wide), Y = TRENCH_Y to 2.8 (3.33 m tall)
	# Arch approximation: stacked horizontal slabs above the spring line (Y=2.0)
	# Tube: solid box tunnel extending ±24 m beyond the portal face.

	# ── TUNNEL CONSTANTS ──────────────────────────────────────────────────────────
	# Train opening: centred on TRACK_Z=21, width 3.2m (Z: 19.4 to 22.6)
	# Opening bottom = TRENCH_Y = -0.55, rect section up to T_SPRING_Y = 2.0
	# Arch from Y=2.0 up to crown Y=3.6 (radius 1.6 = half of 3.2m)
	# Portal wall face is at X = ±26 (inner face, visible from platform)
	# Portal pieces ARE the wall — no separate fill wall needed here.
	var T_HW        : float = 1.6    # half-width of opening
	var T_SPRING    : float = 2.0    # arch spring line Y
	var T_R         : float = 1.6    # arch radius
	var T_CROWN     : float = T_SPRING + T_R   # = 3.6
	var T_WALL_H    : float = WALL_H + 0.5     # = 4.1 — full portal height
	var T_THICK     : float = 0.35   # portal wall thickness (along X)
	var T_TUBE      : float = 26.0   # tunnel tube length beyond portal
	var T_NSEG      : int   = 12

	# Trench Z extents (already defined above as consts but redeclare as var for clarity)
	var TZ1 : float = TRENCH_Z1   # Platform edge at the train sill.
	var TZ2 : float = TRENCH_Z2   # = 24.0  north edge
	var TCZ : float = TRACK_Z    # Keep the tunnel centred on the rails, independently of platform width.

	for side in [-1.0, 1.0]:
		# Inner face of portal wall sits exactly at X = side*26
		# Wall extends outward (away from station) by T_THICK
		var face_x  : float = side * 26.0
		var cx      : float = face_x + side * T_THICK * 0.5  # centre of wall slab
		var s       : String = str(int(side))

		# ── 1. South column (Z: TZ1 → TCZ-T_HW = 18→19.4) ───────────────────
		var sc_z1 : float = TZ1
		var sc_z2 : float = TCZ - T_HW          # = 19.4
		var sc_w  : float = sc_z2 - sc_z1       # = 1.4
		if sc_w > 0.01:
			box("TPortal_S_" + s,
				Vector3(T_THICK, T_WALL_H, sc_w),
				Vector3(cx, T_WALL_H * 0.5, sc_z1 + sc_w * 0.5),
				mat_tunnel)

		# ── 2. North column (Z: TCZ+T_HW → TZ2 = 22.6→24) ───────────────────
		var nc_z1 : float = TCZ + T_HW          # = 22.6
		var nc_z2 : float = TZ2
		var nc_w  : float = nc_z2 - nc_z1       # = 1.4
		box("TPortal_N_" + s,
			Vector3(T_THICK, T_WALL_H, nc_w),
			Vector3(cx, T_WALL_H * 0.5, nc_z1 + nc_w * 0.5),
			mat_tunnel)

		# ── 3. Header slab above arch crown (Y: T_CROWN → T_WALL_H) ──────────
		var hdr_h : float = T_WALL_H - T_CROWN
		box("TPortal_Hdr_" + s,
			Vector3(T_THICK, hdr_h, TZ2 - TZ1),
			Vector3(cx, T_CROWN + hdr_h * 0.5, TCZ),
			mat_tunnel)

		# ── 4. Arch crown slabs (Y: T_SPRING → T_CROWN, left+right of opening) ─
		var seg_h : float = T_R / float(T_NSEG)
		for i in range(T_NSEG):
			var ym   : float = T_SPRING + (float(i) + 0.5) * seg_h
			var dy   : float = ym - T_SPRING
			var hw   : float = sqrt(max(T_R * T_R - dy * dy, 0.0))
			# South slab: from TZ1 to (TCZ - hw)
			var sw : float = (TCZ - hw) - TZ1
			if sw > 0.005:
				box("TArch_S_" + s + "_" + str(i),
					Vector3(T_THICK, seg_h + 0.01, sw),
					Vector3(cx, ym, TZ1 + sw * 0.5),
					mat_tunnel)
			# North slab: from (TCZ + hw) to TZ2
			var nw : float = TZ2 - (TCZ + hw)
			if nw > 0.005:
				box("TArch_N_" + s + "_" + str(i),
					Vector3(T_THICK, seg_h + 0.01, nw),
					Vector3(cx, ym, TZ2 - nw * 0.5),
					mat_tunnel)

		# ── 5. Tunnel tube (4 walls extending outward from portal) ────────────
		var tube_cx : float = face_x + side * (T_THICK + T_TUBE * 0.5)
		var open_h  : float = T_CROWN - TRENCH_Y
		# South wall of tube
		box("TTube_WS_" + s,
			Vector3(T_TUBE, open_h, 0.30),
			Vector3(tube_cx, TRENCH_Y + open_h * 0.5, TCZ - T_HW - 0.15),
			mat_tunnel)
		# North wall of tube
		box("TTube_WN_" + s,
			Vector3(T_TUBE, open_h, 0.30),
			Vector3(tube_cx, TRENCH_Y + open_h * 0.5, TCZ + T_HW + 0.15),
			mat_tunnel)
		# Ceiling of tube
		box("TTube_Ceil_" + s,
			Vector3(T_TUBE, 0.30, T_HW * 2.0 + 0.60),
			Vector3(tube_cx, T_CROWN + 0.15, TCZ),
			mat_tunnel)
		# Floor of tube
		box("TTube_Floor_" + s,
			Vector3(T_TUBE, 0.20, T_HW * 2.0 + 0.60),
			Vector3(tube_cx, TRENCH_Y - 0.10, TCZ),
			mat_track_bed)

	# Invisible guard along the platform edge (see block_track_access).
	if block_track_access:
		invisible_wall("TrackGuard", Vector3(54.0, 4.0, 0.2), Vector3(0.0, 2.0, TRENCH_Z1 + 0.1))

	# Ceiling_Main already covers the trench, and Outer_North seals its back.
	# Do not overlay duplicate slabs on those surfaces.


# ─── 5. CEILING & ROOF ───────────────────────────────────────────────────────
func _build_ceiling_and_roof() -> void:
	# Main ceiling slab — spans entrance + concourse + platform + trench (Z: -16 to 24)
	box("Ceiling_Main", Vector3(54.0, WALL_T, 40.0), Vector3(0.0, CEIL_H + WALL_T * 0.5, 4.0), mat_ceiling)


# ─── 6. LIGHTING & ENVIRONMENT ───────────────────────────────────────────────
func _build_lighting() -> void:
	# Environment
	var env := Environment.new()
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"

	if debug_bright_mode:
		# Bright studio inspection daylight
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.76, 0.82, 0.90)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.90, 0.92, 0.96)
		env.ambient_light_energy = 0.95

		# Overhead work sunlight
		var sun := DirectionalLight3D.new()
		sun.name = "DebugSunlight"
		sun.light_color = Color(1.0, 0.98, 0.94)
		sun.light_energy = 1.3
		sun.rotation_degrees = Vector3(-55, 30, 0)
		sun.shadow_enabled = true
		sun.shadow_opacity = 0.3
		add_child(sun)
	else:
		# Atmospheric night mode
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.02, 0.02, 0.03)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.08, 0.08, 0.10)
		env.ambient_light_energy = 0.10

	we.environment = env
	add_child(we)
	if not has_node("DebugSunlight"):
		var sun := DirectionalLight3D.new()
		sun.name = "DebugSunlight"
		sun.light_energy = 1.3
		sun.rotation_degrees = Vector3(-55, 30, 0)
		sun.visible = false
		add_child(sun)

	# Station electric lights
	var light_mult: float = 2.0 if debug_bright_mode else 1.0

	# Even coverage across the full width, including the station's outer ends.
	for px in [-22.0, -16.0, -10.0, -4.0, 2.0, 8.0, 14.0, 20.0]:
		_ceiling_light("PlatLight_" + str(px), Vector3(px, CEIL_H - 0.3, 14.0), 3.2 * light_mult, 7.0)
	for lx in [-11.0, 0.0, 11.0]:
		for lz in [2.5, 7.5]:
			_ceiling_light("ConcourseLight_%s_%s" % [lx, lz], Vector3(lx, CEIL_H - 0.3, lz), 2.8 * light_mult, 8.0)
	for lx in [-10.0, 0.0, 10.0]:
		for lz in [-13.0, -8.0, -3.0]:
			_ceiling_light("HallLight_%s_%s" % [lx, lz], Vector3(lx, CEIL_H - 0.3, lz), 2.8 * light_mult, 8.0)
	# Warm service lamp keeps kiosk products readable under its canopy.
	var kiosk_lamp := OmniLight3D.new()
	kiosk_lamp.name = "KioskTaskLight"
	kiosk_lamp.position = Vector3(-13.8, 2.1, -13.65)
	kiosk_lamp.light_color = Color(1.0, 0.74, 0.42)
	kiosk_lamp.light_energy = 0.7 * light_mult
	kiosk_lamp.omni_range = 3.0
	kiosk_lamp.shadow_enabled = true
	add_child(kiosk_lamp)
	# Room lights cast shadows so their light stays inside the walls.
	for room in [
		["Restroom", Vector3(23.5, CEIL_H - 0.3, -7.5)],
		["RestroomMen", Vector3(23.5, CEIL_H - 0.3, -2.5)],
		["RestroomWomenWest", Vector3(29.5, 3.25, -9)],
		["RestroomWomenEast", Vector3(37, 3.25, -9)],
		["RestroomWomenStalls", Vector3(33, 3.25, -13.3)],
		["RestroomMenWest", Vector3(29.5, 3.25, -1)],
		["RestroomMenEast", Vector3(37, 3.25, -1)],
		["RestroomMenStalls", Vector3(33, 3.25, 3.3)],
		["Security", Vector3(20.5, CEIL_H - 0.3, 2.5)],
		["Electrical", Vector3(20.5, CEIL_H - 0.3, 7.5)],
		["Booth", Vector3(-11.0, CEIL_H - 0.3, 4.0)],
		["Lounge", Vector3(9.0, CEIL_H - 0.3, -18.0)],
		["SmokingSouth", Vector3(-18.0, CEIL_H - 0.3, -11.0)],
		["SmokingNorth", Vector3(-18.0, CEIL_H - 0.3, -4.0)],
	]:
		_ceiling_light("RoomLight_" + room[0], room[1], 2.6 * light_mult, 7.0, true)
	_ceiling_light("RoomLight_Storage", Vector3(20.5, CEIL_H - 0.3, -11), 2.6 * light_mult, 7, true)


func _ceiling_light(n: String, pos: Vector3, energy: float, reach: float, shadows: bool = false) -> void:
	# Suspended fittings keep usable light at human level in the high station hall.
	pos.y = minf(pos.y, FLOOR_Y + (2.6 if "Restroom" in n else 4.5))
	var public_space: bool = not n.begins_with("RoomLight_")
	var light: Light3D = SpotLight3D.new() if public_space else OmniLight3D.new()
	light.name = n
	light.position = pos
	light.light_energy = energy * (0.85 if public_space else 0.65)
	light.light_color = Color(0.78, 0.87, 0.86) if public_space else Color(1.0, 0.86, 0.65)
	if light is SpotLight3D:
		light.rotation_degrees.x = -90
		light.spot_range = 9.0
		light.spot_angle = 57.0
		light.spot_attenuation = 1.2
		light.spot_angle_attenuation = 1.4
	else:
		light.omni_range = reach
	light.shadow_enabled = shadows or (public_space and absf(pos.x) < 3.0)
	add_child(light)
	# Visible ceiling diffuser, without adding another physics body.
	var fixture := MeshInstance3D.new()
	fixture.name = n + "_Fixture"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.5, 0.06, 0.32)
	fixture.mesh = mesh
	fixture.material_override = mat_light_fixture
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fixture.position = pos + Vector3(0, 0.23, 0)
	add_child(fixture)
	var drop: float = CEIL_H - fixture.position.y - 0.03
	if drop > 0:
		_booth_prop(n + "_Suspension", Vector3(0.025, drop, 0.025), fixture.position + Vector3(0, 0.03 + drop * 0.5, 0), mat_metal_dark)

func _apply_station_power(_powered: bool = true) -> void:
	var manager := get_node_or_null("/root/GameManager")
	var on: bool = manager.powered if manager else true
	for child in get_children():
		if child is Light3D:
			if child.name == "DebugSunlight":
				child.visible = debug_bright_mode and on
			else:
				child.light_energy = float(child.get_meta("nominal_energy", 1.0)) * (2.0 if debug_bright_mode else 1.0) if on and not child.get_meta("faulted", false) else 0.0
		elif child is Gate:
			child.set_powered(on)
		elif child is InteractiveDoor:
			child.powered = on
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		we.environment.ambient_light_energy = (0.95 if debug_bright_mode else 0.12) if on else 0.025
		we.environment.ambient_light_color = Color(0.4, 0.44, 0.5) if on else Color(0.08, 0.08, 0.1)
	# Backlit adverts and vending machines lose power; exit signs stay on backup.
	for material in [mat_panel_a, mat_panel_b, mat_vending_glow, mat_light_fixture, mat_sign_amber]:
		material.emission_enabled = on


func _breaker_prompt() -> String:
	var manager := get_node("/root/GameManager")
	if manager.state in [manager.NightState.SHIFT_OVER, manager.NightState.DEAD]: return "Shift over"
	if manager.powered: return "Station power on"
	return "[Hold E] Repair the electrical fault" if manager.needs_power_repair() else "[Hold E] Switch on station lights"


func _use_breaker() -> void:
	var manager := get_node("/root/GameManager")
	if manager.powered or manager.state in [manager.NightState.SHIFT_OVER, manager.NightState.DEAD]: return
	if manager.needs_power_repair():
		get_node("StationJobs").wire_panel.open_panel()
	elif Coop.active:
		Coop.request_action("power_on")
	else:
		manager.turn_on_power()


# ─── 7. PROPS & ARCHITECTURAL HELPERS ────────────────────────────────────────
func box(n: String, size: Vector3, pos: Vector3, mat: Material = null) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = n

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	if mat:
		mi.material_override = mat
	sb.add_child(mi)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)

	sb.position = pos
	add_child(sb)
	return sb


func invisible_wall(n: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	## Collision only, no mesh.
	var sb := StaticBody3D.new()
	sb.name = n
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	add_child(sb)
	return sb


func _door_sign(n: String, text: String, pos: Vector3, yaw_deg: float, width: float) -> void:
	## Small glowing plate + label above a door. yaw_deg 0 faces +Z, 90 faces +X.
	var plate := box(n + "_Plate", Vector3(width, 0.3, 0.04), Vector3.ZERO, mat_exit_sign if text == "LOUNGE" else mat_sign_amber)
	plate.position = pos
	plate.rotation_degrees.y = yaw_deg
	var lbl := Label3D.new()
	lbl.name = n + "_Label"
	lbl.text = text
	lbl.font_size = 40
	lbl.pixel_size = 0.0035
	lbl.modulate = Color(1.0, 0.95, 0.85)
	lbl.outline_size = 0
	lbl.position = pos + Vector3(0.0, 0.0, 0.03).rotated(Vector3.UP, deg_to_rad(yaw_deg))
	lbl.rotation_degrees.y = yaw_deg
	add_child(lbl)


func _build_smoking_room() -> void:
	## Dressing for the west gallery room (X: -20…-16, Z: -20…0): benches along
	## the back wall, standing ashtrays, a ceiling vent and a warm glow.
	for bz in [-5.5, -9.5, -13.5]:
		box("SR_Bench_Seat_" + str(bz), Vector3(0.6, 0.08, 2.2), Vector3(-19.35, FLOOR_Y + 0.45, bz), mat_wood)
		box("SR_Bench_Back_" + str(bz), Vector3(0.06, 0.42, 2.2), Vector3(-19.62, FLOOR_Y + 0.72, bz), mat_wood)
		for lz in [-0.85, 0.85]:
			box("SR_Bench_Leg_" + str(bz) + "_" + str(lz), Vector3(0.5, 0.44, 0.08), Vector3(-19.35, FLOOR_Y + 0.22, bz + lz), mat_metal_dark)
	for az in [-7.5, -11.5, -15.5]:
		box("SR_Ashtray_Pole_" + str(az), Vector3(0.1, 0.95, 0.1), Vector3(-17.4, FLOOR_Y + 0.475, az), mat_metal_dark)
		box("SR_Ashtray_Base_" + str(az), Vector3(0.34, 0.05, 0.34), Vector3(-17.4, FLOOR_Y + 0.025, az), mat_metal_dark)
		box("SR_Ashtray_Top_" + str(az), Vector3(0.32, 0.12, 0.32), Vector3(-17.4, FLOOR_Y + 1.0, az), mat_wall_trim)
		box("SR_Ashtray_Ember_" + str(az), Vector3(0.2, 0.02, 0.2), Vector3(-17.4, FLOOR_Y + 1.07, az), mat_sign_amber)
	for vz in [-4.0, -9.0, -14.0]:
		box("SR_Vent_" + str(vz), Vector3(1.4, 0.05, 0.5), Vector3(-18.0, CEIL_H - 0.03, vz), mat_wall_trim)


func _build_entrance_tunnel() -> void:
	var cy: float = FLOOR_Y - FLOOR_T * 0.5
	var light_mult: float = 2.0 if debug_bright_mode else 1.0

	# ── A. Service gallery behind the hall's glass walls (visual space only) ──
	box("Floor_GalleryW", Vector3(4.0, FLOOR_T, 4.0), Vector3(-18.0, cy, -18.0), mat_floor_main)
	box("Gallery_Ceiling", Vector3(36.0, WALL_T, 4.0), Vector3(-2.0, CEIL_H + WALL_T * 0.5, -18.0), mat_ceiling)
	wall("Gallery_Back_W", Vector3(18.15, WALL_H, WALL_T), Vector3(-10.925, WALL_H * 0.5, -20.0))
	wall("Gallery_Back_E", Vector3(14.15, WALL_H, WALL_T), Vector3(8.925, WALL_H * 0.5, -20.0))
	wall("Gallery_Side_W", Vector3(WALL_T, WALL_H, 20.0), Vector3(-20.0, WALL_H * 0.5, -10.0))
	wall("Gallery_End_W", Vector3(4.0, WALL_H, WALL_T), Vector3(-18.0, WALL_H * 0.5, 0.0))
	wall("Gallery_End_E", Vector3(WALL_T, WALL_H, 4.0), Vector3(16.0, WALL_H * 0.5, -18.0))
	# Backlit advert panels so the gallery reads as lit and lively
	var k: int = 0
	for lx in [-14.5, -11.5, -8.5, -5.5, 5.5, 8.5, 11.5, 14.5]:
		box("Panel_S_" + str(k), Vector3(1.8, 2.0, 0.06), Vector3(lx, FLOOR_Y + 1.5, -19.85), mat_panel_a if k % 2 == 0 else mat_panel_b)
		k += 1
	for lz in [-3.0, -6.0, -9.0, -12.0, -15.0]:
		box("Panel_W_" + str(k), Vector3(0.06, 2.0, 1.8), Vector3(-19.85, FLOOR_Y + 1.5, lz), mat_panel_a if k % 2 == 0 else mat_panel_b)
		k += 1
	for gp in [Vector3(-10.0, 3.0, -18.0), Vector3(10.0, 3.0, -18.0), Vector3(-18.0, 3.0, -8.0)]:
		var gl := OmniLight3D.new()
		gl.name = "GalleryLight_" + str(gp)
		gl.light_energy = 1.2 * light_mult
		gl.omni_range = 12.0
		gl.light_color = Color(1.0, 0.72, 0.42) if gp.x < -15.0 else Color(0.85, 0.92, 1.0)
		gl.position = gp
		add_child(gl)

	# ── B. Tunnel from the entrance doorway, then stairs up to the street ──
	var w_clear: float = 3.2                    # same as the doorway
	var wx: float = w_clear * 0.5 + WALL_T * 0.5
	var tun_w: float = w_clear + WALL_T * 2.0
	# B1: flat section, Z -16 → -22
	for sx in [-1.0, 1.0]:
		wall("Tun_A_Wall_" + ("W" if sx < 0.0 else "E"), Vector3(WALL_T, WALL_H, 6.0), Vector3(sx * wx, WALL_H * 0.5, -19.0))
	box("Tun_A_Floor", Vector3(tun_w, FLOOR_T, 2.0), Vector3(0.0, cy, -21.0), mat_floor_main)
	box("Tun_A_Ceil", Vector3(w_clear, 0.25, 6.0), Vector3(0.0, FLOOR_Y + 3.0 + 0.125, -19.0), mat_ceiling)

	# B2: stairs going UP (toward -Z)
	var n_steps: int = 24
	var rise: float = 0.18
	var run: float = 0.32
	var z0: float = -22.0
	var total_run: float = run * float(n_steps)
	var top_y: float = FLOOR_Y + rise * float(n_steps)
	var z_end: float = z0 - total_run
	var stair_riser := _mat(Color(0.25, 0.28, 0.27), 0.88)
	var stair_nosing := _mat(Color(0.10, 0.13, 0.13), 0.82)
	for i in range(n_steps):
		var top: float = FLOOR_Y + rise * float(i + 1)
		var h: float = top + 0.5
		box("TStair_" + str(i), Vector3(w_clear, h, run), Vector3(0.0, -0.5 + h * 0.5, z0 - run * (float(i) + 0.5)), mat_floor_main)
		var edge_z := z0 - run * float(i)
		_booth_prop("StairRiser_" + str(i), Vector3(w_clear - 0.04, rise - 0.012, 0.008), Vector3(0, top - rise * 0.5, edge_z + 0.005), stair_riser)
		_booth_prop("StairNosing_" + str(i), Vector3(w_clear - 0.04, 0.012, 0.085), Vector3(0, top + 0.006, edge_z - 0.0425), stair_nosing)
		_booth_prop("StairEdge_" + str(i), Vector3(w_clear - 0.08, 0.014, 0.023), Vector3(0, top + 0.008, edge_z - 0.015), mat_tactile)
	var handrail := _mat(Color(0.48, 0.52, 0.50), 0.38, 0.75)
	for side in [-1.0, 1.0]:
		_rail_segment("StairHandrail_" + str(side), Vector3(side * 1.42, FLOOR_Y + 0.95, z0 + 0.25), Vector3(side * 1.42, top_y + 0.95, z_end - 0.25), 0.032, handrail)
		for post in range(5):
			var step_index := post * 6
			var foot := Vector3(side * 1.42, FLOOR_Y + rise * step_index, z0 - run * step_index)
			_rail_segment("StairRailPost_%s_%d" % [side, post], foot, foot + Vector3.UP * 0.95, 0.022, handrail)
	_tactile_warning("StairBottomWarning", Vector3(0, FLOOR_Y, -21.45), Vector2(2.9, 0.6))
	_tactile_warning("StairTopWarning", Vector3(0, top_y, z_end - 0.55), Vector2(2.9, 0.6))

	# Sloped ceiling over the stairs (parallel to the stair nosing line)
	_sloped_ceiling("Tun_Slope_Ceil", w_clear, z0, z_end, FLOOR_Y + 3.0, top_y + 3.0)

	# B3: top landing + closed street shutter
	var landing_len: float = 3.3
	var land_h: float = top_y + 0.5
	box("Tun_Landing", Vector3(w_clear, land_h, landing_len), Vector3(0.0, -0.5 + land_h * 0.5, z_end - landing_len * 0.5), mat_floor_main)
	var tall_h: float = top_y + 3.0 + 0.25 + 0.5
	var tall_cy: float = -0.5 + tall_h * 0.5
	var end_z: float = z_end - landing_len - 0.1
	var side_end: float = end_z + WALL_T * 0.5
	var roof_len: float = z_end - side_end
	box("Tun_Landing_Ceil", Vector3(w_clear, 0.25, roof_len), Vector3(0.0, top_y + 3.0 + 0.125, (z_end + side_end) * 0.5), mat_ceiling)
	var side_len: float = z0 - side_end
	for sx in [-1.0, 1.0]:
		wall("Tun_B_Wall_" + ("W" if sx < 0.0 else "E"), Vector3(WALL_T, tall_h, side_len), Vector3(sx * wx, tall_cy, (z0 + side_end) * 0.5))
	# A real arrival apron outside the stair entrance replaces the closed shutter.
	box("StreetArrivalFloor", Vector3(6, 0.3, 5), Vector3(0, top_y - 0.15, end_z - 2.4), mat_floor_main)
	for side in [-1.0, 1.0]:
		box("StreetParapet_" + str(side), Vector3(0.2, 1.15, 5), Vector3(side * 2.9, top_y + 0.575, end_z - 2.4), mat_wall)
		invisible_wall("StreetSideBoundary_" + str(side), Vector3(0.2, 4, 5), Vector3(side * 2.9, top_y + 2, end_z - 2.4))
	invisible_wall("StreetBoundary", Vector3(6, 4, 0.2), Vector3(0, top_y + 2, end_z - 4.8))
	var sign_lbl := Label3D.new()
	sign_lbl.name = "ShutterSign"
	sign_lbl.text = "STATION 7\nENTRANCE"
	sign_lbl.font_size = 48
	sign_lbl.pixel_size = 0.0045
	sign_lbl.modulate = Color(1.0, 0.9, 0.3)
	sign_lbl.position = Vector3(0.0, top_y + 2.5, end_z + 0.14)
	add_child(sign_lbl)

	# Tunnel lighting
	for lp in [Vector3(0.0, 3.0, -19.5), Vector3(0.0, 4.9, -25.0), Vector3(0.0, 6.9, -30.0), Vector3(0.0, top_y + 2.8, z_end - 1.6)]:
		var tl := OmniLight3D.new()
		tl.name = "TunnelLight_" + str(lp.z)
		tl.light_energy = 1.4 * light_mult
		tl.omni_range = 9.0
		tl.light_color = Color(1.0, 0.95, 0.85)
		tl.position = lp
		add_child(tl)

func _night_number() -> int:
	var manager := get_node_or_null("/root/GameManager")
	return int(manager.night) if manager and not Engine.is_editor_hint() else 1


func _sloped_ceiling(n: String, width: float, z_start: float, z_end: float, y_start: float, y_end: float) -> void:
	# Vertical end faces share the exact planes of the flat ceiling sections.
	# A rotated oversized box cannot form these flush joints.
	var half: float = width * 0.5
	var points := PackedVector3Array([
		Vector3(-half, y_start, z_start), Vector3(half, y_start, z_start),
		Vector3(half, y_end, z_end), Vector3(-half, y_end, z_end),
		Vector3(-half, y_start + 0.25, z_start), Vector3(half, y_start + 0.25, z_start),
		Vector3(half, y_end + 0.25, z_end), Vector3(-half, y_end + 0.25, z_end),
	])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for quad in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [3, 7, 6, 2], [0, 4, 7, 3], [1, 2, 6, 5]]:
		var normal: Vector3 = (points[quad[1]] - points[quad[0]]).cross(points[quad[2]] - points[quad[0]]).normalized()
		# Godot treats clockwise triangle winding as the front face.
		for index in [0, 2, 1, 0, 3, 2]:
			surface.set_normal(normal)
			surface.add_vertex(points[quad[index]])
	var body := StaticBody3D.new()
	body.name = n
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = mat_ceiling
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func wall(n: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := box(n, size, pos, mat_wall)
	_wall_bodies.append(body)
	return body


func pillar(n: String, pos: Vector3, height: float = CEIL_H - FLOOR_Y) -> void:
	# Slender structural column, with low trim instead of oversized pedestal blocks.
	# Small overlaps seat the base in the floor and the cap in the ceiling.
	box(n + "_Shaft", Vector3(0.55, height + 0.02, 0.55), pos + Vector3(0.0, height * 0.5, 0.0), mat_wall)
	box(n + "_Base", Vector3(0.68, 0.12, 0.68), pos + Vector3(0.0, 0.04, 0.0), mat_wall_trim)
	box(n + "_Cap", Vector3(0.68, 0.12, 0.68), pos + Vector3(0.0, height - 0.04, 0.0), mat_wall_trim)


func _bench_pair(n: String, pos: Vector3) -> void:
	bench(n + "_South", pos + Vector3(0, 0, -0.42), 180.0)
	bench(n + "_North", pos + Vector3(0, 0, 0.42), 0.0)


func bench(n: String, pos: Vector3, yaw: float = 0.0) -> void:
	# One transform keeps original woodwork, collision and seat anchors aligned.
	var assembly := Node3D.new()
	assembly.name = n
	assembly.position = pos
	assembly.rotation_degrees.y = yaw
	add_child(assembly)
	# Wooden seat
	var seat_body := box(n + "_Seat", Vector3(2.5, 0.10, 0.72), Vector3(0.0, 0.51, 0.0), mat_wood)
	seat_body.reparent(assembly, false)
	# Wooden backrest
	var back := box(n + "_Back", Vector3(2.5, 0.64, 0.08), Vector3(0.0, 0.86, -0.32), mat_wood)
	back.reparent(assembly, false)
	# Metal legs (2 pairs)
	for lx in [-0.95, 0.95]:
		var leg := box(n + "_Leg_" + str(lx), Vector3(0.10, 0.46, 0.6), Vector3(lx, 0.23, 0.0), mat_metal_dark)
		leg.reparent(assembly, false)
	# Three seating anchors for future passenger positioning / sitting animations.
	for i in range(3):
		var seat := Marker3D.new()
		seat.name = n + "_PassengerSeat_" + str(i)
		seat.position = Vector3((i - 1) * 0.75, 0.56, 0.0)
		seat.add_to_group("passenger_seats")
		assembly.add_child(seat)


func _build_chair(n: String, pos: Vector3) -> void:
	# Chair seat
	box(n + "_Seat", Vector3(0.58, 0.10, 0.58), pos + Vector3(0.0, 0.51, 0.0), mat_metal_dark)
	# Chair backrest
	box(n + "_Back", Vector3(0.58, 0.64, 0.08), pos + Vector3(0.0, 0.86, -0.25), mat_metal_dark)
	# Chair central support leg
	box(n + "_Leg", Vector3(0.10, 0.46, 0.10), pos + Vector3(0.0, 0.23, 0.0), mat_metal_dark)


func _build_chair_east(n: String, pos: Vector3) -> void:
	## Office chair facing +X (toward the ticket window).
	box(n + "_Seat", Vector3(0.58, 0.10, 0.58), pos + Vector3(0.0, 0.51, 0.0), mat_metal_dark)
	box(n + "_Back", Vector3(0.08, 0.64, 0.58), pos + Vector3(-0.25, 0.86, 0.0), mat_metal_dark)
	box(n + "_Leg", Vector3(0.10, 0.46, 0.10), pos + Vector3(0.0, 0.23, 0.0), mat_metal_dark)


func _build_booth_interior() -> void:
	var paper := _mat(Color(0.95, 0.92, 0.81), 0.9)
	var sage := _mat(Color(0.42, 0.55, 0.49), 0.65)
	var blue := _mat(Color(0.22, 0.35, 0.43), 0.7)
	var red := _mat(Color(0.65, 0.22, 0.16), 0.6)
	var cork := _mat(Color(0.49, 0.33, 0.19), 0.95)
	# Full-size furniture has collision; tabletop details are visual meshes only.
	box("TB_Locker", Vector3(0.8, 1.9, 1.25), Vector3(-15.35, FLOOR_Y + 0.95, 2.25), sage)
	for z in [1.95, 2.55]:
		_booth_prop("TB_LockerSeam_" + str(z), Vector3(0.014, 1.7, 0.018), Vector3(-14.94, FLOOR_Y + 1.0, z + 0.27), mat_metal_dark)
		_booth_prop("TB_LockerHandle_" + str(z), Vector3(0.05, 0.16, 0.025), Vector3(-14.91, FLOOR_Y + 1.03, z + 0.17), mat_metal_dark)
		for y in [1.45, 1.51, 1.57]:
			_booth_prop("TB_LockerVent_%s_%s" % [z, y], Vector3(0.018, 0.018, 0.36), Vector3(-14.94, FLOOR_Y + y, z), mat_metal_dark)
	# Open shelves against the back wall, stocked with archive boxes and binders.
	for z in [3.6, 5.0]:
		box("TB_ShelfUpright_" + str(z), Vector3(0.7, 1.85, 0.05), Vector3(-15.4, FLOOR_Y + 0.925, z), mat_wall_trim)
	for level in range(3):
		var y: float = FLOOR_Y + 0.25 + level * 0.6
		# Shelves fit BETWEEN the end panels, with a small front recess. The old
		# full-width boards shared end faces with the panels and visibly flickered.
		box("TB_Shelf_" + str(level), Vector3(0.68, 0.05, 1.35), Vector3(-15.4, y, 4.3), mat_wood)
		for j in range(3):
			var z: float = 3.85 + j * 0.42
			_booth_prop("TB_ArchiveBox_%d_%d" % [level, j], Vector3(0.55, 0.32, 0.35), Vector3(-15.36, y + 0.185, z), paper if j != 1 else blue)
			_booth_prop("TB_ArchiveLabel_%d_%d" % [level, j], Vector3(0.012, 0.09, 0.2), Vector3(-15.075, y + 0.18, z), paper)
	box("TB_BackWorkbench", Vector3(3.8, 0.85, 0.75), Vector3(-12.9, FLOOR_Y + 0.425, 6.35), mat_wall_trim)
	_booth_prop("TB_Worktop", Vector3(3.88, 0.06, 0.8), Vector3(-12.9, FLOOR_Y + 0.88, 6.35), mat_wood)
	# Files, logbook and a small staff radio on the rear worktop.
	for j in range(6):
		_booth_prop("TB_Binder_" + str(j), Vector3(0.1, 0.35, 0.27), Vector3(-14.25 + j * 0.14, FLOOR_Y + 1.085, 6.4), blue if j % 2 == 0 else sage)
	_booth_prop("TB_Logbook", Vector3(0.5, 0.045, 0.34), Vector3(-12.55, FLOOR_Y + 0.935, 6.25), blue)
	_booth_prop("TB_LogbookPages", Vector3(0.46, 0.008, 0.3), Vector3(-12.55, FLOOR_Y + 0.961, 6.25), paper)
	if not Engine.is_editor_hint():
		var logbook := invisible_wall("TB_LogbookInteraction", Vector3(0.54, 0.07, 0.38), Vector3(-12.55, FLOOR_Y + 0.955, 6.25))
		InteractionComponent.attach(logbook, _sign_shift_logbook, _logbook_prompt)
	_booth_prop("TB_Radio", Vector3(0.42, 0.24, 0.18), Vector3(-11.55, FLOOR_Y + 1.03, 6.4), mat_metal_dark)
	for j in range(5):
		_booth_prop("TB_RadioGrille_" + str(j), Vector3(0.19, 0.012, 0.008), Vector3(-11.62, FLOOR_Y + 0.97 + j * 0.032, 6.305), sage)
	box("TB_FilingCabinet", Vector3(0.85, 1.25, 0.75), Vector3(-9.6, FLOOR_Y + 0.625, 6.35), sage)
	for row in range(4):
		var y: float = FLOOR_Y + 0.18 + row * 0.3
		_booth_prop("TB_Drawer_" + str(row), Vector3(0.77, 0.27, 0.025), Vector3(-9.6, y, 5.96), mat_wall_trim)
		_booth_prop("TB_DrawerPull_" + str(row), Vector3(0.24, 0.025, 0.04), Vector3(-9.6, y + 0.03, 5.93), mat_metal_dark)
	# Ticket printer, receipt, phone and rubber stamp beside the service position.
	_booth_prop("TB_TicketPrinter", Vector3(0.46, 0.27, 0.45), Vector3(-7.65, FLOOR_Y + 1.005, 2.1), sage)
	_booth_prop("TB_PrinterSlot", Vector3(0.016, 0.035, 0.3), Vector3(-7.89, FLOOR_Y + 1.03, 2.1), mat_metal_dark)
	_booth_prop("TB_PrintedTicket", Vector3(0.2, 0.008, 0.18), Vector3(-7.97, FLOOR_Y + 0.94, 2.1), paper)
	_booth_prop("TB_PhoneBase", Vector3(0.32, 0.07, 0.24), Vector3(-7.65, FLOOR_Y + 0.895, 3.0), mat_metal_dark)
	_booth_prop("TB_PhoneHandset", Vector3(0.36, 0.06, 0.085), Vector3(-7.65, FLOOR_Y + 0.96, 3.0), blue)
	_booth_prop("TB_StampPad", Vector3(0.18, 0.025, 0.25), Vector3(-7.78, FLOOR_Y + 0.877, 3.36), red)
	_booth_prop("TB_StampBase", Vector3(0.1, 0.025, 0.15), Vector3(-7.73, FLOOR_Y + 0.9, 3.36), mat_metal_dark)
	_booth_prop("TB_StampHandle", Vector3(0.06, 0.1, 0.06), Vector3(-7.73, FLOOR_Y + 0.962, 3.36), mat_wood)
	for j in range(4):
		_booth_prop("TB_TicketStack_" + str(j), Vector3(0.25, 0.008, 0.15), Vector3(-7.62, FLOOR_Y + 0.87 + j * 0.009, 4.72), paper)
	# Mug, coaster and a waste bin add everyday clutter without blocking the slot.
	_booth_prop("TB_Coaster", Vector3(0.2, 0.012, 0.2), Vector3(-7.7, FLOOR_Y + 0.862, 5.95), cork)
	var mug := MeshInstance3D.new()
	mug.name = "TB_Mug"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.065
	cylinder.bottom_radius = 0.06
	cylinder.height = 0.13
	mug.mesh = cylinder
	mug.material_override = paper
	mug.position = Vector3(-7.7, FLOOR_Y + 0.935, 5.95)
	add_child(mug)
	_booth_prop("TB_MugHandle", Vector3(0.055, 0.075, 0.025), Vector3(-7.615, FLOOR_Y + 0.94, 5.95), paper)
	box("TB_WasteBin", Vector3(0.36, 0.46, 0.36), Vector3(-8.55, FLOOR_Y + 0.23, 6.25), mat_metal_dark)
	# Noticeboard on the south wall beside the lockers, clear of the shelves.
	_booth_prop("TB_NoticeFrame", Vector3(2.8, 1.45, 0.065), Vector3(-13.2, FLOOR_Y + 1.72, 1.18), mat_wood)
	_booth_prop("TB_NoticeCork", Vector3(2.66, 1.31, 0.018), Vector3(-13.2, FLOOR_Y + 1.72, 1.225), cork)
	_refresh_noticeboard_notes()
	_build_booth_clock(paper)
	_booth_label("TB_WorkbenchSign", "STATION 7 / STAFF ONLY", Vector3(-12.9, FLOOR_Y + 1.6, 6.84), 180.0)


func _on_platform_entered(body: Node3D) -> void:
	if (body.is_in_group("player") or body.is_in_group("crew")) and not Coop.is_client():
		get_node("/root/GameManager").inspect_platform()


func _sign_shift_logbook() -> void:
	get_node("/root/GameManager").sign_in()


func _logbook_prompt() -> String:
	var manager := get_node("/root/GameManager")
	if manager.signed_in: return "All staff signed — station open"
	if not manager.powered: return "Switch on the station lights before signing in"
	var progress := "%d/%d staff signed" % [manager.staff_sign_in_count(), manager.required_staff().size()]
	return "You have signed — waiting for the crew (" + progress + ")" if manager.local_staff_signed() else "[E] Sign the logbook (" + progress + ")"


func _refresh_noticeboard_notes() -> void:
	for resource in _observed_notes:
		if resource.changed.is_connected(_refresh_noticeboard_notes):
			resource.changed.disconnect(_refresh_noticeboard_notes)
	_observed_notes.clear()
	for child in get_children():
		if str(child.name).begins_with("TB_NoticePaper_") or str(child.name).begins_with("TB_NoticeText_") or str(child.name).begins_with("TB_NoticeTape_"):
			remove_child(child)
			child.queue_free()
	var count: int = noticeboard_notes.size()
	if count == 0:
		return
	var columns: int = mini(4, count)
	var rows: int = ceili(float(count) / columns)
	var cell_w: float = 2.6 / columns
	var cell_h: float = 1.25 / rows
	var note_w: float = minf(0.55, cell_w - 0.1)
	var note_h: float = minf(0.5, cell_h - 0.1)
	for j in range(count):
		var note: NoticeNote = noticeboard_notes[j]
		if note == null:
			continue
		if note not in _observed_notes:
			note.changed.connect(_refresh_noticeboard_notes)
			_observed_notes.append(note)
		var x: float = -13.2 + (j % columns - (columns - 1) * 0.5) * cell_w
		var y: float = FLOOR_Y + 1.72 + ((rows - 1) * 0.5 - floorf(float(j) / columns)) * cell_h
		var material := _mat(note.paper_color, 0.9)
		_booth_prop("TB_NoticePaper_" + str(j), Vector3(note_w, note_h, 0.006), Vector3(x, y, 1.24), material)
		var adhesive := _mat(note.paper_color.darkened(0.08), 0.85)
		_booth_prop("TB_NoticeTape_" + str(j), Vector3(note_w - 0.025, minf(0.055, note_h * 0.15), 0.002), Vector3(x, y + note_h * 0.5 - 0.035, 1.244), adhesive)
		var label := _booth_label("TB_NoticeText_" + str(j), note.text, Vector3(x, y - 0.01, 1.251), 0.0)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.width = (note_w - 0.06) / label.pixel_size
		_fit_notice_label(label, note_w - 0.06, note_h - 0.09)


func _fit_notice_label(label: Label3D, width: float, height: float) -> void:
	# Measure actual shaped text, including user-added line breaks and wrapping.
	for i in range(20):
		await get_tree().process_frame
		if not is_instance_valid(label):
			return
		var bounds: AABB = label.get_aabb()
		if bounds.size.x <= width + 0.001 and bounds.size.y <= height + 0.001:
			return
		if label.font_size <= 6:
			return
		label.font_size -= 1


func _booth_prop(n: String, size: Vector3, pos: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var prop := MeshInstance3D.new()
	prop.name = n
	var mesh := BoxMesh.new()
	mesh.size = size
	prop.mesh = mesh
	prop.material_override = material
	prop.position = pos
	add_child(prop)
	return prop


func _booth_label(n: String, text: String, pos: Vector3, yaw: float) -> Label3D:
	var label := Label3D.new()
	label.name = n
	label.text = text
	label.font_size = 24
	label.pixel_size = 0.0014
	label.modulate = Color(0.08, 0.12, 0.11)
	label.outline_size = 0
	label.shaded = true
	label.position = pos
	label.rotation_degrees.y = yaw
	add_child(label)
	return label


func _build_booth_clock(face_material: StandardMaterial3D) -> void:
	var center := Vector3(-11.2, FLOOR_Y + 2.5, 6.82)
	_booth_prop("TB_ClockFrame", Vector3(0.57, 0.57, 0.055), center, mat_metal_dark)
	_booth_prop("TB_ClockFace", Vector3(0.51, 0.51, 0.012), center + Vector3(0, 0, -0.034), face_material)
	for i in range(12):
		var angle: float = TAU * i / 12.0
		var tick := _booth_prop("TB_ClockTick_" + str(i), Vector3(0.016, 0.04, 0.008), center + Vector3(-sin(angle) * 0.216, cos(angle) * 0.216, -0.045), mat_metal_dark)
		tick.rotation.z = angle
	for hand_name in ["Hour", "Minute"]:
		var pivot := Node3D.new()
		pivot.name = "TB_Clock" + hand_name
		pivot.position = center + Vector3(0, 0, -0.055)
		var length: float = 0.13 if hand_name == "Hour" else 0.19
		var hand := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.018, length, 0.008)
		hand.mesh = mesh
		hand.material_override = mat_metal_dark
		hand.position.y = length * 0.5
		pivot.add_child(hand)
		add_child(pivot)
	# Editor preview; the runtime clock is driven by GameManager.
	get_node("TB_ClockHour").rotation.z = TAU * 130.0 / 720.0
	get_node("TB_ClockMinute").rotation.z = TAU * 10.0 / 60.0


func _update_booth_clock() -> void:
	var manager := get_node_or_null("/root/GameManager")
	if manager and has_node("TB_ClockMinute"):
		get_node("TB_ClockHour").rotation.z = TAU * fmod(manager.time_minutes, 720.0) / 720.0
		get_node("TB_ClockMinute").rotation.z = TAU * fmod(manager.time_minutes, 60.0) / 60.0


func _build_ticket_window() -> void:
	# Thick transparent boxes draw multiple faces on top of one another, making
	# seams and bright specular streaks. Use a single flat mesh for the whole
	# window instead; its three rectangles meet edge-to-edge around the slot.
	var window_start: float = 1.0 + WALL_T * 0.5
	var window_end: float = 7.0 - WALL_T * 0.5
	var jamb_w: float = 0.06
	var bottom: float = FLOOR_Y + 1.06 # Meets the counter's top face exactly.
	var window_top: float = FLOOR_Y + 2.55
	invisible_wall("TB_Front_Glass_A", Vector3(0.05, window_top - bottom, 3.6 - window_start), Vector3(-7.0, (window_top + bottom) * 0.5, (window_start + 3.6) * 0.5))
	invisible_wall("TB_Front_Glass_B", Vector3(0.05, window_top - bottom, window_end - 4.4), Vector3(-7.0, (window_top + bottom) * 0.5, (4.4 + window_end) * 0.5))
	invisible_wall("TB_Front_Glass_Top", Vector3(0.05, 1.05, 0.8), Vector3(-7.0, FLOOR_Y + 2.025, 4.0))
	var clear := StandardMaterial3D.new()
	clear.albedo_color = Color(0.97, 0.99, 1.0, 0.045)
	clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clear.cull_mode = BaseMaterial3D.CULL_DISABLED
	clear.metallic = 0.0
	clear.metallic_specular = 0.0
	clear.roughness = 1.0
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect in [
		[window_start + jamb_w, 3.6, bottom + 0.04, window_top - 0.04],
		[4.4, window_end - jamb_w, bottom + 0.04, window_top - 0.04],
		[3.6, 4.4, FLOOR_Y + 1.54, window_top - 0.04],
	]:
		var corners := [Vector3(-7.0, rect[2], rect[0]), Vector3(-7.0, rect[3], rect[0]), Vector3(-7.0, rect[3], rect[1]), Vector3(-7.0, rect[2], rect[1])]
		for i in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(Vector3.RIGHT)
			surface.add_vertex(corners[i])
	var glass := MeshInstance3D.new()
	glass.name = "TB_ClearWindow"
	glass.mesh = surface.commit()
	glass.material_override = clear
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)
	# Perimeter channels protect the window without putting mullions across the view.
	for z in [window_start + jamb_w * 0.5, window_end - jamb_w * 0.5]:
		box("TB_WindowJamb_" + str(z), Vector3(FRAME_DEPTH, window_top - bottom, jamb_w), Vector3(-7.0, (window_top + bottom) * 0.5, z), mat_wall_trim)
	for y in [bottom + 0.02, window_top - 0.02]:
		box("TB_WindowRail_" + str(y), Vector3(FRAME_DEPTH, 0.04, window_end - window_start - 2.0 * jamb_w), Vector3(-7.0, y, 4.0), mat_wall_trim)
	# Protect the cut-out edges too, keeping the document slot itself open.
	box("TB_SlotHeader", Vector3(0.1, 0.04, 0.84), Vector3(-7.0, FLOOR_Y + 1.52, 4.0), mat_wall_trim)
	for z in [3.58, 4.42]:
		box("TB_SlotJamb_" + str(z), Vector3(0.1, 0.43, 0.04), Vector3(-7.0, FLOOR_Y + 1.285, z), mat_wall_trim)


func _build_document_tray(n: String, pos: Vector3) -> void:
	## Shallow open-ended tray that straddles the window slot: the passenger puts
	## passport + ID card in from the east, the clerk takes them from the west.
	## pos = centre of the tray floor on the counter top.
	var tray := box(n, Vector3(0.5, 0.03, 0.6), pos, mat_metal_dark)
	tray.add_to_group("document_tray")
	for sz in [-0.285, 0.285]:
		box(n + "_Rim_" + str(sz), Vector3(0.5, 0.06, 0.03), pos + Vector3(0.0, 0.03, sz), mat_metal_dark)
	# Small status light on the clerk side
	box(n + "_Light", Vector3(0.04, 0.03, 0.04), pos + Vector3(-0.2, 0.03, 0.0), mat_status_light)


func turnstile(n: String, pos: Vector3, decorative_scanner: bool = true) -> void:
	## One gate pedestal, long axis along Z (the walking direction). pos is its
	## centre on the floor. The working scanner, flap and lights belong to the
	## Gate lane node (gate.gd) between two pedestals.
	box(n + "_Housing", Vector3(0.3, 1.25, 1.4), pos + Vector3(0.0, 0.625, 0.0), mat_metal_dark)
	if decorative_scanner:
		box(n + "_Scanner", Vector3(0.24, 0.04, 0.25), pos + Vector3(0.0, 1.27, -0.45), mat_gate)


func vending_machine(n: String, pos: Vector3, facing: float, blue: bool) -> void:
	## pos = centre on the floor. facing = +1 (front toward +Z) or -1 (toward -Z).
	var body_mat: StandardMaterial3D = mat_vending_blue if blue else mat_vending_red
	box(n + "_Body", Vector3(1.0, 1.9, 0.8), pos + Vector3(0.0, 0.95, 0.0), body_mat)
	# Lit product window
	box(n + "_Window", Vector3(0.72, 1.15, 0.04), pos + Vector3(-0.06, 1.2, facing * 0.41), mat_vending_glow)
	# Selection keypad column
	box(n + "_Keypad", Vector3(0.14, 0.5, 0.04), pos + Vector3(0.36, 1.35, facing * 0.41), mat_metal_dark)
	# Pickup slot
	box(n + "_Slot", Vector3(0.6, 0.22, 0.04), pos + Vector3(-0.06, 0.32, facing * 0.41), mat_metal_dark)
	# Top glow strip
	box(n + "_Glow", Vector3(0.9, 0.08, 0.04), pos + Vector3(0.0, 1.82, facing * 0.41), mat_vending_glow)
	var l := OmniLight3D.new()
	l.name = n + "_Light"
	l.light_color = Color(0.7, 0.85, 1.0) if blue else Color(1.0, 0.8, 0.7)
	l.light_energy = 0.6
	l.omni_range = 3.5
	l.position = pos + Vector3(0.0, 1.3, facing * 0.9)
	add_child(l)


func glass_pane(n: String, size: Vector3, pos: Vector3) -> StaticBody3D:
	var sb := box(n, size, pos, mat_glass)
	(sb.get_child(0) as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sb


func glass_wall(n: String, length: float, center: Vector3, along_x: bool, pane_w: float = 2.4) -> void:
	## A wall with a band of clear glass between a solid lower panel and a
	## header, split into panes by slim trim mullions. `center` uses X/Z only.
	var sill: float = FLOOR_Y + 0.9
	var top: float = FLOOR_Y + 2.7
	var low_h: float = sill
	var up_h: float = WALL_H - top
	var gl_h: float = top - sill
	var pier_w: float = 0.22
	var clear_length: float = length - 2.0 * pier_w
	var rail_h: float = 0.07
	# All horizontal pieces terminate at the INNER faces of the end posts.
	# No coplanar end faces or rails run through the solid posts.
	var low_size := Vector3(clear_length, low_h, WALL_T) if along_x else Vector3(WALL_T, low_h, clear_length)
	var up_size := Vector3(clear_length, up_h, WALL_T) if along_x else Vector3(WALL_T, up_h, clear_length)
	var gl_size := Vector3(clear_length, gl_h - 2.0 * rail_h, 0.06) if along_x else Vector3(0.06, gl_h - 2.0 * rail_h, clear_length)
	wall(n + "_Low", low_size, Vector3(center.x, low_h * 0.5, center.z))
	wall(n + "_Up", up_size, Vector3(center.x, top + up_h * 0.5, center.z))
	glass_pane(n + "_Glass", gl_size, Vector3(center.x, sill + gl_h * 0.5, center.z))
	# Full-height wall piers close BOTH exposed ends, including barrier ends
	# beside gates and window corners. They stay inside this wall's footprint.
	for side in [-1.0, 1.0]:
		var off: float = side * (length * 0.5 - pier_w * 0.5)
		var psize := Vector3(pier_w, WALL_H, WALL_T) if along_x else Vector3(WALL_T, WALL_H, pier_w)
		var ppos := Vector3(center.x + off, WALL_H * 0.5, center.z) if along_x else Vector3(center.x, WALL_H * 0.5, center.z + off)
		wall(n + ("_EndL" if side < 0.0 else "_EndR"), psize, ppos)
	# Continuous sill/head channels cover the horizontal glass edges.
	for y in [sill + rail_h * 0.5, top - rail_h * 0.5]:
		var rail_size := Vector3(clear_length, rail_h, FRAME_DEPTH) if along_x else Vector3(FRAME_DEPTH, rail_h, clear_length)
		box(n + "_FrameRail_" + str(y), rail_size, Vector3(center.x, y, center.z), mat_wall_trim)
	var count: int = maxi(1, int(round(clear_length / pane_w)))
	for i in range(1, count):
		var off: float = -clear_length * 0.5 + clear_length * float(i) / float(count)
		var msize := Vector3(0.12, gl_h - 2.0 * rail_h, FRAME_DEPTH) if along_x else Vector3(FRAME_DEPTH, gl_h - 2.0 * rail_h, 0.12)
		var mpos := Vector3(center.x + off, sill + gl_h * 0.5, center.z) if along_x else Vector3(center.x, sill + gl_h * 0.5, center.z + off)
		box(n + "_Mull_" + str(i), msize, mpos, mat_wall_trim)


func _build_corner_returns() -> void:
	# One shared wall-thickness block at each junction. Adjoining wall volumes
	# are cut back first, so the joint is flush instead of a sleeve over a wall.
	var corners := [
		["HallSW", Vector3(-16, 0, -16)],
		["HallSE", Vector3(16, 0, -16)],
		["HallWestJoin", Vector3(-16, 0, 0)],
		["BarrierWestJoin", Vector3(-16, 0, 10)],
		["BoothNorthWest", Vector3(-16, 0, 7)],
		["BoothSouthWest", Vector3(-16, 0, 1)],
		["BoothWindowNorth", Vector3(-7, 0, 7)],
		["BoothWindowSouth", Vector3(-7, 0, 1)],
		["GallerySW", Vector3(-20, 0, -20)],
		["GalleryNW", Vector3(-20, 0, 0)],
		["GallerySE", Vector3(16, 0, -20)],
		["RoomsSW", Vector3(16, 0, -10)],
		["RoomsSE", Vector3(25, 0, -10)],
		["BathroomSE", Vector3(41, 0, -15)],
		["BathroomNE", Vector3(41, 0, 5)],
		["BathroomMidW", Vector3(16, 0, -5)],
		["BathroomReturnSW", Vector3(26, 0, -15)],
		["BathroomReturnS", Vector3(26, 0, -10)],
		["BathroomReturnN", Vector3(26, 0, 0)],
		["BathroomReturnNW", Vector3(26, 0, 5)],
		["BathroomMidE", Vector3(41, 0, -5)],
		["RoomsDividerW0", Vector3(16, 0, 0)],
		["RoomsDividerE0", Vector3(25, 0, 0)],
		["RoomsDividerW5", Vector3(16, 0, 5)],
		["RoomsDividerE5", Vector3(25, 0, 5)],
		["RoomsNW", Vector3(16, 0, 10)],
		["RoomsNE", Vector3(25, 0, 10)],
		["PlatformSW", Vector3(-26, 0, 10)],
		["PlatformSE", Vector3(26, 0, 10)],
		["EntranceW", Vector3(-1.725, 0, -16)],
		["EntranceE", Vector3(1.725, 0, -16)],
	]
	var cuts: Array[AABB] = []
	corners.append(["StorageSE", Vector3(25, 0, -16)])
	for corner in corners:
		cuts.append(AABB(corner[1] + Vector3(-WALL_T * 0.5, 0, -WALL_T * 0.5), Vector3(WALL_T, WALL_H, WALL_T)))
	for body in _wall_bodies:
		var original_mesh := body.get_child(0) as MeshInstance3D
		var original: AABB = body.transform * original_mesh.get_aabb()
		var pieces: Array[AABB] = [original]
		for cut in cuts:
			var next: Array[AABB] = []
			for piece in pieces:
				next.append_array(_subtract_wall_box(piece, cut))
			pieces = next
		if pieces.size() == 1 and pieces[0] == original:
			continue
		for child in body.get_children():
			body.remove_child(child)
			child.queue_free()
		for i in range(pieces.size()):
			var piece: AABB = pieces[i]
			var mesh := MeshInstance3D.new()
			mesh.name = "WallMesh_" + str(i)
			var box_mesh := BoxMesh.new()
			box_mesh.size = piece.size
			mesh.mesh = box_mesh
			mesh.material_override = mat_wall
			mesh.position = piece.position + piece.size * 0.5 - body.position
			body.add_child(mesh)
			var collision := CollisionShape3D.new()
			collision.name = "WallCollision_" + str(i)
			var shape := BoxShape3D.new()
			shape.size = piece.size
			collision.shape = shape
			collision.position = mesh.position
			body.add_child(collision)
	for corner in corners:
		if str(corner[0]).begins_with("Rooms") or str(corner[0]).begins_with("Bathroom") or corner[0] == "StorageSE":
			continue # Already authored in the room scenes.
		wall("CornerReturn_" + corner[0], Vector3(WALL_T, WALL_H, WALL_T), corner[1] + Vector3(0, WALL_H * 0.5, 0))


func _subtract_wall_box(source: AABB, cut: AABB) -> Array[AABB]:
	var overlap := source.intersection(cut)
	if overlap.size.x < 0.0001 or overlap.size.y < 0.0001 or overlap.size.z < 0.0001:
		return [source]
	var lo: Vector3 = source.position
	var hi: Vector3 = source.position + source.size
	var a: Vector3 = overlap.position
	var b: Vector3 = overlap.position + overlap.size
	# Non-overlapping slices of the source around the shared junction volume.
	var result: Array[AABB] = []
	for bounds in [
		[lo, Vector3(a.x, hi.y, hi.z)],
		[Vector3(b.x, lo.y, lo.z), hi],
		[Vector3(a.x, lo.y, lo.z), Vector3(b.x, hi.y, a.z)],
		[Vector3(a.x, lo.y, b.z), Vector3(b.x, hi.y, hi.z)],
		[Vector3(a.x, lo.y, a.z), Vector3(b.x, a.y, b.z)],
		[Vector3(a.x, b.y, a.z), Vector3(b.x, hi.y, b.z)],
	]:
		var size: Vector3 = bounds[1] - bounds[0]
		if size.x > 0.0001 and size.y > 0.0001 and size.z > 0.0001:
			result.append(AABB(bounds[0], size))
	return result


func _spawn_test_passengers() -> void:
	# The legacy gate probe is source-only and excluded from release packages.
	# Resolve it lazily so its class is never a production parser dependency.
	if not ResourceLoader.exists("res://scripts/test_passenger.gd"): return
	var helper: Script = load("res://scripts/test_passenger.gd")
	var lanes: Array[Gate] = []
	for c in get_children():
		if c is Gate:
			lanes.append(c)
	if lanes.size() < 3:
		return
	var specs := [
		[lanes[1], Ticket.make("T-1001", "Valid Passenger", "Line 0", true)],
		[lanes[2], Ticket.make("T-1002", "Forged Ticket", "Line 0", false)],
	]
	for sp in specs:
		var g: Gate = sp[0]
		var p = helper.new()
		p.name = "TestPassenger_" + (sp[1] as Ticket).id
		p.gate = g
		p.ticket = sp[1]
		p.platform_target = Vector3(g.position.x, FLOOR_Y + 0.05, 13.0)
		p.position = Vector3(g.position.x, FLOOR_Y + 0.05, 5.5)
		add_child(p)


func door_frame(n: String, pos: Vector3, width: float = 1.2, height: float = 2.4, is_east_facing: bool = false, add_door: bool = false, glass_door: bool = false, steel_door: bool = false, security_door: bool = false) -> void:
	var frame_material: StandardMaterial3D = mat_wall_trim
	if steel_door or security_door:
		frame_material = _mat(Color(0.36, 0.43, 0.41), 0.42, 0.65)
	var trim_t: float = 0.08
	var trim_d: float = WALL_T + 0.04

	if not is_east_facing:
		# Left jamb
		box(n + "_JambL", Vector3(trim_t, height, trim_d), pos + Vector3(-width * 0.5 + trim_t * 0.5, height * 0.5, 0.0), frame_material)
		# Right jamb
		box(n + "_JambR", Vector3(trim_t, height, trim_d), pos + Vector3(width * 0.5 - trim_t * 0.5, height * 0.5, 0.0), frame_material)
		# Top header
		box(n + "_Header", Vector3(width - 2.0 * trim_t, trim_t, trim_d), pos + Vector3(0.0, height - trim_t * 0.5, 0.0), frame_material)

	else:
		# Left jamb (south)
		box(n + "_JambL", Vector3(trim_d, height, trim_t), pos + Vector3(0.0, height * 0.5, -width * 0.5 + trim_t * 0.5), frame_material)
		# Right jamb (north)
		box(n + "_JambR", Vector3(trim_d, height, trim_t), pos + Vector3(0.0, height * 0.5, width * 0.5 - trim_t * 0.5), frame_material)
		# Top header
		box(n + "_Header", Vector3(trim_d, trim_t, width - 2.0 * trim_t), pos + Vector3(0.0, height - trim_t * 0.5, 0.0), frame_material)

	if add_door:
		_add_interactive_door(n, pos, width, height, is_east_facing, glass_door, steel_door, security_door)


func _add_interactive_door(n: String, pos: Vector3, width: float, height: float, east_facing: bool, glass_style: bool, steel_style: bool, security_style: bool) -> void:
	const TRIM := 0.08
	var door := InteractiveDoor.new()
	door.name = n + "_InteractiveDoor"
	door.door_name = n
	door.door_width = width - TRIM * 2.0
	door.door_height = height - TRIM
	door.is_east_facing = east_facing
	door.glass_style = glass_style
	door.steel_style = steel_style
	door.security_style = security_style
	door.locked = false
	var hinge_offset := -width * 0.5 + TRIM
	door.position = pos + (Vector3(0, 0, hinge_offset) if east_facing else Vector3(hinge_offset, 0, 0))
	add_child(door)
