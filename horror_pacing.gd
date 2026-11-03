extends Node3D
## Optional atmosphere, separate from ticket cases and required incident objectives.
## Durable transitions are host-owned; viewer heartbeats never enter checkpoints.
const CAMERA_LAYER := 1 << 17
const CAMERA_FEED := 2
const FIGURE_POINT := Vector3(17, 0.35, 17.2)
const ARCHIVE_TEXT := "DEPARTURE LEDGER / ARCHIVED COPY\n31 OCT / 00:07 — LINE 7 — SEAT 07\nHolder: A. Morrow. Ticket issued; departure never confirmed.\nEvery later service carries the same reservation. No payment. No new ticket.\nMargin, different ink: 'Do not count the seat as a passenger.'\nThe entry predates this crew's first shift. The handwriting does not match the letters."
const EVIDENCE := {
	"camera_report": "CAM 03: An unlisted figure was recorded outside the passenger queue. No current document case is attached to this observation.",
	"camera": "CAM 03: A still figure appeared on the platform feed, outside the document queue. It vanished after the monitor was turned away. This is not evidence against a ticket holder.",
	"departure": "NIGHT 4: After departure, dispatch retained SEAT 07 / RESERVED with no corresponding passenger. The announcement stopped halfway through its chime.",
	"archive": "ARCHIVE: Seat 07 was issued to A. Morrow before this crew arrived. Departure was never confirmed; the reservation has carried forward without another sale.",
}
@export_range(0.0, 1.0) var sighting_chance := 0.35
var rng := RandomNumberGenerator.new()
var sighting := "PENDING"
var opportunity_used := false
var available_left := 0.0
var turn := "WAITING"
var turn_left := 0.0
var _viewers: Dictionary = {}
var _away := 0.0
var _sample := 0.0
var _last_visual_key := ""
var _network_initialized := false
var _station: Node3D
var _meshes: Array[Node] = []
var _figure: Node3D
var _dispatch: Label3D
var _archive: StaticBody3D
var _reader: CanvasLayer
var _last_train_phase := "WAITING"

func _ready() -> void:
	add_to_group("horror_pacing")
	add_to_group("save_participant")
	_station = get_parent()
	rng.randomize()
	_figure = preload("res://passenger_visual.gd").new()
	_figure.name = "UnlistedFigure"
	_figure.profile = {"name":"Unlisted traveller", "skin":Color(0.48,0.45,0.42), "hair":Color(0.12,0.12,0.13), "coat":Color(0.16,0.19,0.20)}
	_figure.position = FIGURE_POINT
	_figure.rotation.y = PI * 0.5
	add_child(_figure)
	_meshes = _figure.find_children("*", "MeshInstance3D", true, false)
	for mesh in _meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var player := get_tree().get_first_node_in_group("player")
	if player and player.camera: player.camera.cull_mask &= ~CAMERA_LAYER
	_dispatch = Label3D.new()
	_dispatch.name = "UnlistedReservation"
	_dispatch.position = Vector3(-9, 1.7, 7.26)
	_dispatch.font = preload("res://ui/fonts/SpecialElite.ttf")
	_dispatch.font_size = 30
	_dispatch.pixel_size = 0.002
	_dispatch.modulate = Color(0.82, 0.77, 0.61)
	_dispatch.outline_size = 0
	add_child(_dispatch)
	_build_archive()
	GameManager.power_changed.connect(func(_powered: bool) -> void: _apply_visuals())
	GameManager.shift_finished.connect(_stop)
	GameManager.player_died.connect(_stop)
	GameManager.night_started.connect(_reset)
	_reset(GameManager.night)

func _build_archive() -> void:
	_reader = preload("res://field_panel.gd").new()
	_reader.name = "DepartureLedgerReader"
	add_child(_reader)
	_archive = StaticBody3D.new()
	_archive.name = "ArchivedDepartureLedger"
	_archive.position = Vector3(24.1, 1.2, 4.1)
	_archive.collision_mask = 0
	add_child(_archive)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.38, 0.08, 0.48)
	shape.shape = box
	_archive.add_child(shape)
	var mesh := MeshInstance3D.new()
	var book := BoxMesh.new()
	book.size = box.size
	mesh.mesh = book
	var cover := StandardMaterial3D.new()
	cover.albedo_color = Color(0.28, 0.23, 0.16)
	cover.roughness = 1
	mesh.material_override = cover
	_archive.add_child(mesh)
	var label := Label3D.new()
	label.text = "OLD DEPARTURES"
	label.font_size = 22
	label.pixel_size = 0.0015
	label.position.y = 0.045
	label.rotation.x = -PI / 2
	label.outline_size = 0
	_archive.add_child(label)
	preload("res://interactable.gd").attach(_archive, read_archive, func() -> String: return "[E] Read old departure ledger")

func _reset(_night: int) -> void:
	sighting = "PENDING"
	opportunity_used = false
	available_left = 0
	turn = "WAITING"
	turn_left = 0
	_viewers.clear()
	_away = 0
	_sample = 0
	_last_train_phase = "WAITING"
	if _reader: _reader.close_panel()
	_apply_visuals()

func _running() -> bool:
	return GameManager.signed_in and GameManager.powered and not GameManager.loading and GameManager.state == GameManager.NightState.WORKING

func _process(delta: float) -> void:
	if Coop.simulation_blocked() or not _running(): return
	_sample += delta
	if _sample >= 0.5:
		_sample = 0
		var monitor: CanvasLayer = _station.get_node("StationServices").cctv
		var watching: bool = monitor.is_open and monitor.selected == CAMERA_FEED and not monitor.feeds.is_empty() and not monitor.feeds[CAMERA_FEED].get("signal_lost", false)
		if watching:
			var camera: Camera3D = monitor.feeds[CAMERA_FEED].camera
			watching = sees_figure(camera)
		if Coop.is_client():
			if sighting in ["AVAILABLE", "SEEN"]: Coop.request_action("pacing_view", watching)
		else: observe(1, watching)
	if Coop.is_client(): return
	advance(delta)

func sees_figure(camera: Camera3D) -> bool:
	var point := FIGURE_POINT + Vector3.UP
	return camera.is_position_in_frustum(point) and _station.get_node("StationServices").cctv._line_clear(camera.global_position, point)

func observe(peer: int, watching: bool) -> void:
	if Coop.is_client() or not _running() or sighting not in ["AVAILABLE", "SEEN"]: return
	if watching:
		_viewers[peer] = Time.get_ticks_msec()
		sighting = "SEEN"
		_away = 0
	else: _viewers.erase(peer)

func try_sighting() -> void:
	if Coop.is_client() or opportunity_used or GameManager.night != 3 or not _running(): return
	opportunity_used = true # A miss stays a miss; no per-frame reroll.
	sighting = "AVAILABLE" if rng.randf() < sighting_chance else "RETIRED"
	available_left = 90
	_apply_visuals()

func advance(delta: float) -> void:
	if Coop.is_client() or not _running() or delta <= 0: return
	var service := _station.get_node("PassengerService")
	var incident := _station.get_node("NightEvents")
	if GameManager.night == 3 and not opportunity_used and service.reviewed >= 5 and (not incident.started or incident.completed): try_sighting()
	if sighting == "AVAILABLE":
		available_left = maxf(0, available_left - delta)
		if available_left == 0: sighting = "RETIRED"
	elif sighting == "SEEN":
		var now := Time.get_ticks_msec()
		for peer in _viewers.keys():
			if now - int(_viewers[peer]) > 2000 or (Coop.active and not Coop.roster.has(peer)): _viewers.erase(peer)
		if _viewers.is_empty():
			_away += delta
			if _away >= 1.5:
				sighting = "RETIRED"
				remember("camera")
		else: _away = 0
	if GameManager.night == 4:
		var train := _station.get_node("TrainService")
		if turn == "WAITING" and _last_train_phase == "DEPARTING" and train.phase == "WAITING": begin_turn()
		_last_train_phase = train.phase
		# Recovery for old checkpoints that predate this component or skip the first train.
		if turn == "WAITING" and GameManager.time_minutes >= 155: begin_turn()
		if turn == "AFTERMATH":
			turn_left = maxf(0, turn_left - delta)
			if turn_left == 0: turn = "COMPLETE"
	_apply_visuals()

func begin_turn() -> void:
	if Coop.is_client() or GameManager.night != 4 or turn != "WAITING" or not _running(): return
	turn = "AFTERMATH"
	turn_left = 20
	remember("departure")
	var pa := get_tree().get_first_node_in_group("station_pa")
	if pa: pa.interrupt_for_unlisted_departure()
	GameManager.notice_posted.emit("DISPATCH: Service departed. Unclaimed reservation: SEAT 07.\nNo matching passenger was checked in.")
	_apply_visuals()

func holds_first_hunt() -> bool:
	return GameManager.night == 4 and turn != "COMPLETE"

func remember(id: String) -> bool:
	if Coop.is_client() or GameManager.loading or GameManager.state in [GameManager.NightState.DEAD, GameManager.NightState.SHIFT_OVER]: return false
	if not EVIDENCE.has(id):
		if not id.begins_with("note/"): return false
		var number := id.trim_prefix("note/")
		if not number.is_valid_int() or int(number) < 0 or int(number) >= 10: return false
	var found: Array = GameManager.campaign.get("mystery", []).duplicate()
	if found.has(id): return false
	found.append(id)
	GameManager.campaign["mystery"] = found
	return true

func read_archive() -> void:
	if GameManager.loading or GameManager.night < 3 or GameManager.state in [GameManager.NightState.DEAD, GameManager.NightState.SHIFT_OVER]: return
	if Coop.active: Coop.request_action("pacing_archive")
	else: remember("archive")
	_reader.clear_body()
	_reader.heading.text = "OLD DEPARTURES / SEAT 07"
	_reader.paragraph(ARCHIVE_TEXT)
	_reader.paragraph("This archived reservation is not a valid current travel document. Use the registry and window camera for today's passengers.")
	_reader.open_panel()

func journal_entries() -> PackedStringArray:
	var lines := PackedStringArray()
	for id in GameManager.campaign.get("mystery", []):
		if EVIDENCE.has(id): lines.append(EVIDENCE[id])
		elif str(id).begins_with("note/"): lines.append("Handwritten note %02d discovered. Its writer is unconfirmed." % (int(str(id).get_slice("/", 1)) + 1))
	return lines

func ending_text(passed: bool) -> String:
	if not passed: return "The reservation remains open. The departure ledger offers no explanation."
	var text := "At dawn, dispatch finally releases SEAT 07. The unclaimed reservation—not another ticketed passenger—had been carried from service to service. This train leaves without it."
	var found: Array = GameManager.campaign.get("mystery", [])
	if found.has("archive"): text += "\nThe old ledger's entry for A. Morrow is marked CLOSED. Nothing records where its holder went."
	if found.has("note/0"): text += "\nYou remember the letter: I SAVED YOU A SEAT. It never said which train."
	text += "\nThe booth prints one more ticket. No passenger name. No destination. Just tomorrow's date, and the number of staff who signed tonight."
	return text

func _apply_visuals() -> void:
	if not is_instance_valid(_figure): return
	var key := "%d/%s/%s/%s/%d" % [GameManager.night, sighting, turn, GameManager.powered, GameManager.state]
	if key == _last_visual_key: return
	_last_visual_key = key
	var camera_only := GameManager.night == 3 and sighting in ["AVAILABLE", "SEEN"]
	var aftermath := GameManager.night == 4 and turn == "AFTERMATH"
	_figure.visible = GameManager.powered and GameManager.state == GameManager.NightState.WORKING and (camera_only or aftermath)
	for mesh in _meshes: mesh.layers = CAMERA_LAYER if camera_only else 1
	_dispatch.visible = GameManager.night >= 4 and turn in ["AFTERMATH", "COMPLETE"]
	_dispatch.text = "SEAT 07 / RESERVED\nNO MATCHING PASSENGER"
	_archive.visible = GameManager.night >= 3
	_archive.collision_layer = 8 if _archive.visible else 0

func save_state() -> Dictionary:
	return {"version":1, "sighting":sighting, "used":opportunity_used, "available":available_left, "turn":turn, "turn_left":turn_left, "train_phase":_last_train_phase, "rng":str(rng.state)}

func load_state(data: Dictionary) -> void:
	if int(data.get("version", 1)) != 1: return
	sighting = str(data.get("sighting", "PENDING"))
	if sighting not in ["PENDING", "AVAILABLE", "SEEN", "RETIRED"]: sighting = "RETIRED"
	opportunity_used = bool(data.get("used", false))
	available_left = _seconds(data.get("available", 0), 90)
	turn = str(data.get("turn", "WAITING"))
	if turn not in ["WAITING", "AFTERMATH", "COMPLETE"]: turn = "COMPLETE"
	turn_left = _seconds(data.get("turn_left", 0), 20)
	_last_train_phase = str(data.get("train_phase", "WAITING"))
	if data.get("rng") is String and str(data.rng).is_valid_int(): rng.state = int(data.rng)
	# Heartbeats are local live observations, never serialized. Do not replay PA on restore.
	_viewers.clear()
	_away = 0
	_apply_visuals()

func _stop() -> void:
	_figure.hide()
	_reader.close_panel()
	_viewers.clear()

func apply_network_state(data: Dictionary) -> void:
	var previous := turn
	var initialized := _network_initialized
	load_state(data)
	_network_initialized = true
	# A first snapshot is a restored world, not permission to replay a scare.
	if initialized and previous == "WAITING" and turn == "AFTERMATH":
		var pa := get_tree().get_first_node_in_group("station_pa")
		if pa: pa.interrupt_for_unlisted_departure()

func report_sighting(feed: int, camera: Camera3D) -> String:
	if Coop.is_client() or not _running() or GameManager.night != 3 or feed != CAMERA_FEED: return ""
	if sighting not in ["AVAILABLE", "SEEN"] or not sees_figure(camera): return ""
	return "UNLISTED FIGURE RECORDED / NO TICKET CASE ATTACHED" if remember("camera_report") else "THIS UNLISTED FIGURE HAS ALREADY BEEN RECORDED"

func _seconds(value: Variant, maximum: float) -> float:
	if not (value is int or value is float) or not is_finite(float(value)): return 0
	return clampf(float(value), 0, maximum)
