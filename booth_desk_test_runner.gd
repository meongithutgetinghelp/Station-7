extends SceneTree
var failures := 0
func _init() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error(text)
func run() -> void:
	var gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(1)
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	station.get_node("NightEvents").set_process(false)
	station.get_node("PassengerDialogueEvents").set_process(false)
	station.get_node("PassengerEntity").set_physics_process(false)
	station.get_node("TrainService").set_process(false)
	var director = station.get_node("PassengerService")
	director.set_process(false)
	director.pre_ticket_routines_enabled = false
	gm.turn_on_power()
	gm.sign_in()
	for person in director.actors: person.set_physics_process(false)
	var actor = director.actors[0]
	actor.position = Vector3(-5.85, 0.35, 4)
	actor.phase = "COUNTER"
	director._on_counter_ready(actor)
	var desk = station.get_node("BoothDesk")
	check(desk.documents.size() == 2 and desk.sliding, "Passenger presents a physical ticket and passport with a slide-in animation")
	check(desk.documents.ticket.body.position.x > -7, "Documents start on the passenger side of the slot")
	await create_timer(0.9).timeout
	check(desk.documents.ticket.viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS and desk.documents.passport.viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "Static papers do not redraw their textures every frame")
	check(not desk.sliding and desk.documents.ticket.body.position.x < -7.5, "Both documents finish sliding onto the clerk's desk")
	var player = station.get_node("Player")
	player.position = Vector3(-9.3, 0.35, 3.2)
	var origin: Vector3 = player.position
	director.open_desk()
	check(director.ui.is_open and not director.ui.visible and player.in_booth_inspection, "Inspection stays in the 3D booth without the fullscreen picture")
	check(player._physical_desk_active() and player.get_meta("seated_workstation", false), "Desk inspection keeps the mouse captured and the clerk seated")
	var position_before: Vector3 = player.position
	Input.action_press("move_forward")
	for i in range(4): await physics_frame
	Input.action_release("move_forward")
	check(player.position.distance_to(position_before) < 0.01, "Clerk cannot walk through the desk while seated")
	var yaw: float = player.rotation.y
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(40, 0)
	player._unhandled_input(mouse)
	check(player._physical_desk_active() if DisplayServer.get_name() == "headless" else not is_equal_approx(yaw, player.rotation.y), "Mouse look remains free for turning between papers and computer")
	var monitor = desk.get_node("BoothComputerScreen")
	var facing: Vector3 = (player.camera.global_position - monitor.global_position).normalized()
	check(monitor.global_basis.z.dot(facing) > 0.85, "Computer screen is angled toward the seated player")
	player.camera.look_at(desk.get_node("BoothComputerScreen").global_position)
	desk._process(1.0)
	check(desk._feed.render_target_update_mode == SubViewport.UPDATE_ONCE, "Visible booth camera schedules a live frame")
	desk._process(0.001)
	check(desk._feed.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Booth live camera respects its refresh-rate budget")
	player.camera.look_at(player.camera.global_position + Vector3.LEFT)
	desk._process(1.0)
	check(desk._feed.render_target_update_mode == SubViewport.UPDATE_DISABLED and desk._screen.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Looking away stops hidden booth monitor renders")
	desk.pick_up("passport")
	check(desk.held_kind == "passport" and desk.held.get_parent() == player.camera, "Passport can be lifted into the player's hands")
	check(not desk.documents.passport.visual.visible and desk.held.layers == 4, "Held copy replaces the desk copy locally and stays out of CCTV")
	desk.pick_up("ticket")
	check(desk.held_kind == "ticket" and desk.documents.passport.visual.visible, "Switching papers puts the previous passport back")
	desk.verify_record()
	check(desk._record.text.contains("IDENTITY CONFIRMED"), "Physical computer verifies the current passport and ticket ownership")
	var menu = station.get_node("PauseMenu")
	menu.set_paused(true)
	menu.set_paused(false)
	check(player._physical_desk_active() if DisplayServer.get_name() == "headless" else Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Resuming the game restores head movement at the physical desk")
	var verdict_target = station.get_node("BoothStampApprove/Interaction")
	check(root.get_node("Coop").local_interaction(verdict_target), "Desk stamps use local presentation before authoritative ticket requests")
	verdict_target.interact()
	check(desk.stamping and director.reviewed == 0, "Stamp travels to the paper before a verdict is submitted")
	await create_timer(0.45).timeout
	check(desk.documents.ticket.viewport.has_node("VerdictStamp"), "Stamp impact leaves a visible verdict on the ticket")
	await create_timer(0.35).timeout
	check(director.reviewed == 1 and director.correct == 1 and desk.sliding and desk.held_kind.is_empty(), "Approve uses existing ticket rules and starts the return slide")
	check(actor.document_handover_left > 0, "Passenger waits for their returned paperwork before walking away")
	await create_timer(0.9).timeout
	check(desk.documents.is_empty(), "Returned paperwork clears after its animation")
	var second = director.actors[1]
	second.phase = "COUNTER"
	second.position = Vector3(-5.85, 0.35, 4)
	director._on_counter_ready(second)
	await create_timer(0.9).timeout
	gm.cause_power_failure()
	desk.stamp_ticket(true)
	check(not desk.stamping and director.reviewed == 1, "Approval stamp cannot bypass an offline gate reader")
	desk.stamp_ticket(false)
	desk.stamp_ticket(false)
	await create_timer(0.45).timeout
	check(director.reviewed == 2 and director.correct == 2 and desk.documents.ticket.viewport.get_node("VerdictStamp").get_child(0).text == "DENIED", "Denial stamp works without power and repeated presses cannot duplicate the decision")
	await create_timer(1.2).timeout
	director.ui.close_desk()
	check(not player.in_booth_inspection and not player.get_meta("seated_workstation", false) and player.position.distance_to(origin) < 0.01, "Leaving desk restores standing controls and original position")
	station.queue_free()
	for i in range(8): await process_frame
	# Let the audio mixer release stopped playback buffers before fast headless exit.
	OS.delay_msec(120)
	print("PHYSICAL BOOTH CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
