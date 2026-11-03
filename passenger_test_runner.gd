extends SceneTree

const Cases = preload("res://passenger_cases.gd")
const Interaction = preload("res://interactable.gd")
var failures: int = 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, text: String) -> void:
	if value:
		print("PASS: ", text)
	else:
		failures += 1
		push_error(text)

func wait_for(predicate: Callable, frames: int = 2400) -> bool:
	for i in range(frames):
		if predicate.call():
			return true
		await physics_frame
	return false

func run() -> void:
	var manager := root.get_node("GameManager")
	manager.set_process(false)
	manager.start_night()
	var station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	var service = station.get_node("PassengerService")
	# Keep this existing inspection/boarding fixture deterministic.
	service.passengers_per_round = 3
	service.pre_ticket_routines_enabled = false
	service.round_limit = 1
	var player = station.get_node("Player")
	check(not service.started and service.actors.is_empty(), "Inspection fixture starts before deferred population setup")
	manager.restore_power()
	manager.sign_in()
	check(service.actors.size() == 3, "Inspection fixture creates its configured three-person queue")
	if not await wait_for(func() -> bool: return service.counter_ready):
		push_error("First passenger never reached booth")
		for actor in service.actors:
			print(actor.phase, " at ", actor.position)
		quit(1)
		return
	var first: Node = service.current_actor
	check(Cases.errors(first.profile).is_empty(), "First case has internally valid documents")
	player.position = Vector3(-8.9, 0.36, 3.25)
	await create_timer(0.9).timeout
	player.camera.look_at(station.get_node("BoothDesk").documents.ticket.body.global_position)
	await physics_frame
	check(player._get_interaction_target() == Interaction.resolve(station.get_node("BoothDesk").documents.ticket.body), "Clerk can reach the desk inspection interaction")
	service.open_desk()
	check(service.ui.is_open and player.in_booth_inspection, "Desk inspection keeps the clerk seated in the world")
	check(station.get_node("BoothDesk").documents.size() == 2 and not service.ui.visible, "Desk presents physical ticket and passport without the fullscreen view")
	var old_position: Vector3 = player.position
	Input.action_press("move_forward")
	for i in range(8):
		await physics_frame
	OS.delay_msec(80)
	Input.action_release("move_forward")
	check(player.position.distance_to(old_position) < 0.05, "Player cannot walk away while inspecting")
	var menu = station.get_node("PauseMenu")
	menu.set_paused(true)
	menu.set_paused(false)
	check(player.in_booth_inspection and service.ui.is_open, "Pause/resume preserves the active desk inspection")
	service.ui._approve.pressed.emit()
	check(service.reviewed == 1 and service.correct == 1, "Approval records a correct decision")
	check(first.ticket.is_valid and not first.ticket.used, "Approval authorizes a ticket before the passenger reaches the gate")
	var duplicate: Dictionary = service.decide(true)
	check(duplicate.is_empty() and service.reviewed == 1, "A passenger cannot be approved twice")
	if not await wait_for(func() -> bool: return service.counter_ready):
		quit(1)
		return
	check(not station.get_node("BoothDesk").shown_uid.is_empty(), "Next passenger slides their own documents onto the desk")
	service.ui._next.pressed.emit()
	check(not service.ui.decision_locked and service.ui._name.text == "Eli Ward", "Next passenger presents their own documents")
	check(not Cases.errors(service.current_actor.profile).is_empty(), "Name discrepancy is detectable from the documents")
	var rejected: Node = service.current_actor
	service.ui._deny.pressed.emit()
	check(service.reviewed == 2 and service.correct == 2 and rejected.phase == "LEAVING", "Denied passenger returns toward the entrance")
	if not await wait_for(func() -> bool: return service.counter_ready):
		quit(1)
		return
	service.ui._next.pressed.emit()
	check(service.current_actor.profile.date != Cases.SERVICE_DATE, "Third case presents an expired service date")
	service.ui._deny.pressed.emit()
	check(service.reviewed == 3 and service.correct == 3 and manager.objectives["check_tickets"]["done"], "All three inspections complete the objective and score")
	if not await wait_for(func() -> bool: return first.phase == "SEATED"):
		push_error("Approved passenger stuck: " + first.phase + " " + str(first.position))
		quit(1)
		return
	check(first.ticket.used and first.seat_anchor.get_meta("occupied", false), "Approved passenger scans once, passes gate and sits at a reserved seat")
	check(station.get_node("GateLane_0").state == Gate.State.CLOSED, "Gate closes behind the admitted passenger")
	service.ui.close_desk()
	check(not player.in_booth_inspection, "Leaving the desk restores first-person control")
	manager.start_night()
	check(service.actors.is_empty() and service.reviewed == 0, "Restart clears actors, decisions and seat reservations")
	manager.restore_power()
	manager.sign_in()
	await wait_for(func() -> bool: return service.counter_ready)
	var wrong_denial: Dictionary = service.decide(false)
	check(not wrong_denial.correct and service.correct == 0, "Denying valid documents is recorded as a mistake")
	await wait_for(func() -> bool: return service.counter_ready)
	var wrong_actor: Node = service.current_actor
	var wrong_approval: Dictionary = service.decide(true)
	check(not wrong_approval.correct and wrong_actor.ticket.is_valid, "Gate follows the clerk's stamp even when the approval was mistaken")
	await wait_for(func() -> bool: return service.counter_ready)
	manager.cause_power_failure()
	check(service.decide(true).is_empty(), "Power loss prevents gate approval without consuming a case")
	manager.restore_power()
	service.open_desk()
	manager.advance_clock(100000.0)
	check(not service.ui.is_open and station.get_node("ShiftReport").is_open, "Shift ending safely closes inspection and opens the report")
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false):
		audio.stop()
	station.queue_free()
	for i in range(8):
		await physics_frame
	# Drain audio mixer stop/free commands before the fast headless runner exits.
	OS.delay_msec(100)
	await process_frame
	print("PASSENGER CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
