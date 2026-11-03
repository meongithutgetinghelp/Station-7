extends SceneTree
var failures := 0
var gm: Node
var station: Node
var service: Node
var desk: Node
var player: Node
func _init() -> void: call_deferred("run")
func check(ok: bool, text: String) -> void:
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error(text)
func settle(seconds: float = 0.9) -> void:
	await create_timer(seconds).timeout
func run() -> void:
	gm = root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(1)
	gm.save_path = "user://qa-booth-interruption.json"
	station = load("res://station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	station.get_node("NightEvents").set_process(false)
	station.get_node("PassengerDialogueEvents").set_process(false)
	station.get_node("PassengerEntity").set_physics_process(false)
	station.get_node("TrainService").set_process(false)
	service = station.get_node("PassengerService")
	service.set_process(false)
	service.pre_ticket_routines_enabled = false
	gm.turn_on_power()
	gm.sign_in()
	for actor in service.actors: actor.set_physics_process(false)
	var first = service.actors[0]
	first.phase = "COUNTER"
	first.position = Vector3(-5.85,0.35,4)
	service._on_counter_ready(first)
	desk = station.get_node("BoothDesk")
	player = station.get_node("Player")
	player.set_physics_process(false)
	player.position = Vector3(-8.9,0.35,4)
	await settle()
	check(not service.ui.is_open, "Standing staff can approach the physical stamps without opening a modal")
	check(gm.save_game(), "Pre-verdict booth checkpoint saves")
	desk.stamp_ticket(true)
	await settle(0.2)
	check(desk.stamping and service.reviewed == 0, "Stamp is in flight before its authoritative impact")
	check(gm.load_game(), "Checkpoint can be loaded while a standing stamp is in flight")
	for actor in service.actors: actor.set_physics_process(false)
	await settle(0.8)
	check(service.reviewed == 0 and not desk.stamping, "Loading a pre-verdict checkpoint cancels a standing stamp instead of committing after load")
	gm.load_game()
	for actor in service.actors: actor.set_physics_process(false)
	desk.clear_documents()
	await settle()
	player.position = Vector3(-8.9,0.35,4)
	service.open_desk()
	desk.pick_up("passport")
	check(desk.held_kind == "passport", "Passport can be held before an interrupted inspection")
	gm.load_game()
	for actor in service.actors: actor.set_physics_process(false)
	await settle(0.1)
	check(desk.held_kind.is_empty() and not service.ui.is_open and not player.in_booth_inspection, "Load clears held papers and seated input state")
	player.position = Vector3(-8.9,0.35,4)
	service.open_desk()
	desk.stamp_ticket(true)
	await settle(0.2)
	service.ui.close_desk()
	await settle(0.7)
	check(service.reviewed == 0 and not desk.stamping, "Leaving the seat before impact cancels the verdict")
	player.position = Vector3(-8.9,0.35,4)
	service.open_desk()
	for press in range(20): desk.stamp_ticket(true)
	await settle(0.45)
	check(service.reviewed == 1, "Twenty rapid stamp attempts commit exactly one verdict")
	check(gm.save_game(), "Post-impact checkpoint saves during the return animation")
	gm.load_game()
	for actor in service.actors: actor.set_physics_process(false)
	await settle(1.8)
	check(service.reviewed == 1 and desk.held_kind.is_empty() and desk.documents.is_empty(), "Loading after impact does not duplicate the verdict or strand documents")
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for frame in range(12): await process_frame
	OS.delay_msec(100)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gm.save_path))
	print("BOOTH INTERRUPTION CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
