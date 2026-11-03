extends Node3D
## Authored incidents are host-owned. Loading/snapshots only restore state, never replay actions.
const TITLES := ["EXIT SEAL", "DEAD LINE", "FALSE LAST CALL", "OVERLOAD", "ROLL CALL", "SPLIT CIRCUIT", "FINAL CLEARANCE"]
const THRESHOLDS := [2, 4, 4, 6, 6, 8, 4]
var started := false
var completed := false
var stage := "WAITING"
var warning_left := 0.0
var target_uid := ""
var checkpoints: Array[String] = []
var _station: Node3D
var _tick := 0.0
var _label: Label3D

func _ready() -> void:
	add_to_group("night_events")
	add_to_group("save_participant")
	_station = get_parent()
	_target("ExitSeal", Vector3(-1.95, 1.45, -15.73), 0, "EXIT SEAL", "exit")
	_target("CameraJunction", Vector3(24.67, 1.3, 4.7), -90, "CAM 04\nLINE RESET", "camera")
	_target("KeepService", Vector3(-9.28, 1.5, 7.28), 0, "KEEP TRAIN\nRUNNING", "keep")
	_target("CancelService", Vector3(-8.72, 1.5, 7.28), 0, "CANCEL\nTRAIN", "cancel")
	_target("RollCall", Vector3(-11.6, 1.38, 6.2), 180, "ROLL CALL", "roster")
	_target("ClearanceBooth", Vector3(-14.1, 1.45, 6.2), 180, "CLEARANCE\nBOOTH", "booth")
	_target("ClearanceSecurity", Vector3(24.67, 1.3, 0.3), -90, "CLEARANCE\nSECURITY", "security")
	_target("ClearancePlatform", Vector3(-9.0, 1.5, 7.28), 0, "PLATFORM\nREADY", "platform")
	var board := MeshInstance3D.new()
	board.name = "ServiceBoard"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.6, 1.55, 0.08)
	board.mesh = mesh
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.16, 0.22, 0.20)
	board.material_override = paint
	board.position = Vector3(-9.0, 1.9, 7.20)
	add_child(board)
	_label = Label3D.new()
	_label.font = preload("res://ui/fonts/SpecialElite.ttf")
	_label.font_size = 28
	_label.pixel_size = 0.0013
	_label.position = Vector3(-9.0, 2.22, 7.25)
	_label.outline_size = 0
	_label.modulate = Color(0.93, 0.89, 0.74)
	_label.text = "TRAIN DISPATCH / PLATFORM 7"
	add_child(_label)
	GameManager.night_started.connect(_reset)
	_reset(GameManager.night)

func _target(n: String, at: Vector3, yaw: float, text: String, action: String) -> void:
	var body := StaticBody3D.new()
	body.name = n
	body.set_meta("incident_action", action)
	body.collision_layer = 8
	body.collision_mask = 0
	body.position = at
	body.rotation_degrees.y = yaw
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.32, 0.28, 0.07)
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.49, 0.48, 0.36)
	material.roughness = 0.9
	visual.material_override = material
	body.add_child(visual)
	var label := Label3D.new()
	label.font = preload("res://ui/fonts/SpecialElite.ttf")
	label.font_size = 24
	label.pixel_size = 0.0016
	label.text = text
	label.position.z = 0.04
	label.modulate = Color(0.93, 0.89, 0.74)
	label.outline_size = 0
	body.add_child(label)
	preload("res://scripts/interactable.gd").attach(body, resolve.bind(action), func() -> String:
		return "[E] " + text.replace("\n", " ") if started and not completed else "")

func _reset(_night: int) -> void:
	started = false
	completed = false
	stage = "WAITING"
	warning_left = 0
	target_uid = ""
	checkpoints.clear()
	_tick = 0
	_apply_visuals()

func _process(delta: float) -> void:
	if Coop.simulation_blocked() or GameManager.loading or not GameManager.signed_in: return
	if GameManager.state not in [GameManager.NightState.WORKING, GameManager.NightState.BLACKOUT]: return
	_tick += delta
	if _tick < 0.25: return
	var elapsed := _tick
	_tick = 0
	advance(elapsed)

func advance(delta: float) -> void:
	if Coop.is_client() or GameManager.loading or not GameManager.signed_in: return
	if GameManager.state not in [GameManager.NightState.WORKING, GameManager.NightState.BLACKOUT]: return
	if not started:
		if _station.get_node("PassengerService").reviewed < THRESHOLDS[clampi(GameManager.night - 1, 0, 6)]: return
		var conversations := get_tree().get_first_node_in_group("passenger_dialogue_events")
		if conversations and not conversations.yield_to_incident(): return
		begin_incident()
	if completed: return
	var jobs := _station.get_node("StationJobs")
	match GameManager.night:
		4:
			if stage == "WARNING":
				warning_left = maxf(0, warning_left - delta)
				if warning_left <= 0:
					stage = "OUTAGE"
					GameManager.cause_power_failure()
					_update_duty()
			elif stage == "OUTAGE" and GameManager.powered: _complete()
		5:
			if stage == "ESCORT":
				var actor := _actor(target_uid)
				if actor and actor.phase == "SAFE": _complete()
				elif not actor:
					stage = "RECONCILE"
					_update_duty()
		6:
			if stage == "LIGHT" and GameManager.objectives.get("fix_light", {}).get("done", false):
				stage = "GATE"
				jobs.trigger_fault("gate")
				_update_duty()
			elif stage == "GATE" and GameManager.objectives.get("fix_gate", {}).get("done", false): _complete()

func begin_incident() -> void:
	if started or Coop.is_client() or not GameManager.signed_in: return
	started = true
	stage = ["SEAL", "SIGNAL", "TIMETABLE", "WARNING", "ROSTER", "LIGHT", "CLEARANCE"][GameManager.night - 1]
	warning_left = 18 if GameManager.night == 4 else 0
	if GameManager.night == 6: _station.get_node("StationJobs").trigger_fault("light")
	_apply_visuals()
	_update_duty()
	var announcements := [
		"STAFF: Check the entrance exit seal. Keep the emergency route clear.",
		"SECURITY: Camera 04 line fault. Reset its junction in Security; other feeds remain live.",
		"UNSCHEDULED VOICE: Last train cancelled. Clear the platform.\nStaff: this call is not on the service sheet. Check TRAIN DISPATCH on the outside wall of the ticket booth.",
		"ELECTRICAL: Overload detected. Power will trip in 18 seconds. Collect a battery and prepare at Electrical.",
		"STAFF: A passenger count is unconfirmed. Use ROLL CALL on the booth rear workbench.",
		"MAINTENANCE: The hall lighting circuit has failed. Repair it at Electrical panel 2; then test the gate reader.",
		"FINAL SERVICE: Train held for crew clearance. Complete the Booth and Security checks, then confirm PLATFORM READY at TRAIN DISPATCH outside the ticket booth."
	]
	GameManager.notice_posted.emit(announcements[GameManager.night - 1])

func hint() -> String:
	match GameManager.night:
		1: return "SAFETY: Check the EXIT SEAL beside the entrance stairs. [J] Details"
		2: return "CAM 04: Reset LINE RESET in Security. Other cameras remain live."
		3: return "FALSE CALL: TRAIN DISPATCH outside ticket booth → KEEP TRAIN RUNNING. The train is still scheduled."
		4: return "OVERLOAD: Prepare a battery; then restore power at Electrical." if stage == "WARNING" else "POWER: Reconnect the three wires and use the main switch."
		5: return "ROLL CALL: Booth rear workbench → reconcile passenger count." if stage in ["ROSTER", "RECONCILE"] else "ASSIST: Escort the marked passenger to Security or the booth."
		6: return "CIRCUIT: Repair hall lighting at Electrical panel 2." if stage == "LIGHT" else "READER: Repair the jammed central gate."
		7: return "FINAL CLEARANCE: Booth, Security, then PLATFORM READY at dispatch outside ticket booth · %d/3 signed" % checkpoints.size()
	return ""

func _update_duty() -> void:
	_apply_visuals()
	GameManager.objectives["night_incident"] = {"text": TITLES[GameManager.night - 1] + ": " + hint(), "done": completed}
	GameManager.objectives_changed.emit()

func resolve(action: String) -> void:
	if Coop.is_client() or not started or completed or not GameManager.powered: return
	if GameManager.state != GameManager.NightState.WORKING: return
	match GameManager.night:
		1:
			if action == "exit": _complete()
		2:
			if action == "camera": _complete()
		3:
			if action == "keep": _complete()
			elif action == "cancel": GameManager.notice_posted.emit("Official indicator: North Terminal service remains scheduled. The unverified voice is false. Use KEEP TRAIN RUNNING at dispatch outside the ticket booth.")
		5:
			if action != "roster" or stage == "ESCORT": return
			if stage == "RECONCILE":
				GameManager.notice_posted.emit("Passenger absence entered in the log. Any passenger loss still counts against the shift.")
				_complete()
				return
			for actor in get_tree().get_nodes_in_group("passenger_actor"):
				# Never remove an uninspected passenger from the ticket queue.
				if actor.phase == "SEATED" and not actor._pre_ticket_seated and not actor.profile.get("anomaly", false):
					target_uid = actor.profile.uid
					actor.put_in_danger()
					actor.danger_timer = 90
					stage = "ESCORT"
					_update_duty()
					return
			if _station.get_node("TrainService").boarded_count > 0: _complete()
			else: GameManager.notice_posted.emit("No cleared waiting passenger yet. Continue inspections, then repeat roll call.")
		7:
			if action not in ["booth", "security", "platform"] or checkpoints.has(action): return
			var service := _station.get_node("PassengerService")
			if action == "booth" and service.reviewed < service.total_cases():
				GameManager.notice_posted.emit("Booth clearance waits until all passenger documents are checked.")
				return
			if action == "security" and not GameManager.entity_identified:
				GameManager.notice_posted.emit("Security clearance requires the three reports and confirmed intruder identity.")
				return
			if action == "platform" and _station.get_node("TrainService").boarded_count <= 0:
				GameManager.notice_posted.emit("No passengers have boarded yet. Confirm PLATFORM READY after a genuine passenger boards.")
				return
			checkpoints.append(action)
			_update_duty()
			if checkpoints.size() == 3: _complete()

func _complete() -> void:
	if completed: return
	completed = true
	stage = "COMPLETE"
	_apply_visuals()
	GameManager.complete_objective("night_incident")
	GameManager.reward_once("night_incident/%d" % GameManager.night, 4)
	GameManager.notice_posted.emit("%s complete. Continue the shift." % TITLES[GameManager.night - 1])

func _actor(uid: String) -> Node3D:
	for actor in get_tree().get_nodes_in_group("passenger_actor"):
		if str(actor.profile.uid) == uid: return actor
	return null

func holds_departure() -> bool:
	return GameManager.night == 7 and started and not completed

func _apply_visuals() -> void:
	var actions: Array = [["exit"], ["camera"], ["keep", "cancel"], [], ["roster"], [], ["booth", "security", "platform"]][clampi(GameManager.night-1, 0, 6)]
	for body in get_children():
		if not body.has_meta("incident_action"): continue
		var action: String = body.get_meta("incident_action")
		var relevant: bool = action in actions
		var active: bool = relevant and started and not completed and not checkpoints.has(action)
		if action == "roster" and stage == "ESCORT": active = false
		if action in ["keep", "cancel", "platform"]:
			body.visible = relevant
			body.collision_layer = 8 if relevant else 0
		body.get_node("Interaction").enabled = active
		for visual in body.get_children():
			if visual is MeshInstance3D:
				visual.material_override.albedo_color = Color(0.50,0.44,0.27) if active else (Color(0.22,0.36,0.28) if relevant and completed else Color(0.28,0.31,0.28))
	if is_instance_valid(_label):
		var status := "Train status and departure checks\nNo dispatch action needed tonight."
		if GameManager.night == 3:
			status = "NORTH TERMINAL: SCHEDULED\nIf a voice says cancelled, check here.\nKeep the scheduled train running."
		elif GameManager.night == 7:
			status = "FINAL TRAIN: DEPARTURE CHECK\nConfirm passengers have boarded.\nThen press PLATFORM READY."
		if completed and GameManager.night in [3, 7]:
			status = "DISPATCH CHECK COMPLETE\nContinue your remaining duties."
		_label.text = "TRAIN DISPATCH / PLATFORM 7\n\n" + status
	var jobs := _station.get_node_or_null("StationJobs") if _station else null
	if jobs and jobs._camera_screens.size() > 3:
		jobs._camera_screens[3]["signal_lost"] = GameManager.night == 2 and started and not completed

func save_state() -> Dictionary:
	return {"version": 1, "night": GameManager.night, "started": started, "completed": completed, "stage": stage, "warning": warning_left, "target": target_uid, "checkpoints": checkpoints.duplicate()}

func load_state(data: Dictionary) -> void:
	if int(data.get("version",1)) != 1: return
	started = bool(data.get("started", false))
	completed = bool(data.get("completed", false))
	stage = str(data.get("stage", "WAITING"))
	warning_left = maxf(0, float(data.get("warning", 0)))
	target_uid = str(data.get("target", ""))
	checkpoints.clear()
	for point in data.get("checkpoints", []):
		if point in ["booth", "security", "platform"] and not checkpoints.has(point): checkpoints.append(point)
	_apply_visuals()
