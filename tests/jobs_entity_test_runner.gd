extends SceneTree
const Interaction = preload("res://scripts/interactable.gd")
var failures: int = 0
func _init() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if value: print("PASS: ", message)
	else:
		failures += 1
		push_error(message)
func wait_for(predicate: Callable, limit: int = 4000) -> bool:
	for i in range(limit):
		if predicate.call(): return true
		await physics_frame
	return false
func run() -> void:
	var gm := root.get_node("GameManager")
	gm.set_process(false)
	gm.start_night(4)
	var station = load("res://scenes/station_builder.tscn").instantiate()
	root.add_child(station)
	current_scene = station
	station.get_node("PassengerService").passengers_per_round = 3
	station.get_node("PassengerService").pre_ticket_routines_enabled = false
	station.get_node("PassengerService").round_limit = 1
	for i in range(20): await physics_frame
	var jobs = station.get_node("StationJobs")
	var entity = station.get_node("PassengerEntity")
	var player = station.get_node("Player")
	check(jobs._messes.is_empty() and jobs.cleanliness == 100, "Station starts clean without passengers")
	jobs._spawn_mess(0) # Explicit fixture for the cleaning interaction checks below.
	jobs._update_cleanliness()
	var initial: float = jobs.cleanliness
	jobs._clean("0")
	check(jobs.cleanliness == initial, "Cleaning requires the mop")
	jobs._take("mop")
	jobs._clean("0")
	check(gm.has_item("mop") and jobs.cleanliness > initial, "Mop pickup enables hold-to-clean jobs")
	gm.restore_power()
	gm.sign_in()
	for id in jobs._messes.keys(): jobs._clean(id)
	check(jobs.cleanliness == 100 and gm.objectives["clean_station"]["done"], "Cleaning all messes completes the station job")
	check(jobs._camera_screens.size() == 6, "Security has six live camera feeds")
	jobs.trigger_fault("door")
	var door = station.get_node("ElecDoor_InteractiveDoor")
	check(door.jammed and door.get_node("Interaction").hold_seconds == 2, "Door fault exposes a hold-to-unjam action")
	door.interact()
	check(not door.jammed and gm.objectives["fix_door"]["done"], "Door repair completes its fault objective")
	jobs.trigger_fault("gate")
	station.get_node("GateLane_1").scanner.interact()
	check(not station.get_node("GateLane_1").jammed and gm.objectives["fix_gate"]["done"], "Gate reader fault can be repaired")
	jobs.trigger_fault("light")
	jobs.repair_light()
	check(gm.objectives["fix_light"]["done"], "Lighting fault can be repaired at the service panel")
	gm.cause_power_failure()
	var wires = jobs.wire_panel
	wires.open_panel()
	check(not wires.flip_switch() and not gm.powered, "Main switch cannot bypass disconnected wires")
	check(not wires.connect_wire(0, 1), "Wrong wire terminal is rejected")
	for i in range(3): wires.connect_wire(i, i)
	check(wires.flip_switch() and gm.powered, "Three correct wires unlock the main switch")
	for id in ["camera", "power", "light"]:
		Interaction.resolve(station.get_node("Clue_" + id)).interact()
		jobs.journal.close_panel()
	jobs._identify()
	check(jobs.clues.size() == 3 and gm.entity_identified, "Collected reports enable Security identification")
	player.set_physics_process(false)
	player.position = Vector3(29.8, 0.36, 2.7)
	player.is_crouching = true
	for i in range(3): await physics_frame
	jobs._process(0)
	check(player.get_meta("hiding", false), "Crouching in a closed restroom stall provides hiding")
	player.is_crouching = false
	jobs._process(0)
	check(not player.get_meta("hiding", false), "Standing cancels hiding")
	entity.set_physics_process(false)
	entity.wake()
	entity.hear_noise(entity.position + Vector3(2, 0, 0), 13)
	check(entity.phase == "HUNT", "Entity reacts to a nearby loud noise")
	player.position = Vector3(-20, 0.36, 12.8)
	player.camera.look_at(entity.position + Vector3(0, 1.5, 0))
	player.set_flashlight(true, false)
	entity._path.clear()
	entity._path_timer = 1000
	for i in range(30): entity._physics_process(0.1)
	check(entity.banished and gm.objectives["banish_entity"]["done"], "Identified entity can be banished with sustained flashlight aim")
	var service = station.get_node("PassengerService")
	service.round_limit = 1
	await wait_for(func() -> bool: return service.counter_ready)
	var actor: Node = service.current_actor
	service.decide(true)
	await wait_for(func() -> bool: return actor.phase == "SEATED")
	actor.put_in_danger()
	check(actor.phase == "DANGER" and gm.objectives.has("save_passenger"), "Threatened passenger enters a timed danger state")
	Interaction.resolve(actor).interact()
	check(actor.phase == "FOLLOW", "Rescue interaction makes passenger follow the player")
	player.position = Vector3(-10, 0.36, 4)
	station.get_node("TB_StaffDoor_InteractiveDoor").set_open(true)
	var safe: bool = await wait_for(func() -> bool: return actor.phase == "SAFE")
	check(safe and gm.rescued_passengers == 1, "Passenger can be led through the door into the booth to safety")
	if not safe: print("Rescue stuck at ", actor.position, " path ", actor._points)
	gm.kill_player()
	check(gm.state == gm.NightState.DEAD and paused and station.get_node("ShiftReport").is_open, "Death opens a restart/load screen and pauses gameplay")
	for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
	station.queue_free()
	for i in range(8): await process_frame
	OS.delay_msec(100)
	print("JOBS / ENTITY CHECKS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
